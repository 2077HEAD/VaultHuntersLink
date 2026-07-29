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

// FloatInput-Fabrik: group = Feature-Name, name = Feature-Eigenschaft (Mechanismus
// verifiziert, Anatomie-Doc — Beispiel im Dump: group="crowd_locomotion", name="speed").
// Kein Graph-Node "schreibt" ein Feature — nur unser C++-Feed tut das.
function floatInputNode(propName, debugSuffix) {
    return {
        HandleId: String(nextId++),
        Data: {
            $type: 'animAnimNode_FloatInput',
            debugInput: 0,
            debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_' + debugSuffix },
            group: { $type: 'CName', $storage: 'string', $value: 'choomlink_locomotion' },
            id: 4294967295,
            name: { $type: 'CName', $storage: 'string', $value: propName },
            poseInfoLogger: null,
            visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
            visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
            visPrePose: 0,
            visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
            visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
            visWhenActive: 0,
        },
    };
}

const speedInputNode = floatInputNode('speed', 'speed');

// --- Stufe 4: Richtungs-Dimension (2026-07-18, korrigiert 2026-07-27) ------------------
// Erste Fassung erzeugte am Ort ±90° eine Bind-Pose (Beine kerzengerade, Arme waagerecht
// abgespreizt) — in-game am 2026-07-27 belegt, während Richtung 0° einen sauberen
// Gehzyklus lieferte. Ursachenanalyse gegen die Vanilla-Richtungs-Blends (Skript
// scratchpad/dirdetail.mjs, Abfrage über den gebauten Graphen) ergab fünf Abweichungen:
//   1. walk_180 / jog_180 haben KEINEN einzigen Vanilla-SkAnim-Knoten — es gibt im
//      NPC-Clip-Satz gar keinen Backpedal-Zyklus. Ein nicht auflösbarer Clip im Blend
//      erklärt die Bind-Pose. (walk_090/walk_270 aus dem Anatomie-Doc existieren
//      ebenfalls nicht als Clips — das waren Strings, keine spielbaren Animationen.)
//   2. min/maxWeight muss dem tatsächlichen Winkelbereich der Clips entsprechen
//      (Vanilla: walk ±90, jog/sprint ±45) — nicht pauschal ±180.
//   3. radialBlending ist bei allen drei Vanilla-Blends 0, nicht 1.
//   4. timeWarpingEnabled=1 hält die Clips im Blend auf gleicher Schrittphase.
//   5. syncMethod=animSyncMethodByProgress (walk/jog) synchronisiert den Fortschritt.
// Folge für den Umfang: echte Seitwärts-Zyklen (±90°) gibt es NUR im Walk-Tempo. Jog und
// Sprint besitzen lediglich ±45°-Varianten (Lean, kein Strafe), Rückwärts gar nicht —
// jenseits des Bereichs klemmt der Blend auf den äußersten Clip, wie bei Vanilla.
// Konvention (Vorzeichen noch zu kalibrieren): left=negativ, right=positiv.
// rangeOverride=180 heißt: der Blend deckt den vollen Kreis ab (Rückwärts ist dabei) —
// dann MUSS radialBlending=1 sein, damit -180 und +180 als derselbe Punkt gelten und der
// Übergang Rückwärts→Seitwärts nicht quer durch alle Zwischenclips läuft. Reicht der Blend
// nur bis ±90 (kein Rückwärts-Clip), ist der lineare Vanilla-Fall mit radialBlending=0
// richtig.
function directionBlendNode(tierDebugName, clipsByAngle, useSyncMethod = true, rangeOverride = null) {
    const dirInput = floatInputNode('movementDirectionHorizontalAngle', tierDebugName + '_dir');
    const sorted = [...clipsByAngle].sort((a, b) => a.angle - b.angle);
    const clipNodes = sorted.map((c) => ({ HandleId: String(nextId++), Data: skAnimNode(c.clip, 'None') }));
    const range = rangeOverride ?? Math.max(...sorted.map((c) => Math.abs(c.angle)));
    const fullCircle = range >= 180;
    const blend = {
        HandleId: String(nextId++),
        Data: {
            $type: 'animAnimNode_BlendMultiple',
            debug: 0,
            debugName: { $type: 'CName', $storage: 'string', $value: 'choomlink_' + tierDebugName + '_dir_blend' },
            id: 4294967295,
            inputNodes: clipNodes.map((n) => ({ $type: 'animPoseLink', node: n })),
            inputValues: sorted.map((c) => c.angle),
            maxWeight: range,
            minWeight: -range,
            motionProvider: null,
            poseInfoLogger: null,
            radialBlending: fullCircle ? 1 : 0,
            sortedInputValues: sorted.map((c) => c.angle),
            syncMethod: useSyncMethod
                ? { HandleId: String(nextId++), Data: { $type: 'animSyncMethodByProgress' } }
                : null,
            timeWarpingEnabled: 1,
            visAxes: 0, visMask: null, visNames: 0, visPostPose: 0,
            visPostPoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
            visPrePose: 0,
            visPrePoseColor: { $type: 'Color', Alpha: 0, Blue: 0, Green: 0, Red: 0 },
            visRigPartMask: { $type: 'CName', $storage: 'string', $value: 'None' },
            visWhenActive: 0,
            weightNode: { $type: 'animFloatLink', node: dirInput },
        },
    };
    return blend;
}

