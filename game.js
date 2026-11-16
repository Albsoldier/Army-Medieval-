/* Iron Crowns — a turn-based medieval strategy game.
 * Plain JavaScript, no dependencies. Everything lives in this file:
 *   1. Data (units, provinces, kingdoms)
 *   2. Map generation (seeded, so saves only store the seed)
 *   3. Rules: economy, movement, battles, raids, conquest
 *   4. Computer-controlled kingdoms
 *   5. Rendering, UI and the animated battle viewer
 */
'use strict';
(() => {

// ======================================================================
// Utilities
// ======================================================================
const $ = s => document.querySelector(s);
const rand = (a, b) => a + Math.random() * (b - a);
const ri = (a, b) => Math.floor(rand(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const fmt = n => n >= 10000 ? Math.round(n / 1000) + 'k' : n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(Math.round(n));
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function shuffle(a, r = Math.random) {
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}
function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
function makeNoise(rnd) {
  const perm = new Uint8Array(512), vals = new Float32Array(256);
  for (let i = 0; i < 256; i++) { vals[i] = rnd() * 2 - 1; perm[i] = i; }
  for (let i = 255; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); const t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
  for (let i = 0; i < 256; i++) perm[i + 256] = perm[i];
  const h = (x, y) => vals[perm[(perm[x & 255] + y) & 255]];
  return (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    const a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  };
}
const hexRgb = h => { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };

// ======================================================================
// 1. Data
// ======================================================================
const MAP_W = 1000, MAP_H = 640;
const SAVE_KEY = 'iron-crowns-save-v1';

// cost is per recruited batch; upkeep is food per soldier per turn
const UNITS = {
  militia:  { name: 'Militia',   icon: '🗡️', atk: 1.0, def: 1.0, hp: 10, ranged: 0,   batch: 10, cost: { gold: 12, wood: 0 },  upkeep: 0.08, desc: 'Cheap and plentiful. Good for holding ground.' },
  spear:    { name: 'Spearmen',  icon: '🔱', atk: 1.4, def: 2.0, hp: 12, ranged: 0,   batch: 10, cost: { gold: 22, wood: 6 },  upkeep: 0.10, desc: 'Sturdy line infantry. Deadly against knights.' },
  archer:   { name: 'Archers',   icon: '🏹', atk: 0.6, def: 0.8, hp: 9,  ranged: 1.6, batch: 10, cost: { gold: 24, wood: 10 }, upkeep: 0.10, desc: 'Loose a volley before the armies clash. Shred spearmen.' },
  knight:   { name: 'Knights',   icon: '🐎', atk: 3.5, def: 3.0, hp: 20, ranged: 0,   batch: 10, cost: { gold: 100, wood: 0 }, upkeep: 0.25, desc: 'Heavy cavalry. Ride down archers and militia.' },
  catapult: { name: 'Catapults', icon: '🪨', atk: 0,   def: 0.5, hp: 30, ranged: 6,   batch: 1,  cost: { gold: 45, wood: 35 }, upkeep: 0.5,  desc: 'Each one knocks 10% off enemy wall bonuses. Pounds ranks too.' },
  levy:     { name: 'Levy',      icon: '👨‍🌾', atk: 0.8, def: 1.0, hp: 9,  ranged: 0,   batch: 0,  cost: { gold: 0, wood: 0 },   upkeep: 0,    desc: 'Townsfolk who man the walls when attacked.' },
};
const ARMY_TYPES = ['militia', 'spear', 'archer', 'knight', 'catapult'];
// damage multipliers: attacker type -> target type
const BONUS = {
  spear: { knight: 2.5 },
  knight: { archer: 1.6, militia: 1.3, levy: 1.3 },
  archer: { spear: 1.3, militia: 1.2 },
};

const PTYPES = {
  castle:  { name: 'Castle',   icon: '🏰', yield: { gold: 30, food: 12, wood: 8 }, recruit: true },
  town:    { name: 'Town',     icon: '🏘️', yield: { gold: 18, food: 4, wood: 3 },  recruit: true },
  village: { name: 'Village',  icon: '🛖', yield: { gold: 7, food: 10, wood: 2 } },
  farm:    { name: 'Farmland', icon: '🌾', yield: { gold: 2, food: 18, wood: 0 } },
  forest:  { name: 'Forest',   icon: '🌲', yield: { gold: 0, food: 3, wood: 14 } },
  mine:    { name: 'Mine',     icon: '⛏️', yield: { gold: 16, food: 0, wood: 2 } },
};
const LEVEL_MULT = [1, 1.5, 2];

const KINGDOM_DEFS = [
  { name: 'Aldmere',   title: 'Kingdom of Aldmere',  color: '#2f6fd6' },
  { name: 'Varkholm',  title: 'Duchy of Varkholm',   color: '#c0392b' },
  { name: 'Thornwood', title: 'Realm of Thornwood',  color: '#2e8b57' },
  { name: 'Goldcrest', title: 'Barony of Goldcrest', color: '#c9a227' },
];
const REBEL = { name: 'Rebels', title: 'Rebel lords', color: '#857a6c' };

const DIFFS = {
  easy:   { name: 'Squire',  ai: 0.75, aggr: 1.55, raid: 0.25 },
  normal: { name: 'Knight',  ai: 1.0,  aggr: 1.3,  raid: 0.4 },
  hard:   { name: 'Warlord', ai: 1.35, aggr: 1.15, raid: 0.55 },
};

const NAME_A = ['Ash', 'Black', 'Bram', 'Cold', 'Dun', 'Elm', 'Fen', 'Glen', 'Grey', 'Hart', 'Iron', 'Kings', 'Lang', 'Marl', 'North', 'Oak', 'Raven', 'Red', 'Stone', 'Thorn', 'Wolf', 'Wyn', 'Ald', 'Bel', 'Cor', 'Dray', 'Ever', 'Frost', 'Holl', 'Mist', 'Rook', 'Sil', 'Tarn', 'Ul', 'Wester', 'Yar'];
const NAME_B = ['ford', 'wick', 'moor', 'dale', 'holm', 'bury', 'stead', 'vale', 'gate', 'mere', 'hollow', 'field', 'brook', 'crag', 'haven', 'ton', 'wood', 'reach', 'march', 'keep', 'fell', 'combe'];

// ======================================================================
// Army helpers
// ======================================================================
const emptyArmy = () => ({ militia: 0, spear: 0, archer: 0, knight: 0, catapult: 0 });
const total = a => { let s = 0; for (const t in a) s += a[t] || 0; return s; };
const addArmy = (a, b) => { for (const t in b) a[t] = (a[t] || 0) + (b[t] || 0); return a; };
const subArmy = (a, b) => { for (const t in b) a[t] = Math.max(0, (a[t] || 0) - (b[t] || 0)); return a; };
const scaleArmy = (a, f) => { const r = emptyArmy(); for (const t of ARMY_TYPES) r[t] = Math.floor((a[t] || 0) * f); return r; };
const unitPow = t => { const u = UNITS[t]; return (u.atk + u.ranged * 0.7) * u.hp * (1 + u.def * 0.25); };
const power = a => { let s = 0; for (const t in a) s += (a[t] || 0) * unitPow(t); return s; };
const wallMult = (walls, cats) => 1 + 0.35 * walls * Math.max(0, 1 - (cats || 0) * 0.1);

// ======================================================================
// 2. Map generation
// ======================================================================
function genMap(seed) {
  for (let i = 0; i < 10; i++) {
    const g = tryGen(seed + i, false);
    if (g) { g.seed = seed + i; return g; }
  }
  const g = tryGen(seed, true); g.seed = seed; return g;
}

function tryGen(seed, force) {
  const W = MAP_W, H = MAP_H, N = W * H;
  const rnd = mulberry32(seed);
  const nA = makeNoise(rnd), nB = makeNoise(rnd), nC = makeNoise(rnd);
  const cols = 8, rows = 5, cw = W / cols, ch = H / rows;
  const sx = [], sy = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    sx.push((c + 0.5 + (rnd() - 0.5) * 0.55) * cw);
    sy.push((r + 0.5 + (rnd() - 0.5) * 0.55) * ch);
  }
  const n = sx.length;
  const ids = new Int16Array(N), shade = new Uint8Array(N);

  // Voronoi regions with warped coordinates for organic borders; noisy coastline
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x;
    shade[i] = clamp(128 + 70 * nA(x / 45, y / 45) + 30 * nB(x / 9, y / 9) + (rnd() - 0.5) * 18, 0, 255);
    const e = Math.min(x, y, W - 1 - x, H - 1 - y);
    const m = 24 + 16 * nC(x / 60, y / 60) + 6 * nC(x / 15 + 50, y / 15);
    if (e < m) { ids[i] = -1; continue; }
    const wx = x + 28 * nA(x / 110 + 7, y / 110), wy = y + 28 * nB(x / 110, y / 110 + 9);
    let best = 0, bd = Infinity;
    for (let k = 0; k < n; k++) {
      const dx = wx - sx[k], dy = wy - sy[k], d = dx * dx + dy * dy;
      if (d < bd) { bd = d; best = k; }
    }
    ids[i] = best;
  }

  // Remove enclaves: keep only the largest connected piece of each region
  const comp = new Int32Array(N).fill(-1), q = new Int32Array(N);
  const compSize = [], compId = [];
  for (let i = 0; i < N; i++) {
    if (ids[i] < 0 || comp[i] >= 0) continue;
    const id = ids[i], cc = compSize.length;
    let h = 0, t = 0; q[t++] = i; comp[i] = cc;
    while (h < t) {
      const j = q[h++], x = j % W, y = (j / W) | 0;
      if (x > 0 && comp[j - 1] < 0 && ids[j - 1] === id) { comp[j - 1] = cc; q[t++] = j - 1; }
      if (x < W - 1 && comp[j + 1] < 0 && ids[j + 1] === id) { comp[j + 1] = cc; q[t++] = j + 1; }
      if (y > 0 && comp[j - W] < 0 && ids[j - W] === id) { comp[j - W] = cc; q[t++] = j - W; }
      if (y < H - 1 && comp[j + W] < 0 && ids[j + W] === id) { comp[j + W] = cc; q[t++] = j + W; }
    }
    compSize.push(t); compId.push(id);
  }
  const bestComp = new Int32Array(n).fill(-1);
  for (let c = 0; c < compSize.length; c++) {
    const id = compId[c];
    if (bestComp[id] < 0 || compSize[c] > compSize[bestComp[id]]) bestComp[id] = c;
  }
  for (let i = 0; i < N; i++) if (ids[i] >= 0 && bestComp[ids[i]] !== comp[i]) ids[i] = -2;
  for (let pass = 0, changed = true; changed && pass < 300; pass++) {
    changed = false;
    for (let i = 0; i < N; i++) {
      if (ids[i] !== -2) continue;
      const x = i % W, y = (i / W) | 0;
      const cand = [x > 0 ? ids[i - 1] : -9, x < W - 1 ? ids[i + 1] : -9, y > 0 ? ids[i - W] : -9, y < H - 1 ? ids[i + W] : -9];
      for (const c of cand) if (c >= 0) { ids[i] = c; changed = true; break; }
    }
  }
  for (let i = 0; i < N; i++) if (ids[i] === -2) ids[i] = -1;

  // Borders, adjacency, centroids
  const cnt = new Int32Array(n), smx = new Float64Array(n), smy = new Float64Array(n);
  const border = new Uint8Array(N), nb = new Int16Array(N).fill(-1);
  const adjC = new Map();
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x, id = ids[i];
    if (id >= 0) { cnt[id]++; smx[id] += x; smy[id] += y; }
    const nbrs = [];
    if (x < W - 1) nbrs.push(i + 1);
    if (y < H - 1) nbrs.push(i + W);
    for (const j of nbrs) {
      const id2 = ids[j];
      if (id2 === id) continue;
      if (id >= 0 && id2 >= 0) {
        if (border[i] !== 2) { border[i] = 1; nb[i] = id2; }
        if (border[j] !== 2) { border[j] = 1; nb[j] = id; }
        const key = Math.min(id, id2) * 64 + Math.max(id, id2);
        adjC.set(key, (adjC.get(key) || 0) + 1);
      } else { border[i] = 2; border[j] = 2; }
    }
  }
  const prov = [];
  for (let k = 0; k < n; k++) {
    if (cnt[k] < 1500 && !force) return null;
    prov.push({ cx: smx[k] / Math.max(1, cnt[k]), cy: smy[k] / Math.max(1, cnt[k]), area: cnt[k], adj: [] });
  }
  for (const [key, c] of adjC) {
    if (c < 6) continue;
    const a = Math.floor(key / 64), b = key % 64;
    prov[a].adj.push(b); prov[b].adj.push(a);
  }
  // connectivity check
  const seen = new Set([0]), stack = [0];
  while (stack.length) for (const j of prov[stack.pop()].adj) if (!seen.has(j)) { seen.add(j); stack.push(j); }
  if (seen.size !== n && !force) return null;

  // Label points: far from borders, near the centroid (chamfer distance transform)
  const dt = new Float32Array(N);
  for (let i = 0; i < N; i++) dt[i] = (ids[i] < 0 || border[i]) ? 0 : 1e9;
  for (let y = 1; y < H; y++) for (let x = 1; x < W - 1; x++) {
    const i = y * W + x; if (!dt[i]) continue;
    dt[i] = Math.min(dt[i], dt[i - 1] + 1, dt[i - W] + 1, dt[i - W - 1] + 1.414, dt[i - W + 1] + 1.414);
  }
  for (let y = H - 2; y >= 0; y--) for (let x = W - 2; x > 0; x--) {
    const i = y * W + x; if (!dt[i]) continue;
    dt[i] = Math.min(dt[i], dt[i + 1] + 1, dt[i + W] + 1, dt[i + W + 1] + 1.414, dt[i + W - 1] + 1.414);
  }
  const bestScore = new Float32Array(n).fill(-Infinity);
  for (const p of prov) { p.lx = p.cx; p.ly = p.cy; }
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x, id = ids[i]; if (id < 0) continue;
    const p = prov[id];
    const s = Math.min(dt[i], 45) - 0.25 * Math.hypot(x - p.cx, y - p.cy);
    if (s > bestScore[id]) { bestScore[id] = s; p.lx = x; p.ly = y; }
  }
  return { ids, shade, border, nb, n, prov };
}

