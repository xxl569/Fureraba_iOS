#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGI/Ethornell `bw  ` 音频头解析与 Ogg Vorbis 提取校验模块。

`bw  ` 容器结构（64 字节固定头 + 原始 Ogg Vorbis 数据流）：
- `0x00` (u32): `header_size`（固定 64）
- `0x04` (4s) : `magic`（`b"bw  "`）
- `0x08` (u32): `ogg_size`（后续 Ogg 数据字节数，等于 `entry_size - 64`）
- `0x0C` (u32): `total_samples`（总采样帧数）
- `0x10` (u32): `sample_rate`（22050 / 44100 Hz）
- `0x14` (u32): `channels`（1 / 2 声道）
- `0x18` (u32): `loop_flag`（1 表示循环播放，0 表示单次播放）
- `0x1C..0x2C` (5 * u32): 保留/循环偏移字段（本作全部为 0）
- `0x30` (u32): `format_tag`（本作全部为 3 = Ogg Vorbis）
- `0x34..0x3C` (3 * u32): 保留字段（本作全部为 0）
"""

from __future__ import annotations

from dataclasses import dataclass
import ctypes
from pathlib import Path
import struct


MAGIC_BW = b"bw  "


def _load_audio_fast_dll():
    """按需加载同目录下的 C 加速库 `bgi_fast.dll`。"""
    dll_path = Path(__file__).resolve().parent / "bgi_fast.dll"
    if not dll_path.is_file():
        return None
    try:
        lib = ctypes.CDLL(str(dll_path))
        lib.bgi_ogg_validate_stream.argtypes = [
            ctypes.c_char_p,
            ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_int64),
        ]
        lib.bgi_ogg_validate_stream.restype = ctypes.c_int
        return lib
    except OSError:
        return None


_AUDIO_FAST_DLL = _load_audio_fast_dll()


@dataclass(frozen=True)
class BwHeader:
    """64 字节 BGI `bw  ` 音频头信息。"""

    header_size: int
    ogg_size: int
    total_samples: int
    sample_rate: int
    channels: int
    loop_flag: int
    loop_start: int
    loop_end: int
    format_tag: int

    @property
    def duration_sec(self) -> float:
        if self.sample_rate <= 0:
            return 0.0
        return self.total_samples / float(self.sample_rate)


def parse_bw_header(data: bytes) -> BwHeader:
    """解析 BGI `bw  ` 音频容器头（不解码 Ogg 音频帧）。"""
    if len(data) < 64:
        raise ValueError(f"bw 音频数据过短: {len(data)} bytes")
    fields = struct.unpack_from("<16I", data, 0)
    hdr_size = fields[0]
    magic = data[4:8]
    if magic != MAGIC_BW or hdr_size < 64:
        raise ValueError(f"非法的 bw 音频头: hdr_size={hdr_size}, magic={magic!r}")
    return BwHeader(
        header_size=hdr_size,
        ogg_size=fields[2],
        total_samples=fields[3],
        sample_rate=fields[4],
        channels=fields[5],
        loop_flag=fields[6],
        loop_start=fields[7],
        loop_end=fields[8],
        format_tag=fields[12],
    )


def _build_ogg_crc_table() -> list[int]:
    table = [0] * 256
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if (r & 0x80000000) else ((r << 1) & 0xFFFFFFFF)
        table[i] = r
    return table


_OGG_CRC_TABLE = _build_ogg_crc_table()


def _ogg_page_crc32(page: bytes | bytearray | memoryview) -> int:
    crc = 0
    for idx, b in enumerate(page):
        if 22 <= idx < 26:
            b = 0
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _OGG_CRC_TABLE[((crc >> 24) & 0xFF) ^ b]
    return crc


def validate_ogg_stream(ogg_bytes: bytes, check_crc: bool = True) -> dict[str, object]:
    """
    校验提取出的 Ogg Vorbis 流结构完整性：
    - 当 `bgi_fast.dll` 可用且 `check_crc=True` 时，执行全页 Ogg CRC32 + Vorbis 三头包 (`\\x01/\\x03/\\x05`) + EOS 校验；
    - 否则使用纯 Python 执行等价的页结构、Ogg CRC32（若 `check_crc=True`）、Vorbis 三头包及 EOS 校验。
    """
    if check_crc and _AUDIO_FAST_DLL is not None:
        pages = ctypes.c_uint32()
        ch = ctypes.c_uint32()
        sr = ctypes.c_uint32()
        eos = ctypes.c_uint32()
        gran = ctypes.c_int64()
        rc = _AUDIO_FAST_DLL.bgi_ogg_validate_stream(
            ogg_bytes,
            len(ogg_bytes),
            ctypes.byref(pages),
            ctypes.byref(ch),
            ctypes.byref(sr),
            ctypes.byref(eos),
            ctypes.byref(gran),
        )
        if rc != 0:
            raise ValueError(f"Ogg 流 C 校验失败 (rc={rc}, pages={pages.value})")
        return {
            "vorbis_version": 0,
            "ogg_channels": ch.value,
            "ogg_sample_rate": sr.value,
            "page_count": pages.value,
            "has_eos": bool(eos.value),
            "last_granule": gran.value,
            "crc32_verified": True,
        }

    if not ogg_bytes.startswith(b"OggS"):
        raise ValueError(f"非法的 Ogg 起始魔数: {ogg_bytes[:8]!r}")

    page_count = 0
    last_flags = 0
    pos = 0
    n = len(ogg_bytes)
    last_granule = 0
    has_id = False
    has_comment = False
    has_setup = False
    ver = -1
    ch = 0
    rate = 0
    mv = memoryview(ogg_bytes)

    while pos + 27 <= n:
        if ogg_bytes[pos : pos + 4] != b"OggS":
            raise ValueError(f"Ogg 页同步丢失 @ offset {pos}")
        flags = ogg_bytes[pos + 5]
        granule = struct.unpack_from("<q", ogg_bytes, pos + 6)[0]
        expected_crc = struct.unpack_from("<I", ogg_bytes, pos + 22)[0]
        nseg = ogg_bytes[pos + 26]
        if pos + 27 + nseg > n:
            raise ValueError(f"Ogg segment 表越界 @ offset {pos}")
        body_len = sum(ogg_bytes[pos + 27 : pos + 27 + nseg])
        next_pos = pos + 27 + nseg + body_len
        if next_pos > n:
            raise ValueError(f"Ogg 页载荷越界 @ offset {pos}")
        if check_crc and _ogg_page_crc32(mv[pos:next_pos]) != expected_crc:
            raise ValueError(f"Ogg 页 CRC32 校验失败 @ page={page_count}")

        if page_count < 8:
            body = ogg_bytes[pos + 27 + nseg : next_pos]
            if not has_id:
                idx_id = body.find(b"\x01vorbis")
                if idx_id != -1 and idx_id + 16 <= len(body):
                    ver, ch, rate = struct.unpack_from("<IBI", body, idx_id + 7)
                    if ver != 0:
                        raise ValueError(f"不支持的 Vorbis 版本: {ver}")
                    has_id = True
            if b"\x03vorbis" in body:
                has_comment = True
            if b"\x05vorbis" in body:
                has_setup = True

        page_count += 1
        last_flags = flags
        if granule >= 0:
            last_granule = granule
        pos = next_pos

    if pos != n:
        raise ValueError(f"Ogg 流末尾存在未对齐残留字节: {n - pos} bytes")
    if not (last_flags & 0x04):
        raise ValueError("Ogg 流缺少末尾 EOS (0x04) 标志")
    if not (has_id and has_comment and has_setup):
        raise ValueError("Ogg 流缺少完整的 Vorbis 三头包 (\\x01/\\x03/\\x05 vorbis)")

    return {
        "vorbis_version": ver,
        "ogg_channels": ch,
        "ogg_sample_rate": rate,
        "page_count": page_count,
        "has_eos": True,
        "last_granule": last_granule,
        "crc32_verified": bool(check_crc),
    }


def extract_ogg(data: bytes, validate: bool = True) -> tuple[BwHeader, bytes, dict[str, object] | None]:
    """从 `bw  ` 容器中提取裸 `.ogg` 数据并可选校验 Ogg 结构。"""
    hdr = parse_bw_header(data)
    ogg_bytes = data[hdr.header_size : hdr.header_size + hdr.ogg_size]
    if len(ogg_bytes) != hdr.ogg_size:
        raise ValueError(f"Ogg 数据截断: 期望 {hdr.ogg_size}, 实际 {len(ogg_bytes)}")
    info = validate_ogg_stream(ogg_bytes) if validate else None
    return hdr, ogg_bytes, info


def export_bw_ogg(bw_bytes: bytes, out_path: Path | str) -> BwHeader:
    """提取 `bw  ` 音频并写出为 `.ogg` 文件。"""
    hdr, ogg_bytes, _ = extract_ogg(bw_bytes, validate=True)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(ogg_bytes)
    return hdr
