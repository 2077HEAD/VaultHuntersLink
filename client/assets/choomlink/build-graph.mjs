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
        // Stufe 3 (2026-07-17): Weight fest 1 — unser Puppet braucht den Vanilla-Pfad nicht
        // (Plan-Fallback-Klausel: "falls kein Condition-Knoten praktikabel, Weight fest 1").
        // Stufe 2 testete bei Weight 0 (Nullprobe bestanden); ab hier läuft der Override live.
        value: 1,
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

// --- Stufe 3: 1D-Speed-Blend (Idle/Walk/Jog/Sprint) als Gate-Override -----------------
// Vorbild-Felder aus einem echten idle_stand-SkAnim-Knoten kopiert (applyMotion=0 — Root-
// Motion bleibt aus, Translation macht ausschließlich der kinematische Mover in C++).
function skAnimNode(clipName, loopEventName) {
    return {
        $type: 'animAnimNode_SkAnim',
        animation: { $type: 'CName', $storage: 'string', $value: clipName },
        animLoopEventName: { $type: 'CName', $storage: 'string', $value: loopEventName },
        applyInertializationOnAnimSetSwap: 1,
        applyMotion: 0,
        clipEnd: 0,
        clipEndByEvent: { $type: 'CName', $storage: 'string', $value: 'None' },
        clipFront: 0,
        clipFrontByEvent: { $type: 'CName', $storage: 'string', $value: 'None' },
        collectEvents: 1,
        convertToAdditive: 0,
        debug: 0,
        debugFootsteps: 0,
        debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_' + clipName },
        fireAnimLoopEvent: 1,
        id: 4294967295,
        isLooped: 1,
        motionProvider: null,
        popDataByTag: { $type: 'CName', $storage: 'string', $value: 'None' },
        poseInfoLogger: null,
        pushDataByTag: { $type: 'CName', $storage: 'string', $value: 'None' },
        pushSafeCutTag: { $type: 'CName', $storage: 'string', $value: 'None' },
        resume: 0,
        visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
        visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visPrePose: 0,
        visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
        visWhenActive: 0,
    };
}

const idleClip = { HandleId: String(nextId++), Data: skAnimNode('idle_stand', 'idle_end') };
const walkClip = { HandleId: String(nextId++), Data: skAnimNode('walk_0', 'None') };
const jogClip = { HandleId: String(nextId++), Data: skAnimNode('jog_0', 'None') };
const sprintClip = { HandleId: String(nextId++), Data: skAnimNode('sprint_0', 'None') };

// FloatInput liest choomlink_locomotion.speed — Mechanismus verifiziert (Anatomie-Doc):
// group = Feature-Name, name = Feature-Eigenschaft (Beispiel im Dump: group="crowd_locomotion",
// name="speed"). Kein Graph-Node "schreibt" das Feature — nur unser C++-Feed tut das.
const speedInputNode = {
    HandleId: String(nextId++),
    Data: {
        $type: 'animAnimNode_FloatInput',
        debugInput: 0,
        debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_speed' },
        group: { $type: 'CName', $storage: 'string', $value: 'choomlink_locomotion' },
        id: 4294967295,
        name: { $type: 'CName', $storage: 'string', $value: 'speed' },
        poseInfoLogger: null,
        visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
        visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visPrePose: 0,
        visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
        visWhenActive: 0,
    },
};

// BlendMultiple: 1D-Blend über inputValues als Tempo-Stützstellen (Plan-Schwellen 0/1.5/
// 3.5/6 m/s). Feldmuster von einer echten Vanilla-BlendMultiple-Instanz übernommen
// (inputNodes/inputValues/weightNode/minWeight/maxWeight/radialBlending, Task-2-Fund).
const speedBlendNode = {
    HandleId: String(nextId++),
    Data: {
        $type: 'animAnimNode_BlendMultiple',
        debug: 0,
        debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_speed_blend' },
        id: 4294967295,
        inputNodes: [
            { $type: 'animPoseLink', node: idleClip },
            { $type: 'animPoseLink', node: walkClip },
            { $type: 'animPoseLink', node: jogClip },
            { $type: 'animPoseLink', node: sprintClip },
        ],
        inputValues: [0, 1.5, 3.5, 6],
        maxWeight: 6,
        minWeight: 0,
        motionProvider: null,
        poseInfoLogger: null,
        radialBlending: 0,
        sortedInputValues: [0, 1.5, 3.5, 6],
        syncMethod: null,
        timeWarpingEnabled: 0,
        visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
        visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visPrePose: 0,
        visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
        visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
        visWhenActive: 0,
        weightNode: { $type: 'animFloatLink', node: speedInputNode },
    },
};

// Gate-Override zeigt jetzt auf den Speed-Blend statt auf den Switch-Platzhalter aus Stufe 2.
blendOverrideNode.Data.overrideInputNode = { $type: 'animPoseLink', node: speedBlendNode };

console.log('Speed-Blend eingebaut: BlendMultiple handle', speedBlendNode.HandleId,
    ', Clips (idle/walk/jog/sprint) handles', idleClip.HandleId, walkClip.HandleId, jogClip.HandleId, sprintClip.HandleId,
    ', FloatInput handle', speedInputNode.HandleId);

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
let blendCount = 0, clipCount = 0, floatInputCount = 0;
walk(rc2, (o) => {
    if (o.$type === 'animAnimNode_BlendMultiple' && o.debugName && o.debugName.$value === 'choomlink_speed_blend') blendCount++;
    if (o.$type === 'animAnimNode_SkAnim' && o.debugName && String(o.debugName.$value).startsWith('choomlink_')) clipCount++;
    if (o.$type === 'animAnimNode_FloatInput' && o.debugName && o.debugName.$value === 'choomlink_speed') floatInputCount++;
});
console.log('Rückgelesen: choomlink_speed_blend BlendMultiple-Knoten =', blendCount, ', choomlink_-Clip-Knoten =', clipCount, ', choomlink_speed FloatInput-Knoten =', floatInputCount);
