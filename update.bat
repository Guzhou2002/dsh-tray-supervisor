@echo off
setlocal EnableExtensions
title dsh-autostart 更新
echo ==================================================
echo   dsh-autostart 更新
echo ==================================================
set "TRAYDIR=%USERPROFILE%\.dsh\plugins\dsh-autostart"
where git >nul 2>&1
if errorlevel 1 (
  echo [X] 没检测到 git。请先安装 Git for Windows 再更新。
  pause
  exit /b 1
)
choice /c yn /n /m "是否从 GitHub 拉取最新版并更新? [Y/N] "
if errorlevel 2 exit /b 0
echo [1/3] git pull ...
git -C "%~dp0" pull --ff-only
if errorlevel 1 (
  echo [!] git pull 失败。若你不是 clone 的仓库, 请直接下载新版 zip 解压安装。
)
echo [2/3] 复制到 %TRAYDIR% ...
if not exist "%TRAYDIR%" mkdir "%TRAYDIR%" >nul 2>&1
if not exist "%TRAYDIR%\sounds" mkdir "%TRAYDIR%\sounds" >nul 2>&1
copy /Y "%~dp0dsh-tray.ps1"        "%TRAYDIR%\dsh-tray.ps1"        >nul
copy /Y "%~dp0dsh-tray-hidden.vbs" "%TRAYDIR%\dsh-tray-hidden.vbs" >nul
if exist "%~dp0dsh-logo.png" copy /Y "%~dp0dsh-logo.png" "%TRAYDIR%\dsh-logo.png" >nul
if exist "%~dp0sounds\*.wav" copy /Y "%~dp0sounds\*.wav" "%TRAYDIR%\sounds\" >nul
echo [3/3] 重启托盘 ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'dsh-tray.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
start "" wscript.exe "%TRAYDIR%\dsh-tray-hidden.vbs"
echo.
echo 更新完成。
pause