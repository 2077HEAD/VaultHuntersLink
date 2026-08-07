# ChoomLink Core — Claude Code instructions

> **Kept byte-identical with `AGENTS.md` / `CLAUDE.md`.** Two tools read two filenames; there is no sync mechanism, so edit one and copy it over the other in the same commit.

Fork of [TDUniverse/Cyberverse](https://github.com/TDUniverse/Cyberverse) (MIT). Project home / planning docs: `..\choomlink` (see its `START_HERE.md` and `RESEARCH.md`).

## What this is

GTA-Online-style shared-world multiplayer for Cyberpunk 2077. Near-term target: **8 concurrent players**, first target experience: **PvP combat that works well** (locomotion → weapon → damage/health sync, upstream issues #6/#4/#5).

## Ground rules

- **Never read tiltedphoques/CyberpunkMP core source** — its license forbids studying it for a competing multiplayer product. Only its 3 MIT dirs are safe (details in `..\choomlink\RESEARCH.md`).
- **No game binaries/assets in the repo.** No paths into the game install committed.
- Generic fixes (build breaks, sync primitives) should be PR'd upstream to TDUniverse/Cyberverse where practical; divergent GTA-freeroam direction stays here.
- Verify community claims empirically before building on them.
- Issue tracking: **beans** (`beans list` / `beans create`), data lives in `..\choomlink`. Backlog follows the combat dependency chain.

## Architecture (upstream's 4 projects)

| Part | Tech | Path |
|---|---|---|
| Server.Native | C++ (GameNetworkingSockets) | `server\Native` |
| Server.Managed | C# (net9.0) — game logic, plugins | `server\Managed` |
| Client.RED4extModule | C++ RED4ext plugin | `client\red4ext` |
| Client.Redscript | redscript game-logic layer | `client\RedscriptModule` |
| Shared protocol | C++ headers (zpp_bits serialization) | `shared\protocol` |
| Bot harness, build/packaging scripts | C++ / PowerShell | `tools\bot-harness`, `tools\dist` |

A new packet touches **seven** places — the full checklist lives in `..\choomlink\CLAUDE.md`. Two of them fail late and confusingly when missed: the `EnqueueMessage` template instantiation list (unresolved external at link time) and the `.reds` native declaration (the game dies at startup with UNRESOLVED_METHOD).

## Building (Windows)

Use the scripts in `tools\dist` — they wrap the MSVC/vcpkg setup that CMake cannot bootstrap itself:

- `tools\dist\build-client.ps1` — the RED4ext plugin.
- `tools\dist\build-server.ps1` — Server.Native **and** Server.Managed, plus the step upstream lacks: copying the native DLLs next to the managed output. Without them the server does not start.
- `tools\dist\build-bot-harness.ps1` — the headless test client.
- `tools\dist\deploy-client.ps1` — builds, packages and installs into the game folder. It installs the *packaged* tree, so a gap in the release zip fails here rather than at a tester.
- `tools\dist\check-redscript.ps1` — type-checks the `.reds` against the game bundle in about a second, no game start.

Two traps worth knowing:

- **Running the server needs `$env:DOTNET_ROLL_FORWARD='LatestMajor'`** — it targets net9.0 and only runtimes 8 and 10 are installed.
- Server config is optional: `config.json` next to the managed output (`server\Managed\bin\Debug\net9.0\`). Absent, the defaults apply and the server says so on startup. It holds the interest-management radii and `combat.maxDamagePerHit`, the cap on the damage a client may claim for its own weapon.
- **Never wrap these scripts in `2>&1` from PowerShell 5.1.** VsDevCmd emits a harmless `vswhere.exe` line on stderr; the redirect turns it into an ErrorRecord and aborts the script although the compiler succeeded.

Underlying toolchain: CMake + Ninja + MSVC (VS 2022 Build Tools) + standalone vcpkg at `C:\Users\G4M3R\Programming\vcpkg` (`VCPKG_ROOT`). GNS comes from vcpkg (manifest mode; `builtin-baseline` added in our fork — candidate upstream PR).

Docker server image is reported broken upstream (#14/#22) — run the server bare via `dotnet run`.

## Game / client environment

- Steam install: `C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077`.
- **Pinned to game v2.31.** Upstream's README claims v2.1, but Cyberverse turned out to run on 2.31 unmodified — verified end-to-end, milestone `choomlink-esjd` closed. ChoomLink now follows FiveM's fixed-build strategy: a version bump is a deliberate project, never an implicit requirement. Do not let Steam update the game (Properties → Updates → "only when launched"; we launch the exe directly anyway).
- Client deps: RED4ext + redscript + Codeware (staged zips: `C:\Users\G4M3R\Programming\cp2077-mod-staging`).
- Toolchain/version record: `..\choomlink\docs\ENVIRONMENT.md`.
