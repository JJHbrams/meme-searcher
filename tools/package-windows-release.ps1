[CmdletBinding()]
param(
    [ValidatePattern('^v\d+\.\d+\.\d+\.\d+$')][string]$ExpectedTag,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
function Assert-LastExitCode([string]$Action) { if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit code $LASTEXITCODE)." } }
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-StreamSha256($Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Require-File([string]$Base, [string]$Relative) {
    $path = Join-Path $Base $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required Windows runtime file: $Relative" }
    $path
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$exePath = Join-Path $releaseDir 'meme_searcher.exe'
$provenancePath = Join-Path $repoRoot 'build\windows-release.json'
$distDir = Join-Path $repoRoot 'dist'
if ((@(& git -C $repoRoot status --porcelain) -join "`n")) { throw 'Packaging requires a clean tracked source tree.' }
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Release executable not found: $exePath. Run tools/build-windows-release.ps1 first." }
if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) { throw "Build provenance not found: $provenancePath. Run tools/build-windows-release.ps1 first." }

$repoVersion = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($repoVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid VERSION '$repoVersion'." }
$head = (& git -C $repoRoot rev-parse HEAD).Trim(); Assert-LastExitCode 'Reading HEAD'
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($provenance.sourceCommit -ne $head) { throw 'Build provenance was made from a different commit.' }
if ($provenance.exeSha256 -ne (Get-Sha256 $exePath)) { throw 'Executable no longer matches build provenance.' }
$appSoPath = Require-File $releaseDir 'data/app.so'
if ($provenance.appSoSha256 -ne (Get-Sha256 $appSoPath)) { throw 'AOT library no longer matches build provenance.' }
$fileInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
$fileVersion = $fileInfo.FileVersion
if ($fileVersion -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $fileInfo.ProductVersion -ne $fileVersion -or $provenance.peVersion -ne $fileVersion) { throw 'PE FileVersion, ProductVersion, and build provenance must agree.' }
if (-not $fileVersion.StartsWith("$repoVersion.")) { throw "PE version '$fileVersion' does not match VERSION '$repoVersion'." }
$tag = "v$fileVersion"
if ($ExpectedTag -and $ExpectedTag -ne $tag) { throw "Expected tag '$ExpectedTag' does not match PE version '$tag'." }

$archiveName = "meme-searcher-$tag-windows-x64.zip"
$archivePath = Join-Path $distDir $archiveName
$checksumPath = Join-Path $distDir 'SHA256SUMS.txt'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempDir = Join-Path $tempRoot ("meme-searcher-package-" + [Guid]::NewGuid().ToString('N'))
$stageDir = Join-Path $tempDir 'package'
$tempArchive = Join-Path $tempDir $archiveName
try {
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    $releasePrefix = [IO.Path]::GetFullPath($releaseDir) + [IO.Path]::DirectorySeparatorChar
    $manifest = Join-Path $repoRoot 'build\windows\x64\install_manifest.txt'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "Missing install manifest: $manifest" }
    $installed = Get-Content -LiteralPath $manifest | ForEach-Object { [IO.Path]::GetFullPath($_) } | Where-Object { $_.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase) }
    foreach ($source in (@($installed) + $exePath | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Install manifest references missing runtime file: $source" }
        $relative = $source.Substring($releasePrefix.Length)
        $rootCopy = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $rootCopy -PathType Leaf) -or (Get-Sha256 $rootCopy) -ne (Get-Sha256 $source)) { throw "Project-root copy differs from build: $relative" }
        $destination = Join-Path $stageDir $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($required in @('meme_searcher.exe','flutter_windows.dll','flutter_secure_storage_windows_plugin.dll','url_launcher_windows_plugin.dll','webview_flutter_windows_plugin.dll','WebView2Loader.dll','data/app.so','data/icudtl.dat','data/flutter_assets/AssetManifest.bin','data/flutter_assets/NOTICES.Z','data/licenses/webview2/LICENSE.txt','data/licenses/webview2/NOTICE.txt')) { [void](Require-File $stageDir $required) }
    foreach ($document in @('README.md','THIRD_PARTY_NOTICES.md')) { Copy-Item -LiteralPath (Join-Path $repoRoot $document) -Destination (Join-Path $stageDir $document) -Force }
    Copy-Item -LiteralPath $provenancePath -Destination (Join-Path $stageDir 'RELEASE-BUILD.json') -Force
    $mediaDirectory = New-Item -ItemType Directory -Path (Join-Path $stageDir 'docs/media') -Force
    foreach ($document in @('guide.md', 'release.md')) { Copy-Item -LiteralPath (Join-Path $repoRoot "docs/$document") -Destination (Join-Path $stageDir "docs/$document") }
    foreach ($name in @('meme-drawer.jpg','find-your-meme.png','find-your-meme-mobile.png','home.png','search-results.png')) { Copy-Item -LiteralPath (Join-Path $repoRoot "docs/media/$name") -Destination $mediaDirectory.FullName }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $tempArchive -CompressionLevel Optimal
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($tempArchive)
    try {
        foreach ($required in @('meme_searcher.exe','flutter_windows.dll','data/app.so','RELEASE-BUILD.json')) { if (-not ($zip.Entries.FullName -contains $required)) { throw "Archive is missing $required" } }
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            if ([IO.Path]::IsPathRooted($entry.FullName) -or $entry.FullName.Split('/') -contains '..') { throw "Unsafe archive entry: $($entry.FullName)" }
            $staged = Require-File $stageDir $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $stream = $entry.Open()
            try { if ((Get-StreamSha256 $stream) -ne (Get-Sha256 $staged)) { throw "Archive entry hash differs from staged runtime: $($entry.FullName)" } } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Move-Item -LiteralPath $tempArchive -Destination $archivePath
    $hash = Get-Sha256 $archivePath
    Set-Content -LiteralPath $checksumPath -Value "$hash *$archiveName" -Encoding Ascii
} finally {
    if ((Test-Path -LiteralPath $tempDir) -and $tempDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
Write-Host "Created $archivePath"
Write-Host "Created $checksumPath"
if ($Publish) {
    if (-not $ExpectedTag) { throw '-Publish requires -ExpectedTag.' }
    $tagCommit = (& git -C $repoRoot rev-parse -q --verify "refs/tags/$tag^{commit}").Trim(); Assert-LastExitCode "Verifying local tag $tag"
    if ($tagCommit -ne $head) { throw "Tag $tag does not resolve to HEAD." }
    $remoteTag = (& git -C $repoRoot ls-remote origin "refs/tags/$tag^{}").Trim(); Assert-LastExitCode "Reading remote tag $tag"
    if (-not $remoteTag -or ($remoteTag.Split("`t")[0] -ne $head)) { throw "Remote tag $tag does not resolve to HEAD." }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI is required for -Publish; use the documented authenticated REST equivalent otherwise.' }
    & gh release view $tag --repo JJHbrams/meme-searcher 2>$null
    if ($LASTEXITCODE -eq 0) { throw "A release for $tag already exists; refusing overwrite." }
    & gh release create $tag $archivePath $checksumPath --repo JJHbrams/meme-searcher --verify-tag --draft --notes-from-tag --title "Meme Snatcher $tag (Windows x64)"; Assert-LastExitCode 'Creating draft release'
    $draft = & gh release view $tag --repo JJHbrams/meme-searcher --json isDraft,assets | ConvertFrom-Json
    $checksumHash = Get-Sha256 $checksumPath
    $archiveAsset = @($draft.assets | Where-Object { $_.name -eq $archiveName -and $_.size -eq (Get-Item $archivePath).Length -and $_.digest -eq "sha256:$hash" })
    $checksumAsset = @($draft.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' -and $_.size -eq (Get-Item $checksumPath).Length -and $_.digest -eq "sha256:$checksumHash" })
    if (-not $draft.isDraft -or $archiveAsset.Count -ne 1 -or $checksumAsset.Count -ne 1) { throw 'Draft asset digest verification failed.' }
    & gh release edit $tag --repo JJHbrams/meme-searcher --draft=false --latest; Assert-LastExitCode 'Publishing release'
    $downloadPath = Join-Path $tempRoot ("meme-searcher-download-" + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/JJHbrams/meme-searcher/releases/download/$tag/$archiveName" -OutFile $downloadPath
        if ((Get-Sha256 $downloadPath) -ne $hash) { throw 'Anonymous release download hash differs from packaged archive.' }
    } finally { if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force } }
}
