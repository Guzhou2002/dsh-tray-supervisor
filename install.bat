@echo off
setlocal EnableExtensions
title dsh-autostart 一键安装
echo ==================================================
echo   dsh-autostart 一键安装 —— DeepSeek Harness 托盘守护
echo ==================================================
echo   本脚本会:
echo     1. 检查 Node.js / DeepSeek Harness
echo     2. 复制文件到  %%USERPROFILE%%\.dsh\plugins\dsh-autostart
echo     3. 生成配置 config.ini
echo     4. 可选: 设置开机自启
echo     5. 可选: 立即启动托盘
echo.
echo   ! 每一步都会先问你, 选 N 即跳过该步。
echo --------------------------------------------------
if not exist "%~dp0dsh-tray.ps1" (
  echo [X] 检测到你不是从解压后的文件夹运行。
  echo     请先把整个压缩包解压到文件夹, 再双击 install.bat。
  pause
  exit /b 1
)
choice /c yn /n /m "是否开始安装? [Y/N] "
if errorlevel 2 (
  echo.
  echo 已取消, 什么都没做。
  pause
  exit /b 0
)
echo.

echo [1/5] 检查 Node.js ...
where node >nul 2>&1
if errorlevel 1 (
  echo   [X] 没检测到 Node.js。
  echo       请先安装 Node.js 22 或更高版本: https://nodejs.org/
  echo       装好后重新双击本文件。
  pause
  exit /b 1
)
for /f "delims=" %%v in ('node --version') do echo   [OK] Node.js %%v
echo.

echo [2/5] 检查 DeepSeek Harness ...
set "ENTRY=%APPDATA%\npm\node_modules\@deepseek-ai\dsh\lib\bin.js"
if exist "%ENTRY%" (
  echo   [OK] 已安装 dsh
  goto :havedish
)
echo   [!] 未检测到 dsh。
choice /c yn /n /m "  是否现在自动安装 dsh ? [Y/N] "
if errorlevel 2 (
  echo   已跳过。没有 dsh 无法运行; 稍后可自行执行: npm i -g @deepseek-ai/dsh
  pause
  exit /b 1
)
echo   正在安装, 需要联网, 请稍候...
call npm i -g @deepseek-ai/dsh
if not exist "%ENTRY%" (
  echo   [X] 自动安装失败, 请手动执行: npm i -g @deepseek-ai/dsh
  pause
  exit /b 1
)
echo   [OK] dsh 安装完成
:havedish
echo.

set "TRAYDIR=%USERPROFILE%\.dsh\plugins\dsh-autostart"
echo [3/5] 复制文件到: %TRAYDIR%
choice /c yn /n /m "  是否复制文件? [Y/N] "
if errorlevel 2 (
  echo   已跳过复制。
  goto :skipcopy
)
if not exist "%TRAYDIR%" mkdir "%TRAYDIR%" >nul 2>&1
if not exist "%TRAYDIR%\sounds" mkdir "%TRAYDIR%\sounds" >nul 2>&1
copy /Y "%~dp0dsh-tray.ps1"        "%TRAYDIR%\dsh-tray.ps1"        >nul
copy /Y "%~dp0dsh-tray-hidden.vbs" "%TRAYDIR%\dsh-tray-hidden.vbs" >nul
if exist "%~dp0dsh-logo.png" copy /Y "%~dp0dsh-logo.png" "%TRAYDIR%\dsh-logo.png" >nul
if exist "%~dp0sounds\*.wav" copy /Y "%~dp0sounds\*.wav" "%TRAYDIR%\sounds\" >nul
echo   [OK] 文件已复制
:skipcopy
echo.

echo [4/5] 生成配置 config.ini
choice /c yn /n /m "  是否写入配置? [Y/N] "
if errorlevel 2 (
  echo   已跳过配置。
  goto :skipconf
)
set "LOG=%TRAYDIR%\dsh-web.log"
(
echo # dsh-tray supervisor config
echo node=
echo entry=%ENTRY%
echo webUrl=http://127.0.0.1:3080
echo port=3080
echo logPath=%LOG%
echo pollSec=5
echo logMaxMB=5
)>"%TRAYDIR%\config.ini"
echo   [OK] 配置已写入
:skipconf
echo.

echo [5/5] 开机自启【可选: 不想要就选 N; 装好后也能在托盘菜单里随时开关】
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
choice /c yn /n /m "  是否设置开机自启? [Y/N] "
if errorlevel 2 (
  echo   已跳过自启。
  goto :skipauto
)
> "%STARTUP%\dsh-autostart.vbs" echo set sh = CreateObject("WScript.Shell")
>>"%STARTUP%\dsh-autostart.vbs" echo sh.Run "%TRAYDIR%\dsh-tray-hidden.vbs",0,False
echo   [OK] 已加入开机自启
:skipauto
echo.

choice /c yn /n /m "是否现在启动托盘? [Y/N] "
if errorlevel 2 goto :done
start "" wscript.exe "%TRAYDIR%\dsh-tray-hidden.vbs"
echo   已启动, 请看右下角托盘图标。
:done
echo.
echo ==================================================
echo   流程结束。
echo   - 文件位置: %TRAYDIR%
echo   - 网页界面: http://127.0.0.1:3080
echo   - 卸载请双击同目录的 uninstall.bat
echo ==================================================
echo.
pause