// Clip-Namen NICHT mehr aus dem Graphen geraten, sondern aus den tatsächlichen
// .anims-Sets belegt (2026-07-27, Skript scratchpad/animnames.mjs über die mit
// WolvenKit extrahierten Sets). Befund:
//   wa_gang_unarmed_locomotion_combat  : walk_0, walk_090, walk_180, walk_270 (+Übergänge)
//   wa_gang_unarmed_locomotion_relaxed : walk_0, walk_180, sprint_0 (KEINE Seitwärts-Clips)
//   generic_average_female_locomotion  : walk_0, walk_180, sprint_0
//   wa_judy_unarmed_locomotion_relaxed : walk_0, walk_180
//   ...searching / ...stealth / exploration_relaxed / judy_handgun_combat: kein Seitwärts
// Zwei Konsequenzen, beide in-game am 2026-07-27 belegt:
//   * walk_left/walk_right/jog_left/jog_right/sprint_left/sprint_right existieren in
//     KEINEM Set — genau darum lieferte Richtung ±90° eine Bind-Pose. Die echten
//     Richtungsnamen sind walk_090 / walk_180 / walk_270 (Anatomie-Doc hatte recht).
//   * jog_* kommt in keinem der geprüften Sets vor. Die Jog-Stufe bekommt deshalb
//     keinen Richtungs-Blend mehr, sondern bleibt ein einzelner Clip — genauso Sprint,
//     wo nur sprint_0 belegt ist.
// Damit hat ausschließlich die Walk-Stufe echte Richtungsabdeckung — dafür aber alle
// vier Himmelsrichtungen, Rückwärtslaufen eingeschlossen.
// In-Game-Befund 2026-07-28 (nachdem die Jog-Stufe als Störgröße ausgeschlossen war):
// walk_0 und walk_180 spielen sauber (Schrittstellung, Armschwung), walk_090/walk_270
// weiterhin Bind-Pose. Beide Seitwärts-Clips liegen ausschließlich in
// wa_gang_unarmed_locomotion_combat.anims — dieses Set lädt unsere friedliche Puppet-Entity
// offenbar nicht. Solange das so ist, dürfen die beiden Clips NICHT im Blend hängen: bei
// jeder Richtungsumkehr interpoliert der Radial-Blend von 0° nach 180° durch ±90° und
// blitzt dabei sichtbar die Bind-Pose auf (im Backpedal-Burst als kurzes T-Pose-Zucken an
// den Umkehrpunkten belegt). Flag auf true stellen, sobald das Combat-Set über die
// Animation-Setup-Seite der Entity geladen wird — dann ist der volle 4-Wege-Blend da.
const LATERAL_CLIPS_AVAILABLE = false;
const walkClip = LATERAL_CLIPS_AVAILABLE
    ? directionBlendNode('walk', [
          { clip: 'walk_270', angle: -90 }, { clip: 'walk_0', angle: 0 },
          { clip: 'walk_090', angle: 90 }, { clip: 'walk_180', angle: 180 },
      ], true, 180)
    : directionBlendNode('walk', [
          { clip: 'walk_0', angle: 0 }, { clip: 'walk_180', angle: 180 },
      ], true, 180);
