# ============================================================================
#  winiso / lib/common.ps1  ——  公共基础（日志、菜单、网络、权限）
#  兼容 Windows PowerShell 5.1
# ============================================================================

$script:UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# ---------------------------- 输出 ----------------------------
function Write-Title([string]$Text) {
    $w = 66
    Write-Host ''
    Write-Host ('  ' + ('=' * $w)) -ForegroundColor DarkCyan
    Write-Host ('   ' + $Text) -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * $w)) -ForegroundColor DarkCyan
    Write-Host ''
}
function Write-Step([int]$No, [int]$Total, [string]$Text) {
    Write-Host ''
    Write-Host ("  [{0}/{1}] " -f $No, $Total) -ForegroundColor Yellow -NoNewline
    Write-Host $Text -ForegroundColor White
}
function Write-Ok([string]$Text)   { Write-Host ('  [OK]   ' + $Text) -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host ('  [WARN] ' + $Text) -ForegroundColor Yellow }
function Write-Err2([string]$Text) { Write-Host ('  [FAIL] ' + $Text) -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host ('  ' + $Text) -ForegroundColor Gray }

# ---------------------------- 交互 ----------------------------
# 单选菜单；返回选中项的 Value
function Read-Choice {
    param(
        [string]$Prompt,
        [array]$Items,          # @( @{Label='...'; Value=...; Hint='...'} )
        [object]$Default = $null
    )
    Write-Host ''
    Write-Host ("  " + $Prompt) -ForegroundColor White
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $n = $i + 1
        $label = $Items[$i].Label
        $hint = $Items[$i].Hint
        $mark = '  '
        if ($null -ne $Default -and $Items[$i].Value -eq $Default) { $mark = '* ' }
        Write-Host ("   {0}{1,2}) {2}" -f $mark, $n, $label) -ForegroundColor Cyan -NoNewline
        if ($hint) { Write-Host ("   " + $hint) -ForegroundColor DarkGray } else { Write-Host '' }
    }
    while ($true) {
        Write-Host '   请选择编号（回车=默认，q=返回）: ' -ForegroundColor Gray -NoNewline
        $s = Read-Host
        if ($null -eq $s) { return $Default }
        if ($s -eq 'q') { return $null }
        if ($s -eq '' -and $null -ne $Default) {
            foreach ($it in $Items) { if ($it.Value -eq $Default) { return $it.Value } }
        }
        $num = 0
        if ([int]::TryParse($s, [ref]$num)) {
            if ($num -ge 1 -and $num -le $Items.Count) { return $Items[$num - 1].Value }
        }
        Write-Warn2 '无效输入，请重试'
    }
}

# 多选菜单；返回选中的 Value 数组（回车=全部选项按默认状态）
function Read-MultiChoice {
    param(
        [string]$Prompt,
        [array]$Items,          # @( @{Label; Value; Hint; On=[bool]} )
        [string]$Key
    )
    $state = @{}
    for ($i = 0; $i -lt $Items.Count; $i++) { $state[$i] = [bool]$Items[$i].On }
    Write-Host ''
    Write-Host ("  " + $Prompt) -ForegroundColor White
    while ($true) {
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $box = '[ ]'
            if ($state[$i]) { $box = '[x]' }
            $n = $i + 1
            Write-Host ("   {0} {1,2}) {2}" -f $box, $n, $Items[$i].Label) -ForegroundColor Cyan -NoNewline
            if ($Items[$i].Hint) { Write-Host ("   " + $Items[$i].Hint) -ForegroundColor DarkGray } else { Write-Host '' }
        }
        Write-Host '   输入编号（单个=切换，多个=直接指定），回车确认: ' -ForegroundColor Gray -NoNewline
        $s = Read-Host
        if ($null -eq $s) { break }
        if ($s -eq '') { break }
        if ($s -eq 'a') { for ($i = 0; $i -lt $Items.Count; $i++) { $state[$i] = $true }; continue }
        if ($s -eq 'n') { for ($i = 0; $i -lt $Items.Count; $i++) { $state[$i] = $false }; continue }
        # 支持 "1234" / "1,3,5" / "1 3 5" 三种写法：
        #   只给一个编号 -> 切换那一项；给多个编号 -> 直接把它们设为勾选（其余取消）
        $nums = @()
        $tokens = @($s -split '[ ,，;；]+' | Where-Object { $_ -ne '' })
        foreach ($tok in $tokens) {
            $num = 0
            if ([int]::TryParse($tok, [ref]$num) -and $num -ge 1 -and $num -le $Items.Count) {
                $nums += $num
            } elseif ($tok -match '^\d+$' -and $tok.Length -gt 1) {
                foreach ($ch in $tok.ToCharArray()) {
                    $d = [int]::Parse($ch)
                    if ($d -ge 1 -and $d -le $Items.Count) { $nums += $d }
                }
            }
        }
        if ($nums.Count -eq 1) {
            $state[$nums[0] - 1] = -not $state[$nums[0] - 1]
        } elseif ($nums.Count -gt 1) {
            for ($i = 0; $i -lt $Items.Count; $i++) { $state[$i] = $false }
            foreach ($d in $nums) { $state[$d - 1] = $true }
        }
        Write-Host ''
    }
    $sel = @()
    for ($i = 0; $i -lt $Items.Count; $i++) { if ($state[$i]) { $sel += $Items[$i].Value } }
    return $sel
}

