"""
BGI / Ethornell 脚本反汇编与协议分析工具（BCS1 `.bs` / 场景脚本 与 `._bp` 系统模块）。

支持特性：
1. 自动识别并解压外层 `DSC FORMAT 1.00` 压缩壳；
2. 解析 `BurikoCompiledScriptVer1.00` (BCS1) 头部（导入表、导出符号表与代码起始偏移）；
3. 基于操作数长度表完整反汇编 BCS1 字节码并提取字符串表（支持混合 CP932 日文调试路径/系统提示与 GBK 汉化对白）；
4. 解析并反汇编 `._bp` 字节码模块（支持 `0x05` PC 相对字符串引用、`0x06` 跳转目标与 `0x8000+` 双字节大端系统调用）。
"""

from __future__ import annotations

from dataclasses import dataclass
import struct

from bgi_dsc import decode_dsc

DSC_MAGIC = b"DSC FORMAT 1.00\x00"
BCS1_MAGIC_PREFIX = b"BurikoCompiledScriptVer1.00"

# BCS1 指令操作数长度（单位：4 字节 word）
BCS1_OP_ARGS: dict[int, int] = {
    0x00: 1,
    0x01: 1,
    0x02: 1,
    0x03: 1,
    0x08: 1,
    0x09: 1,
    0x0A: 1,
    0x19: 1,
    0x3F: 2,  # (kind/scope, arg) 成对作用域/调试帧标记
    0x7F: 2,  # (src_file_str_rel, line_no) 调试行号
}
for _op in (
    [0x10, 0x11, 0x18]
    + list(range(0x1A, 0x2C))
    + list(range(0x30, 0x3B))
    + list(range(0x80, 0x400))
):
    BCS1_OP_ARGS[_op] = 0

# 已知部分 BCS1 引擎内置 Opcode 语义助记符（基于 BGI/Ethornell 规范与反汇编交叉验证）
BCS1_OP_NAMES: dict[int, str] = {
    0x00: "PUSH_INT",
    0x01: "PUSH_ADDR_REL",
    0x02: "PUSH_OFFSET",
    0x03: "PUSH_STR",
    0x08: "READ_MEM",
    0x09: "WRITE_MEM",
    0x0A: "POP_VAR",
    0x10: "PUSH_SP",
    0x11: "POP_SP",
    0x18: "JMP",
    0x19: "JCC",
    0x1A: "CALL",
    0x1B: "RET",
    0x1C: "CALL_EXTERNAL",
    0x1D: "SET_RETVAL",
    0x1E: "REG_EXCEPTION",
    0x1F: "UNREG_EXCEPTION",
    0x20: "ADD",
    0x21: "SUB",
    0x22: "MUL",
    0x23: "DIV",
    0x24: "MOD",
    0x25: "AND",
    0x26: "OR",
    0x27: "XOR",
    0x28: "SHL",
    0x29: "SHR",
    0x30: "CMP_EQ",
    0x31: "CMP_NE",
    0x32: "CMP_LE",
    0x33: "CMP_GE",
    0x34: "CMP_LT",
    0x35: "CMP_GT",
    0x38: "BOOL_AND",
    0x39: "BOOL_OR",
    0x3A: "BOOL_NOT",
    0x3F: "SCOPE_MARK",
    0x7F: "DEBUG_LINE",
    0x140: "SYS_TEXT_PRINT",
    0x142: "SYS_TEXT_CLEAR_OR_WAIT",
}

# ._bp 指令集中包含立即数的操作码（单位：字节）
BP_IMM_BYTES: dict[int, int] = {
    0x00: 1,
    0x08: 1,
    0x09: 1,
    0x0A: 1,
    0x15: 1,
    0x19: 1,
    0x01: 2,
    0x04: 2,
    0x05: 2,
    0x06: 2,
    0x0C: 2,
    0x02: 4,
}


@dataclass(slots=True)
class Bcs1Header:
    """BCS1 脚本头部元数据。"""

    magic: str
    header_size: int
    code_start: int
    imports: list[str]
    exports: list[tuple[str, int]]


