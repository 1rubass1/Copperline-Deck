param([Parameter(Mandatory=$true)][string]$Command)
& (Join-Path $PSScriptRoot 'server-control.ps1') -Command $Command
exit $LASTEXITCODE
