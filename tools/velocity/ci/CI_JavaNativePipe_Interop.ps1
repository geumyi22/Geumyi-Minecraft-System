#requires -Version 5.1
[CmdletBinding()]
param()
# GitHub Windows runner ONLY. No GSC/Velocity/TaskScheduler integration.
# One temporary pipe, exact runner user SID DACL, and one test-owned JVM.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$javaSource=Join-Path $PSScriptRoot 'JavaNativePipeProbe.java'
if(-not (Test-Path -LiteralPath $javaSource -PathType Leaf)){throw 'CI Java source missing'}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('GSC452-JavaPipe-CI-'+[Guid]::NewGuid().ToString('N'))
$pipeName='GSC452-CI-PIPE-'+[Guid]::NewGuid().ToString('N').Substring(0,24)
$server=$null
$child=$null
try {
 [void](New-Item -ItemType Directory -Path $temporary -Force)
 & javac -d $temporary $javaSource
 if($LASTEXITCODE -ne 0){throw 'Java 25 CI-only client compile failed'}

 # Explicitly protected DACL. No Everyone, Authenticated Users, Users or
 # administrative-group ACE. This allocates an ephemeral DACL in the runner.
 $user=[System.Security.Principal.WindowsIdentity]::GetCurrent().User
 if($null -eq $user){throw 'CI runner user SID unavailable'}
 $acl=[IO.Pipes.PipeSecurity]::new()
 $acl.SetAccessRuleProtection($true,$false)
 $rule=[IO.Pipes.PipeAccessRule]::new(
  $user,[IO.Pipes.PipeAccessRights]::FullControl,
  [Security.AccessControl.AccessControlType]::Allow)
 $acl.AddAccessRule($rule)
 $server=[IO.Pipes.NamedPipeServerStream]::new(
  $pipeName,[IO.Pipes.PipeDirection]::InOut,1,
  [IO.Pipes.PipeTransmissionMode]::Byte,
  [IO.Pipes.PipeOptions]::Asynchronous,4096,4096,$acl)

 $connected=$server.BeginWaitForConnection($null,$null)
 $stdout=Join-Path $temporary 'java.stdout.txt'
 $stderr=Join-Path $temporary 'java.stderr.txt'
 $child=Start-Process -FilePath 'java.exe' -ArgumentList @(
  '-cp', ('"'+$temporary+'"'), 'JavaNativePipeProbe',$pipeName
 ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

 if(-not $connected.AsyncWaitHandle.WaitOne(15000)){
  throw 'NO-GO: Java 25 native RandomAccessFile did not connect to Windows pipe'
 }
 $server.EndWaitForConnection($connected)
 # Real JDK RandomAccessFile readInt()/writeInt() interoperability.
 # This fixture proves the 4-byte big-endian frame shape, but deliberately
 # sends no JSON commands, credentials, player data or server controls.
 $request=[Text.Encoding]::ASCII.GetBytes('GSC452-CI-BOUND-FRAME-V1')
 $size=[BitConverter]::GetBytes([int]$request.Length)
 if([BitConverter]::IsLittleEndian){[Array]::Reverse($size)}
 $server.Write($size,0,$size.Length)
 $server.Write($request,0,$request.Length)
 $server.Flush()
 function Read-Exactly([IO.Stream]$inputStream,[int]$count){
  if($count -le 0 -or $count -gt 2048){throw 'CI frame size out of range'}
  $data=New-Object byte[] $count
  $off=0
  while($off -lt $count){
   $n=$inputStream.Read($data,$off,$count-$off)
   if($n -le 0){throw 'CI frame truncated or disconnected'}
   $off+=$n
  }
  return ,$data
 }
 $header=Read-Exactly $server 4
 if([BitConverter]::IsLittleEndian){[Array]::Reverse($header)}
 $responseSize=[BitConverter]::ToInt32($header,0)
 if($responseSize -le 0 -or $responseSize -gt 2048){
  throw 'NO-GO: Java native pipe response frame length rejected'
 }
 $response=Read-Exactly $server $responseSize
 $actual=[Text.Encoding]::ASCII.GetString($response)
 if($actual -cne 'GSC452-CI-JAVA-FRAME-PASS'){
  throw 'NO-GO: Java native pipe bounded response frame mismatch'
 }
 if(-not $child.WaitForExit(10000)){
  throw 'NO-GO: disposable Java client did not exit after pipe handshake'
 }
 $observedStdout=[string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
 $observedStderr=[string](Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
 Write-Host ('CI child exit code: '+[string]$child.ExitCode)
 Write-Host ('CI Java success marker present: '+[string]($observedStdout -match 'GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS'))
 Write-Host ('CI Java stderr present: '+[string](-not [string]::IsNullOrWhiteSpace($observedStderr)))
 # GitHub Windows PowerShell 5.1 Start-Process may expose an empty
 # ExitCode even after WaitForExit succeeded. Null is not numeric failure.
 # Require the real Java success marker and absence of JVM stderr below;
 # an actual nonzero numeric exit code still fails closed.
 if($null -ne $child.ExitCode -and $child.ExitCode -ne 0){
  $safeFailure=@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue |
    Select-Object -First 6)
  foreach($line in $safeFailure){
   # CI fixture only; never disclose a literal runner temp path, pipe name,
   # Windows account or accidental stacktrace file location.
   $line=[string]$line -replace [regex]::Escape($temporary),'<CI_TEMP>'
   $line=$line -replace [regex]::Escape($pipeName),'<CI_PIPE>'
   $line=$line -replace '(?i)[A-Z]:\\[^\s:]+','<PATH>'
   Write-Host ('Java CI-only error: '+$line)
  }
  throw 'NO-GO: disposable Java client exited unsuccessfully'
 }
 $result=(Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
 if($result -notmatch 'GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS'){
  throw 'NO-GO: Java native pipe client lacked success marker'
 }
 if(-not [string]::IsNullOrWhiteSpace($observedStderr)){
  throw 'NO-GO: Java 25 native pipe CI client emitted an unexpected stderr diagnostic'
 }
 Write-Host 'CI PASS: Java 25 native Windows named pipe, same-account DACL, bounded big-endian two-way frame exchange'
 Write-Host 'No production plugin, live process, key, Scheduled Task, player, ACL or service touched.'
}finally {
 if($null -ne $server){$server.Dispose()}
 if($null -ne $child){
  try {
   $child.Refresh()
   if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}
  }catch{}
  $child.Dispose()
 }
 Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
