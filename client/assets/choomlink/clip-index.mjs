// clip-index.mjs — build/query a local index of the puppet entity's NPC
// animation-set clip names.
//
// Problem this solves (D3 Stufe 4, 2026-07-27/28): a CName reference inside
// humanoid.animgraph (e.g. "walk_left") does NOT prove a clip exists — it may
// be a name that only appears inside the graph itself, never in any .anims
// set the entity actually loads. An unresolvable clip silently renders a bind
// pose, no error, no log line. Verifying a clip name previously meant:
// extract the relevant .anims file(s) with WolvenKit CLI, serialize each to
// JSON, and grep by hand — repeated from scratch every time a name needed
// checking. This script does that extraction ONCE (`build`) and writes a
// compact index so every later check is an instant `query`.
//
// Usage:
//   node clip-index.mjs build               (re)build the index from every .anims
//                                            set puppet_base.ent references
//   node clip-index.mjs query <name>        exact match, falls back to substring
//   node clip-index.mjs sets                list every indexed .anims set
//   node clip-index.mjs list <setPath>      list every clip in one set
//
// Config (env vars — defaults match this machine, see docs/ENVIRONMENT.md):
//   WOLVENKIT_CLI        path to WolvenKit.CLI.exe
//   CP2077_PATH          Cyberpunk 2077 install directory
//   CLIP_INDEX_SCRATCH   scratch dir for raw WolvenKit extraction (NOT committed —
//                        only the compact clip-index.json is)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const WOLVENKIT_CLI = process.env.WOLVENKIT_CLI || 'C:/Users/G4M3R/Tools/wolvenkit-cli/WolvenKit.CLI.exe';
const CP2077_PATH = process.env.CP2077_PATH || 'C:/Program Files (x86)/Steam/steamapps/common/Cyberpunk 2077';
const SCRATCH = process.env.CLIP_INDEX_SCRATCH || 'C:/wk/clip-index-scratch';
const ENTITY_FILE = path.join(HERE, 'puppet_base.ent');
const INDEX_FILE = path.join(HERE, 'clip-index.json');

function wolvenkit(...args) {
    return execFileSync(WOLVENKIT_CLI, args, { encoding: 'utf8', maxBuffer: 1024 * 1024 * 200 });
}

function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function depotToLocalParts(depotPath) {
    return depotPath.split(/[\\/]/).filter(Boolean);
}

// Naive full-tree walk — same pattern as graph-tools.mjs's walk(): nested
// {HandleId, Data} pairs are plain JS objects, so content search doesn't need
// the handle-resolver machinery graph-tools.mjs needs for structural queries.
function walk(o, fn) {
    if (o === null || typeof o !== 'object') return;
    if (Array.isArray(o)) { for (const v of o) walk(v, fn); return; }
    fn(o);
    for (const k of Object.keys(o)) walk(o[k], fn);
}

function findAnimsPaths(entityJson) {
    const rc = entityJson.Data.RootChunk;
    const found = new Set();
    walk(rc, (o) => {
        if (o.DepotPath !== undefined) {
            const p = o.DepotPath.$value ?? o.DepotPath;
            if (typeof p === 'string' && p.endsWith('.anims')) found.add(p);
        }
    });
    return [...found].sort();
}

function extractClipNames(animsJson) {
    const names = new Set();
    walk(animsJson, (o) => {
        if (o.$type === 'animAnimation' && o.name && typeof o.name.$value === 'string') {
            names.add(o.name.$value);
        }
    });
    return [...names].sort();
}

