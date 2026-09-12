# GitHub 仓库资料填写模板(照抄即可)

把 `Guzhou2002` 换成你的 GitHub 用户名。

---

## 1) 仓库名(Repository name)
```
dsh-tray-supervisor
```

## 2) 简介(Description,填 What's this?)
**推荐(中文,189 字符内):**
```
🐳 给 DeepSeek Harness 的托盘守护外壳:开机无黑窗静默后台运行,右下角托盘一点即开界面,崩溃变红提示不偷偷重启,一键强退杀干净,自动解析鉴权 token,支持版本校验与一键更新。Windows / PowerShell。
```

**备选(中英混排,利于搜索):**
```
DeepSeek Harness (dsh) tray supervisor for Windows — silent autostart, no console window, crash alert, clean force-kill, token URL menu, version check & one-click git update.
```

## 3) 网站(Website)
可留空;想填就填 Release 页,方便群友直接下:
```
https://github.com/Guzhou2002/dsh-tray-supervisor/releases/latest
```

## 4) 主题标签(Topics)
> GitHub 的 Topics 只能小写、用连字符。一次一个粘贴:

```
deepseek
deepseek-harness
dsh
dsh-plugin
dsh-plugins
system-tray
tray-icon
windows
powershell
autostart
supervisor
process-manager
one-click-install
gui-automation
```

## 5) About 区勾选项
- ✅ Releases
- ✅ Packages(不用)
- ✅ Include in the home page: 勾上
- License: **MIT**(加入 LICENSE 后会自动识别)

---

## 6) 首个 Release 怎么写

**Tag**:`v1.3.0`  **Target**:`main`  **Title**:`v1.3.0 —— 大肥鱼托盘首发`

**说明正文(可直接粘):**
```markdown
## 🐳 dsh-tray-supervisor v1.3.0

给 DeepSeek Harness 的托盘守护外壳,**下载即用**。

### 怎么用
1. 下载本页的 `dsh-tray-supervisor-v1.3.0.zip`
2. **先完整解压**,再双击 `install.bat`(每一步都会问你)
3. 右下角出现托盘图标即完成

### 本次包含
- 无黑窗后台托管 dsh,托盘一点即开界面
- 崩溃**只提示不自动重启**(图标变红)
- 强退:多种方式杀干净,不留后台进程
- 鉴权网址:自动解析 `?token=`,菜单直接打开
- 开机自启**可开关**;无 WSH 环境自动改用 BAT 启动
- 版本校验 + **一键更新**(git pull / clone 后同步)
- 关于页 + 彩蛋 🎏

### 前置
Windows 10/11 · Node.js 22+(脚本可自动安装 dsh)

> 编写者:孤舟蓑笠 · QQ 578778930
```

**附件**:上传 `dsh-tray-supervisor-自启动+托盘.zip`(即打包好的那个 zip,建议改名成 `dsh-tray-supervisor-v1.3.0.zip`)

---

## 7) 社交预览图(Settings → Social preview)
上传一张图(建议 1280×640):托盘图标 + 菜单截图 + 标题 `dsh-tray-supervisor`。

## 8) 建议放进 README 的截图
| 文件 | 内容 |
|---|---|
| `docs/tray-menu.png` | 右键展开的托盘菜单(把所有菜单项都露出来) |
| `docs/about.png` | "关于 · 大肥鱼"窗口(能看到作者/版本/更新源) |
| `docs/in-tray.png` | 右下角托盘区的小图标(可放大截图) |
