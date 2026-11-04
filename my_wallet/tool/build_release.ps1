<#
Builds the signed universal release APK and copies it to ..\release\my_wallet-<version>.apk

  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1

Version comes from pubspec.yaml (`version: X.Y.Z+CODE`). CODE must equal
X*1000000 + Y*1000 + Z so every new release installs over the previous one.
#>
$ErrorActionPreference = 'Stop'
$app = Split-Path -Parent $PSScriptRoot
Set-Location $app

$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
if (-not $line) { throw 'pubspec.yaml: version must look like X.Y.Z+CODE' }
$g = $line.Matches[0].Groups
$name = "$($g[1].Value).$($g[2].Value).$($g[3].Value)"
$code = [int]$g[4].Value
$expected = [int]$g[1].Value * 1000000 + [int]$g[2].Value * 1000 + [int]$g[3].Value
if ($code -ne $expected) { throw "pubspec.yaml: build number for $name must be $expected, found $code" }

if (-not (Test-Path android\key.properties)) {
    throw 'android\key.properties missing: refusing to build a release that could not update the installed app'
}

# Gradle 8.14 does not run on Android Studio's bundled JDK 25; use JDK 17 for this build only.
$jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($jdk) { flutter config --jdk-dir="$($jdk.FullName)" | Out-Null }
try {
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }
} finally {
    if ($jdk) { flutter config --jdk-dir="" | Out-Null }
}

$outDir = Join-Path (Split-Path -Parent $app) 'release'
New-Item -ItemType Directory -Force $outDir | Out-Null
$apk = Join-Path $outDir "my_wallet-$name.apk"
Copy-Item build\app\outputs\flutter-apk\app-release.apk $apk -Force
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
"$hash  my_wallet-$name.apk" | Set-Content -Encoding ascii "$apk.sha256"
Write-Host "Built $apk (versionCode $code)"