// ======================================================================
// Game state
// ======================================================================
let G = null;     // geometry (regenerated from the seed, never saved)
let S = null;     // saved state
let busy = false; // true while the AI moves or a battle is playing
const UI = { selected: null, march: emptyArmy() };
const battleQueue = [];

function uniqueNames(count) {
  const used = new Set(), out = [];
  let guard = 0;
  while (out.length < count && guard++ < 5000) {
    const a = NAME_A[ri(0, NAME_A.length - 1)], b = NAME_B[ri(0, NAME_B.length - 1)];
    const nm = a + b;
    if (!used.has(nm)) { used.add(nm); out.push(nm); }
  }
  while (out.length < count) out.push('Hold ' + out.length);
  return out;
}

function weightedPick(pairs) {
  let s = 0; for (const [, w] of pairs) s += w;
  let r = Math.random() * s;
  for (const [v, w] of pairs) { r -= w; if (r <= 0) return v; }
  return pairs[pairs.length - 1][0];
}

function newGame(diff) {
  G = genMap(Math.floor(Math.random() * 1e9));
  const n = G.n, d = DIFFS[diff];
  const names = uniqueNames(n);
  S = { seed: G.seed, turn: 1, difficulty: diff, kingdoms: [], provinces: [], log: [], over: null };
  for (let i = 0; i < n; i++) {
    S.provinces.push({ name: names[i], type: 'village', owner: -1, army: emptyArmy(), tired: emptyArmy(), walls: 0, level: 1, pillaged: 0 });
  }
  // Neutral land types
  const typeW = [['village', 26], ['farm', 22], ['forest', 18], ['mine', 14], ['town', 14]];
  for (const p of S.provinces) p.type = weightedPick(typeW);

  // Capitals in the four corners
  const corners = shuffle([[0.1, 0.15], [0.9, 0.85], [0.9, 0.15], [0.1, 0.85]]);
  const taken = new Set();
  KINGDOM_DEFS.forEach((def, k) => {
    let best = -1, bd = Infinity;
    G.prov.forEach((g, i) => {
      if (taken.has(i)) return;
      const dd = Math.hypot(g.cx - corners[k][0] * MAP_W, g.cy - corners[k][1] * MAP_H);
      if (dd < bd) { bd = dd; best = i; }
    });
    taken.add(best);
    const isAI = k !== 0;
    S.kingdoms.push({
      ...def, ai: isAI, alive: true, capital: best,
      gold: 200, food: 150, wood: 80,
      aggr: isAI ? d.aggr + rand(-0.1, 0.15) : 0,
      raid: isAI ? d.raid + rand(-0.1, 0.1) : 0,
    });
    const p = S.provinces[best];
    Object.assign(p, { type: 'castle', owner: k, walls: 2, level: 1 });
    p.army = { militia: 60, spear: 40, archer: 30, knight: 10, catapult: 0 };
  });
  // Starting lands: two neighbours of each capital
  S.kingdoms.forEach((K, k) => {
    const nbrs = shuffle(G.prov[K.capital].adj.filter(j => S.provinces[j].owner < 0 && !taken.has(j)));
    nbrs.slice(0, 2).forEach((j, idx) => {
      const p = S.provinces[j];
      p.owner = k; p.type = idx === 0 ? 'farm' : (Math.random() < 0.5 ? 'village' : 'forest');
      p.army = { ...emptyArmy(), militia: 20 };
      taken.add(j);
    });
  });
  // Two rebel strongholds near the middle
  const mid = G.prov.map((g, i) => [i, Math.hypot(g.cx - MAP_W / 2, (g.cy - MAP_H / 2) * 1.4)])
    .filter(([i]) => !taken.has(i)).sort((a, b) => a[1] - b[1]);
  const strongholds = [];
  for (const [i] of mid) {
    if (strongholds.length >= 2) break;
    if (strongholds.some(s => G.prov[s].adj.includes(i))) continue;
    strongholds.push(i);
  }
  // Rebel garrisons get stronger the further they are from any capital
  S.provinces.forEach((p, i) => {
    if (p.owner >= 0) return;
    const g = G.prov[i];
    const dist = Math.min(...S.kingdoms.map(K => Math.hypot(g.cx - G.prov[K.capital].cx, g.cy - G.prov[K.capital].cy)));
    const s = 0.6 + (dist / 500) * 1.4;
    if (strongholds.includes(i)) {
      Object.assign(p, { type: 'castle', walls: 1 });
      p.army = { militia: 80, spear: 60, archer: 40, knight: 15, catapult: 0 };
      return;
    }
    const m = p.type === 'town' ? 1.5 : 1;
    p.army = {
      militia: Math.round(ri(12, 25) * s * m), spear: Math.round(ri(0, 18) * s * m),
      archer: Math.round(ri(0, 12) * s * m), knight: 0, catapult: 0,
    };
    if (p.type === 'town') p.walls = 1;
  });
  UI.selected = S.kingdoms[0].capital;
  UI.march = { ...S.provinces[UI.selected].army };
  log(`Your reign begins. Lead the ${S.kingdoms[0].title} to glory!`, 'big');
  log('Recruit at your castle, raid your rivals and seize their capitals.', 'dim');
  save();
}

