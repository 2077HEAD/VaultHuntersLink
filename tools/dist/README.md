# tools/dist — client build, packaging and deployment

Three PowerShell scripts, layered. Each one is usable on its own; the later ones call the
earlier ones.

| Script | Does |
|---|---|
| `build-client.ps1` | Builds `Cyberverse.Red4Ext.dll` via VsDevCmd + CMake/Ninja |
| `package-client.ps1` | Assembles the release zip in game-folder layout |
| `deploy-client.ps1` | Installs that same layout into a local game folder |

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

## Not covered yet

- Server packaging (`server/Managed` + `server/Native` DLLs) is still manual.
- No one-click installer; see choomlink-xrpn for the follow-up idea.
