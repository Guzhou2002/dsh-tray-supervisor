# dsh-autostart

**DeepSeek Harness(dsh) 托盘守护外壳** —— 开机自动在后台把 dsh 跑起来(无黑窗)，右下角常驻托盘图标，可开界面 / 看日志 / 启停重启 / 开关开机自启。

> 编写者：**孤舟蓑笠**　QQ：**578778930**

## 特性
- 无窗口常驻：托盘直接托管 dsh(node) 进程，不弹黑窗
- 崩溃只提示、**不自动重启**（图标变红），可手动重启
- 强制退出：多种方式确保 dsh 进程杀干净、不留后台
- 鉴权网址：自动从日志解析 `?token=` 并可从菜单直接打开
- 开机自启**可开关**（托盘菜单里随时切换）
- XP 音效（关于页/彩蛋触发）
- 托盘菜单含"关于 · 大肥鱼"（内有彩蛋）

## 安装（给使用者）
1. **先解压整个压缩包**到任意文件夹（不要在压缩包里直接双击）
2. 双击 `install.bat`，**每一步按提示选 Y / N**
3. 看到"流程结束"即完成，右下角出现托盘图标

前置：Windows 10/11 + Node.js 22+（脚本会问你是否自动安装 `dsh`）

## 更新
双击 `update.bat`（需 git）：自动 `git pull` → 同步到 `%USERPROFILE%\.dsh\plugins\dsh-autostart` → 重启托盘

## 卸载
双击 `uninstall.bat`，每一步先确认：停托盘 / 关 dsh / 移除自启 / 删目录

## 仓库结构
```
dsh-tray.ps1          托盘主程序(supervisor)
dsh-tray-hidden.vbs   无窗口启动入口
dsh-logo.png          托盘图标
sounds\               XP 音效(感叹号 / 关键性终止)
install.bat           一键安装(每步确认)
uninstall.bat         一键卸载(每步确认)
update.bat            一键更新(git pull + 同步)
安装说明.md / .txt    详细说明(两种格式)
.gitattributes        关键：固定 *.bat/*.ps1 为 CRLF，防止被改成 LF 后无法运行
```

## 注意
- `config.ini` 与本机日志不入库（见 `.gitignore`）
- 修改 `.bat` 请保持 **CRLF 换行 + GBK(cp936) 编码**，否则中文批处理会解析出错

## 许可
自用/学习分享用。Windows XP 系统音效版权归微软所有。
