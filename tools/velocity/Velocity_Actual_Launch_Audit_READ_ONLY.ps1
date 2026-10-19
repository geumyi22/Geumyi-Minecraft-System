#requires -Version 5.1
[CmdletBinding()]
param(
  [ValidateSet('wild','playground','other','all')]
  [string]$Target='all'
)
# READ ONLY. NEVER emit raw Task XML, executable commands, login names,
# user paths, private arguments, keys or hashes. No process/task mutation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$names=@{
 wild='Geumyi Day10 Velocity wild'
 playground='Geumyi Day10 Velocity playground'
 other='Geumyi Day10 Velocity other'
}
$ciHash='35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8'
$targets=@('wild','playground','other')
if($Target -ne 'all'){$targets=@($Target)}
function Inspect([string]$id){
 $out=[ordered]@{
  target=$id
  read_only=$true
  task_state='UNKNOWN'
  action_class='UNKNOWN'
  launch_workdir_class='UNKNOWN'
  working_directory_exists=$false
  java_executable_exists=$false
  jar_file_found=$false
  jar_sha256_class='NOT_CHECKED'
  matches_old_fixed_programdata_layout=$false
  task_policy_999=$false
  console_stdin_reachability='NOT_PROVEN'
  lifecycle_migration_authorized=$false
  status='READ_ONLY_LAUNCH_PROFILE_UNVERIFIED'
 }
 try{
  $task=Get-ScheduledTask -TaskName $names[$id] -TaskPath '\' -ErrorAction Stop
  if($null -eq $task){return [pscustomobject]$out}
  $out.task_state=[string]$task.State
  $xml=[xml](Export-ScheduledTask -TaskName $names[$id] -TaskPath '\' -ErrorAction Stop)
  $exec=@($xml.SelectNodes("//*[local-name()='Actions']/*"))
  if($exec.Count -ne 1 -or $exec[0].LocalName -ne 'Exec'){
    $out.action_class='MULTIPLE_OR_NON_EXEC_ACTIONS'
    return [pscustomobject]$out
  }
  $node=$exec[0]
  $cmdNode=$node.SelectSingleNode("*[local-name()='Command']")
  $argsNode=$node.SelectSingleNode("*[local-name()='Arguments']")
  $dirNode=$node.SelectSingleNode("*[local-name()='WorkingDirectory']")
  if($null -eq $cmdNode){return [pscustomobject]$out}
  $cmd=[string]$cmdNode.InnerText
  $line=if($null -ne $argsNode){[string]$argsNode.InnerText}else{''}
  $dir=if($null -ne $dirNode){[string]$dirNode.InnerText}else{''}
  $out.action_class=if($cmd -match '(?i)(^|[\\/])javaw?\.exe$'){'DIRECT_JAVA'}else{'WRAPPER_OR_OTHER'}
  if($out.action_class -eq 'DIRECT_JAVA'){
    $out.java_executable_exists=[IO.Path]::IsPathRooted($cmd) -and (Test-Path -LiteralPath $cmd -PathType Leaf)
  }
  $out.working_directory_exists=[IO.Path]::IsPathRooted($dir) -and (Test-Path -LiteralPath $dir -PathType Container)
  if($dir -match '(?i)[\\/]OneDrive[\\/]'){
    $out.launch_workdir_class='ONEDRIVE'
  }elseif($dir -match '(?i)[\\/]ProgramData[\\/]'){
    $out.launch_workdir_class='PROGRAMDATA'
  }elseif($dir -match '^[A-Za-z]:[\\/]'){
    $out.launch_workdir_class='OTHER_LOCAL_DRIVE'
  }elseif($dir -match '^\\\\'){
    $out.launch_workdir_class='NETWORK_SHARE'
  }else{
    $out.launch_workdir_class='NOT_ABSOLUTE'
  }
  $oldBase=Join-Path $env:ProgramData ('GeumyiServerCenter\Network\FourServer\'+$id)
  if([IO.Path]::IsPathRooted($dir)){
    $out.matches_old_fixed_programdata_layout=([IO.Path]::GetFullPath($dir).TrimEnd('\') -ieq ([IO.Path]::GetFullPath($oldBase).TrimEnd('\')))
  }
  $argsValid=$line -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)'
  if($out.working_directory_exists -and $argsValid){
    $jar=Join-Path $dir 'velocity.jar'
    if(Test-Path -LiteralPath $jar -PathType Leaf){
      $out.jar_file_found=$true
      $fi=Get-Item -LiteralPath $jar
      if($fi.Length -lt 10000 -or $fi.Length -gt 200MB){
        $out.jar_sha256_class='BAD_JAR_LENGTH'
      }else{
        $digest=(Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $out.jar_sha256_class=if($digest -ceq $ciHash){'MATCHES_CI_420_TEST_JAR'}else{'DIFFERENT_FROM_CI_420_TEST_JAR'}
      }
    }else{$out.jar_sha256_class='FILE_NOT_FOUND'}
  }else{$out.jar_sha256_class='UNSUPPORTED_LAUNCH_FORMAT_OR_WORKDIR'}
  $c=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']/*[local-name()='Count']")
  $m=$xml.SelectSingleNode("//*[local-name()='MultipleInstancesPolicy']")
  $out.task_policy_999=($null -ne $c -and [string]$c.InnerText -ceq '999' -and $null -ne $m -and [string]$m.InnerText -ceq 'IgnoreNew')
  $out.status='READ_ONLY_LAUNCH_PROFILE_CAPTURED_NO_GO'
 }catch{
  $out.status='READ_ONLY_INSPECTION_FAILED_NO_GO'
 }
 return [pscustomobject]$out
}
$result=@(foreach($id in $targets){Inspect $id})
[pscustomobject]@{schema=1;read_only=$true;actual_host_inspection=$true
  lifecycle_migration_authorized=$false;results=@($result)}|ConvertTo-Json -Depth 5