function build() {
    fs.mkdirSync(SCRATCH, { recursive: true });

    // Step 1: serialize the entity fresh (not a cached copy) to discover which
    // .anims sets it references right now.
    const entScratch = path.join(SCRATCH, 'entity');
    fs.mkdirSync(entScratch, { recursive: true });
    const entCopy = path.join(entScratch, 'puppet_base.ent');
    fs.copyFileSync(ENTITY_FILE, entCopy);
    console.log('serializing puppet_base.ent...');
    wolvenkit('convert', 'serialize', entCopy, '-o', entScratch);
    const entityJson = JSON.parse(fs.readFileSync(entCopy + '.json', 'utf8'));
    const animsPaths = findAnimsPaths(entityJson);
    console.log(`entity references ${animsPaths.length} .anims sets`);
    if (animsPaths.length === 0) {
        console.error('no .anims references found — is puppet_base.ent the right file?');
        process.exit(1);
    }

    // Step 2: ONE extract call covering every referenced set (a separate call
    // per file would rescan every content archive once per set — this session's
    // manual extractions each took a noticeable pause per file for exactly that
    // reason). Combined alternation regex, anchored at the end of the path.
    const extractDir = path.join(SCRATCH, 'sets');
    fs.mkdirSync(extractDir, { recursive: true });
    const combinedRegex = '(' + animsPaths.map(escapeRegex).join('|') + ')$';
    console.log('extracting all referenced sets in one pass...');
    wolvenkit('extract', path.join(CP2077_PATH, 'archive', 'pc', 'content'),
        '--regex', combinedRegex, '-o', extractDir);

    // Step 3: serialize + parse each extracted set.
    const clips = {}; // clipName -> [setPath, ...]
    const sets = {};  // setPath -> [clipName, ...]
    let missing = [];
    let done = 0;
    for (const setPath of animsPaths) {
        done++;
        const localFile = path.join(extractDir, ...depotToLocalParts(setPath));
        if (!fs.existsSync(localFile)) {
            console.warn(`  [${done}/${animsPaths.length}] MISSING after extraction: ${setPath}`);
            missing.push(setPath);
            continue;
        }
        wolvenkit('convert', 'serialize', localFile, '-o', path.dirname(localFile));
        const setJson = JSON.parse(fs.readFileSync(localFile + '.json', 'utf8'));
        const names = extractClipNames(setJson);
        sets[setPath] = names;
        console.log(`  [${done}/${animsPaths.length}] ${setPath} — ${names.length} clips`);
        for (const n of names) {
            if (!clips[n]) clips[n] = [];
            if (!clips[n].includes(setPath)) clips[n].push(setPath);
        }
    }

    const index = {
        entitySource: path.relative(path.resolve(HERE, '..', '..', '..'), ENTITY_FILE),
        setCount: Object.keys(sets).length,
        clipCount: Object.keys(clips).length,
        missingSets: missing,
        clips,
        sets,
    };
    fs.writeFileSync(INDEX_FILE, JSON.stringify(index, null, 2));
    console.log(`\nindex written to ${INDEX_FILE}`);
    console.log(`${index.clipCount} distinct clips across ${index.setCount} sets` +
        (missing.length ? ` (${missing.length} sets failed to extract, see missingSets)` : ''));
}

function loadIndex() {
    if (!fs.existsSync(INDEX_FILE)) {
        console.error(`no index at ${INDEX_FILE} yet — run "node clip-index.mjs build" first`);
        process.exit(1);
    }
    return JSON.parse(fs.readFileSync(INDEX_FILE, 'utf8'));
}

function query(name) {
    const index = loadIndex();
    if (index.clips[name]) {
        console.log(`"${name}" — EXISTS, in ${index.clips[name].length} set(s):`);
        for (const s of index.clips[name]) console.log('  ', s);
        return;
    }
    const needle = name.toLowerCase();
    const matches = Object.keys(index.clips).filter((c) => c.toLowerCase().includes(needle));
    if (matches.length === 0) {
        console.log(`"${name}" — NOT FOUND (exact or substring) in any indexed set.`);
        console.log('Either it lives in a set this entity does not reference, or the name is wrong.');
        process.exit(1);
    }
    console.log(`"${name}" — no exact match. Substring matches:`);
    for (const m of matches) console.log(`  ${m}  (${index.clips[m].join(', ')})`);
}

function listSets() {
    const index = loadIndex();
    console.log(`${index.setCount} indexed sets (built from ${index.entitySource}):`);
    for (const s of Object.keys(index.sets).sort()) {
        console.log(`  ${s}  — ${index.sets[s].length} clips`);
    }
    if (index.missingSets.length) {
        console.log(`\n${index.missingSets.length} sets referenced but failed to extract:`);
        for (const s of index.missingSets) console.log('  ', s);
    }
}

function listClipsIn(setPath) {
    const index = loadIndex();
    const candidates = setPath.endsWith('.anims') ? [setPath] : [setPath, setPath + '.anims'];
    const match = Object.keys(index.sets).find((s) => candidates.some((c) => s === c || s.endsWith(c)));
    if (!match) {
        console.error(`no indexed set matches "${setPath}" — run "node clip-index.mjs sets" to see what's indexed`);
        process.exit(1);
    }
    console.log(`${match} — ${index.sets[match].length} clips:`);
    for (const c of index.sets[match]) console.log('  ', c);
}

const [, , verb, arg] = process.argv;
switch (verb) {
    case 'build':
        build();
        break;
    case 'query':
        if (!arg) { console.error('usage: node clip-index.mjs query <name>'); process.exit(1); }
        query(arg);
        break;
    case 'sets':
        listSets();
        break;
    case 'list':
        if (!arg) { console.error('usage: node clip-index.mjs list <setPath>'); process.exit(1); }
        listClipsIn(arg);
        break;
    default:
        console.error('usage: node clip-index.mjs <build|query|sets|list> [arg]');
        process.exit(1);
}
