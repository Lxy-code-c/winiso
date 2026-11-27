# ============================================================================
#  winiso / lib/uup.ps1  ——  UUP dump 接口层（列出构建 / 语言 / 版本 / 下载清单）
# ============================================================================

$script:ApiBase  = 'https://api.uupdump.net'
$script:SiteBase = 'https://uupdump.net'

# 家族 -> 搜索关键词
# 注意：直接 search=Windows 11 会返回 1700+ 条、响应 200KB+（易被代理截断），
# 因此按"代次"分开查询，每次只有几十~一百多条，既快又稳。
$script:Families = @(
    @{ Value = 'win11';  Label = 'Windows 11';     Search = @('Windows 11 26H1', 'Windows 11 25H2', 'Windows 11 24H2', 'Windows 11 23H2') },
    @{ Value = 'win10';  Label = 'Windows 10';     Search = @('Windows 10 22H2', 'Windows 10 21H2', 'Windows 10 21H1') },
    @{ Value = 'server'; Label = 'Windows Server'; Search = @('Windows Server 2025', 'Windows Server 2022', 'Windows Server 2019') },
    @{ Value = 'custom'; Label = '手动输入构建 UUID / 链接'; Search = @() }
)

function Get-FamilyLabel([string]$V) {
    foreach ($f in $script:Families) { if ($f.Value -eq $V) { return $f.Label } }
    return $V
}

# 只保留正式版完整构建
function Test-ProductionTitle([string]$Title) {
    if (-not $Title) { return $false }
    if (-not ($Title -match '^(Windows 1[01]|Windows Server)')) { return $false }
    if ($Title -match 'Insider|Preview|prerelease|Skip Ahead|Canary|Dev Channel|Beta|flighting') { return $false }
    if ($Title -match 'Update|KB\d|Framework|Service Stack|Hotfix|\.NET') { return $false }
    return $true
}

function ConvertTo-BuildNumber([string]$Build) {
    # "28000.2113" -> 28000.2113
    $b = 0.0
    $null = [double]::TryParse($Build, [ref]$b)
    return $b
}

# 列出某个家族 + 架构的构建（正式版，去重后按版本降序）
function Get-UupBuilds {
    param([string]$Family, [string]$Arch)
    $fam = $null
    foreach ($f in $script:Families) { if ($f.Value -eq $Family) { $fam = $f } }
    if (-not $fam) { throw "未知家族: $Family" }

    $terms = @($fam.Search)
    if ($terms.Count -eq 0) { throw "该家族需要手动输入 UUID" }

    $rows = @()
    $failTerms = @()
    foreach ($term in $terms) {
        $url = "$script:ApiBase/listid.php?search=" + [Uri]::EscapeDataString($term)
        try {
            $json = Get-JsonFromUrl -Url $url
        } catch {
            $failTerms += $term
            continue
        }
        $builds = $json.response.builds
        if (-not $builds) { continue }
        foreach ($p in $builds.PSObject.Properties) {
            $b = $p.Value
            if ($Arch -and $b.arch -ne $Arch) { continue }
            if (-not (Test-ProductionTitle $b.title)) { continue }
            $rows += [pscustomobject]@{
                Title   = $b.title
                Build   = $b.build
                Arch    = $b.arch
                Uuid    = $b.uuid
                Created = $b.created
                Num     = (ConvertTo-BuildNumber $b.build)
            }
        }
    }
    if ($rows.Count -eq 0) {
        $msg = "$($fam.Label) 的 $Arch 架构没有找到正式版构建"
        if ($failTerms.Count -gt 0) { $msg += "（查询失败的代次: " + ($failTerms -join ', ') + "）" }
        throw $msg
    }

    # 同一标题+架构只留最新的一个
    $seen = @{}
    $out = @()
    foreach ($r in ($rows | Sort-Object -Property Num -Descending)) {
        $key = $r.Title + '|' + $r.Arch
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = 1
        $out += $r
    }
    return $out
}

