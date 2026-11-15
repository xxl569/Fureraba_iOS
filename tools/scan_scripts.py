"""
全量脚本归档扫描工具：
扫描 `data01000~01890.arc`、`sysprg.arc`、`sysprg2.arc`、`system.arc` 中的所有字节码脚本，
统计全量 Opcode 频次表、BCS1 系统调用（0x80..0x3FF）与导出函数调用（framework._bs / function）、
`_bp` 系统调用表与字符串编码分布，并输出结构化 JSON 与 Markdown 统计摘要。
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bgi_arc import BgiArchive
from bgi_script import (
    BCS1_MAGIC_PREFIX,
    BCS1_OP_NAMES,
    disassemble_bcs1,
    disassemble_bp,
    maybe_decompress_script,
    decode_bgi_string,
)

SCRIPT_ARCS_ROOT = ("system.arc", "sysprg.arc", "sysprg2.arc")
SCRIPT_ARCS_ARCHIVE = (
    "data01000.arc",
    "data01200.arc",
    "data01210.arc",
    "data01300.arc",
    "data01350.arc",
    "data01800.arc",
    "data01810.arc",
    "data01860.arc",
    "data01870.arc",
    "data01880.arc",
    "data01890.arc",
)


def scan_all_scripts(game_dir: Path) -> dict:
    """全量扫描并反汇编游戏目录下所有脚本包。"""
    arc_paths: list[Path] = []
    for name in SCRIPT_ARCS_ROOT:
        p = game_dir / name
        if p.is_file():
            arc_paths.append(p)
    for name in SCRIPT_ARCS_ARCHIVE:
        p = game_dir / "Archive" / name
        if p.is_file():
            arc_paths.append(p)

    bcs1_op_freq: Counter[int] = Counter()
    bcs1_call_targets: Counter[str] = Counter()
    bp_op_freq: Counter[int] = Counter()
    bp_sys_freq: Counter[int] = Counter()
    enc_freq: Counter[str] = Counter()

    bcs1_files: list[dict] = []
    bp_files: list[dict] = []
    other_files: list[dict] = []
    errors: list[str] = []

    framework_exports: list[tuple[str, int]] = []
    function_exports: list[tuple[str, int]] = []
    all_imports: Counter[str] = Counter()

    for arc_path in arc_paths:
        arc = BgiArchive(arc_path)
        is_scenario_arc = arc_path.name.startswith("data018")
        prefer_gbk = is_scenario_arc or arc_path.name in ("data01000.arc", "data01200.arc", "data01210.arc")
        for entry, data in arc.iter_entries():
            raw, was_dsc = maybe_decompress_script(data)
            full_name = f"{arc_path.name}/{entry.name}"

            if raw.startswith(BCS1_MAGIC_PREFIX):
                try:
                    scr = disassemble_bcs1(raw, name=full_name, prefer_gbk=prefer_gbk)
                except Exception as exc:
                    errors.append(f"BCS1 失败 {full_name}: {exc}")
                    continue

                if entry.name == "framework._bs" and arc_path.name == "system.arc":
                    framework_exports = list(scr.header.exports)
                elif entry.name == "function" and arc_path.name == "data01000.arc":
                    function_exports = list(scr.header.exports)

                for imp in scr.header.imports:
                    all_imports[imp] += 1

                insns = scr.instructions
                for idx, insn in enumerate(insns):
                    bcs1_op_freq[insn.opcode] += 1
                    # 统计外部/导出函数调用（仅 0x1c CALL_EXTERNAL 紧邻前方的 PUSH_STR 0x03，排除 0x18 JMP）
                    if insn.opcode == 0x1C and idx > 0:
                        for back in range(1, min(4, idx + 1)):
                            prev = insns[idx - back]
                            if prev.opcode == 0x03:
                                sb = scr.strings.get(prev.args[0], b"")
                                if sb and all(32 <= b < 127 for b in sb) and b"BURIKOScript" not in sb:
                                    bcs1_call_targets[sb.decode("ascii")] += 1
                                break

                for sb in scr.strings.values():
                    _, enc = decode_bgi_string(sb, prefer_gbk=prefer_gbk)
                    enc_freq[enc] += 1

                bcs1_files.append(
                    {
                        "name": full_name,
                        "dsc": was_dsc,
                        "size": len(raw),
                        "insns": len(insns),
                        "strings": len(scr.strings),
                        "trailing_bytes": scr.trailing_bytes,
                        "imports": scr.header.imports,
                        "exports": len(scr.header.exports),
                    }
                )
            elif entry.name.endswith("._bp") and len(raw) >= 16:
                try:
                    bp = disassemble_bp(raw, name=full_name, prefer_gbk=True)
                except Exception as exc:
                    errors.append(f"_bp 失败 {full_name}: {exc}")
                    continue

                for insn in bp.instructions:
                    bp_op_freq[insn.opcode] += 1
                    if insn.syscall_id is not None:
                        bp_sys_freq[insn.syscall_id] += 1

                for sb in bp.strings.values():
                    _, enc = decode_bgi_string(sb, prefer_gbk=True)
                    enc_freq[enc] += 1

                bp_files.append(
                    {
                        "name": full_name,
                        "dsc": was_dsc,
                        "size": len(raw),
                        "code_end": bp.code_end,
                        "insns": len(bp.instructions),
                        "strings": len(bp.strings),
                    }
                )
            else:
                other_files.append(
                    {
                        "name": full_name,
                        "dsc": was_dsc,
                        "size": len(raw),
                        "head_hex": raw[:16].hex(),
                    }
                )

    return {
        "summary": {
            "archives_scanned": len(arc_paths),
            "bcs1_count": len(bcs1_files),
            "bp_count": len(bp_files),
            "other_count": len(other_files),
            "error_count": len(errors),
            "distinct_bcs1_opcodes": len(bcs1_op_freq),
            "total_bcs1_insns": sum(bcs1_op_freq.values()),
            "distinct_bp_opcodes": len(bp_op_freq),
            "distinct_bp_syscalls": len(bp_sys_freq),
            "total_bp_insns": sum(bp_op_freq.values()),
            "string_encodings": dict(enc_freq),
        },
        "errors": errors,
        "imports": dict(all_imports.most_common()),
        "framework_exports": [{"name": n, "offset": off} for n, off in framework_exports],
        "function_exports": [{"name": n, "offset": off} for n, off in function_exports],
        "bcs1_opcodes": [
            {
                "opcode": f"0x{op:03x}",
                "opcode_int": op,
                "mnemonic": BCS1_OP_NAMES.get(op, "SYS" if op >= 0x80 else "OP"),
                "count": cnt,
            }
            for op, cnt in bcs1_op_freq.most_common()
        ],
        "bcs1_call_targets": [
            {"name": k, "count": v} for k, v in bcs1_call_targets.most_common()
        ],
        "bp_opcodes": [
            {"opcode": f"0x{op:02x}", "count": cnt}
            for op, cnt in bp_op_freq.most_common()
        ],
        "bp_syscalls": [
            {"syscall": f"0x{sid:04x}", "count": cnt}
            for sid, cnt in bp_sys_freq.most_common()
        ],
        "other_files": other_files,
        "bcs1_files_trailing_gt4": [f for f in bcs1_files if abs(f["trailing_bytes"]) > 8],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="全量扫描 Fureraba 脚本字节码统计")
    parser.add_argument("--game-dir", type=Path, default=Path(r"U:\anti\projects\game"))
    parser.add_argument(
        "--out-json",
        type=Path,
        default=Path(r"U:\anti\temp\Fureraba_iOS\script_scan_stats.json"),
    )
    args = parser.parse_args()

    result = scan_all_scripts(args.game_dir)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("扫描汇总:", json.dumps(result["summary"], ensure_ascii=False))
    print("异常数:", result["summary"]["error_count"], result["errors"][:5])
    print("trailing > 8 字节的 BCS1 脚本:", len(result["bcs1_files_trailing_gt4"]), result["bcs1_files_trailing_gt4"][:5])
    print("非字节码其他文件:", result["other_files"])
    print("Top 25 BCS1 Opcodes:")
    for row in result["bcs1_opcodes"][:25]:
        print(f"  {row['opcode']} ({row['mnemonic']:24s}): {row['count']}")
    print("Top 25 BCS1 Call Targets:")
    for row in result["bcs1_call_targets"][:25]:
        print(f"  {row['name']:28s}: {row['count']}")
    print("Top 25 _bp Syscalls:")
    for row in result["bp_syscalls"][:25]:
        print(f"  {row['syscall']}: {row['count']}")
    return 0 if result["summary"]["error_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