function save() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(S)); } catch (e) { /* storage unavailable */ } }
function loadSave() {
  try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch (e) { return null; }
}
function clearSave() { try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ignore */ } }

function log(text, cls = '') {
  S.log.unshift({ t: S.turn, text, cls });
  if (S.log.length > 120) S.log.length = 120;
}

const kName = k => k >= 0 ? S.kingdoms[k].name : REBEL.name;
const kTitle = k => k >= 0 ? S.kingdoms[k].title : REBEL.title;
const kColor = k => k >= 0 ? S.kingdoms[k].color : REBEL.color;
const isCapital = i => S.kingdoms.some(K => K.alive && K.capital === i);
const ownedBy = k => S.provinces.map((p, i) => i).filter(i => S.provinces[i].owner === k);

// ======================================================================
// 3. Rules
// ======================================================================
function yieldOf(p) {
  const b = PTYPES[p.type].yield, m = LEVEL_MULT[p.level - 1];
  return { gold: Math.round(b.gold * m), food: Math.round(b.food * m), wood: Math.round(b.wood * m) };
}

function income(k) {
  let gold = 0, food = 0, wood = 0, upkeep = 0;
  for (const p of S.provinces) {
    if (p.owner !== k) continue;
    if (!p.pillaged) { const y = yieldOf(p); gold += y.gold; food += y.food; wood += y.wood; }
    for (const t of ARMY_TYPES) upkeep += ((p.army[t] || 0) + (p.tired[t] || 0)) * UNITS[t].upkeep;
  }
  const m = k === 0 ? 1 : DIFFS[S.difficulty].ai;
  return { gold: Math.round(gold * m), food: Math.round(food * m), wood: Math.round(wood * m), upkeep: Math.round(upkeep) };
}

const upgradeCost = p => ({ gold: 60 * p.level, wood: 40 * p.level });
const wallCost = p => ({ gold: 60 * (p.walls + 1), wood: 50 * (p.walls + 1) });
const recruitCost = t => UNITS[t].cost;
const afford = (K, c) => K.gold >= (c.gold || 0) && K.wood >= (c.wood || 0);
const pay = (K, c) => { K.gold -= c.gold || 0; K.wood -= c.wood || 0; };

function levyFor(p) {
  if (p.owner < 0) return 0;
  let l = p.walls * 15;
  if (p.type === 'castle') l += 25; else if (p.type === 'town') l += 10;
  return l;
}
function defenders(p) {
  const d = addArmy(addArmy(emptyArmy(), p.army), p.tired);
  const lv = levyFor(p);
  if (lv) d.levy = lv;
  return d;
}
const defPower = (p, cats = 0) => power(defenders(p)) * wallMult(p.walls, cats);

// One exchange of blows from side A into side B. Returns casualties in B.
function strike(A, B, ranged, defMult) {
  const cas = {}, dmg = {};
  const tb = total(B);
  if (tb <= 0) return cas;
  for (const a in A) {
    const n = A[a]; if (!n) continue;
    const u = UNITS[a];
    const atk = ranged ? u.ranged : u.atk + (a === 'catapult' ? u.ranged * 0.4 : 0) + (a === 'archer' ? u.ranged * 0.3 : 0);
    if (!atk) continue;
    for (const t in B) {
      if (!B[t]) continue;
      const m = (BONUS[a] && BONUS[a][t]) || 1;
      dmg[t] = (dmg[t] || 0) + n * atk * m * B[t] / tb;
    }
  }
  for (const t in dmg) {
    const u = UNITS[t];
    const eff = u.hp * (1 + u.def * 0.25) * defMult;
    const k = dmg[t] * 1.7 * rand(0.8, 1.2) / eff;
    cas[t] = Math.min(B[t], Math.floor(k) + (Math.random() < k % 1 ? 1 : 0));
  }
  return cas;
}

function resolveBattle(attIn, defIn, walls) {
  const att = { ...attIn }, def = { ...defIn };
  const wm = wallMult(walls, att.catapult);
  const p0a = Math.max(1, power(att)), p0d = Math.max(1, power(def));
  const rounds = [{ a: { ...att }, d: { ...def }, ranged: false }];
  let winner = null;
  for (let r = 1; r <= 14 && !winner; r++) {
    const ranged = r === 1;
    const ca = strike(def, att, ranged, 1);
    const cd = strike(att, def, ranged, wm);
    subArmy(att, ca); subArmy(def, cd);
    rounds.push({ a: { ...att }, d: { ...def }, ranged });
    const ra = power(att) / p0a, rd = power(def) / p0d;
    const aBroken = total(att) === 0 || ra < 0.3, dBroken = total(def) === 0 || rd < 0.3;
    if (aBroken && dBroken) winner = ra >= rd ? 'att' : 'def';
    else if (dBroken) winner = 'att';
    else if (aBroken) winner = 'def';
  }
  return { att, def, winner: winner || 'def', rounds };
}

function retreatTarget(i, owner) {
  const opts = G.prov[i].adj.filter(j => S.provinces[j].owner === owner);
  if (!opts.length) return null;
  return opts.sort((a, b) => power(S.provinces[b].army) - power(S.provinces[a].army))[0];
}

function moveUnits(from, to, units) {
  const a = S.provinces[from], b = S.provinces[to];
  const u = {}; for (const t of ARMY_TYPES) u[t] = Math.min(units[t] || 0, a.army[t] || 0);
  subArmy(a.army, u); addArmy(b.tired, u);
}

