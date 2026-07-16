// Builds the AI-lobotomized remote-player puppet template from a vanilla judy.ent JSON
// export (WolvenKit CLI serialize). Edit SRC/OUT, then:
//   node strip-puppet-template.mjs
//   WolvenKit.CLI.exe convert deserialize puppet_base.ent.json
// WolvenKit treats the readable `components` array as authoritative and regenerates the
// compiledData RedPackage buffer (all handles re-indexed) on deserialize.
import fs from 'fs';
const SRC = 'C:/wk/judy.ent.json', OUT = 'C:/wk/puppet_base.ent.json';
const j = JSON.parse(fs.readFileSync(SRC, 'utf8'));
const rc = j.Data.RootChunk;
// KEPT deliberately (measured 2026-07-16, see spec 2026-07-14-ai-free-puppet-template-design.md):
//  - AIHumanComponent: the AI controller is the engine's ONLY teleport executor
//    (TeleportationFacility.Teleport silently no-ops on puppets); movement runs via
//    AITeleportCommand + ForceTickNextFrame.
//  - NPCStatesComponent + move trio: puppet state machine / move executor.
// STRIPPED: perception, reactions, combat, breach, crowd — the AI-budget eaters — and
// entRagdollComponent (traffic hits would ragdoll the puppet permanently; without it the
// puppet stays upright and cars bounce off).
const STRIP = new Set([
  'AIObjectSelectionComponent','AISignalHandlerComponent','AITargetTrackerComponent',
  'ReactionManagerComponent','HitReactionComponent','StimBroadcasterComponent',
  'senseComponent','senseVisibleObjectComponent',
  'gameTargetingComponent','gameTargetShootComponent','gameSourceShootComponent','gameWeakspotComponent',
  'gameBreachComponent','gameBreachControllerComponent','gameDismembermentComponent',
  'SquadMemberBaseComponent','ScavengeComponent','CrowdMemberBaseComponent',
  'entRagdollComponent',
]);
const before = rc.components.length;
rc.components = rc.components.filter(c => {
  const t = c.$type;
  return !(STRIP.has(t) || (t && t.endsWith('PS') && STRIP.has(t.slice(0, -2))));
});
console.log('components', before, '->', rc.components.length);
fs.writeFileSync(OUT, JSON.stringify(j));
