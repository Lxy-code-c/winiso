# ============================================================================
#  winiso / lib/slim.ps1  ——  离线精简 / 定制（DISM 挂载 wim）+ 重建 ISO
# ============================================================================

# 读取精简清单：Appx 预置包前缀 + DISM 功能包
function Get-DebloatData {
    param([string]$Family)
    $dataDir = Join-Path (Join-Path $PSScriptRoot '..') 'data'
    $file = Join-Path $dataDir ("debloat_" + $Family + ".txt")
    if (-not (Test-Path $file)) { $file = Join-Path $dataDir 'debloat_win11.txt' }
    $appx = @(); $pkg = @()
    foreach ($line in Get-Content $file) {
        $line = $line -replace ([char]0xFEFF), ''      # 去掉 UTF-8 BOM 残留在第一行行首的零宽字符
        $t = ($line -split '#')[0].Trim()
        if (-not $t) { continue }
        if ($t -match 'Microsoft-Windows-' -or $t -match '\-Package~') { $pkg += $t }
        else { $appx += $t }
    }
    return [pscustomobject]@{ Appx = $appx; Pkg = $pkg; Source = $file }
}

# 广告域名清单
function Get-AdDomains {
    param([string]$ExtraFile)
    $dataDir = Join-Path (Join-Path $PSScriptRoot '..') 'data'
    $files = @((Join-Path $dataDir 'adblock_hosts.txt'))
    if ($ExtraFile -and (Test-Path $ExtraFile)) { $files += $ExtraFile }
    $doms = @()
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { continue }
        foreach ($line in Get-Content $f) {
            $line = $line -replace ([char]0xFEFF), ''
            $t = ($line -split '#')[0].Trim().ToLower()
            if (-not $t) { continue }
            $t = $t.TrimStart('*', '.')
            if ($t -match '^[a-z0-9.-]+$' -and $t.Contains('.')) { $doms += $t }
        }
    }
    return ($doms | Sort-Object -Unique)
}

function Build-HostsBlock([array]$Domains) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# === winiso adblock (auto generated) ===')
    foreach ($d in $Domains) { [void]$sb.AppendLine("0.0.0.0 $d") }
    return $sb.ToString()
}

