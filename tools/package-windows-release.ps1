[CmdletBinding()]
param(
    [ValidatePattern('^v\d+\.\d+\.\d+\.\d+$')][string]$ExpectedTag,
    [switch]$IncludeAndroid,
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
$updaterPath = Require-File $releaseDir 'meme_updater.exe'
if ($provenance.updaterSha256 -ne (Get-Sha256 $updaterPath)) { throw 'Updater no longer matches build provenance.' }
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
$mcpArchiveName = "meme-searcher-$tag-mcp.zip"
$mcpArchivePath = Join-Path $distDir $mcpArchiveName
$checksumPath = Join-Path $distDir 'SHA256SUMS.txt'
$androidPath = $null
$androidHash = $null
if ($IncludeAndroid) {
    $androidName = "meme-searcher-$tag-android.apk"
    $androidPath = Require-File $distDir $androidName
    $androidProvenancePath = Require-File $repoRoot 'build/android-release.json'
    $androidProvenance = Get-Content -LiteralPath $androidProvenancePath -Raw | ConvertFrom-Json
    $androidHash = Get-Sha256 $androidPath
    if ($androidProvenance.sourceCommit -ne $head -or
        $androidProvenance.versionName -ne $fileVersion -or
        $androidProvenance.versionCode -ne [int]$fileVersion.Split('.')[-1] -or
        $androidProvenance.packageName -ne 'dev.memesearcher.meme_searcher' -or
        $androidProvenance.assetName -ne $androidName -or
        $androidProvenance.apkSha256 -ne $androidHash) {
        throw 'The Android APK does not match this release source, version, or SHA-256.'
    }
}
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
    foreach ($source in (@($installed) + $exePath + $updaterPath | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Install manifest references missing runtime file: $source" }
        $relative = $source.Substring($releasePrefix.Length)
        $rootCopy = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $rootCopy -PathType Leaf) -or (Get-Sha256 $rootCopy) -ne (Get-Sha256 $source)) { throw "Project-root copy differs from build: $relative" }
        $destination = Join-Path $stageDir $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($required in @('meme_searcher.exe','meme_updater.exe','flutter_windows.dll','flutter_secure_storage_windows_plugin.dll','url_launcher_windows_plugin.dll','webview_flutter_windows_plugin.dll','WebView2Loader.dll','data/app.so','data/icudtl.dat','data/flutter_assets/AssetManifest.bin','data/flutter_assets/NOTICES.Z','data/licenses/webview2/LICENSE.txt','data/licenses/webview2/NOTICE.txt')) { [void](Require-File $stageDir $required) }
    foreach ($document in @('README.md','THIRD_PARTY_NOTICES.md')) { Copy-Item -LiteralPath (Join-Path $repoRoot $document) -Destination (Join-Path $stageDir $document) -Force }
    Copy-Item -LiteralPath $provenancePath -Destination (Join-Path $stageDir 'RELEASE-BUILD.json') -Force
    $mediaDirectory = New-Item -ItemType Directory -Path (Join-Path $stageDir 'docs/media') -Force
    foreach ($document in @('guide.md', 'release.md')) { Copy-Item -LiteralPath (Join-Path $repoRoot "docs/$document") -Destination (Join-Path $stageDir "docs/$document") }
    foreach ($name in @('meme-drawer.jpg','find-your-meme.png','find-your-meme-mobile.png','home.png','search-results.png')) { Copy-Item -LiteralPath (Join-Path $repoRoot "docs/media/$name") -Destination $mediaDirectory.FullName }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stagePrefix = [IO.Path]::GetFullPath($stageDir).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $createdZip = [IO.Compression.ZipFile]::Open($tempArchive, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -LiteralPath $stageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($stagePrefix.Length).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($createdZip, $_.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $createdZip.Dispose() }
    $zip = [IO.Compression.ZipFile]::OpenRead($tempArchive)
    try {
        foreach ($required in @('meme_searcher.exe','meme_updater.exe','flutter_windows.dll','data/app.so','RELEASE-BUILD.json')) { if (-not ($zip.Entries.FullName -contains $required)) { throw "Archive is missing $required" } }
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            if ([IO.Path]::IsPathRooted($entry.FullName) -or $entry.FullName.Split('/') -contains '..') { throw "Unsafe archive entry: $($entry.FullName)" }
            $staged = Require-File $stageDir $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $stream = $entry.Open()
            try { if ((Get-StreamSha256 $stream) -ne (Get-Sha256 $staged)) { throw "Archive entry hash differs from staged runtime: $($entry.FullName)" } } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    $tempMcpArchive = & (Join-Path $PSScriptRoot 'package-mcp-release.ps1') -Tag $tag -OutputDirectory $tempDir
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Move-Item -LiteralPath $tempArchive -Destination $archivePath
    Move-Item -LiteralPath $tempMcpArchive -Destination $mcpArchivePath -Force
    $hash = Get-Sha256 $archivePath
    $checksums = @("$hash *$archiveName")
    if ($IncludeAndroid) { $checksums += "$androidHash *$androidName" }
    $checksums += "$(Get-Sha256 $mcpArchivePath) *$mcpArchiveName"
    Set-Content -LiteralPath $checksumPath -Value $checksums -Encoding Ascii
} finally {
    if ((Test-Path -LiteralPath $tempDir) -and $tempDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
Write-Host "Created $archivePath"
Write-Host "Created $mcpArchivePath"
Write-Host "Created $checksumPath"
if ($IncludeAndroid) { Write-Host "Verified $androidPath" }
if ($Publish) {
    if (-not $ExpectedTag) { throw '-Publish requires -ExpectedTag.' }
    $tagCommit = (& git -C $repoRoot rev-parse -q --verify "refs/tags/$tag^{commit}").Trim(); Assert-LastExitCode "Verifying local tag $tag"
    if ($tagCommit -ne $head) { throw "Tag $tag does not resolve to HEAD." }
    $remoteTag = (& git -C $repoRoot ls-remote origin "refs/tags/$tag^{}").Trim(); Assert-LastExitCode "Reading remote tag $tag"
    if (-not $remoteTag -or ($remoteTag.Split("`t")[0] -ne $head)) { throw "Remote tag $tag does not resolve to HEAD." }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI is required for -Publish; use the documented authenticated REST equivalent otherwise.' }
    $repo = 'JJHbrams/meme-searcher'
    $existing = & gh release list --repo $repo --limit 100 --json tagName | ConvertFrom-Json
    Assert-LastExitCode 'Checking for existing releases'
    if ($tag -in $existing.tagName) { throw "A release for $tag already exists; refusing overwrite." }
    $assets = @($archivePath, $mcpArchivePath, $checksumPath)
    if ($IncludeAndroid) { $assets += $androidPath }
    $title = if ($IncludeAndroid) { "Meme Snatcher $tag (Windows 및 Android)" } else { "Meme Snatcher $tag (Windows x64)" }
    $notesPath = Join-Path $tempRoot ("meme-searcher-notes-" + [Guid]::NewGuid().ToString('N') + '.md')
    try {
        $notes = & git -C $repoRoot -c i18n.logOutputEncoding=UTF-8 tag --list --format='%(contents)' $tag
        Assert-LastExitCode 'Reading tag annotation'
        $releaseNotes = ($notes -join "`n").Trim()
        $releaseNotes += "`n`nCodex용 MCP가 필요하면 Assets에서 $mcpArchiveName 파일을 받으세요."
        [IO.File]::WriteAllText($notesPath, $releaseNotes, [Text.UTF8Encoding]::new($false))
        & gh release create $tag @assets --repo $repo --verify-tag --draft --notes-file $notesPath --title $title
        Assert-LastExitCode 'Creating draft release'
    } finally {
        if (Test-Path -LiteralPath $notesPath -PathType Leaf) { Remove-Item -LiteralPath $notesPath -Force }
    }
    $draft = & gh release view $tag --repo $repo --json isDraft,assets | ConvertFrom-Json
    Assert-LastExitCode 'Reading draft assets'
    if (-not $draft.isDraft -or $draft.assets.Count -ne $assets.Count) { throw 'Unexpected release draft.' }
    $verified = @{}
    foreach ($path in $assets) {
        $item = Get-Item -LiteralPath $path
        $expected = Get-Sha256 $path
        $matches = @($draft.assets | Where-Object {
            $_.name -eq $item.Name -and $_.size -eq $item.Length -and $_.digest -eq "sha256:$expected"
        })
        if ($matches.Count -ne 1) { throw "Draft asset digest verification failed: $($item.Name)" }
        $verified[$item.Name] = $expected
    }
    & gh release edit $tag --repo $repo --draft=false --latest
    Assert-LastExitCode 'Publishing release'
    foreach ($item in $verified.GetEnumerator()) {
        $downloadPath = Join-Path $tempRoot ("meme-searcher-download-" + [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/$($item.Key)" -OutFile $downloadPath
            if ((Get-Sha256 $downloadPath) -ne $item.Value) { throw "Anonymous asset digest mismatch: $($item.Key)" }
        } finally {
            if (Test-Path -LiteralPath $downloadPath -PathType Leaf) { Remove-Item -LiteralPath $downloadPath -Force }
        }
    }
}
