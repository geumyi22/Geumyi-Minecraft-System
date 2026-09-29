param(
    [string]$Repository = "geumyi22/Geumyi-Minecraft-System",
    [string]$ExistingAndroidKeystore = "",
    [string]$ExistingStorePassword = "",
    [string]$ExistingKeyAlias = "",
    [string]$ExistingKeyPassword = ""
)

$ErrorActionPreference = "Stop"

function Find-Tool([string]$Name, [string[]]$Candidates) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in $Candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    throw "$Name was not found."
}

function New-RandomSecret([int]$Bytes = 32) {
    $buf = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buf)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($buf).Replace("+","A").Replace("/","B").Replace("=","")
}

function Set-GitHubSecret([string]$Name, [string]$Value) {
    & $script:GH secret set $Name --repo $Repository --body $Value
    if ($LASTEXITCODE -ne 0) { throw "GitHub secret registration failed: $Name" }
}

$GH = Find-Tool "gh" @()
$KEYTOOL = Find-Tool "keytool" @(
    $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\keytool.exe" } else { "" })
)
$OPENSSL = Find-Tool "openssl" @(
    "$env:ProgramFiles\Git\usr\bin\openssl.exe"
)

& $GH auth status
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI login is required. Run gh auth login first."
}

$root = Join-Path $env:USERPROFILE ".geumyi-signing"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$androidKey = Join-Path $root "gscm-release.jks"
$androidStorePass = ""
$androidKeyAlias = ""
$androidKeyPass = ""

if ($ExistingAndroidKeystore) {
    if (-not (Test-Path $ExistingAndroidKeystore)) {
        throw "Existing Android keystore was not found: $ExistingAndroidKeystore"
    }
    if (-not $ExistingStorePassword -or -not $ExistingKeyAlias -or -not $ExistingKeyPassword) {
        throw "Existing keystore mode requires StorePassword, KeyAlias, and KeyPassword."
    }
    Copy-Item $ExistingAndroidKeystore $androidKey -Force
    $androidStorePass = $ExistingStorePassword
    $androidKeyAlias = $ExistingKeyAlias
    $androidKeyPass = $ExistingKeyPassword
    Write-Host "Using the existing Android signing key." -ForegroundColor Green
}
elseif (-not (Test-Path $androidKey)) {
    $androidStorePass = New-RandomSecret 24
    $androidKeyPass = $androidStorePass
    $androidKeyAlias = "gscm-release"
    & $KEYTOOL -genkeypair -v         -keystore $androidKey         -storetype JKS         -storepass $androidStorePass         -keypass $androidKeyPass         -alias $androidKeyAlias         -keyalg RSA         -keysize 3072         -validity 10000         -dname "CN=Geumyi GSCM, OU=Release, O=Geumyi, C=KR"
    if ($LASTEXITCODE -ne 0) { throw "Android release keystore generation failed" }

    $cred = @{
        storePassword = $androidStorePass
        keyAlias = $androidKeyAlias
        keyPassword = $androidKeyPass
    } | ConvertTo-Json
    $credPath = Join-Path $root "gscm-release-credentials.json"
    [IO.File]::WriteAllText($credPath, $cred, [Text.UTF8Encoding]::new($false))
    Write-Host "Created a new persistent Android release key." -ForegroundColor Yellow
    Write-Host "Warning: if the installed GSCM uses another signer, one uninstall/reinstall may be required for this transition." -ForegroundColor Yellow
}
else {
    $credPath = Join-Path $root "gscm-release-credentials.json"
    if (-not (Test-Path $credPath)) {
        throw "The keystore exists but its credentials file is missing. Re-run with the existing-keystore parameters."
    }
    $cred = Get-Content $credPath -Raw | ConvertFrom-Json
    $androidStorePass = [string]$cred.storePassword
    $androidKeyAlias = [string]$cred.keyAlias
    $androidKeyPass = [string]$cred.keyPassword
    Write-Host "Reusing the existing Day 8 Android release key." -ForegroundColor Green
}

& $KEYTOOL -list -v -keystore $androidKey -storepass $androidStorePass -alias $androidKeyAlias |
    Select-String -Pattern "SHA256|SHA-256"

$manifestPrivate = Join-Path $root "deployment-ed25519-private.pem"
$manifestPublic = Join-Path $root "deployment-public.pem"
if (-not (Test-Path $manifestPrivate)) {
    & $OPENSSL genpkey -algorithm ED25519 -out $manifestPrivate
    if ($LASTEXITCODE -ne 0) { throw "Ed25519 private key generation failed" }
}
& $OPENSSL pkey -in $manifestPrivate -pubout -out $manifestPublic
if ($LASTEXITCODE -ne 0) { throw "Ed25519 public key generation failed" }

$androidB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($androidKey))
$manifestPrivateB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPrivate))

Write-Host "Registering GitHub Actions secrets..." -ForegroundColor Cyan
Set-GitHubSecret "ANDROID_RELEASE_KEYSTORE_B64" $androidB64
Set-GitHubSecret "ANDROID_RELEASE_STORE_PASSWORD" $androidStorePass
Set-GitHubSecret "ANDROID_RELEASE_KEY_ALIAS" $androidKeyAlias
Set-GitHubSecret "ANDROID_RELEASE_KEY_PASSWORD" $androidKeyPass
Set-GitHubSecret "DEPLOYMENT_ED25519_PRIVATE_KEY_B64" $manifestPrivateB64

$programDataRoot = Join-Path $env:ProgramData "GeumyiServerCenter"
$trustedPublic = Join-Path $programDataRoot "deployment-public.pem"
try {
    New-Item -ItemType Directory -Force -Path $programDataRoot | Out-Null
    Copy-Item $manifestPublic $trustedPublic -Force
    Write-Host "Installed GSC trusted public key: $trustedPublic" -ForegroundColor Green
}
catch {
    Write-Warning "Could not copy the public key into ProgramData. Copy this file from an Administrator shell:"
    Write-Host "$manifestPublic -> $trustedPublic"
}

Write-Host ""
Write-Host "Day 8 signing bootstrap complete" -ForegroundColor Green
Write-Host "Android keystore: $androidKey"
Write-Host "Manifest public key: $manifestPublic"
Write-Host "GitHub repository: $Repository"
Write-Host ""
Write-Host "Known signer SHA-256 for the Day 6 CI APK build 113:" -ForegroundColor Yellow
Write-Host "21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da"
Write-Host "If the new signer differs and that CI APK is installed, a one-time uninstall/reinstall is required before future in-place updates." -ForegroundColor Yellow
