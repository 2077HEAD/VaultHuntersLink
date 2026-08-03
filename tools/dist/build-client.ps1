<#
.SYNOPSIS
    Builds the ChoomLink client native plugin (Cyberverse.Red4Ext.dll + its runtime DLLs).

.DESCRIPTION
    Replaces the ad-hoc scratch batch file that used to live outside the repo. The build needs
    the MSVC environment, which CMake/Ninja cannot bootstrap themselves — so we source
    VsDevCmd.bat and re-run cmake inside that environment.

    The configure step is only run when the build directory does not exist yet; a normal
    incremental build skips straight to `cmake --build`.

.PARAMETER Clean
    Delete the build directory first and configure from scratch.
#>
[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sourceDir  = Join-Path $repoRoot 'client\red4ext'
$buildDir   = Join-Path $sourceDir 'build\ninja-vcpkg'

# VsDevCmd lives in a version-specific path; probe the known editions rather than hardcoding one,
# so a machine with the full VS install (not just Build Tools) works too.
$vsDevCmd = $null
$vsRoots = @(
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
    'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
    'C:\Program Files\Microsoft Visual Studio\2022\Community',
    'C:\Program Files\Microsoft Visual Studio\2022\Professional',
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise'
)
foreach ($root in $vsRoots) {
    $candidate = Join-Path $root 'Common7\Tools\VsDevCmd.bat'
    if (Test-Path $candidate) {
        $vsDevCmd = $candidate
        break
    }
}
if ($null -eq $vsDevCmd) {
    throw "VsDevCmd.bat not found. Install Visual Studio 2022 Build Tools with the C++ workload."
}

if ($Clean -and (Test-Path $buildDir)) {
    Write-Host "Cleaning $buildDir"
    Remove-Item -Recurse -Force $buildDir
}

# The configure preset resolves the vcpkg toolchain from $env:VCPKG_ROOT; fail loudly here rather
# than letting CMake emit a confusing toolchain-file error.
$needsConfigure = -not (Test-Path (Join-Path $buildDir 'CMakeCache.txt'))
if ($needsConfigure -and [string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    throw "VCPKG_ROOT is not set, but a fresh configure needs it (CMakePresets.json toolchain file)."
}

# One cmd.exe invocation: the MSVC environment set by VsDevCmd only lives inside that process.
if ($needsConfigure) {
    $inner = "cmake --preset ninja-vcpkg -S `"$sourceDir`" && cmake --build `"$buildDir`""
} else {
    $inner = "cmake --build `"$buildDir`""
}

Write-Host "Building client plugin..."
& cmd.exe /c "call `"$vsDevCmd`" -arch=x64 -no_logo && $inner"
if ($LASTEXITCODE -ne 0) {
    throw "Client build failed (exit code $LASTEXITCODE)."
}

$pluginDll = Join-Path $buildDir 'src\Cyberverse.Red4Ext.dll'
if (-not (Test-Path $pluginDll)) {
    throw "Build reported success but $pluginDll is missing."
}
Write-Host "OK: $pluginDll"
