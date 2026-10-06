param([switch]$SkipBootstrap)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$deps = Join-Path $root '.deps'

if (-not $SkipBootstrap) {
    & (Join-Path $PSScriptRoot 'bootstrap.ps1')
}

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $dist | Out-Null

Copy-Item (Join-Path $src 'runtime\*') $dist -Recurse -Force

New-Item -ItemType Directory -Force (Join-Path $dist 'webview2') | Out-Null
Copy-Item (Join-Path $deps 'webview2\Microsoft.Web.WebView2.Core.dll') (Join-Path $dist 'webview2') -Force
Copy-Item (Join-Path $deps 'webview2\Microsoft.Web.WebView2.WinForms.dll') (Join-Path $dist 'webview2') -Force
Copy-Item (Join-Path $deps 'webview2\WebView2Loader.dll') (Join-Path $dist 'webview2') -Force
Copy-Item (Join-Path $deps 'pixi\pixi.min.js') (Join-Path $dist 'webui\pixi.min.js') -Force

$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw 'Could not locate .NET Framework csc.exe.' }

$launcher = Join-Path $src 'launcher\CopperlineDeckLauncher.cs'
$outExe = Join-Path $dist 'CopperlineDeck.exe'

& $csc /nologo /target:winexe /reference:System.Windows.Forms.dll /out:$outExe $launcher
if ($LASTEXITCODE -ne 0) { throw "Launcher compilation failed with exit code $LASTEXITCODE." }

Copy-Item (Join-Path $root 'config\copperline.example.psd1') (Join-Path $dist 'copperline.example.psd1') -Force
Copy-Item (Join-Path $root 'VERSION') (Join-Path $dist 'VERSION') -Force

Write-Host "Build complete: $dist"
