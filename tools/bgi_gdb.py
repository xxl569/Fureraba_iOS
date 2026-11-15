#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGI/Ethornell `BGI.gdb` (`SDC FORMAT 1.00` + `BURIKO GDB 3.00`) 解码与结构解析模块。

协议说明：
1. 外层容器 `SDC FORMAT 1.00\\x00` (32 字节头)：
   - `0x00..0x10` (16B): 魔数 `b"SDC FORMAT 1.00\\x00"`
   - `0x10..0x14` (u32): `key`（`bgi_key_step` 线性同余密钥种子）
   - `0x14..0x18` (u32): `compressed_size`（后续加密+压缩载荷字节数，等于 `len(data) - 32`）
   - `0x18..0x1C` (u32): `uncompressed_size`（解压后 `BURIKO GDB 3.00` 总字节数）
   - `0x1C..0x20` (u32): `reserved` / 引擎保留字段
2. 字节流解密与 LZ77 解压：
   - 对 `data[32 : 32 + compressed_size]` 逐字节执行 `(b - kb) & 0xFF`（密钥步进同 `bgi_key_step`）；
   - 解密后为字节令牌流：
     - `b0 < 0x80`：拷贝后续 `b0 + 1` 个字面字节；
     - `b0 >= 0x80`：2 字节回溯匹配 `(b0, b1)`，长度 `((b0 >> 3) & 0x0F) + 2`，回溯距离 `(((b0 & 0x07) << 8) | b1) + 2`。
3. 内层 `BURIKO GDB 3.00\\x00` 结构：
   - `0x0000..0x0424`：全局头、工程代号（如 `HAROKJSLTE`）、默认主角/字体配置；
   - `0x0424..0x100424`（1 MB 固定槽）：标签/CG/事件记录（每条 40 字节：`<2I32s>`）；
   - `0x100424..`：`u32 res_count` + `res_count` 个 NUL 结尾资源名字符串池；
   - 资源名池之后（对齐到引擎块边界）：`u32 script_count` + `script_count` 个脚本已读位图记录
     （`name\\x00` + `u32 bit_count` + `ceil(bit_count / 8)` 字节位图，通常初始化为 `0xFF`）。
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bgi_dsc import bgi_key_step

MAGIC_SDC = b"SDC FORMAT 1.00\x00"
MAGIC_GDB = b"BURIKO GDB 3.00\x00"


@dataclass(frozen=True)
class SdcHeader:
    """`SDC FORMAT 1.00` 外层容器头。"""

    key: int
    compressed_size: int
    uncompressed_size: int
    reserved: int


@dataclass(frozen=True)
class GdbLabelEntry:
    """`BURIKO GDB 3.00` 固定槽标签/场景记录（40 字节）。"""

    kind: int
    value: int
    name: str


@dataclass(frozen=True)
class GdbScriptReadEntry:
    """`BURIKO GDB 3.00` 脚本已读位图记录。"""

    name: str
    bit_count: int
    bitmap_bytes: int


@dataclass(frozen=True)
class GdbDatabase:
    """解析后的 `BGI.gdb` 完整结构摘要。"""

    magic: str
    total_size: int
    header_count: int
    project_code: str
    labels: list[GdbLabelEntry]
    resources: list[str]
    scripts: list[GdbScriptReadEntry]


def parse_sdc_header(data: bytes) -> SdcHeader:
    """解析 32 字节 `SDC FORMAT 1.00` 头部。"""
    if len(data) < 32 or data[:16] != MAGIC_SDC:
        raise ValueError(f"非法的 SDC 头: {data[:16]!r}")
    key, comp_len, raw_len, reserved = struct.unpack_from("<4I", data, 16)
    return SdcHeader(
        key=key,
        compressed_size=comp_len,
        uncompressed_size=raw_len,
        reserved=reserved,
    )


def decode_sdc(data: bytes) -> tuple[SdcHeader, bytes]:
    """解密并解压 `SDC FORMAT 1.00` 数据块，返回 `(SdcHeader, raw_bytes)`。"""
    hdr = parse_sdc_header(data)
    if 32 + hdr.compressed_size > len(data):
        raise ValueError(
            f"SDC 压缩载荷越界: 需要 {32 + hdr.compressed_size} bytes, 实际 {len(data)} bytes"
        )
    if hdr.uncompressed_size == 0:
        return hdr, b""

    # 1. 线性同余密钥流逐字节解密
    k = hdr.key
    dec = bytearray(hdr.compressed_size)
    for i in range(hdr.compressed_size):
        k, kb = bgi_key_step(k)
        dec[i] = (data[32 + i] - kb) & 0xFF

    # 2. BGI SDC LZ77 解压
    out = bytearray()
    pos = 0
    n = len(dec)
    while pos < n:
        b0 = dec[pos]
        pos += 1
        if b0 < 0x80:
            cnt = b0 + 1
            if pos + cnt > n:
                raise ValueError(f"SDC 字面量拷贝越界 @ pos={pos - 1}, cnt={cnt}")
            out.extend(dec[pos : pos + cnt])
            pos += cnt
        else:
            if pos >= n:
                raise ValueError(f"SDC 回溯令牌截断 @ pos={pos - 1}")
            b1 = dec[pos]
            pos += 1
            length = ((b0 >> 3) & 0x0F) + 2
            dist = (((b0 & 0x07) << 8) | b1) + 2
            start = len(out) - dist
            if start < 0:
                raise ValueError(f"SDC LZ77 回溯越界: out_len={len(out)}, dist={dist}")
            if dist >= length:
                out.extend(out[start : start + length])
            else:
                for j in range(length):
                    out.append(out[start + j])

    if len(out) != hdr.uncompressed_size:
        raise ValueError(
            f"SDC 解压大小不匹配: 期望 {hdr.uncompressed_size}, 实际 {len(out)}"
        )
    return hdr, bytes(out)


