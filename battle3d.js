// 3D battle viewer. Replays a battle that the rules engine has already
// resolved (round-by-round soldier counts) as a cinematic Three.js scene.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import * as M from './models.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const ease = x => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const lerp = (a, b, k) => a + (b - a) * k;
const total = a => { let s = 0; for (const t in a) s += a[t] || 0; return s; };
const TYPES = ['spear', 'militia', 'levy', 'knight', 'archer', 'catapult'];
const INTRO = 2200, RD = 1400;

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler();
const _p = new THREE.Vector3(), _s = new THREE.Vector3(1, 1, 1), _zero = new THREE.Vector3(0, 0, 0);
const _v = new THREE.Vector3(), _x = new THREE.Vector3(1, 0, 0);
const WHITE = new THREE.Color(1, 1, 1), DEAD = new THREE.Color(0.42, 0.38, 0.36);

function groundH(x, z) {
  return 0.35 * Math.sin(x * 0.11 + 1) * Math.cos(z * 0.09) + 0.2 * Math.sin(x * 0.31 + z * 0.23)
    + Math.max(0, Math.abs(z) - 46) * 0.18 + Math.max(0, Math.abs(x) - 78) * 0.14;
}

function mulberry(a) {
  return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}

export function createBattle3D(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const camera = new THREE.PerspectiveCamera(42, 16 / 9, 0.5, 700);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true; controls.maxPolarAngle = 1.45; controls.minDistance = 10; controls.maxDistance = 170;
  let userCam = false;
  controls.addEventListener('start', () => { userCam = true; });
  let current = null, raf = 0;

  function resize() {
    const w = canvas.clientWidth || 800, h = canvas.clientHeight || 450;
    renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', () => { if (current) resize(); });

  function frame(now) {
    if (!current) return;
    current.update(now);
    if (userCam) controls.update();
    renderer.render(current.scene, camera);
    raf = requestAnimationFrame(frame);
  }

  function play(b, hooks) {
    stop();
    userCam = false;
    resize();
    current = buildBattle(b, hooks, camera, controls, () => userCam);
    raf = requestAnimationFrame(frame);
    return { skip: () => current && current.skip() };
  }
  function stop() {
    cancelAnimationFrame(raf);
    if (current) { current.dispose(); current = null; }
    renderer.renderLists.dispose();
  }
  return { play, stop };
}

function buildBattle(b, hooks, camera, controls, isUserCam) {
  const rnd = mulberry(b.rounds.length * 7919 + total(b.rounds[0].a) * 31 + total(b.rounds[0].d));
  const scene = new THREE.Scene();
  const own = []; // per-battle geometries & materials to dispose
  const keep = x => { own.push(x); return x; };
  const sky = new THREE.Color('#a8c6d8');
  scene.background = sky;
  scene.fog = new THREE.Fog(sky, 110, 260);
  scene.add(new THREE.HemisphereLight(0xe6f2ff, 0x5b4a30, 0.95));
  const sun = new THREE.DirectionalLight(0xfff0d8, 1.8);
  sun.position.set(-35, 70, 45);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -70, right: 70, top: 55, bottom: -55, near: 10, far: 200 });
  sun.shadow.bias = -0.0006;
  scene.add(sun);

  const terrain = b.terrain || 'farm';
  const walls = b.walls || 0;
  const WX = 10, HW = 2.2 + 0.6 * walls;

  // ---------------- ground ----------------
  const gg = keep(new THREE.PlaneGeometry(220, 150, 110, 75).rotateX(-Math.PI / 2));
  const pos = gg.attributes.position, cols = new Float32Array(pos.count * 3);
  const base = {
    forest: [0.24, 0.37, 0.17], mine: [0.44, 0.41, 0.35], castle: [0.4, 0.45, 0.24],
    town: [0.42, 0.47, 0.25], village: [0.37, 0.49, 0.22], farm: [0.38, 0.5, 0.22],
  }[terrain] || [0.36, 0.48, 0.22];
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), z = pos.getZ(i);
    pos.setY(i, groundH(x, z));
    let c = base.slice();
    if (terrain === 'farm' && Math.abs(z) > 22 && Math.floor((x + 200) / 7) % 2) c = [0.72, 0.63, 0.3];
    if ((terrain === 'castle' || terrain === 'town' || terrain === 'village') && Math.abs(z) < 2.6) c = [0.5, 0.42, 0.3];
    if (terrain === 'mine' && rnd() < 0.3) c = [0.52, 0.5, 0.46];
    const n = (rnd() - 0.5) * 0.06;
    cols[i * 3] = c[0] + n; cols[i * 3 + 1] = c[1] + n; cols[i * 3 + 2] = c[2] + n * 0.5;
  }
  gg.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  gg.computeVertexNormals();
  const ground = new THREE.Mesh(gg, keep(M.stdMaterial({ flatShading: true, roughness: 1 })));
  ground.receiveShadow = true;
  scene.add(ground);

  const mat = keep(M.stdMaterial());

  // ---------------- scenery ----------------
  const scatter = (geo, n, ok, scaleMin, scaleMax) => {
    const im = new THREE.InstancedMesh(geo, mat, n);
    im.castShadow = true; im.receiveShadow = true;
    for (let i = 0; i < n; i++) {
      let x, z, tries = 0;
      do { x = (rnd() - 0.5) * 210; z = (rnd() - 0.5) * 140; } while (!ok(x, z) && ++tries < 40);
      const s = lerp(scaleMin, scaleMax, rnd());
      im.setMatrixAt(i, _m.compose(_p.set(x, groundH(x, z) - 0.05, z), _q.setFromEuler(_e.set(0, rnd() * 6.3, 0)), _v.set(s, s, s)));
    }
    scene.add(im);
  };
  const edge = (x, z) => Math.abs(z) > 38 || Math.abs(x) > 72;
  const nTrees = terrain === 'forest' ? 420 : terrain === 'farm' ? 60 : 110;
  scatter(M.treeGeo(0), nTrees, (x, z) => edge(x, z) || (terrain === 'forest' && Math.abs(z) > 30), 2.2, 3.6);
  scatter(M.treeGeo(1), Math.round(nTrees * 0.4), edge, 2.0, 3.2);
  if (terrain === 'mine') scatter(M.rockGeo(), 90, (x, z) => Math.abs(z) > 24 || Math.abs(x) > 60, 1.5, 5);
  // the place being fought over, in the background behind the defenders
  const homeGeo = {
    castle: M.castleGeo(b.def.color, walls, true), town: M.townGeo(b.def.color, 0), village: M.villageGeo(b.def.color, 0),
    farm: M.farmGeo(b.def.color, 0), mine: M.mineGeo(b.def.color, 0), forest: M.forestLodgeGeo(b.def.color, 0),
  }[terrain];
  if (homeGeo) {
    const home = new THREE.Mesh(homeGeo, mat);
    home.scale.setScalar(3.4); home.position.set(62, groundH(62, 0), 0); home.rotation.y = -Math.PI / 2;
    home.castShadow = true; scene.add(home);
  }

  // ---------------- walls ----------------
  const segs = [];
  if (walls) {
    const stone = keep(new THREE.MeshStandardMaterial({ color: '#a39b8d', roughness: 0.95, flatShading: true }));
    const segGeo = keep(new THREE.BoxGeometry(1.8, 1, 4.02));
    const gate = keep(new THREE.MeshStandardMaterial({ color: '#5a3d22', roughness: 0.9 }));
    for (let z = -38; z < 38; z += 4) {
      const isGate = Math.abs(z + 2) < 1;
      const m = new THREE.Mesh(segGeo, isGate ? gate : stone);
      m.scale.y = HW; m.position.set(WX, HW / 2, z + 2);
      m.castShadow = true; m.receiveShadow = true;
      scene.add(m);
      segs.push({ m, hp: 1, z: z + 2 });
    }
    const towerGeo = keep(new THREE.CylinderGeometry(1.5, 1.7, HW + 1.8, 10));
    const roofGeo = keep(new THREE.ConeGeometry(2.0, 2.2, 10));
    const roofMat = keep(new THREE.MeshStandardMaterial({ color: b.def.color, roughness: 0.8, flatShading: true }));
    for (let z = -36; z <= 36; z += 12) {
      const t = new THREE.Mesh(towerGeo, stone); t.position.set(WX, (HW + 1.8) / 2, z); t.castShadow = true; scene.add(t);
      const r = new THREE.Mesh(roofGeo, roofMat); r.position.set(WX, HW + 1.8 + 1.1, z); r.castShadow = true; scene.add(r);
    }
  }

  // ---------------- armies ----------------
  const r0 = b.rounds[0], R = b.rounds.length - 1;
  const per = Math.max(1, Math.ceil(Math.max(total(r0.a), total(r0.d)) / 350));
  const sides = [
    { s: -1, color: b.att.color, army: r0.a, figs: [], meshes: {} },
    { s: 1, color: b.def.color, army: r0.d, figs: [], meshes: {} },
  ];
  for (const side of sides) {
    const s = side.s, isDef = s === 1;
    const front = isDef ? (walls ? WX + 2.8 : 10) : (walls ? -18 : -10);
    const counts = {}; for (const t of TYPES) counts[t] = Math.ceil((side.army[t] || 0) / per);
    const add = (type, x, z, extra = {}) => {
      const y = extra.onWall ? HW : groundH(x, z);
      side.figs.push({ type, s, hx: x, hz: z, hy: y, rotY: isDef ? Math.PI : 0, alive: true, deathT: 0, phase: rnd() * 6.28, dx: 0, dy: 0, dz: 0, ...extra });
    };
    // infantry block
    const inf = [];
    for (const t of ['spear', 'militia', 'levy']) for (let i = 0; i < counts[t]; i++) inf.push(t);
    const COLS = 26;
    inf.forEach((t, j) => {
      const rank = Math.floor(j / COLS), col = j % COLS;
      const inRow = Math.min(COLS, inf.length - rank * COLS);
      add(t, front + s * rank * 1.3 + (rnd() - 0.5) * 0.25, (col - (inRow - 1) / 2) * 1.2 + (rnd() - 0.5) * 0.25);
    });
    const infRanks = Math.ceil(inf.length / COLS);
    // cavalry wings
    for (let j = 0; j < counts.knight; j++) {
      const wing = j % 2 ? -1 : 1, idx = Math.floor(j / 2);
      const rank = Math.floor(idx / 5), col = idx % 5;
      add('knight', front + s * rank * 2.6, wing * (18.5 + col * 1.7));
    }
    // archers
    let archRanks = 0;
    let onWall = isDef && walls ? Math.min(counts.archer, 120) : 0;
    for (let j = 0; j < onWall; j++) {
      const row = j % 2, idx = Math.floor(j / 2), cols = Math.ceil(onWall / 2);
      add('archer', WX + (row - 0.5) * 0.8, (idx - (cols - 1) / 2) * (Math.min(72 / cols, 1.3)), { onWall: true });
    }
    const groundArchers = counts.archer - onWall;
    for (let j = 0; j < groundArchers; j++) {
      const rank = Math.floor(j / COLS), col = j % COLS, inRow = Math.min(COLS, groundArchers - rank * COLS);
      add('archer', front + s * (infRanks + 1.5 + rank) * 1.25, (col - (inRow - 1) / 2) * 1.2);
    }
    archRanks = Math.ceil(groundArchers / COLS);
    for (let j = 0; j < counts.catapult; j++) {
      const rank = Math.floor(j / 8), col = j % 8, inRow = Math.min(8, counts.catapult - rank * 8);
      add('catapult', front + s * ((infRanks + archRanks + 3.5) * 1.25 + rank * 4), (col - (inRow - 1) / 2) * 4.2);
    }
    // instanced meshes, one per unit type
    for (const t of TYPES) {
      const list = side.figs.filter(f => f.type === t);
      if (!list.length) continue;
      const im = new THREE.InstancedMesh(M.soldierGeo(t, side.color), mat, list.length);
      im.castShadow = true;
      im.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      list.forEach((f, i) => { f.mesh = im; f.i = i; im.setColorAt(i, WHITE); });
      side.meshes[t] = im;
      scene.add(im);
    }
    side.front = front;
  }
  const [A, D] = sides;
  const attContact = walls ? WX - 1.6 : -0.9, defContact = 0.9;

  // ---------------- projectiles & dust ----------------
  const arrowGeo = keep(M.merge([
    M.P(new THREE.CylinderGeometry(0.035, 0.035, 1.3, 4), '#d9c8a0', [0, 0, 0], [0, 0, Math.PI / 2]),
    M.P(new THREE.ConeGeometry(0.08, 0.25, 4), '#555', [0.75, 0, 0], [0, 0, -Math.PI / 2]),
  ]));
  const arrows = new THREE.InstancedMesh(arrowGeo, mat, 600);
  const stoneGeo = keep(new THREE.DodecahedronGeometry(0.45));
  const stones = new THREE.InstancedMesh(stoneGeo, keep(new THREE.MeshStandardMaterial({ color: '#4a4038', flatShading: true })), 80);
  for (const im of [arrows, stones]) {
    im.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    im.frustumCulled = false;
    for (let i = 0; i < im.count; i++) im.setMatrixAt(i, _m.makeScale(0, 0, 0));
    scene.add(im);
  }
  const shots = [];
  const free = { arrow: [...Array(600).keys()], stone: [...Array(80).keys()] };
  const NDUST = 320;
  const dustGeo = keep(new THREE.BufferGeometry());
  const dustPos = new Float32Array(NDUST * 3), dustSeed = new Float32Array(NDUST);
  for (let i = 0; i < NDUST; i++) { dustSeed[i] = rnd(); dustPos[i * 3 + 1] = -50; }
  dustGeo.setAttribute('position', new THREE.BufferAttribute(dustPos, 3));
  const dust = new THREE.Points(dustGeo, keep(new THREE.PointsMaterial({ color: '#c9b08a', size: 1.6, transparent: true, opacity: 0.4, depthWrite: false })));
  dust.frustumCulled = false;
  scene.add(dust);

  function figPos(f) {
    if (!f.alive) return _v.set(f.dx, f.dy, f.dz);
    return _v.set(f.x ?? f.hx, f.y ?? f.hy, f.z ?? f.hz);
  }
  function spawn(kind, from, to, t0, dur, h, onHit) {
    const slot = free[kind].pop();
    if (slot === undefined) return;
    shots.push({ kind, slot, sx: from.x, sy: from.y, sz: from.z, ex: to.x, ey: to.y, ez: to.z, t0, dur, h, onHit });
  }
  function volley(side, enemy, density, now) {
    const targets = enemy.figs.filter(f => f.alive);
    if (!targets.length) return;
    targets.sort((a, b2) => Math.abs(a.x ?? a.hx) - Math.abs(b2.x ?? b2.hx));
    const shooters = side.figs.filter(f => f.alive && f.type === 'archer');
    let n = 0;
    for (const f of shooters) {
      if (rnd() > density || n++ > 260) continue;
      const tg = targets[Math.floor(rnd() * rnd() * targets.length)];
      const from = figPos(f).clone(); from.y += 1.6;
      const to = figPos(tg).clone(); to.x += (rnd() - 0.5) * 2; to.z += (rnd() - 0.5) * 2; to.y += 0.5;
      const dist = from.distanceTo(to);
      spawn('arrow', from, to, now + rnd() * 550, 850 + dist * 9, 4 + dist * 0.18);
    }
    for (const f of side.figs.filter(c => c.alive && c.type === 'catapult')) {
      const from = figPos(f).clone(); from.y += 1.8;
      let to, hit = null;
      if (side.s === -1 && segs.length) {
        const sg = segs[Math.floor(rnd() * segs.length)];
        to = new THREE.Vector3(WX - 0.6, HW * sg.hp * 0.7, sg.z + (rnd() - 0.5) * 3);
        hit = () => { sg.hp = Math.max(0.35, sg.hp - 0.16); sg.m.scale.y = HW * sg.hp; sg.m.position.y = HW * sg.hp / 2; puff(to); };
      } else {
        to = figPos(targets[Math.floor(rnd() * targets.length)]).clone();
        hit = () => puff(to);
      }
      const dist = from.distanceTo(to);
      spawn('stone', from, to, now + rnd() * 400, 1300 + dist * 6, 10 + dist * 0.25, hit);
    }
  }
  const puffs = [];
  function puff(at) { puffs.push({ x: at.x, y: at.y, z: at.z, t: performance.now() }); }

  // ---------------- casualties ----------------
  let applied = 0, curA = r0.a, curD = r0.d;
  function killTo(side, army, now, ranged) {
    for (const t of TYPES) {
      const want = Math.ceil((army[t] || 0) / per);
      const alive = side.figs.filter(f => f.type === t && f.alive);
      if (!ranged) alive.sort((a, c) => Math.abs(a.x ?? a.hx) - Math.abs(c.x ?? c.hx));
      for (let k = alive.length - want; k > 0; k--) {
        const idx = ranged ? Math.floor(rnd() * alive.length) : Math.floor(rnd() * rnd() * alive.length);
        const f = alive.splice(idx, 1)[0];
        f.alive = false; f.deathT = now + rnd() * 300;
        f.dx = f.x ?? f.hx; f.dy = f.y ?? f.hy; f.dz = f.z ?? f.hz;
        if (f.onWall) f.fallOff = true;
        f.mesh.setColorAt(f.i, DEAD); f.mesh.instanceColor.needsUpdate = true;
      }
    }
  }
  function applyUpTo(r, now) {
    while (applied < r) {
      applied++;
      curA = b.rounds[applied].a; curD = b.rounds[applied].d;
      const ranged = b.rounds[applied].ranged;
      killTo(A, curA, now, ranged); killTo(D, curD, now, ranged);
    }
    hud();
  }
  let lastHud = '';
  function hud(label) {
    const t = performance.now() - start;
    const rr = clamp(Math.floor((t - INTRO) / RD) + 1, 0, R);
    const lbl = label || (finished ? 'The field falls silent' : t < INTRO ? 'The armies form up…' : rr === 1 && b.rounds[1] && b.rounds[1].ranged ? 'Loose arrows!' : `Round ${rr} of ${R}`);
    const key = `${total(curA)}|${total(curD)}|${lbl}`;
    if (key === lastHud) return;
    lastHud = key;
    hooks.hud(total(curA), total(curD), lbl, per);
  }

  // ---------------- update loop ----------------
  let start = performance.now(), spawnedRounds = 0, finished = false, skipped = false;
  const END = INTRO + R * RD + 700;

  function placeFigure(f, t, now, pInf, pKn) {
    let x = f.hx, y = f.hy, z = f.hz, rx = 0, rz = 0;
    if (!f.alive && now >= f.deathT) {
      const k = clamp((now - f.deathT) / 450, 0, 1);
      if (f.fallOff) { // archers tumble off the wall
        x = f.dx + k * 1.6; y = lerp(f.dy, groundH(f.dx + 1.6, f.dz) + 0.25, k * k);
      } else { x = f.dx; y = f.dy + 0.22 * k; }
      z = f.dz; rz = k * Math.PI / 2 * 0.95;
    } else if (!f.alive) {
      x = f.dx; y = f.dy; z = f.dz;
    } else {
      const s = f.s, isDef = s === 1;
      const moves = !f.onWall && f.type !== 'archer' && f.type !== 'catapult' && !(isDef && walls);
      if (moves) {
        const side = isDef ? D : A;
        const contact = isDef ? defContact : attContact;
        const p = f.type === 'knight' ? pKn : pInf;
        x += (contact - side.front) * p;
        if (p > 0 && p < 1) y += Math.abs(Math.sin(now * (f.type === 'knight' ? 0.022 : 0.014) + f.phase)) * (f.type === 'knight' ? 0.35 : 0.12);
        if (p >= 0.98 && !finished) x += Math.sin(now * 0.009 + f.phase) * 0.35;
        y = Math.max(y, groundH(x, z));
      } else if (isDef && walls && !f.onWall && f.type !== 'archer' && f.type !== 'catapult' && pInf > 0.9 && !finished) {
        x += Math.sin(now * 0.009 + f.phase) * 0.25;
      }
      f.x = x; f.y = y; f.z = z;
    }
    _q.setFromEuler(_e.set(rx, f.rotY, rz, 'YXZ'));
    f.mesh.setMatrixAt(f.i, _m.compose(_p.set(x, y, z), _q, _s));
  }

  function update(now) {
    let t = now - start;
    // spawn volleys as each round begins
    const curRound = t < INTRO ? 0 : clamp(Math.floor((t - INTRO) / RD) + 1, 0, R);
    while (spawnedRounds < curRound) {
      spawnedRounds++;
      if (!skipped) {
        const ranged = b.rounds[spawnedRounds].ranged;
        volley(A, D, ranged ? 1 : 0.3, now);
        volley(D, A, ranged ? 1 : 0.3, now);
      }
    }
    // casualties land a little after each round begins
    const due = t < INTRO ? 0 : clamp(Math.floor((t - INTRO - RD * 0.55) / RD) + 1, 0, R);
    if (due > applied) applyUpTo(due, now);
    if (!finished && t >= END) finish();
    if (!finished) hud();

    const pInf = ease((t - INTRO - RD * 0.9) / (RD * 1.4));
    const pKn = ease((t - INTRO - RD * 0.6) / (RD * 0.95));
    for (const side of sides) {
      for (const f of side.figs) placeFigure(f, t, now, pInf, pKn);
      for (const k in side.meshes) side.meshes[k].instanceMatrix.needsUpdate = true;
    }
    // projectiles
    for (let i = shots.length - 1; i >= 0; i--) {
      const sh = shots[i], im = sh.kind === 'arrow' ? arrows : stones;
      const p = (now - sh.t0) / sh.dur;
      if (p < 0) { im.setMatrixAt(sh.slot, _m.makeScale(0, 0, 0)); continue; }
      if (p >= 1) {
        im.setMatrixAt(sh.slot, _m.makeScale(0, 0, 0));
        free[sh.kind].push(sh.slot); shots.splice(i, 1);
        if (sh.onHit) sh.onHit();
        continue;
      }
      const x = lerp(sh.sx, sh.ex, p), y = lerp(sh.sy, sh.ey, p) + sh.h * 4 * p * (1 - p), z = lerp(sh.sz, sh.ez, p);
      _v.set(sh.ex - sh.sx, (sh.ey - sh.sy) + sh.h * 4 * (1 - 2 * p), sh.ez - sh.sz).normalize();
      _q.setFromUnitVectors(_x, _v);
      im.setMatrixAt(sh.slot, _m.compose(_p.set(x, y, z), _q, _s));
    }
    arrows.instanceMatrix.needsUpdate = true; stones.instanceMatrix.needsUpdate = true;
    // dust over the melee and where stones land
    const fighting = pInf > 0.9 && !finished;
    for (let i = 0; i < NDUST; i++) {
      const sd = dustSeed[i];
      const life = ((now * 0.00035 + sd * 7) % 1);
      if (i < 240) {
        if (!fighting) { dustPos[i * 3 + 1] = -50; continue; }
        const cx = walls ? WX - 2 : 0;
        dustPos[i * 3] = cx + (sd - 0.5) * 6 + Math.sin(sd * 40) * 1.5;
        dustPos[i * 3 + 1] = 0.3 + life * 4;
        dustPos[i * 3 + 2] = (((sd * 977) % 1) - 0.5) * 34;
      } else {
        const pf = puffs[(i - 240) % Math.max(1, puffs.length)];
        if (!pf || now - pf.t > 1500) { dustPos[i * 3 + 1] = -50; continue; }
        const k = (now - pf.t) / 1500;
        dustPos[i * 3] = pf.x + (sd - 0.5) * 4 * (0.5 + k);
        dustPos[i * 3 + 1] = pf.y + k * 3 + sd;
        dustPos[i * 3 + 2] = pf.z + (((sd * 977) % 1) - 0.5) * 4 * (0.5 + k);
      }
    }
    dustGeo.attributes.position.needsUpdate = true;

    // camera
    if (!isUserCam()) {
      let px, py, pz, tx, tz;
      if (t < INTRO) {
        const k = ease(t / INTRO);
        px = lerp(-85, -6, k); py = lerp(38, 30, k); pz = lerp(26, 68, k); tx = lerp(-12, 0, k); tz = 0;
      } else {
        const a = 0.38 * Math.sin((t - INTRO) * 0.00017);
        px = Math.sin(a) * 68 - 6 * Math.cos(a); py = 30 - 3 * Math.sin(t * 0.0002); pz = Math.cos(a) * 68; tx = walls ? 3 : 0; tz = 0;
      }
      camera.position.set(px, py, pz);
      controls.target.set(tx, 1, tz);
      camera.lookAt(controls.target);
    }
  }

  function finish() {
    if (finished) return;
    applyUpTo(R, performance.now());
    finished = true;
    hud();
    hooks.done();
  }

  return {
    scene,
    update,
    skip() {
      if (finished) return;
      skipped = true;
      for (const sh of shots) { (sh.kind === 'arrow' ? arrows : stones).setMatrixAt(sh.slot, _m.makeScale(0, 0, 0)); free[sh.kind].push(sh.slot); }
      shots.length = 0;
      start = performance.now() - END;
      spawnedRounds = R;
      finish();
    },
    dispose() {
      for (const x of own) x.dispose();
      scene.traverse(o => { if (o.isInstancedMesh) o.dispose(); });
    },
  };
}
