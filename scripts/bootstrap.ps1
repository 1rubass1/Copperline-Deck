param(
    [string]$WebView2Version = '1.0.4258.31',
    [string]$PixiVersion = '8.22.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$deps = Join-Path $root '.deps'
$webview = Join-Path $deps 'webview2'
$pixi = Join-Path $deps 'pixi'

New-Item -ItemType Directory -Force $webview,$pixi | Out-Null

$pixiOut = Join-Path $pixi 'pixi.min.js'
if (-not (Test-Path $pixiOut)) {
    $url = "https://cdn.jsdelivr.net/npm/pixi.js@$PixiVersion/dist/pixi.min.js"
    Write-Host "Downloading PixiJS $PixiVersion..."
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $pixiOut
}

$coreOut = Join-Path $webview 'Microsoft.Web.WebView2.Core.dll'
$formsOut = Join-Path $webview 'Microsoft.Web.WebView2.WinForms.dll'
$loaderOut = Join-Path $webview 'WebView2Loader.dll'

if (-not ((Test-Path $coreOut) -and (Test-Path $formsOut) -and (Test-Path $loaderOut))) {
    $packageDir = Join-Path $deps "Microsoft.Web.WebView2.$WebView2Version"
    $zip = Join-Path $deps "Microsoft.Web.WebView2.$WebView2Version.zip"
    if (Test-Path $packageDir) { Remove-Item $packageDir -Recurse -Force }

    Write-Host "Downloading Microsoft.Web.WebView2 $WebView2Version..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$WebView2Version" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $packageDir -Force

    Copy-Item (Join-Path $packageDir 'lib\net462\Microsoft.Web.WebView2.Core.dll') $coreOut -Force
    Copy-Item (Join-Path $packageDir 'lib\net462\Microsoft.Web.WebView2.WinForms.dll') $formsOut -Force
    Copy-Item (Join-Path $packageDir 'runtimes\win-x64\native\WebView2Loader.dll') $loaderOut -Force
    Remove-Item $zip -Force
}

Write-Host 'Dependencies are ready.'
