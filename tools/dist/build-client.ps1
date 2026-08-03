<#
.SYNOPSIS
    Builds the ChoomLink client native plugin (Cyberverse.Red4Ext.dll + its runtime DLLs).

.PARAMETER Clean
    Delete the build directory first and configure from scratch.
#>
[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_msvc.ps1')

$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sourceDir = Join-Path $repoRoot 'client\red4ext'
$buildDir  = Join-Path $sourceDir 'build\ninja-vcpkg'

Invoke-MsvcCMakeBuild -SourceDir $sourceDir -BuildDir $buildDir -Label 'client plugin' `
    -ExpectedArtifact (Join-Path $buildDir 'src\Cyberverse.Red4Ext.dll') -Clean:$Clean
