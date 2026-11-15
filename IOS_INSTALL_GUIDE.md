# 《フレラバ 〜Friend to Lover〜 HD》iOS TrollStore 安装与使用指南

## 1. 获取签名空壳与本地 3 秒热打包

1. **云端编译 iOS 原生空壳（仅首次或修改 C 原生库时需要）**：
   - 将仓库推送至 GitHub 后，触发 Actions 工作流 `.github/workflows/ios-ipa.yml`；
   - 下载产物 `Fureraba_iOS_TrollStore`，将其中的 `Fureraba_iOS_Shell.zip` 解压出 `Fureraba_iOS.app`，放到 `U:\anti\projects\Fureraba_iOS\build\ios\Fureraba_iOS.app`（`build\.gdignore` 会自动阻止 Godot 扫描空壳目录）。
2. **Windows 本地 3 秒热打包**：
   - 双击运行项目根目录的 `打包TrollStore_PCK与IPA.bat`，或在终端执行：
     ```powershell
     python tools/package_trollstore_ipa.py export-pck --output build/ios/Fureraba_iOS.pck
     python tools/package_trollstore_ipa.py package --app-shell build/ios/Fureraba_iOS.app --pck build/ios/Fureraba_iOS.pck --output build/ios/Fureraba_iOS_TrollStore.ipa
     python tools/package_trollstore_ipa.py verify-ipa --ipa build/ios/Fureraba_iOS_TrollStore.ipa
     ```
3. **通过 TrollStore 安装**：
   - 将 `Fureraba_iOS_TrollStore.ipa` 发送至 iPhone / iPad，使用 TrollStore 安装。

---

## 2. BYOA 外置游戏资产放置说明（首次启动必读）

本应用采用外置资产挂载（BYOA）机制，`.ipa` 安装包内不包含任何 PC 版权资产。请在 iPhone/iPad「文件」App 中打开 **我的 iPhone -> Fureraba_iOS**（应用沙盒 `Documents` 目录），将 PC 原版目录中的以下文件拷贝进去：

- **根目录系统包**：`sysgrp.arc`、`sysprg.arc`、`sysprg2.arc`、`system.arc`、`BGI.gdb`
- **Archive 文件夹**：`Archive/data*.arc`（包含汉化补丁与 `data02150.arc` / `data02150.arc.bak` 无码补丁）
- **中文字体（强烈推荐）**：`GalHei.ttf`（放入 `Documents/` 或 `Documents/font/GalHei.ttf`）
- **转码后的 OP 过场视频**：将 `friendtolover.ogv` 放入 `Documents/movie/friendtolover.ogv`

> **提示**：拷贝完成后无需重启应用，切回游戏界面（触发焦点恢复）或点击「重新扫描资产目录」即可自动挂载进入主界面。

---

## 3. 移动端触控手势与特色功能

- **单指轻触**：推进对白（当 `Auto` 或 `Skip` 开启时，首次轻触仅停止自动/快进，不会误跳过当前对白）。
- **单指右滑**：打开对话历史记录（Backlog）。
- **双指轻触**：隐藏 / 显示底部对白框，方便纯享 CG。
- **三指轻触 / 右上角「透视」按钮**：即时切换原版 `nudeprcs._bp` F12 透视/全裸差分立绘与 CG。
- **设置面板无码开关**：可随时热切换是否优先挂载 `data02150.arc.bak` 高清无码差分（自动清理纹理缓存并重绘当前画面）。