# 从摘要链接/UUID 里提取 UUID
function Resolve-UuidFromInput([string]$Text) {
    $m = [regex]::Match([string]$Text, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($m.Success) { return $m.Groups[1].Value.ToLower() }
    return $null
}

# 用 get.php 拉构建详情（标题/架构/版本）
function Get-UupBuildInfo([string]$Uuid) {
    $json = Get-JsonFromUrl -Url "$script:ApiBase/get.php?id=$Uuid"
    $resp = $json.response
    $info = [pscustomobject]@{
        Title = $resp.updateInfo.title
        Arch  = $resp.updateInfo.arch
        Build = $resp.updateInfo.build
        Uuid  = $Uuid
        Ring  = $resp.updateInfo.ring
    }
    return $info
}

function Get-UupLangs([string]$Uuid) {
    $json = Get-JsonFromUrl -Url "$script:ApiBase/listlangs.php?id=$Uuid"
    $list = $json.response.langList
    $names = $json.response.langFancyNames
    $rows = @()
    foreach ($l in $list) {
        $fancy = $l
        if ($names -and $names.$l) { $fancy = $names.$l }
        $rows += [pscustomobject]@{ Code = $l; Name = $fancy }
    }
    return $rows
}

function Get-UupEditions([string]$Uuid, [string]$Lang) {
    $json = Get-JsonFromUrl -Url "$script:ApiBase/listeditions.php?id=$Uuid&lang=$Lang"
    $list = $json.response.editionList
    $names = $json.response.editionFancyNames
    $rows = @()
    foreach ($e in $list) {
        $fancy = $e
        if ($names -and $names.$e) { $fancy = $names.$e }
        $rows += [pscustomobject]@{ Code = $e; Name = $fancy }
    }
    return $rows
}

# aria2 下载清单（纯文本，含 文件URL + out= + checksum=sha-1）
function Get-UupAriaScript([string]$Uuid, [string]$Lang, [string]$Edition) {
    $url = "$script:SiteBase/get.php?id=$Uuid&pack=$Lang&edition=$Edition&aria2=2"
    # 清单会被代理/网络中途截断：URL 数与 out= 数必须一一对应才算完整
    for ($round = 1; $round -le 4; $round++) {
        $txt = $null
        try { $txt = Invoke-CurlText -Url $url -TimeoutSec 120 -Attempts 2 } catch { $txt = $null }
        if ($txt -and ($txt -match 'http')) {
            $nUrl = ([regex]::Matches($txt, '(?m)^http')).Count
            $nOut = ([regex]::Matches($txt, '(?m)^\s*out=')).Count
            if ($nUrl -ge 3 -and $nOut -eq $nUrl) { return $txt }
        }
        Start-Sleep -Seconds (3 * $round)
    }
    throw '拿不到完整的 UUP 下载清单（多因网络中途断开或该组合已下架）——可重跑，或用 winiso diag 诊断'
}

function ConvertFrom-AriaScript([string]$Text) {
    $items = @()
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -match '^http' -or $line -match '^\(http') {
            $url = $line.Trim()
            if ($url.StartsWith('(')) { $url = $url.TrimStart('(') }   # aria2 清单里偶尔有 ( 包住的长 URL
            $out = ''; $sha1 = ''
            for ($j = $i + 1; $j -lt [math]::Min($i + 6, $lines.Count); $j++) {
                $l2 = $lines[$j].Trim()
                if ($l2 -match '^out=') { $out = ($l2 -replace '^out=', '').Trim() }
                elseif ($l2 -match '^checksum=sha-1=') { $sha1 = ($l2 -replace '^checksum=sha-1=', '').Trim() }
                elseif ($l2 -match '^http') { break }
            }
            if (-not $out) { $out = [System.IO.Path]::GetFileName(($url -split '\?')[0]) }
            $items += [pscustomobject]@{ Url = $url; Out = $out; Sha1 = $sha1 }
        }
    }
    return $items
}

# 下载官方脚本包（ZIP：uup_download_windows.cmd + converter 配置）
# 关键：edition 必须是真实版本键（PROFESSIONAL/CORE/...），写 0 会报
#       "The language and edition combination is not correct."
function Save-UupPackage {
    param([string]$Uuid, [string]$Lang, [string]$Edition, [string]$OutFile)
    $url = "$script:SiteBase/get.php?id=$Uuid&pack=$Lang&edition=$Edition"
    $referer = "$script:SiteBase/download.php?id=$Uuid&pack=$Lang"

    # 依次尝试：POST 两次（站点偶发返回提示页）+ GET 兜底
    $plans = @(
        @{ Method = 'POST'; Body = 'autodl=2&updates=1' },
        @{ Method = 'POST'; Body = 'autodl=2&updates=1' },
        @{ Method = 'GET';  Body = $null }
    )
    $lastErr = '未知错误'
    foreach ($plan in $plans) {
        if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
        try {
            Save-UrlToFile -Url $url -Path $OutFile -Method $plan.Method -Body $plan.Body -Referer $referer
        } catch {
            $lastErr = $_.Exception.Message
            Start-Sleep -Seconds 2
            continue
        }
        if (-not (Test-Path -LiteralPath $OutFile)) { $lastErr = '没有写出文件'; continue }

        $len = (Get-Item -LiteralPath $OutFile).Length
        $head = New-Object byte[] ([math]::Min(4, $len))
        $fs = [IO.File]::Open($OutFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $null = $fs.Read($head, 0, $head.Length) } finally { $fs.Dispose() }

        if ($len -ge 2000 -and $len -gt 4 -and $head[0] -eq 0x50 -and $head[1] -eq 0x4B) {
            return $OutFile
        }
        # 不是 ZIP：说明拿到的是网页/错误页，把开头文字带进错误里
        $text = ''
        try { $text = ([IO.File]::ReadAllText($OutFile) -replace '\s+', ' ') } catch { }
        if ($text.Length -gt 120) { $text = $text.Substring(0, 120) }
        $lastErr = ('服务器返回的不是 ZIP（' + $len + ' 字节）: ' + $text)
        Start-Sleep -Seconds 2
    }
    throw ('脚本包下载失败 —— ' + $lastErr + '  建议：换一个构建/语言/版本种类，或运行 winiso diag 看网络诊断')
}

# 商店应用下载清单（跳过时可以不下）
function Get-UupAppAriaScript([string]$Uuid) {
    $url = "$script:SiteBase/get.php?id=$Uuid&pack=neutral&edition=app&aria2=2"
    return (Invoke-CurlText -Url $url -TimeoutSec 120)
}

# 列出可用语言（限制为常用集合，避免菜单过长）
function Get-LangChoices([array]$Langs) {
    $preferred = @('zh-cn', 'en-us', 'zh-tw', 'ja-jp', 'ko-kr', 'de-de', 'fr-fr', 'es-es', 'ru-ru')
    $items = @()
    foreach ($p in $preferred) {
        $hit = $Langs | Where-Object { $_.Code -eq $p } | Select-Object -First 1
        if ($hit) { $items += [pscustomobject]@{ Label = ($hit.Name + '  (' + $hit.Code + ')'); Value = $hit.Code } }
    }
    $others = $Langs | Where-Object { $preferred -notcontains $_.Code }
    foreach ($o in $others) {
        $items += [pscustomobject]@{ Label = ($o.Name + '  (' + $o.Code + ')'); Value = $o.Code }
    }
    return $items
}