function Read-TextInput {
    param([string]$Prompt, [string]$Default = '')
    if ($Default) {
        Write-Host ("  " + $Prompt + " [" + $Default + "]: ") -ForegroundColor Gray -NoNewline
    } else {
        Write-Host ("  " + $Prompt + ": ") -ForegroundColor Gray -NoNewline
    }
    $s = Read-Host
    if ($null -eq $s -or $s -eq '') { return $Default }
    return $s
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $d = 'Y/n'
    if (-not $Default) { $d = 'y/N' }
    while ($true) {
        Write-Host ("  " + $Prompt + " [" + $d + "]: ") -ForegroundColor Gray -NoNewline
        $s = Read-Host
        if ($null -eq $s -or $s -eq '') { return $Default }
        if ($s -match '^(y|Y|yes|YES)$') { return $true }
        if ($s -match '^(n|N|no|NO)$') { return $false }
    }
}

function Pause-Any {
    Write-Host ''
    Write-Host '  按回车继续...' -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

# ---------------------------- 权限 / 环境 ----------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-Admin) { return }
    if ($script:SkipElevate) {
        Write-Warn2 '当前不是管理员：DISM 挂载/写系统目录可能失败（GUI 已提权时不会走到这里）'
        return
    }
    Write-Warn2 '需要管理员权限（DISM 挂载映像、写系统目录），正在请求提权...'
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptPath + '"'))
    foreach ($a in @($script:RawArgs)) {
        if ($null -eq $a) { continue }
        $s = [string]$a
        if ($s -match '[ \t]') { $s = '"' + $s + '"' }
        $argList += $s
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
        exit 0
    } catch {
        Write-Err2 '提权被取消。请右键 winiso.cmd → 以管理员身份运行。'
        exit 1
    }
}

function Get-HostArch {
    $a = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $a = $env:PROCESSOR_ARCHITEW6432 }   # 32 位 PowerShell 跑在 x64 上时
    if ($a -eq 'ARM64') { return 'arm64' }
    return 'amd64'
}

