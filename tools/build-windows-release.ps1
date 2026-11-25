[CmdletBinding()]
param([ValidatePattern('^v\d+\.\d+\.\d+\.\d+$')][string]$ExpectedTag)
$ErrorActionPreference = 'Stop'
function Assert-LastExitCode([string]$Action) { if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit code $LASTEXITCODE)." } }
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Invoke-Flutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    Push-Location -LiteralPath $repoRoot
    try { & flutter @Arguments } finally { Pop-Location }
}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version=(Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid VERSION '$version'." }
$head=(& git -C $repoRoot rev-parse HEAD).Trim(); Assert-LastExitCode 'Reading HEAD'
$initialStatus = @(& git -C $repoRoot status --porcelain) -join "`n"; Assert-LastExitCode 'Checking source status'
if ($initialStatus) { throw 'Release build requires a clean tracked source tree.' }
$buildNumber=if ($ExpectedTag) { $ExpectedTag.Split('.')[3] } else { (& git -C $repoRoot rev-list --count HEAD).Trim() }
if ($ExpectedTag -and $ExpectedTag -ne "v$version.$buildNumber") { throw "Expected tag '$ExpectedTag' does not match VERSION '$version'." }
if ($buildNumber -notmatch '^\d+$' -or [int64]$buildNumber -gt 65534) { throw "Invalid Windows build number '$buildNumber'." }
$provenancePath = Join-Path $repoRoot 'build\windows-release.json'
if (Test-Path -LiteralPath $provenancePath -PathType Leaf) { Remove-Item -LiteralPath $provenancePath -Force }
Invoke-Flutter pub get
if ($LASTEXITCODE -ne 0) { & powershell -NoProfile -File (Join-Path $repoRoot 'tools\prepare-flutter-windows.ps1'); Assert-LastExitCode 'Preparing junctions'; Invoke-Flutter pub get; Assert-LastExitCode 'Resolving dependencies' }
& powershell -NoProfile -File (Join-Path $repoRoot 'tools\prepare-flutter-windows.ps1'); Assert-LastExitCode 'Preparing junctions'
Invoke-Flutter analyze; Assert-LastExitCode 'Running flutter analyze'
Invoke-Flutter test; Assert-LastExitCode 'Running flutter test'
$previousSemver4 = $env:SEMVER4_BUILD
try {
    $env:SEMVER4_BUILD=$buildNumber
    Invoke-Flutter build windows --release; Assert-LastExitCode 'Building Windows Release'
} finally { $env:SEMVER4_BUILD=$previousSemver4 }
$exe=Join-Path $repoRoot 'build\windows\x64\runner\Release\meme_searcher.exe'; $appSo=Join-Path $repoRoot 'build\windows\x64\runner\Release\data\app.so'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or -not (Test-Path -LiteralPath $appSo -PathType Leaf)) { throw 'Release build did not produce expected runtime files.' }
$fileInfo=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe); $peVersion=$fileInfo.FileVersion
if ($peVersion -ne "$version.$buildNumber" -or $fileInfo.ProductVersion -ne $peVersion) { throw "PE version '$peVersion' differs from expected '$version.$buildNumber'." }
$flutter=Invoke-Flutter --version --machine | ConvertFrom-Json; Assert-LastExitCode 'Reading Flutter version'
$headAfter=(& git -C $repoRoot rev-parse HEAD).Trim(); Assert-LastExitCode 'Rechecking HEAD'
if ($headAfter -ne $head) { throw 'Source commit changed during the release build.' }
[ordered]@{sourceCommit=$head;peVersion=$peVersion;exeSha256=(Get-Sha256 $exe);appSoSha256=(Get-Sha256 $appSo);flutterVersion=$flutter.flutterVersion;flutterRevision=$flutter.frameworkRevision} | ConvertTo-Json | Set-Content -LiteralPath $provenancePath -Encoding utf8
$finalStatus = @(& git -C $repoRoot status --porcelain) -join "`n"; Assert-LastExitCode 'Rechecking source status'
if ($finalStatus) { throw 'Release build changed tracked source files.' }
Write-Host "Built Windows Release $peVersion from $head"
