"""
Fureraba iOS 移植项目 —— 阶段一工具链自动化测试套件。

覆盖模块：
- `bgi_arc.py` (ARC v1/v2 归档解析与 `BgiVfs` 优先级覆盖)
- `bgi_dsc.py` (DSC 1.00 解压、0xFFFF 进位边界、`BM` 位图解码与 PNG 导出)
- `bgi_cbg.py` (CBG v1 8/24/32bpp 与超长卷轴解码、校验和异常)
- `bgi_audio.py` (`bw  ` 音频头、Ogg Vorbis 流页完整性与边界异常)
- `bgi_script.py` (BCS1 与 `._bp` 反汇编、混合编码与边界异常)
- `extract_and_transcode_video.py` (`.ogv` 转码成品 `ffprobe` 校验)
"""

from __future__ import annotations

from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from bgi_arc import BgiArchive, BgiVfs
from bgi_audio import extract_ogg, parse_bw_header, validate_ogg_stream
from bgi_cbg import cbg_to_pil, decode_cbg, decode_cbg_py, export_cbg_png, parse_cbg_header
from bgi_dsc import (
    bgi_key_step,
    decode_dsc,
    dsc_image_to_pil,
    export_dsc_png,
    inspect_dsc_image_header,
    parse_dsc_header,
)
from bgi_gdb import decode_sdc, load_gdb_file, parse_sdc_header
from bgi_script import (
    BCS1_OP_NAMES,
    disassemble_bcs1,
    disassemble_bp,
    maybe_decompress_script,
    parse_bcs1_header,
)
from extract_and_transcode_video import find_ffmpeg_pair, probe_media
from verify_phase1_assets import verify_uncensored_patch_and_nude_pairs

GAME_DIR = Path(r"U:\anti\projects\game")
OGV_PATH = Path(r"U:\anti\temp\Fureraba_iOS\movie\friendtolover.ogv")
GODOT_EXE = Path(r"U:\anti\projects\HenPri_iOS\tools\godot\Godot_v4.3-stable_win64_console.exe")
GODOT_VERIFY_DIR = Path(__file__).resolve().parents[1] / "godot_verify"


