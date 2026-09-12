# =============================================================================
#  dsh-tray.ps1  ——  DSH 托盘外壳 supervisor (Phase 1 定稿版)
#  OS 层职责:无窗口后台运行、持有并保活 dsh(node) 子进程、崩溃提示(不自动重启)、
#  日志、托盘图标两态(正常/红故障)、菜单、气泡通知。
#  业务/会话/音效 一律归 dsh 内部 Cordis 插件,本外壳不接触。
#
#  用法:
#     dsh-tray.ps1                正常启动托盘
#     dsh-tray.ps1 -CheckOnly     只校验配置+依赖+日志,不弹 GUI 不启 dsh(自检)
#  依赖: 同目录 config.ini(缺失则用默认值)
# =============================================================================
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------- 配置区:从同目录 config.ini 读取,缺项用默认 ----------------
function Get-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:CfgDir = Get-ScriptDir
$script:CfgFile = Join-Path $script:CfgDir 'config.ini'

# 默认值
$default = @{
    node      = ''                                  # 留空=自动找 node
    entry     = 'C:\Users\1\AppData\Roaming\npm\node_modules\@deepseek-ai\dsh\lib\bin.js'
    webUrl    = 'http://127.0.0.1:3080'
    port      = 3080
    logPath   = 'C:\Users\1\.dsh\dsh-autostart\dsh-web.log'
    pollSec   = 5
    logMaxMB  = 5
}

function Read-Config {
    $cfg = @{}
    foreach ($k in $default.Keys) { $cfg[$k] = $default[$k] }
    if (Test-Path $script:CfgFile) {
        foreach ($line in (Get-Content $script:CfgFile)) {
            $line = $line.Trim()
            if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
            $i = $line.IndexOf('=')
            if ($i -lt 1) { continue }
            $k = $line.Substring(0, $i).Trim()
            $v = $line.Substring($i + 1).Trim().Trim('"')
            if ($default.ContainsKey($k)) { $cfg[$k] = $v }
        }
    }
    # node:留空则自动探测
    if (-not $cfg['node']) {
        $cmd = Get-Command node -ErrorAction SilentlyContinue
        if ($cmd) { $cfg['node'] = $cmd.Source }
        elseif (Test-Path 'C:\Program Files\nodejs\node.exe') { $cfg['node'] = 'C:\Program Files\nodejs\node.exe' }
    }
    $cfg['pollSec']  = [int]$cfg['pollSec']
    $cfg['port']     = [int]$cfg['port']
    $cfg['logMaxMB'] = [int]$cfg['logMaxMB']
    return $cfg
}
$script:cfg = Read-Config

# 派生路径/启动参数
$node     = $script:cfg['node']
$entry    = $script:cfg['entry']
$webUrl   = $script:cfg['webUrl']
$port     = $script:cfg['port']
$logFile  = $script:cfg['logPath']
$pollMs   = $script:cfg['pollSec'] * 1000
$logMaxMB = $script:cfg['logMaxMB']

# 入口若缺失,尝试回退到 npx 缓存副本
if (-not (Test-Path $entry)) {
    $alt = 'C:\Users\1\AppData\Local\npm-cache\_npx\1e7f6d9597241db0\node_modules\@deepseek-ai\dsh\lib\bin.js'
    if (Test-Path $alt) { $entry = $alt }
}

# ---------------- 日志 ----------------
$script:logLock = New-Object System.Object
function Write-LogFile([string]$msg) {
    if (-not $logFile) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        [System.Threading.Monitor]::Enter($script:logLock)
        try { [System.IO.File]::AppendAllText($logFile, "[$ts] $msg`r`n") }
        finally { [System.Threading.Monitor]::Exit($script:logLock) }
    } catch { }
}
function Test-LogRotate {
    # 超过阈值→旧档 .1 保留,新日志另起
    try {
        if (Test-Path $logFile) {
            $fi = Get-Item $logFile
            if ($fi.Length -gt ($logMaxMB * 1MB)) {
                $bak = "$logFile.1"
                try { if (Test-Path $bak) { [System.IO.File]::Delete($bak) } } catch { }
                try { [System.IO.File]::Move($logFile, $bak) } catch { }
                Write-LogFile '日志已轮转(>上限,旧档存 .1)'
            }
        }
    } catch { }
}

