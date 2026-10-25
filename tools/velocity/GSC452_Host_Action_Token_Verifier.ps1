#requires -Version 5.1
# This file defines read-only verification functions. It does not invoke them.
# ONLY dot-source from an attended ADMIN script on the GSC Host Windows PC.
Set-StrictMode -Version Latest
function Unseal-GSCLocalMachineToken([string]$protected){
 if([string]::IsNullOrWhiteSpace($protected)){throw 'HOST_TOKEN_EMPTY'}
 if($protected.StartsWith('dpapi-m:')){
  # Windows PowerShell 5.1 may not auto-load the System.Security assembly.
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $raw=$protected.Substring(8)
  $padding=(4-($raw.Length%4))%4
  $cipher=[Convert]::FromBase64String($raw+('='*$padding))
  try{
   $bytes=[Security.Cryptography.ProtectedData]::Unprotect(
    $cipher,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
   try{return [Text.Encoding]::UTF8.GetString($bytes)}
   finally{[Array]::Clear($bytes,0,$bytes.Length)}
  }finally{[Array]::Clear($cipher,0,$cipher.Length)}
 }
 if($protected.StartsWith('dpapi-u:')){throw 'HOST_TOKEN_USER_SCOPE_UNSUPPORTED'}
 if($protected -match '^dpapi-'){throw 'HOST_TOKEN_UNKNOWN_ENCRYPTION'}
 # Go's securestore explicitly supports historical plaintext config values.
 return $protected
}
function Test-GSCConstantTimeTokenMatch([string]$candidate,[string]$expected){
 if($null -eq $candidate -or $null -eq $expected){return $false}
 $a=[Text.Encoding]::UTF8.GetBytes($candidate.Trim())
 $b=[Text.Encoding]::UTF8.GetBytes($expected)
 try{
  if($a.Length -eq 0 -or $a.Length -ne $b.Length){return $false}
  $diff=0
  for($i=0;$i -lt $a.Length;$i++){
   $diff=$diff -bor ([int]$a[$i] -bxor [int]$b[$i])
  }
  return ($diff -eq 0)
 }finally{
  [Array]::Clear($a,0,$a.Length)
  [Array]::Clear($b,0,$b.Length)
 }
}
function Test-GSCActualHostActionToken([string]$operatorToken){
 # Never invoke POST or print secrets. HTTP GET managed/status may allow
 # loopback WITHOUT valid X-GSC-Token, so GET success is NOT proof.
 $service=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -eq $service -or $service.State -cne 'Running' -or
    $service.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM') -or
    [int]$service.ProcessId -le 4){return $false}
 $m=[regex]::Match([string]$service.PathName,
   '(?i)^\s*"([^"]+\\GeumyiServerHost-v4\.5\.2-Velocity-CANARY\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$')
 if(-not $m.Success){return $false}
 $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$service.ProcessId) -ErrorAction Stop
 if($null -eq $proc -or [string]::IsNullOrWhiteSpace([string]$proc.ExecutablePath) -or
    [IO.Path]::GetFullPath([string]$proc.ExecutablePath) -ine
    [IO.Path]::GetFullPath($m.Groups[1].Value)){return $false}
 $configFile=$m.Groups[2].Value
 $file=Get-Item -LiteralPath $configFile -Force -ErrorAction Stop
 if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  return $false
 }
 $config=Get-Content -LiteralPath $configFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 $secret=$null
 try{
  $secret=Unseal-GSCLocalMachineToken ([string]$config.api_token)
  return (Test-GSCConstantTimeTokenMatch $operatorToken $secret)
 }finally{$secret=$null}
}