// Jog-Stufe spielt walk_0 statt jog_0 — BESTÄTIGT durch Gegentest 2026-07-28: im
// Backpedal-Burst trat die Bind-Pose zweimal pro Schwingung auf, also einmal pro Halbwelle
// bei Höchsttempo (~2,2 m/s) und richtungsunabhängig. Bei 2,2 m/s mischt der Speed-Blend
// 67 % walk + 33 % jog; jog_* kommt in keinem der acht geprüften .anims-Sets vor. Nach dem
// Umhängen auf walk_0 zeigten dieselben Frames einen sauberen Gehzyklus. Es gibt für diese
// Figur schlicht keine Jog-Clips — bis eines gefunden ist, ist walk_0 die ehrlichste
// Belegung (lieber ein zu langsamer Zyklus als eine Bind-Pose).
const jogClip = { HandleId: String(nextId++), Data: skAnimNode('walk_0', 'None') };
const sprintClip = { HandleId: String(nextId++), Data: skAnimNode('sprint_0', 'None') };

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
let blendCount = 0, clipCount = 0, floatInputCount = 0, dirBlendCount = 0, dirFloatInputCount = 0;
walk(rc2, (o) => {
    if (o.$type === 'animAnimNode_BlendMultiple' && o.debugName && o.debugName.$value === 'choomlink_speed_blend') blendCount++;
    if (o.$type === 'animAnimNode_SkAnim' && o.debugName && String(o.debugName.$value).startsWith('choomlink_')) clipCount++;
    if (o.$type === 'animAnimNode_FloatInput' && o.debugName && o.debugName.$value === 'choomlink_speed') floatInputCount++;
    if (o.$type === 'animAnimNode_BlendMultiple' && o.debugName && /_dir_blend$/.test(String(o.debugName.$value))) dirBlendCount++;
    if (o.$type === 'animAnimNode_FloatInput' && o.debugName && /_dir$/.test(String(o.debugName.$value))) dirFloatInputCount++;
});
console.log('Rückgelesen: choomlink_speed_blend BlendMultiple-Knoten =', blendCount, ', choomlink_-Clip-Knoten =', clipCount, ', choomlink_speed FloatInput-Knoten =', floatInputCount);
// Nur noch die Walk-Stufe hat einen Richtungs-Blend (Jog/Sprint besitzen im Clip-Satz
// keine Richtungsvarianten) → 1 Blend, 1 Richtungs-FloatInput, 7 Clip-Knoten
// (idle + walk_270/0/090/180 + jog_0 + sprint_0).
console.log('Rückgelesen: Richtungs-Blend-Knoten (nur walk) =', dirBlendCount, '(erwartet 1), Richtungs-FloatInput-Knoten =', dirFloatInputCount, '(erwartet 1)');

