# 编译 winiso.exe（用系统自带的 .NET Framework 编译器，无需下载任何东西）
param([string]$OutName = 'winiso.exe')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src  = Join-Path $root 'launcher\WinIsoLauncher.cs'
$out  = Join-Path $root $OutName

$csc = $null
foreach ($v in @('v4.0.30319', 'v3.5')) {
    foreach ($arch in @('Framework64', 'Framework')) {
        $p = Join-Path $env:SystemRoot ("Microsoft.NET\" + $arch + "\" + $v + "\csc.exe")
        if (Test-Path -LiteralPath $p) { $csc = $p; break }
    }
    if ($csc) { break }
}
if (-not $csc) { throw '没找到 csc.exe（系统自带 .NET Framework 编译器）' }

Write-Host ("编译器: " + $csc)
& $csc /nologo /target:winexe /optimize ('/out:' + '"' + $out + '"') $src
if ($LASTEXITCODE -ne 0) { throw ("编译失败，退出码 " + $LASTEXITCODE) }
Write-Host ("已生成: " + $out + "  (" + [math]::Round((Get-Item -LiteralPath $out).Length / 1KB, 1) + " KB)")