@dataclass(slots=True)
class Bcs1Insn:
    """单条 BCS1 反汇编指令。"""

    offset: int  # 相对于 code_start 的字节偏移
    opcode: int
    args: tuple[int, ...]
    comment: str = ""


@dataclass(slots=True)
class Bcs1Script:
    """完整解析后的 BCS1 脚本对象。"""

    name: str
    header: Bcs1Header
    code_end: int  # 相对于文件起始的字节偏移
    instructions: list[Bcs1Insn]
    strings: dict[int, bytes]  # key 为相对于 code_start 的字符串偏移
    trailing_bytes: int = 0


@dataclass(slots=True)
class BpHeader:
    """`._bp` 字节码模块 16 字节头部。"""

    header_size: int
    payload_size: int
    unknown1: int
    unknown2: int


@dataclass(slots=True)
class BpInsn:
    """单条 `._bp` 反汇编指令。"""

    offset: int  # 相对于 payload 起始的字节偏移
    opcode: int
    arg: int | None
    size: int
    syscall_id: int | None = None
    comment: str = ""


@dataclass(slots=True)
class BpScript:
    """完整解析后的 `._bp` 模块对象。"""

    name: str
    header: BpHeader
    code_end: int  # 相对于 payload 起始的字节偏移
    instructions: list[BpInsn]
    strings: dict[int, bytes]  # key 为相对于 payload 起始的字节偏移


def maybe_decompress_script(data: bytes) -> tuple[bytes, bool]:
    """若脚本外层包裹了 `DSC FORMAT 1.00`，先执行解压。"""
    if data.startswith(DSC_MAGIC):
        return decode_dsc(data), True
    return data, False


def decode_bgi_string(raw_bytes: bytes, prefer_gbk: bool = True) -> tuple[str, str]:
    """
    智能解码 BGI 脚本字符串（处理 CP932 与 GBK 混合编码）。

    说明：在本作已汉化版本中，剧本对白、流程图选项、UI 菜单标签（含部分 `._bp`）
    已汉化为 GBK，而源码路径（`*.BS5`/`*.bsc`）、系统报错、`framework._bs` 参数名
    等仍保持 CP932 (Shift-JIS)。通过 GB2312 核心区判别与假名特征计数避免误判。
    """
    if not raw_bytes:
        return "", "ascii"
    if all(b < 0x80 for b in raw_bytes):
        return raw_bytes.decode("ascii"), "ascii"

    # 明显的日文源码调试路径（*.BS5 / *.bsc）
    if (
        b"BURIKOScriptSystem" in raw_bytes
        or raw_bytes.endswith(b".BS5")
        or raw_bytes.endswith(b".bsc")
    ):
        return raw_bytes.decode("cp932", errors="replace"), "cp932"

    # GB2312 核心区（0xA1..0xF7, 0xA1..0xFE）排除 Shift-JIS 0x81..0x9F 假名/常用汉字区
    try:
        return raw_bytes.decode("gb2312"), "gbk"
    except UnicodeDecodeError:
        pass

    t_gbk: str | None = None
    t_cp932: str | None = None
    try:
        t_gbk = raw_bytes.decode("gbk")
    except UnicodeDecodeError:
        pass
    try:
        t_cp932 = raw_bytes.decode("cp932")
    except UnicodeDecodeError:
        pass

    if t_gbk is not None and t_cp932 is None:
        return t_gbk, "gbk"
    if t_cp932 is not None and t_gbk is None:
        return t_cp932, "cp932"
    if t_gbk is not None and t_cp932 is not None:
        # 若 CP932 解码出现半角片假名（\uff61-\uff9f），通常为 GBK 高位字节误判
        if any("\uff61" <= ch <= "\uff9f" for ch in t_cp932):
            return t_gbk, "gbk"
        kana_cnt = sum(1 for ch in t_cp932 if "\u3040" <= ch <= "\u30ff")
        if kana_cnt >= 2 or (kana_cnt >= 1 and not prefer_gbk):
            return t_cp932, "cp932"
        return (t_gbk, "gbk") if prefer_gbk else (t_cp932, "cp932")

    fallback = "gbk" if prefer_gbk else "cp932"
    return raw_bytes.decode(fallback, errors="replace"), f"{fallback}-lossy"


