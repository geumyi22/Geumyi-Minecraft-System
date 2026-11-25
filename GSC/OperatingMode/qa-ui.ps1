[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [string]$EvidenceFolder = (Join-Path $PSScriptRoot 'qa')
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$exe = (Get-Item -LiteralPath $Executable).FullName
$evidence = [IO.Directory]::CreateDirectory($EvidenceFolder).FullName
$result = [ordered]@{ binarySha256 = (Get-FileHash -LiteralPath $exe).Hash; localTime = [DateTimeOffset]::Now.ToString('o') }
if (-not [Environment]::Is64BitProcess) { throw 'Run this check in 64-bit PowerShell.' }

if (-not ('GmsWindowQa' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class GmsWindowQa
{
    public struct Rect { public int Left, Top, Right, Bottom; }
    delegate bool EnumCallback(IntPtr hwnd, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr root, EnumCallback callback, IntPtr unused);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wParam, StringBuilder lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,uint info,out int elevated,int size,out int bytes);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    static bool IsOwned(IntPtr hwnd, int processId) {
        uint actual;
        return GetWindowThreadProcessId(hwnd,out actual) != 0 && actual == (uint)processId;
    }
    public static IntPtr FindVisible(int processId, string title) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hwnd, IntPtr unused) {
            if (!IsOwned(hwnd,processId) || !IsWindowVisible(hwnd)) return true;
            StringBuilder name = new StringBuilder(256);
            GetWindowText(hwnd,name,name.Capacity);
            if (name.ToString() != title) return true;
            found=hwnd; return false;
        },IntPtr.Zero);
        return found;
    }
    public static bool HasLabel(IntPtr root,int processId,string needle) {
        if (!IsOwned(root,processId)) return false;
        bool found = false;
        EnumChildWindows(root,delegate(IntPtr hwnd,IntPtr unused) {
            if (!IsOwned(hwnd,processId) || !IsWindowVisible(hwnd)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassName(hwnd,cls,cls.Capacity);
            if (cls.ToString().IndexOf("STATIC",StringComparison.OrdinalIgnoreCase) < 0) return true;
            StringBuilder label = new StringBuilder(1024); UIntPtr count;
            SendMessageTimeout(hwnd,13,(UIntPtr)label.Capacity,label,2,250,out count);
            if (label.ToString().IndexOf(needle,StringComparison.Ordinal) < 0) return true;
            found=true; return false;
        },IntPtr.Zero);
        return found;
    }
    public static bool IsElevated(IntPtr handle) {
        IntPtr token;
        if (!OpenProcessToken(handle,8,out token)) throw new Win32Exception();
        try {
            int elevated, count;
            if (!GetTokenInformation(token,20,out elevated,4,out count)) throw new Win32Exception();
            return elevated != 0;
        } finally { CloseHandle(token); }
    }
    public static void CloseTestWindow(IntPtr root,int processId) {
        if (IsOwned(root,processId)) PostMessage(root,16,IntPtr.Zero,IntPtr.Zero);
    }
}
'@
}

