# Vault Hunters Link

Small-party co-op (2–4 players) for the **Vault Hunters** Cyberpunk 2077 mod.

Vault Hunters Link is a fork of [ChoomLink](https://github.com/FOX-cOSMIC/choomlink-core), which is
itself a fork of [Cyberverse](https://github.com/TDUniverse/Cyberverse) by MeFisto94 / TDUniverse.
Both are MIT-licensed, and so is this fork (see `LICENSE`). Huge thanks to both projects: the hard
parts (remote player puppets, movement, aiming, shooting and damage sync) are theirs.

Nobody needs an account, an alpha key or anyone's permission to play: one friend runs the small
server program, everyone else connects to it.

## What Vault Hunters adds on top

* **Script events.** One general-purpose message (`PlayerScriptEvent` / `EntityScriptEvent`) that
  the server relays without understanding it. All Vault Hunters co-op rules are plain redscript in
  the Vault Hunters mod, so new co-op features don't need C++ or server changes.
* **Party roster.** The server tells everyone who is in the party and who the host is
  (`vh.session`). The first player in the world hosts; if they leave, the next one takes over.
* **Class avatars.** Players can tell the server which character record to show them as. Only
  records flagged `vhNetworkPuppet: true` are used (they need a stripped, AI-free template, see
  `client/assets/choomlink/README.md`); until those exist everyone appears as the default puppet.
* **Linux smoke test + Windows builds in GitHub Actions**, so releases don't depend on one PC.

The co-op gameplay itself lives in the Vault Hunters mod (`r6/scripts/VaultHunters/Coop/`):
class callouts, shared kill XP, location pings and **Bounties** — gang hit squads that every
party member fights together, with one shared health pool per enemy owned by the host.

## How co-op works ("parallel worlds, shared outcomes")

Everyone runs their own Night City. You see your friends (position, aim, weapons, shots, health),
and what you do together is shared: the party, bounties, kill XP, pings. Vanilla NPCs, traffic,
gigs and police are still each player's own — syncing those is a much larger project that no
Cyberpunk multiplayer mod has finished yet.

## Playing

Requirements (everyone): Cyberpunk 2077 **2.31**, RED4ext, redscript, Codeware, TweakXL, Cyber
Engine Tweaks, and the Vault Hunters mod.

1. Everyone: unpack `VaultHuntersLink-Client.zip` into the Cyberpunk 2077 folder.
2. Host: also unpack `VaultHuntersLink-Server.zip` there, then run **`Vault Hunters Co-op - Host.bat`**.
3. Friends: put the host's address in `vaulthunters-coop.txt`, then run
   **`Vault Hunters Co-op - Join.bat`**.

Easiest way to reach each other over the internet: all join the same free virtual LAN
([Tailscale](https://tailscale.com), ZeroTier or Radmin VPN) and use the host's address from that
app. Otherwise the host forwards UDP port 1337.

Launch through the .bat files, not through Steam/Epic — the store launchers drop the connect
arguments. A normal launch is plain single player.

## Building

GitHub Actions builds both zips on every push (`.github/workflows/vaulthunters.yml`); push a tag
like `v0.1.0` to publish them as a release. Local Windows builds: see `CLAUDE.md` / `tools/dist`.

The server and the bot harness also build on Linux; `tools/ci/coop-smoke-test.sh` runs the server
against three headless bots and checks roster, relay, sender stamping and avatar respawn.
