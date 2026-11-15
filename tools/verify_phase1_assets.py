"""
阶段一资产全量解码、完整性校验与审计报告生成脚本。

覆盖目标：
1. DSC 图像包 (`sysgrp.arc`, `data02400`, `data02600`, `data02700`, `data02810`)：
   校验裸 BMP 头部结构并导出 PNG 样本到 `U:\\anti\\temp\\Fureraba_iOS\\samples\\dsc\\`；
2. CBG 图像包 (`data02000`, `data02020`, `data02100`, `data02150.arc.bak`, `data02200`,
   `data02210`, `data02300`, `data02800`, `data02910`)：
   全库 4,864 张图像执行完整像素级解码校验并导出代表性 PNG 样本到 `U:\\anti\\temp\\Fureraba_iOS\\samples\\cbg\\`；
3. `bw  ` 音频包 (`data03000`, `data04001~04012`, `data04800`, `data05000`, `data05100` 及 `system.arc` 内置音效)：
   全量校验 22,501 + 6 条音频的 `bw  ` 头字段与全页 Ogg CRC32 / Vorbis 三头包 / EOS，
   并对代表样本执行 `ffmpeg` 真实 PCM 解码，输出 JSON 审计报告；
4. `BGI.gdb` (`SDC FORMAT 1.00` + `BURIKO GDB 3.00`) 完整解密解压与结构校验。
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bgi_arc import BgiArchive, BgiVfs
from bgi_audio import export_bw_ogg, extract_ogg, parse_bw_header
from bgi_cbg import _read_varint, decode_cbg, export_cbg_png, parse_cbg_header
from bgi_dsc import bgi_key_step, decode_dsc, export_dsc_png, inspect_dsc_image_header
from bgi_gdb import load_gdb_file
from extract_and_transcode_video import find_ffmpeg_pair

DSC_GRAPHIC_ARCS = [
    ("sysgrp.arc", False),
    ("data02400.arc", True),
    ("data02600.arc", True),
    ("data02700.arc", True),
    ("data02810.arc", True),
]

CBG_GRAPHIC_ARCS = [
    ("data02000.arc", True),
    ("data02020.arc", True),
    ("data02100.arc", True),
    ("data02150.arc.bak", True),
    ("data02200.arc", True),
    ("data02210.arc", True),
    ("data02300.arc", True),
    ("data02800.arc", True),
    ("data02910.arc", True),
]

AUDIO_ARCS = (
    ["data03000.arc"]
    + [f"data040{i:02d}.arc" for i in range(1, 13)]
    + ["data04800.arc", "data05000.arc", "data05100.arc"]
)


def _arc_path(game_dir: Path, name: str, in_archive: bool) -> Path:
    return (game_dir / "Archive" / name) if in_archive else (game_dir / name)


def verify_dsc_archives(game_dir: Path, out_dir: Path) -> list[dict]:
    out_dir.mkdir(parents=True, exist_ok=True)
    report: list[dict] = []
    for arc_name, in_arch in DSC_GRAPHIC_ARCS:
        arc = BgiArchive(_arc_path(game_dir, arc_name, in_arch))
        bpp_counts: Counter[int] = Counter()
        exported: list[dict] = []
        # 抽样前 2 个 + 末尾 1 个（若存在）
        sample_indices = sorted({0, min(1, len(arc.entries) - 1), len(arc.entries) - 1})
        for idx in sample_indices:
            e = arc.entries[idx]
            raw = arc.read_bytes(e.name)
            decoded = decode_dsc(raw)
            bmp = inspect_dsc_image_header(decoded)
            bpp_counts[bmp.bpp] += 1
            safe_stem = f"{arc_name.replace('.', '_')}__{e.name}".replace("/", "_")
            png_path = out_dir / f"{safe_stem}.png"
            export_dsc_png(raw, png_path)
            exported.append(
                {
                    "entry": e.name,
                    "png": str(png_path),
                    "width": bmp.width,
                    "height": bmp.height,
                    "bpp": bmp.bpp,
                    "compression": bmp.compression,
                    "data_offset": bmp.data_offset,
                }
            )
        report.append(
            {
                "archive": arc_name,
                "total_entries": len(arc.entries),
                "sample_bpps": dict(bpp_counts),
                "exported": exported,
            }
        )
    return report


def verify_cbg_archives(game_dir: Path, out_dir: Path) -> list[dict]:
    out_dir.mkdir(parents=True, exist_ok=True)
    report: list[dict] = []
    for arc_name, in_arch in CBG_GRAPHIC_ARCS:
        arc = BgiArchive(_arc_path(game_dir, arc_name, in_arch))
        ver_counts: Counter[int] = Counter()
        bpp_counts: Counter[int] = Counter()
        checksum_errors = 0
        pixel_decode_errors = 0
        pixel_decoded_count = 0
        max_dim = (0, 0, "")
        for e, raw in arc.iter_entries():
            h = parse_cbg_header(raw)
            ver_counts[h.version] += 1
            bpp_counts[h.bpp] += 1
            if h.width == 0 or h.height == 0 or h.bpp not in (8, 24, 32):
                pixel_decode_errors += 1
                continue
            try:
                dec_hdr, pixels = decode_cbg(raw)
                expected_len = dec_hdr.width * dec_hdr.height * (dec_hdr.bpp // 8)
                if len(pixels) != expected_len:
                    pixel_decode_errors += 1
                else:
                    pixel_decoded_count += 1
            except Exception:
                checksum_errors += 1
                pixel_decode_errors += 1
            if h.width * h.height > max_dim[0] * max_dim[1]:
                max_dim = (h.width, h.height, e.name)

        # 挑选代表性样本导出 PNG：包含首条目、以及若为 data02910 则必含 fl_roll_hi、若为 data02100 必含一对 _n/_nh
        target_names: list[str] = [arc.entries[0].name]
        if len(arc.entries) > 1:
            target_names.append(arc.entries[-1].name)
        if arc_name == "data02910.arc" and "fl_roll_hi" in arc:
            target_names.append("fl_roll_hi")
        if arc_name == "data02100.arc":
            for cand in ("hi01wa_n", "hi01wa_nh"):
                if cand in arc:
                    target_names.append(cand)
        if arc_name in ("data02150.arc.bak", "data02200.arc") and "miev10_a05_9" in arc:
            target_names.append("miev10_a05_9")

        exported: list[dict] = []
        seen: set[str] = set()
        for name in target_names:
            if name in seen:
                continue
            seen.add(name)
            safe_stem = f"{arc_name.replace('.', '_')}__{name}".replace("/", "_")
            png_path = out_dir / f"{safe_stem}.png"
            h = export_cbg_png(arc.read_bytes(name), png_path)
            exported.append(
                {
                    "entry": name,
                    "png": str(png_path),
                    "width": h.width,
                    "height": h.height,
                    "bpp": h.bpp,
                    "version": h.version,
                }
            )

        report.append(
            {
                "archive": arc_name,
                "total_entries": len(arc.entries),
                "versions": dict(ver_counts),
                "bpps": dict(bpp_counts),
                "checksum_errors": checksum_errors,
                "pixel_decoded_count": pixel_decoded_count,
                "pixel_decode_errors": pixel_decode_errors,
                "largest_entry": {"name": max_dim[2], "width": max_dim[0], "height": max_dim[1]},
                "exported": exported,
            }
        )
    return report


def verify_audio_archives(game_dir: Path, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    per_arc: list[dict] = []
    ogg_samples: list[dict] = []
    import subprocess

    try:
        ffmpeg_exe, _ = find_ffmpeg_pair()
    except FileNotFoundError:
        ffmpeg_exe = None

    for arc_name in AUDIO_ARCS:
        arc = BgiArchive(game_dir / "Archive" / arc_name)
        loop_counts: Counter[int] = Counter()
        sr_counts: Counter[int] = Counter()
        ch_counts: Counter[int] = Counter()
        fmt_counts: Counter[int] = Counter()
        nonzero_loop_offsets = 0
        size_mismatches = 0
        ogg_stream_errors = 0
        ogg_crc_verified_count = 0
        total_duration = 0.0

        for e, raw in arc.iter_entries():
            bw = parse_bw_header(raw)
            loop_counts[bw.loop_flag] += 1
            sr_counts[bw.sample_rate] += 1
            ch_counts[bw.channels] += 1
            fmt_counts[bw.format_tag] += 1
            if bw.loop_start != 0 or bw.loop_end != 0:
                nonzero_loop_offsets += 1
            if bw.header_size + bw.ogg_size != e.size:
                size_mismatches += 1
            else:
                try:
                    _, _, info = extract_ogg(raw, validate=True)
                    if (
                        not info
                        or not info.get("has_eos")
                        or info.get("ogg_channels") != bw.channels
                        or info.get("ogg_sample_rate") != bw.sample_rate
                    ):
                        ogg_stream_errors += 1
                    elif info.get("crc32_verified"):
                        ogg_crc_verified_count += 1
                except Exception:
                    ogg_stream_errors += 1
            total_duration += bw.duration_sec

        # 对每个归档抽取第 0 个条目完整提取并校验 Ogg Vorbis
        sample_e = arc.entries[0]
        raw = arc.read_bytes(sample_e.name)
        bw, ogg_bytes, info = extract_ogg(raw, validate=True)
        # 导出几个代表性 Ogg（BGM / SE / Voice / System）并用 ffmpeg 真实解码为 PCM
        exported_path = None
        ffmpeg_pcm_ok = None
        if arc_name in ("data03000.arc", "data04001.arc", "data04800.arc", "data05000.arc", "data05100.arc"):
            exported_path = out_dir / f"{arc_name.replace('.', '_')}__{sample_e.name}.ogg"
            export_bw_ogg(raw, exported_path)
            if ffmpeg_exe is not None:
                proc = subprocess.run(
                    [str(ffmpeg_exe), "-v", "error", "-i", str(exported_path), "-f", "null", "-"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                ffmpeg_pcm_ok = proc.returncode == 0 and proc.stderr.strip() == ""

        ogg_samples.append(
            {
                "archive": arc_name,
                "entry": sample_e.name,
                "bw_sample_rate": bw.sample_rate,
                "bw_channels": bw.channels,
                "bw_loop_flag": bw.loop_flag,
                "bw_duration_sec": round(bw.duration_sec, 3),
                "ogg_info": info,
                "exported_ogg": str(exported_path) if exported_path else None,
                "ffmpeg_pcm_ok": ffmpeg_pcm_ok,
            }
        )
        per_arc.append(
            {
                "archive": arc_name,
                "total_entries": len(arc.entries),
                "loop_flags": dict(loop_counts),
                "nonzero_loop_offsets": nonzero_loop_offsets,
                "size_mismatches": size_mismatches,
                "ogg_stream_errors": ogg_stream_errors,
                "ogg_crc_verified_count": ogg_crc_verified_count,
                "sample_rates": dict(sr_counts),
                "channels": dict(ch_counts),
                "format_tags": dict(fmt_counts),
                "total_duration_sec": round(total_duration, 1),
            }
        )

    # 额外校验 system.arc 内嵌 DSC+bw 音频（click, cursor, TITLE_*）
    sys_arc = BgiArchive(game_dir / "system.arc")
    sys_audio: list[dict] = []
    for e in sys_arc.entries:
        raw = sys_arc.read_bytes(e.name)
        if raw.startswith(b"DSC FORMAT 1.00"):
            dec = decode_dsc(raw)
            if len(dec) >= 64 and dec[4:8] == b"bw  ":
                bw, _, info = extract_ogg(dec, validate=True)
                sys_audio.append(
                    {
                        "entry": f"system.arc/{e.name}",
                        "sample_rate": bw.sample_rate,
                        "channels": bw.channels,
                        "loop_flag": bw.loop_flag,
                        "ogg_info": info,
                    }
                )

    return {"archives": per_arc, "ogg_samples": ogg_samples, "system_arc_audio": sys_audio}


def verify_uncensored_patch_and_nude_pairs(game_dir: Path) -> dict:
    """核查 `data02150.arc.bak` vs `data02200.arc` 覆盖差异与 `data02100.arc` `_h` 透视配对。"""
    a2150 = BgiArchive(game_dir / "Archive" / "data02150.arc.bak")
    a2200 = BgiArchive(game_dir / "Archive" / "data02200.arc")
    overlap_names = [e.name for e in a2150.entries if e.name in a2200]
    bpp_pairs: Counter[str] = Counter()
    dim_mismatches: list[dict] = []

    for name in overlap_names:
        h1 = parse_cbg_header(a2150.read_bytes(name, limit=64))
        h2 = parse_cbg_header(a2200.read_bytes(name, limit=64))
        bpp_pairs[f"{h1.bpp}vs{h2.bpp}"] += 1
        if (h1.width, h1.height) != (h2.width, h2.height):
            dim_mismatches.append(
                {
                    "entry": name,
                    "data02150": [h1.width, h1.height],
                    "data02200": [h2.width, h2.height],
                }
            )

    # 抽样比对同尺寸 CG 实际 RGB 像素差异（hiev08_a01）
    h1, raw1 = decode_cbg(a2150.read_bytes("hiev08_a01"))
    h2, raw2 = decode_cbg(a2200.read_bytes("hiev08_a01"))
    b1, b2 = h1.bpp // 8, h2.bpp // 8
    max_rgb_diff = 0
    diff_pixels = 0
    total_pixels = h1.width * h1.height
    for i in range(total_pixels):
        p1, p2 = i * b1, i * b2
        d = max(abs(raw1[p1] - raw2[p2]), abs(raw1[p1 + 1] - raw2[p2 + 1]), abs(raw1[p1 + 2] - raw2[p2 + 2]))
        if d > max_rgb_diff:
            max_rgb_diff = d
        if d > 30:
            diff_pixels += 1

    # 校验 VFS 挂载优先级
    vfs_uncensored = BgiVfs(game_dir, include_data02150_bak=True)
    vfs_hit = vfs_uncensored.get_entry("hiev08_a01").archive_path.name

    # 校验 data02100.arc 立绘 `_h` 透视差分严格配对
    a2100 = BgiArchive(game_dir / "Archive" / "data02100.arc")
    names_2100 = {e.name.lower() for e in a2100.entries}
    nude_pairs = sorted(n for n in names_2100 if (n + "h") in names_2100)
    orphan_h = sorted(n for n in names_2100 if n.endswith("h") and n[:-1] not in names_2100)

    return {
        "data02150_entries": len(a2150.entries),
        "data02200_entries": len(a2200.entries),
        "overlap_count": len(overlap_names),
        "bpp_pairs": dict(bpp_pairs),
        "dimension_mismatches": dim_mismatches,
        "vfs_priority_winner_for_hiev08_a01": vfs_hit,
        "sample_pixel_diff_hiev08_a01": {
            "max_rgb_diff": max_rgb_diff,
            "pixels_gt_30": diff_pixels,
            "total_pixels": total_pixels,
            "diff_ratio_pct": round(diff_pixels * 100.0 / total_pixels, 3),
        },
        "data02100_total": len(names_2100),
        "data02100_h_pairs": len(nude_pairs),
        "data02100_orphan_h": orphan_h,
    }


def verify_gdb(game_dir: Path) -> dict:
    """解码并校验 `BGI.gdb` (`SDC FORMAT 1.00` + `BURIKO GDB 3.00`) 完整性。"""
    sdc_hdr, db, _ = load_gdb_file(game_dir / "BGI.gdb")
    return {
        "sdc_key": sdc_hdr.key,
        "sdc_compressed_size": sdc_hdr.compressed_size,
        "sdc_uncompressed_size": sdc_hdr.uncompressed_size,
        "sdc_reserved": sdc_hdr.reserved,
        "gdb_magic": db.magic,
        "project_code": db.project_code,
        "header_count": db.header_count,
        "labels_count": len(db.labels),
        "resources_count": len(db.resources),
        "scripts_count": len(db.scripts),
        "total_script_bits": sum(s.bit_count for s in db.scripts),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="阶段一图像、音频与 BGI.gdb 全量审计及样本导出")
    parser.add_argument("--game-dir", type=Path, default=Path(r"U:\anti\projects\game"))
    parser.add_argument(
        "--samples-dir",
        type=Path,
        default=Path(r"U:\anti\temp\Fureraba_iOS\samples"),
    )
    parser.add_argument(
        "--out-json",
        type=Path,
        default=Path(r"U:\anti\temp\Fureraba_iOS\phase1_asset_audit.json"),
    )
    args = parser.parse_args()

    dsc_rep = verify_dsc_archives(args.game_dir, args.samples_dir / "dsc")
    cbg_rep = verify_cbg_archives(args.game_dir, args.samples_dir / "cbg")
    aud_rep = verify_audio_archives(args.game_dir, args.samples_dir / "audio")
    patch_rep = verify_uncensored_patch_and_nude_pairs(args.game_dir)
    gdb_rep = verify_gdb(args.game_dir)

    full = {"dsc": dsc_rep, "cbg": cbg_rep, "audio": aud_rep, "patches": patch_rep, "gdb": gdb_rep}
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(full, ensure_ascii=False, indent=2), encoding="utf-8")

    cbg_errors = sum(x["pixel_decode_errors"] for x in cbg_rep)
    aud_errors = sum(x["ogg_stream_errors"] for x in aud_rep["archives"]) + sum(
        x["size_mismatches"] for x in aud_rep["archives"]
    )
    sys_audio_ok = all(
        s["ogg_info"]["vorbis_version"] == 0
        and s["ogg_info"]["has_eos"]
        and s["ogg_info"].get("crc32_verified")
        for s in aud_rep["system_arc_audio"]
    )
    samples_ok = all(
        s["ogg_info"]["vorbis_version"] == 0
        and s["ogg_info"]["has_eos"]
        and (s["ffmpeg_pcm_ok"] in (None, True))
        for s in aud_rep["ogg_samples"]
    )

    print("DSC 抽样归档数:", len(dsc_rep))
    print(
        "CBG 审计归档数:",
        len(cbg_rep),
        "| 合计条目:",
        sum(x["total_entries"] for x in cbg_rep),
        "| 像素全解码:",
        sum(x["pixel_decoded_count"] for x in cbg_rep),
        "| 解码失败:",
        cbg_errors,
    )
    print(
        "Audio 审计归档数:",
        len(aud_rep["archives"]),
        "| 合计条目:",
        sum(x["total_entries"] for x in aud_rep["archives"]),
        "| Ogg 校验失败:",
        aud_errors,
        "| CRC32 全校验:",
        sum(x["ogg_crc_verified_count"] for x in aud_rep["archives"]),
    )
    print("2150 vs 2200 重叠:", patch_rep["overlap_count"], "| 分辨率差异:", len(patch_rep["dimension_mismatches"]), "| 2100 _h 配对:", patch_rep["data02100_h_pairs"])
    print("system.arc 内置 bw 音频:", [x["entry"] for x in aud_rep["system_arc_audio"]])
    print("BGI.gdb 解析:", gdb_rep["project_code"], "| labels:", gdb_rep["labels_count"], "| resources:", gdb_rep["resources_count"], "| scripts:", gdb_rep["scripts_count"])
    print("Ogg 流校验通过:", samples_ok and sys_audio_ok)
    if cbg_errors > 0 or aud_errors > 0 or not (samples_ok and sys_audio_ok):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
