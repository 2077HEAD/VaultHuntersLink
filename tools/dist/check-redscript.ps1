<#
.SYNOPSIS
    Type-checks the ChoomLink redscript sources without starting the game.

.DESCRIPTION
    A redscript error normally only surfaces when the game boots -- and it does not surface
    gently: the game dies at startup and you have to read r6\logs\redscript_rCURRENT.log to find
    out why. That is a multi-minute round trip for a typo.

    redscript-cli compiles the same sources against the game's own bundle, so most of those
    errors can be found in about a second instead.

    WHAT THIS CATCHES: unknown types, wrong method names, wrong argument types and counts against
    vanilla and Codeware, syntax errors, missing returns, invalid literals.

    WHAT IT CANNOT CATCH: a `native` declaration whose C++ counterpart is missing. Natives are
    registered into RTTI by the RED4ext plugin at runtime, so nothing in the bundle can confirm
    them at this point -- that is exactly the UNRESOLVED_METHOD failure that kills the game at
    startup. For those, the RTTI_METHOD line in the C++ header is still the thing to check by eye.

.PARAMETER GamePath
    Needed for the vanilla bundle and for Codeware's scripts.
#>
[CmdletBinding()]
param(
    [string] $GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [string] $RedscriptCli = 'C:\Users\G4M3R\Tools\redscript-cli\redscript-cli.exe'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$srcDir   = Join-Path $repoRoot 'client\RedscriptModule\src'
$bundle   = Join-Path $GamePath 'r6\cache\final.redscripts'
$codeware = Join-Path $GamePath 'red4ext\plugins\Codeware\Scripts'

foreach ($required in @($RedscriptCli, $srcDir, $bundle)) {
    if (-not (Test-Path $required)) {
        throw "Not found: $required"
    }
}

# final.redscripts is the untouched vanilla bundle. Deliberately NOT final.redscripts.modded:
# that one already contains a previous compilation of our own sources, which would let a stale
# definition satisfy a reference that the real (clean) startup compile would reject.
$args = @('compile', '-s', $srcDir)
if (Test-Path $codeware) {
    $args += @('-s', $codeware)
} else {
    Write-Warning "Codeware scripts not found at $codeware -- imports of Codeware.* will fail."
}
$outFile = Join-Path ([System.IO.Path]::GetTempPath()) 'choomlink-redscript-check.redscripts'
$args += @('-b', $bundle, '-o', $outFile)

$output = & $RedscriptCli @args | Out-String -Stream
$exit = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }

if (Test-Path $outFile) { Remove-Item -Force $outFile }

# $exit alone is not proof of success (found 2026-08-09): redscript-cli's `compile` prints
# `ERROR [...] Build failed` for genuine compile errors -- unresolved methods, type mismatches --
# while still exiting 0. A script that reports success is not evidence (this machine's own
# standing rule) -- grep the actual diagnostic text instead of trusting the exit code alone.
$hasErrorLine = $output | Select-String -Pattern '^ERROR ' -Quiet
if ($exit -ne 0 -or $hasErrorLine) {
    throw "Redscript check failed (exit code $exit, error lines present: $hasErrorLine)."
}
Write-Host "Redscript OK"
