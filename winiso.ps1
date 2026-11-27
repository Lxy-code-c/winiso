# ============================================================================
#  winiso —— Windows ISO 生成终端（UUP 官方源，纯 PowerShell/CMD，无 Python）
#
#  E:\winiso> winiso                交互向导：指定版本 -> 选择操作 -> 开始生成
#              winiso list          列出所有可用正式版构建
#              winiso slim D:\x.iso 直接精简/定制已有 ISO
#              winiso check         检查环境
#
#  流程：UUP 下载官方原版 -> 官方转换器合成 ISO -> 离线精简/定制 -> 重建 ISO
# ============================================================================

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'lib\common.ps1')
. (Join-Path $script:Root 'lib\uup.ps1')
. (Join-Path $script:Root 'lib\converter.ps1')
. (Join-Path $script:Root 'lib\slim.ps1')

$script:RawArgs = @($args)
$script:AutoIndex = $null      # 可选：GUI/命令行显式指定 wim 索引时用；不设就默认 1
$script:NonInteractive = $false

# ----------------------------------------------------------------------------
#  环境检查
# ----------------------------------------------------------------------------
function Do-Check {
    Write-Title '环境检查'
    $bad = 0

    $isAdmin = $false
    try { $isAdmin = [bool](Test-Admin) } catch { }
    if ($isAdmin) { Write-Ok '管理员权限' }
    else { Write-Warn2 '不是管理员（生成时会自动请求提权）' }

    if (Test-CommandExists 'curl.exe') { Write-Ok 'curl.exe（下载 / 调用 API）' }
    else { Write-Err2 '缺少 curl.exe（Windows 10 1803+ 自带）'; $bad++ }

    if (Test-CommandExists 'dism.exe') { Write-Ok 'dism.exe（离线精简）' }
    else { Write-Err2 '缺少 dism.exe'; $bad++ }

    if (Test-CommandExists 'robocopy.exe') { Write-Ok 'robocopy.exe（复制 ISO）' }
    else { Write-Warn2 '缺少 robocopy（可用 xcopy 兜底）' }

    $osc = Resolve-Oscdimg -Preferred $null
    if ($osc) { Write-Ok ('oscdimg: ' + $osc) }
    else { Write-Info '暂未发现 oscdimg（生成时转换器会自带一份，无需预先安装 ADK）' }

    $arch = Get-HostArch
    Write-Info ('本机架构: ' + $arch + '（可生成 amd64 与 arm64 的 ISO，arm64 只能做运行期精简）')

    # 网络
    try {
        $null = Get-JsonFromUrl -Url 'https://api.uupdump.net/listid.php?search=Windows%2011' -Retry 1
        Write-Ok '能访问 uupdump API'
    } catch {
        Write-Err2 '访问 uupdump API 失败（检查网络/代理）'; $bad++
    }

    Write-Host ''
    if ($bad -eq 0) { Write-Ok '环境就绪，可以开始生成' } else { Write-Err2 ('有 ' + $bad + ' 项缺失，请先处理') }
    Write-Host ''
}