def _read_cstr_at(buf: bytes, pos: int) -> tuple[bytes, int]:
    nul = buf.find(b"\x00", pos)
    if nul == -1:
        return buf[pos:], len(buf)
    return buf[pos:nul], nul + 1


def parse_bcs1_header(raw: bytes) -> Bcs1Header:
    """解析 BCS1 (`BurikoCompiledScriptVer1.00`) 头部结构。"""
    if not raw.startswith(BCS1_MAGIC_PREFIX):
        raise ValueError(f"非 BCS1 脚本头: {raw[:32]!r}")
    if len(raw) < 36:
        raise ValueError(f"BCS1 数据长度不足: {len(raw)}")

    magic = raw[:28].split(b"\x00", 1)[0].decode("ascii", errors="replace")
    hdr_size, import_count = struct.unpack_from("<II", raw, 28)
    code_start = 28 + hdr_size
    if code_start > len(raw):
        raise ValueError(f"BCS1 code_start 越界: {code_start} > {len(raw)}")

    pos = 36
    imports: list[str] = []
    for _ in range(import_count):
        if pos >= code_start:
            break
        sb, pos = _read_cstr_at(raw, pos)
        imports.append(sb.decode("ascii", errors="replace"))

    exports: list[tuple[str, int]] = []
    if pos + 4 <= code_start:
        export_count = struct.unpack_from("<I", raw, pos)[0]
        pos += 4
        for _ in range(export_count):
            if pos >= code_start:
                break
            sb, pos = _read_cstr_at(raw, pos)
            if pos + 4 <= code_start:
                off = struct.unpack_from("<I", raw, pos)[0]
                pos += 4
            else:
                off = 0
            exports.append((sb.decode("ascii", errors="replace"), off))

    return Bcs1Header(
        magic=magic,
        header_size=hdr_size,
        code_start=code_start,
        imports=imports,
        exports=exports,
    )


def disassemble_bcs1(raw: bytes, name: str = "", prefer_gbk: bool = True) -> Bcs1Script:
    """反汇编完整 BCS1 脚本，自动定位字符串区边界以防止将字符串数据误解码为指令。"""
    hdr = parse_bcs1_header(raw)
    cs = hdr.code_start
    total_words = (len(raw) - cs) // 4
    words = struct.unpack_from(f"<{total_words}I", raw, cs)

    instructions: list[Bcs1Insn] = []
    strings: dict[int, bytes] = {}
    min_str_abs = len(raw)
    pc = 0

    while pc < total_words and (cs + pc * 4) < min_str_abs:
        op = words[pc]
        if op not in BCS1_OP_ARGS:
            raise ValueError(
                f"BCS1 未知操作码 0x{op:04x} @ {name or '<mem>'} +0x{cs + pc * 4:x}"
            )
        nargs = BCS1_OP_ARGS[op]
        if pc + 1 + nargs > total_words:
            raise ValueError(
                f"BCS1 操作数截断 op=0x{op:04x} @ {name or '<mem>'} +0x{cs + pc * 4:x}"
            )
        args = tuple(words[pc + 1 : pc + 1 + nargs])
        comment = ""

        if op == 0x03:
            str_rel = args[0]
            str_abs = cs + str_rel
            if cs <= str_abs < len(raw):
                if str_abs < min_str_abs:
                    min_str_abs = str_abs
                sb, _ = _read_cstr_at(raw, str_abs)
                strings[str_rel] = sb
                txt, enc = decode_bgi_string(sb, prefer_gbk=prefer_gbk)
                comment = f"[{enc}] {txt!r}"
        elif op == 0x7F:
            str_rel, line_no = args
            str_abs = cs + str_rel
            if cs <= str_abs < len(raw):
                if str_abs < min_str_abs:
                    min_str_abs = str_abs
                sb, _ = _read_cstr_at(raw, str_abs)
                strings[str_rel] = sb
                txt, enc = decode_bgi_string(sb, prefer_gbk=False)
                comment = f"LINE {txt}:{line_no}"

        instructions.append(
            Bcs1Insn(offset=pc * 4, opcode=op, args=args, comment=comment)
        )
        pc += 1 + nargs

    code_end = cs + pc * 4
    trailing_bytes = min_str_abs - code_end
    return Bcs1Script(
        name=name,
        header=hdr,
        code_end=code_end,
        instructions=instructions,
        strings=strings,
        trailing_bytes=trailing_bytes,
    )