/** Attack (conquer) or raid province `toId` from `fromId` with `units`. */
function attack(fromId, toId, unitsIn, mode) {
  const from = S.provinces[fromId], to = S.provinces[toId];
  const ak = from.owner, dk = to.owner;
  const units = emptyArmy();
  for (const t of ARMY_TYPES) units[t] = Math.min(unitsIn[t] || 0, from.army[t] || 0);
  if (total(units) <= 0) return;
  subArmy(from.army, units);

  const defArmy = defenders(to);
  const hasDef = total(defArmy) > 0;
  const wallsBefore = to.walls;
  let res = null, won = true, attSurv = units;
  if (hasDef) {
    res = resolveBattle(units, defArmy, to.walls);
    won = res.winner === 'att';
    attSurv = emptyArmy(); for (const t of ARMY_TYPES) attSurv[t] = res.att[t] || 0;
    // Share defender survivors back between rested and tired troops; levy goes home
    for (const t of ARMY_TYPES) {
      const before = (to.army[t] || 0) + (to.tired[t] || 0);
      const left = res.def[t] || 0;
      const ready = before ? Math.round(left * (to.army[t] || 0) / before) : 0;
      to.army[t] = ready; to.tired[t] = left - ready;
    }
  }
  const attLost = total(units) - total(attSurv);
  let summary = '';
  const pi = ak === 0 || dk === 0;

  if (mode === 'raid') {
    addArmy(from.tired, attSurv);
    if (won) {
      let gold = 0, food = 0, wood = 0;
      if (!to.pillaged) {
        const y = yieldOf(to);
        gold = y.gold * 4 + 20; food = y.food * 4 + 10; wood = y.wood * 3;
        if (dk >= 0) {
          const D = S.kingdoms[dk];
          const sg = Math.round(D.gold * 0.15), sf = Math.round(D.food * 0.1);
          D.gold -= sg; D.food -= sf; gold += sg; food += sf;
        }
        to.pillaged = 3;
      }
      const A = S.kingdoms[ak];
      A.gold += gold; A.food += food; A.wood += wood;
      summary = gold + food + wood > 0
        ? `${kName(ak)} raided ${to.name}, carrying off 💰${gold} 🍞${food} 🪵${wood}. It will yield nothing for 3 turns.`
        : `${kName(ak)} raided ${to.name}, but it had already been stripped bare.`;
      if (pi) log(summary, ak === 0 ? 'good' : 'bad');
    } else {
      summary = `${kName(ak)}'s raid on ${to.name} was driven off (${attLost} fell).`;
      if (pi) log(summary, ak === 0 ? 'bad' : 'good');
    }
  } else if (won) {
    const surv = addArmy(addArmy(emptyArmy(), to.army), to.tired);
    to.army = emptyArmy(); to.tired = emptyArmy();
    if (total(surv) > 0) {
      const r = retreatTarget(toId, dk);
      if (r !== null) addArmy(S.provinces[r].tired, surv);
    }
    const wasCapital = dk >= 0 && S.kingdoms[dk].capital === toId && S.kingdoms[dk].alive;
    to.owner = ak;
    to.tired = attSurv;
    to.walls = Math.max(0, to.walls - 1);
    summary = `${kName(ak)} captured ${to.name}${hasDef ? ` (${attLost} fell in the assault)` : ' without a fight'}.`;
    if (pi) log(summary, ak === 0 ? 'good' : 'bad');
    else if (ak > 0 && dk >= 0) log(summary, 'dim');
    if (wasCapital) fallKingdom(dk, ak);
  } else {
    addArmy(from.tired, attSurv);
    summary = `${kName(ak)}'s assault on ${to.name} failed (${attLost} fell).`;
    if (pi) log(summary, ak === 0 ? 'bad' : 'good');
  }

  if (hasDef && pi) {
    battleQueue.push({
      title: (mode === 'raid' ? 'Raid on ' : 'Battle of ') + to.name,
      att: { name: kName(ak), color: kColor(ak) },
      def: { name: kName(dk), color: kColor(dk) },
      rounds: res.rounds, walls: wallsBefore, winner: res.winner,
      playerSide: ak === 0 ? 'att' : 'def', summary,
    });
  }
}

function fallKingdom(k, by) {
  const K = S.kingdoms[k];
  K.alive = false;
  for (const p of S.provinces) if (p.owner === k) p.owner = -1;
  log(`👑 The ${K.title} has fallen to ${kName(by)}! Its lands rise in rebellion.`, 'big');
  if (k === 0) { S.over = 'lost'; return; }
  if (S.kingdoms.every((Kk, i) => i === 0 || !Kk.alive)) S.over = 'won';
}

function newRound() {
  S.kingdoms.forEach((K, k) => {
    if (!K.alive) return;
    const inc = income(k);
    K.gold += inc.gold; K.wood += inc.wood; K.food += inc.food - inc.upkeep;
    if (K.food < 0) {
      K.food = 0;
      let lost = 0;
      for (const p of S.provinces) {
        if (p.owner !== k) continue;
        for (const t of ARMY_TYPES) {
          const a = Math.ceil(p.army[t] * 0.1), b = Math.ceil(p.tired[t] * 0.1);
          p.army[t] -= a; p.tired[t] -= b; lost += a + b;
        }
      }
      if (k === 0 && lost) log(`Starvation! ${lost} hungry soldiers deserted. Grow more food or disband troops.`, 'bad');
    }
  });
  for (const p of S.provinces) {
    if (p.pillaged > 0) p.pillaged--;
    addArmy(p.army, p.tired); p.tired = emptyArmy();
  }
  S.turn++;
}

// ======================================================================
// 4. Computer-controlled kingdoms
// ======================================================================
function threatAt(i, k) {
  let m = 0;
  for (const j of G.prov[i].adj) {
    const q = S.provinces[j];
    if (q.owner >= 0 && q.owner !== k) m = Math.max(m, power(q.army) + power(q.tired));
  }
  return m;
}
const isFrontier = (i, k) => G.prov[i].adj.some(j => S.provinces[j].owner !== k);

function provValue(i, k) {
  const p = S.provinces[i];
  let v = { castle: 5, town: 3, mine: 2.2, village: 2, farm: 2, forest: 1.6 }[p.type];
  if (isCapital(i)) v += 4;
  if (p.owner === 0 && S.difficulty === 'hard') v *= 1.15;
  v *= LEVEL_MULT[p.level - 1];
  return v;
}

// First step from province i toward a good frontier province (through own land)
function stepToFrontier(i, k) {
  const prev = new Map([[i, -1]]), dist = new Map([[i, 0]]), q = [i], fronts = [];
  while (q.length) {
    const c = q.shift();
    if (c !== i && isFrontier(c, k)) fronts.push(c);
    for (const j of G.prov[c].adj) {
      if (!prev.has(j) && S.provinces[j].owner === k) { prev.set(j, c); dist.set(j, dist.get(c) + 1); q.push(j); }
    }
  }
  if (!fronts.length) return null;
  const minD = Math.min(...fronts.map(f => dist.get(f)));
  const cands = fronts.filter(f => dist.get(f) <= minD + 2);
  const pw = f => power(S.provinces[f].army) + power(S.provinces[f].tired) + threatAt(f, k) * 0.5;
  let s = cands.sort((a, b) => pw(b) - pw(a))[0];
  while (prev.get(s) !== i) s = prev.get(s);
  return s;
}

function aiBuild(k) {
  const K = S.kingdoms[k];
  const cap = S.provinces[K.capital];
  if (cap.owner === k && cap.walls < 3 && threatAt(K.capital, k) > 0 && afford(K, wallCost(cap)) && K.gold > 250) {
    pay(K, wallCost(cap)); cap.walls++;
  }
  if (K.gold < 220 || K.wood < 80 || Math.random() < 0.4) return;
  const opts = ownedBy(k).map(i => S.provinces[i]).filter(p => p.level < 3)
    .sort((a, b) => { const ya = yieldOf(a), yb = yieldOf(b); return (yb.gold + yb.food + yb.wood) - (ya.gold + ya.food + ya.wood); });
  for (const p of opts.slice(0, 3)) {
    if (afford(K, upgradeCost(p))) { pay(K, upgradeCost(p)); p.level++; return; }
  }
}

function aiRecruit(k) {
  const K = S.kingdoms[k];
  const sites = ownedBy(k).filter(i => PTYPES[S.provinces[i].type].recruit && !S.provinces[i].pillaged);
  if (!sites.length) return;
  const inc = income(k);
  let netFood = inc.food - inc.upkeep;
  let budget = K.gold * (S.difficulty === 'hard' ? 0.8 : S.difficulty === 'easy' ? 0.55 : 0.7);
  // prefer sites near threats
  sites.sort((a, b) => threatAt(b, k) - threatAt(a, k));
  for (let guard = 0; guard < 60; guard++) {
    const t = weightedPick([
      ['militia', 2], ['spear', 3], ['archer', 3],
      ['knight', K.gold > 300 ? 2 : 0.5],
      ['catapult', K.wood > 90 ? 0.9 : 0],
    ]);
    const u = UNITS[t], c = u.cost, up = u.upkeep * u.batch;
    if (budget < c.gold || !afford(K, c)) { if (budget < 12) break; continue; }
    if (netFood - up < -K.food / 8) break;
    pay(K, c); budget -= c.gold; netFood -= up;
    const site = guard % 3 === 0 ? sites[ri(0, sites.length - 1)] : sites[0];
    S.provinces[site].tired[t] += u.batch;
  }
}

function aiMoveArmy(k, i) {
  const K = S.kingdoms[k], p = S.provinces[i];
  const myPow = power(p.army);
  if (myPow <= 0) return;
  const threat = threatAt(i, k);
  let keep = K.capital === i ? Math.max(myPow * 0.35, threat * 0.9) : threat * 0.5;
  keep -= (power(p.tired) + (levyFor(p) * unitPow('levy'))) * wallMult(p.walls, 0);
  const f = clamp(1 - Math.max(0, keep) / myPow, 0, 1);
  if (f < 0.15) return;
  const send = scaleArmy(p.army, f);
  const sp = power(send);
  if (sp <= 0) return;

  let best = null;
  for (const j of G.prov[i].adj) {
    const q = S.provinces[j];
    if (q.owner === k) continue;
    const dp = defPower(q, send.catapult);
    const ratio = sp / (dp + 1);
    if (ratio > K.aggr) {
      const score = provValue(j, k) * (1 + Math.min(ratio, 4) * 0.2) + Math.random() * 0.3;
      if (!best || score > best.score) best = { j, mode: 'conquer', score };
    } else if (q.owner >= 0 && !q.pillaged && ratio > 1.2 && Math.random() < K.raid) {
      const score = provValue(j, k) * 0.6;
      if (!best || score > best.score) best = { j, mode: 'raid', score };
    }
  }
  if (best) {
    // raids only need a strong enough party, not the whole host
    let force = send;
    if (best.mode === 'raid') {
      const need = defPower(S.provinces[best.j], send.catapult) * 1.6;
      force = scaleArmy(send, clamp(need / sp, 0.3, 1));
    }
    attack(i, best.j, force, best.mode);
    return;
  }
  if (!isFrontier(i, k)) {
    const step = stepToFrontier(i, k);
    if (step !== null && step !== i) moveUnits(i, step, send);
  }
}

