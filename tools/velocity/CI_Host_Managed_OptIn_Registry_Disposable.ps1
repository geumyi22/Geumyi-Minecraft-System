#requires -Version 5.1
[CmdletBinding()]
param()
# CI-only, unique HKCU registry KEY. Never query/update a real service.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:CI -cne 'true' -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
 throw 'WINDOWS_GITHUB_HOSTED_CI_ONLY'
}
$path='HKCU:\Software\GSC452_CI_OptIn_'+[Guid]::NewGuid().ToString('N')
$flag='GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN=DIRECT_OWNERSHIP_APPROVED'
try{
 if(Test-Path -LiteralPath $path){throw 'CI key collision'}
 New-Item -Path $path -Force -ErrorAction Stop|Out-Null
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 if(@($key.GetValueNames()) -contains 'Environment'){throw 'Unexpected original Environment'}
 New-ItemProperty -LiteralPath $path -Name Environment -PropertyType MultiString -Value ([string[]]@($flag)) -Force -ErrorAction Stop|Out-Null
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 if($key.GetValueKind('Environment') -ne [Microsoft.Win32.RegistryValueKind]::MultiString){throw 'not REG_MULTI_SZ'}
 $v=@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 if($v.Count -ne 1 -or $v[0] -cne $flag){throw 'CI optin MultiString bytes did not persist'}
 Write-Host 'CI_HOST_SERVICE_SPECIFIC_REG_MULTI_SZ_OPTIN=PASS'
 Remove-ItemProperty -LiteralPath $path -Name Environment -ErrorAction Stop
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 if(@($key.GetValueNames()) -contains 'Environment'){throw 'CI absent Environment was not restored'}
 Write-Host 'CI_HOST_SERVICE_ENV_ABSENCE_RESTORE=PASS'
 $prior=[string[]]@('JAVA_TOOL_OPTIONS=-XX:+UseG1GC','EXISTING_PRIVATE_SETTING=CI_ONLY_NOT_REAL')
 New-ItemProperty -LiteralPath $path -Name Environment -PropertyType MultiString -Value $prior -Force -ErrorAction Stop|Out-Null
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 $before=[string[]]@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 New-ItemProperty -LiteralPath $path -Name Environment -PropertyType MultiString -Value ([string[]]($before+@($flag))) -Force -ErrorAction Stop|Out-Null
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 $during=[string[]]@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 if($during.Count -ne 3 -or $during[0] -cne $prior[0] -or
    $during[1] -cne $prior[1] -or $during[2] -cne $flag){throw 'CI existing env not preserved'}
 New-ItemProperty -LiteralPath $path -Name Environment -PropertyType MultiString -Value $prior -Force -ErrorAction Stop|Out-Null
 $key=Get-Item -LiteralPath $path -ErrorAction Stop
 $after=[string[]]@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 if($after.Count -ne 2 -or $after[0] -cne $prior[0] -or $after[1] -cne $prior[1]){
  throw 'CI existing environment restore drifted'
 }
 Write-Host 'CI_HOST_SERVICE_ENV_EXISTING_VALUES_PRESERVED_AND_RESTORED=PASS'
}finally{
 if(Test-Path -LiteralPath $path){
  # Only the one provably unique CI-owned HKCU key is deleted.
  Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
 }
}
Write-Host 'CI_NO_REAL_WINDOWS_SERVICE_OR_MINECRAFT_OPERATIONS=PASS'
