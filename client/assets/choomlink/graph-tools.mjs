// graph-tools.mjs — Query/Edit-Werkzeug für den humanoid.animgraph-JSON-Dump (~420 MB).
// Aufruf: node --max-old-space-size=8192 graph-tools.mjs <verb> <json> [args]
//
// Struktur-Erkenntnis (2026-07-17): Der Graph ist KEIN flacher Node-Pool. Er ist ein
// verschachtelter Baum unter $.Data.RootChunk.nodesToInit[0].Data — das erste Auftreten
// eines Handles trägt volle {HandleId, Data}, jedes weitere Auftreten ist nur ein
// Rückverweis {HandleRefId}. Feature-Input-Deklarationen liegen dagegen in einem FLACHEN
// Array: $.Data.RootChunk.animFeatures[i] = {$type:"animAnimFeatureEntry", className, name}.
//
// Verben:
//   stats [N]              Top-N $type-Histogramm (default 60) — naive Volltraversierung
//   find-inputs            animFeatures-Array dumpen (Name + Klasse + Index)
//   find-output             Root->Output-Kette ab rootNode auflösen (Handle-Resolver)
//   find-clips <regex>     CName-Werte, deren Text den Regex matcht (z. B. "^walk")
//   find-type <typeName>   Alle Objekte mit diesem $type ausgeben (kurz)
//   get <jsonpath>         Wert an $.a.b.0.c ausgeben (Punkt-Notation, $ = Wurzel)
//   set <jsonpath> <json>  Wert setzen (schreibt die Datei zurück!) und rücklesen
import fs from 'fs';

const [, , verb, file, ...args] = process.argv;
if (!verb || !file) {
    console.error('usage: node graph-tools.mjs <stats|find-inputs|find-output|find-clips|find-type|get|set> <json> [args]');
    process.exit(1);
}
const j = JSON.parse(fs.readFileSync(file, 'utf8'));
const rc = j.Data.RootChunk;

// Naive Volltraversierung — reicht für Inhaltssuche (stats/find-clips/find-type), weil
// verschachtelte {HandleId, Data}-Paare normale JS-Objekte sind und mitrekursiert werden.
// Für STRUKTUR (Elternkette, "was zeigt auf den Output") braucht es den Handle-Resolver
// unten (buildHandleMap + resolveNode), weil Rückverweise sonst nicht auflösbar sind.
function walk(o, fn) {
    if (o && typeof o === 'object') {
        fn(o);
        for (const k of Object.keys(o)) {
            const v = o[k];
            if (v && typeof v === 'object') walk(v, fn);
        }
    }
}

function buildHandleMap() {
    const byHandle = new Map();
    walk(rc, (o) => {
        if (o.HandleId !== undefined && o.Data !== undefined) byHandle.set(String(o.HandleId), o.Data);
    });
    return byHandle;
}

function resolveNode(byHandle, n) {
    if (!n || typeof n !== 'object') return null;
    if (n.HandleId !== undefined && n.Data !== undefined) return n.Data;
    if (n.HandleRefId !== undefined) return byHandle.get(String(n.HandleRefId)) || null;
    if (n.node !== undefined) return resolveNode(byHandle, n.node);
    return null;
}

function resolvePath(path) {
    // "$.foo.0.bar" -> [Elternobjekt, letzter Schlüssel]. Relativ zu RootChunk (rc) — dieselbe
    // Konvention wie die Pfade, die find-output/stats/find-clips/find-type ausgeben und die
    // im Anatomie-Doc dokumentiert sind (NICHT relativ zur Datei-Wurzel j, die noch
    // Header/Data-Hülle trägt).
    const parts = path.replace(/^\$\.?/, '').split('.').filter(Boolean);
    let cur = rc;
    for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]];
    return [cur, parts[parts.length - 1]];
}

if (verb === 'stats') {
    const hist = {};
    walk(rc, (o) => { if (o.$type) hist[o.$type] = (hist[o.$type] || 0) + 1; });
    const sorted = Object.entries(hist).sort((a, b) => b[1] - a[1]);
    for (const [t, n] of sorted.slice(0, Number(args[0] || 60))) console.log(String(n).padStart(8), t);
    console.log('distinct types:', sorted.length);
}

if (verb === 'find-inputs') {
    // Feature-Input-Deklarationen: flaches Array, verifiziert 2026-07-17 (51 Einträge).
    rc.animFeatures.forEach((entry, i) => {
        console.log(`animFeatures[${i}]`, '::', entry.name.$value, '->', entry.className.$value);
    });
}

if (verb === 'find-output') {
    const byHandle = buildHandleMap();
    const root = byHandle.get(String(rc.rootNode.HandleRefId));
    function name(data) {
        if (!data) return '(null)';
        const dn = data.debugName && data.debugName.$value;
        return data.$type + (dn && dn !== 'None' ? ` "${dn}"` : '');
    }
    function printSpine(data, depth, maxDepth, path) {
        if (!data || depth > maxDepth) return;
        console.log('  '.repeat(depth) + path + ': ' + name(data));
        if (data.node) printSpine(resolveNode(byHandle, data.node), depth + 1, maxDepth, 'node');
        if (data.inputLink) printSpine(resolveNode(byHandle, data.inputLink), depth + 1, maxDepth, 'inputLink');
        if (Array.isArray(data.inputNodes)) {
            data.inputNodes.forEach((n, i) => printSpine(resolveNode(byHandle, n), depth + 1, maxDepth, `inputNodes[${i}]`));
        }
        if (Array.isArray(data.nodes)) {
            data.nodes.forEach((n, i) => printSpine(resolveNode(byHandle, n), depth + 1, maxDepth, `nodes[${i}]`));
        }
    }
    printSpine(root, 0, Number(args[0] || 8), 'root');
}

if (verb === 'find-clips') {
    const re = new RegExp(args[0] || '^walk', 'i');
    const seen = new Set();
    walk(rc, (o) => {
        const v = o.$value;
        if (typeof v === 'string' && re.test(v)) seen.add(v);
    });
    for (const v of [...seen].sort()) console.log(v);
    console.log('distinct matches:', seen.size);
}

if (verb === 'find-type') {
    const target = args[0];
    let count = 0;
    walk(rc, (o) => {
        if (o.$type === target && count < 200) {
            console.log(JSON.stringify(o).slice(0, 400));
            count++;
        }
    });
    console.log('shown (capped 200):', count);
}

if (verb === 'get') {
    const [parent, key] = resolvePath(args[0]);
    console.log(JSON.stringify(parent[key]).slice(0, 4000));
}

if (verb === 'set') {
    const [parent, key] = resolvePath(args[0]);
    const before = JSON.stringify(parent[key]);
    parent[key] = JSON.parse(args[1]);
    fs.writeFileSync(file, JSON.stringify(j));
    // Rücklesen zur Bestätigung: Datei komplett neu parsen (nicht das In-Memory-Objekt
    // wiederverwenden), damit der Schreibvorgang selbst verifiziert wird.
    const j2 = JSON.parse(fs.readFileSync(file, 'utf8'));
    const rc2 = j2.Data.RootChunk;
    const parts = args[0].replace(/^\$\.?/, '').split('.').filter(Boolean);
    let cur = rc2;
    for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]];
    console.log('before:', before.slice(0, 200));
    console.log('written+reread:', JSON.stringify(cur[parts[parts.length - 1]]).slice(0, 200));
}
