param([string]$Project = (Join-Path $PSScriptRoot '..'))

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($Project)
$manifest = Join-Path $projectRoot '.flutter-plugins-dependencies'

if (-not (Test-Path -LiteralPath $manifest)) {
    throw 'Run flutter pub get first to resolve plugin locations.'
}

$plugins = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$linkRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'windows/flutter/ephemeral/.plugin_symlinks'))

if (-not $linkRoot.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid project path.'
}

New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
foreach ($plugin in $plugins.plugins.windows) {
    if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Invalid plugin name.' }
    $link = Join-Path $linkRoot $plugin.name
    $target = [IO.Path]::GetFullPath($plugin.path)
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Plugin directory missing: $($plugin.name)" }
    if (-not (Test-Path -LiteralPath $link)) { New-Item -ItemType Junction -Path $link -Target $target | Out-Null }
}

Write-Output 'Windows plugin directories are ready.'