function aiTurn(k) {
  const K = S.kingdoms[k];
  if (!K.alive) return;
  aiBuild(k);
  aiRecruit(k);
  const armies = ownedBy(k).filter(i => total(S.provinces[i].army) > 0)
    .sort((a, b) => power(S.provinces[b].army) - power(S.provinces[a].army));
  for (const i of armies) {
    if (S.over) return;
    if (!K.alive) return;
    const p = S.provinces[i];
    if (p.owner !== k || total(p.army) === 0) continue;
    aiMoveArmy(k, i);
  }
}

// ======================================================================
// 5. Rendering
// ======================================================================
const canvas = $('#map');
const DPR = Math.min(2, window.devicePixelRatio || 1);
canvas.width = MAP_W * DPR; canvas.height = MAP_H * DPR;
const mctx = canvas.getContext('2d');
const baseCanvas = document.createElement('canvas');
baseCanvas.width = MAP_W; baseCanvas.height = MAP_H;
const bctx = baseCanvas.getContext('2d');
let baseImg = null;

function targetsOf(sel) {
  if (sel == null) return [];
  const p = S.provinces[sel];
  if (p.owner !== 0 || total(p.army) <= 0) return [];
  return G.prov[sel].adj;
}

function renderBase() {
  if (!baseImg) baseImg = bctx.createImageData(MAP_W, MAP_H);
  const d = baseImg.data, { ids, shade, border, nb, n } = G;
  const PARCH = [228, 212, 172];
  const cols = [], mixes = [], owners = new Int8Array(n), pill = new Uint8Array(n), tg = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    const p = S.provinces[i];
    owners[i] = p.owner;
    cols.push(hexRgb(kColor(p.owner)));
    mixes.push(p.owner >= 0 ? 0.5 : 0.18);
    pill[i] = p.pillaged ? 1 : 0;
  }
  for (const j of targetsOf(UI.selected)) tg[j] = 1;
  const sel = UI.selected == null ? -1 : UI.selected;
  for (let i = 0, N = MAP_W * MAP_H; i < N; i++) {
    const id = ids[i], s = shade[i], o = i * 4;
    let r, g, b;
    if (id < 0) {
      const k = s / 255;
      r = 34 + k * 26; g = 74 + k * 36; b = 106 + k * 40;
      if (border[i] === 2) { r = 150; g = 170; b = 170; }
    } else {
      const c = cols[id], mx = mixes[id], k = 0.82 + (s / 255) * 0.32;
      r = (PARCH[0] * (1 - mx) + c[0] * mx) * k;
      g = (PARCH[1] * (1 - mx) + c[1] * mx) * k;
      b = (PARCH[2] * (1 - mx) + c[2] * mx) * k;
      if (pill[id]) { r = r * 0.8 + 34; g *= 0.66; b *= 0.58; }
      if (id === sel) { r = r * 0.72 + 75; g = g * 0.72 + 68; b = b * 0.72 + 52; }
      else if (tg[id]) { r = r * 0.78 + 62; g = g * 0.78 + 52; b = b * 0.78 + 6; }
      const bd = border[i];
      if (bd === 2) { r = 74; g = 54; b = 34; }
      else if (bd === 1) {
        if (owners[nb[i]] !== owners[id]) { r = c[0] * 0.5; g = c[1] * 0.5; b = c[2] * 0.5; }
        else { r *= 0.62; g *= 0.62; b *= 0.62; }
      }
    }
    d[o] = r; d[o + 1] = g; d[o + 2] = b; d[o + 3] = 255;
  }
  bctx.putImageData(baseImg, 0, 0);
}

function roundRect(c, x, y, w, h, r) {
  c.beginPath();
  c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
  c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
}

function drawMap() {
  const c = mctx;
  c.setTransform(DPR, 0, 0, DPR, 0, 0);
  c.clearRect(0, 0, MAP_W, MAP_H);
  c.imageSmoothingEnabled = false;
  c.drawImage(baseCanvas, 0, 0, MAP_W, MAP_H);
  c.imageSmoothingEnabled = true;
  c.textAlign = 'center'; c.textBaseline = 'middle';
  for (let i = 0; i < G.n; i++) {
    const g = G.prov[i], p = S.provinces[i];
    const x = g.lx, y = g.ly;
    c.font = '22px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",serif';
    c.fillText(PTYPES[p.type].icon, x, y - 10);
    if (isCapital(i)) { c.font = '14px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",serif'; c.fillText('👑', x + 15, y - 24); }
    if (p.pillaged) { c.font = '14px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",serif'; c.fillText('🔥', x - 16, y - 22); }
    c.font = '600 12px "EB Garamond", Georgia, serif';
    c.lineWidth = 3; c.strokeStyle = 'rgba(250,242,222,.85)'; c.lineJoin = 'round';
    c.strokeText(p.name, x, y + 11);
    c.fillStyle = '#2b2118'; c.fillText(p.name, x, y + 11);
    if (p.walls > 0) {
      for (let w = 0; w < p.walls; w++) { c.fillStyle = '#5b5148'; c.fillRect(x - 6 * p.walls / 2 + w * 6 + 0.5, y + 19, 5, 3); }
    }
    const n = total(p.army) + total(p.tired);
    if (n > 0) {
      const ready = total(p.army) > 0;
      const txt = (p.owner === 0 && ready ? '⚔ ' : '') + fmt(n);
      c.font = 'bold 11px system-ui, sans-serif';
      const w = c.measureText(txt).width + 12;
      roundRect(c, x - w / 2, y + 24, w, 16, 4);
      c.fillStyle = kColor(p.owner); c.fill();
      c.lineWidth = 1.5; c.strokeStyle = 'rgba(0,0,0,.55)'; c.stroke();
      c.fillStyle = '#fff'; c.fillText(txt, x, y + 32.5);
    }
  }
}

// ---------------- Panel / UI ----------------
function costTxt(c) {
  return [c.gold ? `💰${c.gold}` : '', c.wood ? `🪵${c.wood}` : ''].filter(Boolean).join(' ');
}

function renderTop() {
  const K = S.kingdoms[0], inc = income(0);
  const net = inc.food - inc.upkeep;
  const sg = v => v >= 0 ? `<small class="pos">+${v}</small>` : `<small class="neg">${v}</small>`;
  $('#resources').innerHTML = `
    <span class="r">📜 Turn <b>${S.turn}</b></span>
    <span class="r" title="Gold">💰 <b>${fmt(K.gold)}</b>${sg(inc.gold)}</span>
    <span class="r" title="Food (income minus army upkeep)">🍞 <b>${fmt(K.food)}</b>${sg(net)}</span>
    <span class="r" title="Wood">🪵 <b>${fmt(K.wood)}</b>${sg(inc.wood)}</span>
    <span class="r muted">${DIFFS[S.difficulty].name}</span>`;
  $('#endTurn').disabled = busy || !!S.over;
}

function armyTable(p) {
  const rows = ARMY_TYPES.filter(t => p.army[t] || p.tired[t]).map(t =>
    `<tr><td>${UNITS[t].icon} ${UNITS[t].name}</td><td>${p.army[t] || 0}</td><td>${p.tired[t] || 0}</td></tr>`).join('');
  if (!rows) return '<p class="muted">No troops stationed here.</p>';
  return `<table class="army"><tr><th>Troops</th><th title="Can act this turn">Ready</th><th title="Moved or recruited this turn">Resting</th></tr>${rows}</table>`;
}

function overviewHTML() {
  const rows = S.kingdoms.map((K, k) => {
    const prov = ownedBy(k).length;
    const men = ownedBy(k).reduce((s, i) => s + total(S.provinces[i].army) + total(S.provinces[i].tired), 0);
    return `<div class="kingdom ${K.alive ? '' : 'dead'}"><span class="sw" style="background:${K.color}"></span>
      <span class="nm">${esc(K.title)}${k === 0 ? ' (you)' : ''}</span><span class="muted">🗺 ${prov} · ⚔ ${fmt(men)}</span></div>`;
  }).join('');
  return `<h2>The Realm</h2>
    <p class="hint">Click a province to inspect it. Click one of your armies, then a highlighted neighbour to march, raid or attack.</p>
    <div class="kingdoms">${rows}</div>`;
}

