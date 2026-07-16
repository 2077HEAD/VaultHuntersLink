# AI-lobotomized remote-player puppet template

`puppet_base.ent` is an NPC entity template with perception / reactions / combat /
breach / crowd / ragdoll stripped out (101 → 65 components). The AI controller
(`AIHumanComponent`), `NPCStatesComponent` and the move trio are deliberately KEPT:
measured 2026-07-16, the AI controller is the engine's **only** teleport executor —
`TeleportationFacility.Teleport` silently no-ops on puppets, movement runs via
`AITeleportCommand` + `ForceTickNextFrame()` per interpolation frame (Phase 4b,
Iteration 2 — see spec `2026-07-14-ai-free-puppet-template-design.md`).

Spawn path (client): `recordID = t"Character.choomlink_puppet"` — a real Character
record (`choomlink.yaml`, TweakXL → `<game>\r6\tweaks\`) inheriting Character.Judy
with `entityTemplatePath` overridden to this template. Do NOT spawn via Codeware
`templatePath` (its synthetic SpawnableObject record breaks puppet teleports).
Packed into `../choomlink_puppet.archive` → deploy to `<game>\archive\pc\mod\`.

## Regenerating (reproducible — no opaque binary)

Source: base-game `base\characters\entities\main_npc\judy.ent` (v2.31).

1. Extract + serialize the vanilla template to JSON with WolvenKit.CLI:
   `WolvenKit.CLI.exe extract <base archive> --pattern judy.ent` then
   `WolvenKit.CLI.exe convert serialize judy.ent`
2. Strip the perception/reaction/combat components:
   `node strip-puppet-template.mjs` (edit the `SRC`/`OUT` paths inside first).
   The KEEP/STRIP rationale lives as comments in that script.
3. Bake back to `.ent`: `WolvenKit.CLI.exe convert deserialize puppet_base.ent.json`
   (WolvenKit treats the readable `components` array as authoritative and
   regenerates the `compiledData` RedPackage buffer, re-indexing all handles —
   so only the `components` array needs editing).
4. Pack: lay the `.ent` at `src\base\choomlink\puppet_base.ent`, then
   `WolvenKit.CLI.exe pack src -o .` and rename to `choomlink_puppet.archive`.

The strip list lives in `strip-puppet-template.mjs` (see the `STRIP` set).