# ----------------------------------------------------------------------------
#  下载 / 网络诊断（winiso diag）：真正把官方包 + 清单 + 一个文件走一遍
# ----------------------------------------------------------------------------
function Do-Diag {
    Write-Title '下载 / 网络诊断（把这段输出发回来即可定位问题）'
    $fails = 0
    $tmpBase = $env:TEMP
    if (-not $tmpBase) { $tmpBase = [IO.Path]::GetTempPath() }
    $tmp = Join-Path $tmpBase ('winiso_diag_' + (Get-Date -Format 'HHmmss'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    # 1. 依赖
    $curl = Resolve-Exe 'curl.exe'
    if ($curl) {
        Write-Ok ('curl.exe: ' + $curl)
        try { Write-Info ('  ' + ((& $curl --version 2>$null) | Select-Object -First 1)) } catch { }
    } else { Write-Err2 '找不到 curl.exe'; $fails++ }

    $archTxt = 'unknown'
    try { $archTxt = Get-HostArch } catch { }
    $adminTxt = 'unknown'
    try { $adminTxt = [string](Test-Admin) } catch { }
    Write-Info ('本机架构: ' + $archTxt + '；管理员: ' + $adminTxt)
    try {
        $d = Get-PSDrive -Name ($tmp.Substring(0, 1))
        Write-Info ('临时盘剩余: ' + [math]::Round($d.Free / 1GB, 1) + ' GB')
    } catch { }

    # 2. API：列表
    $uuid = $null
    try {
        $builds = @(Get-UupBuilds -Family 'win11' -Arch 'amd64')
        Write-Ok ('API 正常，win11/amd64 正式版 ' + $builds.Count + ' 个')
        if ($builds.Count -gt 0) {
            $uuid = $builds[0].Uuid
            Write-Info ('  取样构建: ' + $builds[0].Title + '  ' + $builds[0].Build)
        }
    } catch {
        Write-Err2 ('API 不通: ' + $_.Exception.Message)
        $fails++
    }

    if ($uuid) {
        # 3. 语言 / 版本
        $lang = 'zh-cn'; $edition = $null
        try {
            $langs = @(Get-UupLangs -Uuid $uuid)
            Write-Ok ('语言列表 ' + $langs.Count + ' 个')
            if (-not ($langs | Where-Object { $_.Code -eq 'zh-cn' })) { $lang = $langs[0].Code }
        } catch { Write-Err2 ('语言列表失败: ' + $_.Exception.Message); $fails++ }

        try {
            $eds = @(Get-UupEditions -Uuid $uuid -Lang $lang)
            Write-Ok ('版本列表 ' + $eds.Count + ' 个（' + $lang + '）')
            $edition = ($eds | Where-Object { $_.Code -eq 'PROFESSIONAL' } | Select-Object -First 1)
            if (-not $edition) { $edition = $eds[0] }
            if ($edition) { Write-Info ('  取样版本: ' + $edition.Name + ' [' + $edition.Code + ']') }
        } catch { Write-Err2 ('版本列表失败: ' + $_.Exception.Message); $fails++ }

        # 4. 官方脚本包（get.php POST）
        if ($edition) {
            $zip = Join-Path $tmp 'uup.zip'
            try {
                $null = Save-UupPackage -Uuid $uuid -Lang $lang -Edition $edition.Code -OutFile $zip
                Write-Ok ('脚本包 OK (' + (Format-Size (Get-Item -LiteralPath $zip).Length) + ')')
            } catch {
                Write-Err2 ('脚本包失败: ' + $_.Exception.Message)
                $fails++
            }

            # 5. aria2 清单
            $aria = $null; $files = @()
            try {
                $aria = Get-UupAriaScript -Uuid $uuid -Lang $lang -Edition $edition.Code
                $files = @(ConvertFrom-AriaScript $aria)
                Write-Ok ('aria2 清单 OK，共 ' + $files.Count + ' 个文件')
            } catch {
                Write-Err2 ('清单失败: ' + $_.Exception.Message)
                $fails++
            }

            # 6. 真下一个小文件并校验
            if ($files.Count -gt 0) {
                $probe = $files | Where-Object { $_.Out -match '\.(cab|esd)$' } | Select-Object -First 1
                if (-not $probe) { $probe = $files[0] }
                $dst = Join-Path $tmp $probe.Out
                try {
                    Save-UrlToFile -Url $probe.Url -Path $dst
                    $len = (Get-Item -LiteralPath $dst).Length
                    $h = (Get-FileHash -LiteralPath $dst -Algorithm SHA1).Hash.ToLower()
                    if ($probe.Sha1 -and $h -ne $probe.Sha1.ToLower()) {
                        Write-Err2 ('样例文件校验不过: ' + $probe.Out + '（' + (Format-Size $len) + '，SHA1 不符）')
                        $fails++
                    } else {
                        Write-Ok ('样例文件 OK: ' + $probe.Out + '（' + (Format-Size $len) + '，SHA1 一致）')
                    }
                } catch {
                    Write-Err2 ('样例文件下载失败: ' + $_.Exception.Message)
                    $fails++
                }
            }
        }
    }

            # 7. 4 线程并发下载（多文件分片是真实下载走的路）
            if ($uuid -and $files.Count -ge 8) {
                $pick = @($files | Where-Object {
                    $_.Out -notmatch '\.(msu|wim)$' -and
                    $_.Out -notmatch 'Client-Desktop-Required' -and
                    $_.Out -notmatch 'professional_'
                } | Select-Object -First 8)
                $dd = Join-Path $tmp 'dl'
                New-Item -ItemType Directory -Path $dd -Force | Out-Null
                try {
                    Start-ParallelDownload -Items $pick -DestDir $dd -Jobs 4
                    $n = @(Get-ChildItem -LiteralPath $dd -File).Count
                    if ($n -ge $pick.Count) { Write-Ok ('并发下载 OK: ' + $n + '/' + $pick.Count + ' 个文件') }
                    else { Write-Err2 ('并发下载不全: 只有 ' + $n + '/' + $pick.Count + ' 个'); $fails++ }
                } catch {
                    Write-Err2 ('并发下载异常: ' + $_.Exception.Message)
                    $fails++
                }
            }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    if ($fails -eq 0) { Write-Ok '诊断结论：下载链路完好，可以正常生成' }
    else { Write-Err2 ('诊断结论：' + $fails + ' 项有问题，多数是网络/代理或所选组合不可用') }
    Write-Host ''
}

# ----------------------------------------------------------------------------
#  列出构建
# ----------------------------------------------------------------------------
function Do-List {
    param([string]$Family = 'win11', [string]$Arch = 'amd64')
    Write-Title ('可用正式版构建 - ' + (Get-FamilyLabel $Family) + ' / ' + $Arch)
    try {
        $rows = Get-UupBuilds -Family $Family -Arch $Arch
    } catch {
        Write-Err2 $_.Exception.Message
        return
    }
    $i = 0
    foreach ($r in ($rows | Select-Object -First 25)) {
        $i++
        $when = ''
        if ($r.Created) { $when = ([datetimeoffset]::FromUnixTimeSeconds([int64]$r.Created)).LocalDateTime.ToString('yyyy-MM-dd') }
        Write-Host ('   {0,2}) {1,-46} {2,10}   {3}' -f $i, $r.Title, $r.Build, $when) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Info ('共 ' + $rows.Count + ' 个正式版构建（显示前 25 个，最新在上面）')
    Write-Host ''
}

# ----------------------------------------------------------------------------
#  选择：版本 -> 架构 -> 构建 -> 语言 -> 版本种类
# ----------------------------------------------------------------------------
function Select-Target {
    Write-Step 1 3 '指定版本'

    # 1) 家族
    $famItems = @()
    foreach ($f in $script:Families) { $famItems += [pscustomobject]@{ Label = $f.Label; Value = $f.Value; Hint = '' } }
    $family = Read-Choice -Prompt '选择系统家族' -Items $famItems -Default 'win11'
    if (-not $family) { return $null }

    # 2) 手动 UUID
    if ($family -eq 'custom') {
        $raw = Read-TextInput -Prompt '粘贴 UUP 摘要页链接或构建 UUID'
        $uuid = Resolve-UuidFromInput $raw
        if (-not $uuid) { Write-Err2 '没识别出 UUID'; return $null }
        $info = Get-UupBuildInfo -Uuid $uuid
        Write-Ok ('构建: ' + $info.Title + '  ' + $info.Build + '  ' + $info.Arch)
        return [pscustomobject]@{
            Family = 'custom'; Arch = $info.Arch; Uuid = $uuid;
            Title = $info.Title; Build = $info.Build
        }
    }

    # 3) 架构
    $archItems = @(
        [pscustomobject]@{ Label = 'x64 (amd64)'; Value = 'amd64'; Hint = '绝大多数电脑' },
        [pscustomobject]@{ Label = 'ARM64'; Value = 'arm64'; Hint = '骁龙/苹果虚拟机等 ARM 设备' }
    )
    $arch = Read-Choice -Prompt '选择架构' -Items $archItems -Default 'amd64'
    if (-not $arch) { return $null }

    # 4) 构建
    Write-Info '正在查询可用构建 ...'
    $rows = $null
    try { $rows = Get-UupBuilds -Family $family -Arch $arch } catch { Write-Err2 $_.Exception.Message; return $null }

    $items = @()
    foreach ($r in ($rows | Select-Object -First 10)) {
        $when = ''
        if ($r.Created) { $when = ([datetimeoffset]::FromUnixTimeSeconds([int64]$r.Created)).LocalDateTime.ToString('yyyy-MM') }
        $items += [pscustomobject]@{ Label = ($r.Title + '   ' + $r.Build); Value = $r.Uuid; Hint = $when }
    }
    $items += [pscustomobject]@{ Label = '显示更多 / 手动输入 UUID'; Value = 'MORE'; Hint = '' }

    $pick = Read-Choice -Prompt ('选择具体构建（共 ' + $rows.Count + ' 个正式版）') -Items $items -Default $rows[0].Uuid
    if (-not $pick) { return $null }
    if ($pick -eq 'MORE') {
        Write-Host ''
        for ($i = 0; $i -lt [math]::Min(40, $rows.Count); $i++) {
            Write-Host ('   {0,2}) {1,-46} {2}' -f ($i + 1), $rows[$i].Title, $rows[$i].Build) -ForegroundColor Gray
        }
        Write-Host '   也可直接粘贴 UUID/链接' -ForegroundColor Gray
        $raw = Read-TextInput -Prompt '编号 或 UUID'
        $num = 0
        if ([int]::TryParse($raw, [ref]$num) -and $num -ge 1 -and $num -le $rows.Count) { $pick = $rows[$num - 1].Uuid }
        else {
            $u = Resolve-UuidFromInput $raw
            if (-not $u) { Write-Err2 '无效输入'; return $null }
            $pick = $u
        }
    }

    $row = $rows | Where-Object { $_.Uuid -eq $pick } | Select-Object -First 1
    if ($row) { Write-Ok ('已选: ' + $row.Title + '  ' + $row.Build + '  ' + $row.Arch) }
    else {
        $info = Get-UupBuildInfo -Uuid $pick
        $row = [pscustomobject]@{ Title = $info.Title; Build = $info.Build; Arch = $info.Arch; Uuid = $pick }
        Write-Ok ('已选: ' + $row.Title + '  ' + $row.Build)
    }
    return [pscustomobject]@{ Family = $family; Arch = $row.Arch; Uuid = $row.Uuid; Title = $row.Title; Build = $row.Build }
}

function Select-LangEdition {
    param([string]$Uuid, [string]$Arch)
    Write-Host ''
    Write-Info '查询语言 ...'
    $langs = Get-UupLangs -Uuid $Uuid
    $items = Get-LangChoices -Langs $langs
    $lang = Read-Choice -Prompt '选择语言' -Items $items -Default 'zh-cn'
    if (-not $lang) { return $null }

    Write-Host ''
    Write-Info ('查询 ' + $lang + ' 的版本 ...')
    $eds = Get-UupEditions -Uuid $Uuid -Lang $lang
    $edItems = @()
    foreach ($e in $eds) {
        $hint = $e.Code
        # 标出常见可升级/可数字激活的版本
        if ($e.Code -match 'PROFESSIONAL') { $hint = '专业版（推荐，可数字激活）' }
        elseif ($e.Code -match 'CORE') { $hint = '家庭版' }
        elseif ($e.Code -match 'ENTERPRISE') { $hint = '企业版（需 KMS/批量授权）' }
        elseif ($e.Code -match 'EDUCATION') { $hint = '教育版' }
        $edItems += [pscustomobject]@{ Label = ($e.Name + '  [' + $e.Code + ']'); Value = $e.Code; Hint = $hint }
    }
    if ($edItems.Count -eq 0) { Write-Err2 ('该语言没有可用版本'); return $null }
    $edition = Read-Choice -Prompt '选择版本' -Items $edItems -Default $edItems[0].Value
    if (-not $edition) { return $null }

    return [pscustomobject]@{ Lang = $lang; Edition = $edition }
}

# ----------------------------------------------------------------------------
#  选择操作
# ----------------------------------------------------------------------------
function Select-Operations {
    Write-Step 2 3 '选择操作'
    $items = @(
        [pscustomobject]@{ Label = '精简组件'; Value = 'slim'; On = $true; Hint = '删 Copilot/Cortana/Bing/Xbox 等预置应用与冗余功能包' },
        [pscustomobject]@{ Label = '广告与追踪拦截'; Value = 'adblock'; On = $true; Hint = '写 hosts，装机即全局屏蔽广告/遥测域名' },
        [pscustomobject]@{ Label = 'macOS 风格'; Value = 'mac'; On = $true; Hint = '居中任务栏/深色/透明/自绘壁纸/Spotlight；勾选后进入美化细节子菜单' },
        [pscustomobject]@{ Label = '无人值守安装'; Value = 'unattend'; On = $true; Hint = '跳过 TPM/安全启动检测与联网 OOBE' },
        [pscustomobject]@{ Label = '移除 WinRE'; Value = 'nowinre'; On = $false; Hint = '省约 500MB，但失去恢复环境' },
        [pscustomobject]@{ Label = '移除 Edge 浏览器'; Value = 'noedge'; On = $false; Hint = '激进选项，可能影响部分系统组件' },
        [pscustomobject]@{ Label = '集成 .NET Framework 3.5'; Value = 'netfx3'; On = $false; Hint = '部分老软件需要' },
        [pscustomobject]@{ Label = '清理组件库 (ResetBase)'; Value = 'resetbase'; On = $false; Hint = '显著缩小体积，但之后无法卸载更新' },
        [pscustomobject]@{ Label = '跳过商店应用下载'; Value = 'skipapps'; On = $true; Hint = '更快；同时会让商店应用不被预置' }
    )
    $sel = Read-MultiChoice -Prompt '勾选要执行的操作（输入编号切换，回车确认）' -Items $items

    $beauty = @{ Theme = 'dark'; SmallIcons = $true; Seconds = $true; Explorer = $true; Wallpaper = $true; Spotlight = $true; Dock = $false }
    if ($sel -contains 'mac') {
        Write-Host ''
        Write-Info '—— 美化细节（直接回车=用默认）——'
        $themeItems = @(
            [pscustomobject]@{ Label = '深色主题'; Value = 'dark'; Hint = '接近 macOS 深色外观' },
            [pscustomobject]@{ Label = '浅色主题'; Value = 'light'; Hint = '亮色，适合白天' }
        )
        $theme = Read-Choice -Prompt '主题' -Items $themeItems -Default 'dark'
        if ($theme) { $beauty.Theme = $theme }

        $beautyItems = @(
            [pscustomobject]@{ Label = '任务栏小图标'; Value = 'SmallIcons'; On = $true; Hint = '任务栏更纤细' },
            [pscustomobject]@{ Label = '时钟显示秒'; Value = 'Seconds'; On = $true; Hint = '' },
            [pscustomobject]@{ Label = '资源管理器整理'; Value = 'Explorer'; On = $true; Hint = '显示扩展名 / 默认打开此电脑 / 紧凑视图' },
            [pscustomobject]@{ Label = '自绘渐变壁纸'; Value = 'Wallpaper'; On = $true; Hint = '程序自己画，无版权素材' },
            [pscustomobject]@{ Label = 'Spotlight 全局搜索'; Value = 'Spotlight'; On = $true; Hint = '装 PowerToys Run，Alt+Space ≈ ⌘+Space（需联网）' },
            [pscustomobject]@{ Label = '程序坞 Dock'; Value = 'Dock'; On = $false; Hint = '装 Nexus Dock（需联网，非微软商店应用）' }
        )
        $b = Read-MultiChoice -Prompt '美化选项（输入编号切换，回车确认）' -Items $beautyItems
        $beauty.SmallIcons = ($b -contains 'SmallIcons')
        $beauty.Seconds    = ($b -contains 'Seconds')
        $beauty.Explorer   = ($b -contains 'Explorer')
        $beauty.Wallpaper  = ($b -contains 'Wallpaper')
        $beauty.Spotlight  = ($b -contains 'Spotlight')
        $beauty.Dock       = ($b -contains 'Dock')
    }
    return [pscustomobject]@{ Ops = $sel; Beauty = $beauty }
}

# ----------------------------------------------------------------------------
#  工作目录 / 输出目录
# ----------------------------------------------------------------------------
function Select-Paths {
    param([string]$Build, [string]$Title)
    Write-Host ''
    $defWork = ''
    # 选可用空间最大的盘
    $best = $null; $bestFree = -1
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($d.Free -ne $null -and $d.Free -gt $bestFree -and $d.Name -match '^[A-Z]$') { $best = $d; $bestFree = $d.Free }
    }
    # 默认放 E 盘（约定：工作目录/产出别放 C 盘），E 盘不够用再退到空间最大的盘
    $eDrive = Get-PSDrive -Name 'E' -ErrorAction SilentlyContinue
    if ($eDrive -and $eDrive.Free -gt 20GB) { $defWork = 'E:\winiso\work' }
    elseif ($best) { $defWork = ($best.Name + ':\winiso\work') }

    Write-Info ('工作目录需要约 30 GB 空闲空间（下载 7-8 GB + 解包 6 GB + 成品 ISO 6-8 GB）')
    $work = Read-TextInput -Prompt '工作目录' -Default $defWork
    $out = Read-TextInput -Prompt '成品 ISO 输出目录' -Default (Join-Path (Split-Path -Parent $work) 'ISO')

    return [pscustomobject]@{ Work = $work; Out = $out }
}

# ----------------------------------------------------------------------------
#  生成主流程
# ----------------------------------------------------------------------------
function Invoke-Generate {
    param(
        [string]$Family, [string]$Arch, [string]$Uuid, [string]$Title,
        [string]$Lang, [string]$Edition,
        [array]$Ops,
        [hashtable]$Beauty,
        [string]$WorkDir, [string]$OutDir
    )

    Ensure-Admin

    $t0 = Get-Date
    $safeName = ($Title -replace '[\\/:*?"<>|]', '_') + '_' + $Arch + '_' + $Lang + '_' + $Edition
    $uidShort = $(if ($Uuid -and $Uuid.Length -ge 8) { $Uuid.Substring(0, 8) } else { 'build' })
    $projDir = Join-Path $WorkDir $uidShort
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null
    # 原版 ISO 缓存：放在 $stage 外面，$stage 每次会重建，只有这里能跨轮次复用
    # 文件名里必须带语言：同一个构建换语言时不会误用上一轮的原版 ISO
    $baseIso = Join-Path $projDir ('base_' + $Arch + '_' + $Lang + '_' + $Edition + '.iso')
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $free = Get-FreeSpaceGB $WorkDir
    if ($free -ge 0 -and $free -lt 25) { Write-Warn2 ('工作盘只有 ' + $free + ' GB 空闲，可能不够（建议 30 GB+）') }
    # 输出盘也要够（要写一份 5-6 GB 的成品 ISO），否则一路跑完才在拷贝这步失败
    $outFree = Get-FreeSpaceGB $OutDir
    if ($outFree -ge 0 -and $outFree -lt 8) {
        Write-Err2 ('输出目录所在盘只剩 ' + $outFree + ' GB，写不下成品 ISO（需要 8 GB 以上）')
        Write-Info ('换个输出目录，或先清点空间：' + $OutDir)
        return $null
    }

    Write-Step 3 3 '开始生成'
    Write-Info ('目标: ' + $Title + '  ' + $Arch + '  ' + $Lang + '  ' + $Edition)
    Write-Info ('项目目录: ' + $projDir)
    Write-Host ''

    $iso1 = $null
    # 缓存门槛必须够高：任何一个 Windows 安装 ISO 都 >= 2 GB。原门槛 100 MB 时，
    # 上次拷贝到一半被中断留下的残缺文件会被当成"完好缓存"直接复用，最后打出来的
    # ISO 是坏的，而且日志里一句提示都没有。
    $cacheOk = $false
    if (Test-Path -LiteralPath $baseIso) {
        $cacheLen = (Get-Item -LiteralPath $baseIso).Length
        if ($cacheLen -ge 2GB) { $cacheOk = $true }
        elseif ($cacheLen -gt 0) {
            Write-Warn2 ('发现不完整的原版 ISO 缓存（' + [math]::Round($cacheLen / 1GB, 2) + ' GB），已丢弃重做')
            Remove-Item -LiteralPath $baseIso -Force -ErrorAction SilentlyContinue
        }
    }
    if ($cacheOk) {
        Write-Ok ('发现上次已合成的原版 ISO，跳过下载与转换: ' + (Split-Path $baseIso -Leaf))
        $iso1 = $baseIso
    }
    if (-not $iso1) {

    # ---- 1. 取官方脚本包 ----
    Write-Info '[1/5] 获取 UUP 官方脚本包 ...'
    $zip = Join-Path $projDir 'uup.zip'
    try {
        $null = Save-UupPackage -Uuid $Uuid -Lang $Lang -Edition $Edition -OutFile $zip
        Write-Ok ('脚本包已下载 (' + (Format-Size (Get-Item $zip).Length) + ')')
    } catch {
        Write-Err2 $_.Exception.Message
        Write-Info '若该组合下架，请在向导里换一个构建或语言。'
        return $null
    }

    # 解包（覆盖同名文件，但保留已下好的 UUPs 目录）
    Write-Info '解包脚本 ...'
    $stage = Join-Path $projDir 'pkg'
    $uupKeep = Join-Path $projDir 'UUPs_keep'
    if (Test-Path $stage) {
        # 关键：重建 stage 前先把已下好的 UUPs（6-8 GB）挪出去，否则"断点续跑"等于从头再下
        $oldUup = Join-Path $stage 'UUPs'
        if (Test-Path $oldUup) {
            if (Test-Path $uupKeep) { Remove-Item $uupKeep -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $oldUup -Destination $uupKeep -Force
        }
        Remove-Item $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $stage -Force
    if (Test-Path $uupKeep) { Move-Item -LiteralPath $uupKeep -Destination (Join-Path $stage 'UUPs') -Force }

    # ---- 2. 转换器 ----
    Write-Info '[2/5] 准备官方转换器 ...'
    $conv = Initialize-Converter -WorkDir $stage

    # ---- 3. 下载 UUP 集 ----
    Write-Info '[3/5] 下载 UUP 文件集 ...'
    $uupDir = Join-Path $stage 'UUPs'
    New-Item -ItemType Directory -Path $uupDir -Force | Out-Null
    $aria = Get-UupAriaScript -Uuid $Uuid -Lang $Lang -Edition $Edition
    $files = ConvertFrom-AriaScript $aria
    Write-Info ('清单共 ' + $files.Count + ' 个文件')
    if ($files.Count -eq 0) { Write-Err2 '下载清单为空'; return $null }

    # 只下缺失/校验不过的文件（断点续传时不会重下已完成的部分）
    $todo = @()
    $existing = 0
    foreach ($f in $files) {
        $target = Join-Path $uupDir $f.Out
        if ((Test-Path $target) -and (Get-Item $target).Length -gt 0) {
            if ($f.Sha1) {
                $h = (Get-FileHash -Path $target -Algorithm SHA1).Hash.ToLower()
                if ($h -eq $f.Sha1.ToLower()) { $existing++; continue }
            } else { $existing++; continue }
            Remove-Item $target -Force -ErrorAction SilentlyContinue
        }
        $todo += $f
    }
    if ($existing -gt 0) { Write-Ok ('本地已完好 ' + $existing + ' 个文件，跳过') }
    if ($todo.Count -gt 0) {
        Start-ParallelDownload -Items $todo -DestDir $uupDir -Jobs 4
    } else { Write-Ok '文件都已在本地' }

    # 完整性兜底：缺文件（或被截断）就不要往下走，避免转换器报难懂的错
    $missing = @()
    foreach ($f in $files) {
        $p = Join-Path $uupDir $f.Out
        if (-not (Test-Path -LiteralPath $p)) { $missing += $f.Out; continue }
        if ($f.Sha1) {
            $h = (Get-FileHash -Path $p -Algorithm SHA1).Hash.ToLower()
            if ($h -ne $f.Sha1.ToLower()) {
                Write-Warn2 ('文件损坏，已删除待重下: ' + $f.Out)
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                $missing += $f.Out
            }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Err2 ('还缺 ' + $missing.Count + ' 个文件，转换中止（重跑本程序会接着下）')
        foreach ($m in ($missing | Select-Object -First 5)) { Write-Info ('  缺: ' + $m) }
        return $null
    }

    # 商店应用
    if (-not ($Ops -contains 'skipapps')) {
        Write-Info '下载商店应用（可选步骤，耗时较长）...'
        try {
            $appAria = Get-UupAppAriaScript -Uuid $Uuid
            $appFiles = ConvertFrom-AriaScript $appAria
            $appTodo = @()
            foreach ($f in $appFiles) {
                $t = Join-Path $uupDir $f.Out
                if (-not (Test-Path $t)) { $appTodo += $f }
            }
            if ($appTodo.Count -gt 0) { Start-ParallelDownload -Items $appTodo -DestDir $uupDir -Jobs 4 }
        } catch { Write-Warn2 ('商店应用下载跳过: ' + $_.Exception.Message) }
    }

    # ---- 4. 转换 ----
    Write-Info '[4/5] 合成映像并打包 ISO ...'
    $cfgOpt = @{
        AddUpdates = $true
        Cleanup    = ($Ops -contains 'resetbase')
        ResetBase  = ($Ops -contains 'resetbase')
        NetFx3     = ($Ops -contains 'netfx3')
        SkipWinRE  = ($Ops -contains 'nowinre')
        # 官方转换器的 SkipEdge：0=不做处理，1=不集成 Edge 更新组件，2=真正移除 Edge
        # （原来的写法给 1，等于"没删 Edge"，和界面上的"移除 Edge 浏览器"不符）
        SkipEdge   = $(if ($Ops -contains 'noedge') { 2 } else { 0 })
        SkipApps   = ($Ops -contains 'skipapps')
    }
    New-ConvertConfig -WorkDir $stage -Opt $cfgOpt | Out-Null
    try {
        $iso1 = Invoke-Convert -WorkDir $stage
    } catch {
        Write-Err2 $_.Exception.Message
        return $null
    }
    # 立刻把原版 ISO 挪到项目目录缓存，后面的精简失败也不至于白下载一遍
    try {
        if (-not (Test-Path -LiteralPath $baseIso)) {
            Move-Item -LiteralPath $iso1 -Destination $baseIso -Force
            $iso1 = $baseIso
            Write-Ok ('原版 ISO 已缓存: ' + (Split-Path $baseIso -Leaf))
        }
    } catch {
        Write-Warn2 ('缓存原版 ISO 失败（不影响本次结果）: ' + $_.Exception.Message)
    }
    }   # endif (-not $iso1) —— 下载/转换段结束

    # ---- 5. 精简/定制 ----
    $selections = @()
    if ($Ops -contains 'slim') { $selections += 'slim' }
    if ($Ops -contains 'adblock') { $selections += 'adblock' }
    if ($Ops -contains 'mac') { $selections += 'mac' }
    if ($Ops -contains 'unattend') { $selections += 'unattend' }
    $needSlim = ($selections.Count -gt 0 -or ($Ops -contains 'nowinre'))

    $finalIso = $iso1
    if ($needSlim) {
        Write-Info '[5/5] 离线精简与定制 ...'
        $hostArch = Get-HostArch
        $offline = ($Arch -eq $hostArch)   # 跨架构无法用 DISM 挂载
        if (-not $offline) {
            Write-Warn2 ('目标 ' + $Arch + ' 与本机 ' + $hostArch + ' 不同：只做运行期精简（首次登录时清理）')
        }

        $data = Get-DebloatData -Family $Family
        $opts = @{
            Offline     = $offline
            KeepWinRE   = -not ($Ops -contains 'nowinre')
            Appx        = @()
            Pkg         = @()
            AdDomains   = @()
            Tweaks      = @()
            Autounattend = $null
            FirstLogon  = $null
        }
        if ($Ops -contains 'slim') { $opts.Appx = $data.Appx; $opts.Pkg = $data.Pkg }
        if ($Ops -contains 'adblock') { $opts.AdDomains = @(Get-AdDomains) }
        if (-not $Beauty) { $Beauty = @{ Theme = 'dark'; SmallIcons = $true; Seconds = $true; Explorer = $true; Wallpaper = $true; Spotlight = $true; Dock = $false } }
        if ($Ops -contains 'mac') { $opts.Tweaks = @(Get-MacTweaks -Opt $Beauty) }
        if ($Ops -contains 'unattend') {
            $opts.Autounattend = Build-Autounattend -Arch $Arch -Lang $Lang -Opt @{ RuntimeTweaks = ($Ops -contains 'slim' -or $Ops -contains 'mac') }
        }
        if ($Ops -contains 'slim' -or $Ops -contains 'mac') {
            $appxForScript = @()
            if ($Ops -contains 'slim') { $appxForScript = $data.Appx }
            $opts.FirstLogon = Build-FirstLogonScript -AppxList $appxForScript -Opt @{
                Tweaks    = $opts.Tweaks
                Wallpaper = [bool]$Beauty.Wallpaper
                Spotlight = [bool]$Beauty.Spotlight
                Dock      = [bool]$Beauty.Dock
                Theme     = $Beauty.Theme
            }
        }

        $opts.OutIso = Join-Path $OutDir ($safeName + '.iso')
        # 命中缓存 ISO 时上面那段（含 $conv）根本没执行，$conv 是空的；
        # 而转换器自带的光盘打包工具就在 <项目目录>\pkg\bin 里，直接指过去，不要只指望 ADK
        $oscHint = $null
        if ($conv -and $conv.Oscdimg) { $oscHint = $conv.Oscdimg }
        else {
            foreach ($n in @('oscdimg.exe', 'cdimage.exe')) {
                $cand = Join-Path $projDir ('pkg\bin\' + $n)
                if (Test-Path -LiteralPath $cand) { $oscHint = $cand; break }
            }
        }
        $osc = Resolve-Oscdimg -Preferred $oscHint
        if (-not $osc) {
            Write-Err2 '找不到 oscdimg（转换器没自带、也没装 ADK），无法重建 ISO'
            Write-Info ('已转换好的原版 ISO 在: ' + $iso1)
            return $null
        }
        Write-Host ''
        $finalIso = Invoke-SlimIso -IsoPath $iso1 -WorkRoot $projDir -Opt $opts -Oscdimg $osc
    } else {
        Write-Info '未选择精简/定制，直接使用原版 ISO'
        $dst = Join-Path $OutDir ($safeName + '.iso')
        Copy-Item $iso1 $dst -Force
        $finalIso = $dst
    }

    $elapsed = (Get-Date) - $t0
    Write-Host ''
    Write-Title '生成完成'
    Write-Ok ('ISO: ' + $finalIso)
    Write-Ok ('大小: ' + (Format-Size (Get-Item $finalIso).Length))
    Write-Info ('耗时: ' + [int]$elapsed.TotalMinutes + ' 分钟')
    Write-Host ''
    Write-Info '提示：arm64 目标请在对应设备上安装；精简版首次开机可能需要 3-10 分钟。'
    Write-Host ''
    return $finalIso
}

# ----------------------------------------------------------------------------
#  向导
# ----------------------------------------------------------------------------
function Do-Wizard {
    Write-Title 'winiso —— Windows ISO 生成终端（UUP 官方源 · 无 Python）'
    Write-Info '三步：指定版本 → 选择操作 → 开始生成'

    $target = Select-Target
    if (-not $target) { Write-Info '已取消'; return }

    $le = Select-LangEdition -Uuid $target.Uuid -Arch $target.Arch
    if (-not $le) { Write-Info '已取消'; return }

    $opsSel = Select-Operations
    if ($null -eq $opsSel) { Write-Info '已取消'; return }
    $ops = $opsSel.Ops
    $beauty = $opsSel.Beauty

    $paths = Select-Paths -Build $target.Build -Title $target.Title

    # 汇总确认
    Write-Host ''
    Write-Host '  ┌ 生成任务 ─────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ('  │ 版本   ' + $target.Title + '  ' + $target.Build) -ForegroundColor White
    Write-Host ('  │ 架构   ' + $target.Arch) -ForegroundColor White
    Write-Host ('  │ 语言   ' + $le.Lang + '    版本   ' + $le.Edition) -ForegroundColor White
    $opLabel = '无（仅生成原版 ISO）'
    if ($ops -and $ops.Count -gt 0) { $opLabel = ($ops -join ', ') }
    Write-Host ('  │ 操作   ' + $opLabel) -ForegroundColor White
    Write-Host ('  │ 工作   ' + $paths.Work) -ForegroundColor White
    Write-Host ('  │ 输出   ' + $paths.Out) -ForegroundColor White
    Write-Host '  └───────────────────────────────────────────────────' -ForegroundColor DarkCyan
    if (-not (Read-YesNo -Prompt '开始生成？' -Default $true)) { Write-Info '已取消'; return }

    $null = Invoke-Generate -Family $target.Family -Arch $target.Arch -Uuid $target.Uuid -Title $target.Title `
        -Lang $le.Lang -Edition $le.Edition -Ops $ops -Beauty $beauty -WorkDir $paths.Work -OutDir $paths.Out
}

# ----------------------------------------------------------------------------
#  直接精简已有 ISO
# ----------------------------------------------------------------------------
function Do-SlimExisting {
    param([string]$Iso)
    if (-not $Iso) { $Iso = Read-TextInput -Prompt '要精简的 ISO 路径' }
    if (-not (Test-Path $Iso)) { Write-Err2 ('找不到文件: ' + $Iso); return }
    Ensure-Admin

    $items = @(
        [pscustomobject]@{ Label = '精简组件'; Value = 'slim'; On = $true; Hint = '' },
        [pscustomobject]@{ Label = '广告与追踪拦截'; Value = 'adblock'; On = $true; Hint = '' },
        [pscustomobject]@{ Label = 'macOS 风格'; Value = 'mac'; On = $true; Hint = '' },
        [pscustomobject]@{ Label = '无人值守安装'; Value = 'unattend'; On = $true; Hint = '' },
        [pscustomobject]@{ Label = '移除 WinRE'; Value = 'nowinre'; On = $false; Hint = '' }
    )
    $ops = Read-MultiChoice -Prompt '选择操作' -Items $items

    $beauty = @{ Theme = 'dark'; SmallIcons = $true; Seconds = $true; Explorer = $true; Wallpaper = $true; Spotlight = $true; Dock = $false }
    if ($ops -contains 'mac') {
        Write-Host ''
        Write-Info '—— 美化细节（直接回车=用默认）——'
        $themeItems = @(
            [pscustomobject]@{ Label = '深色主题'; Value = 'dark'; Hint = '' },
            [pscustomobject]@{ Label = '浅色主题'; Value = 'light'; Hint = '' }
        )
        $theme = Read-Choice -Prompt '主题' -Items $themeItems -Default 'dark'
        if ($theme) { $beauty.Theme = $theme }
        $beautyItems = @(
            [pscustomobject]@{ Label = '任务栏小图标'; Value = 'SmallIcons'; On = $true; Hint = '' },
            [pscustomobject]@{ Label = '时钟显示秒'; Value = 'Seconds'; On = $true; Hint = '' },
            [pscustomobject]@{ Label = '资源管理器整理'; Value = 'Explorer'; On = $true; Hint = '显示扩展名/打开此电脑/紧凑视图' },
            [pscustomobject]@{ Label = '自绘渐变壁纸'; Value = 'Wallpaper'; On = $true; Hint = '' },
            [pscustomobject]@{ Label = 'Spotlight 全局搜索'; Value = 'Spotlight'; On = $true; Hint = 'PowerToys Run（需联网）' },
            [pscustomobject]@{ Label = '程序坞 Dock'; Value = 'Dock'; On = $false; Hint = 'Nexus Dock（需联网）' }
        )
        $b = Read-MultiChoice -Prompt '美化选项' -Items $beautyItems
        $beauty.SmallIcons = ($b -contains 'SmallIcons')
        $beauty.Seconds    = ($b -contains 'Seconds')
        $beauty.Explorer   = ($b -contains 'Explorer')
        $beauty.Wallpaper  = ($b -contains 'Wallpaper')
        $beauty.Spotlight  = ($b -contains 'Spotlight')
        $beauty.Dock       = ($b -contains 'Dock')
    }

    $family = 'win11'
    if (-not (Read-YesNo -Prompt '这套 ISO 是 Windows 10 吗？' -Default $false)) { $family = 'win11' } else { $family = 'win10' }

    # 架构决定能否离线挂载：arm64 映像在 amd64 主机上 DISM 挂不上，只能做运行期精简
    $archItems = @(
        [pscustomobject]@{ Label = 'x64 (amd64)'; Value = 'amd64'; Hint = '绝大多数电脑' },
        [pscustomobject]@{ Label = 'ARM64'; Value = 'arm64'; Hint = '骁龙/ARM 设备' }
    )
    $archOfIso = Read-Choice -Prompt '这套 ISO 的架构' -Items $archItems -Default (Get-HostArch)
    if (-not $archOfIso) { $archOfIso = 'amd64' }
    $offline = ($archOfIso -eq (Get-HostArch))
    if (-not $offline) { Write-Warn2 ('目标 ' + $archOfIso + ' 与本机 ' + (Get-HostArch) + ' 不同：只能做运行期精简（首次登录清理）') }

    $outDir = Read-TextInput -Prompt '输出目录' -Default (Split-Path -Parent $Iso)
    $work = Read-TextInput -Prompt '工作目录' -Default (Join-Path $outDir '_winiso_work')

    # 需要一个 oscdimg：先准备转换器（含 oscdimg），失败则用系统里的
    $conv = $null
    try {
        $stage = Join-Path $work 'conv'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $conv = Initialize-Converter -WorkDir $stage
    } catch {
        Write-Warn2 ('无法准备转换器: ' + $_.Exception.Message)
    }
    $preferred = $null
    if ($conv) { $preferred = $conv.Oscdimg }
    $oscdimg = Resolve-Oscdimg -Preferred $preferred
    if (-not $oscdimg) { Write-Err2 '缺少 oscdimg（ADK 与转换器都没有），无法重建 ISO'; return }

    $data = Get-DebloatData -Family $family
    $opts = @{
        Offline     = $offline
        KeepWinRE   = -not ($ops -contains 'nowinre')
        Appx        = $(if ($ops -contains 'slim') { $data.Appx } else { @() })
        Pkg         = $(if ($ops -contains 'slim') { $data.Pkg } else { @() })
        AdDomains   = $(if ($ops -contains 'adblock') { @(Get-AdDomains) } else { @() })
        Tweaks      = $(if ($ops -contains 'mac') { @(Get-MacTweaks -Opt $beauty) } else { @() })
        Autounattend = $(if ($ops -contains 'unattend') { Build-Autounattend -Arch $archOfIso -Lang 'zh-cn' -Opt @{ RuntimeTweaks = ($ops -contains 'slim' -or $ops -contains 'mac') } } else { $null })
        FirstLogon  = $(if ($ops -contains 'slim' -or $ops -contains 'mac') { Build-FirstLogonScript -AppxList $(if ($ops -contains 'slim') { $data.Appx } else { @() }) -Opt @{ Tweaks = $(if ($ops -contains 'mac') { @(Get-MacTweaks -Opt $beauty) } else { @() }); Wallpaper = [bool]$beauty.Wallpaper; Spotlight = [bool]$beauty.Spotlight; Dock = [bool]$beauty.Dock } } else { $null })
        OutIso      = (Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($Iso) + '.winiso.iso'))
    }
    try {
        $null = Invoke-SlimIso -IsoPath $Iso -WorkRoot $work -Opt $opts -Oscdimg $oscdimg
    } catch {
        Write-Err2 $_.Exception.Message
    }
}


# ----------------------------------------------------------------------------
#  只生成官方下载脚本包（等同 UUP dump 网页上"下载脚本包"）
# ----------------------------------------------------------------------------
function Do-Pack {
    Write-Title '生成 UUP 官方脚本包'
    $target = Select-Target
    if (-not $target) { return }
    $le = Select-LangEdition -Uuid $target.Uuid -Arch $target.Arch
    if (-not $le) { return }
    $out = Read-TextInput -Prompt '保存到目录' -Default (Join-Path (Get-Location) ('uup-' + $target.Build))
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    $zip = Join-Path $out ('UUP-' + $target.Build + '_' + $target.Arch + '_' + $le.Lang + '_' + $le.Edition + '.zip')
    try {
        $null = Save-UupPackage -Uuid $target.Uuid -Lang $le.Lang -Edition $le.Edition -OutFile $zip
    } catch {
        Write-Err2 $_.Exception.Message
        return
    }
    Expand-Archive -Path $zip -DestinationPath $out -Force
    Write-Host ''
    Write-Ok ('脚本包已生成: ' + $out)
    Write-Info '用法：进入该目录，右键"以管理员身份运行" uup_download_windows.cmd，它会自动下载并合成 ISO。'
    Write-Info '（需要管理员权限；脚本会自己下载 aria2 与转换器）'
    Write-Host ''
}

# ----------------------------------------------------------------------------
#  帮助 / 入口
# ----------------------------------------------------------------------------
function Show-Help {
    Write-Title 'winiso —— Windows ISO 生成终端'
@"
  用法:
    winiso                 交互向导（指定版本 → 选择操作 → 开始生成）
    winiso list            列出所有正式版构建（win11/win10/server × x64/arm64）
    winiso list win10 arm64
    winiso pack            只生成 UUP 官方脚本包（等同网页版下载脚本）
    winiso slim <iso>      精简/定制已有的 ISO（例如你自己的 VLSC 原版）
    winiso check           检查环境
    winiso diag            下载/网络诊断（下载失败时先跑这个）

  生成原理:
    1. UUP dump 官方源：拉取微软 Windows Update 的原版文件集
    2. 官方转换器 uup-converter-wimlib 合成映像（自带 wimlib + oscdimg + 引导文件）
    3. DISM 离线精简：删预置应用/功能包、写 hosts 广告拦截、注册表动态调整
    4. oscdimg 重建可引导 ISO（BIOS + UEFI 双引导）

  无需 Python、无需安装 ADK、无需模板 ISO。
  生成目录结构:
    <工作目录>\<uuid前8位>\  下载与转换现场（可断点续传）
    输出目录\<版本>_<架构>_<语言>_<版本种类>.iso
"@
    Write-Host ''
}

# ----------------------------------------------------------------------------
#  非交互执行（供 GUI 调用）：winiso run -ParamFile <json>
# ----------------------------------------------------------------------------
function Do-Run {
    param([string]$ParamFile)
    if (-not $ParamFile -or -not (Test-Path -LiteralPath $ParamFile)) {
        Write-Err2 ('参数文件不存在: ' + $ParamFile)
        Write-Host 'WINISO_RESULT_ERROR=参数文件不存在'
        exit 2
    }
    $script:NonInteractive = $true
    $script:SkipElevate = $true
    try {
        $p = (Get-Content -LiteralPath $ParamFile -Raw -Encoding UTF8) | ConvertFrom-Json
    } catch {
        Write-Err2 '参数文件不是合法 JSON'
        Write-Host 'WINISO_RESULT_ERROR=参数文件解析失败'
        exit 2
    }

    $ops = @($p.Ops)
    $beauty = @{ Theme = 'dark'; SmallIcons = $true; Seconds = $true; Explorer = $true; Wallpaper = $true; Spotlight = $true; Dock = $false }
    if ($p.Beauty) {
        foreach ($k in $p.Beauty.PSObject.Properties) { $beauty[$k.Name] = $k.Value }
    }

    Write-Title '开始生成（图形界面任务）'
    Write-Info ('目标: ' + $p.Title + '  ' + $p.Arch + '  ' + $p.Lang + '  ' + $p.Edition)
    Write-Info ('操作: ' + ($ops -join ', '))

    try {
        $final = Invoke-Generate -Family $p.Family -Arch $p.Arch -Uuid $p.Uuid -Title $p.Title `
            -Lang $p.Lang -Edition $p.Edition -Ops $ops -Beauty $beauty `
            -WorkDir $p.WorkDir -OutDir $p.OutDir
        if ($final) {
            Write-Host ''
            Write-Host ('WINISO_RESULT_ISO=' + $final)
            exit 0
        }
        Write-Host 'WINISO_RESULT_ERROR=没有产出 ISO'
        exit 3
    } catch {
        Write-Err2 $_.Exception.Message
        Write-Host ('WINISO_RESULT_ERROR=' + $_.Exception.Message)
        exit 1
    }
}

$cmd = 'wizard'
if ($script:RawArgs.Count -gt 0) { $cmd = $script:RawArgs[0] }

switch -Regex ($cmd) {
    '^(wizard|-w)$'              { Do-Wizard }
    '^(list|ls)$'                {
        $f = 'win11'; $a = 'amd64'
        if ($script:RawArgs.Count -gt 1) { $f = $script:RawArgs[1] }
        if ($script:RawArgs.Count -gt 2) { $a = $script:RawArgs[2] }
        Do-List -Family $f -Arch $a
    }
    '^(check)$'                  { Do-Check }
    '^(diag|diagnose)$'          { Do-Diag }
    '^(pack)$'                   { Do-Pack }
    '^(slim)$'                   {
        $iso = ''
        if ($script:RawArgs.Count -gt 1) { $iso = $script:RawArgs[1] }
        Do-SlimExisting -Iso $iso
    }
    '^(run)$'                    {
        $pf = ''
        if ($script:RawArgs.Count -gt 1) { $pf = $script:RawArgs[1] }
        Do-Run -ParamFile $pf
    }
    '^(help|-h|--help|/?)$'      { Show-Help }
    default {
        Write-Warn2 ('未知命令: ' + $cmd)
        Show-Help
    }
}