function renderPanel() {
  const el = $('#info');
  const id = UI.selected;
  if (id == null) { el.innerHTML = overviewHTML(); return; }
  const p = S.provinces[id], T = PTYPES[p.type], own = p.owner === 0, K = S.kingdoms[0];
  const y = yieldOf(p);
  let h = `<div class="phead"><span class="picon">${T.icon}</span><div>
    <h2>${esc(p.name)}</h2>
    <div class="sub">${T.name}${isCapital(id) ? ' · 👑 Capital' : ''} — <span style="color:${kColor(p.owner)};font-weight:600">${esc(kTitle(p.owner))}</span></div></div></div>
    <div class="stats"><span title="Gold per turn">💰 ${y.gold}</span><span title="Food per turn">🍞 ${y.food}</span><span title="Wood per turn">🪵 ${y.wood}</span>
    <span title="Development level">⭐ Lv ${p.level}/3</span><span title="Walls give defenders a bonus">🧱 Walls ${p.walls}/3</span></div>`;
  if (p.pillaged) h += `<div class="warn">🔥 Pillaged. No income for ${p.pillaged} more turn${p.pillaged > 1 ? 's' : ''}.</div>`;
  h += `<h3>Garrison</h3>${armyTable(p)}`;
  const lv = levyFor(p);
  if (lv) h += `<p class="hint">+ ${lv} levy will man the walls if attacked.</p>`;

  if (own && !S.over) {
    if (total(p.army) > 0) {
      h += `<h3>March</h3><p class="hint">Choose who marches, then click a <b style="color:#e8d27a">highlighted</b> neighbour. Your own land: move. Enemy land: attack or raid.</p><div class="march">`;
      for (const t of ARMY_TYPES) {
        if (!p.army[t]) continue;
        h += `<label><span class="n">${UNITS[t].icon} ${UNITS[t].name}</span>
          <input type="number" min="0" max="${p.army[t]}" value="${clamp(UI.march[t] || 0, 0, p.army[t])}" data-unit="${t}"> <span class="muted">/ ${p.army[t]}</span></label>`;
      }
      h += `</div><div class="row"><button class="btn small" data-act="mAll">All</button><button class="btn small" data-act="mHalf">Half</button><button class="btn small" data-act="mNone">None</button></div>`;
    }
    h += `<h3>Build</h3><div class="row">`;
    if (p.level < 3) { const c = upgradeCost(p); h += `<button class="btn" data-act="upgrade" ${afford(K, c) ? '' : 'disabled'} title="+50% yields">⭐ Develop (${costTxt(c)})</button>`; }
    if (p.walls < 3) { const c = wallCost(p); h += `<button class="btn" data-act="walls" ${afford(K, c) ? '' : 'disabled'} title="Stronger defence and more levy">🧱 Walls (${costTxt(c)})</button>`; }
    if (p.level >= 3 && p.walls >= 3) h += '<span class="muted">Fully built.</span>';
    h += '</div>';
    if (T.recruit) {
      h += `<h3>Recruit</h3>${p.pillaged ? '<p class="hint">Cannot recruit while pillaged.</p>' : ''}<div class="recruit">`;
      for (const t of ARMY_TYPES) {
        const u = UNITS[t], c = u.cost;
        h += `<button class="btn" data-act="recruit" data-t="${t}" ${afford(K, c) && !p.pillaged ? '' : 'disabled'} title="${esc(u.desc)}">
          <span>${u.icon} ${u.name} ×${u.batch}</span><small>${costTxt(c)} · 🍞${+(u.upkeep * u.batch).toFixed(1)}/turn</small></button>`;
      }
      h += '</div><p class="hint">Recruits are ready to march next turn.</p>';
    } else {
      h += '<p class="hint">Recruit soldiers in castles 🏰 and towns 🏘️.</p>';
    }
  } else if (!own) {
    h += `<p class="hint">Defensive strength: <b>${fmt(defPower(p))}</b>${p.walls ? ` (walls ×${wallMult(p.walls, 0).toFixed(2)})` : ''}</p>`;
  }
  h += `<div class="row" style="margin-top:12px"><button class="btn small" data-act="deselect">◀ Realm overview</button></div>`;
  el.innerHTML = h;
}

function renderLog() {
  $('#log').innerHTML = S.log.slice(0, 60).map(e => `<li class="${e.cls}"><span class="t">T${e.t}</span>${esc(e.text)}</li>`).join('');
}

function refresh() {
  renderBase(); drawMap(); renderPanel(); renderTop(); renderLog();
}

let toastTimer = null;
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg; t.classList.remove('hidden'); t.style.opacity = 1;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.opacity = 0; setTimeout(() => t.classList.add('hidden'), 400); }, 1800);
}

function showModal(html, actions = {}) {
  const box = $('#modalBox');
  box.innerHTML = html;
  $('#modal').classList.remove('hidden');
  box.onclick = e => {
    const b = e.target.closest('[data-m]');
    if (!b || !(b.dataset.m in actions)) return;
    $('#modal').classList.add('hidden');
    const f = actions[b.dataset.m];
    if (f) f();
  };
}
const hideModal = () => $('#modal').classList.add('hidden');

// ---------------- Interaction ----------------
function select(id) {
  UI.selected = id;
  UI.march = id != null && S.provinces[id].owner === 0 ? { ...S.provinces[id].army } : emptyArmy();
  refresh();
}

function oddsLabel(r) {
  if (r > 2) return ['Overwhelming', 4];
  if (r > 1.4) return ['Favourable', 3];
  if (r > 1.0) return ['Even', 2];
  if (r > 0.7) return ['Risky', 1];
  return ['Hopeless', 0];
}

function handleMarch(from, to) {
  const units = emptyArmy();
  const src = S.provinces[from];
  for (const t of ARMY_TYPES) units[t] = clamp(Math.floor(UI.march[t] || 0), 0, src.army[t] || 0);
  if (total(units) <= 0) { toast('Choose some soldiers to march'); return; }
  const dst = S.provinces[to];
  if (dst.owner === 0) {
    moveUnits(from, to, units);
    log(`${total(units)} soldiers marched from ${src.name} to ${dst.name}.`, 'dim');
    save();
    select(total(src.army) > 0 ? from : to);
    return;
  }
  const ap = power(units), dp = defPower(dst, units.catapult);
  const [lbl, cls] = oddsLabel(ap / Math.max(1, dp));
  const dArmy = defenders(dst);
  const y = yieldOf(dst);
  const raidable = !dst.pillaged;
  const dList = ['levy', ...ARMY_TYPES].filter(t => dArmy[t]).map(t => `${UNITS[t].icon} ${dArmy[t]} ${UNITS[t].name}`).join(', ') || 'none';
  showModal(`
    <h2>⚔️ ${esc(dst.name)}</h2>
    <p class="muted">${PTYPES[dst.type].name} held by <b style="color:${kColor(dst.owner)}">${esc(kTitle(dst.owner))}</b></p>
    <p><b>Your host:</b> ${total(units)} soldiers (strength ${fmt(ap)})</p>
    <p><b>Defenders:</b> ${dList}${dst.walls ? ` behind level ${dst.walls} walls` : ''} (strength ${fmt(dp)})</p>
    <p>Odds: <span class="odds o${cls}">${lbl}</span>${dst.walls && !units.catapult ? ' <span class="muted">(catapults weaken walls)</span>' : ''}</p>
    <ul>
      <li><b>Conquer:</b> take the province. Your army stays to hold it.</li>
      <li><b>Raid:</b> loot about 💰${y.gold * 4 + 20} 🍞${y.food * 4 + 10} 🪵${y.wood * 3}${dst.owner >= 0 ? ' plus some of their treasury' : ''}, burn it for 3 turns, then return home.${raidable ? '' : ' <i>(Already pillaged, so nothing left to take.)</i>'}</li>
    </ul>
    <div class="btns">
      <button class="btn primary" data-m="conquer">⚔️ Conquer</button>
      <button class="btn gold" data-m="raid">🔥 Raid</button>
      <button class="btn" data-m="cancel">Cancel</button>
    </div>`, {
    conquer: () => doAttack(from, to, units, 'conquer'),
    raid: () => doAttack(from, to, units, 'raid'),
    cancel: null,
  });
}

function doAttack(from, to, units, mode) {
  attack(from, to, units, mode);
  save();
  const after = S.provinces[to].owner === 0 ? to : from;
  busy = true;
  refresh();
  playBattles(() => {
    busy = false;
    select(after);
    if (S.over) showGameOver();
  });
}