def parse_gdb(gdb_bytes: bytes) -> GdbDatabase:
    """解析解压后的 `BURIKO GDB 3.00` 数据库结构。"""
    if len(gdb_bytes) < 0x100428 or gdb_bytes[:16] != MAGIC_GDB:
        raise ValueError(f"非法的 BURIKO GDB 头: {gdb_bytes[:16]!r}")

    total_size, header_count = struct.unpack_from("<II", gdb_bytes, 16)
    if total_size != len(gdb_bytes):
        raise ValueError(f"GDB 内部长度字段不匹配: {total_size} != {len(gdb_bytes)}")

    # 工程代号位于 0x00D0
    proj_end = gdb_bytes.find(0, 0xD0, 0xF0)
    project_code = (
        gdb_bytes[0xD0 : proj_end if proj_end != -1 else 0xF0].decode("ascii", errors="replace")
    )

    # 1. 解析 0x0424..0x100424 固定槽标签记录（遇到全零槽即停止）
    labels: list[GdbLabelEntry] = []
    off = 0x0424
    while off + 40 <= 0x100424:
        kind, val = struct.unpack_from("<II", gdb_bytes, off)
        raw_name = gdb_bytes[off + 8 : off + 40]
        nul = raw_name.find(0)
        if nul <= 0:
            break
        name = raw_name[:nul].decode("cp932", errors="replace")
        labels.append(GdbLabelEntry(kind=kind, value=val, name=name))
        off += 40

    # 2. 解析 0x100424 资源名字符串池
    res_count = struct.unpack_from("<I", gdb_bytes, 0x100424)[0]
    p = 0x100428
    resources: list[str] = []
    for _ in range(res_count):
        nul = gdb_bytes.find(0, p)
        if nul == -1:
            raise ValueError(f"GDB 资源名字符串未以 NUL 结尾 @ {p:#x}")
        resources.append(gdb_bytes[p:nul].decode("cp932", errors="replace"))
        p = nul + 1

    # 3. 紧接资源名池之后为脚本已读位图记录
    if p + 4 > len(gdb_bytes):
        raise ValueError("GDB 缺少脚本已读记录区")

    script_count = struct.unpack_from("<I", gdb_bytes, p)[0]
    p += 4
    scripts: list[GdbScriptReadEntry] = []
    for _ in range(script_count):
        nul = gdb_bytes.find(0, p)
        if nul == -1 or nul + 5 > len(gdb_bytes):
            raise ValueError(f"GDB 脚本记录头越界 @ {p:#x}")
        sname = gdb_bytes[p:nul].decode("cp932", errors="replace")
        bit_count = struct.unpack_from("<I", gdb_bytes, nul + 1)[0]
        bitmap_bytes = (bit_count + 7) // 8
        p = nul + 5 + bitmap_bytes
        if p > len(gdb_bytes):
            raise ValueError(f"GDB 脚本位图越界 ({sname}): {p} > {len(gdb_bytes)}")
        scripts.append(GdbScriptReadEntry(name=sname, bit_count=bit_count, bitmap_bytes=bitmap_bytes))

    if p != len(gdb_bytes):
        raise ValueError(f"GDB 末尾存在未解析字节: {p} != {len(gdb_bytes)}")

    return GdbDatabase(
        magic="BURIKO GDB 3.00",
        total_size=total_size,
        header_count=header_count,
        project_code=project_code,
        labels=labels,
        resources=resources,
        scripts=scripts,
    )


def load_gdb_file(gdb_path: Path | str) -> tuple[SdcHeader, GdbDatabase, bytes]:
    """读取并完整解析 `BGI.gdb` 文件，返回 `(SdcHeader, GdbDatabase, raw_gdb_bytes)`。"""
    raw = Path(gdb_path).read_bytes()
    sdc_hdr, gdb_bytes = decode_sdc(raw)
    db = parse_gdb(gdb_bytes)
    return sdc_hdr, db, gdb_bytes


if __name__ == "__main__":
    default_gdb = Path(r"U:\anti\projects\game\BGI.gdb")
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else default_gdb
    sdc_hdr, db, _ = load_gdb_file(target)
    print(f"SDC: key={sdc_hdr.key:#x}, comp={sdc_hdr.compressed_size}, raw={sdc_hdr.uncompressed_size}, reserved={sdc_hdr.reserved:#x}")
    print(f"GDB: magic={db.magic}, project={db.project_code}, header_count={db.header_count}")
    print(f"  labels={len(db.labels)}, resources={len(db.resources)}, scripts={len(db.scripts)}")
    print(f"  total_script_bits={sum(s.bit_count for s in db.scripts)}")