# 解析可执行文件：先查 PATH，再兜底 System32 / SysWOW64（PATH 被裁剪时也能用）
function Resolve-Exe([string]$Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c -and $c.Source) { return $c.Source }
    $dirs = @()
    if ($env:SystemRoot) {
        $dirs += (Join-Path $env:SystemRoot 'System32')
        $dirs += (Join-Path $env:SystemRoot 'SysWOW64')
    }
    foreach ($d in $dirs) {
        $p = Join-Path $d $Name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-CommandExists([string]$Name) {
    return [bool](Resolve-Exe $Name)
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-FreeSpaceGB([string]$Path) {
    # 注意：不能用 Get-Item 取盘符——目录还没创建时 Get-Item 会抛错，
    # 于是"E 盘还有多少空间"永远返回 -1，默认目录就选不中 E 盘。这里直接解析盘符。
    try {
        if (-not $Path) { return -1 }
        $letter = $null
        if ($Path -match '^([A-Za-z])\:') { $letter = $Matches[1].ToUpper() }
        else {
            $full = [IO.Path]::GetFullPath($Path)
            if ($full -match '^([A-Za-z])\:') { $letter = $Matches[1].ToUpper() } else { return -1 }
        }
        $v = Get-PSDrive -Name $letter -ErrorAction Stop
        if ($null -eq $v.Free) { return -1 }
        return [math]::Round($v.Free / 1GB, 1)
    } catch { return -1 }
}

# ---------------------------- 网络 ----------------------------
# 使用 curl.exe（Win10 1803+ 自带，稳定且可断点续传/并发）
# curl 重试参数：--retry-all-errors 需要 curl >= 7.71。Win10 1803-1909 自带 7.55-7.66，
# 直接带上会报 "option --retry-all-errors: is unknown"（退出码 2），导致下载全部失败。
# 这里先探测版本，低版本自动降级成只带 --retry。
function Get-CurlRetryArgs {
    if ($script:CurlRetryArgs) { return $script:CurlRetryArgs }
    $retry = @('--retry', '4', '--retry-delay', '2')
    $ver = $null
    $curl = Resolve-Exe 'curl.exe'
    if ($curl) {
        try {
            $first = (& $curl --version 2>$null | Select-Object -First 1)
            if ($first -match 'curl\s+([0-9]+(?:\.[0-9]+){1,3})') { $ver = $Matches[1] }
        } catch { }
    }
    $useAll = $true
    if ($ver) { if (([version]$ver) -lt [version]'7.71') { $useAll = $false } }
    if ($useAll) { $retry += '--retry-all-errors' }
    $script:CurlRetryArgs = $retry
    return $retry
}

function Invoke-CurlText {
    param(
        [string]$Url,
        [string]$Method = 'GET',
        [string]$Body = $null,
        [int]$TimeoutSec = 60,
        [int]$Attempts = 3
    )
    $curl = Resolve-Exe 'curl.exe'
    if ($curl) {
        $last = ''
        for ($i = 1; $i -le $Attempts; $i++) {
            # --retry* 让 curl 自己在连接重置/半途断开时重试，外层再兜几次
            $argList = @('-sL', '-A', $script:UA, '--max-time', "$TimeoutSec", '--connect-timeout', '20')
            $argList += (Get-CurlRetryArgs)
            $argList += @('--retry-connrefused')
            if ($Method -eq 'POST') { $argList += @('-X', 'POST', '-d', $Body) }
            $argList += $Url
            $out = & $curl @argList 2>$null
            $code = $LASTEXITCODE
            $txt = ($out -join "`n")
            if ($code -eq 0 -and $txt) { return $txt }
            $last = ('curl 退出码 ' + $code)
            Start-Sleep -Seconds (2 * $i)
        }
        throw ("请求失败（$last，已重试 $Attempts 次）: $Url")
    }
# 兜底：Invoke-WebRequest
    $p = @{ Uri = $Url; UseBasicParsing = $true; TimeoutSec = $TimeoutSec; Headers = @{ 'User-Agent' = $script:UA } }
    if ($Method -eq 'POST') { $p.Method = 'POST'; $p.Body = $Body }
    $lastErr = $null
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $r = Invoke-WebRequest @p -ErrorAction Stop
            if ($r.Content) { return $r.Content }
            throw '空响应'
        } catch { $lastErr = $_.Exception.Message; Start-Sleep -Seconds (2 * $i) }
    }
    throw ("请求失败（$lastErr）: $Url")
}

