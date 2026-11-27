[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+\.\d+\.\d+$')][string]$Tag,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$files = [ordered]@{
    'README.md' = 'docs/mcp-release.md'
    'THIRD_PARTY_NOTICES.md' = 'THIRD_PARTY_NOTICES.md'
    'tools/meme-snatcher-mcp.mjs' = 'tools/meme-snatcher-mcp.mjs'
}
$seedDirectory = 'assets/seed-assets'
$seedImages = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot $seedDirectory) -File -Attributes !ReparsePoint |
    Where-Object Extension -In '.gif', '.jpeg', '.jpg', '.png', '.webp' | Sort-Object Name)
if (!$seedImages.Count) { throw 'No bundled meme images found.' }
foreach ($image in $seedImages) {
    $path = "$seedDirectory/$($image.Name)"
    $files[$path] = $path
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$output = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
$archivePath = Join-Path $output "meme-searcher-$Tag-mcp.zip"
$temporary = Join-Path $output ('.meme-mcp-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entry in $files.GetEnumerator()) {
            $source = Join-Path $repoRoot $entry.Value
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, $entry.Key, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }

    $archive = [IO.Compression.ZipFile]::OpenRead($temporary)
    try {
        if ($archive.Entries.Count -ne $files.Count) { throw 'Unexpected MCP archive contents.' }
        foreach ($entry in $archive.Entries) {
            if (!$files.Contains($entry.FullName)) { throw "Unexpected MCP archive entry: $($entry.FullName)" }
            $source = Join-Path $repoRoot $files[$entry.FullName]
            $stream = $entry.Open()
            try {
                if ((Get-FileHash -InputStream $stream).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
                    throw "MCP archive entry differs from source: $($entry.FullName)"
                }
            } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }

    Move-Item -LiteralPath $temporary -Destination $archivePath -Force
    Write-Output $archivePath
} finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
}
