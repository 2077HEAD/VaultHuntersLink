# Vault Hunters - mod cleanup and install check.
#
#   (no switch)  Set aside every mod Vault Hunters doesn't use: moved into _VH_disabled_mods in the
#                game folder, exactly where they were, nothing deleted. Then runs the check.
#   -Restore     Put everything from _VH_disabled_mods back. Files that exist again in the game
#                folder (e.g. reinstalled since) are left in the box rather than overwritten.
#   -Check       Only check that Vault Hunters and what it needs are installed.
#
# Works on any mod list: it keeps a short list of what Vault Hunters needs and sets aside the rest.
param([switch]$Restore, [switch]$Check)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$box  = Join-Path $root '_VH_disabled_mods'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

if (-not (Test-Path (Join-Path $root 'bin\x64\Cyberpunk2077.exe'))) {
    Say 'Put this file in your Cyberpunk 2077 folder (next to bin and r6) and run it from there.' Yellow; exit 1
}
if (-not $Check -and (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue)) {
    Say 'Close Cyberpunk 2077 first, then run this again.' Yellow; exit 1
}

# ---------------- what Vault Hunters keeps (everything else in these folders is set aside) ----------------
$keep = [ordered]@{
  'archive\pc\mod'                            = @('VaultHunters*', '#VaultHunters*', 'choomlink_puppet.archive')
  'mods'                                      = @('.stub')
  'r6\scripts'                                = @('VaultHunters', 'VaultHunterMovement', 'Cyberverse')
  'r6\tweaks'                                 = @('VaultHunters', 'VaultHuntersLink')
  'r6\input'                                  = @('VaultHunters.xml')
  'red4ext\plugins'                           = @('ArchiveXL', 'Codeware', 'TweakXL', 'Cyberverse', 'input_loader')
  'bin\x64\plugins'                           = @('cyber_engine_tweaks', 'cyber_engine_tweaks.asi', 'address_library')
  'bin\x64\plugins\cyber_engine_tweaks\mods'  = @('VaultHunters')
}

function Kept($dir, $name) {
    foreach ($pat in $keep[$dir]) { if ($name -like $pat) { return $true } }
    return $false
}

# ---------------- the check ----------------
function Test-Install {
    Say ''
    Say 'Vault Hunters install check' Cyan
    $bad = 0
    $need = @(
      @('RED4ext',               'red4ext\RED4ext.dll',                                   'https://www.nexusmods.com/cyberpunk2077/mods/2380'),
      @('redscript',             'engine\tools\scc.exe',                                  'https://www.nexusmods.com/cyberpunk2077/mods/1511'),
      @('Cyber Engine Tweaks',   'bin\x64\plugins\cyber_engine_tweaks.asi',               'https://www.nexusmods.com/cyberpunk2077/mods/107'),
      @('Codeware',              'red4ext\plugins\Codeware\Codeware.dll',                 'https://www.nexusmods.com/cyberpunk2077/mods/7780'),
      @('TweakXL',               'red4ext\plugins\TweakXL\TweakXL.dll',                   'https://www.nexusmods.com/cyberpunk2077/mods/4197'),
      @('ArchiveXL',             'red4ext\plugins\ArchiveXL\ArchiveXL.dll',               'https://www.nexusmods.com/cyberpunk2077/mods/4198'),
      @('Input Loader',          'red4ext\plugins\input_loader\input_loader.dll',         'https://www.nexusmods.com/cyberpunk2077/mods/5839'),
      @('Vault Hunters',         'r6\scripts\VaultHunters\Classes.reds',                  'unpack VaultHunters-Mod.zip into this folder'),
      @('Vault Hunters fonts',   'archive\pc\mod\VaultHuntersFonts.archive',              'unpack VaultHunters-Mod.zip into this folder'),
      @('Co-op plugin',          'red4ext\plugins\Cyberverse\Cyberverse.Red4Ext.dll',     'unpack VaultHuntersLink-Client.zip into this folder'),
      @('Co-op scripts',         'r6\scripts\Cyberverse\Cyberverse.reds',                 'unpack VaultHuntersLink-Client.zip into this folder')
    )
    foreach ($n in $need) {
        if (Test-Path (Join-Path $root $n[1])) { Say ("  OK       " + $n[0]) Green }
        else { Say ("  MISSING  " + $n[0] + "  ->  " + $n[2]) Red; $bad++ }
    }
    # The co-op plugin needs Microsoft's C++ runtime; without it the game stops with
    # "scripts contain invalid native definitions".
    $sys = Join-Path $env:WINDIR 'System32'
    if ((Test-Path (Join-Path $sys 'vcruntime140_1.dll')) -and (Test-Path (Join-Path $sys 'msvcp140.dll'))) {
        Say '  OK       Microsoft Visual C++ runtime' Green
    } else {
        Say '  MISSING  Microsoft Visual C++ runtime  ->  https://aka.ms/vs/17/release/vc_redist.x64.exe' Red; $bad++
    }
    $exe = Get-Item (Join-Path $root 'bin\x64\Cyberpunk2077.exe')
    Say ("  Game version: " + $exe.VersionInfo.ProductVersion + "  (Vault Hunters is made for 2.31)")
    # The newest RED4ext log says why a plugin didn't load.
    $logs = Join-Path $root 'red4ext\logs'
    if (Test-Path $logs) {
        $latest = Get-ChildItem $logs -Filter 'red4ext-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            $lines = Select-String -Path $latest.FullName -Pattern 'Cyberverse' -SimpleMatch | Select-Object -Last 4
            if ($lines) {
                Say ''
                Say ("  From the last RED4ext log (" + $latest.Name + "):")
                $lines | ForEach-Object { Say ("    " + $_.Line.Trim()) }
            }
        }
    }
    Say ''
    if ($bad -eq 0) { Say 'Everything Vault Hunters needs is installed.' Green }
    else { Say "$bad thing(s) missing - install them, then run this check again." Yellow }
}

