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
    throw "$Name 을(를) 찾지 못했습니다."
}

function New-RandomSecret([int]$Bytes = 32) {
    $buf = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Fill($buf)
    return [Convert]::ToBase64String($buf).Replace("+","A").Replace("/","B").Replace("=","")
}

function Set-GitHubSecret([string]$Name, [string]$Value) {
    & $script:GH secret set $Name --repo $Repository --body $Value
    if ($LASTEXITCODE -ne 0) { throw "GitHub secret 등록 실패: $Name" }
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
    throw "GitHub CLI 로그인이 필요합니다. 먼저 gh auth login 을 실행하세요."
}

$root = Join-Path $env:USERPROFILE ".geumyi-signing"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$androidKey = Join-Path $root "gscm-release.jks"
$androidStorePass = ""
$androidKeyAlias = ""
$androidKeyPass = ""

if ($ExistingAndroidKeystore) {
    if (-not (Test-Path $ExistingAndroidKeystore)) {
        throw "기존 Android keystore 파일이 없습니다: $ExistingAndroidKeystore"
    }
    if (-not $ExistingStorePassword -or -not $ExistingKeyAlias -or -not $ExistingKeyPassword) {
        throw "기존 keystore 사용 시 StorePassword/KeyAlias/KeyPassword를 모두 지정해야 합니다."
    }
    Copy-Item $ExistingAndroidKeystore $androidKey -Force
    $androidStorePass = $ExistingStorePassword
    $androidKeyAlias = $ExistingKeyAlias
    $androidKeyPass = $ExistingKeyPassword
    Write-Host "기존 Android signing key를 사용합니다." -ForegroundColor Green
}
elseif (-not (Test-Path $androidKey)) {
    $androidStorePass = New-RandomSecret 24
    $androidKeyPass = $androidStorePass
    $androidKeyAlias = "gscm-release"
    & $KEYTOOL -genkeypair -v         -keystore $androidKey         -storetype JKS         -storepass $androidStorePass         -keypass $androidKeyPass         -alias $androidKeyAlias         -keyalg RSA         -keysize 3072         -validity 10000         -dname "CN=Geumyi GSCM, OU=Release, O=Geumyi, C=KR"
    if ($LASTEXITCODE -ne 0) { throw "Android release keystore 생성 실패" }

    $cred = @{
        storePassword = $androidStorePass
        keyAlias = $androidKeyAlias
        keyPassword = $androidKeyPass
    } | ConvertTo-Json
    $credPath = Join-Path $root "gscm-release-credentials.json"
    [IO.File]::WriteAllText($credPath, $cred, [Text.UTF8Encoding]::new($false))
    Write-Host "새 Android release key를 생성했습니다." -ForegroundColor Yellow
    Write-Host "주의: 현재 설치된 GSCM이 다른 signer라면 이번 전환 때 한 번 삭제/재설치가 필요합니다." -ForegroundColor Yellow
}
else {
    $credPath = Join-Path $root "gscm-release-credentials.json"
    if (-not (Test-Path $credPath)) {
        throw "기존 $androidKey 는 있지만 credentials 파일이 없습니다. 기존 keystore 매개변수로 다시 실행하세요."
    }
    $cred = Get-Content $credPath -Raw | ConvertFrom-Json
    $androidStorePass = [string]$cred.storePassword
    $androidKeyAlias = [string]$cred.keyAlias
    $androidKeyPass = [string]$cred.keyPassword
    Write-Host "기존 Day 8 Android release key를 재사용합니다." -ForegroundColor Green
}

& $KEYTOOL -list -v -keystore $androidKey -storepass $androidStorePass -alias $androidKeyAlias |
    Select-String -Pattern "SHA256|SHA-256"

$manifestPrivate = Join-Path $root "deployment-ed25519-private.pem"
$manifestPublic = Join-Path $root "deployment-public.pem"
if (-not (Test-Path $manifestPrivate)) {
    & $OPENSSL genpkey -algorithm ED25519 -out $manifestPrivate
    if ($LASTEXITCODE -ne 0) { throw "Ed25519 private key 생성 실패" }
}
& $OPENSSL pkey -in $manifestPrivate -pubout -out $manifestPublic
if ($LASTEXITCODE -ne 0) { throw "Ed25519 public key 생성 실패" }

$androidB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($androidKey))
$manifestPrivateB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPrivate))

Write-Host "GitHub Actions secrets 등록 중..." -ForegroundColor Cyan
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
    Write-Host "GSC trusted public key 설치: $trustedPublic" -ForegroundColor Green
}
catch {
    Write-Warning "ProgramData에 public key를 복사하지 못했습니다. 관리자 PowerShell에서 다음 파일을 복사하세요:"
    Write-Host "$manifestPublic -> $trustedPublic"
}

Write-Host ""
Write-Host "Day 8 signing bootstrap 완료" -ForegroundColor Green
Write-Host "Android keystore: $androidKey"
Write-Host "Manifest public key: $manifestPublic"
Write-Host "GitHub repository: $Repository"
Write-Host ""
Write-Host "Day 6 CI APK build 113의 알려진 signer SHA-256:" -ForegroundColor Yellow
Write-Host "21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da"
Write-Host "새 signer가 이 값과 다르고 현재 휴대폰에 그 CI APK가 설치되어 있다면 최초 1회 삭제/재설치 후부터 정상 in-place update가 가능합니다." -ForegroundColor Yellow
