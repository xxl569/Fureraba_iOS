@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Fureraba HD - Windows Trial Launcher

echo ======================================================================
echo   Fureraba -Friend to Lover- HD Windows Trial (Godot 4.3)
echo   Mode   : GL Compatibility (1280x720 Windowed)
echo   Assets : U:\anti\projects\game
echo   Movie  : U:\anti\temp\Fureraba_iOS\movie\friendtolover.ogv
echo ======================================================================
echo.

set "GODOT_BIN="
if exist "%~dp0tools\godot\Godot_v4.3-stable_win64_console.exe" set "GODOT_BIN=%~dp0tools\godot\Godot_v4.3-stable_win64_console.exe"
if "%GODOT_BIN%"=="" if exist "%~dp0..\HenPri_iOS\tools\godot\Godot_v4.3-stable_win64_console.exe" set "GODOT_BIN=%~dp0..\HenPri_iOS\tools\godot\Godot_v4.3-stable_win64_console.exe"
if "%GODOT_BIN%"=="" if exist "%~dp0tools\godot\Godot_v4.3-stable_win64.exe" set "GODOT_BIN=%~dp0tools\godot\Godot_v4.3-stable_win64.exe"
if "%GODOT_BIN%"=="" if exist "%~dp0..\HenPri_iOS\tools\godot\Godot_v4.3-stable_win64.exe" set "GODOT_BIN=%~dp0..\HenPri_iOS\tools\godot\Godot_v4.3-stable_win64.exe"

if "%GODOT_BIN%"=="" (
    echo [ERROR] Godot 4.3 Windows executable not found.
    pause
    exit /b 1
)

echo [INFO] Launching: %GODOT_BIN%
echo [TIP] Left-click to advance dialogue, right-click to toggle UI.
echo.

"%GODOT_BIN%" --path "." scenes/main.tscn %*
if errorlevel 1 (
    echo.
    echo [ERROR] Godot exited with code %errorlevel%
    pause
    exit /b %errorlevel%
)