// --- Lint: Clip-Existenz + Regressions-Diff (2026-07-29, choomlink-i2ic) --------------
// Auslöser: Commit 0444fbf entfernte versehentlich walk_180 aufgrund einer falschen
// Annahme ("kein Backpedal-Zyklus existiert") — der Fehler wurde erst einen ganzen
// In-Game-Verifikationszyklus später bemerkt (b5bce07/27c1f8f). Diese zwei Prüfungen
// laufen bei JEDEM Build automatisch, ohne das Spiel zu brauchen:
//   1. Existenz — jeder von uns verdrahtete Clip-Name muss im clip-index.json
//      (siehe clip-index.mjs) tatsächlich vorkommen. Ein nicht auflösbarer Clip
//      rendert lautlos eine Bind-Pose; das hier ist ein harter Fehler (Exit 1).
//   2. Regression — die Menge unserer Clip-Referenzen wird gegen den letzten
//      committeten Snapshot (graph-clip-baseline.json) verglichen. Änderungen
//      werden laut ausgegeben (kein harter Fehler — Entfernen/Hinzufügen kann
//      beabsichtigt sein, z. B. das LATERAL_CLIPS_AVAILABLE-Flag), aber niemand
//      soll eine Änderung mehr übersehen wie bei walk_180.
const CLIP_INDEX_FILE = new URL('clip-index.json', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const BASELINE_FILE = new URL('graph-clip-baseline.json', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

const referencedClips = new Map(); // clipName -> Set(debugName der SkAnim-Knoten, die ihn nutzen)
walk(rc2, (o) => {
    if (o.$type === 'animAnimNode_SkAnim' && o.debugName && String(o.debugName.$value).startsWith('choomlink_')
        && o.animation && typeof o.animation.$value === 'string') {
        const clip = o.animation.$value;
        if (!referencedClips.has(clip)) referencedClips.set(clip, new Set());
        referencedClips.get(clip).add(o.debugName.$value);
    }
});
const clipNames = [...referencedClips.keys()].sort();
console.log(`Lint: ${clipNames.length} choomlink_-Clip-Referenzen gefunden:`, clipNames.join(', '));

// 1. Existenz gegen den Clip-Index.
if (fs.existsSync(CLIP_INDEX_FILE)) {
    const clipIndex = JSON.parse(fs.readFileSync(CLIP_INDEX_FILE, 'utf8'));
    const unknown = clipNames.filter((c) => !clipIndex.clips[c]);
    if (unknown.length > 0) {
        console.error('\nLINT FEHLGESCHLAGEN — folgende Clips existieren in KEINEM indizierten .anims-Set:');
        for (const c of unknown) {
            console.error(`  ${c}  (referenziert von: ${[...referencedClips.get(c)].join(', ')})`);
        }
        console.error('\nEntweder ein Tippfehler, oder der Clip existiert für dieses Entity schlicht nicht.');
        console.error('Vor dem Verdrahten prüfen: node clip-index.mjs query <name>');
        process.exit(1);
    }
    console.log('Lint: alle referenzierten Clips im Index gefunden — OK.');
} else {
    console.warn(`Lint: ${CLIP_INDEX_FILE} nicht gefunden — Existenz-Prüfung übersprungen (node clip-index.mjs build ausführen).`);
}

// 2. Regressions-Diff gegen den letzten committeten Snapshot.
const baseline = fs.existsSync(BASELINE_FILE) ? JSON.parse(fs.readFileSync(BASELINE_FILE, 'utf8')) : { clips: [] };
const before = new Set(baseline.clips);
const after = new Set(clipNames);
const added = clipNames.filter((c) => !before.has(c));
const removed = [...before].filter((c) => !after.has(c));
if (added.length || removed.length) {
    console.log('\nLint: Änderung gegenüber dem letzten Snapshot:');
    if (added.length) console.log('  + hinzugekommen:', added.join(', '));
    if (removed.length) console.log('  - entfernt:      ', removed.join(', '));
} else {
    console.log('Lint: keine Änderung gegenüber dem letzten Snapshot.');
}
fs.writeFileSync(BASELINE_FILE, JSON.stringify({ clips: clipNames }, null, 2));
