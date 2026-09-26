param(
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:TranscriptStarted = $false

function Step([string]$Text) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "[GSCM] $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkGray
}

function Fail([string]$Text) {
    Write-Host ""
    Write-Host "[GSCM] BUILD FAILED" -ForegroundColor Red
    Write-Host $Text -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $script:LogFile" -ForegroundColor Yellow
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
        $script:TranscriptStarted = $false
    }
    exit 1
}

function Download([string]$Url, [string]$OutFile) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    Write-Host "Download: $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    } catch {
        throw "Download failed: $Url`n$($_.Exception.Message)"
    }
}

function Expand([string]$Zip, [string]$Destination) {
    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $Destination -Force
}

function GetJavaVersionText([string]$JavaExe) {
    if (-not (Test-Path $JavaExe)) { throw "Java executable not found: $JavaExe" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $JavaExe
    $psi.Arguments = '-version'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw 'Could not start Java.' }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "Java failed to start. Exit code: $($proc.ExitCode)" }
    return (($stdout + "`n" + $stderr).Trim())
}

function ShowJavaVersion([string]$JavaExe) {
    $text = GetJavaVersionText $JavaExe
    if ($text) { Write-Host $text }
}

function EnsureJdk([string]$ToolRoot, [string]$CacheRoot) {
    Step 'Preparing dedicated JDK 17'

    # Always use a builder-local JDK 17. Do not inherit a system JDK such as
    # Java 25, because Flutter/Gradle/AGP compatibility can differ by release.
    $jdkHome = Join-Path $ToolRoot 'jdk17'
    $javaExe = Join-Path $jdkHome 'bin\java.exe'

    if (-not (Test-Path $javaExe)) {
        Write-Host 'Dedicated JDK 17 was not found. Installing Temurin JDK 17 locally.'
        $api = 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
        $assets = Invoke-RestMethod -Uri $api
        if (-not $assets -or -not $assets[0].binary.package.link) {
            throw 'Could not resolve the Temurin JDK 17 download URL.'
        }
        $zip = Join-Path $CacheRoot 'jdk17.zip'
        $tmp = Join-Path $CacheRoot 'jdk17-extract'
        Download $assets[0].binary.package.link $zip
        Expand $zip $tmp
        $dir = Get-ChildItem $tmp -Directory | Select-Object -First 1
        if (-not $dir) { throw 'JDK archive layout was not recognized.' }
        if (Test-Path $jdkHome) { Remove-Item $jdkHome -Recurse -Force }
        Move-Item $dir.FullName $jdkHome
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Reusing builder-local JDK: $jdkHome"
    }

    $env:JAVA_HOME = $jdkHome
    # Put the dedicated JDK first, even when a newer system Java is installed.
    $env:PATH = "$jdkHome\bin;$env:PATH"
    ShowJavaVersion $javaExe

    $versionText = GetJavaVersionText $javaExe
    if ($versionText -notmatch 'version "17(?:\.|\")') {
        throw "The builder-local Java is not JDK 17: $versionText"
    }

    return $jdkHome
}

function EnsureFlutter([string]$ToolRoot, [string]$CacheRoot) {
    Step 'Checking Flutter 3.47.5 stable'

    # Keep the mobile release reproducible. Do not inherit a random system
    # Flutter version; use the builder-local SDK that this source was validated
    # against. Existing GSCM toolchains already containing it are reused.
    $flutterRoot = Join-Path $ToolRoot 'flutter'
    $flutter = Join-Path $flutterRoot 'bin\flutter.bat'
    if (-not (Test-Path $flutter)) {
        Write-Host 'Flutter 3.47.5 was not found in the GSCM toolchain. Installing it locally.'
        $url = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.5-stable.zip'
        $zip = Join-Path $CacheRoot 'flutter-3.47.5-stable.zip'
        $tmp = Join-Path $CacheRoot 'flutter-extract'
        Download $url $zip
        Expand $zip $tmp
        $extracted = Join-Path $tmp 'flutter'
        if (-not (Test-Path (Join-Path $extracted 'bin\flutter.bat'))) {
            throw 'Flutter archive layout was not recognized.'
        }
        if (Test-Path $flutterRoot) { Remove-Item $flutterRoot -Recurse -Force }
        Move-Item $extracted $flutterRoot
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Reusing builder-local Flutter: $flutterRoot"
    }

    $env:PATH = "$flutterRoot\bin;$env:PATH"
    & $flutter --version | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Flutter failed to start.' }
    return $flutter
}