if ($Check) { Test-Install; exit 0 }

# ---------------- restore ----------------
if ($Restore) {
    if (-not (Test-Path $box)) { Say 'Nothing to restore - no mods were set aside.'; exit 0 }
    $n = 0; $skipped = 0
    Get-ChildItem -LiteralPath $box -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($box.Length + 1)
        if ($rel -eq 'moved.txt') { return }
        $dst = Join-Path $root $rel
        if (Test-Path -LiteralPath $dst) { $skipped++; return }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Move-Item -LiteralPath $_.FullName -Destination $dst; $n++
    }
    if ($skipped -eq 0) {
        Remove-Item -LiteralPath $box -Recurse -Force
        Say "Put back $n files. Your mods are all active again." Green
    } else {
        Say "Put back $n files. $skipped were left in _VH_disabled_mods because a file with the same name is in the game folder again." Yellow
    }
    exit 0
}

# ---------------- set aside ----------------
$log = New-Object System.Collections.Generic.List[string]
foreach ($dir in $keep.Keys) {
    $src = Join-Path $root $dir
    if (-not (Test-Path -LiteralPath $src)) { continue }
    foreach ($item in @(Get-ChildItem -LiteralPath $src -Force)) {
        if (Kept $dir $item.Name) { continue }
        $dest = Join-Path (Join-Path $box $dir) $item.Name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        if ((Test-Path -LiteralPath $dest) -and -not $item.PSIsContainer) {
            Move-Item -LiteralPath $item.FullName -Destination $dest -Force   # newer copy wins
        } elseif (Test-Path -LiteralPath $dest) {
            # a folder set aside before under the same name: merge into it
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force | ForEach-Object {
                $d = Join-Path $dest $_.FullName.Substring($item.FullName.Length + 1)
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d) | Out-Null
                Move-Item -LiteralPath $_.FullName -Destination $d -Force
            }
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        } else {
            Move-Item -LiteralPath $item.FullName -Destination $dest
        }
        $log.Add("$dir\$($item.Name)")
    }
}
if ($log.Count) {
    Add-Content -LiteralPath (Join-Path $box 'moved.txt') -Value $log -Encoding UTF8
    Say "Set aside $($log.Count) mods into _VH_disabled_mods (list in moved.txt). Nothing was deleted." Green
    Say 'Run "VH Restore Disabled Mods.bat" any time to put them all back.'
} else { Say 'Nothing to set aside - only Vault Hunters is installed.' Green }
Test-Install
