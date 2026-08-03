<#
.SYNOPSIS
    Builds, packages and installs the ChoomLink client into a local Cyberpunk 2077 folder.

.DESCRIPTION
    The dev-loop counterpart to package-client.ps1: it installs exactly the tree that testers get,
    so a "works here, broken in the zip" split cannot happen -- the zip layout is the only layout.

    An existing choomlink-server.txt is left alone, so a locally configured server address survives
    redeploys.

.PARAMETER GamePath
    Cyberpunk 2077 install folder. Defaults to the Steam default location.
#>
[CmdletBinding()]
param(
    [string] $GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [string] $ServerAddress = '127.0.0.1',
    [int]    $ServerPort    = 1337,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $GamePath 'bin\x64\Cyberpunk2077.exe'))) {
    throw "No Cyberpunk2077.exe under $GamePath -- pass -GamePath."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outDir   = Join-Path $repoRoot 'dist'

$packageArgs = @{
    ServerAddress = $ServerAddress
    ServerPort    = $ServerPort
    Version       = 'local'
    OutDir        = $outDir
}
if ($SkipBuild) { $packageArgs['SkipBuild'] = $true }
& (Join-Path $PSScriptRoot 'package-client.ps1') @packageArgs

$stage = Join-Path $outDir 'stage-local'

# Wipe the plugin and script folders before copying: a renamed or removed .reds file left behind in
# the game folder still gets compiled by redscript and can break the whole compilation unit.
foreach ($rel in @('red4ext\plugins\Cyberverse', 'r6\scripts\Cyberverse')) {
    $target = Join-Path $GamePath $rel
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
}

foreach ($rel in @('red4ext\plugins\Cyberverse', 'r6\scripts\Cyberverse', 'archive\pc\mod')) {
    $src = Join-Path $stage $rel
    $dst = Join-Path $GamePath $rel
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
}

Copy-Item -Path (Join-Path $stage 'ChoomLink starten.bat') -Destination $GamePath -Force

$cfgTarget = Join-Path $GamePath 'choomlink-server.txt'
if (Test-Path $cfgTarget) {
    Write-Host "Kept existing choomlink-server.txt"
} else {
    Copy-Item -Path (Join-Path $stage 'choomlink-server.txt') -Destination $cfgTarget
}

Write-Host "Deployed to $GamePath"
