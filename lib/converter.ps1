# ============================================================================
#  winiso / lib/converter.ps1  ——  官方转换器（uup-converter-wimlib）编排
#  转换器自带 wimlib + oscdimg + 引导文件，因此无需安装 ADK，也无需模板 ISO
# ============================================================================

$script:SevenZrUrl  = 'https://uupdump.net/misc/7zr.exe'
$script:Converter7z = 'https://uupdump.net/misc/uup-converter-wimlib-v128m.7z'

# 从下载包里的 files\converter_windows 解析转换器地址（未来版本变了也能跟上）
function Get-ConverterIndex {
    param([string]$WorkDir)
    $idx = Join-Path $WorkDir 'files\converter_windows'
    $url = $script:Converter7z
    if (Test-Path $idx) {
        foreach ($line in Get-Content $idx) {
            $t = $line.Trim()
            if ($t -match '^https?://.*uup-converter') { $url = $t; break }
        }
    }
    return $url
}

function Initialize-Converter {
    param([string]$WorkDir)

    $filesDir = Join-Path $WorkDir 'files'
    if (-not (Test-Path $filesDir)) { New-Item -ItemType Directory -Path $filesDir -Force | Out-Null }

    $sevenZr = Join-Path $filesDir '7zr.exe'
    if (-not (Test-Path $sevenZr)) {
        Write-Info '下载 7zr.exe ...'
        Save-UrlToFile -Url $script:SevenZrUrl -Path $sevenZr
    }

    $conv7z = Join-Path $filesDir 'uup-converter-wimlib.7z'
    # 包体约 1.6 MB：小于 1.5 MB 说明是半截文件（网络中断会把 7z 写坏，
    # 7zr 解压时报"无法打开压缩包"，用户看到的就是莫名其妙的失败）
    $needConv = $true
    if (Test-Path -LiteralPath $conv7z) {
        if ((Get-Item -LiteralPath $conv7z).Length -ge 1500000) { $needConv = $false }
    }
    if ($needConv) {
        $url = Get-ConverterIndex -WorkDir $WorkDir
        Write-Info ('下载官方转换器 ... ' + $url)
        for ($try = 1; $try -le 4; $try++) {
            if (Test-Path -LiteralPath $conv7z) { Remove-Item -LiteralPath $conv7z -Force -ErrorAction SilentlyContinue }
            try { Save-UrlToFile -Url $url -Path $conv7z } catch { Write-Warn2 ('转换器下载出错: ' + $_.Exception.Message) }
            if ((Test-Path -LiteralPath $conv7z) -and ((Get-Item -LiteralPath $conv7z).Length -ge 1500000)) { break }
            Write-Warn2 ('转换器不完整（第 ' + $try + ' 次），重试 ...')
            Start-Sleep -Seconds (2 * $try)
        }
        if (-not (Test-Path -LiteralPath $conv7z)) { throw '官方转换器下载失败（网络问题），可重跑或换时段' }
    }

    # 解出 convert-UUP.cmd / bin\cdimage.exe / bin\wimlib-imagex.exe 等
    $marker = Join-Path $WorkDir 'convert-UUP.cmd'
    if (-not (Test-Path $marker)) {
        Write-Info '解压转换器 ...'
        for ($try = 1; $try -le 3; $try++) {
            & $sevenZr x $conv7z ('-o' + $WorkDir) '-y' '-x!ConvertConfig.ini' '-x!CustomAppsList.txt' | Out-Null
            if (Test-Path $marker) { break }
            Write-Warn2 ('解压转换器失败（第 ' + $try + ' 次），重试 ...')
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path $marker)) { throw '转换器解压失败：找不到 convert-UUP.cmd（7z 包可能不完整，删掉 pkg\files\uup-converter-wimlib.7z 后重跑）' }
    }
    # 官方转换器自带的是 cdimage.exe（微软光盘打包工具，语法与 oscdimg 一致），
    # 也有部分版本带 oscdimg.exe，两者都要认；引导文件来自介质本身（boot\etfsboot.com / efi\...\efisys.bin）
    $imgTool = $null
    foreach ($n in @('oscdimg.exe', 'cdimage.exe')) {
        $p = Join-Path $WorkDir ('bin\' + $n)
        if (Test-Path -LiteralPath $p) { $imgTool = $p; break }
    }
    if ($imgTool) {
        Write-Ok ('转换器就绪（' + (Split-Path $imgTool -Leaf) + ' + wimlib，无需 ADK）')
    } else {
        Write-Warn2 '转换器里没找到 oscdimg/cdimage，将回退到系统 ADK'
    }
    return [pscustomobject]@{
        WorkDir   = $WorkDir
        Converter = $marker
        BinDir    = (Join-Path $WorkDir 'bin')
        Oscdimg   = $imgTool
        Wimlib    = (Join-Path $WorkDir 'bin\wimlib-imagex.exe')
    }
}

