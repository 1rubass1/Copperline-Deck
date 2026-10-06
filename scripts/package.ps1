$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'build.ps1')

$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$artifacts = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Force $artifacts | Out-Null

$zip = Join-Path $artifacts ("CopperlineDeck-$version-win-x64.zip")
if (Test-Path $zip) { Remove-Item $zip -Force }

Compress-Archive -Path (Join-Path $root 'dist\*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Package created: $zip"
