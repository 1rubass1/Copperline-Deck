$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$ctl=Join-Path $PSScriptRoot '.control'
$managerLog=Join-Path $PSScriptRoot 'logs\console-manager.log'
$script:logStartOffset=[int64]0
$script:sessionStartedUtc=''
New-Item -ItemType Directory -Force $ctl | Out-Null
try {$guard=[IO.File]::Open((Join-Path $ctl 'host.lock'),'OpenOrCreate','ReadWrite','None')} catch {exit 2}
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
public class ManagedMinecraft {
 public Process Process;
 public volatile bool Ready;
 private object gate=new object();
 private string log;
 public ManagedMinecraft(string java,string root) {
  log=Path.Combine(root,"logs","console-manager.log");
  Process=new Process();
  Process.StartInfo=new ProcessStartInfo(java,"-Xms2G -Xmx6G -XX:+UseG1GC -jar fabric-server-launch.jar nogui");
  Process.StartInfo.WorkingDirectory=root;
  Process.StartInfo.UseShellExecute=false;
  Process.StartInfo.CreateNoWindow=true;
  Process.StartInfo.RedirectStandardInput=true;
  Process.StartInfo.RedirectStandardOutput=true;
  Process.StartInfo.RedirectStandardError=true;
  Process.OutputDataReceived+=Output;
  Process.ErrorDataReceived+=Output;
 }
 private void Output(object sender,DataReceivedEventArgs e) {
  if(e.Data==null) return;
  lock(gate) {File.AppendAllText(log,e.Data+Environment.NewLine);}
  if(e.Data.Contains("Done (") && e.Data.Contains("For help")) Ready=true;
 }
 public void Start() { Process.Start(); Process.BeginOutputReadLine(); Process.BeginErrorReadLine(); }
 public void Send(string command) {Process.StandardInput.WriteLine(command); Process.StandardInput.Flush();}
}
'@
function Rotate-ManagerLogIfNeeded {
 if(-not (Test-Path $managerLog)){return}
 try {
  $info=Get-Item -LiteralPath $managerLog
  if($info.Length -lt 8MB){return}
  $archive=Join-Path $PSScriptRoot ('logs\console-manager.'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
  Move-Item -LiteralPath $managerLog -Destination $archive -Force
  Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'logs') -Filter 'console-manager.*.log' -File |
   Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force
 } catch {}
}
function State($status) {
 $data=@{hostPid=$PID;hostStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString();status=$status;javaPid=0;logStartOffset=$script:logStartOffset;sessionStartedUtc=$script:sessionStartedUtc}
 if($script:mc -and -not $script:mc.Process.HasExited){$data.javaPid=$script:mc.Process.Id}
 $tmp=Join-Path $ctl 'state.tmp'
 $data | ConvertTo-Json | Set-Content $tmp -Encoding UTF8
 Move-Item $tmp (Join-Path $ctl 'state.json') -Force
}
function Start-Minecraft {
 if(Get-NetTCPConnection -State Listen -LocalPort 25565 -ErrorAction SilentlyContinue){throw 'Port 25565 is busy'}
 Rotate-ManagerLogIfNeeded
 $script:sessionStartedUtc=[DateTime]::UtcNow.ToString('o')
 [IO.File]::AppendAllText($managerLog,([Environment]::NewLine+'=== COPPERLINE DECK SESSION START '+$script:sessionStartedUtc+' ==='+[Environment]::NewLine))
 $script:logStartOffset=[int64](Get-Item -LiteralPath $managerLog).Length
 $lock=Join-Path $PSScriptRoot 'world\session.lock'
 if(Test-Path $lock){$f=[IO.File]::Open($lock,'Open','ReadWrite','None');$f.Dispose()}
 $java=Join-Path $PSScriptRoot 'runtime\jdk-21.0.12.1+1-jre\bin\java.exe'
 $script:mc=New-Object ManagedMinecraft($java,$PSScriptRoot)
 $script:mc.Start()
 State 'starting'
 $limit=(Get-Date).AddSeconds(180)
 while(-not $script:mc.Ready){
  if($script:mc.Process.HasExited){throw ('Java exited: '+$script:mc.Process.ExitCode)}
  if((Get-Date)-gt $limit){throw 'Startup timed out; Java was NOT killed'}
  Start-Sleep -Milliseconds 250
 }
 State 'running'
}
function Stop-Minecraft {
 State 'stopping'
 $script:mc.Send('stop')
 if(-not $script:mc.Process.WaitForExit(120000)){throw 'Stop timed out; Java was NOT killed'}
 $script:mc.Process.WaitForExit()
 if($script:mc.Process.ExitCode -ne 0){throw ('Java exited abnormally: '+$script:mc.Process.ExitCode)}
 [IO.File]::AppendAllText($managerLog,('=== COPPERLINE DECK SESSION END '+[DateTime]::UtcNow.ToString('o')+' ==='+[Environment]::NewLine))
 $lock=Join-Path $PSScriptRoot 'world\session.lock'
 if(Test-Path $lock){$f=[IO.File]::Open($lock,'Open','ReadWrite','None');$f.Dispose()}
}
try {
 Get-ChildItem $ctl -Filter '*.request' | Remove-Item
 try {Start-Minecraft} catch {State ('error: '+$_.Exception.Message); if(-not $script:mc -or $script:mc.Process.HasExited){throw}}
 $quit=$false
 while(-not $quit) {
  if($script:mc.Process.HasExited){State 'stopped';break}
  foreach($file in @(Get-ChildItem $ctl -Filter '*.request' | Sort-Object Name)) {
   $reply=Join-Path $ctl ($file.BaseName+'.response')
   $ok=$true;$message='Command delivered'
   try {
    $request=Get-Content $file.FullName -Raw | ConvertFrom-Json
    Remove-Item $file.FullName
    $command=[string]$request.command
    if($command -match '[\r\n]' -or [string]::IsNullOrWhiteSpace($command)){throw 'Invalid command'}
    if($command -eq 'stop'){Stop-Minecraft;State 'stopped';$quit=$true;$message='Server stopped; Java exited and world unlocked'}
    elseif($command -eq 'restart'){Stop-Minecraft;Start-Minecraft;$message='Server restarted and ready'}
    else {$script:mc.Send($command)}
   } catch {$ok=$false;$message=$_.Exception.Message;State ('error: '+$message)}
   @{ok=$ok;message=$message} | ConvertTo-Json | Set-Content ($reply+'.tmp') -Encoding UTF8
   Move-Item ($reply+'.tmp') $reply -Force
   if($quit){break}
  }
  Start-Sleep -Milliseconds 100
 }
} catch {
 $_ | Out-String | Add-Content (Join-Path $ctl 'manager-errors.log')
} finally {
 if($script:mc -and -not $script:mc.Process.HasExited){
  try {$script:mc.Send('stop');$script:mc.Process.WaitForExit()} catch {}
 }
 $guard.Dispose()
}
