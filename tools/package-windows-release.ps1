[CmdletBinding()]
param(
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode([string]$Action) {
    if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit code $LASTEXITCODE)." }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$exePath = Join-Path $releaseDir 'meme_searcher.exe'
$versionPath = Join-Path $repoRoot 'VERSION'
$distDir = Join-Path $repoRoot 'dist'

if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Release executable not found: $exePath. Run 'flutter build windows --release' first."
}

$repoVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($repoVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must be a numeric three-part version; found '$repoVersion'."
}

$fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
$fileVersion = $fileInfo.FileVersion
$productVersion = $fileInfo.ProductVersion
if ($fileVersion -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $productVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "PE file and product versions must both be numeric four-part versions. File='$fileVersion'; Product='$productVersion'."
}
if ($fileVersion -ne $productVersion) {
    throw "PE file and product versions differ. File='$fileVersion'; Product='$productVersion'."
}
if (-not $fileVersion.StartsWith("$repoVersion.")) {
    throw "PE version '$fileVersion' does not have VERSION '$repoVersion' as its prefix."
}

$archiveName = "meme-searcher-v$fileVersion-windows-x64.zip"
$archivePath = Join-Path $distDir $archiveName
$checksumPath = Join-Path $distDir 'SHA256SUMS.txt'
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempDir = Join-Path $tempRoot ("meme-searcher-package-" + [Guid]::NewGuid().ToString('N'))
$stageDir = Join-Path $tempDir 'package'
$tempArchive = Join-Path $tempDir $archiveName

try {
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

    # Flutter can leave test files in the output directory. CMake records the
    # runtime files it actually installed; the runner is built in place.
    $releasePrefix = [IO.Path]::GetFullPath($releaseDir) + [IO.Path]::DirectorySeparatorChar
    $manifest = Join-Path $repoRoot 'build/windows/x64/install_manifest.txt'
    $installed = Get-Content -LiteralPath $manifest | ForEach-Object { [IO.Path]::GetFullPath($_) } |
        Where-Object { $_.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase) }
    foreach ($source in (@($installed) + $exePath | Sort-Object -Unique)) {
        $relative = $source.Substring($releasePrefix.Length)
        $rootCopy = Join-Path $repoRoot $relative
        if ((Get-FileHash -LiteralPath $rootCopy).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
            throw "Project-root copy differs from the release build: $relative"
        }
        $destination = Join-Path $stageDir $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($required in @('flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stageDir $required) -PathType Leaf)) {
            throw "Missing $required in release manifest. Run 'flutter build windows --release' first."
        }
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $stageDir 'README.md') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination (Join-Path $stageDir 'THIRD_PARTY_NOTICES.md') -Force
    $readmeMedia = New-Item -ItemType Directory -Path (Join-Path $stageDir 'docs/media') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/guide.md') -Destination (Join-Path $stageDir 'docs/guide.md')
    foreach ($name in @('meme-drawer.jpg', 'home.png', 'search-results.png')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "docs/media/$name") -Destination $readmeMedia.FullName
    }

    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $tempArchive -CompressionLevel Optimal
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Move-Item -LiteralPath $tempArchive -Destination $archivePath

    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $checksumPath -Value "$hash *$archiveName" -Encoding Ascii
}
finally {
    if ((Test-Path -LiteralPath $tempDir) -and $tempDir.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

Write-Host "Created $archivePath"
Write-Host "Created $checksumPath"

if ($Publish) {
    $tag = "v$fileVersion"
    $head = & git -C $repoRoot rev-parse HEAD
    Assert-LastExitCode 'Reading HEAD'
    $tagCommit = & git -C $repoRoot rev-parse -q --verify "refs/tags/$tag^{commit}"
    Assert-LastExitCode "Verifying tag $tag"
    if ($tagCommit -ne $head) { throw "Tag $tag does not resolve to HEAD." }

    Push-Location -LiteralPath $repoRoot
    try {
        & gh release create $tag $archivePath $checksumPath --verify-tag --latest --notes-from-tag --title "Meme Snatcher $tag (Windows x64)"
        Assert-LastExitCode 'Publishing GitHub release'
    } finally {
        Pop-Location
    }
}