# macOS 风格 + 隐私去广告 的注册表项
# Hive: SOFTWARE(机器级) / DEFAULT(新用户默认) / SYSTEM
# Opt(美化细节): Theme(dark|light) SmallIcons Seconds Explorer
function Get-MacTweaks([hashtable]$Opt) {
    $t = @()
    $theme = 'dark'
    if ($Opt -and $Opt.Theme) { $theme = $Opt.Theme }
    $smallIcons = $true; if ($Opt -and $Opt.ContainsKey('SmallIcons')) { $smallIcons = [bool]$Opt.SmallIcons }
    $seconds = $true;    if ($Opt -and $Opt.ContainsKey('Seconds')) { $seconds = [bool]$Opt.Seconds }
    $explorer = $true;   if ($Opt -and $Opt.ContainsKey('Explorer')) { $explorer = [bool]$Opt.Explorer }

    # ---- 隐私 / 广告 / 推荐 ----
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsSpotlightFeatures'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\CloudContent'; Name='DisableSoftLanding'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='OemPreInstalledAppsEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='PreInstalledAppsEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SilentInstalledAppsEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-310093Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338388Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338389Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353694Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353696Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SystemPaneSuggestionsEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name='AllowTelemetry'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\Windows Search'; Name='AllowCortana'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\Windows Search'; Name='DisableSearchBoxSuggestions'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\Windows Search'; Name='AllowCloudSearch'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\OneDrive'; Name='DisableFileSyncNGSC'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\Explorer'; Name='DisableSearchBoxSuggestions'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSyncProviderNotifications'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='SOFTWARE'; Path='Policies\Microsoft\Windows\Explorer'; Name='HideSCAMeetNow'; Type='REG_DWORD'; Value=1 }

    # ---- macOS 风格：任务栏/开始菜单 ----
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAl'; Type='REG_DWORD'; Value=1 }        # 居中
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarGlomLevel'; Type='REG_DWORD'; Value=2 }
    if ($smallIcons) {
        $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarSmallIcons'; Type='REG_DWORD'; Value=1 }
    }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarDa'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarMn'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowTaskViewButton'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowCopilotButton'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_ShowRecommendations'; Type='REG_DWORD'; Value=0 }
    # 机器级：新用户也默认居中（部分版本读 HKLM 项）
    $t += @{ Hive='SOFTWARE'; Path='Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAl'; Type='REG_DWORD'; Value=1 }

    # ---- 主题：深色/浅色 + 透明 + 强调色 ----
    $light = 0
    if ($theme -eq 'light') { $light = 1 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='AppsUseLightTheme'; Type='REG_DWORD'; Value=$light }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='SystemUsesLightTheme'; Type='REG_DWORD'; Value=$light }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='ColorPrevalence'; Type='REG_DWORD'; Value=1 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\DWM'; Name='ColorPrevalence'; Type='REG_DWORD'; Value=1 }
    # 强调色：接近 macOS 蓝，用十六进制避免超过 int32 的十进制
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\DWM'; Name='AccentColor'; Type='REG_DWORD'; Value='0xff0078d4' }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\DWM'; Name='ColorizationColor'; Type='REG_DWORD'; Value='0xc40078d4' }

    # ---- 细节：时钟秒 / 菜单速度 / 字体平滑 ----
    if ($seconds) {
        $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSecondsInSystemClock'; Type='REG_DWORD'; Value=1 }
    }
    $t += @{ Hive='DEFAULT'; Path='Control Panel\Desktop'; Name='MenuShowDelay'; Type='REG_SZ'; Value='150' }
    $t += @{ Hive='DEFAULT'; Path='Control Panel\Desktop'; Name='FontSmoothing'; Type='REG_SZ'; Value='2' }

    # ---- 资源管理器整理：显示扩展名、默认打开"此电脑"、紧凑视图 ----
    if ($explorer) {
        $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='HideFileExt'; Type='REG_DWORD'; Value=0 }
        $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='LaunchTo'; Type='REG_DWORD'; Value=1 }
        $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='UseCompactMode'; Type='REG_DWORD'; Value=1 }
    }

    # 关闭「值得注意/建议」与锁屏花絮
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338387Enabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='RotatingLockScreenOverlayEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SoftLandingEnabled'; Type='REG_DWORD'; Value=0 }
    $t += @{ Hive='DEFAULT'; Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353698Enabled'; Type='REG_DWORD'; Value=0 }

    return $t
}

# 把注册表项写进挂载后的映像
function Apply-OfflineTweaks {
    param([string]$MountDir, [array]$Tweaks)
    $swHive = Join-Path $MountDir 'Windows\System32\config\SOFTWARE'
    $defHive = Join-Path $MountDir 'Users\Default\NTUSER.DAT'
    $loaded = @()
    $applied = 0
    $swKey = 'HKLM\WISO_SW'
    $defKey = 'HKLM\WISO_DEF'

    # 上一次异常退出可能留下同名挂载（reg load 会报"已被加载"），先清掉
    & reg.exe unload $swKey 2>$null | Out-Null
    & reg.exe unload $defKey 2>$null | Out-Null

    try {
        if (Test-Path $swHive) {
            & reg.exe load $swKey $swHive 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $loaded += $swKey }
            else { Write-Warn2 '加载 SOFTWARE 配置单元失败（机器级注册表项跳过）' }
        }
        if (Test-Path $defHive) {
            & reg.exe load $defKey $defHive 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $loaded += $defKey }
            else { Write-Warn2 '加载 DEFAULT 配置单元失败（用户级注册表项跳过）' }
        }
        foreach ($tw in $Tweaks) {
            $root = $null
            if ($tw.Hive -eq 'SOFTWARE') { $root = $swKey }
            elseif ($tw.Hive -eq 'DEFAULT') { $root = $defKey }
            if (-not $root) { continue }
            if (-not ($loaded -contains $root)) { continue }
            $key = $root + '\' + $tw.Path
            $type = $tw.Type
            $val = [string]$tw.Value
            & reg.exe add $key /v $tw.Name /t $type /d $val /f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $applied++ }
        }
    } finally {
        foreach ($h in $loaded) {
            # 卸载偶尔会因句柄未释放失败：重试几次，别把映像锁住
            for ($i = 1; $i -le 5; $i++) {
                & reg.exe unload $h 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { break }
                Start-Sleep -Milliseconds 400
            }
        }
    }
    return $applied
}

