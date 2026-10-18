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
 $server.WriteByte(0x41)
 $server.Flush()
 $received=$server.ReadByte()
 if($received -ne 0x42){throw 'NO-GO: Java native pipe response byte did not match'}
 if(-not $child.WaitForExit(10000)){
  throw 'NO-GO: disposable Java client did not exit after pipe handshake'
 }
 if($child.ExitCode -ne 0){throw 'NO-GO: disposable Java client exited unsuccessfully'}
 $result=(Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
 if($result -notmatch 'GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS'){
  throw 'NO-GO: Java native pipe client lacked success marker'
 }
 Write-Host 'CI PASS: Java 25 native Windows named pipe, same-account DACL, two-way byte exchange'
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
