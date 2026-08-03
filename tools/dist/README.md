# tools/dist — client build, packaging and deployment

Three PowerShell scripts, layered. Each one is usable on its own; the later ones call the
earlier ones.

| Script | Does |
|---|---|
| `build-client.ps1` | Builds `Cyberverse.Red4Ext.dll` via VsDevCmd + CMake/Ninja |
| `build-server.ps1` | Builds Server.Native **and** Server.Managed, and copies the native DLLs next to the managed output |
| `build-bot-harness.ps1` | Builds `bot-harness.exe` |
| `check-redscript.ps1` | Type-checks the `.reds` sources against the game bundle, no game start |
| `package-client.ps1` | Assembles the release zip in game-folder layout |
| `deploy-client.ps1` | Type-checks, then installs that same layout into a local game folder |

`_msvc.ps1` holds the shared VsDevCmd discovery and CMake invocation; the three build
scripts differ only in which directory they build.

All four components (client plugin, server native, server managed, bot harness) are
therefore buildable with no scratch files outside the repo.

## Why the zip layout is also the dev layout

`deploy-client.ps1` installs the *packaged* tree rather than copying from the source tree
directly. That removes a whole class of release bug: if the zip is missing a file, the dev
machine notices immediately, because the dev machine runs the zip's contents.

## Typical use

Dev loop (build + install into the local game folder):

```powershell
.\tools\dist\deploy-client.ps1
```

Release build for testers:

```powershell
.\tools\dist\package-client.ps1 -ServerAddress 100.64.12.34 -Version v0.2.0
```

Output lands in `dist\` (gitignored) together with the SHA256 to publish alongside the
GitHub release. Attach `docs/INSTALL.md` as the release description or link to it.

## The redscript pre-check

`deploy-client.ps1` type-checks the scripts before they reach the game folder, because the
alternative feedback loop is: launch the game, wait, watch it die at startup, read
`r6\logs\redscript_rCURRENT.log`. The check takes about a second and found two real errors
the first time it ran.

It compiles against `final.redscripts` — the untouched vanilla bundle — deliberately **not**
`final.redscripts.modded`, which already contains a previous compile of our own sources and
would let a stale definition satisfy a reference the real startup compile rejects.

**It cannot catch a `native` declaration whose C++ side is missing.** Natives are registered
into RTTI by the RED4ext plugin at runtime, so no bundle can confirm them here — and that is
exactly the `UNRESOLVED_METHOD` failure that kills the game at startup. Adding a native still
means checking the `RTTI_METHOD` line in the header by eye.

## Notes

- The plugin's runtime DLLs are **not** listed anywhere. Whatever CMake places next to
  `Cyberverse.Red4Ext.dll` in the build tree is what gets packaged, so adding a dependency
  needs no change here.
- Zip entries are written with forward slashes explicitly. `Compress-Archive` on
  PowerShell 5.1 writes backslashes, which some extractors turn into files literally named
  `red4ext\plugins\...` — an install that appears to succeed and does nothing.
- `ChoomLink starten.bat` supports `CHOOMLINK_DRYRUN=1`: it prints the parsed
  address/port and exits instead of launching the game, so the launcher can be tested
  without a game install.

- VsDevCmd prints `'vswhere.exe' is not recognized` on this machine. Harmless, it still sets
  up the toolchain. Do **not** wrap these scripts in `2>&1` from PowerShell 5.1: that turns
  every stderr line from a native command into an ErrorRecord and aborts the build under
  `$ErrorActionPreference = 'Stop'`, even though the compiler succeeded.

## Not covered yet

- Server *packaging* (a zip for someone else to host) — `build-server.ps1` only produces a
  locally runnable folder.
- No one-click installer; see choomlink-xrpn for the follow-up idea.