function endTurn() {
  if (busy || S.over) return;
  busy = true;
  UI.selected = null;
  for (let k = 1; k < S.kingdoms.length && !S.over; k++) aiTurn(k);
  if (!S.over) newRound();
  const inc = income(0);
  if (!S.over) log(`Turn ${S.turn} begins. Income 💰${inc.gold} 🍞${inc.food - inc.upkeep} 🪵${inc.wood}.`, 'dim');
  save();
  refresh();
  playBattles(() => {
    busy = false;
    if (S.over) { refresh(); showGameOver(); return; }
    UI.selected = null;
    refresh();
    toast(`Turn ${S.turn}`);
  });
}

canvas.addEventListener('click', e => {
  if (busy || !S) return;
  const r = canvas.getBoundingClientRect();
  const x = Math.floor((e.clientX - r.left) * MAP_W / r.width), y = Math.floor((e.clientY - r.top) * MAP_H / r.height);
  if (x < 0 || y < 0 || x >= MAP_W || y >= MAP_H) return;
  const id = G.ids[y * MAP_W + x];
  if (id < 0) { select(null); return; }
  const sel = UI.selected;
  if (sel != null && sel !== id && !S.over && targetsOf(sel).includes(id)) { handleMarch(sel, id); return; }
  select(id);
});

$('#panel').addEventListener('click', e => {
  const b = e.target.closest('[data-act]');
  if (!b || busy || !S) return;
  const id = UI.selected, p = id != null ? S.provinces[id] : null, K = S.kingdoms[0];
  switch (b.dataset.act) {
    case 'deselect': select(null); return;
    case 'mAll': UI.march = { ...p.army }; break;
    case 'mHalf': UI.march = scaleArmy(p.army, 0.5); break;
    case 'mNone': UI.march = emptyArmy(); break;
    case 'upgrade': {
      const c = upgradeCost(p);
      if (p.owner !== 0 || p.level >= 3 || !afford(K, c)) return;
      pay(K, c); p.level++; log(`${p.name} developed to level ${p.level}.`, 'good'); break;
    }
    case 'walls': {
      const c = wallCost(p);
      if (p.owner !== 0 || p.walls >= 3 || !afford(K, c)) return;
      pay(K, c); p.walls++; log(`${p.name} walls raised to level ${p.walls}.`, 'good'); break;
    }
    case 'recruit': {
      const t = b.dataset.t, u = UNITS[t];
      if (p.owner !== 0 || !PTYPES[p.type].recruit || p.pillaged || !afford(K, u.cost)) return;
      pay(K, u.cost); p.tired[t] += u.batch; break;
    }
  }
  save();
  refresh();
});

$('#panel').addEventListener('input', e => {
  const t = e.target.dataset && e.target.dataset.unit;
  if (!t || UI.selected == null) return;
  const max = S.provinces[UI.selected].army[t] || 0;
  UI.march[t] = clamp(Math.floor(+e.target.value || 0), 0, max);
});

$('#endTurn').addEventListener('click', endTurn);
$('#menuBtn').addEventListener('click', () => { if (!busy) showTitle(true); });
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
  if (!$('#modal').classList.contains('hidden') || !$('#battle').classList.contains('hidden')) return;
  if (e.key === 'e' || e.key === 'E') endTurn();
  if (e.key === 'Escape' && !busy && S) select(null);
});

// ---------------- Title / help / game over ----------------
const HELP = `
  <h2>How to play</h2>
  <ul>
    <li><b>Goal:</b> capture the capital 👑 of every rival kingdom. Lose your own capital and your reign ends.</li>
    <li><b>Economy:</b> each province yields gold 💰, food 🍞 and wood 🪵 every turn. Armies eat food. If your granaries run dry, soldiers desert.</li>
    <li><b>Recruit</b> in castles 🏰 and towns 🏘️. New troops can march next turn.</li>
    <li><b>March:</b> click a province with your army, pick the soldiers, then click a highlighted neighbour. Each soldier marches once per turn.</li>
    <li><b>Conquer</b> to take a province, or <b>Raid</b> to loot it, burn its income for 3 turns and bring your raiders home.</li>
    <li><b>Battles</b> are fought automatically. Archers 🏹 and catapults 🪨 shoot first. Spearmen 🔱 beat knights 🐎, knights beat archers, archers beat spearmen.</li>
    <li><b>Walls</b> 🧱 strengthen defenders and call up levy. Catapults break walls.</li>
    <li><b>Develop</b> ⭐ provinces to raise their yields.</li>
    <li>Shortcuts: <b>E</b> ends the turn, <b>Esc</b> deselects.</li>
  </ul>`;

function showTitle(fromMenu) {
  const hasSave = !!loadSave();
  showModal(`
    <h1>⚔️ Iron Crowns</h1>
    <p class="tag">A turn-based war of raids, sieges and great hosts</p>
    <p>Four crowns, one realm. Build your economy, raise vast armies, raid your rivals' lands and storm their castles.</p>
    <p style="text-align:center">Difficulty:
      <select id="diff">
        <option value="easy">Squire (easy)</option>
        <option value="normal" selected>Knight (normal)</option>
        <option value="hard">Warlord (hard)</option>
      </select></p>
    <div class="btns">
      ${fromMenu && S && !S.over ? '<button class="btn" data-m="resume">Resume</button>' : ''}
      ${!fromMenu && hasSave ? '<button class="btn gold" data-m="cont">Continue campaign</button>' : ''}
      <button class="btn primary" data-m="new">New campaign</button>
      <button class="btn" data-m="help">How to play</button>
    </div>`, {
    resume: null,
    cont: () => startFrom(loadSave()),
    new: () => {
      const diff = ($('#diff') && $('#diff').value) || 'normal';
      if (fromMenu && S && !S.over) {
        showModal('<h2>Abandon this campaign?</h2><p>Your current progress will be lost.</p><div class="btns"><button class="btn primary" data-m="y">Start anew</button><button class="btn" data-m="n">Keep playing</button></div>',
          { y: () => beginNew(diff), n: null });
      } else beginNew(diff);
    },
    help: () => showModal(HELP + '<div class="btns"><button class="btn primary" data-m="back">Back</button></div>', { back: () => showTitle(fromMenu) }),
  });
}

function beginNew(diff) {
  $('#info').innerHTML = '<p class="muted">Drawing the map…</p>';
  setTimeout(() => {
    newGame(diff);
    refresh();
    showModal(HELP + '<div class="btns"><button class="btn primary" data-m="go">To war!</button></div>', { go: null });
  }, 30);
}

function startFrom(saved) {
  if (!saved) { showTitle(false); return; }
  S = saved;
  G = genMap(S.seed);
  UI.selected = null;
  refresh();
  if (S.over) showGameOver();
}

function showGameOver() {
  const won = S.over === 'won';
  clearSave();
  showModal(`
    <h1>${won ? '👑 Victory!' : '💀 Defeat'}</h1>
    <p class="tag">${won ? `All rival crowns are yours after ${S.turn} turns.` : `Your capital has fallen on turn ${S.turn}.`}</p>
    <div class="btns"><button class="btn primary" data-m="again">New campaign</button><button class="btn" data-m="look">View the map</button></div>`,
  { again: () => showTitle(false), look: null });
}

// ======================================================================
// Battle viewer
// ======================================================================
function playBattles(done) {
  if (!battleQueue.length) { done && done(); return; }
  showBattle(battleQueue.shift(), () => playBattles(done));
}

