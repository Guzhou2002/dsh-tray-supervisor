# dsh-tray-supervisor 🐳

**给 DeepSeek Harness(dsh) 套一个"大肥鱼"右下角托盘。**

[![Release](https://img.shields.io/github/v/release/Guzhou2002/dsh-tray-supervisor?color=4D6BFE&label=release)](../../releases)
[![Stars](https://img.shields.io/github/stars/Guzhou2002/dsh-tray-supervisor?color=4D6BFE)](../../stargazers)
[![License](https://img.shields.io/badge/license-MIT-2EA44F)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6)](#)

> 编写者：**孤舟蓑笠**　QQ：**578778930**

---

## 它解决什么

`Deepseek-harness web` 每次都要开终端、敲命令、不敢关闭黑窗口?这个托盘外壳帮你:

- **开机自动在后台把 dsh 跑起来**,全程**无黑窗命令行窗口**
- **右下角一个托盘图标**,双击就打开界面,右键就是全部操作
- **崩溃看得见**:dsh 意外退出时图标变红 + 气泡提示
- **强退杀得干净**:不留后台 node 进程占端口
- **鉴权不用手敲**:自动从日志里揪出 `?token=...` 网址,菜单一点直接进
- **带版本校验与一键更新**:发现新版弹气泡,菜单点一下用 git 拉取并自动重启

---

## 截图

> 建议放两张:`docs/tray-menu.png`(右键菜单)、`docs/about.png`(关于页)

```markdown
![托盘菜单](docs/tray-menu.png)
![关于页](docs/about.png)
```

---

## 快速开始

1. 去 [Releases](../../releases) 下载 `dsh-tray-supervisor-*.zip`
   (或 `git clone` 本仓库)
2. **先解压整个压缩包**,再双击里面的 **`install.bat`**
3. 按提示选 Y / N(每一步都会先问你),看到"流程结束"即完成
4. 右下角出现托盘图标 → 双击打开 `http://127.0.0.1:3080`

前置:Windows 10/11 + Node.js 22+(脚本会问你要不要自动装 `dsh`)

---

## 托盘菜单

```
打开界面                    双击托盘图标等效
鉴权网址(带 token)          网页提示"需要鉴权"时点它
dsh 控制 ▸
   启动 dsh
   停止 dsh
   ──────────
   重启 dsh
打开日志
关于 · 大肥鱼                版本 / 更新源 / 彩蛋按钮
─────────────────
版本 v1.3.0
检查更新
更新到 vX.Y.Z               仅发现新版时出现
打开仓库主页                更新拉不动时可手动下载
─────────────────
开机自启: 已开启 / 已关闭     点一下切换
退出(保留大肥鱼)             只退托盘, dsh 继续运行
```

---

## 配置(`config.ini`,与脚本同目录)

| 键 | 说明 |
|---|---|
| `node` | node 路径, 留空自动探测 |
| `entry` | dsh 入口 `lib\bin.js` |
| `webUrl` / `port` | 界面地址 / 端口 |
| `logPath` | 日志路径(默认放在安装目录) |
| `pollSec` | 存活轮询秒数(默认 5) |
| `logMaxMB` | 日志轮转阈值(默认 5MB) |
| `repo` | **更新源**:`用户名/仓库名`,留空=不检查更新 |
| `updateCheck` | `on` / `off` 更新检查总开关 |
| `updateHours` | 每多少小时检查一次(默认 6) |

---

## 更新 / 卸载

- **更新**:托盘菜单 →`检查更新`→ 有新版点`更新到 vX.Y.Z`
  (用 git:`git pull` 或 `git clone` 到同级 `dsh-tray-supervisor-src` 再同步 → 自动重启托盘)
  也可手动双击 `update.bat`
- **卸载**:双击 `uninstall.bat`,逐步确认:停托盘 / 关 dsh / 移除自启 / 删目录

---

## 常见问题

| 现象 | 处理 |
|---|---|
| `没有运行 .vbs 的脚本引擎` | 系统禁用了 WSH。安装脚本会自动改用 **BAT 方式**启动;也可手动双击 `dsh-tray-hidden.bat` |
| `无法打开此 http 链接` | 默认浏览器关联异常。程序会自动兜底(explorer / rundll32 / cmd start),全失败则**复制地址到剪贴板**并弹框 |
| 没看到托盘图标 | 点托盘区 `^` 展开找 |
| 被杀软拦截 | 把安装目录加入**信任/排除** |
| dsh 崩了 | 图标变红 + 提示,**不会自动重启**;`dsh 控制 ▸ 启动 dsh` 手动拉起 |
| 3080 被占用 | 托盘检测到已有 dsh 会**接管**,不会重复启动 |
| 更新拉不动 | 菜单`打开仓库主页`手动下载 |

---

## 仓库结构

```
dsh-tray.ps1          托盘主程序(supervisor, 直接托管 dsh 进程)
dsh-tray-hidden.vbs   无窗启动入口(需要 WSH)
dsh-tray-hidden.bat   无窗启动入口(BAT 兜底, 不需要 WSH)
dsh-logo.png          托盘图标
sounds\               XP 音效(感叹号 / 关键性终止)
install.bat           一键安装(每步确认, 自动探测 WSH)
uninstall.bat         一键卸载(每步确认)
update.bat            一键更新(git pull + 同步 + 重启)
VERSION               版本号(供无 Release 时校验)
.gitattributes        关键: 固定 *.bat/*.ps1 为 CRLF
```

---

## 注意

- `config.ini` 与本机日志**不入库**(见 `.gitignore`)
- 改 `.bat` 请保持 **CRLF 换行 + GBK(cp936) 编码**,否则中文批处理会解析出错
- 本工具只做操作系统层的事(后台/守护/日志/托盘);**不碰 agent 会话逻辑**

## License

[MIT](LICENSE) © 2026 孤舟蓑笠
随包 Windows XP 音效版权归 Microsoft,仅学习/自用演示。
