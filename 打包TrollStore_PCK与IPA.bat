@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo [1/3] 导出 Godot .pck 资源包...
python tools\package_trollstore_ipa.py export-pck --output build\ios\Fureraba_iOS.pck
if errorlevel 1 goto :err

if not exist "build\ios\Fureraba_iOS.app" (
    echo [提示] 未找到 build\ios\Fureraba_iOS.app 空壳，仅完成了 .pck 导出。
    echo 请先从 GitHub Actions 下载 Fureraba-iOS-AppShell 并解压至 build\ios\Fureraba_iOS.app 后再打包 .ipa。
    pause
    exit /b 0
)

echo [2/3] 注入 .pck 并使用 ldid 重签 TrollStore .ipa...
python tools\package_trollstore_ipa.py package --app-shell build\ios\Fureraba_iOS.app --pck build\ios\Fureraba_iOS.pck --output build\ios\Fureraba_iOS_TrollStore.ipa
if errorlevel 1 goto :err

echo [3/3] 校验最终 .ipa 结构与权限...
python tools\package_trollstore_ipa.py verify-ipa --ipa build\ios\Fureraba_iOS_TrollStore.ipa
if errorlevel 1 goto :err

echo [完成] 已成功生成 build\ios\Fureraba_iOS_TrollStore.ipa !
pause
exit /b 0

:err
echo [失败] 打包过程出现错误，请检查上方输出日志。
pause
exit /b 1