# 无人值守应答文件（跳过 TPM/安全启动/联网 OOBE；不自动分区，避免误清盘）
function Build-Autounattend {
    param([string]$Arch, [string]$Lang, [hashtable]$Opt)
    $pa = 'amd64'
    if ($Arch -eq 'arm64') { $pa = 'arm64' }
    $loc = 'zh-CN'
    $inputLocale = '0804:00000804'          # 规范写法是 "LCID:键盘布局"，只写 zh-CN 有被判非法值风险
    if ($Lang -eq 'en-us') { $loc = 'en-US'; $inputLocale = '0409:00000409' }
    $ts = 'China Standard Time'
    $firstLogon = ''
    if ($Opt -and $Opt.RuntimeTweaks) {
        $firstLogon = @"
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add"><Order>1</Order><Description>winiso firstlogon</Description><CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\winiso-firstlogon.ps1</CommandLine><RequiresUserInput>false</RequiresUserInput></SynchronousCommand>
      </FirstLogonCommands>
"@
    }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$loc</UILanguage></SetupUILanguage>
      <InputLocale>$inputLocale</InputLocale><SystemLocale>$loc</SystemLocale><UILanguage>$loc</UILanguage><UserLocale>$loc</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>2</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>3</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>4</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
      </RunSynchronous>
      <UserData><AcceptEula>true</AcceptEula><FullName>winiso</FullName><Organization>winiso</Organization></UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>*</ComputerName><RegisteredOwner>winiso</RegisteredOwner>
      <TimeZone>$ts</TimeZone>
    </component>
    <component name="Microsoft-Windows-International-Core" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$inputLocale</InputLocale><SystemLocale>$loc</SystemLocale><UILanguage>$loc</UILanguage><UserLocale>$loc</UserLocale>
    </component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>2</Order><Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v HideOnlineAccountScreens /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$pa" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE><HideEULAPage>true</HideEULAPage><HideLocalAccountScreen>true</HideLocalAccountScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><ProtectYourPC>3</ProtectYourPC></OOBE>
$firstLogon
    </component>
  </settings>
</unattend>
"@
}

