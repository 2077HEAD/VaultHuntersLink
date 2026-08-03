<#
Shared MSVC/CMake build helper, dot-sourced by the build-*.ps1 scripts.

All three native targets (client plugin, server native, bot harness) use the same
Ninja + vcpkg preset and the same MSVC environment, so the only thing that differs is
which directory gets built.
#>

function Get-VsDevCmd
{
    # Probe the known editions instead of hardcoding one path, so a machine with the full VS
    # install works as well as one with only the Build Tools.
    $vsRoots = @(
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
        'C:\Program Files\Microsoft Visual Studio\2022\Community',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise'
    )
    foreach ($root in $vsRoots) {
        $candidate = Join-Path $root 'Common7\Tools\VsDevCmd.bat'
        if (Test-Path $candidate) { return $candidate }
    }
    throw "VsDevCmd.bat not found. Install Visual Studio 2022 Build Tools with the C++ workload."
}

function Invoke-MsvcCMakeBuild
{
    param(
        [Parameter(Mandatory)] [string] $SourceDir,
        [Parameter(Mandatory)] [string] $BuildDir,
        [Parameter(Mandatory)] [string] $Label,
        [string] $ExpectedArtifact,
        [switch] $Clean
    )

    $vsDevCmd = Get-VsDevCmd

    if ($Clean -and (Test-Path $BuildDir)) {
        Write-Host "Cleaning $BuildDir"
        Remove-Item -Recurse -Force $BuildDir
    }

    # The configure preset resolves the vcpkg toolchain from $env:VCPKG_ROOT; fail loudly here
    # rather than letting CMake emit a confusing toolchain-file error.
    $needsConfigure = -not (Test-Path (Join-Path $BuildDir 'CMakeCache.txt'))
    if ($needsConfigure -and [string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
        throw "VCPKG_ROOT is not set, but a fresh configure of $Label needs it."
    }

    if ($needsConfigure) {
        $inner = "cmake --preset ninja-vcpkg -S `"$SourceDir`" && cmake --build `"$BuildDir`""
    } else {
        $inner = "cmake --build `"$BuildDir`""
    }

    # One cmd.exe invocation: the MSVC environment set by VsDevCmd only lives in that process.
    Write-Host "Building $Label..."
    & cmd.exe /c "call `"$vsDevCmd`" -arch=x64 -no_logo && $inner"
    if ($LASTEXITCODE -ne 0) {
        throw "$Label build failed (exit code $LASTEXITCODE)."
    }

    if ($ExpectedArtifact) {
        if (-not (Test-Path $ExpectedArtifact)) {
            throw "$Label build reported success but $ExpectedArtifact is missing."
        }
        Write-Host "OK: $ExpectedArtifact"
    }
}
