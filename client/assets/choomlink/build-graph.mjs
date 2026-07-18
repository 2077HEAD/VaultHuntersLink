// build-graph.mjs — einziger Edit-Einstiegspunkt für den ChoomLink-Locomotion-Zweig im
// geklonten humanoid.animgraph. Idempotent: liest IMMER die pristine Quelle neu (nie den
// zuletzt bearbeiteten Stand), damit jeder Lauf reproduzierbar vom selben Ausgangspunkt
// startet — Lehre aus Task 3 (ein Mass-Revert traf versehentlich nativ vorhandene Werte,
// weil vom bereits-editierten Stand aus gearbeitet wurde statt von der Quelle).
//
// Aufruf: node --max-old-space-size=8192 build-graph.mjs
// Liest:  C:/wk/pristine/humanoid.animgraph.json (Kopie der Vanilla-Quelle, siehe Setup unten)
// Schreibt: C:/wk/graph/puppet_locomotion.animgraph.json (Arbeitskopie für WolvenKit deserialize)
//
// Setup (einmalig, falls C:/wk/pristine fehlt):
//   mkdir -p C:/wk/pristine
//   cp "<wolvenkit-out>/base/gameplay/anim_graphs/humanoid.animgraph.json" C:/wk/pristine/
import fs from 'fs';

const PRISTINE = 'C:/wk/pristine/humanoid.animgraph.json';
const OUT = 'C:/wk/graph/puppet_locomotion.animgraph.json';

const j = JSON.parse(fs.readFileSync(PRISTINE, 'utf8'));
const rc = j.Data.RootChunk;

function walk(o, fn) {
    if (o && typeof o === 'object') {
        fn(o);
        for (const k of Object.keys(o)) {
            const v = o[k];
            if (v && typeof v === 'object') walk(v, fn);
        }
    }
}

// --- Stufe 2, Step 1: choomlink_locomotion Feature-Input deklarieren -----------------
// Klasse animAnimFeature_PlayerMovement (existierender Nativ-Typ, Felder speed/
// facingDirection/movementDirectionHorizontalAngle decken 1D+8-Wege ab — kein neuer
// RTTI-Typ nötig). Kein Spiel-System schreibt diesen Namen; der Schreiber sind wir.
rc.animFeatures.push({
    $type: 'animAnimFeatureEntry',
    className: { $type: 'CName', $storage: 'string', $value: 'animAnimFeature_PlayerMovement' },
    debugEnabled: 0,
    forceAllocate: 0,
    name: { $type: 'CName', $storage: 'string', $value: 'choomlink_locomotion' },
});
console.log('animFeatures: choomlink_locomotion appended, total =', rc.animFeatures.length);

// --- Stufe 2, Step 2: Passthrough-Gate vor dem Output --------------------------------
// Kette (Anatomie-Doc): Root -> nodes[0]=Output -> node=SkipPerformanceModeEnd ->
// inputLink=Switch (Haupt-Body-Pfad). Wir hängen ein animAnimNode_BlendOverride
// zwischen SkipPerformanceModeEnd und den bisherigen Switch: inputNode=Switch (Basis/
// Vanilla), overrideInputNode=derselbe Switch (Platzhalter bis Task 5), weightNode=
// FloatConstant(0) -> bei Weight 0 liefert BlendOverride exakt den Vanilla-Pfad
// (unverändertes Verhalten, Nullprobe).
let maxHandleId = -1;
walk(rc, (o) => {
    if (o.HandleId !== undefined) {
        const n = parseInt(o.HandleId, 10);
        if (!isNaN(n) && n > maxHandleId) maxHandleId = n;
    }
});
let nextId = maxHandleId + 1;

const root = rc.nodesToInit[0].Data; // animAnimNode_Root, volle Definition
const outputEntry = root.nodes[0]; // {HandleId, Data: animAnimNode_Output}
const skipEnd = outputEntry.Data.node.node; // {HandleId, Data: animAnimNode_SkipPerformanceModeEnd}
const existingLink = skipEnd.Data.inputLink.node; // {HandleId, Data: animAnimNode_Switch} — volle Def

const switchHandleId = existingLink.HandleId;
if (switchHandleId === undefined) {
    throw new Error('Erwarteter Switch-Knoten hat keine volle Definition (HandleId fehlt) — Anatomie hat sich geändert, Pfad prüfen.');
}

const floatConstId = String(nextId++);
const blendOverrideId = String(nextId++);

const floatConstNode = {
    HandleId: floatConstId,
    Data: {
        $type: 'animAnimNode_FloatConstant',
        debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_gate_weight' },
        id: 4294967295,
        poseInfoLogger: null,
        value: 0, // Weight 0 = Vanilla-Passthrough (Sicherheitszustand, Spec §Architektur)
        visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
        visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visPrePose: 0,
        visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
        visWhenActive: 0,
    },
};

const blendOverrideNode = {
    HandleId: blendOverrideId,
    Data: {
        $type: 'animAnimNode_BlendOverride',
        blendAllTracks: 1,
        blendMethod: {
            HandleId: String(nextId++),
            Data: { $type: 'animPoseBlendMethod_Mask', maskName: { $type: 'CName', $storage: 'string', $value: 'fullbody' } },
        },
        blendTrackMode: 'AGBT_Interpolate',
        bones: [],
        debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_locomotion_gate' },
        getDeltaMotionFromOverride: 0,
        id: 4294967295,
        // inputNode: erste (volle) Verwendung des bestehenden Switch-Knotens — Basis/Vanilla.
        inputNode: { $type: 'animPoseLink', node: existingLink },
        // overrideInputNode: Platzhalter bis Task 5 — Rückverweis auf DENSELBEN Switch (kein
        // zweiter voller Definitionsort für dasselbe Handle erlaubt).
        overrideInputNode: { $type: 'animPoseLink', node: { HandleRefId: switchHandleId } },
        poseInfoLogger: null,
        postProcess: null,
        syncMethod: null,
        timeWarpingEnabled: 0,
        tracks: [],
        visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
        visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visPrePose: 0,
        visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
        visWhenActive: 0,
        weightNode: { $type: 'animFloatLink', node: floatConstNode },
    },
};

// SkipPerformanceModeEnd.inputLink zeigt jetzt auf unser Gate statt direkt auf den Switch.
skipEnd.Data.inputLink = { $type: 'animPoseLink', node: blendOverrideNode };

console.log('Gate eingebaut: BlendOverride handle', blendOverrideId, ', FloatConstant handle', floatConstId, ', referenzierter Switch handle', switchHandleId);

fs.writeFileSync(OUT, JSON.stringify(j));
console.log('geschrieben nach', OUT);

// --- Verifikation: neu einlesen und Struktur bestätigen -------------------------------
const j2 = JSON.parse(fs.readFileSync(OUT, 'utf8'));
const rc2 = j2.Data.RootChunk;
const hasFeature = rc2.animFeatures.some((f) => f.name.$value === 'choomlink_locomotion' && f.className.$value === 'animAnimFeature_PlayerMovement');
console.log('Rückgelesen: choomlink_locomotion Feature vorhanden =', hasFeature);
let gateCount = 0;
walk(rc2, (o) => { if (o.$type === 'animAnimNode_BlendOverride' && o.debugName && o.debugName.$value === 'choomlink_locomotion_gate') gateCount++; });
console.log('Rückgelesen: choomlink_locomotion_gate BlendOverride-Knoten gefunden =', gateCount);