function New-QaProcess([string]$arguments = '') {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = $arguments
    $start.UseShellExecute = $false
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($exe)
    return [Diagnostics.Process]::Start($start)
}
function Find-QaWindow([Diagnostics.Process]$process, [string]$requiredLabel = '', [int]$timeoutSec = 90) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        if ($process.HasExited) { throw "Process $($process.Id) exited early ($($process.ExitCode))." }
        $hwnd = [GmsWindowQa]::FindVisible($process.Id,'GMS Operating Mode 3.0.1')
        if ($hwnd -ne [IntPtr]::Zero -and ($requiredLabel -eq '' -or [GmsWindowQa]::HasLabel($hwnd,$process.Id,$requiredLabel))) { return $hwnd }
        Start-Sleep -Milliseconds 200
    } while ($clock.Elapsed.TotalSeconds -lt $timeoutSec)
    throw "Visible window timed out ($requiredLabel)."
}
function Assert-Painted([IntPtr]$hwnd) {
    Add-Type -AssemblyName System.Drawing
    $rect = New-Object GmsWindowQa+Rect
    if (-not [GmsWindowQa]::GetWindowRect($hwnd,[ref]$rect)) { throw 'Could not inspect window.' }
    $w = $rect.Right-$rect.Left; $h = $rect.Bottom-$rect.Top
    if ($w -lt 100 -or $h -lt 100) { throw 'Window too small to display the application.' }
    $bitmap = New-Object Drawing.Bitmap($w,$h)
    try {
        $g = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $dc=$g.GetHdc()
            try { if (-not [GmsWindowQa]::PrintWindow($hwnd,$dc,2)) { throw 'PrintWindow failed.' } }
            finally { $g.ReleaseHdc($dc) }
        } finally { $g.Dispose() }
        $colors=New-Object 'Collections.Generic.HashSet[int]'
        for ($y=15; $y -lt $h-15; $y+=11) {
            for ($x=15; $x -lt $w-15; $x+=11) { [void]$colors.Add($bitmap.GetPixel($x,$y).ToArgb()) }
        }
        if ($colors.Count -lt 5) { throw 'No populated window rendering.' }
        return "$($w)x$($h), $($colors.Count) sampled colors"
    } finally { $bitmap.Dispose() }
}
function Close-QaWindow([Diagnostics.Process]$process,[IntPtr]$hwnd,[int]$expectedExit) {
    [GmsWindowQa]::CloseTestWindow($hwnd,$process.Id)
    if (-not $process.WaitForExit(12000)) { throw 'Window did not close cleanly.' }
    if ($process.ExitCode -ne $expectedExit) { throw "Exit code $($process.ExitCode), expected $expectedExit." }
    return $process.ExitCode
}

$owned = New-Object 'Collections.Generic.List[Diagnostics.Process]'
try {
    $main = New-QaProcess
    $owned.Add($main)
    $w = Find-QaWindow $main
    $result.initialVisible = $true
    $result.elevated = [GmsWindowQa]::IsElevated($main.Handle)
    if ($result.elevated) { throw 'Use a standard non-elevated desktop for this test.' }
    $w = Find-QaWindow $main '검사 완료'
    $result.inventoryCompleted = $true
    $result.windowRender = Assert-Painted $w
    $dupe = New-QaProcess
    $owned.Add($dupe)
    $dw = Find-QaWindow $dupe '이미 실행 중인 운영 모드 관리자 창을 사용해 주세요.'
    $result.duplicateExit = Close-QaWindow $dupe $dw 2
    $result.mainExit = Close-QaWindow $main $w 0
    $bad = New-QaProcess '--qa-invalid-argument'
    $owned.Add($bad)
    $bw = Find-QaWindow $bad '시작 실패'
    $result.visibleStartupError = $true
    $result.errorExit = Close-QaWindow $bad $bw 1
    $logFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GMS Operating Mode/Logs'
    $logs = @(Get-ChildItem -LiteralPath $logFolder -Filter '*.log' | Where-Object { $_.LastWriteTime -ge $bad.StartTime.AddSeconds(-1) } |
            Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('시작 실패') })
    $result.startupErrorLogged = $logs.Count -gt 0
    if (-not $result.startupErrorLogged) { throw 'No corresponding failure log was created.' }
    $result.passed = $true
} catch {
    $result.passed = $false
    $result.error = $_.Exception.Message
    throw
} finally {
    foreach ($ownedProcess in $owned) {
        if (-not $ownedProcess.HasExited) {
            $ownedHwnd=[GmsWindowQa]::FindVisible($ownedProcess.Id,'GMS Operating Mode 3.0.1')
            [GmsWindowQa]::CloseTestWindow($ownedHwnd,$ownedProcess.Id)
            if (-not $ownedProcess.WaitForExit(4000)) { $ownedProcess.Kill(); $ownedProcess.WaitForExit(5000) | Out-Null }
        }
        $ownedProcess.Dispose()
    }
    $json = $result | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $evidence 'ui-smoke.json'),$json,$utf8)
    $json
}
