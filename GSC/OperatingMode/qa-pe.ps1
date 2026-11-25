[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Executable,[string]$EvidenceFolder=(Join-Path $PSScriptRoot 'qa'))
$ErrorActionPreference='Stop'
$exe=(Get-Item -LiteralPath $Executable).FullName
$folder=[IO.Directory]::CreateDirectory($EvidenceFolder).FullName
if (-not ('GmsPeManifest' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class GmsPeManifest {
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr handle);
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr FindResource(IntPtr h,IntPtr name,IntPtr type);
    [DllImport("kernel32")] static extern IntPtr LoadResource(IntPtr h,IntPtr resource);
    [DllImport("kernel32")] static extern IntPtr LockResource(IntPtr data);
    [DllImport("kernel32")] static extern uint SizeofResource(IntPtr h,IntPtr resource);
    public static string Read(string path) {
        IntPtr h=LoadLibraryEx(path,IntPtr.Zero,2); // LOAD_LIBRARY_AS_DATAFILE; never execute module code
        if(h==IntPtr.Zero) throw new Win32Exception();
        try {
            IntPtr r=FindResource(h,new IntPtr(1),new IntPtr(24));
            if(r==IntPtr.Zero) throw new Win32Exception();
            uint length=SizeofResource(h,r);
            if(length==0||length>1048576) throw new FormatException("Invalid manifest length");
            IntPtr p=LockResource(LoadResource(h,r));
            if(p==IntPtr.Zero) throw new Win32Exception();
            byte[] bytes=new byte[length]; Marshal.Copy(p,bytes,0,(int)length);
            return Encoding.UTF8.GetString(bytes).TrimStart('\ufeff').TrimEnd('\0');
        } finally { FreeLibrary(h); }
    }
}
'@
}
$bytes=[IO.File]::ReadAllBytes($exe)
if ([BitConverter]::ToUInt16($bytes,0) -ne 0x5A4D) { throw 'Invalid DOS header.' }
$pe=[BitConverter]::ToInt32($bytes,0x3C)
if ([BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550) { throw 'Invalid PE header.' }
$machine=[BitConverter]::ToUInt16($bytes,$pe+4)
$optional=$pe+24
$magic=[BitConverter]::ToUInt16($bytes,$optional)
$subsystem=[BitConverter]::ToUInt16($bytes,$optional+68)
$directories=$optional+112
$importRva=[BitConverter]::ToUInt32($bytes,$directories+8)
$clrRva=[BitConverter]::ToUInt32($bytes,$directories+14*8)
$manifestXml=[GmsPeManifest]::Read($exe)
$xml=[xml]$manifestXml
$request=$xml.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
$identity=$xml.SelectSingleNode("/*[local-name()='assembly']/*[local-name()='assemblyIdentity']")
$level=$request.GetAttribute('level')
$arch=$identity.GetAttribute('processorArchitecture')
if ($machine -ne 0x8664 -or $magic -ne 0x20b -or $subsystem -ne 2 -or
    $clrRva -eq 0 -or $level -ne 'asInvoker' -or $arch -ne 'amd64') { throw 'PE/manifest differs from the expected Windows x64 GUI build.' }
# Use the Windows-provided Framework reflection-only loader to get assembly references under both PowerShell editions.
$infoWorker={
    $a=[Reflection.Assembly]::ReflectionOnlyLoadFrom($env:GMS_QA_PE_IMAGE)
    [pscustomobject]@{ frameworkMetadata=$a.ImageRuntimeVersion; references=@($a.GetReferencedAssemblies()|ForEach-Object Name|Sort-Object) } | ConvertTo-Json -Compress
}
$old=$env:GMS_QA_PE_IMAGE
try {
    $env:GMS_QA_PE_IMAGE=$exe
    $legacy=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($infoWorker.ToString()))
    $meta=(& $legacy -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $meta.references) { throw 'Metadata reference inspection failed.' }
} finally { $env:GMS_QA_PE_IMAGE=$old }
$result=[ordered]@{sha256=(Get-FileHash -LiteralPath $exe).Hash; bytes=$bytes.Length; machine='AMD64'; format='PE32+'; subsystem='Windows GUI'; sourceAssemblyVersion=[Reflection.AssemblyName]::GetAssemblyName($exe).Version.ToString(); clrDirectoryPresent=($clrRva -ne 0); staticImportDirectoryPresent=($importRva -ne 0); elevation=$level; manifestArchitecture=$arch; signature=(Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString(); frameworkMetadata=$meta.frameworkMetadata; managedReferences=$meta.references}
$utf8=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $folder 'embedded-manifest.xml'),$manifestXml,$utf8)
$json=$result|ConvertTo-Json -Depth 3
[IO.File]::WriteAllText((Join-Path $folder 'pe-summary.json'),$json,$utf8)
$json
