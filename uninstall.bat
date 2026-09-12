@echo off
setlocal EnableExtensions
title dsh-autostart 卸载
echo ==================================================
echo   dsh-autostart 卸载
echo ==================================================
set "TRAYDIR=%USERPROFILE%\.dsh\plugins\dsh-autostart"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
echo   将要执行:
echo     1. 停止正在运行的托盘
echo     2. 可选: 关闭正在运行的 dsh
echo     3. 移除开机自启
echo     4. 删除目录  %TRAYDIR%
echo.
echo   ! 每一步都会先问你, 选 N 即跳过该步。
echo --------------------------------------------------
choice /c yn /n /m "是否开始卸载? [Y/N] "
if errorlevel 2 (
  echo.
  echo 已取消, 什么都没动。
  pause
  exit /b 0
)
echo.

choice /c yn /n /m "1) 停止托盘进程? [Y/N] "
if errorlevel 2 (
  echo   已跳过。
  goto :skipstop
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'dsh-tray.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo   已尝试停止托盘。
:skipstop
echo.

choice /c yn /n /m "2) 同时关闭正在运行的 dsh? [Y/N] "
if errorlevel 2 (
  echo   已跳过。dsh 会继续在后台运行。
  goto :skipdsh
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'deepseek-ai' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo   已尝试关闭 dsh。
:skipdsh
echo.

choice /c yn /n /m "3) 移除开机自启? [Y/N] "
if errorlevel 2 (
  echo   已跳过。
  goto :skipauto
)
if exist "%STARTUP%\dsh-autostart.vbs" del /f /q "%STARTUP%\dsh-autostart.vbs"
echo   已移除开机自启。
:skipauto
echo.

choice /c yn /n /m "4) 删除文件目录? [Y/N] "
if errorlevel 2 (
  echo   已跳过。文件保留在 %TRAYDIR%
  goto :skipdel
)
if exist "%TRAYDIR%" rmdir /s /q "%TRAYDIR%"
echo   已删除目录。
:skipdel
echo.
echo ==================================================
echo   卸载流程结束。
echo ==================================================
echo.
pause