# 首次登录脚本：清理预置应用 + 应用美化注册表 + 自绘壁纸 + Spotlight/程序坞
# Opt: Tweaks(注册表项数组) Wallpaper(bool) Spotlight(bool) Dock(bool) Theme(dark|light)
function Build-FirstLogonScript {
    param([array]$AppxList, [hashtable]$Opt)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('$ErrorActionPreference = "SilentlyContinue"')
    [void]$sb.AppendLine('Start-Sleep -Seconds 5')

    if ($AppxList -and $AppxList.Count -gt 0) {
        [void]$sb.AppendLine('# ---- 移除预置应用 ----')
        [void]$sb.AppendLine('$patterns = @(')
        foreach ($a in $AppxList) { [void]$sb.AppendLine(('    "{0}"' -f $a)) }
        [void]$sb.AppendLine(')')
        [void]$sb.AppendLine('foreach ($p in $patterns) { Get-AppxPackage -AllUsers -Name ($p + "*") | Remove-AppxPackage -AllUsers }')
        [void]$sb.AppendLine('foreach ($p in $patterns) { Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like ($p + "*") } | Remove-AppxProvisionedPackage -Online }')
    }

    [void]$sb.AppendLine('# ---- 关闭遥测服务 ----')
    [void]$sb.AppendLine('Stop-Service DiagTrack -Force; Set-Service DiagTrack -StartupType Disabled')
    [void]$sb.AppendLine('Stop-Service dmwappushservice -Force; Set-Service dmwappushservice -StartupType Disabled')

    # 美化注册表：Hive=DEFAULT -> HKCU；SOFTWARE -> HKLM（离线时已写入，这里是兜底/跨架构路径）
    if ($Opt -and $Opt.Tweaks -and $Opt.Tweaks.Count -gt 0) {
        [void]$sb.AppendLine('# ---- 应用美化注册表 ----')
        foreach ($tw in $Opt.Tweaks) {
            $root = 'HKLM:\SOFTWARE'
            if ($tw.Hive -eq 'DEFAULT') { $root = 'HKCU:' }
            $key = $root + '\' + $tw.Path
            $type = 'DWord'
            if ($tw.Type -eq 'REG_SZ') { $type = 'String' }
            $raw = "$($tw.Value)"
            if ($type -eq 'DWord') {
                $n = 0L
                if ($raw.StartsWith('0x')) { $n = [Convert]::ToUInt32($raw.Substring(2), 16) }
                else { $n = [int64]$raw }
                if ($n -gt 2147483647) { $valExpr = ('[uint32]' + $n) } else { $valExpr = "$n" }
            } else {
                $valExpr = "'" + $raw.Replace("'", "''") + "'"
            }
            $keyQ = $key.Replace("'", "''")
            [void]$sb.AppendLine(('New-ItemProperty -Path ''{0}'' -Name ''{1}'' -Value {2} -PropertyType {3} -Force | Out-Null' -f $keyQ, $tw.Name, $valExpr, $type))
        }
    }

    if ($Opt -and $Opt.Wallpaper) {
        [void]$sb.AppendLine('# ---- macOS 风格壁纸（自己画一张渐变，避免版权问题）----')
        [void]$sb.AppendLine('Add-Type -AssemblyName System.Drawing')
        [void]$sb.AppendLine('$w = 3840; $h = 2160')
        [void]$sb.AppendLine('$bmp = New-Object System.Drawing.Bitmap($w, $h)')
        [void]$sb.AppendLine('$g = [System.Drawing.Graphics]::FromImage($bmp)')
        [void]$sb.AppendLine('$r = New-Object System.Drawing.Rectangle(0, 0, $w, $h)')
        [void]$sb.AppendLine('$c1 = [System.Drawing.Color]::FromArgb(255, 12, 24, 46)')
        [void]$sb.AppendLine('$c2 = [System.Drawing.Color]::FromArgb(255, 32, 82, 140)')
        [void]$sb.AppendLine('$c3 = [System.Drawing.Color]::FromArgb(255, 120, 60, 130)')
        [void]$sb.AppendLine('$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $c1, $c2, 35.0)')
        [void]$sb.AppendLine('$g.FillRectangle($brush, $r)')
        [void]$sb.AppendLine('$brush2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, [System.Drawing.Color]::FromArgb(0, 0, 0, 0), [System.Drawing.Color]::FromArgb(200, 10, 20, 40), 120.0)')
        [void]$sb.AppendLine('$g.FillRectangle($brush2, $r)')
        [void]$sb.AppendLine('$dir = "C:\Windows\Web\Wallpaper\winiso"')
        [void]$sb.AppendLine('New-Item -ItemType Directory -Path $dir -Force | Out-Null')
        [void]$sb.AppendLine('$file = Join-Path $dir "winiso-mac.png"')
        [void]$sb.AppendLine('$bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)')
        [void]$sb.AppendLine('$g.Dispose(); $bmp.Dispose()')
        [void]$sb.AppendLine('New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -Value $file -PropertyType String -Force | Out-Null')
        [void]$sb.AppendLine('New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10" -PropertyType String -Force | Out-Null')
        [void]$sb.AppendLine('New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0" -PropertyType String -Force | Out-Null')
        [void]$sb.AppendLine('rundll32.exe user32.dll,UpdatePerUserSystemParameters')
    }

    if ($Opt -and $Opt.Spotlight) {
        [void]$sb.AppendLine('# ---- Spotlight 式全局搜索（PowerToys Run，Alt+Space ≈ macOS Cmd+Space）----')
        [void]$sb.AppendLine('winget install --id Microsoft.PowerToys -e --accept-package-agreements --accept-source-agreements --silent')
        [void]$sb.AppendLine('$ptCandidates = @("$env:ProgramFiles\PowerToys\PowerToys.exe", "${env:ProgramFiles(x86)}\PowerToys\PowerToys.exe", "$env:LOCALAPPDATA\PowerToys\PowerToys.exe")')
        [void]$sb.AppendLine('$pt = $ptCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1')
        [void]$sb.AppendLine('if ($pt) { Start-Process $pt }')
    }

    if ($Opt -and $Opt.Dock) {
        [void]$sb.AppendLine('# ---- 程序坞 Dock（尽力安装，失败则留提示）----')
        [void]$sb.AppendLine('winget install --id WinstepWerk.Nexus -e --accept-package-agreements --accept-source-agreements --silent')
        [void]$sb.AppendLine('if ($LASTEXITCODE -ne 0) { Write-Host "[winiso] Dock 未自动安装，可在 Store 搜 dock 或 winget 安装" }')
    }

    [void]$sb.AppendLine('taskkill /f /im explorer.exe; Start-Process explorer.exe')
    return $sb.ToString()
}

