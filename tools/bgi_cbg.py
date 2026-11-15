#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGI/Ethornell `CompressedBG___` (CBG v1) 图像解码与 PNG 导出模块。

本作所有背景/立绘/CG/片尾长卷（`data02000`, `data02020`, `data02100`,
`data02150.arc.bak`, `data02200`, `data02210`, `data02300`, `data02800`, `data02910`）
共 4864 张图片全部为 `ver == 1`（8 / 24 / 32 bpp）。

解码管线：
1. 解析 48 字节 `CompressedBG___` 文件头；
2. 使用 `bgi_key_step` 解密 256 符号变长频率表并校验 `sum_check` 与 `xor_check`；
3. 按最小双节点合并构建霍夫曼树，并生成 12-bit 前缀查找表加速比特流解码；
4. 解码零游程 RLE (`c1_len -> width * height * bpp_bytes`)；
5. 逆向空间差分预测滤波（左/上/均值预测），导出 `L` / `RGB` / `RGBA` PNG。
"""

from __future__ import annotations

from dataclasses import dataclass
import ctypes
from pathlib import Path
import struct
from PIL import Image

from bgi_dsc import bgi_key_step


MAGIC_CBG = b"CompressedBG___\x00"


def _load_cbg_fast_dll():
    """按需加载同目录下的 C 加速库 `bgi_fast.dll`（不存在时返回 None 回退纯 Python）。"""
    dll_path = Path(__file__).resolve().parent / "bgi_fast.dll"
    if not dll_path.is_file():
        return None
    try:
        lib = ctypes.CDLL(str(dll_path))
        lib.bgi_cbg_decode_v1.argtypes = [
            ctypes.c_char_p,
            ctypes.c_uint32,
            ctypes.c_void_p,
            ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
        ]
        lib.bgi_cbg_decode_v1.restype = ctypes.c_int
        return lib
    except OSError:
        return None


_CBG_FAST_DLL = _load_cbg_fast_dll()


@dataclass(frozen=True)
class CbgHeader:
    """CBG 文件头元数据。"""

    width: int
    height: int
    bpp: int
    rle_size: int
    key: int
    enc_freq_size: int
    sum_check: int
    xor_check: int
    version: int


def parse_cbg_header(data: bytes) -> CbgHeader:
    """解析 48 字节 `CompressedBG___` 文件头。"""
    if len(data) < 48 or data[:16] != MAGIC_CBG:
        raise ValueError(f"非法的 CBG 头: {data[:16]!r}")
    w, h, bpp, _z1, _z2, rle_size, key, enc_len, sum_c, xor_c, ver = struct.unpack_from(
        "<HHIIIIIIBBH", data, 16
    )
    return CbgHeader(
        width=w,
        height=h,
        bpp=bpp,
        rle_size=rle_size,
        key=key,
        enc_freq_size=enc_len,
        sum_check=sum_c,
        xor_check=xor_c,
        version=ver,
    )


def _read_varint(buf: bytes | bytearray, pos: int) -> tuple[int, int]:
    """读取 7-bit LEB128 变长无符号整数。"""
    val = 0
    shift = 0
    n = len(buf)
    while pos < n:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return val, pos
        shift += 7
    raise ValueError("CBG varint 读取越界")


def decode_cbg(data: bytes, use_fast_dll: bool = True) -> tuple[CbgHeader, bytes]:
    """
    解码 `CompressedBG___` 图像字节流。

    默认在 `bgi_fast.dll` 可用时调用 C 加速解码；否则自动回退纯 Python 实现 `decode_cbg_py`。
    返回 `(CbgHeader, raw_pixels)`，像素通道顺序为：`8bpp -> L`、`24bpp -> BGR`、`32bpp -> BGRA`。
    """
    hdr = parse_cbg_header(data)
    if use_fast_dll and _CBG_FAST_DLL is not None and hdr.version == 1 and hdr.bpp in (8, 24, 32):
        raw_len = hdr.width * hdr.height * (hdr.bpp // 8)
        out_buf = ctypes.create_string_buffer(max(1, raw_len))
        w = ctypes.c_uint32()
        h = ctypes.c_uint32()
        bpp = ctypes.c_uint32()
        rc = _CBG_FAST_DLL.bgi_cbg_decode_v1(
            data,
            len(data),
            out_buf,
            max(1, raw_len),
            ctypes.byref(w),
            ctypes.byref(h),
            ctypes.byref(bpp),
        )
        if rc != 0:
            raise ValueError(f"CBG C 加速解码失败 (rc={rc})")
        return hdr, out_buf.raw[:raw_len]
    return decode_cbg_py(data)


def decode_cbg_py(data: bytes) -> tuple[CbgHeader, bytes]:
    """
    纯 Python 参考实现：解码 `CompressedBG___` 图像字节流。

    返回 `(CbgHeader, raw_pixels)`，像素通道顺序为：`8bpp -> L`、`24bpp -> BGR`、`32bpp -> BGRA`。
    """
    hdr = parse_cbg_header(data)
    if hdr.version != 1:
        raise NotImplementedError(f"当前仅实现 CBG v1，遇到不支持版本: {hdr.version}")
    if hdr.bpp not in (8, 24, 32):
        raise ValueError(f"不支持的 CBG 色深: {hdr.bpp} bpp")
    if 48 + hdr.enc_freq_size > len(data):
        raise ValueError("CBG 频率表长度超出输入范围")

    # 1. 解密频率表并校验和
    k = hdr.key
    dec_freq = bytearray(hdr.enc_freq_size)
    s_acc = 0
    x_acc = 0
    for i in range(hdr.enc_freq_size):
        k, kb = bgi_key_step(k)
        b = (data[48 + i] - kb) & 0xFF
        dec_freq[i] = b
        s_acc = (s_acc + b) & 0xFF
        x_acc ^= b
    if s_acc != hdr.sum_check or x_acc != hdr.xor_check:
        raise ValueError(
            f"CBG 频率表校验失败: sum({s_acc}!={hdr.sum_check}), xor({x_acc}!={hdr.xor_check})"
        )

    # 2. 解析 256 个符号频率
    freqs = [0] * 256
    pos = 0
    for i in range(256):
        val, pos = _read_varint(dec_freq, pos)
        freqs[i] = val

    total_freq = sum(freqs)
    if total_freq == 0:
        raise ValueError("CBG 频率表全零")

    # 3. 构建 BGI 霍夫曼树（每次合并权重最小的两个有效节点）
    # 节点格式: [weight, valid, left, right]
    nodes: list[list[int]] = [[freqs[i], 1 if freqs[i] > 0 else 0, -1, -1] for i in range(256)]
    root = 0
    while True:
        min1_idx, min1_w = -1, 1 << 62
        min2_idx, min2_w = -1, 1 << 62
        for idx, n in enumerate(nodes):
            if not n[1]:
                continue
            w_n = n[0]
            if w_n < min1_w:
                min2_idx, min2_w = min1_idx, min1_w
                min1_idx, min1_w = idx, w_n
            elif w_n < min2_w:
                min2_idx, min2_w = idx, w_n
        if min2_idx == -1:
            root = min1_idx
            break
        nodes[min1_idx][1] = 0
        nodes[min2_idx][1] = 0
        new_idx = len(nodes)
        nodes.append([min1_w + min2_w, 1, min1_idx, min2_idx])
        if min1_w + min2_w == total_freq:
            root = new_idx
            break

    # 4. 从显式霍夫曼树构建 12-bit 查找表以加速纯 Python 解码
    table_bits = 12
    table_size = 1 << table_bits
    lut_val = [-1] * table_size  # >=0: 叶子符号; <0: -(node_idx + 1) 子树根
    lut_len = [0] * table_size

    def _fill_lut(node_idx: int, prefix: int, depth: int) -> None:
        if node_idx < 256:
            if depth == 0:
                # 单符号退化树（0 bit）：整表指向该符号且消耗 0 bit
                for i in range(table_size):
                    lut_val[i] = node_idx
                    lut_len[i] = 0
                return
            shift = table_bits - depth
            base = prefix << shift
            fill = 1 << shift
            for i in range(base, base + fill):
                lut_val[i] = node_idx
                lut_len[i] = depth
            return
        if depth == table_bits:
            lut_val[prefix] = -(node_idx + 1)
            lut_len[prefix] = table_bits
            return
        left_idx = nodes[node_idx][2]
        right_idx = nodes[node_idx][3]
        _fill_lut(left_idx, prefix << 1, depth + 1)
        _fill_lut(right_idx, (prefix << 1) | 1, depth + 1)

    _fill_lut(root, 0, 0)

    # 5. 解码霍夫曼比特流 -> RLE 缓冲
    bs_pos = 48 + hdr.enc_freq_size
    bs_len = len(data)
    bit_buf = 0
    bits_left = 0
    mask_table = table_size - 1
    rle_len = hdr.rle_size
    rle_buf = bytearray(rle_len)

    for i in range(rle_len):
        while bits_left < table_bits and bs_pos < bs_len:
            bit_buf = (bit_buf << 8) | data[bs_pos]
            bs_pos += 1
            bits_left += 8
        if bits_left >= table_bits:
            idx = (bit_buf >> (bits_left - table_bits)) & mask_table
        else:
            idx = (bit_buf << (table_bits - bits_left)) & mask_table

        val = lut_val[idx]
        if val >= 0:
            need_bits = lut_len[idx]
            if bits_left < need_bits:
                raise ValueError("CBG 霍夫曼比特流提前截断")
            bits_left -= need_bits
            bit_buf &= (1 << bits_left) - 1
            rle_buf[i] = val
        else:
            if bits_left < table_bits:
                raise ValueError("CBG 霍夫曼比特流提前截断")
            cur = (-val) - 1
            bits_left -= table_bits
            bit_buf &= (1 << bits_left) - 1
            while cur >= 256:
                if bits_left == 0:
                    if bs_pos >= bs_len:
                        raise ValueError("CBG 霍夫曼比特流提前截断")
                    bit_buf = data[bs_pos]
                    bs_pos += 1
                    bits_left = 8
                bits_left -= 1
                bit = (bit_buf >> bits_left) & 1
                bit_buf &= (1 << bits_left) - 1
                cur = nodes[cur][2 + bit]
            rle_buf[i] = cur

    # 6. 零游程 RLE 解码
    bpp_bytes = hdr.bpp // 8
    raw_len = hdr.width * hdr.height * bpp_bytes
    raw = bytearray(raw_len)
    src_i = 0
    dst_i = 0
    zero_flag = False
    while src_i < rle_len and dst_i < raw_len:
        cnt, src_i = _read_varint(rle_buf, src_i)
        if dst_i + cnt > raw_len:
            cnt = raw_len - dst_i
        if not zero_flag:
            if src_i + cnt > rle_len:
                raise ValueError(
                    f"CBG RLE 非零拷贝越界: src={src_i}, cnt={cnt}, rle_len={rle_len}"
                )
            raw[dst_i : dst_i + cnt] = rle_buf[src_i : src_i + cnt]
            src_i += cnt
        dst_i += cnt
        zero_flag = not zero_flag

    if dst_i != raw_len:
        raise ValueError(f"CBG RLE 解压像素字节数不匹配: {dst_i} != {raw_len}")

    # 7. 逆向空间差分预测滤波
    stride = hdr.width * bpp_bytes
    h = hdr.height
    if h > 0 and stride > 0:
        for x in range(bpp_bytes, stride):
            raw[x] = (raw[x] + raw[x - bpp_bytes]) & 0xFF
        for y in range(1, h):
            row_off = y * stride
            prev_off = row_off - stride
            for c in range(bpp_bytes):
                raw[row_off + c] = (raw[row_off + c] + raw[prev_off + c]) & 0xFF
            for x in range(bpp_bytes, stride):
                avg = (raw[row_off + x - bpp_bytes] + raw[prev_off + x]) >> 1
                raw[row_off + x] = (raw[row_off + x] + avg) & 0xFF

    return hdr, bytes(raw)


def cbg_to_pil(hdr: CbgHeader, raw: bytes) -> Image.Image:
    """将解码后的 CBG 像素缓冲转换为 PIL Image。"""
    if hdr.bpp == 8:
        return Image.frombytes("L", (hdr.width, hdr.height), raw)
    if hdr.bpp == 24:
        return Image.frombytes("RGB", (hdr.width, hdr.height), raw, "raw", "BGR")
    if hdr.bpp == 32:
        return Image.frombytes("RGBA", (hdr.width, hdr.height), raw, "raw", "BGRA")
    raise ValueError(f"不支持的 CBG 色深: {hdr.bpp}")


def export_cbg_png(cbg_bytes: bytes, out_path: Path | str) -> CbgHeader:
    """解码 CBG 并导出为 PNG 文件。"""
    hdr, raw = decode_cbg(cbg_bytes)
    img = cbg_to_pil(hdr, raw)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return hdr
