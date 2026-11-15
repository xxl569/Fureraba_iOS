# 《フレラバ 〜Friend to Lover〜 HD Renewal Edition》阶段一协议解析与资产审计报告

> 项目目录：`U:\anti\projects\Fureraba_iOS\`
> 目标游戏目录：`U:\anti\projects\game\`（总活跃资产约 4.17 GB，严禁拷入 Git 仓库或 `.pck`）
> 中间提取、抽样 PNG/OGG 与转码视频目录：`U:\anti\temp\Fureraba_iOS\`
> 原始资产审计 JSON：`U:\anti\temp\Fureraba_iOS\phase1_asset_audit.json`

---

## 1. 归档协议 (`ARC v1 / v2`) 与 VFS 优先级审计

全量扫描 `U:\anti\projects\game\` 及其 `Archive\` 子目录下共 **45 个 `.arc` / `.arc.bak` 归档**，全部结构零损坏、索引尾部扩展字全为 `0`：

1. **`PackFile    ` (ARC v1，32 字节索引项)**：共 5 个归档，全部位于脚本/系统层：
   - `data01000.arc` (5), `data01200.arc` (8), `data01300.arc` (6), `sysprg.arc` (74), `system.arc` (8)。
2. **`BURIKO ARC20` (ARC v2，128 字节索引项)**：共 40 个归档：
   - 根目录：`sysgrp.arc` (415), `sysprg2.arc` (1)
   - `Archive\`：`data01210`、`data01350`、`data01800~01890`、`data02000~02910`、`data03000~05100`（含 `data02150.arc.bak`）。
3. **VFS 挂载优先级 (`tools/bgi_arc.py::BgiVfs`)**：
   - `system.arc/ipl._bp` 按 `Archive\data0????.arc` 升序扫描，根目录 `sysprg2.arc` 优先于 `sysprg.arc`；`Archive\` 下小序号补丁归档优先于大序号主归档。
   - 开启 `include_data02150_bak=True` 后，VFS 共挂载 `27,811` 个唯一键，其中 `486` 个存在同名覆盖（含 `data02150.arc.bak` 全部 `470` 条 CG 覆盖 `data02200.arc`，以及 `system.arc` 覆盖 `data03000/04800` 的 `6` 条 DSC 压缩系统音效、`data03000` 与 `data05100` 重叠 `5` 条、`data04001` 与 `data04012` 重叠 `5` 条）。

### 1.1 `data02150.arc.bak` vs `data02200.arc` 重名 CG 实测差异

对 `data02150.arc.bak` 全部 `470` 条与 `data02200.arc` 同名条目逐一比对 CBG 头部及抽样 15 组全尺寸 RGB 像素差：
- **BPP 格式差异**：`469/470` 为 `2150=32bpp RGBA`（Alpha 全为不透明 `255`）对比 `2200=24bpp RGB`；`1/470` 为 `24 vs 24`。
- **实际像素内容差异**：抽样 `hiev08/11/15/16`、`miev11/14`、`riev13/16/18`、`yuev12/14/15/18/19` 均存在明显内容差异（通道绝对差峰值 `116..255`，差异>30 的核心去码区占 `0.09%~9.85%`），确认 `data02150.arc.bak` 确为「美版无码 CG 覆盖包」（`无&有码切换.bat` 即通过重命名 `data02150.arc.bak <-> data02150.arc` 控制是否生效）。
- **高分辨率差分异常风险**：有 **7 个条目 (`miev10_a05_9` ~ `miev10_a11_9`) 在两边分辨率不一致**：`data02150.arc.bak` 为 **`2048x1152`**，而 `data02200.arc` 为 **`1536x864`**（4:3 倍缩放差异）。阶段二渲染引擎在执行带平移/缩放坐标的 CG 时，必须按原始基准比例或图像实际尺寸做归一化适配，避免无码包裁切偏移。

---

## 2. `DSC FORMAT 1.00` 解压协议与裸位图头验证 (`tools/bgi_dsc.py`)

### 2.1 算法与 `bgi_key_step` 进位边界修正
- 验证全部 `290` 个 DSC 脚本与 `4,864` 个 CBG 频数表头均 100% 满足 Kraft 和检验（`bad = 0`）。
- **关键算法边界**：在 LCG 密钥步进 `bgi_key_step(key)` 中，`data01350.arc/roll_hi` 第 81 步及 34 个 CBG 头触发了 `(v0 & 0xFFFF) == 0xFFFF`；返回值字节 **`v1 & 0xFF` 必须在低 16 位 `+1` 进位前提取**，否则解压流即错位崩坏。
- **Bit Buffer 优化**：消耗比特后必须执行 `bit_buf &= (1 << bits_left) - 1` 掩码截断，避免 Python 大整数膨胀引发 $O(N^2)$ 性能退化。

### 2.2 DSC 图像包格式确认与 PNG 导出验证
全量验证 `sysgrp.arc` (415)、`data02400.arc` (91)、`data02600.arc` (90)、`data02700.arc` (16)、`data02810.arc` (29) 共 **641 个 DSC 图像**：
- **100% 为标准无压缩 Windows BMP (`BM` 头，offset `0x36 = 54`，`compression = 0`，`24bpp BGR` 或 `32bpp BGRA`)**。
- 已导出 15 张涵盖全部 5 个 DSC 图像归档的 PNG 样本至 `U:\anti\temp\Fureraba_iOS\samples\dsc\`（如 `sysgrp_arc__sgusdtwnd990001.png` `1280x720 32bpp`、`data02810_arc__talkwindow.png` `3390x71 32bpp`、`data02600_arc__himari_mail_01.png` `1280x720 32bpp` 等）。

---

## 3. `CompressedBG___` (`CBG v1`) 解码验证 (`tools/bgi_cbg.py` + `tools/bgi_fast.c`)

全量审计 `9` 个 CBG 归档共计 **4,864 个图像条目**，已通过 C 加速解码器 `bgi_fast.dll`（与纯 Python 参考实现 `decode_cbg_py` 像素逐字节一致）完成**全库 4,864 张图像的完整像素级解码**（含频率表解密、`sum_check`/`xor_check`、Huffman、RLE 与逆向空间差分滤波），**解码失败数 `0`、尺寸/通道异常数 `0`**：
- **全部为 `CBG v1` (`version == 1`)**，未发现 `v2`；覆盖 `8bpp` 灰度遮罩、`24bpp RGB` 与 `32bpp RGBA`（其中 `data02020.arc` 56 个过场转场遮罩 `effect01..56` 全部为 `8bpp`）。
- **各归档审计汇总**：
  - `data02000.arc` (169 条，24bpp=153 / 32bpp=16，最大 `fl_bg_01a_9` `2248x1352`)
  - `data02020.arc` (56 条，8bpp=56，`1280x720`)
  - `data02100.arc` (2,938 条，32bpp=2,938，最大 `mi01_k001` `2155x1220`；含 549 对 `_h` 透视差分)
  - `data02150.arc.bak` (470 条，32bpp=469 / 24bpp=1，最大 `hiev15_a05_9` `2048x1152`)
  - `data02200.arc` (1,098 条，24bpp=1,097 / 32bpp=1，最大 `hiev09_a11_9` `2048x1152`)
  - `data02210.arc` (119 条，24bpp=119，`480x90` CG 缩略图)
  - `data02300.arc` (7 条，32bpp=7，`1280x720` Eyecatch)
  - `data02800.arc` (2 条，24bpp=2，含 `1280x768` `smee_logo`)
  - `data02910.arc` (5 条，32bpp=5，含 4 张 **`1280x11362` 超长 Staff Roll 卷轴图** `fl_roll_hi/mi/ri/yu`)
- 已全部抽样导出 PNG 至 `U:\anti\temp\Fureraba_iOS\samples\cbg\`（含 `fl_roll_hi`、`fl_roll_yu` 1280x11362 完整导出并通过 Pillow 尺寸校验）。
- **性能提示**：`1280x11362 32bpp` 约 58MB 原始像素，在纯 Python 空间差分解码下耗时约 45~50 秒；阶段二 BYOA 在 iOS 客户端加载建议通过原生插件/预转码/缓存或优化解码避免卡顿，另注意 iOS GPU 单张纹理尺寸上限（通常 4096/8192/16384，需对 `11362px` 高度超长图做分片裁剪或运行时分段加载）。

---

## 4. `bw  ` 音频头与 Ogg Vorbis 验证 (`tools/bgi_audio.py`)

全量扫描 `16` 个音频归档（`data03000`、`data04001~04012`、`data04800`、`data05000`、`data05100`）共 **22,501 条音频** + `system.arc` 内置 6 条 DSC+`bw  ` 音频（全部满足 `header_size(64) + ogg_size == entry.size`，异常数 `0`）：
- **格式与采样率**：全库 `format_tag` 100% 为 `3`（Ogg Vorbis）；Voice (`data04001~04012`, `data04800`) 全部为 `44100 Hz`（以单声道为主，偶有 2ch）；SE (`data03000`) 覆盖 `11025/22050/44100/48000 Hz`；BGM (`data05000`) 全部为 `44100 Hz 立体声`。
- **循环字段审计结论**：
  - `data05000.arc` (37 首 BGM)：`loop_flag=1` 共 32 首（常规循环曲目），`loop_flag=0` 共 5 首（`fl_bgm_27b`、`fl_bgm_30~33` 等短 Jingle/ED）。
  - `data05100.arc` (157 条循环音效/环境音)：`loop_flag=1` 共 153 条，`loop_flag=0` 共 4 条。
  - `data03000.arc`、`data04001~04012.arc`、`data04800.arc`、`system.arc` 内置音频：`loop_flag` 全部为 `0`。
  - **重要发现：全库 22,501 条音频中 `loop_start` / `loop_end` (`fields[7..11]`) 全部为 `0`（`nonzero_loop_offsets = 0`）**。即本作不依赖采样级区间循环，所有循环 BGM/循环 SE 均采用**整曲首尾无缝循环** (`AudioStreamOggVorbis.loop = true` when `loop_flag == 1`)。
- 对全部 `16` 个音频归档 **22,501 条** + `system.arc` 内置 **6 条**（共计 **22,507 条**）音频流执行全量 `OggS` 页结构、**全页 Ogg CRC32**、Vorbis 三头包（`\x01vorbis` / `\x03vorbis` / `\x05vorbis`）与末尾 `EOS (0x04)` 校验，**校验失败数 `0`**；同时抽样 BGM / Loop SE / SE / Voice 导出 `.ogg` 并通过 `ffmpeg -v error -f null -` 真实 PCM 解码校验无报错。

---

## 5. 开场动画 `friendtolover.mpg` 提取与 `.ogv` 转码验证 (`tools/extract_and_transcode_video.py`)

- **提取源**：`Archive/data02900.arc/friendtolover.mpg`（105,488,388 bytes；`mpeg1video 1280x720 yuv420p`, `mp2 44100 Hz stereo`, 时长 `91.402s`）。
- **转码产物**：`U:\anti\temp\Fureraba_iOS\movie\friendtolover.ogv`（61,739,535 bytes，约 58.9 MB；已放置于工作区外置临时目录，未进入 Git 仓库）。
- **`ffprobe` 校验实测结果**：
  - 容器格式：`ogg`
  - 视频流：`theora`, `1280x720`, `yuv420p`, `30000/1001 fps` (`29.97 fps`)
  - 音频流：`vorbis`, `44100 Hz`, `2 channels (stereo)`
  - 总时长：`91.402449 s`（与源文件时长 `91.402444 s` 吻合，平均码率 `5,403,753 bps`）。

---

## 6. `BGI.gdb` (`SDC FORMAT 1.00` + `BURIKO GDB 3.00`) 解码与结构审计 (`tools/bgi_gdb.py`)

- **外层封装 (`SDC FORMAT 1.00`)**：32 字节头（魔数 `SDC FORMAT 1.00\x00`、`key=0xba`、`compressed_size=394,997`、`uncompressed_size=3,249,405`、`reserved=0x3066fe`）。经 `bgi_key_step(0xba)` 逐字节减法解密后，采用 BGI LZ77 字节令牌流压缩（`b0 < 0x80` 拷贝 `b0 + 1` 字面量；`b0 >= 0x80` 2 字节回溯 `length=((b0>>3)&0xF)+2, dist=(((b0&7)<<8)|b1)+2`），精确解压至 `3,249,405` 字节。
- **内层数据库 (`BURIKO GDB 3.00`)**：
  1. `0x0000..0x0424`：工程全局配置头（工程代号 `HAROKJSLTE`、`header_count=159`，含默认角色名与字体 `ＭＳ ゴシック` 预设）；
  2. `0x0424..0x100424`（1 MB 固定槽）：73 条 40 字节标签/事件索引记录（`<2I32s>`）；
  3. `0x100424..0x10709c`：全作 **2,705 个资源名字符串池**（`smee_logo` 等）；
  4. `0x10709c..0x3194fd`：**181 个脚本已读位图记录**（`Setup` 至 `Main`，每条 `name\0 + u32 bit_count + ceil(bit_count / 8)` 字节位图，合计 `17,350,407` bits），解析指针严丝合缝抵达文件末尾 `0x3194fd`。

---

## 7. Godot 4.3 运行时基础环境验证 (`godot_verify/`)

使用本地 `Godot_v4.3-stable_win64_console.exe` 在 `--headless` 与 `--rendering-driver opengl3` (`gl_compatibility` / `NVIDIA GeForce GTX 1650`) 两种模式下均实测通过：
1. **`VideoStreamTheora`**：成功加载并播放 `U:\anti\temp\Fureraba_iOS\movie\friendtolover.ogv`，第 5 帧实时解码纹理尺寸 `(1280, 720)`，播放状态正常。
2. **`GalHei.ttf` 字体渲染**：`FontFile.load_dynamic_font` 加载成功，简中（`要跳过序章吗？阳茉莉`）与日文（`フレラバ 〜Friend to Lover〜`）字形度量正常非零。
3. **`nudeprcs._bp` 双层立绘叠加**：加载 `hi01wa_n.png` + `hi01wa_nh.png`（`1280x938`），双层 `TextureRect` 挂载及 `KEY_F12` 状态切换（`modulate.a = 0.0 <-> 1.0`）验证通过。
