param(
    [string]$JdkHome = $env:JAVA_HOME,
    [string]$OutputJar = (Join-Path $PSScriptRoot '..\..\GSC\ServerCenter\cmd\host\assets\gsc-velocity-control.jar')
)
$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $PSScriptRoot 'build'
$depsDir = Join-Path $buildDir 'deps'
$classDir = Join-Path $buildDir ('classes-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $depsDir,$classDir | Out-Null
$dependencies = @{
    'velocity-api.jar' = 'https://repo.papermc.io/repository/maven-public/com/velocitypowered/velocity-api/4.2.0/velocity-api-4.2.0.jar'
    'guice.jar' = 'https://repo.maven.apache.org/maven2/com/google/inject/guice/7.0.0/guice-7.0.0.jar'
    'adventure-api.jar' = 'https://repo.maven.apache.org/maven2/net/kyori/adventure-api/5.2.0/adventure-api-5.2.0.jar'
    'slf4j-api.jar' = 'https://repo.maven.apache.org/maven2/org/slf4j/slf4j-api/2.0.19/slf4j-api-2.0.19.jar'
}
foreach ($name in $dependencies.Keys) {
    Invoke-WebRequest -Uri $dependencies[$name] -OutFile (Join-Path $depsDir $name)
}
if ($JdkHome) {
    $compiler = Join-Path $JdkHome 'bin\javac.exe'
    $archiver = Join-Path $JdkHome 'bin\jar.exe'
} else {
    $compiler = (Get-Command javac -ErrorAction Stop).Source
    $archiver = (Get-Command jar -ErrorAction Stop).Source
}
& $compiler --release 17 -proc:none -encoding UTF-8 -cp "$depsDir\*" -d $classDir (Join-Path $PSScriptRoot 'src\main\java\kr\geumyi\velocitycontrol\GSCVelocityControl.java')
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed; use JDK 25 or newer for the Velocity 4.2 API.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputJar) | Out-Null
& $archiver --create --date=2026-11-14T00:00:00Z --file $OutputJar -C $classDir . -C (Join-Path $PSScriptRoot 'src\main\resources') velocity-plugin.json
if ($LASTEXITCODE -ne 0) { throw 'JAR packaging failed.' }
Get-FileHash -LiteralPath $OutputJar -Algorithm SHA256
