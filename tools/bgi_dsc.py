#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGI/Ethornell `DSC FORMAT 1.00` 解压与图像位图导出模块。

核心算法要点：
1. 32 字节头：`DSC FORMAT 1.00\\x00` (16B) + `key` (u32) + `out_len` (u32) + `dec_count` (u32) + `unk` (u32)。
2. 线性同余密钥流 `bgi_key_step`：
   v0 = 20021 * (key & 0xFFFF)
   v1 = 20021 * (key >> 16) + 346 * (key & 0xFFFF) + (v0 >> 16)
   next_key = (((v1 & 0xFFFF) << 16) + (v0 & 0xFFFF) + 1) & 0xFFFFFFFF
   注意：返回字节为 `v1 & 0xFF`（即 `+1` 产生 16 位向高 16 位进位之前的 `v1` 低 8 位），
   已在 `Archive/data01350.arc::roll_hi` 与全部 4864 张 CBG 校验和中验证。
3. 512 符号（0..255 字面字节，256..511 LZSS 长度 `(sym-256)+2` + 12bit 距离 `dist+2`）规范霍夫曼树。
4. 通过 12-bit 查找表 + 有界 bit_buf 加速纯 Python 解压。
"""

from __future__ import annotations

from dataclasses import dataclass
import io
from pathlib import Path
import struct
from PIL import Image


MAGIC_DSC = b"DSC FORMAT 1.00\x00"


def bgi_key_step(key: int) -> tuple[int, int]:
    """执行一步 BGI 伪随机密钥步进，返回 `(next_key, key_byte)`。"""
    v0 = 20021 * (key & 0xFFFF)
    v1 = 20021 * (key >> 16) + 346 * (key & 0xFFFF) + (v0 >> 16)
    next_key = (((v1 & 0xFFFF) << 16) + (v0 & 0xFFFF) + 1) & 0xFFFFFFFF
    return next_key, v1 & 0xFF


@dataclass(frozen=True)
class DscHeader:
    """DSC 压缩头元数据。"""

    key: int
    uncompressed_size: int
    dec_count: int
    unknown: int


@dataclass(frozen=True)
class BmpInfo:
    """DSC 内嵌 BMP 图像头信息。"""

    width: int
    height: int
    bpp: int
    compression: int
    data_offset: int


def parse_dsc_header(data: bytes) -> DscHeader:
    """解析 32 字节 DSC 文件头。"""
    if len(data) < 544 or data[:16] != MAGIC_DSC:
        raise ValueError(f"非法的 DSC 头: {data[:16]!r}")
    key, out_len, dec_count, unk = struct.unpack_from("<IIII", data, 16)
    return DscHeader(key=key, uncompressed_size=out_len, dec_count=dec_count, unknown=unk)


def decode_dsc(data: bytes) -> bytes:
    """解压 `DSC FORMAT 1.00` 数据块，返回精确长度的原始字节流。"""
    hdr = parse_dsc_header(data)
    if hdr.uncompressed_size == 0 or hdr.dec_count == 0:
        return b""
    if hdr.dec_count > hdr.uncompressed_size:
        raise ValueError(
            f"DSC 头参数非法: dec_count({hdr.dec_count}) > uncompressed_size({hdr.uncompressed_size})"
        )

    k = hdr.key
    nodes: list[tuple[int, int]] = []
    for sym in range(512):
        k, kbyte = bgi_key_step(k)
        depth = (data[32 + sym] - kbyte) & 0xFF
        if depth:
            nodes.append((depth, sym))
    nodes.sort()
    if not nodes:
        raise ValueError("DSC 霍夫曼码长表为空")

    max_depth = nodes[-1][0]
    table_bits = min(12, max_depth)
    table_size = 1 << table_bits
    lut_sym = [-1] * table_size
    lut_len = [0] * table_size
    root: list[object] = [None, None]

    code = 0
    prev_d = 0
    for d, sym in nodes:
        code <<= d - prev_d
        prev_d = d
        if code >= (1 << d):
            raise ValueError(f"DSC 霍夫曼树不满足 Kraft 不等式: depth={d}, code={code}")
        if d <= table_bits:
            shift = table_bits - d
            base = code << shift
            fill = 1 << shift
            for i in range(base, base + fill):
                lut_sym[i] = sym
                lut_len[i] = d
        else:
            cur = root
            for bpos in range(d - 1, -1, -1):
                bit = (code >> bpos) & 1
                if bpos == 0:
                    cur[bit] = sym
                else:
                    if cur[bit] is None:
                        cur[bit] = [None, None]
                    cur = cur[bit]  # type: ignore[assignment]
        code += 1

    out = bytearray()
    pos = 544
    total_len = len(data)
    bit_buf = 0
    bits_left = 0
    mask_table = table_size - 1

    for _ in range(hdr.dec_count):
        while bits_left < table_bits and pos < total_len:
            bit_buf = (bit_buf << 8) | data[pos]
            pos += 1
            bits_left += 8
        if bits_left >= table_bits:
            idx = (bit_buf >> (bits_left - table_bits)) & mask_table
        else:
            idx = (bit_buf << (table_bits - bits_left)) & mask_table

        sym = lut_sym[idx]
        if sym >= 0:
            bits_left -= lut_len[idx]
            bit_buf &= (1 << bits_left) - 1
        else:
            cur_node: object = root
            while isinstance(cur_node, list):
                if bits_left == 0:
                    bit_buf = (bit_buf << 8) | (data[pos] if pos < total_len else 0)
                    pos += 1
                    bits_left += 8
                bits_left -= 1
                cur_node = cur_node[(bit_buf >> bits_left) & 1]
                bit_buf &= (1 << bits_left) - 1
            if not isinstance(cur_node, int):
                raise ValueError("DSC 霍夫曼树解码落入空分支")
            sym = cur_node

        if sym < 256:
            out.append(sym)
        else:
            length = (sym & 0xFF) + 2
            while bits_left < 12:
                bit_buf = (bit_buf << 8) | (data[pos] if pos < total_len else 0)
                pos += 1
                bits_left += 8
            bits_left -= 12
            dist = ((bit_buf >> bits_left) & 0xFFF) + 2
            bit_buf &= (1 << bits_left) - 1
            start = len(out) - dist
            if start < 0:
                raise ValueError(f"DSC LZSS 回溯越界: out_len={len(out)}, dist={dist}")
            if dist >= length:
                out.extend(out[start : start + length])
            else:
                for j in range(length):
                    out.append(out[start + j])

    if len(out) != hdr.uncompressed_size:
        raise ValueError(f"DSC 解压长度不匹配: 期望 {hdr.uncompressed_size}, 实际 {len(out)}")
    return bytes(out)


def inspect_dsc_image_header(decoded: bytes) -> BmpInfo:
    """
    检查 DSC 解压后的图像头结构。

    本作 `sysgrp.arc`、`data02400~02810.arc` 全部为标准未压缩 Windows BMP (`BM`)，
    此处亦保留 16 字节 BGI 裸位图头识别分支以防特殊资源。
    """
    if decoded.startswith(b"BM") and len(decoded) >= 54:
        bf_off = struct.unpack_from("<I", decoded, 10)[0]
        _, w, h, _, bpp, comp = struct.unpack_from("<IiiHHI", decoded, 14)
        return BmpInfo(width=w, height=abs(h), bpp=bpp, compression=comp, data_offset=bf_off)
    if len(decoded) >= 16:
        w, h, bpp = struct.unpack_from("<HHI", decoded, 0)
        if bpp in (8, 24, 32) and 16 + w * h * (bpp // 8) == len(decoded):
            return BmpInfo(width=w, height=h, bpp=bpp, compression=-1, data_offset=16)
    raise ValueError(f"无法识别的 DSC 解压图像头: {decoded[:16].hex(' ')}")


def dsc_image_to_pil(decoded: bytes) -> Image.Image:
    """将 DSC 解压后的 BMP 或裸位图数据转换为 PIL Image。"""
    info = inspect_dsc_image_header(decoded)
    if decoded.startswith(b"BM"):
        if info.bpp == 32 and info.compression == 0:
            # 显式保留 32-bit BGRA 透明通道（Pillow 对某些 32bpp BMP 可能丢 alpha）
            _, w, h_signed, _, bpp, comp = struct.unpack_from("<IiiHHI", decoded, 14)
            px = decoded[info.data_offset : info.data_offset + abs(w) * abs(h_signed) * 4]
            img = Image.frombytes("RGBA", (w, abs(h_signed)), px, "raw", "BGRA")
            return img.transpose(Image.Transpose.FLIP_TOP_BOTTOM) if h_signed > 0 else img
        return Image.open(io.BytesIO(decoded)).convert("RGBA" if info.bpp == 32 else "RGB")

    # 16 字节裸位图回退
    raw = decoded[16:]
    if info.bpp == 8:
        return Image.frombytes("L", (info.width, info.height), raw)
    if info.bpp == 24:
        return Image.frombytes("RGB", (info.width, info.height), raw, "raw", "BGR")
    return Image.frombytes("RGBA", (info.width, info.height), raw, "raw", "BGRA")


def export_dsc_png(dsc_bytes: bytes, out_path: Path | str) -> BmpInfo:
    """解压 DSC 图像并导出为 PNG 文件。"""
    dec = decode_dsc(dsc_bytes)
    info = inspect_dsc_image_header(dec)
    img = dsc_image_to_pil(dec)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return info