function showBattle(b, cb) {
  const ov = $('#battle');
  ov.classList.remove('hidden');
  $('#bTitle').textContent = b.title;
  const W = 760, H = 360, CX = W / 2;
  const cv = $('#bcv');
  cv.width = W * DPR; cv.height = H * DPR;
  const c = cv.getContext('2d');
  c.setTransform(DPR, 0, 0, DPR, 0, 0);
  const r0 = b.rounds[0], R = b.rounds.length - 1;
  const per = Math.max(1, Math.ceil(Math.max(total(r0.a), total(r0.d)) / 220));
  const ROWS = 26;
  const order = ['catapult', 'archer', 'knight', 'spear', 'militia', 'levy'];
  function makeDots(army, side) {
    const dots = []; let col = 0;
    for (const t of order) {
      const n = Math.ceil((army[t] || 0) / per);
      for (let j = 0; j < n; j++) {
        const cc = col + Math.floor(j / ROWS), rr = j % ROWS;
        const x = side < 0 ? 30 + cc * 11 : W - 30 - cc * 11;
        dots.push({ t, x, y: 50 + rr * 10.5 + (cc % 2) * 5, alive: true, dx: 0, died: 0 });
      }
      col += Math.ceil(n / ROWS);
    }
    return dots;
  }
  const A = makeDots(r0.a, -1), D = makeDots(r0.d, 1);
  const aFront = A.length ? Math.max(...A.map(d => d.x)) : 30;
  const dFront = D.length ? Math.min(...D.map(d => d.x)) : W - 30;
  const aCol = b.att.color, dCol = b.def.color;
  const wallX = dFront - 14;
  $('#bSides').innerHTML = `<span style="color:${aCol}">⚔ ${esc(b.att.name)}</span><span style="color:${dCol}">${esc(b.def.name)} 🛡${b.walls ? ` 🧱${b.walls}` : ''}</span>`;
  $('#bResult').innerHTML = '';
  $('#bSkip').classList.remove('hidden'); $('#bCont').classList.add('hidden');

  const INTRO = 700, RD = 820, END = INTRO + R * RD + 250;
  let applied = 0, raf = 0, finished = false, curA = r0.a, curD = r0.d;
  const start = performance.now();
  let advA = 0, advD = 0;

  function killTo(dots, army, now, offs) {
    for (const t of order) {
      const want = Math.ceil((army[t] || 0) / per);
      const alive = dots.filter(d => d.t === t && d.alive);
      for (let k = alive.length - want; k > 0; k--) {
        const d = alive.splice(Math.floor(Math.random() * alive.length), 1)[0];
        d.alive = false; d.died = now; d.dx = d.x + offs;
      }
    }
  }
  function applyUpTo(r, now) {
    while (applied < r) {
      applied++;
      curA = b.rounds[applied].a; curD = b.rounds[applied].d;
      killTo(A, curA, now, advA); killTo(D, curD, now, advD);
    }
  }
  function shape(t, x, y, col) {
    c.fillStyle = col;
    switch (t) {
      case 'knight': c.fillRect(x - 3, y - 3, 7, 6); c.fillStyle = 'rgba(255,255,255,.55)'; c.fillRect(x - 1, y - 1, 2, 2); break;
      case 'archer': c.beginPath(); c.moveTo(x, y - 3.5); c.lineTo(x + 3.2, y + 3); c.lineTo(x - 3.2, y + 3); c.fill(); break;
      case 'catapult': c.fillStyle = '#6b4a2a'; c.fillRect(x - 4, y - 3, 9, 6); c.fillStyle = col; c.fillRect(x - 1, y - 6, 2, 4); break;
      case 'spear': c.beginPath(); c.arc(x, y, 2.6, 0, 7); c.fill(); c.strokeStyle = '#ddd'; c.lineWidth = 1; c.beginPath(); c.moveTo(x, y + 3); c.lineTo(x, y - 6); c.stroke(); break;
      case 'levy': c.fillStyle = '#9b8f7a'; c.beginPath(); c.arc(x, y, 2.4, 0, 7); c.fill(); break;
      default: c.beginPath(); c.arc(x, y, 2.6, 0, 7); c.fill();
    }
  }
  function draw(t) {
    const g = c.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#5f6f3a'); g.addColorStop(1, '#3d4a24');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    c.fillStyle = 'rgba(0,0,0,.08)';
    for (let i = 0; i < 40; i++) c.fillRect((i * 97) % W, (i * 53) % H, 30, 3);
    const roundF = (t - INTRO) / RD;
    const adv = clamp((roundF - 1) / 1.2, 0, 1);
    const ease = adv * adv * (3 - 2 * adv);
    if (b.walls) { advA = ease * (wallX - 10 - aFront); advD = 0; }
    else { advA = ease * (CX - 8 - aFront); advD = ease * (CX + 8 - dFront); }
    if (b.walls) {
      c.fillStyle = '#7d7569'; c.fillRect(wallX - 4, 30, 10, H - 50);
      c.fillStyle = '#5d564c';
      for (let y = 30; y < H - 20; y += 12) c.fillRect(wallX - 7, y, 16, 6);
    }
    const melee = roundF >= 1 && roundF < R;
    const drawSide = (dots, col, off, dir) => {
      dots.forEach((d, i) => {
        if (d.alive) return;
        const age = (t + start) - d.died;
        c.globalAlpha = age < 600 ? 1 : 0.35;
        c.strokeStyle = age < 600 ? '#b22' : '#2a1f14'; c.lineWidth = 1.4;
        c.beginPath(); c.moveTo(d.dx - 2, d.y - 2); c.lineTo(d.dx + 2, d.y + 2); c.moveTo(d.dx + 2, d.y - 2); c.lineTo(d.dx - 2, d.y + 2); c.stroke();
        c.globalAlpha = 1;
      });
      dots.forEach((d, i) => {
        if (!d.alive) return;
        const stay = d.t === 'archer' || d.t === 'catapult';
        const jitter = melee ? Math.sin(t / 70 + i * 1.7) * 1.8 * ease : 0;
        shape(d.t, d.x + (stay ? off * 0.25 : off) + jitter * dir, d.y + (melee ? Math.cos(t / 90 + i) * 0.8 : 0), col);
      });
    };
    drawSide(A, aCol, advA, 1);
    drawSide(D, dCol, advD, -1);
    // arrows and stones
    const fly = (dots, off, toX, dir, ranged) => {
      const shooters = dots.filter(d => d.alive && (d.t === 'archer' || d.t === 'catapult'));
      if (!shooters.length) return;
      const ph = (roundF % 1 + 1) % 1;
      const n = Math.min(ranged ? 30 : 10, shooters.length);
      for (let k = 0; k < n; k++) {
        const s = shooters[(k * 7) % shooters.length];
        const sx = s.x + off * 0.25, sy = s.y;
        const tx = toX + dir * ((k * 37) % 40), ty = 50 + ((k * 97) % 270);
        const p = (ph + k * 0.037) % 1;
        const x = sx + (tx - sx) * p, y = sy + (ty - sy) * p - Math.sin(Math.PI * p) * 60;
        if (s.t === 'catapult') { c.fillStyle = '#3b332a'; c.beginPath(); c.arc(x, y, 3, 0, 7); c.fill(); }
        else {
          const x2 = sx + (tx - sx) * (p + 0.03), y2 = sy + (ty - sy) * (p + 0.03) - Math.sin(Math.PI * (p + 0.03)) * 60;
          c.strokeStyle = '#f3e8c8'; c.lineWidth = 1; c.beginPath(); c.moveTo(x, y); c.lineTo(x2, y2); c.stroke();
        }
      }
    };
    if (roundF >= 0 && roundF < R) {
      const ranged = roundF < 1;
      fly(A, advA, b.walls ? wallX + 20 : dFront + advD, 1, ranged);
      fly(D, advD, aFront + advA, -1, ranged);
    }
    // counters
    c.font = 'bold 15px Georgia, serif';
    c.fillStyle = 'rgba(0,0,0,.45)'; c.fillRect(0, H - 26, W, 26);
    c.textBaseline = 'middle';
    c.fillStyle = aCol; c.textAlign = 'left'; c.fillText(`${total(curA)} soldiers`, 12, H - 13);
    c.fillStyle = dCol; c.textAlign = 'right'; c.fillText(`${total(curD)} soldiers`, W - 12, H - 13);
    c.fillStyle = '#f1e6cf'; c.textAlign = 'center';
    const rr = clamp(Math.floor(roundF) + 1, 0, R);
    c.fillText(t < INTRO ? 'The armies form up…' : rr === 1 && R > 0 ? 'Volley!' : `Round ${rr} of ${R}`, CX, H - 13);
    c.font = '11px system-ui, sans-serif'; c.fillStyle = 'rgba(255,255,255,.6)';
    c.fillText(`each mark ≈ ${per} soldier${per > 1 ? 's' : ''}`, CX, 16);
  }
  function finish() {
    if (finished) return;
    finished = true;
    cancelAnimationFrame(raf);
    applyUpTo(R, performance.now());
    draw(END);
    const playerWon = b.winner === b.playerSide;
    const big = playerWon ? '<b style="color:#7cc47a">Victory!</b>' : '<b style="color:#e0675a">Defeat</b>';
    const la = total(r0.a) - total(curA), ld = total(r0.d) - total(curD);
    $('#bResult').innerHTML = `${big}<br>${esc(b.summary)}<br><span class="muted">Losses: ${esc(b.att.name)} ${la} · ${esc(b.def.name)} ${ld}</span>`;
    $('#bSkip').classList.add('hidden'); $('#bCont').classList.remove('hidden');
    $('#bCont').focus();
  }
  function frame(now) {
    const t = now - start;
    const r = t < INTRO ? 0 : clamp(Math.floor((t - INTRO) / RD + 0.5), 0, R);
    applyUpTo(r, now);
    draw(t);
    if (t >= END) { finish(); return; }
    raf = requestAnimationFrame(frame);
  }
  $('#bSkip').onclick = finish;
  $('#bCont').onclick = () => { ov.classList.add('hidden'); cb(); };
  raf = requestAnimationFrame(frame);
}

// ======================================================================
// Boot
// ======================================================================
const saved = loadSave();
if (saved) {
  // show the saved map behind the title screen
  S = saved; G = genMap(S.seed); UI.selected = null; refresh();
} else {
  // draw a preview map so the title screen has something behind it
  newGame('normal'); clearSave(); refresh();
}
showTitle(false);

// expose a tiny hook for automated testing
window.__ironCrowns = { get S() { return S; }, get G() { return G; }, endTurn, attack, newRound, aiTurn, power, defPower };
})();
