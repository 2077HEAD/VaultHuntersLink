<#
.SYNOPSIS
    Builds the headless bot / fake-client harness used for load and sync testing.

.PARAMETER Clean
    Configure from scratch.
#>
[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_msvc.ps1')

$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sourceDir = Join-Path $repoRoot 'tools\bot-harness'
$buildDir  = Join-Path $sourceDir 'build\ninja-vcpkg'

Invoke-MsvcCMakeBuild -SourceDir $sourceDir -BuildDir $buildDir -Label 'bot harness' `
    -ExpectedArtifact (Join-Path $buildDir 'bot-harness.exe') -Clean:$Clean