function Get-JsonFromUrl {
    param([string]$Url, [int]$Retry = 3)
    $lastErr = $null
    for ($i = 0; $i -lt $Retry; $i++) {
        try {
            $txt = Invoke-CurlText -Url $Url
            if (-not $txt) { throw '空响应' }
            # 应对被截断的响应
            return ($txt | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            $lastErr = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    throw "接口请求失败: $Url ($lastErr)"
}

function Save-UrlToFile {
    param(
        [string]$Url,
        [string]$Path,
        [string]$Method = 'GET',
        [string]$Body = $null,
        [string]$Referer = $null,
        [switch]$Resume
    )
    $curl = Resolve-Exe 'curl.exe'
    if (-not $curl) { throw '缺少 curl.exe（需要 Windows 10 1803 及以上）' }
    $base = @('-sL', '-A', $script:UA, '--connect-timeout', '20')
    $base += (Get-CurlRetryArgs)
    if ($Referer) { $base += @('-H', ('Referer: ' + $Referer)) }
    if ($Method -eq 'POST') { $base += @('-X', 'POST', '-d', $Body) }
    else { $base += '-f' }        # GET 时 404/403 直接判失败，避免把错误网页当成文件存下来
    if ($Resume -and $Method -ne 'POST') { $base += @('-C', '-') }

    $last = ''
    for ($i = 1; $i -le 3; $i++) {
        $argList = @($base) + @('-o', $Path, $Url)
        & $curl @argList 2>$null
        $code = $LASTEXITCODE
        # 33 = 服务器不支持 Range / 文件已完整；只要文件确实写出来了就当成功（后续还有 SHA1 兜底）
        if ($code -eq 0 -or $code -eq 33) {
            if (-not $Resume -or (Test-Path -LiteralPath $Path)) { return }
        }
        $last = ('curl 退出码 ' + $code)
        if (-not $Resume) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds (2 * $i)
    }
    throw ('下载失败（' + $last + '）: ' + $Url)
}

# 多线程下载（curl.exe 并发）
function Start-ParallelDownload {
    param(
        [array]$Items,        # @( @{Url; Out; Sha1} )
        [string]$DestDir,
        [int]$Jobs = 4
    )
    $total = $Items.Count
    if ($total -eq 0) { return }
    if ($Jobs -lt 1) { $Jobs = 1 }
    if ($Jobs -gt 8) { $Jobs = 8 }

    $scriptBlock = {
        param($Ctx)
        # 注意：必须用哈希表整体传参。若写成 (,$c),$Dest,... 这种逗号写法，
        # PowerShell 会把分片数组再套一层，$Files.Count 变成 1、$f 变成整个分片，
        # 结果 $f.Out 为空 -> Join-Path 拿不到子路径 -> 所有多文件分片全部失败。
        $Files = $Ctx.Files
        $Dest = $Ctx.Dest
        $UA = $Ctx.UA
        $Curl = $Ctx.Curl
        $Retry = @($Ctx.Retry)
        $done = 0; $fail = 0
        foreach ($f in $Files) {
            $name = [string]$f.Out
            $out = Join-Path $Dest $name
            $ok = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $cargs = @('-sL', '-A', $UA, '--connect-timeout', '20') + $Retry + @('-C', '-', '-o', $out, $f.Url)
                & $Curl @cargs 2>$null
                $ce = $LASTEXITCODE
                # 33 = Range 不被支持/文件已存在完整；仍然按"有文件"处理，交给下面的 SHA1 判定
                if (($ce -eq 0 -or $ce -eq 33) -and (Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0)) { $ok = $true; break }
                Start-Sleep -Seconds 3
            }
            if (-not $ok) { $fail++; Write-Output ("FAIL|" + $name); continue }
            if ($f.Sha1) {
                $h = (Get-FileHash -LiteralPath $out -Algorithm SHA1).Hash.ToLower()
                if ($h -ne $f.Sha1.ToLower()) {
                    Write-Output ("HASHFAIL|" + $name)
                    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
                    $fail++
                    continue
                }
            }
            $done++
            Write-Output ("DONE|" + $name + "|" + (Get-Item -LiteralPath $out).Length)
        }
        Write-Output ("JOBEND|" + $done + "|" + $fail)
    }

    $chunks = @()
    for ($i = 0; $i -lt $Jobs; $i++) { $chunks += , @() }
    for ($i = 0; $i -lt $total; $i++) { $chunks[$i % $Jobs] += $Items[$i] }

    $curlPath = Resolve-Exe 'curl.exe'
    if (-not $curlPath) { throw '缺少 curl.exe，无法下载' }
    $retryArgs = @(Get-CurlRetryArgs)
    $jobList = @()
    foreach ($c in $chunks) {
        if ($c.Count -eq 0) { continue }
        $ctx = @{ Files = $c; Dest = $DestDir; UA = $script:UA; Curl = $curlPath; Retry = $retryArgs }
        $jobList += Start-Job -ScriptBlock $scriptBlock -ArgumentList $ctx
    }

    $finished = 0; $failed = 0; $failedNames = @(); $lastReport = Get-Date
    while ($true) {
        $running = @($jobList | Where-Object { $_.State -eq 'Running' })
        foreach ($j in $jobList) {
            $outs = @(Receive-Job -Job $j -ErrorAction SilentlyContinue)
            foreach ($line in $outs) {
                if ($line -like 'DONE|*') { $finished++ }
                elseif ($line -like 'FAIL|*' -or $line -like 'HASHFAIL|*') { $failed++; $failedNames += $line.Split('|')[1] }
            }
        }
        $pct = [int](100 * ($finished + $failed) / [math]::Max(1, $total))
        if (((Get-Date) - $lastReport).TotalSeconds -ge 2 -or $running.Count -eq 0) {
            Write-Host ("`r  下载进度 {0}/{1}  ({2}%)  失败 {3}" -f ($finished + $failed), $total, $pct, $failed) -ForegroundColor Gray -NoNewline
            $lastReport = Get-Date
        }
        if ($running.Count -eq 0) { break }
        Start-Sleep -Milliseconds 1500
    }
    foreach ($j in $jobList) { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    if ($failed -gt 0) {
        Write-Warn2 ("有 {0} 个文件下载失败（可重跑本程序断点续传）" -f $failed)
        if ($failedNames.Count -gt 0) {
            Write-Info ('  失败清单: ' + (($failedNames | Select-Object -First 10) -join ', ') + $(if ($failedNames.Count -gt 10) { ' …' } else { '' }))
        }
    }
    else { Write-Ok ("全部 {0} 个文件下载完成并通过校验" -f $finished) }
}
