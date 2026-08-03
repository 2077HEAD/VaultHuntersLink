<#
.SYNOPSIS
    Assembles the ChoomLink client release zip (unpack-into-the-game-folder layout).

.DESCRIPTION
    Produces a staging tree whose paths mirror the Cyberpunk 2077 install folder, so the whole
    thing can be dragged in with one extraction -- the layout Nexus mods use and the one testers
    already know from RED4ext/Codeware.

    The DLL list is NOT hardcoded: everything CMake linked next to the plugin in the build tree is
    what the plugin needs at runtime, so we copy that set verbatim. A hardcoded list silently rots
    the moment a dependency is added, and the failure mode (missing DLL at game start) is exactly
    the broken-first-install we are trying to avoid.

.PARAMETER ServerAddress
    Baked into choomlink-server.txt so testers can just double-click the launcher. Still editable
    afterwards -- the launcher re-reads the file on every start.

.PARAMETER Version
    Release label used in the zip name and LIESMICH.txt. Defaults to a git describe of HEAD.

.PARAMETER SkipBuild
    Package whatever is already in the build tree instead of rebuilding first.
#>
[CmdletBinding()]
param(
    [string] $ServerAddress = '127.0.0.1',
    [int]    $ServerPort    = 1337,
    [string] $Version,
    [string] $OutDir,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildSrc  = Join-Path $repoRoot 'client\red4ext\build\ninja-vcpkg\src'
$redsSrc   = Join-Path $repoRoot 'client\RedscriptModule\src'
$archive   = Join-Path $repoRoot 'client\assets\choomlink_puppet.archive'
$templates = Join-Path $PSScriptRoot 'templates'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-client.ps1')
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    Push-Location $repoRoot
    try {
        $Version = (& git describe --tags --always --dirty).Trim()
    } finally {
        Pop-Location
    }
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = 'dev' }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot 'dist'
}

$stage = Join-Path $OutDir "stage-$Version"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }

$pluginDir  = Join-Path $stage 'red4ext\plugins\Cyberverse'
$scriptsDir = Join-Path $stage 'r6\scripts\Cyberverse'
$archiveDir = Join-Path $stage 'archive\pc\mod'
foreach ($d in @($pluginDir, $scriptsDir, $archiveDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# --- native plugin + its runtime dependencies ---------------------------------------------------
$dlls = @(Get-ChildItem -Path $buildSrc -Filter '*.dll' -File -ErrorAction SilentlyContinue)
if ($dlls.Count -eq 0) {
    throw "No DLLs in $buildSrc -- build the client first (build-client.ps1)."
}
if (-not ($dlls.Name -contains 'Cyberverse.Red4Ext.dll')) {
    throw "Cyberverse.Red4Ext.dll missing from $buildSrc."
}
$dlls | Copy-Item -Destination $pluginDir
Write-Host ("Plugin DLLs: {0}" -f ($dlls.Name -join ', '))

# --- redscript sources --------------------------------------------------------------------------
# Copied as a tree; the Network\ subfolder matters (module paths are folder-independent, but the
# deployed layout has always mirrored the source and keeping that makes log paths readable).
Copy-Item -Path (Join-Path $redsSrc '*') -Destination $scriptsDir -Recurse
$redsCount = (Get-ChildItem -Path $scriptsDir -Filter '*.reds' -Recurse -File).Count
if ($redsCount -eq 0) {
    throw "No .reds files staged from $redsSrc."
}
Write-Host "Redscript files: $redsCount"

# --- puppet archive -----------------------------------------------------------------------------
if (-not (Test-Path $archive)) {
    throw "Puppet archive missing: $archive"
}
Copy-Item -Path $archive -Destination $archiveDir

# --- launcher + config + readme -----------------------------------------------------------------
Copy-Item -Path (Join-Path $templates 'ChoomLink starten.bat') -Destination $stage

# Written BOM-less: PowerShell 5.1's -Encoding utf8 prepends a BOM, and cmd's `for /f` hands the
# BOM to the first token. Today it lands on a comment line that eol=# discards, but a tester who
# deletes the comments would get an unparseable address= line out of nowhere.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$cfg = Get-Content -Path (Join-Path $templates 'choomlink-server.txt') -Raw
$cfg = $cfg.Replace('@SERVER_ADDRESS@', $ServerAddress).Replace('@SERVER_PORT@', "$ServerPort")
[System.IO.File]::WriteAllText((Join-Path $stage 'choomlink-server.txt'), $cfg, $utf8NoBom)

$readme = Get-Content -Path (Join-Path $templates 'LIESMICH.txt') -Raw
$readme = $readme.Replace('@VERSION@', $Version)
[System.IO.File]::WriteAllText((Join-Path $stage 'LIESMICH.txt'), $readme, $utf8NoBom)

# --- zip ----------------------------------------------------------------------------------------
# Built entry by entry rather than with Compress-Archive: PowerShell 5.1 writes Windows-style
# backslashes into the entry names, which the zip format does not allow. Explorer copes, but some
# extractors then create single files literally named "red4ext\plugins\..." -- a first install that
# silently produces nothing. Forward slashes are the only portable form.
# ZipFile/ZipFileExtensions live in ...FileSystem, ZipArchiveMode in ...Compression -- both needed.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = Join-Path $OutDir "ChoomLink-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }

$stageFull = (Resolve-Path $stage).Path
$zipStream = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -Path $stageFull -Recurse -File) {
        $entryName = $file.FullName.Substring($stageFull.Length).TrimStart('\').Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zipStream, $file.FullName, $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zipStream.Dispose()
}

$sha = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
$sizeKb = [math]::Round((Get-Item $zip).Length / 1KB)

Write-Host ""
Write-Host "Package: $zip ($sizeKb KB)"
Write-Host "SHA256:  $sha"
Write-Host "Stage:   $stage"
