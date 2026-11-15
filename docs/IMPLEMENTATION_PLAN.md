# 《フレラバ 〜Friend to Lover〜 HD Renewal Edition》iOS (TrollStore) 移植实施计划

> **技术路线（师父拍板方案 B+）**：**Godot 4.3 (`gl_compatibility`) + C GDExtension 原生编解码静态库 (`BgiNative`) + GDScript 栈式虚拟机与交互 UI + BYOA 壳肉分离**
>
> **项目目录**：`U:\anti\projects\Fureraba_iOS\`
> **PC 原盘目录**：`U:\anti\projects\game\`（活跃体积约 4.17 GB，严禁进入 Git 或 `.pck`）
> **外置临时/转码目录**：`U:\anti\temp\Fureraba_iOS\`
> **参考工程与检查点**：`U:\anti\projects\HenPri_iOS\`、[261115.001.md](file:///U:/anti/checkpoints/261115.001.md)

---

## 阶段一：协议勘察、全库资产审计与基础环境验证（已完成）

- [x] **步骤 1.1**：搭建 `U:\anti\projects\Fureraba_iOS\` 基础工具链与 `.gitignore` 隔离规范。
- [x] **步骤 1.2**：打通 `ARC v1/v2`、`DSC FORMAT 1.00`、`CompressedBG___ (CBG v1)`、`bw  ` Ogg 音频、`BGI.gdb (SDC FORMAT 1.00)` 解码，完成全库 4,864 张 CBG 像素级解码与 22,501+6 条 Ogg 流强校验（零失败）。
- [x] **步骤 1.3**：全量扫描 208 个 `BCS1` 脚本与 76 个 `._bp` 模块，产出 Opcode 频次表、混合编码（ASCII/GBK/CP932）统计与 `nudeprcs._bp` F12 透视机制分析。
- [x] **步骤 1.4**：提取并转码 `friendtolover.ogv` 至 `U:\anti\temp\Fureraba_iOS\movie\`，并在本地 Godot 4.3 (`--headless` / `opengl3`) 实测验证 `VideoStreamTheora`、`GalHei.ttf` 与双层透视渲染。

---

## 阶段二：Godot 4.3 主工程搭建与 C GDExtension 原生编解码库 (`BgiNative`)

- [x] **步骤 2.1：Godot 4.3 主工程与 iOS TrollStore 构建骨架**
  - 创建主工程配置文件：`project.godot`（`1280×720` 逻辑画布、`gl_compatibility`、`import_etc2_astc=true`、横屏自适应）、`export_presets.cfg`（排除 `tools/tests/native/temp/*.arc/*.ogv` 等大文件）、`assets/icons/app_icon.png`（`1024×1024`）、`platforms/ios/Entitlements_TrollStore.plist`（严格遵守权限红线）、`.github/workflows/ios-ipa.yml`（含 `macos-latest` 编 `arm64` 静态库与无签名 `.app` 壳）及 `tools/package_trollstore_ipa.py`。
  - **验收标准**：`Godot_v4.3-stable_win64_console.exe --headless --import --quit` 退出码为 `0`。

- [x] **步骤 2.2：纯 C GDExtension 原生库 (`native/bgi_native`) 实现与跨平台构建**
  - 导出 Godot 4.3 官方 `gdextension_interface.h`，在 `native/bgi_native/` 实现纯 C 单例类 `BgiNative`（零外部三方库依赖，同时支持 Windows `.dll` 与 iOS `arm64` `.a` 静态链接）：
    - `mount_game_dir(dir_path, uncensored_mode)`：按 `ipl._bp` 优先级挂载 45 个 ARC v1/v2 归档，`uncensored_mode=true` 时支持自动识别 `data02150.arc` 或 `data02150.arc.bak` 覆盖 `data02200.arc`。
    - `has_entry(name)` / `get_entry_count()` / `list_entries(prefix)`。
    - `extract_raw(name)`：自动剥离 `DSC FORMAT 1.00` 返回原始字节（供脚本/文本/`BGI.gdb` 读取）。
    - `decode_image(name)` / `decode_image_slices(name, max_height)`：统一解码 `CBG v1`（8/24/32bpp）与 `DSC` 内嵌 BMP（24/32bpp）为 Godot `Image`（RGBA8），并对 `1280×11362` 等超长卷轴图提供按 `<=4096px` 自动分片接口防止 iOS 纹理分配失败。
    - `extract_audio_info(name)`：剥离 `0x40` 字节 `bw  ` 头（支持 `system.arc` 外包 `DSC` 再包 `bw  ` 的嵌套音频），返回 `{ogg_bytes, sample_rate, channels, loop_flag}`。
  - **验收标准**：`gcc` 零警告编译 Windows DLL；编写 Godot 测试脚本对比 `BgiNative` 与阶段一 Python 工具链对脚本、CBG、DSC BMP、Ogg 提取的结果 100% 一致，退出码 `0`。

---

## 阶段三：GDScript 核心运行时（BYOA + BGI 栈式字节码 VM + 舞台/音视频/缓存）

- [x] **步骤 3.1：BYOA 资产扫描、GBK 转码表与字体体系**
  - 生成轻量静态 GBK-to-Unicode 映射表（`assets/tables/gbk_to_utf8.bin`）并实现 `scripts/gbk_codec.gd`（支持混合 ASCII/GBK/CP932 智能解码，零乱码）。
  - 实现 `scripts/config_manager.gd` 与 `scripts/bgi_vfs.gd`（多路径扫描：iOS `Documents/`、PC `--game-dir`/`--movie-dir`、`NOTIFICATION_APPLICATION_FOCUS_IN` 自动重扫、无资产时显示中文 BYOA 指引界面）。
  - **验收标准**：Godot `--headless` 测试验证 GBK/CP932 混合解码与 BYOA 路径探测通过。

- [x] **步骤 3.2：BGI 双引擎栈式虚拟机 (\`bgi_vm.gd\` & \`bgi_bp_vm.gd\`)**
  - 实现 `BCS1` 字节码解释器（覆盖阶段一普查出的全部核心 Opcode：栈操作、局部变量/工作内存读写、算术/位运算/比较/逻辑、`JMP/JCC/CALL/RET/CALL_EXTERNAL/SET_RETVAL`、`SCOPE_MARK`、`DEBUG_LINE`、`SYS_*` 系统调用）。
  - 实现 `._bp` 模块轻量指令/配置解析与 `framework._bs` / `function` 导出函数绑定（立绘 `_DrawBS/_FadeBS/_MoveBS`、背景/场景 `_DrawBG/_DrawScene/_ScrollBG`、头像 `_DrawFace`、音频 `_PlayBGM/_FadeBGM/_PlaySE/_PlayVoice`、视频 `_PlayMovie`、等待/震动 `_Wait/_QuakeEx`、选单 `SelectTalk/_Select/_SelectEx` 等）。
  - **验收标准**：在 Godot `--headless` 中挂载真实 `U:\anti\projects\game` 执行 `setup` -> `main` -> `a_prologue01`，成功推进至首句中文台词、立绘与 BGM 调用无报错。

- [x] **步骤 3.3：256 层图元舞台、3 通道音频、\`.ogv\` 视频与字节级 LRU 缓存**
  - 实现 `scripts/bgi_stage.gd`（多图层纹理管理、转场遮罩、超长图分片拼接、`nudeprcs._bp` 双层 `_h` 透视实时切换、`data02150` 异分辨率 CG 归一化适配）。
  - 实现 `scripts/bgi_audio_mgr.gd`（BGM 带 `loop_flag` 无缝循环 + SE + Voice 三通道音量独立控制）。
  - 实现 `scripts/bgi_video_player.gd`（外置 `friendtolover.ogv` 播放与按下起点防误跳过保护）。
  - 实现 `scripts/bgi_cache.gd`（字节级 + 条目数双上限 LRU 淘汰，响应 `NOTIFICATION_OS_MEMORY_WARNING`）。
  - **验收标准**：Godot `--headless` 回归测试验证舞台图层、音频循环标志、`.ogv` 播放及 LRU 超限回收全部通过。

---

## 阶段四：SMEE 强交互系统与 iOS 移动端 UI/触控适配

- [x] **步骤 4.1：主界面、对白框与系统功能面板 (\`main.gd\` / \`ui_panels.gd\`)**
  - 实现适配 `1280×720` 逻辑舞台（自动缩放适配 iPhone 横屏）的对白框（`GalHei.ttf` + 日文字体 Fallback、姓名栏、语音重听）、QuickMenu（Save/Load/QSave/QLoad/Backlog/Auto/Skip/Config/透视开关）。
  - 实现多槽位 Save/Load（含 VM 栈状态、全局/局部标志、舞台图层快照、已读位图）与 Config 设置面板（有码/无码切换、透视模式开关、音量/文字速度）。
  - **验收标准**：Save/Load 序列化往返测试通过，所有 `.gd` 脚本 `--check-only` 零报错。

- [x] **步骤 4.2：SMEE 交互分支（TalkWindow / Topic / Mail）与移动端手势防误触**
  - 联调 `SelectTalk` / 话题选择 / 邮件界面的触控选区点击与分支跳转。
  - 实现 `scripts/mobile_gesture_helper.gd`（沿用 `HenPri_iOS` 经验：`Skip/Auto` 按下即停并吞噬当次手势、过滤 `DEVICE_ID_EMULATION` 派生事件、双指轻点呼出菜单、HUD 透视快捷开关）。
  - **验收标准**：Godot `--headless` 交互与触控回归测试通过（推进、Skip/Auto 按下即停、选项分支跳转、透视切换、Save/Load 恢复）。

---

## 阶段五：全线压力回归、本地 3 秒热打包校验与成品交付

- [x] **步骤 5.1：全线脚本、无码差分与内存压测**
  - 编写并执行全线自动化测试：扫描验证 208 个 `BCS1` 脚本指令覆盖率与关键分支可执行性、抽测 `data02150` 含异分辨率 `miev10_a05_9` 在内的无码 CG 渲染、`data02910` `1280×11362` 卷轴图分片加载与 LRU 内存上限控制。
  - **验收标准**：全部自动化测试套（Python + Godot `--headless`）100% 通过。

- [x] **步骤 5.2：本地 \`.pck\` 导出、TrollStore 打包校验与使用指南**
  - 编写 [IOS_INSTALL_GUIDE.md](file:///U:/anti/projects/Fureraba_iOS/IOS_INSTALL_GUIDE.md) 与本地一键打包脚本 `打包TrollStore_PCK与IPA.bat`。
  - 实测运行 `tools/package_trollstore_ipa.py export-pck` 导出纯净 `Fureraba_iOS.pck` 并校验 0 资产泄露；使用模拟 `.app` 壳验证 `package` 与 `verify-ipa` 全项体检（UNIX `0755` 权限位、`Entitlements_TrollStore.plist` 合规、`UIFileSharingEnabled`、`.pck` 命名一致）。
  - **验收标准**：`git status -u` 洁净无大文件泄露，全部测试与打包校验退出码 `0`。