function FindSdkManager([string]$SdkRoot) {
    if (-not $SdkRoot -or -not (Test-Path $SdkRoot)) { return $null }

    # Preferred modern Android SDK command-line tools layout.
    $preferred = @(
        (Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'),
        (Join-Path $SdkRoot 'tools\bin\sdkmanager.bat')
    )
    foreach ($candidate in $preferred) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }

    # Also support versioned cmdline-tools folders such as
    # cmdline-tools\12.0\bin\sdkmanager.bat. Prefer the newest-looking folder.
    $cmdlineRoot = Join-Path $SdkRoot 'cmdline-tools'
    if (Test-Path $cmdlineRoot) {
        $versioned = Get-ChildItem -Path $cmdlineRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'latest' } |
            Sort-Object -Property Name -Descending
        foreach ($dir in $versioned) {
            $candidate = Join-Path $dir.FullName 'bin\sdkmanager.bat'
            if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
        }
    }

    return $null
}


function GetFlutterCompileSdk([string]$Flutter) {
    $flutterRoot = Split-Path (Split-Path $Flutter -Parent) -Parent
    $extensionFile = Join-Path $flutterRoot 'packages\flutter_tools\gradle\src\main\kotlin\FlutterExtension.kt'
    if (Test-Path $extensionFile) {
        $text = Get-Content -Raw -Path $extensionFile
        $m = [regex]::Match($text, 'compileSdkVersion\s*:\s*Int\s*=\s*(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    # Flutter 3.47.x default. Used only if the installed SDK layout changes.
    return 36
}

function InvokeSdkManagerWithInput([string]$SdkManager, [string[]]$Arguments, [string]$InputText, [string]$CacheRoot) {
    $inputFile = Join-Path $CacheRoot 'sdkmanager-input.txt'
    $stdoutFile = Join-Path $CacheRoot 'sdkmanager-stdout.txt'
    $stderrFile = Join-Path $CacheRoot 'sdkmanager-stderr.txt'
    [IO.File]::WriteAllText($inputFile, $InputText, [Text.Encoding]::ASCII)
    Remove-Item $stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue

    $quoted = '"' + $SdkManager + '"'
    if ($Arguments -and $Arguments.Count -gt 0) {
        $quoted += ' ' + (($Arguments | ForEach-Object {
            if ($_ -match '[\s&|<>^]') { '"' + $_.Replace('"','\"') + '"' } else { $_ }
        }) -join ' ')
    }
    $cmdArgs = '/d /s /c "' + $quoted + '"'
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru `
        -RedirectStandardInput $inputFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

    if (Test-Path $stdoutFile) { Get-Content $stdoutFile | Out-Host }
    if (Test-Path $stderrFile) {
        $errText = Get-Content $stderrFile
        if ($errText) { $errText | Out-Host }
    }
    return $p.ExitCode
}

function EnsureAndroidSdk([string]$ToolRoot, [string]$CacheRoot, [string]$Flutter) {
    Step 'Checking Android SDK'
    $candidates = @()
    if ($env:ANDROID_SDK_ROOT) { $candidates += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $candidates += $env:ANDROID_HOME }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    $candidates += (Join-Path $ToolRoot 'android-sdk')

    $sdkRoot = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path $candidate)) {
            $sm = FindSdkManager $candidate
            if ($sm) { $sdkRoot = $candidate; break }
        }
    }

    if (-not $sdkRoot) {
        $sdkRoot = Join-Path $ToolRoot 'android-sdk'
        New-Item -ItemType Directory -Force -Path $sdkRoot | Out-Null
    }

    $sdkManager = FindSdkManager $sdkRoot
    if (-not $sdkManager) {
        Write-Host 'Android command-line tools were not found. Installing them locally.'
        $zip = Join-Path $CacheRoot 'android-commandline-tools.zip'
        $tmp = Join-Path $CacheRoot 'android-commandline-tools-extract'
        $url = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
        Download $url $zip
        Expand $zip $tmp
        $source = Join-Path $tmp 'cmdline-tools'
        if (-not (Test-Path $source)) { throw 'Android command-line tools archive layout was not recognized.' }
        $latest = Join-Path $sdkRoot 'cmdline-tools\latest'
        if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $latest | Out-Null
        Copy-Item (Join-Path $source '*') $latest -Recurse -Force
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $sdkManager = FindSdkManager $sdkRoot
        if (-not $sdkManager) { throw 'sdkmanager.bat is still missing after installation.' }
    }

    $env:ANDROID_SDK_ROOT = $sdkRoot
    $env:ANDROID_HOME = $sdkRoot
    $env:PATH = "$(Join-Path $sdkRoot 'platform-tools');$(Split-Path $sdkManager -Parent);$env:PATH"

    # Reuse a previously accepted Android SDK license. This keeps repeated Fix builds
    # non-interactive while still requiring explicit consent on a fresh toolchain.
    $stableLicense = Join-Path $sdkRoot 'licenses\android-sdk-license'
    if (-not (Test-Path $stableLicense)) {
        Step 'Android SDK license consent'
        Write-Host 'Android SDK packages require acceptance of the Google Android SDK license.' -ForegroundColor Yellow
        Write-Host 'Type ACCEPT to confirm that you have reviewed and accept the SDK license terms.' -ForegroundColor Yellow
        $consent = Read-Host 'Consent'
        if ($consent -cne 'ACCEPT') {
            throw 'Android SDK licenses were not accepted. Build stopped without changing license state.'
        }

        Step 'Accepting Android SDK licenses'
        $yesInput = (('y' + "`r`n") * 100)
        $licenseExit = InvokeSdkManagerWithInput $sdkManager @('--licenses') $yesInput $CacheRoot
        if ($licenseExit -ne 0) { throw "Android SDK license acceptance failed. Exit code: $licenseExit" }
        if (-not (Test-Path $stableLicense)) {
            throw 'Android SDK stable license file was not created after acceptance.'
        }
    } else {
        Write-Host 'Reusing accepted Android SDK license.' -ForegroundColor Green
    }

    Step 'Installing Android SDK packages'
    & $sdkManager 'platform-tools' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Android platform-tools.' }

    $compileSdk = GetFlutterCompileSdk $Flutter
    Write-Host "Flutter requires Android compileSdk $compileSdk."

    # Install only the SDK platform Flutter actually compiles against. Fix 5 tried
    # the newest repository API first (API 37), even though Flutter 3.47.x uses 36.
    # This avoids needless preview/newer-platform failures.
    & $sdkManager "platforms;android-$compileSdk" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Android API $compileSdk required by the installed Flutter SDK."
    }

    # Flutter doctor requires at least one runnable Android Build Tools package
    # before it considers the installed platform valid. Keep the build-tools major
    # aligned with compileSdk for this private Android build.
    $buildToolsVersion = "$compileSdk.0.0"
    Write-Host "Installing Android Build Tools $buildToolsVersion."
    & $sdkManager "build-tools;$buildToolsVersion" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Android Build Tools $buildToolsVersion."
    }

    return @($sdkRoot, $sdkManager, $compileSdk)
}

function SyncGradleTooling([string]$Flutter, [string]$Root) {
    Step 'Synchronizing Gradle tooling with installed Flutter'
    $tmpProject = Join-Path $env:TEMP ('gscm_flutter_template_' + [guid]::NewGuid().ToString('N'))
    try {
        & $Flutter create --platforms=android --org com.geumyi --project-name gscm $tmpProject | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter create failed while generating Gradle tooling.' }

        $srcAndroid = Join-Path $tmpProject 'android'
        $dstAndroid = Join-Path $Root 'android'
        Copy-Item (Join-Path $srcAndroid 'gradlew') (Join-Path $dstAndroid 'gradlew') -Force
        Copy-Item (Join-Path $srcAndroid 'gradlew.bat') (Join-Path $dstAndroid 'gradlew.bat') -Force
        New-Item -ItemType Directory -Force -Path (Join-Path $dstAndroid 'gradle\wrapper') | Out-Null
        Copy-Item (Join-Path $srcAndroid 'gradle\wrapper\*') (Join-Path $dstAndroid 'gradle\wrapper') -Force
        Copy-Item (Join-Path $srcAndroid 'settings.gradle.kts') (Join-Path $dstAndroid 'settings.gradle.kts') -Force
        Copy-Item (Join-Path $srcAndroid 'build.gradle.kts') (Join-Path $dstAndroid 'build.gradle.kts') -Force
        Copy-Item (Join-Path $srcAndroid 'gradle.properties') (Join-Path $dstAndroid 'gradle.properties') -Force

        # IMPORTANT: settings/wrapper and app Gradle DSL must come from the same
        # Flutter template generation. Fix 6 mixed an AGP 9.1 settings file with
        # an older app build.gradle.kts, causing Kotlin DSL deprecation errors.
        $generatedAppBuild = Join-Path $srcAndroid 'app\build.gradle.kts'
        if (-not (Test-Path $generatedAppBuild)) {
            throw 'Flutter template did not generate android/app/build.gradle.kts.'
        }
        Copy-Item $generatedAppBuild (Join-Path $dstAndroid 'app\build.gradle.kts') -Force
        $appBuildPath = Join-Path $dstAndroid 'app\build.gradle.kts'
        $appBuildText = Get-Content -Raw -Path $appBuildPath
        $appBuildText = $appBuildText -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
        [IO.File]::WriteAllText($appBuildPath, $appBuildText, [Text.UTF8Encoding]::new($false))

        Add-Content -Path (Join-Path $dstAndroid 'gradle.properties') -Value "`r`nandroid.builder.sdkDownload=true"
    } finally {
        if (Test-Path $tmpProject) { Remove-Item $tmpProject -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function WriteLocalProperties([string]$Root, [string]$SdkRoot, [string]$Flutter) {
    $flutterRoot = Split-Path (Split-Path $Flutter -Parent) -Parent
    function EscapeProp([string]$s) { return $s.Replace('\','\\').Replace(':','\:') }
    $content = @(
        'sdk.dir=' + (EscapeProp $SdkRoot),
        'flutter.sdk=' + (EscapeProp $flutterRoot)
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $Root 'android\local.properties'), $content + "`r`n", [Text.Encoding]::ASCII)
}

try {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Set-Location $Root
    $script:LogFile = Join-Path $Root 'GSCM-build.log'
    if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue }
    try {
        Start-Transcript -Path $script:LogFile -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {}

    Write-Host 'GSCM v1.1.2 APK Builder' -ForegroundColor Green
    Write-Host "Project: $Root"

    $ToolRoot = Join-Path $env:LOCALAPPDATA 'GSCM-Toolchain'
    $CacheRoot = Join-Path $ToolRoot 'cache'
    New-Item -ItemType Directory -Force -Path $ToolRoot, $CacheRoot | Out-Null

    $jdkHome = EnsureJdk $ToolRoot $CacheRoot
    $flutter = EnsureFlutter $ToolRoot $CacheRoot
    $sdkInfo = EnsureAndroidSdk $ToolRoot $CacheRoot $flutter
    $sdkRoot = $sdkInfo[0]

    & $flutter config --android-sdk $sdkRoot | Out-Host
    # JAVA_HOME and Gradle org.gradle.java.home below pin the Android build to JDK 17.
    & $flutter config --no-analytics | Out-Null

    SyncGradleTooling $flutter $Root
    WriteLocalProperties $Root $sdkRoot $flutter

    # Pin Gradle itself to the same JDK 17. Use forward slashes so the
    # Java-properties parser does not treat Windows backslashes as escapes.
    $gradleJavaHome = $jdkHome.Replace('\','/')
    Add-Content -Path (Join-Path $Root 'android\gradle.properties') -Value ("`r`norg.gradle.java.home=" + $gradleJavaHome)

    Step 'Flutter doctor'
    & $flutter doctor -v | Out-Host

    Step 'Resolving Dart packages'
    & $flutter pub get | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    if (-not $SkipChecks) {
        Step 'Static analysis'
        & $flutter analyze | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }

        Step 'Unit tests'
        & $flutter test | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
    }

    Step 'Building release APK'
    & $flutter build apk --release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk --release failed.' }

    $built = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $built)) { throw "APK was not created at expected path: $built" }

    $dist = Join-Path $Root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $final = Join-Path $dist 'GSCM-v1.1.2.apk'
    Copy-Item $built $final -Force
    $hash = (Get-FileHash $final -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = [math]::Round((Get-Item $final).Length / 1MB, 2)

    Write-Host ""
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host 'GSCM APK BUILD SUCCESS' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "APK: $final"
    Write-Host "Size: $size MB"
    Write-Host "SHA256: $hash"
    Write-Host "Log: $script:LogFile"

    try { Start-Process explorer.exe -ArgumentList "/select,`"$final`"" } catch {}
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
        $script:TranscriptStarted = $false
    }
    exit 0
} catch {
    Fail $_.Exception.Message
}
