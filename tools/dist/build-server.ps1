<#
.SYNOPSIS
    Builds both halves of the ChoomLink server and puts them in one runnable folder.

.DESCRIPTION
    Server.Native (C++, wire serialization) and Server.Managed (.NET, game logic) are separate
    projects with no copy step between them upstream -- the managed output simply will not start
    without the native DLLs sitting next to it. That copy is the whole point of this script.

    Server.Managed targets net9.0 while this machine has runtimes 8 and 10, hence the
    DOTNET_ROLL_FORWARD hint printed at the end.

.PARAMETER Clean
    Configure the native build from scratch.
#>
[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_msvc.ps1')

$repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nativeSource = Join-Path $repoRoot 'server\Native'
$nativeBuild  = Join-Path $nativeSource 'build\ninja-vcpkg'
$managedDir   = Join-Path $repoRoot 'server\Managed'

Invoke-MsvcCMakeBuild -SourceDir $nativeSource -BuildDir $nativeBuild -Label 'server native' `
    -ExpectedArtifact (Join-Path $nativeBuild 'src\Cyberverse.Server.Native.dll') -Clean:$Clean

Write-Host "Building server managed..."
& dotnet build $managedDir -v m
if ($LASTEXITCODE -ne 0) {
    throw "Server.Managed build failed (exit code $LASTEXITCODE)."
}

$managedOut = Join-Path $managedDir 'bin\Debug\net9.0'
if (-not (Test-Path $managedOut)) {
    throw "Managed output folder not found: $managedOut"
}

$nativeDlls = @(Get-ChildItem -Path (Join-Path $nativeBuild 'src') -Filter '*.dll' -File)
if ($nativeDlls.Count -eq 0) {
    throw "No native DLLs in $nativeBuild\src."
}
$nativeDlls | Copy-Item -Destination $managedOut -Force
Write-Host ("Copied native DLLs: {0}" -f ($nativeDlls.Name -join ', '))

Write-Host ""
Write-Host "Run with:  `$env:DOTNET_ROLL_FORWARD='LatestMajor'; dotnet run --project `"$managedDir`""