function Test-PortListening {
    try {
        $l = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($l) { return $true }
    } catch { }
    $n = netstat -ano | Select-String (":$port") | Select-String 'LISTENING'
    return [bool]$n
}

# ---------------- 校验(CheckOnly / 启动前) ----------------
function Test-Prereqs {
    $bad = @()
    if (-not $node -or -not (Test-Path $node)) { $bad += "node 不存在: '$node'" }
    if (-not (Test-Path $entry))               { $bad += "dsh 入口不存在: '$entry'" }
    return $bad
}

if ($CheckOnly) {
    Write-Host "== dsh-tray 自检 =="
    Write-Host "配置文件 : $($script:CfgFile)  存在=$(Test-Path $script:CfgFile)"
    Write-Host "node      : $node  存在=$(Test-Path $node)"
    Write-Host "entry     : $entry  存在=$(Test-Path $entry)"
    Write-Host "webUrl    : $webUrl"
    Write-Host "port      : $port  轮询=$($pollMs/1000)s  日志上限=${logMaxMB}MB"
    Write-Host "logFile   : $logFile"
    $logDir = Split-Path -Parent $logFile
    Write-Host "logDir可写: $(try { Test-Path $logDir } catch { $false })"
    $bad = Test-Prereqs
    if ($bad.Count) { Write-Host '校验失败:'; $bad | ForEach-Object { Write-Host ' - ' + $_ }; exit 1 }
    Write-Host '自检通过。'
    exit 0
}

# ---------------- 状态/图标/工具 ----------------
$script:state = 'starting'      # starting / running / stopped / crashed
$script:proc  = $null
$script:stopRequested = $false
$script:egg = 0
$script:eggColors = @([System.Drawing.Color]::Red,[System.Drawing.Color]::Orange,[System.Drawing.Color]::Gold,[System.Drawing.Color]::LimeGreen,[System.Drawing.Color]::DodgerBlue,[System.Drawing.Color]::Purple)
$script:aboutTitle = $null
$script:aboutTimer = $null

function New-IconFromPng([string]$path) {
    if (Test-Path $path) {
        try {
            $bmp = [System.Drawing.Bitmap]::FromFile($path)
            $h = $bmp.GetHicon()
            $script:keepIconBmp = $bmp
            return [System.Drawing.Icon]::FromHandle($h)
        } catch { }
    }
    return $null
}

function New-WhaleIcon {
    $bmp = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $blue = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 77, 107, 254))
    $g.FillEllipse($blue, (New-Object System.Drawing.Rectangle 4, 4, 56, 56))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($white, (New-Object System.Drawing.Rectangle 10, 26, 34, 16))
    $tail = [System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point 52, 22),
        (New-Object System.Drawing.Point 60, 17),
        (New-Object System.Drawing.Point 58, 26),
        (New-Object System.Drawing.Point 60, 33),
        (New-Object System.Drawing.Point 52, 30)
    )
    $g.FillPolygon($white, $tail)
    $g.FillEllipse($blue, (New-Object System.Drawing.Rectangle 18, 30, 3, 3))
    $h = $bmp.GetHicon()
    $script:keepIconBmp = $bmp
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($h)
}

function New-FaultIcon {
    # 故障红图标:红底 + 白叉
    $bmp = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $red = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 224, 60, 60))
    $g.FillEllipse($red, (New-Object System.Drawing.Rectangle 4, 4, 56, 56))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 7)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, 20, 20, 44, 44)
    $g.DrawLine($pen, 44, 20, 20, 44)
    $pen.Dispose(); $white.Dispose(); $red.Dispose()
    $h = $bmp.GetHicon()
    $script:keepIconBmp = $bmp
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($h)
}

function Get-NormalIcon {
    $ico = Join-Path $script:CfgDir 'dsh-logo.ico'
    $png = Join-Path $script:CfgDir 'dsh-logo.png'
    $ic = New-IconFromPng $ico
    if ($ic) { return $ic }
    $ic = New-IconFromPng $png
    if ($ic) { return $ic }
    return New-WhaleIcon
}