@unittest.skipUnless(GAME_DIR.is_dir(), "未找到目标游戏目录 U:\\anti\\projects\\game")
class TestPhase1RealArchives(unittest.TestCase):
    """基于真实游戏归档与转码产物的端到端验证。"""

    def test_arc_v1_v2_and_vfs_override(self) -> None:
        v1 = BgiArchive(GAME_DIR / "system.arc")
        self.assertEqual(v1.version, 1)
        self.assertIn("ipl._bp", v1)
        self.assertIn("framework._bs", v1)
        self.assertEqual(v1.get_entry("IPL._BP").name, "ipl._bp")

        v2 = BgiArchive(GAME_DIR / "Archive" / "data02200.arc")
        self.assertEqual(v2.version, 2)
        self.assertIn("hiev08_a01", v2)

        with self.assertRaises(KeyError):
            v1.get_entry("nonexistent_entry_xyz")

        # 挂载不含 data02150.arc.bak 时应命中 data02200.arc
        vfs_censored = BgiVfs(GAME_DIR, include_data02150_bak=False)
        self.assertEqual(vfs_censored.get_entry("hiev08_a01").archive_path.name, "data02200.arc")
        self.assertEqual(vfs_censored.get_entry("nudeprcs._bp").archive_path.name, "sysprg2.arc")

        # 挂载含 data02150.arc.bak 时应由 data02150.arc.bak 覆盖 data02200.arc
        vfs_uncensored = BgiVfs(GAME_DIR, include_data02150_bak=True)
        self.assertEqual(
            vfs_uncensored.get_entry("hiev08_a01").archive_path.name,
            "data02150.arc.bak",
        )
        shadowed = vfs_uncensored.list_shadowed_entries()
        self.assertGreaterEqual(len(shadowed), 470)

    def test_dsc_scripts_and_graphics(self) -> None:
        # 触发 key 0xFFFF 进位边界的 roll_hi 脚本
        a1350 = BgiArchive(GAME_DIR / "Archive" / "data01350.arc")
        roll_hi_dec = decode_dsc(a1350.read_bytes("roll_hi"))
        self.assertTrue(roll_hi_dec.startswith(b"BurikoCompiledScriptVer1.00"))

        # 验证全部 5 个 DSC 图像归档的首条目均能正确解码为 Windows BMP 并导出 PNG
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            for p in [
                GAME_DIR / "sysgrp.arc",
                GAME_DIR / "Archive" / "data02400.arc",
                GAME_DIR / "Archive" / "data02600.arc",
                GAME_DIR / "Archive" / "data02700.arc",
                GAME_DIR / "Archive" / "data02810.arc",
            ]:
                arc = BgiArchive(p)
                entry_name = arc.entries[0].name
                raw = arc.read_bytes(entry_name)
                dec = decode_dsc(raw)
                bmp = inspect_dsc_image_header(dec)
                self.assertIn(bmp.bpp, (24, 32))
                self.assertEqual(bmp.compression, 0)
                out_png = tmp_dir / f"{p.stem}.png"
                export_dsc_png(raw, out_png)
                with Image.open(out_png) as im:
                    self.assertEqual(im.size, (bmp.width, bmp.height))

    def test_cbg_all_bpps_and_long_scroll(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            # 抽样验证 8bpp / 24bpp / 32bpp 与 1280x11362 超长卷轴图
            cases = [
                (GAME_DIR / "Archive" / "data02000.arc", None, None),
                (GAME_DIR / "Archive" / "data02020.arc", None, None),
                (GAME_DIR / "Archive" / "data02100.arc", "hi01wa_n", (1280, 938)),
                (GAME_DIR / "Archive" / "data02150.arc.bak", "hiev08_a01", (1280, 720)),
                (GAME_DIR / "Archive" / "data02200.arc", "hiev08_a01", (1280, 720)),
                (GAME_DIR / "Archive" / "data02210.arc", None, None),
                (GAME_DIR / "Archive" / "data02300.arc", None, None),
                (GAME_DIR / "Archive" / "data02800.arc", None, None),
                (GAME_DIR / "Archive" / "data02910.arc", "fl_roll_hi", (1280, 11362)),
            ]
            for arc_path, name, expected_size in cases:
                arc = BgiArchive(arc_path)
                target = name or arc.entries[0].name
                raw = arc.read_bytes(target)
                hdr = parse_cbg_header(raw)
                self.assertEqual(hdr.version, 1)
                self.assertIn(hdr.bpp, (8, 24, 32))
                if expected_size is not None:
                    self.assertEqual((hdr.width, hdr.height), expected_size)
                out_png = tmp_dir / f"{arc_path.stem}_{target}.png"
                export_cbg_png(raw, out_png)
                with Image.open(out_png) as im:
                    self.assertEqual(im.size, (hdr.width, hdr.height))

    def test_bw_audio_and_ogg_streams(self) -> None:
        # SE: 不循环
        a3000 = BgiArchive(GAME_DIR / "Archive" / "data03000.arc")
        bw_se, _, info_se = extract_ogg(a3000.read_bytes(a3000.entries[0].name), validate=True)
        self.assertEqual(bw_se.loop_flag, 0)
        self.assertEqual(bw_se.format_tag, 3)
        self.assertEqual(info_se["vorbis_version"], 0)
        self.assertTrue(info_se["has_eos"])

        # BGM: 常规曲目循环，短 jingle 不循环
        a5000 = BgiArchive(GAME_DIR / "Archive" / "data05000.arc")
        bw_bgm, _, info_bgm = extract_ogg(a5000.read_bytes("FL_bgm_01"), validate=True)
        self.assertEqual(bw_bgm.loop_flag, 1)
        self.assertEqual(bw_bgm.sample_rate, 44100)
        self.assertEqual(bw_bgm.channels, 2)
        self.assertTrue(info_bgm["has_eos"])

        bw_jingle = parse_bw_header(a5000.read_bytes("fl_bgm_30", limit=64))
        self.assertEqual(bw_jingle.loop_flag, 0)

        # Voice: 抽样校验
        a4001 = BgiArchive(GAME_DIR / "Archive" / "data04001.arc")
        bw_v, _, info_v = extract_ogg(a4001.read_bytes(a4001.entries[0].name), validate=True)
        self.assertEqual(bw_v.channels, 1)
        self.assertEqual(info_v["vorbis_version"], 0)
        self.assertTrue(info_v["has_eos"])

        # system.arc 内嵌 DSC+bw
        sys_arc = BgiArchive(GAME_DIR / "system.arc")
        click_dec = decode_dsc(sys_arc.read_bytes("click"))
        bw_click, _, info_click = extract_ogg(click_dec, validate=True)
        self.assertEqual(bw_click.format_tag, 3)
        self.assertTrue(info_click["has_eos"])

    def test_scripts_bcs1_and_bp(self) -> None:
        # framework._bs 110 个导出函数
        sys_arc = BgiArchive(GAME_DIR / "system.arc")
        fw_raw, was_dsc = maybe_decompress_script(sys_arc.read_bytes("framework._bs"))
        self.assertTrue(was_dsc)
        fw_scr = disassemble_bcs1(fw_raw, name="framework._bs", prefer_gbk=False)
        self.assertEqual(len(fw_scr.header.exports), 110)

        # setup (0x3F 双词 SCOPE_MARK 验证)
        a1300 = BgiArchive(GAME_DIR / "Archive" / "data01300.arc")
        setup_raw, _ = maybe_decompress_script(a1300.read_bytes("setup"))
        setup_scr = disassemble_bcs1(setup_raw, name="setup", prefer_gbk=False)
        self.assertEqual(setup_scr.trailing_bytes, 0)

        # 汉化剧本 (GBK + CP932 混合解码)
        a1800 = BgiArchive(GAME_DIR / "Archive" / "data01800.arc")
        pro_raw, _ = maybe_decompress_script(a1800.read_bytes("a_prologue01"))
        pro_scr = disassemble_bcs1(pro_raw, name="a_prologue01", prefer_gbk=True)
        self.assertEqual(pro_scr.trailing_bytes, 0)
        self.assertTrue(any("GBK" in insn.comment.upper() for insn in pro_scr.instructions))

        # data01200/op_skip GBK 汉化选项解码 + BCS1 控制流助记符修正验证
        a1200 = BgiArchive(GAME_DIR / "Archive" / "data01200.arc")
        skip_raw, _ = maybe_decompress_script(a1200.read_bytes("op_skip"))
        skip_scr = disassemble_bcs1(skip_raw, name="op_skip", prefer_gbk=True)
        self.assertTrue(any("要跳过序章吗？" in insn.comment for insn in skip_scr.instructions))
        self.assertEqual(BCS1_OP_NAMES[0x10], "PUSH_SP")
        self.assertEqual(BCS1_OP_NAMES[0x11], "POP_SP")
        self.assertEqual(BCS1_OP_NAMES[0x18], "JMP")
        self.assertEqual(BCS1_OP_NAMES[0x19], "JCC")
        self.assertEqual(BCS1_OP_NAMES[0x1A], "CALL")
        self.assertEqual(BCS1_OP_NAMES[0x1B], "RET")

        # sysprg2.arc/nudeprcs._bp 与 sysprg.arc/scrslct._bp (含 GBK/CP932 混合字符串)
        sp2 = BgiArchive(GAME_DIR / "sysprg2.arc")
        nude_raw, _ = maybe_decompress_script(sp2.read_bytes("nudeprcs._bp"))
        nude_bp = disassemble_bp(nude_raw, name="nudeprcs._bp")
        syscalls = {i.syscall_id for i in nude_bp.instructions if i.syscall_id is not None}
        self.assertIn(0xA024, syscalls)
        self.assertIn(0x9056, syscalls)
        self.assertIn(0x9058, syscalls)

        sp = BgiArchive(GAME_DIR / "sysprg.arc")
        file_raw, _ = maybe_decompress_script(sp.read_bytes("file._bp"))
        file_bp = disassemble_bp(file_raw, name="file._bp")
        self.assertGreater(len(file_bp.instructions), 0)

        scrslct_raw, _ = maybe_decompress_script(sp.read_bytes("scrslct._bp"))
        scrslct_bp = disassemble_bp(scrslct_raw, name="scrslct._bp", prefer_gbk=True)
        self.assertTrue(any("阳茉莉" in insn.comment for insn in scrslct_bp.instructions))
        self.assertTrue(any("指定されたビットマップ" in insn.comment for insn in scrslct_bp.instructions))

    def test_uncensored_patch_and_nude_pairs_reproducible(self) -> None:
        rep = verify_uncensored_patch_and_nude_pairs(GAME_DIR)
        self.assertEqual(rep["overlap_count"], 470)
        self.assertEqual(len(rep["dimension_mismatches"]), 7)
        self.assertEqual(rep["vfs_priority_winner_for_hiev08_a01"], "data02150.arc.bak")
        self.assertGreater(rep["sample_pixel_diff_hiev08_a01"]["max_rgb_diff"], 100)
        self.assertEqual(rep["data02100_h_pairs"], 549)
        self.assertEqual(rep["data02100_orphan_h"], [])

    def test_transcoded_ogv_video(self) -> None:
        self.assertTrue(OGV_PATH.is_file(), f"未找到转码视频: {OGV_PATH}")
        _, ffprobe_exe = find_ffmpeg_pair()
        info = probe_media(ffprobe_exe, OGV_PATH)
        self.assertTrue(info["probed"])
        self.assertEqual(info["format_name"], "ogg")
        self.assertEqual(info["video"]["codec_name"], "theora")
        self.assertEqual(info["video"]["width"], 1280)
        self.assertEqual(info["video"]["height"], 720)
        self.assertEqual(info["video"]["pix_fmt"], "yuv420p")
        self.assertEqual(info["audio"]["codec_name"], "vorbis")
        self.assertEqual(info["audio"]["sample_rate"], "44100")
        self.assertEqual(info["audio"]["channels"], 2)
        self.assertGreater(info["duration"], 90.0)
        self.assertLess(info["duration"], 93.0)

    def test_gdb_sdc_decode_and_structure(self) -> None:
        gdb_path = GAME_DIR / "BGI.gdb"
        self.assertTrue(gdb_path.is_file(), f"未找到 {gdb_path}")
        sdc_hdr, db, raw_gdb = load_gdb_file(gdb_path)
        self.assertEqual(sdc_hdr.key, 0xBA)
        self.assertEqual(sdc_hdr.uncompressed_size, len(raw_gdb))
        self.assertEqual(db.magic, "BURIKO GDB 3.00")
        self.assertEqual(db.project_code, "HAROKJSLTE")
        self.assertEqual(len(db.labels), 73)
        self.assertEqual(len(db.resources), 2705)
        self.assertEqual(len(db.scripts), 181)
        self.assertEqual(db.scripts[0].name, "Setup")
        self.assertEqual(db.scripts[-1].name, "Main")

    def test_cbg_fast_dll_matches_python(self) -> None:
        for arc_name, entry in [
            ("data02020.arc", None),
            ("data02000.arc", None),
            ("data02100.arc", "hi01wa_n"),
        ]:
            arc = BgiArchive(GAME_DIR / "Archive" / arc_name)
            raw = arc.read_bytes(entry or arc.entries[0].name)
            hdr_py, px_py = decode_cbg_py(raw)
            hdr_c, px_c = decode_cbg(raw, use_fast_dll=True)
            self.assertEqual(hdr_c, hdr_py)
            self.assertEqual(px_c, px_py)

    @unittest.skipUnless(GODOT_EXE.is_file() and GODOT_VERIFY_DIR.is_dir(), "未找到 Godot 4.3 或验证工程")
    def test_godot_phase1_headless_verify(self) -> None:
        proc = subprocess.run(
            [str(GODOT_EXE), "--headless", "--path", str(GODOT_VERIFY_DIR)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, f"Godot 退出码非 0:\n{proc.stdout}\n{proc.stderr}")
        self.assertIn("PASS_FONT:", proc.stdout)
        self.assertIn("PASS_NUDE_PAIR:", proc.stdout)
        self.assertIn("VIDEO_FRAME_5: is_playing=true", proc.stdout)
        self.assertIn("video_tex_size=(1280, 720)", proc.stdout)
        self.assertIn("PHASE1_GODOT_VERIFY_OK", proc.stdout)


class TestPhase1EdgeCasesAndErrors(unittest.TestCase):
    """异常输入、边界条件与关键算法不变量单元测试（不依赖游戏目录）。"""

    def test_bgi_key_step_ffff_carry_invariant(self) -> None:
        # 构造一个使 v0 & 0xFFFF == 0xFFFF 的密钥：
        # low16 = (-pow(20021, -1, 65536)) % 65536 -> 20021 * low16 ≡ 0xFFFF (mod 65536)
        # 验证返回值 v1 & 0xFF 必须在 +1 进位之前取低 8 位！
        low16 = (-pow(20021, -1, 65536)) % 65536
        key = 0x12340000 | low16
        v0 = 20021 * (key & 0xFFFF)
        self.assertEqual(v0 & 0xFFFF, 0xFFFF)
        v1 = 20021 * (key >> 16) + 346 * (key & 0xFFFF) + (v0 >> 16)
        next_key, byte_val = bgi_key_step(key)
        self.assertEqual(byte_val, v1 & 0xFF)
        # 检查低 16 位加 1 产生向 bit16 的进位
        self.assertEqual(next_key & 0xFFFF, 0x0000)
        self.assertEqual((next_key >> 16) & 0xFFFF, ((v1 & 0xFFFF) + 1) & 0xFFFF)

    def test_invalid_arc_and_dsc_and_cbg(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bad_arc = Path(tmp) / "bad.arc"
            bad_arc.write_bytes(b"NOT_A_BGI_ARCHIVE_1234")
            with self.assertRaises(ValueError):
                BgiArchive(bad_arc)

        with self.assertRaises(ValueError):
            parse_dsc_header(b"BAD_MAGIC" + b"\x00" * 32)
        with self.assertRaises(ValueError):
            decode_dsc(b"DSC FORMAT 1.00\x00" + b"\x00" * 16)
        # 恶意超大 dec_count (> uncompressed_size) 应立即拒绝而非死循环
        bad_dec_hdr = b"DSC FORMAT 1.00\x00" + struct.pack("<IIII", 0, 10, 0xFFFFFFFF, 0) + b"\x00" * 512
        with self.assertRaises(ValueError):
            decode_dsc(bad_dec_hdr)
        with self.assertRaises(ValueError):
            inspect_dsc_image_header(b"NOT_A_BMP" + b"\x00" * 64)
        with self.assertRaises(ValueError):
            parse_cbg_header(b"NOT_A_CBG" + b"\x00" * 48)

    def test_cbg_rle_truncation_raises(self) -> None:
        # 构造合法频率表 (symbol 0x05 -> 1次, sum=1) 但 RLE 拷贝越界，不能静默缩短 raw
        freq_raw = bytearray(256)
        freq_raw[5] = 1
        # key=0 时 bgi_key_step(0) 先输出 0，随后再 +1，需按 bgi_key_step 加密
        from bgi_dsc import bgi_key_step
        k = 0
        enc_freq = bytearray(256)
        s_acc = 0
        x_acc = 0
        for i, b in enumerate(freq_raw):
            k, kb = bgi_key_step(k)
            enc_freq[i] = (b + kb) & 0xFF
            s_acc = (s_acc + b) & 0xFF
            x_acc ^= b
        # 构造 1x1 8bpp CBG，rle_size=1，仅 1 字节但 varint=5 表示需要后续 5 字节非零数据 -> 应报越界错
        hdr = b"CompressedBG___\x00" + struct.pack(
            "<HHIIIIIIBBH", 1, 1, 8, 0, 0, 1, 0, 256, s_acc, x_acc, 1
        )
        # 仅 1 符号时为 0-bit 退化树，直接消费 0 bit 填充 rle_buf=[5]
        with self.assertRaises(ValueError):
            decode_cbg(hdr + bytes(enc_freq))

    @unittest.skipUnless(GAME_DIR.is_dir(), "未找到目标游戏目录")
    def test_cbg_checksum_mismatch_raises(self) -> None:
        a2000 = BgiArchive(GAME_DIR / "Archive" / "data02000.arc")
        raw = bytearray(a2000.read_bytes(a2000.entries[0].name))
        # 破坏头部 sum_check (offset 40..44)
        raw[40] ^= 0xFF
        with self.assertRaises(ValueError):
            decode_cbg(bytes(raw))

    def test_audio_and_script_error_paths(self) -> None:
        with self.assertRaises(ValueError):
            parse_bw_header(b"short")
        with self.assertRaises(ValueError):
            parse_bw_header(b"\x40\x00\x00\x00XXXX" + b"\x00" * 56)
        with self.assertRaises(ValueError):
            validate_ogg_stream(b"RIFF....WAVE")
        # 缺少 Vorbis 标识包
        with self.assertRaises(ValueError):
            validate_ogg_stream(b"OggS" + b"\x00" * 30)

        # 非法 BCS1 / 未知操作码
        with self.assertRaises(ValueError):
            parse_bcs1_header(b"InvalidMagic")
        fake_bcs1 = (
            b"BurikoCompiledScriptVer1.00\x00"
            + struct.pack("<III", 12, 0, 0)
            + struct.pack("<I", 0x9999)
        )
        with self.assertRaises(ValueError):
            disassemble_bcs1(fake_bcs1)

        # 截断的 _bp
        with self.assertRaises(ValueError):
            disassemble_bp(struct.pack("<4I", 16, 1, 0, 0) + b"\x02")

        # SDC 异常头与截断
        with self.assertRaises(ValueError):
            parse_sdc_header(b"BAD_SDC")
        bad_sdc = b"SDC FORMAT 1.00\x00" + struct.pack("<4I", 0, 100, 10, 0)
        with self.assertRaises(ValueError):
            decode_sdc(bad_sdc)

    @unittest.skipUnless(GAME_DIR.is_dir(), "未找到目标游戏目录")
    def test_ogg_crc32_tamper_detection(self) -> None:
        a3000 = BgiArchive(GAME_DIR / "Archive" / "data03000.arc")
        _, ogg_bytes, info = extract_ogg(a3000.read_bytes(a3000.entries[0].name), validate=True)
        self.assertTrue(info["crc32_verified"])
        # 篡改末字节应触发 Ogg CRC32 校验失败（同时验证 C DLL 与纯 Python 回退路径）
        tampered = bytearray(ogg_bytes)
        tampered[-1] ^= 0x01
        with self.assertRaises(ValueError):
            validate_ogg_stream(bytes(tampered), check_crc=True)

        import bgi_audio
        orig_dll = bgi_audio._AUDIO_FAST_DLL
        try:
            bgi_audio._AUDIO_FAST_DLL = None
            py_info = validate_ogg_stream(ogg_bytes, check_crc=True)
            self.assertTrue(py_info["crc32_verified"])
            self.assertTrue(py_info["has_eos"])
            with self.assertRaises(ValueError):
                validate_ogg_stream(bytes(tampered), check_crc=True)
        finally:
            bgi_audio._AUDIO_FAST_DLL = orig_dll

    def test_gdb_zero_scripts_boundary(self) -> None:
        from bgi_gdb import parse_gdb
        raw_gdb = bytearray(0x10042C)
        raw_gdb[:16] = b"BURIKO GDB 3.00\x00"
        struct.pack_into("<II", raw_gdb, 16, len(raw_gdb), 0)
        raw_gdb[0xD0 : 0xD0 + 4] = b"TEST"
        # res_count = 0 (at 0x100424), script_count = 0 (at 0x100428)
        db = parse_gdb(bytes(raw_gdb))
        self.assertEqual(db.project_code, "TEST")
        self.assertEqual(db.resources, [])
        self.assertEqual(db.scripts, [])

    @unittest.skipUnless(GAME_DIR.is_dir(), "未找到目标游戏目录")
    def test_cbg_truncated_bitstream_raises(self) -> None:
        a2020 = BgiArchive(GAME_DIR / "Archive" / "data02020.arc")
        raw = a2020.read_bytes(a2020.entries[0].name)
        hdr = parse_cbg_header(raw)
        trunc = raw[: 48 + hdr.enc_freq_size + 10]
        with self.assertRaises(ValueError):
            decode_cbg_py(trunc)
        with self.assertRaises(ValueError):
            decode_cbg(trunc, use_fast_dll=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