# 生成 ConvertConfig.ini（转换器行为开关）
function New-ConvertConfig {
    param(
        [string]$WorkDir,
        [hashtable]$Opt
    )
    $lines = @(
        '[convert-UUP]',
        'AutoStart    =1',
        ('AddUpdates   =' + $(if ($Opt.AddUpdates) { 1 } else { 0 })),
        ('Cleanup      =' + $(if ($Opt.Cleanup) { 1 } else { 0 })),
        ('ResetBase    =' + $(if ($Opt.ResetBase) { 1 } else { 0 })),
        ('NetFx3       =' + $(if ($Opt.NetFx3) { 1 } else { 0 })),
        'StartVirtual =0',
        'wim2esd      =0',
        'wim2swm      =0',
        'SkipISO      =0',
        ('SkipWinRE    =' + $(if ($Opt.SkipWinRE) { 1 } else { 0 })),
        'LCUwinre     =0',
        'LCUmsuExpand =0',
        'UpdtBootFiles=0',
        'ForceDism    =0',
        'RefESD       =0',
        'SkipLCUmsu   =0',
        # SkipEdge 是个"档位"而不是布尔：0/1/2（2=真正移除 Edge），所以原样写出去
        ('SkipEdge     =' + $(if ($Opt.SkipEdge) { [int]$Opt.SkipEdge } else { 0 })),
        'AutoExit     =1',
        'DisableUpdatingUpgrade=0',
        'AddDrivers   =0',
        'Drv_Source   =\Drivers',
        '',
        '[Store_Apps]',
        ('SkipApps     =' + $(if ($Opt.SkipApps) { 1 } else { 0 })),
        'AppsLevel    =0',
        'StubAppsFull =1',
        'CustomList   =0',
        '',
        '[create_virtual_editions]',
        'vUseDism     =1',
        'vAutoStart   =0',
        'vDeleteSource=0',
        'vPreserve    =0',
        'vwim2esd     =0',
        'vwim2swm     =0',
        'vSkipISO     =0',
        'vAutoEditions=',
        'vSortEditions=',
        ''
    )
    $path = Join-Path $WorkDir 'ConvertConfig.ini'
    Set-Content -Path $path -Value ($lines -join "`r`n") -Encoding ASCII
    return $path
}

# 运行 convert-UUP.cmd（它会下载 UUP 集并转成 ISO）
function Invoke-Convert {
    param([string]$WorkDir)

    $cmd = Join-Path $WorkDir 'convert-UUP.cmd'
    if (-not (Test-Path $cmd)) { throw '转换器脚本不存在: ' + $cmd }

    Write-Info '开始转换（下载 UUP 集 → 合成映像 → 打包 ISO），耗时约 20-60 分钟 ...'
    $t0 = Get-Date
    Push-Location $WorkDir
    try {
        # "< nul"：转换器出错时会 pause 等回车，非交互运行时没有输入会永久卡住
        & cmd.exe /c 'convert-UUP.cmd < nul'
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # 只认本次运行之后写出的 ISO，避免把上一轮遗留的旧 ISO 当成本轮产物
    $iso = Get-ChildItem -Path $WorkDir -Filter *.iso -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.LastWriteTime -ge $t0 } |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $iso) {
        # 再宽松找一次（极端情况：文件时间戳被继承），但会给出警告
        $iso = Get-ChildItem -Path $WorkDir -Filter *.iso -Recurse -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($iso) { Write-Warn2 ('没找到本轮新生成的 ISO，退而使用最新的旧 ISO: ' + $iso.Name) }
    }
    if (-not $iso) {
        throw ("转换没有产出 ISO（退出码 $code）。日志见: " + (Join-Path $WorkDir 'convert.log'))
    }
    if ($code -ne 0) {
        Write-Warn2 ("转换脚本退出码 $code，但已找到 ISO：" + $iso.Name)
    }
    Write-Ok ('ISO 已生成: ' + $iso.FullName + '  (' + (Format-Size $iso.Length) + ')')
    return $iso.FullName
}

# 找光盘打包工具：优先转换器自带（cdimage.exe / oscdimg.exe）-> ADK -> 全盘搜索
function Resolve-Oscdimg {
    param([string]$Preferred)
    $names = @('oscdimg.exe', 'cdimage.exe')
    $cands = @()
    if ($Preferred) { $cands += $Preferred }
    $workDirs = @(
        (Join-Path $PSScriptRoot '..\stage\bin'),
        (Join-Path $PSScriptRoot '..\work\conv\bin'),
        (Join-Path $PSScriptRoot '..\work\bin')
    )
    foreach ($d in $workDirs) {
        foreach ($n in $names) { $cands += (Join-Path $d $n) }
    }
    $kits = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools'
    foreach ($a in @('amd64', 'arm64', 'x86')) { $cands += (Join-Path $kits ($a + '\Oscdimg\oscdimg.exe')) }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    # 兜底：搜索 Windows Kits 目录
    if (Test-Path 'C:\Program Files (x86)\Windows Kits') {
        $hit = Get-ChildItem 'C:\Program Files (x86)\Windows Kits' -Recurse -Filter 'oscdimg.exe' -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