function Set-State([string]$newState) {
    $script:state = $newState
    try {
        $old = $notify.Icon
        if ($newState -eq 'crashed') { $notify.Icon = New-FaultIcon }
        elseif ($newState -eq 'running') { $notify.Icon = Get-NormalIcon }
        # stopped:保留上一个图标(正常),仅改文字
        if ($old) { $old.Dispose() }
    } catch { }
    Update-StateText
}

function Get-StateText {
    switch ($script:state) {
        'running' { return "DSHarness: Running" }
        'stopped' { return "DSHarness: Stopped" }
        'crashed' { return "DSHarness: Stopped (Crashed)" }
        default   { return "DSHarness: ..." }
    }
}
function Get-CtlLabelText {
    switch ($script:state) {
        'running' { return 'dsh 控制 · 运行中' }
        default   { return 'dsh 控制 · 已停止' }
    }
}
function Update-StateText {
    try { $notify.Text = Get-StateText } catch { }
}

# ---------------- 子进程管理 ----------------
function Start-ChildProcess {
    Test-LogRotate
    if ($script:proc -and -not $script:proc.HasExited) {
        Write-LogFile 'start 被忽略:已有子进程在运行'
        return
    }
    # 端口已被占用(外部已有 dsh) → 不重复启动
    if (Test-PortListening) {
        Write-LogFile '端口已被占用,视为已在运行;托盘只接管状态,不重复启动'
        Set-State 'running'
        Show-Balloon '大肥鱼' 'dsh 已在运行(占用端口),托盘已接管状态。' 'Info'
        return
    }
    $bad = Test-Prereqs
    if ($bad.Count) {
        $script:stopRequested = $true
        Set-State 'crashed'
        Show-Balloon '大肥鱼' ('启动失败:' + ($bad -join '; ')) 'Warning'
        Write-LogFile ('前置校验失败:' + ($bad -join '; '))
        return
    }
    Write-LogFile '正在启动 dsh(node)……'
    $cmdExe = Join-Path $env:WINDIR 'System32\cmd.exe'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cmdExe
    # 经 cmd 把 node 输出重定向到 $logFile(文件级重定向,不用 .NET 输出事件 → 避免后台线程导致的闪退)。
    # 顺带能把 dsh 启动时打印的鉴权 token 网址写进日志,供菜单解析。
    $psi.Arguments = '/d /s /c "' + '"' + $node + '" "' + $entry + '" web --no-open --trusted-host 127.0.0.1:3080 --trusted-host localhost:3080 >> "' + $logFile + '" 2>&1' + '"'
    $psi.WorkingDirectory = $script:CfgDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.EnableRaisingEvents = $true
    try {
        [void]$p.Start()
    } catch {
        Write-LogFile ('node 启动失败:' + $_.Exception.Message)
        Set-State 'crashed'
        Show-Balloon '大肥鱼' 'node 启动失败,见日志' 'Error'
        return
    }
    $script:proc = $p
    $script:stopRequested = $false
    Set-State 'running'
    Show-Balloon '大肥鱼' 'dsh 已在后台运行(无窗口)' 'Info'
    Write-LogFile ('dsh 已启动(cmd PID=' + $p.Id + ')')
}

