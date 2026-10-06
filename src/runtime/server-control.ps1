param([string]$Command,[switch]$StartOnly)
$ErrorActionPreference='Stop'
$ctl=Join-Path $PSScriptRoot '.control'
function Get-Manager {
 try {
  $state=Get-Content (Join-Path $ctl 'state.json') -Raw | ConvertFrom-Json
  $p=Get-Process -Id $state.hostPid -ErrorAction Stop
  if($p.StartTime.ToUniversalTime().Ticks.ToString() -ne $state.hostStarted){return $null}
  $f=$null
  try {$f=[IO.File]::Open((Join-Path $ctl 'host.lock'),'Open','ReadWrite','None');return $null}
  catch {return $state}
  finally {if($f){$f.Dispose()}}
 } catch {return $null}
}
function Send-Command([string]$text) {
 if(-not (Get-Manager)){throw 'No managed server is running'}
 $id=[Guid]::NewGuid().ToString('N')
 $request=Join-Path $ctl ($id+'.request')
 @{command=$text} | ConvertTo-Json | Set-Content ($request+'.tmp') -Encoding UTF8
 Move-Item ($request+'.tmp') $request
 $reply=Join-Path $ctl ($id+'.response')
 $limit=(Get-Date).AddSeconds(330)
 while(-not (Test-Path $reply)){
  if((Get-Date)-gt $limit){throw 'Command timed out; server was NOT killed. Check logs and status.'}
  Start-Sleep -Milliseconds 200
 }
 $r=Get-Content $reply -Raw | ConvertFrom-Json
 Remove-Item $reply
 if(-not $r.ok){throw $r.message}
 Write-Host $r.message
}
try {
 if($Command){Send-Command $Command;exit 0}
 $state=Get-Manager
 if(-not $state){
  if(Get-NetTCPConnection -State Listen -LocalPort 25565 -ErrorAction SilentlyContinue){throw 'An unmanaged server owns port 25565. Stop it in its original console first.'}
  $hostScript=Join-Path $PSScriptRoot 'server-manager.ps1'
  $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$psExe
  $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$hostScript+'"'
  $psi.WorkingDirectory=$PSScriptRoot
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $manager=New-Object Diagnostics.Process
  $manager.StartInfo=$psi
  [void]$manager.Start()
  $manager.Dispose()
  $limit=(Get-Date).AddSeconds(190)
  do {
   Start-Sleep -Milliseconds 500
   $state=Get-Manager
   if($state -and $state.status -like 'error:*'){throw $state.status}
   if((Get-Date)-gt $limit){throw 'Startup timed out. See .control\manager-errors.log and logs\console-manager.log'}
  } until($state -and $state.status -eq 'running')
 }
 Write-Host ('Server status: '+$state.status)
 if($StartOnly){exit 0}
 Write-Host 'Commands: stop, restart, logs, status, or any Minecraft console command.'
 Write-Host 'Empty input closes this window and leaves the server running.'
 while($true){
  $text=Read-Host 'server>'
  if([string]::IsNullOrWhiteSpace($text)){break}
  if($text -eq 'logs'){Get-Content (Join-Path $PSScriptRoot 'logs\console-manager.log') -Tail 40;continue}
  if($text -eq 'status'){$st=Get-Manager;if($st){$st | Format-List}else{Write-Host 'Stopped'};continue}
  try {Send-Command $text;if($text -eq 'stop'){break}} catch {Write-Host $_.Exception.Message -ForegroundColor Red}
 }
} catch {Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}
