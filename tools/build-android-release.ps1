[CmdletBinding()]
param([ValidatePattern('^v\d+\.\d+\.\d+\.\d+$')][string]$ExpectedTag)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-LastExitCode([string]$Action) {
    if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit code $LASTEXITCODE)." }
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
Assert-LastExitCode 'Reading HEAD'
$status = @(& git -C $repoRoot status --porcelain) -join "`n"
Assert-LastExitCode 'Checking source status'
if ($status) { throw 'Release build requires a clean tracked source tree.' }
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
$buildNumber = (& git -C $repoRoot rev-list --count HEAD).Trim()
Assert-LastExitCode 'Reading the build number'
if ($version -notmatch '^\d+\.\d+\.\d+$' -or $buildNumber -notmatch '^[1-9]\d*$' -or [int64]$buildNumber -gt 65534) {
    throw 'Invalid shared release version.'
}
$versionName = "$version.$buildNumber"
$tag = "v$versionName"
if ($ExpectedTag -and $ExpectedTag -ne $tag) { throw "Expected $ExpectedTag but the source version is $tag." }

$signingProperties = $env:MEME_ANDROID_SIGNING_PROPERTIES
if (!$signingProperties -or ![IO.Path]::IsPathRooted($signingProperties) -or
    !(Test-Path -LiteralPath $signingProperties -PathType Leaf)) {
    throw 'Set MEME_ANDROID_SIGNING_PROPERTIES to an absolute path to the private release signing properties file.'
}
$signingProperties = (Resolve-Path -LiteralPath $signingProperties).Path
if ($signingProperties.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep Android release signing properties outside the repository.'
}
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
if (!$sdk) { throw 'Set ANDROID_HOME to the Android SDK directory.' }
$tools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
    } | Select-Object -First 1
if (!$tools) { throw 'Android SDK build-tools with aapt and apksigner are required.' }

Push-Location -LiteralPath $repoRoot
try {
    $provenance = Join-Path $repoRoot 'build/android-release.json'
    if (Test-Path -LiteralPath $provenance -PathType Leaf) {
        Remove-Item -LiteralPath $provenance -Force
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath '.flutter-plugins-dependencies' -PathType Leaf)) {
        & pwsh -NoProfile -File (Join-Path $repoRoot 'tools/prepare-flutter-windows.ps1')
        Assert-LastExitCode 'Preparing Windows plugin junctions'
        & flutter pub get
    }
    Assert-LastExitCode 'Resolving dependencies and registering Android plugins'
    $registrant = 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
    if (!(Test-Path -LiteralPath $registrant -PathType Leaf)) {
        throw 'The Flutter Android plugin registrant is missing.'
    }
    & flutter build apk --release "--build-name=$versionName" "--build-number=$buildNumber"
    Assert-LastExitCode 'Building the Android APK'
    $apk = (Resolve-Path -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk').Path
    $signer = Join-Path $tools.FullName 'apksigner.bat'
    & $signer verify --print-certs $apk
    Assert-LastExitCode 'Verifying APK signing'
    $badging = @(& (Join-Path $tools.FullName 'aapt.exe') dump badging $apk)
    Assert-LastExitCode 'Reading the APK manifest'
    $package = $badging | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
    $expectedManifest = "name='dev.memesearcher.meme_searcher' versionCode='$buildNumber' versionName='$versionName'"
    if (!$package -or !$package.Contains($expectedManifest)) { throw 'APK package name and version must match the release.' }
    if ((& git rev-parse HEAD).Trim() -ne $commit -or @(& git status --porcelain)) {
        throw 'Source changed during the Android release build.'
    }
    $archiveName = "meme-searcher-$tag-android.apk"
    $dist = New-Item -ItemType Directory -Path (Join-Path $repoRoot 'dist') -Force
    $artifact = Join-Path $dist.FullName $archiveName
    Copy-Item -LiteralPath $apk -Destination $artifact -Force
    [ordered]@{
        sourceCommit = $commit
        versionName = $versionName
        versionCode = [int]$buildNumber
        packageName = 'dev.memesearcher.meme_searcher'
        assetName = $archiveName
        apkSha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    } | ConvertTo-Json | Set-Content -LiteralPath $provenance -Encoding utf8
    Write-Host "Built Android $versionName from $commit"
    Write-Host "Created $artifact"
} finally {
    Pop-Location
}