function Force-KillDsh {
    # 强退:用多种方法确保把 dsh(node) 进程及其后代杀干净,不留孤儿占端口
    param([switch]$quiet)
    $script:stopRequested = $true
    Write-LogFile '强退:开始清理 dsh 进程……'
    $ids = New-Object 'System.Collections.Generic.List[int]'

    $p = $script:proc
    $script:proc = $null
    if ($p) { try { if (-not $p.HasExited) { $ids.Add([int]$p.Id) } } catch { } }

    # 1) 通过监听端口找到占用者
    try {
        $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($c -and $c.OwningProcess -and -not $ids.Contains([int]$c.OwningProcess)) { $ids.Add([int]$c.OwningProcess) }
    } catch { }

    # 2) 通过命令行匹配 dsh 入口的 node 进程(双保险)
    try {
        Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
            Where-Object { $_.CommandLine -like "*$entry*" } |
            ForEach-Object { if (-not $ids.Contains([int]$_.ProcessId)) { $ids.Add([int]$_.ProcessId) } }
    } catch { }

    $tk = Join-Path $env:WINDIR 'System32\taskkill.exe'
    foreach ($id in $ids) {
        Write-LogFile ('强退: 结束 PID ' + $id)
        # 方法a: 整棵进程树强制结束
        if (Test-Path $tk) { try { & $tk /PID $id /T /F 2>$null | Out-Null } catch { } }
        # 方法b: Stop-Process 兜底
        try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($p) { try { $p.WaitForExit(3000) | Out-Null; $p.Dispose() } catch { } }

    # 等待端口释放
    for ($i = 0; $i -lt 6; $i++) { if (-not (Test-PortListening)) { break }; Start-Sleep -Milliseconds 500 }
    if (Test-PortListening) {
        Write-LogFile '强退后端口仍被占用'
        if (-not $quiet) { Show-Balloon '大肥鱼' '仍有进程占用端口,请到任务管理器检查' 'Warning' }
    } else {
        Write-LogFile '强退完成,端口已释放'
        if (-not $quiet) { Show-Balloon '大肥鱼' '已强制关闭 dsh。' 'Info' }
    }
    Set-State 'stopped'
}

function Restart-ChildProcess {
    Write-LogFile '用户手动重启……'
    Force-KillDsh -quiet
    Start-Sleep -Milliseconds 500
    Start-ChildProcess
}

# 崩溃检测:子进程意外退出(非用户主动停止)
function Check-ChildAlive {
    if ($script:stopRequested) { return }
    $p = $script:proc
    if ($null -eq $p) { return }
    try { $exited = $p.HasExited } catch { $exited = $true }
    if ($exited) {
        $script:proc = $null
        $code = '?'
        try { $code = $p.ExitCode } catch { }
        Write-LogFile ("dsh 意外退出 code=$code → 停止(不自动重启)")
        Set-State 'crashed'
        Show-Balloon '大肥鱼' ('dsh 已退出/崩溃(code ' + $code + ')。未自动重启,可点菜单[重启 dsh]。') 'Error'
        try { $p.Dispose() } catch { }
    }
}

# ---------------- UI ----------------
function Show-Balloon([string]$title, [string]$msg, [string]$info = 'Info') {
    try { $notify.ShowBalloonTip(2600, $title, $msg, $info) } catch { }
}
function Open-Web { try { Start-Process $webUrl } catch { } }
function Open-Log {
    if (Test-Path $logFile) { try { Start-Process $logFile } catch { } }
    else { Show-Balloon '大肥鱼' '日志还不存在。' 'Warning' }
}
function Test-AutostartEnabled {
    return (Test-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\dsh-autostart.vbs'))
}
function Update-AutoLabel {
    try {
        if ($miAuto) {
            if (Test-AutostartEnabled) { $miAuto.Text = '开机自启: 已开启' } else { $miAuto.Text = '开机自启: 已关闭' }
        }
    } catch { }
}
function Toggle-Autostart {
    # 在"启动"文件夹里创建/删除自启项 —— 随时可开关
    $dir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    $lnk = Join-Path $dir 'dsh-autostart.vbs'
    $vbs = Join-Path $script:CfgDir 'dsh-tray-hidden.vbs'
    try {
        if (Test-Path $lnk) {
            Remove-Item $lnk -Force
            Show-Balloon 'dsh-tray' '已关闭开机自启(下次开机不会自动运行)。' 'Info'
        } else {
            $content = 'set sh = CreateObject("WScript.Shell")' + "`r`n" + 'sh.Run "' + $vbs + '",0,False' + "`r`n"
            [System.IO.File]::WriteAllText($lnk, $content, [System.Text.Encoding]::ASCII)
            Show-Balloon 'dsh-tray' '已开启开机自启。' 'Info'
        }
    } catch {
        Show-Balloon 'dsh-tray' ('设置失败: ' + $_.Exception.Message) 'Warning'
    }
    Update-AutoLabel
}
function Find-AuthUrl {
    # 从日志里解析 dsh 打印的鉴权网址 http://127.0.0.1:3080/?token=...
    try {
        if (Test-Path $logFile) {
            # dsh 的输出正以 >> 占用该文件;须用共享读写方式打开才能读取
            $fs = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $sr = New-Object System.IO.StreamReader($fs)
                $txt = $sr.ReadToEnd()
            } finally {
                $sr.Dispose(); $fs.Dispose()
            }
            $m = [regex]::Matches($txt, 'http://(127\.0\.0\.1|localhost):3080/\?token=[A-Za-z0-9_\-]+')
            if ($m.Count) { return $m[$m.Count - 1].Value }
        }
    } catch { }
    return $null
}
function Open-Auth {
    $u = Find-AuthUrl
    if ($u) { try { Start-Process $u } catch { } }
    else { Show-Balloon '大肥鱼' '暂未找到带 token 的网址(先启动 dsh 再点)。' 'Warning' }
}
function Start-EggRainbow {
    # 让"关于"页标题循环变色若干次(动画安全版:脚本级变量 + sender 自停)
    $script:rc = 0
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 120
    $t.add_Tick({ param($s, $e)
        $script:rc++
        if ($script:rc -gt 40) {
            $s.Stop(); $s.Dispose()
            try { $script:aboutTitle.ForeColor = [System.Drawing.Color]::Black } catch { }
            $script:aboutTimer = $null
        } else {
            try { $script:aboutTitle.ForeColor = $script:eggColors[$script:rc % $script:eggColors.Count] } catch { }
        }
    })
    $script:aboutTimer = $t
    $t.Start()
}
function Play-XpSound([string]$which) {
    # 播放 Windows XP 音效 wav;文件缺失则回退到系统声音
    $map = @{ exclaim = 'exclaim.wav'; critical = 'critical_stop.wav' }
    $file = Join-Path $script:CfgDir ('sounds\' + $map[$which])
    if (Test-Path $file) {
        try {
            $sp = New-Object System.Media.SoundPlayer($file)
            $sp.PlaySync()
            $sp.Dispose()
            return
        } catch { }
    }
    if ($which -eq 'critical') { [System.Media.SystemSounds]::Hand.Play() }
    else { [System.Media.SystemSounds]::Exclamation.Play() }
}
function Show-About {
    # 自绘"关于页"小窗口
    Play-XpSound 'exclaim'
    $f = New-Object System.Windows.Forms.Form
    $f.Text = '关于 · 大肥鱼'
    $f.ClientSize = New-Object System.Drawing.Size(370, 430)
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.TopMost = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(244, 247, 252)
    $f.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $logoPng = Join-Path $script:CfgDir 'dsh-logo.png'
    if (Test-Path $logoPng) {
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pb.Location = New-Object System.Drawing.Point(150, 14)
        $pb.Size = New-Object System.Drawing.Size(70, 70)
        $pb.Image = [System.Drawing.Image]::FromFile($logoPng)
        $f.Controls.Add($pb)
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '🐳 大肥鱼 supervisor'
    $title.Location = New-Object System.Drawing.Point(0, 92)
    $title.Size = New-Object System.Drawing.Size(370, 28)
    $title.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $f.Controls.Add($title)
    $script:aboutTitle = $title

    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = 'v1.2 · DeepSeek Harness 托盘守护'
    $ver.Location = New-Object System.Drawing.Point(0, 120)
    $ver.Size = New-Object System.Drawing.Size(370, 20)
    $ver.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $ver.ForeColor = [System.Drawing.Color]::Gray
    $f.Controls.Add($ver)

    $author = New-Object System.Windows.Forms.Label
    $author.Text = '编写者：孤舟蓑笠    QQ：578778930'
    $author.Location = New-Object System.Drawing.Point(0, 138)
    $author.Size = New-Object System.Drawing.Size(370, 20)
    $author.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $author.ForeColor = [System.Drawing.Color]::FromArgb(77, 107, 254)
    $author.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $f.Controls.Add($author)

    $body = New-Object System.Windows.Forms.Label
    $bodyLines = @(
        '· 托盘直接托管 dsh(node) 进程',
        ('· 崩溃只提示、不自动重启 · 轮询 ' + $script:cfg['pollSec'] + 's'),
        '· 菜单可打开 鉴权网址/日志',
        ('· 日志: ' + $logFile)
    )
    $body.Text = ($bodyLines -join "`n")
    $body.Location = New-Object System.Drawing.Point(24, 166)
    $body.Size = New-Object System.Drawing.Size(322, 104)
    $body.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $f.Controls.Add($body)

    # 可点开的链接
    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text = '打开 DeepSeek Harness 界面'
    $lnk.Location = New-Object System.Drawing.Point(95, 288)
    $lnk.Size = New-Object System.Drawing.Size(180, 22)
    $lnk.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lnk.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
    $lnk.add_LinkClicked({ Open-Web })
    $f.Controls.Add($lnk)

    # 底部三按钮:千万别点 / 鱼生彩蛋 / 关闭
    $btnDont = New-Object System.Windows.Forms.Button
    $btnDont.Text = '千万别点'
    $btnDont.Location = New-Object System.Drawing.Point(16, 372)
    $btnDont.Size = New-Object System.Drawing.Size(110, 34)
    $btnDont.BackColor = [System.Drawing.Color]::FromArgb(255, 214, 102)
    $btnDont.add_Click({
        Play-XpSound 'critical'
        [System.Windows.Forms.MessageBox]::Show('都说了你还点！哈！', '喂！', 'OK', 'Error') | Out-Null
    })
    $f.Controls.Add($btnDont)

    $btnEgg = New-Object System.Windows.Forms.Button
    $btnEgg.Text = '🎏 鱼生彩蛋'
    $btnEgg.Location = New-Object System.Drawing.Point(130, 372)
    $btnEgg.Size = New-Object System.Drawing.Size(110, 34)
    $btnEgg.add_Click({
        $script:egg += 1
        $n = $script:egg
        if ($n -ge 8) { $script:egg = 1; $n = 1 }
        $msg = ''
        switch ($n) {
            1 {
                [System.Media.SystemSounds]::Asterisk.Play()
                $fishsay = @('深潜快乐，别憋气','你的 token 够买一斤鱼了','多喝水，少胡思乱想','Fish 到碗里来！','本尊正在摸鱼中……')
                $msg = '🐟 ' + $fishsay[(Get-Random -Maximum $fishsay.Count)]
            }
            2 { [System.Media.SystemSounds]::Asterisk.Play(); $msg = '第 2 下：鱼生彩蛋开始分裂！🐟🐟　(再点我就给你下鱼雨)' }
            3 { [System.Media.SystemSounds]::Asterisk.Play(); Start-EggRainbow; $msg = '第 3 下：标题要开始彩虹了，盯好了……' }
            4 { [System.Media.SystemSounds]::Exclamation.Play(); $msg = '第 4 下：警告——附近有大量肥鱼出没 🐡🐟🐠' }
            5 { [System.Media.SystemSounds]::Exclamation.Play(); $msg = '第 5 下：只差两条就能召唤本尊了……你确定要继续？' }
            6 { [System.Media.SystemSounds]::Hand.Play(); $msg = '第 6 下：最后一条！深呼吸，要来了……' }
            default {
                [System.Media.SystemSounds]::Hand.Play()
                $script:egg = 0
                Start-EggRainbow
                $msg = "🐳 集齐七条，召唤 DeepSeek 本尊！🎉`n`n……其实本尊就住在你每次打开它的地方。`n彩蛋已重置，可以再来一遍。"
            }
        }
        [System.Windows.Forms.MessageBox]::Show($msg, ("🎏 鱼生彩蛋(" + $n + "/7)"), 'OK', 'Information') | Out-Null
    })
    $f.Controls.Add($btnEgg)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = '关闭'
    $btnClose.Location = New-Object System.Drawing.Point(244, 372)
    $btnClose.Size = New-Object System.Drawing.Size(110, 34)
    $btnClose.add_Click({ $f.Close() })
    $f.Controls.Add($btnClose)

    $f.ShowDialog() | Out-Null
    try { if ($script:aboutTimer) { $script:aboutTimer.Stop(); $script:aboutTimer.Dispose() } } catch { }
    $script:aboutTitle = $null
    $script:aboutTimer = $null
    $f.Dispose()
}
function Show-ExitAll {
    Write-LogFile '强退:退出托盘并关闭 dsh'
    Force-KillDsh
    try { $timer.Stop() } catch { }
    try { $notify.Visible = $false } catch { }
    try { $notify.Icon.Dispose() } catch { }
    try { $notify.Dispose() } catch { }
    [System.Windows.Forms.Application]::ExitThread()
}

# ---------------- 组装托盘 ----------------
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = Get-NormalIcon
$notify.Visible = $true
$notify.add_DoubleClick({ Open-Web })

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen   = New-Object System.Windows.Forms.ToolStripMenuItem('打开界面')
$miAuth   = New-Object System.Windows.Forms.ToolStripMenuItem('鉴权网址(带 token)')
$miCtl    = New-Object System.Windows.Forms.ToolStripMenuItem('dsh 控制')
$miStart  = New-Object System.Windows.Forms.ToolStripMenuItem('启动 dsh')
$miStop   = New-Object System.Windows.Forms.ToolStripMenuItem('停止 dsh')
$miRestart= New-Object System.Windows.Forms.ToolStripMenuItem('重启 dsh')
$miCtl.DropDownItems.Add($miStart) | Out-Null
$miCtl.DropDownItems.Add($miStop) | Out-Null
$miCtl.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miCtl.DropDownItems.Add($miRestart) | Out-Null
$miLog    = New-Object System.Windows.Forms.ToolStripMenuItem('打开日志')
$miAbout  = New-Object System.Windows.Forms.ToolStripMenuItem('关于 · 大肥鱼')
$miQuit   = New-Object System.Windows.Forms.ToolStripMenuItem('退出(强制关闭 dsh)')
$miAuto   = New-Object System.Windows.Forms.ToolStripMenuItem('开机自启: ?')

$miOpen.Add_Click({ Open-Web })
$miAuth.Add_Click({ Open-Auth })
$miStart.Add_Click({ Start-ChildProcess })
$miStop.Add_Click({ Force-KillDsh })
$miRestart.Add_Click({ Restart-ChildProcess })
$miLog.Add_Click({ Open-Log })
$miAbout.Add_Click({ Show-About })
$miAuto.Add_Click({ Toggle-Autostart })
$miQuit.Add_Click({ Show-ExitAll })

$menu.Items.Add($miOpen) | Out-Null
$menu.Items.Add($miAuth) | Out-Null
$menu.Items.Add($miCtl) | Out-Null
$menu.Items.Add($miLog) | Out-Null
$menu.Items.Add($miAbout) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add($miAuto) | Out-Null
$menu.Items.Add($miQuit) | Out-Null
$notify.ContextMenuStrip = $menu
# 每次打开菜单时刷新"开机自启"文字
$menu.add_Opening({ Update-AutoLabel })
Update-AutoLabel

# 每 pollMs 轮询子进程存活并刷新文字
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $pollMs
$timer.add_Tick({ Check-ChildAlive; Update-StateText })
$timer.Start()

try {
    Write-LogFile '== dsh-tray supervisor 启动 =='
    $bad = Test-Prereqs
    if ($bad.Count) {
        Set-State 'crashed'
        Show-Balloon '大肥鱼' ('配置有误:' + ($bad -join '; ') + '。托盘保留。') 'Warning'
    } else {
        Start-ChildProcess
    }

    [System.Windows.Forms.Application]::Run()
} catch {
    # 顶层崩溃留证:任何未捕获异常 → 写日志 + 弹提示
    $errMsg = $_.Exception.Message
    try { Write-LogFile ('FATAL: ' + $errMsg) } catch { }
    try {
        [System.Windows.Forms.MessageBox]::Show('托盘异常退出: ' + $errMsg, 'dsh-tray 错误', 'OK', 'Error') | Out-Null
    } catch { }
} finally {
    try { $timer.Stop() } catch { }
    try { $notify.Icon.Dispose() } catch { }
    try { $notify.Dispose() } catch { }
}