def parse_bp_header(raw: bytes) -> BpHeader:
    """解析 `._bp` 字节码模块 16 字节头部。"""
    if len(raw) < 16:
        raise ValueError(f"_bp 文件过短: {len(raw)}")
    hdr_size, payload_size, u1, u2 = struct.unpack_from("<4I", raw, 0)
    if hdr_size < 16 or hdr_size + payload_size > len(raw):
        raise ValueError(
            f"_bp 头部异常: hdr_size={hdr_size}, payload_size={payload_size}, len={len(raw)}"
        )
    return BpHeader(
        header_size=hdr_size,
        payload_size=payload_size,
        unknown1=u1,
        unknown2=u2,
    )


def disassemble_bp(raw: bytes, name: str = "", prefer_gbk: bool = True) -> BpScript:
    """反汇编完整 `._bp` 模块（基于 `0x05` 字符串偏移自动定位代码区终点）。"""
    hdr = parse_bp_header(raw)
    payload = raw[hdr.header_size : hdr.header_size + hdr.payload_size]

    pc = 0
    min_str_off = len(payload)
    instructions: list[BpInsn] = []
    strings: dict[int, bytes] = {}

    while pc < min_str_off:
        # 若末尾无字符串表、仅余 <=16 字节的全 0x00 对齐填充，则视作代码区结束
        if (min_str_off - pc) <= 16 and not any(payload[pc:min_str_off]):
            break
        op = payload[pc]
        if op in BP_IMM_BYTES:
            n = BP_IMM_BYTES[op]
            if pc + 1 + n > len(payload):
                raise ValueError(
                    f"_bp 立即数越界 op=0x{op:02x} @ {name or '<mem>'} +0x{pc:x}"
                )
            signed = op in (0x01, 0x02, 0x04, 0x05, 0x06, 0x0C)
            val = int.from_bytes(payload[pc + 1 : pc + 1 + n], "little", signed=signed)
            comment = ""
            if op == 0x05:
                target = pc + val
                if 0 <= target < len(payload):
                    if target > pc and target < min_str_off:
                        min_str_off = target
                    sb, _ = _read_cstr_at(payload, target)
                    strings[target] = sb
                    txt, enc = decode_bgi_string(sb, prefer_gbk=prefer_gbk)
                    comment = f"[{enc}] STR {txt!r}"
            elif op == 0x06:
                comment = f"-> 0x{pc + val:04x}"
            instructions.append(
                BpInsn(offset=pc, opcode=op, arg=val, size=1 + n, comment=comment)
            )
            pc += 1 + n
        elif op >= 0x80:
            if pc + 2 > len(payload):
                raise ValueError(f"_bp 系统调用截断 @ {name or '<mem>'} +0x{pc:x}")
            sub = payload[pc + 1]
            sid = (op << 8) | sub
            instructions.append(
                BpInsn(
                    offset=pc,
                    opcode=op,
                    arg=sub,
                    size=2,
                    syscall_id=sid,
                    comment=f"SYS 0x{sid:04x}",
                )
            )
            pc += 2
        else:
            instructions.append(BpInsn(offset=pc, opcode=op, arg=None, size=1))
            pc += 1

    return BpScript(
        name=name,
        header=hdr,
        code_end=pc,
        instructions=instructions,
        strings=strings,
    )