# 选择要精简的镜像索引（用 Get-WindowsImage，避免 DISM 中文输出解析问题）
function Select-WimIndex {
    param([string]$WimFile)
    if ($script:NonInteractive) {
        # 非交互（GUI / winiso run）没有菜单可问：AutoIndex 只在调用方显式给了才用，
        # 否则默认索引 1。旧代码未定义 AutoIndex 时等于 0，dism /Index:0 必然失败。
        $auto = 0
        if ($script:AutoIndex) { $auto = [int]$script:AutoIndex }
        if ($auto -lt 1) { $auto = 1 }
        return $auto
    }
    $imgs = @()
    try { $imgs = @(Get-WindowsImage -ImagePath $WimFile -ErrorAction Stop) } catch { return 1 }
    if ($imgs.Count -eq 0) { return 1 }
    if ($imgs.Count -eq 1) { return [int]$imgs[0].ImageIndex }
    $items = @()
    foreach ($im in $imgs) {
        $items += [pscustomobject]@{ Label = ('镜像 ' + $im.ImageIndex + '  ' + $im.ImageName); Value = [int]$im.ImageIndex; Hint = $im.ImageDescription }
    }
    return (Read-Choice -Prompt '选择要精简的镜像' -Items $items -Default $items[0].Value)
}

