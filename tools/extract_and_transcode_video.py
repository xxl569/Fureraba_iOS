#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《フレラバ 〜Friend to Lover〜》过场视频提取与转码工具。

职责：
1. 从 `Archive/data02900.arc` 中流式提取原版 MPEG-1 视频 (`friendtolover.mpg`)
   到外置中间目录 `U:\\anti\\temp\\Fureraba_iOS\\extracted\\`；
2. 使用 FFmpeg (`libtheora` + `libvorbis`) 转码为 Godot 4.3 `VideoStreamTheora`
   原生兼容的 `.ogv` 至 `U:\\anti\\temp\\Fureraba_iOS\\movie\\friendtolover.ogv`；
3. 使用 `ffprobe` 校验输出视频的容器格式、视频流 (`theora`, `yuv420p`, 分辨率/帧率)、
   音频流 (`vorbis`, 声道/采样率) 与时长一致性。
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

from bgi_arc import BgiArchive

DEFAULT_GAME_DIR = Path(r"U:\anti\projects\game")
DEFAULT_EXTRACTED_DIR = Path(r"U:\anti\temp\Fureraba_iOS\extracted")
DEFAULT_MOVIE_DIR = Path(r"U:\anti\temp\Fureraba_iOS\movie")


def _ffmpeg_supports_theora_vorbis(ffmpeg_exe: Path) -> bool:
    try:
        proc = subprocess.run(
            [str(ffmpeg_exe), "-hide_banner", "-encoders"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        out = (proc.stdout or "") + "\n" + (proc.stderr or "")
        return ("libtheora" in out) and ("libvorbis" in out)
    except OSError:
        return False


def find_ffmpeg_pair(explicit_ffmpeg: str | None = None) -> tuple[Path, Path | None]:
    """查找支持 `libtheora` + `libvorbis` 的 `ffmpeg` 与同目录 `ffprobe`。"""
    candidates: list[Path] = []
    if explicit_ffmpeg:
        candidates.append(Path(explicit_ffmpeg))

    which_ff = shutil.which("ffmpeg")
    if which_ff:
        candidates.append(Path(which_ff))

    local_app = Path(os.environ.get("LOCALAPPDATA", ""))
    user_prof = Path(os.environ.get("USERPROFILE", ""))
    candidates.extend(
        [
            local_app / "QNWallpaper" / "0.0.1" / "bin" / "ffmpeg.exe",
            user_prof / "scoop" / "shims" / "ffmpeg.exe",
            Path(r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"),
            Path(r"C:\ffmpeg\bin\ffmpeg.exe"),
            Path(r"C:\tools\ffmpeg\bin\ffmpeg.exe"),
        ]
    )

    seen: set[str] = set()
    for cand in candidates:
        key = str(cand).lower()
        if not cand or key in seen:
            continue
        seen.add(key)
        if cand.is_file() and _ffmpeg_supports_theora_vorbis(cand):
            probe = cand.with_name("ffprobe.exe" if os.name == "nt" else "ffprobe")
            if not probe.is_file():
                which_probe = shutil.which("ffprobe")
                probe = Path(which_probe) if which_probe else None
            return cand, probe

    raise FileNotFoundError("未找到同时支持 libtheora 与 libvorbis 的 ffmpeg，请通过 --ffmpeg 指定。")


def probe_media(ffprobe_exe: Path | None, media_path: Path) -> dict[str, Any]:
    """使用 ffprobe 检测媒体文件的封装、分辨率、编解码器、音轨与时长。"""
    if ffprobe_exe is None or not ffprobe_exe.is_file():
        return {"probed": False, "size_bytes": media_path.stat().st_size}

    proc = subprocess.run(
        [
            str(ffprobe_exe),
            "-v",
            "error",
            "-show_entries",
            "format=format_name,duration,size,bit_rate:stream=index,codec_type,codec_name,width,height,r_frame_rate,pix_fmt,sample_rate,channels",
            "-of",
            "json",
            str(media_path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ffprobe 检测失败 ({media_path.name}): {proc.stderr.strip()}")

    data = json.loads(proc.stdout)
    fmt = data.get("format", {})
    streams = data.get("streams", [])
    v_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
    a_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)
    return {
        "probed": True,
        "format_name": fmt.get("format_name", ""),
        "duration": float(fmt.get("duration", 0.0) or 0.0),
        "size_bytes": int(fmt.get("size", media_path.stat().st_size) or 0),
        "bit_rate": int(fmt.get("bit_rate", 0) or 0),
        "video": v_stream,
        "audio": a_stream,
    }


def validate_ogv_info(
    info: dict[str, Any], expected_width: int, expected_height: int, min_duration: float = 1.0
) -> list[str]:
    """校验输出 `.ogv` 是否满足 Godot 4.3 VideoStreamTheora 要求。"""
    errs: list[str] = []
    if info.get("size_bytes", 0) <= 0:
        errs.append("输出文件为空")
    if not info.get("probed", False):
        errs.append("未运行 ffprobe 校验")
        return errs
    if info.get("duration", 0.0) < min_duration:
        errs.append(f"时长异常: {info.get('duration')}s")
    if "ogg" not in str(info.get("format_name", "")).lower():
        errs.append(f"封装格式非 ogg: {info.get('format_name')}")
    v = info.get("video")
    if not v:
        errs.append("缺少视频流")
    else:
        if v.get("codec_name") != "theora":
            errs.append(f"视频编码应为 theora，实际={v.get('codec_name')}")
        if int(v.get("width", 0)) != expected_width or int(v.get("height", 0)) != expected_height:
            errs.append(
                f"分辨率不匹配: {v.get('width')}x{v.get('height')} (预期 {expected_width}x{expected_height})"
            )
        if v.get("pix_fmt") != "yuv420p":
            errs.append(f"像素格式应为 yuv420p，实际={v.get('pix_fmt')}")
    a = info.get("audio")
    if not a:
        errs.append("缺少音频流")
    else:
        if a.get("codec_name") != "vorbis":
            errs.append(f"音频编码应为 vorbis，实际={a.get('codec_name')}")
        if int(a.get("channels", 0)) < 1:
            errs.append(f"音频声道数异常: {a.get('channels')}")
    return errs


def extract_movies(game_dir: Path, extracted_dir: Path) -> list[Path]:
    """从 `Archive/data02900.arc` 提取全部过场视频。"""
    arc_path = game_dir / "Archive" / "data02900.arc"
    arc = BgiArchive(arc_path)
    extracted_dir.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    for entry in arc.entries:
        dst = extracted_dir / entry.name
        if not dst.is_file() or dst.stat().st_size != entry.size:
            dst.write_bytes(arc.read_bytes(entry.name))
        outputs.append(dst)
    return outputs


def transcode_to_ogv(
    ffmpeg_exe: Path,
    ffprobe_exe: Path | None,
    src_path: Path,
    dst_path: Path,
    video_quality: int = 7,
    audio_quality: int = 5,
    force: bool = False,
) -> dict[str, Any]:
    """转码单个视频为 `.ogv` (Theora + Vorbis) 并用 `ffprobe` 校验。"""
    src_info = probe_media(ffprobe_exe, src_path)
    src_v = src_info.get("video") or {}
    exp_w = int(src_v.get("width", 1280) or 1280)
    exp_h = int(src_v.get("height", 720) or 720)
    src_dur = float(src_info.get("duration", 0.0) or 0.0)

    if not force and dst_path.is_file() and dst_path.stat().st_size > 1024:
        existing_info = probe_media(ffprobe_exe, dst_path)
        errs = validate_ogv_info(existing_info, exp_w, exp_h)
        if src_dur > 0 and abs(float(existing_info.get("duration", 0.0)) - src_dur) > 2.0:
            errs.append(f"时长偏差过大: src={src_dur:.2f}s vs out={existing_info.get('duration'):.2f}s")
        if not errs:
            return {"status": "skipped_valid", "src_info": src_info, "out_info": existing_info}

    dst_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = dst_path.with_name(f".{dst_path.stem}.tmp.ogv")
    if tmp_path.exists():
        tmp_path.unlink()

    cmd = [
        str(ffmpeg_exe),
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(src_path),
        "-map",
        "0:v:0",
        "-map",
        "0:a:0?",
        "-c:v",
        "libtheora",
        "-q:v",
        str(video_quality),
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "libvorbis",
        "-q:a",
        str(audio_quality),
        "-f",
        "ogg",
        str(tmp_path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    if proc.returncode != 0:
        if tmp_path.exists():
            tmp_path.unlink()
        raise RuntimeError(f"FFmpeg 转码失败 ({src_path.name}): {proc.stderr.strip()}")

    tmp_path.replace(dst_path)
    out_info = probe_media(ffprobe_exe, dst_path)
    errs = validate_ogv_info(out_info, exp_w, exp_h)
    if src_dur > 0 and abs(float(out_info.get("duration", 0.0)) - src_dur) > 2.0:
        errs.append(f"时长偏差过大: src={src_dur:.2f}s vs out={out_info.get('duration'):.2f}s")
    if errs:
        raise RuntimeError(f"输出校验失败 ({dst_path.name}): {'; '.join(errs)}")
    return {"status": "transcoded", "src_info": src_info, "out_info": out_info}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="提取并转码 Fureraba 过场视频为 Godot 4.3 .ogv")
    parser.add_argument("--game-dir", type=Path, default=DEFAULT_GAME_DIR)
    parser.add_argument("--extracted-dir", type=Path, default=DEFAULT_EXTRACTED_DIR)
    parser.add_argument("--movie-dir", type=Path, default=DEFAULT_MOVIE_DIR)
    parser.add_argument("--ffmpeg", type=str, default=None)
    parser.add_argument("--qv", type=int, default=7, help="Theora 视频质量 (0-10)")
    parser.add_argument("--qa", type=int, default=5, help="Vorbis 音频质量 (0-10)")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args(argv)

    ffmpeg_exe, ffprobe_exe = find_ffmpeg_pair(args.ffmpeg)
    print(f"使用 ffmpeg:  {ffmpeg_exe}")
    print(f"使用 ffprobe: {ffprobe_exe}")

    if args.verify_only:
        ogvs = sorted(args.movie_dir.glob("*.ogv"))
        if not ogvs:
            print(f"未在 {args.movie_dir} 找到 .ogv 文件", file=sys.stderr)
            return 1
        for ogv in ogvs:
            info = probe_media(ffprobe_exe, ogv)
            v = info.get("video") or {}
            exp_w = int(v.get("width", 0) or 0)
            exp_h = int(v.get("height", 0) or 0)
            src_dur = 0.0
            for ext in (".mpg", ".mpeg"):
                src_cand = args.extracted_dir / (ogv.stem + ext)
                if src_cand.is_file():
                    src_info = probe_media(ffprobe_exe, src_cand)
                    src_v = src_info.get("video") or {}
                    exp_w = int(src_v.get("width", exp_w) or exp_w)
                    exp_h = int(src_v.get("height", exp_h) or exp_h)
                    src_dur = float(src_info.get("duration", 0.0) or 0.0)
                    break
            errs = validate_ogv_info(info, exp_w if exp_w > 0 else 1280, exp_h if exp_h > 0 else 720)
            if src_dur > 0 and abs(float(info.get("duration", 0.0)) - src_dur) > 2.0:
                errs.append(f"时长偏差过大: src={src_dur:.2f}s vs out={info.get('duration'):.2f}s")
            print(f"[校验] {ogv.name}: {json.dumps(info, ensure_ascii=False)}")
            if errs:
                print(f"  ERROR: {errs}", file=sys.stderr)
                return 1
        return 0

    extracted = extract_movies(args.game_dir, args.extracted_dir)
    for src in extracted:
        dst = args.movie_dir / (src.stem + ".ogv")
        res = transcode_to_ogv(ffmpeg_exe, ffprobe_exe, src, dst, args.qv, args.qa, args.force)
        print(f"[{res['status']}] {src.name} -> {dst}")
        print("  src:", json.dumps(res["src_info"], ensure_ascii=False))
        print("  out:", json.dumps(res["out_info"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