# 主流程：把 ISO 解包 → 改 wim → 重建 ISO
function Invoke-SlimIso {
    param(
        [string]$IsoPath,
        [string]$WorkRoot,
        [hashtable]$Opt,          # Family/Arch/Lang/Appx/Pkg/AdDomains/Tweaks/Autounattend/FirstLogon/KeepWinRE/Offline
        [string]$Oscdimg
    )

    # 防御：调用方可能漏给某个键（或给了 $null），统一成数组，避免后面 .Count 之类的隐式失败
    if (-not $Opt) { $Opt = @{} }
    foreach ($k in @('Appx', 'Pkg', 'AdDomains', 'Tweaks')) {
        if ($null -eq $Opt[$k]) { $Opt[$k] = @() } else { $Opt[$k] = @($Opt[$k] | Where-Object { $_ }) }
    }

    $extract = Join-Path $WorkRoot 'iso'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    # 1) 挂载并复制
    Write-Info ('挂载 ISO: ' + $IsoPath)
    $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    try {
        # 一个 ISO 偶尔会带多个卷（例如额外的 UDF 元数据卷），只取真正有盘符的那个
        $vol = @($disk | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter })
        if ($vol.Count -eq 0) { throw 'ISO 挂载后没有盘符' }
        $letter = [string]$vol[0].DriveLetter
        Write-Info ('复制 ISO 内容到工作目录（约 5 GB，请稍候）...')
        & robocopy.exe ($letter + ':\') $extract /E /NFL /NDL /NJH /NJS /NP /R:2 /W:2 | Out-Null
        if (-not (Test-Path (Join-Path $extract 'sources'))) { throw '复制失败：找不到 sources 目录' }
    } finally {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }

    # 2) 定位 install.wim / esd
    $wimSrc = Get-ChildItem -Path (Join-Path $extract 'sources') -Filter 'install.*' -ErrorAction SilentlyContinue |
              Where-Object { $_.Extension -in @('.wim', '.esd') } |
              Sort-Object @{ Expression = { if ($_.Extension -eq '.wim') { 0 } else { 1 } } } |
              Select-Object -First 1
    if (-not $wimSrc) { throw 'sources 里找不到 install.wim / install.esd' }
    $workWim = Join-Path $WorkRoot 'install.work.wim'

    if ($wimSrc.Extension -eq '.esd') {
        Write-Info '把 ESD 转成 WIM（需要几分钟）...'
        $esdIndex = 1
        # 多索引 ESD 时让用户挑选（Get-WindowsImage 支持 ESD）
        try {
            $esdImgs = @(Get-WindowsImage -ImagePath $wimSrc.FullName -ErrorAction Stop)
            if ($esdImgs.Count -gt 1 -and -not $script:NonInteractive) {
                $it = @()
                foreach ($im in $esdImgs) { $it += [pscustomobject]@{ Label = ('镜像 ' + $im.ImageIndex + '  ' + $im.ImageName); Value = [int]$im.ImageIndex; Hint = '' } }
                $esdIndex = Read-Choice -Prompt '选择要导出的镜像' -Items $it -Default $it[0].Value
            }
        } catch { }
        & dism.exe /Export-Image /SourceImageFile:"$($wimSrc.FullName)" /SourceIndex:$esdIndex /DestinationImageFile:"$workWim" /Compress:max | Out-Null
        # 只判断"文件存在"不够：导出中途失败也会留下半截文件，后面挂载时报的是看不懂的错
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $workWim) -or (Get-Item -LiteralPath $workWim).Length -lt 50MB) {
            if (Test-Path -LiteralPath $workWim) { Remove-Item -LiteralPath $workWim -Force -ErrorAction SilentlyContinue }
            throw ('ESD 转 WIM 失败（dism 退出码 ' + $LASTEXITCODE + '）')
        }
    } else {
        Copy-Item $wimSrc.FullName $workWim -Force
    }

    # 3) 离线精简（仅同架构可挂载）
    if ($Opt.Offline) {
        $index = Select-WimIndex -WimFile $workWim
        if (-not $index) { throw '没有选择镜像索引（已取消）' }
        $mount = Join-Path $WorkRoot 'mount'
        if (Test-Path $mount) {
            & dism.exe /Unmount-Wim /MountDir:$mount /Discard 2>$null | Out-Null
            Remove-Item $mount -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $mount -Force | Out-Null

        Write-Info ('挂载 install.wim（索引 ' + $index + '）...')
        & dism.exe /Mount-Wim /WimFile:$workWim /Index:$index /MountDir:$mount | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '挂载 install.wim 失败（可能被其它进程占用）' }

        $ok = $false
        try {
            # 3.1 删 Appx 预置应用
            if ($Opt.Appx.Count -gt 0) {
                $prov = @(Get-AppxProvisionedPackage -Path $mount -ErrorAction SilentlyContinue)
                $n = 0
                foreach ($p in $prov) {
                    $name = $p.PackageName
                    foreach ($pat in $Opt.Appx) {
                        if ($name -like ($pat + '*')) {
                            try { Remove-AppxProvisionedPackage -Path $mount -PackageName $name -ErrorAction Stop | Out-Null; $n++ } catch { }
                            break
                        }
                    }
                }
                Write-Ok ('移除预置应用 ' + $n + ' 个')
            }

            # 3.2 删功能包
            if ($Opt.Pkg.Count -gt 0) {
                $n = 0
                $pkgs = @(Get-WindowsPackage -Path $mount -ErrorAction SilentlyContinue)
                foreach ($p in $pkgs) {
                    $name = $p.PackageName
                    foreach ($pat in $Opt.Pkg) {
                        if ($name -like ('*' + $pat + '*')) {
                            try { Remove-WindowsPackage -Path $mount -PackageName $name -NoRestart -ErrorAction Stop | Out-Null; $n++ } catch { }
                            break
                        }
                    }
                }
                Write-Ok ('移除功能包 ' + $n + ' 个')
            }

            # 3.3 广告拦截 hosts
            if ($Opt.AdDomains.Count -gt 0) {
                $etcDir = Join-Path $mount 'Windows\System32\drivers\etc'
                # 极少数精简版/Server 核心版里 etc 目录可能不存在，先确保目录在，别让一条 hosts 把整套流程带崩
                if (-not (Test-Path -LiteralPath $etcDir)) { New-Item -ItemType Directory -Path $etcDir -Force | Out-Null }
                $hosts = Join-Path $etcDir 'hosts'
                $block = Build-HostsBlock -Domains $Opt.AdDomains
                Add-Content -Path $hosts -Value $block -Encoding ASCII
                # 去掉重复行
                $uniq = @(Get-Content $hosts | Sort-Object -Unique)
                Set-Content -Path $hosts -Value $uniq -Encoding ASCII
                Write-Ok ('广告拦截：' + $Opt.AdDomains.Count + ' 个域名写入 hosts')
            }

            # 3.4 注册表调优（含 macOS 风格）
            if ($Opt.Tweaks.Count -gt 0) {
                $c = Apply-OfflineTweaks -MountDir $mount -Tweaks $Opt.Tweaks
                Write-Ok ('写入注册表项 ' + $c + ' 条')
            }

            # 3.5 WinRE
            if (-not $Opt.KeepWinRE) {
                $wr = Join-Path $mount 'Windows\System32\Recovery\Winre.wim'
                if (Test-Path $wr) { Remove-Item $wr -Force -ErrorAction SilentlyContinue; Write-Ok '已移除 WinRE（省约 500MB）' }
            }

            # 3.6 首次登录脚本（同架构时也可以做运行期补充）
            if ($Opt.FirstLogon) {
                $scripts = Join-Path $mount 'Windows\Setup\Scripts'
                New-Item -ItemType Directory -Path $scripts -Force | Out-Null
                Set-Content -Path (Join-Path $scripts 'winiso-firstlogon.ps1') -Value $Opt.FirstLogon -Encoding UTF8
            }
            $ok = $true
        } finally {
            if ($ok) {
                Write-Info '提交映像修改 ...'
                & dism.exe /Unmount-Wim /MountDir:$mount /Commit | Out-Null
            } else {
                & dism.exe /Unmount-Wim /MountDir:$mount /Discard 2>$null | Out-Null
            }
        }
        if ($LASTEXITCODE -ne 0) { throw '提交映像失败' }
    }

    # 4) 回写 install.wim + 应答文件 + 运行期脚本
    Write-Info '写回映像文件 ...'
    Copy-Item $workWim (Join-Path $extract 'sources\install.wim') -Force
    $esdPath = Join-Path $extract 'sources\install.esd'
    if (Test-Path $esdPath) { Remove-Item $esdPath -Force }

    if ($Opt.Autounattend) {
        Set-Content -Path (Join-Path $extract 'autounattend.xml') -Value $Opt.Autounattend -Encoding UTF8
        Write-Ok '已加入无人值守应答文件 autounattend.xml'
    }
    if ($Opt.FirstLogon -and -not $Opt.Offline) {
        # 跨架构无法挂载映像：用 $OEM$ 钩子，安装时自动落到 C:\Windows\Setup\Scripts
        $dir = Join-Path $extract 'sources\$OEM$\$\$\Setup\Scripts'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'winiso-firstlogon.ps1') -Value $Opt.FirstLogon -Encoding UTF8
        Write-Ok '首次登录清理脚本已注入 sources\$OEM$'
    }

    # 5) 重建可引导 ISO
    Write-Info '重建 ISO ...'
    $outIso = [System.IO.Path]::ChangeExtension($IsoPath, '.winiso.iso')
    if ($Opt.OutIso) { $outIso = $Opt.OutIso }
    $etfs = Join-Path $extract 'boot\etfsboot.com'
    $efisys = Join-Path $extract 'efi\microsoft\boot\efisys.bin'
    $label = 'WINISO'

    if (-not (Test-Path $Oscdimg)) { throw ('缺少 oscdimg: ' + $Oscdimg) }

    # 注意：bootdata 里必须带引号，而 PowerShell 5.1 调用原生程序时**不会转义参数里的引号**：
    # 参数同时含空格和引号时会被拼成非法命令行（工作目录带空格时必炸）。
    # 所以这里改成 /s /c + 原样命令行交给 cmd，由 cmd 自己解析引号。
    if ((Test-Path -LiteralPath $etfs) -and (Test-Path -LiteralPath $efisys)) {
        $bootData = '-bootdata:2#p0,e,b"' + $etfs + '"#pEF,e,b"' + $efisys + '"'
        $oscArgs = '-m -o -u2 -udfver102 ' + $bootData + ' "-l' + $label + '" "' + $extract + '" "' + $outIso + '"'
    } else {
        Write-Warn2 'ISO 缺少 boot 文件夹的双启动文件，改为纯 UEFI 或不可引导打包'
        $oscArgs = '-m -o -u2 -udfver102 "-l' + $label + '" "' + $extract + '" "' + $outIso + '"'
    }
    $cmdLine = '"' + $Oscdimg + '" ' + $oscArgs
    $psiArgs = '/s /c "' + $cmdLine + '"'
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList $psiArgs -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $outIso)) { throw ('oscdimg 打包失败（退出码 ' + $proc.ExitCode + '）') }

    Write-Ok ('新 ISO: ' + $outIso + '  (' + (Format-Size (Get-Item $outIso).Length) + ')')
    return $outIso
}
