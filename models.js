// Low-poly models shared by the 3D map and the 3D battles.
// Every model is a single merged BufferGeometry with baked vertex colours,
// so it can be drawn cheaply (and in large numbers with InstancedMesh).
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler();
const _p = new THREE.Vector3(), _s = new THREE.Vector3();

/** Transform a primitive and paint it a flat colour. */
export function P(geo, color, pos = [0, 0, 0], rot = [0, 0, 0], scale = [1, 1, 1]) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  g.applyMatrix4(_m.compose(_p.set(pos[0], pos[1], pos[2]), _q.setFromEuler(_e.set(rot[0], rot[1], rot[2])), _s.set(scale[0], scale[1], scale[2])));
  const c = new THREE.Color(color), n = g.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(a, 3));
  if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
  return g;
}
export const merge = parts => mergeGeometries(parts, false);

const B = (w, h, d) => new THREE.BoxGeometry(w, h, d);
const CY = (rt, rb, h, s = 8) => new THREE.CylinderGeometry(rt, rb, h, s);
const CO = (r, h, s = 8) => new THREE.ConeGeometry(r, h, s);
const SP = (r, w = 8, h = 6) => new THREE.SphereGeometry(r, w, h);

export const COL = {
  skin: '#e0b48a', steel: '#a3acb6', wood: '#7a5230', dark: '#3b2f25', leather: '#6b4a2e',
  stone: '#a49c8e', stoneDark: '#7c7468', plaster: '#ddd0ae', roofRed: '#9c4a32', straw: '#c9a55a',
  horse: '#5a3d26', leaf: '#3f6b35', leafDark: '#2f5530', gold: '#e0b44c',
};
export function shade(hex, f) {
  const c = new THREE.Color(hex); c.multiplyScalar(f); return '#' + c.getHexString();
}

export function stdMaterial(opts = {}) {
  return new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.85, metalness: 0.05, ...opts });
}

const cache = new Map();
const cached = (key, fn) => { if (!cache.has(key)) cache.set(key, fn()); return cache.get(key); };

// ----------------------------------------------------------------------------
// Soldiers (about 1.8 units tall, facing +x)
// ----------------------------------------------------------------------------
function legs() {
  return [P(B(0.22, 0.8, 0.22), COL.dark, [0, 0.4, -0.14]), P(B(0.22, 0.8, 0.22), COL.dark, [0, 0.4, 0.14])];
}
const torso = c => P(B(0.42, 0.75, 0.6), c, [0, 1.17, 0]);
const head = () => P(SP(0.2), COL.skin, [0, 1.75, 0]);

export function soldierGeo(type, team) {
  return cached(`soldier:${type}:${team}`, () => {
    const td = shade(team, 0.65);
    switch (type) {
      case 'spear': return merge([
        ...legs(), torso(team), head(),
        P(CO(0.25, 0.38), COL.steel, [0, 2.0, 0]),
        P(B(0.08, 0.85, 0.6), td, [0.26, 1.15, -0.36]),
        P(CY(0.035, 0.035, 3.4, 5), COL.wood, [0.55, 1.55, 0.3], [0, 0, -1.2]),
        P(CO(0.07, 0.3, 5), COL.steel, [2.15, 2.25, 0.3], [0, 0, -1.2]),
      ]);
      case 'archer': return merge([
        ...legs(), torso(team), head(),
        P(CO(0.26, 0.42), td, [0, 1.98, 0]),
        P(new THREE.TorusGeometry(0.55, 0.035, 4, 10, Math.PI), COL.wood, [0.32, 1.3, 0], [0, 0, -Math.PI / 2]),
        P(CY(0.09, 0.09, 0.6, 6), COL.leather, [-0.26, 1.35, 0.12], [0.35, 0, 0]),
      ]);
      case 'knight': return merge([
        P(B(1.6, 0.7, 0.55), COL.horse, [0, 1.15, 0]),
        P(B(0.15, 0.85, 0.15), COL.dark, [0.6, 0.42, 0.18]), P(B(0.15, 0.85, 0.15), COL.dark, [0.6, 0.42, -0.18]),
        P(B(0.15, 0.85, 0.15), COL.dark, [-0.6, 0.42, 0.18]), P(B(0.15, 0.85, 0.15), COL.dark, [-0.6, 0.42, -0.18]),
        P(B(0.3, 0.75, 0.3), COL.horse, [0.78, 1.6, 0], [0, 0, -0.5]),
        P(B(0.6, 0.26, 0.26), COL.horse, [1.08, 1.92, 0]),
        P(B(1.05, 0.55, 0.64), team, [-0.05, 1.1, 0]),
        P(B(0.4, 0.75, 0.5), team, [-0.1, 1.85, 0]),
        P(SP(0.19), COL.skin, [-0.1, 2.38, 0]),
        P(CY(0.21, 0.21, 0.34, 8), COL.steel, [-0.1, 2.45, 0]),
        P(CY(0.045, 0.045, 3.1, 5), COL.wood, [0.9, 2.0, 0.32], [0, 0, -1.4]),
        P(B(0.08, 0.6, 0.45), td, [0.0, 1.8, -0.36]),
      ]);
      case 'catapult': return merge([
        P(B(2.2, 0.3, 1.2), COL.wood, [0, 0.55, 0]),
        P(CY(0.38, 0.38, 0.15, 10), COL.dark, [0.75, 0.38, 0.66], [Math.PI / 2, 0, 0]),
        P(CY(0.38, 0.38, 0.15, 10), COL.dark, [0.75, 0.38, -0.66], [Math.PI / 2, 0, 0]),
        P(CY(0.38, 0.38, 0.15, 10), COL.dark, [-0.75, 0.38, 0.66], [Math.PI / 2, 0, 0]),
        P(CY(0.38, 0.38, 0.15, 10), COL.dark, [-0.75, 0.38, -0.66], [Math.PI / 2, 0, 0]),
        P(B(0.2, 1.3, 0.2), COL.wood, [0.1, 1.3, 0.42]), P(B(0.2, 1.3, 0.2), COL.wood, [0.1, 1.3, -0.42]),
        P(B(2.4, 0.15, 0.15), COL.wood, [-0.3, 1.75, 0], [0, 0, 0.55]),
        P(B(0.4, 0.22, 0.4), COL.dark, [-1.3, 1.15, 0]),
        P(B(0.5, 0.35, 0.03), team, [1.0, 1.6, 0]),
        P(CY(0.03, 0.03, 1.4, 4), COL.wood, [0.75, 1.3, 0]),
      ]);
      case 'levy': return merge([
        ...legs(), torso('#8a7556'), head(),
        P(SP(0.22, 8, 4), COL.straw, [0, 1.84, 0], [0, 0, 0], [1, 0.45, 1]),
        P(CY(0.035, 0.035, 2.2, 5), COL.wood, [0.35, 1.25, 0.28], [0, 0, -0.25]),
      ]);
      default: return merge([ // militia
        ...legs(), torso(team), head(),
        P(new THREE.SphereGeometry(0.21, 8, 4, 0, Math.PI * 2, 0, Math.PI / 2), COL.leather, [0, 1.8, 0]),
        P(B(0.08, 0.85, 0.08), COL.steel, [0.32, 1.35, 0.28], [0, 0, -0.7]),
        P(CY(0.32, 0.32, 0.08, 10), td, [0.24, 1.15, -0.34], [Math.PI / 2, 0, 0]),
      ]);
    }
  });
}

// ----------------------------------------------------------------------------
// Map pieces (1 unit ≈ 10 map pixels)
// ----------------------------------------------------------------------------
function tower(x, z, h, r, team) {
  return [P(CY(r * 0.9, r, h, 8), COL.stone, [x, h / 2, z]), P(CO(r * 1.25, h * 0.45, 8), team, [x, h + h * 0.22, z])];
}
function flag(x, y, z, team, s = 1) {
  return [P(CY(0.04 * s, 0.04 * s, 1.2 * s, 4), COL.wood, [x, y + 0.6 * s, z]), P(B(0.7 * s, 0.42 * s, 0.04), team, [x + 0.36 * s, y + 1.0 * s, z])];
}
function wallRing(r, h, n, color = COL.stone) {
  const parts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2, len = 2 * r * Math.sin(Math.PI / n) + 0.05;
    parts.push(P(B(len, h, 0.28), color, [Math.cos(a + Math.PI / n) * r * Math.cos(Math.PI / n), h / 2, Math.sin(a + Math.PI / n) * r * Math.cos(Math.PI / n)], [0, -(a + Math.PI / n) + Math.PI / 2, 0]));
  }
  return parts;
}
function house(x, z, h, roof = COL.roofRed, wall = COL.plaster) {
  return [P(B(0.75, h, 0.62), wall, [x, h / 2, z]), P(CO(0.58, 0.5, 4), roof, [x, h + 0.25, z], [0, Math.PI / 4, 0])];
}

export function castleGeo(team, walls, capital) {
  return cached(`castle:${team}:${walls}:${capital}`, () => {
    const s = capital ? 1.15 : 1;
    const parts = [
      P(B(1.5 * s, 2.0 * s, 1.5 * s), COL.stone, [0, 1.0 * s, 0]),
      P(CO(1.15 * s, 1.0 * s, 4), team, [0, 2.5 * s, 0], [0, Math.PI / 4, 0]),
      ...flag(0, 3.0 * s, 0, team, 1.2),
    ];
    const tw = 1.35 * s;
    for (const [x, z] of [[tw, tw], [-tw, tw], [tw, -tw], [-tw, -tw]]) parts.push(...tower(x, z, 1.7 * s, 0.38, team));
    if (walls > 0) {
      const h = 0.6 + 0.25 * walls;
      parts.push(P(B(2.7 * s, h, 0.25), COL.stoneDark, [0, h / 2, tw]), P(B(2.7 * s, h, 0.25), COL.stoneDark, [0, h / 2, -tw]));
      parts.push(P(B(0.25, h, 2.7 * s), COL.stoneDark, [tw, h / 2, 0]), P(B(0.25, h, 2.7 * s), COL.stoneDark, [-tw, h / 2, 0]));
    }
    if (walls >= 3) parts.push(...wallRing(2.6 * s, 0.7, 12, COL.stoneDark));
    return merge(parts);
  });
}

export function townGeo(team, walls) {
  return cached(`town:${team}:${walls}`, () => {
    const parts = [
      ...house(-0.8, -0.5, 0.7), ...house(0.4, -0.8, 0.85, '#7d3b2b'), ...house(0.9, 0.4, 0.65),
      ...house(-0.6, 0.7, 0.8, '#7d3b2b'), ...house(0.1, 1.0, 0.6),
      P(B(0.6, 1.5, 0.6), COL.stone, [-0.1, 0.75, 0]), P(CO(0.45, 1.2, 4), '#5d4b6b', [-0.1, 2.1, 0], [0, Math.PI / 4, 0]),
      ...flag(1.4, 0, -0.9, team, 0.9),
    ];
    if (walls > 0) parts.push(...wallRing(2.0, 0.4 + 0.2 * walls, 14, COL.stoneDark));
    return merge(parts);
  });
}

export function villageGeo(team, walls) {
  return cached(`village:${team}:${walls}`, () => {
    const hut = (x, z, s = 1) => [P(CY(0.36 * s, 0.4 * s, 0.5 * s, 7), '#a0835a', [x, 0.25 * s, z]), P(CO(0.55 * s, 0.55 * s, 7), COL.straw, [x, 0.77 * s, z])];
    const parts = [...hut(-0.6, -0.3), ...hut(0.5, -0.5, 0.9), ...hut(0.1, 0.6, 1.1), P(CY(0.2, 0.2, 0.3, 8), COL.stone, [0.9, 0.15, 0.5]), ...flag(-1.0, 0, 0.6, team, 0.7)];
    if (walls > 0) parts.push(...wallRing(1.7, 0.35 + 0.15 * walls, 16, COL.wood));
    return merge(parts);
  });
}

export function farmGeo(team, walls) {
  return cached(`farm:${team}:${walls}`, () => {
    const parts = [
      P(CY(0.3, 0.45, 1.7, 8), '#e5dcc3', [0, 0.85, 0]), P(CO(0.42, 0.55, 8), '#8b4a2b', [0, 1.97, 0]),
      ...house(1.0, 0.6, 0.55, COL.straw, '#cbb68c'),
      P(CY(0.25, 0.25, 0.35, 8), COL.straw, [-0.9, 0.18, 0.7], [Math.PI / 2, 0, 0]),
      P(CY(0.25, 0.25, 0.35, 8), COL.straw, [-1.3, 0.18, 0.4], [Math.PI / 2, 0, 0]),
      ...flag(-0.9, 0, -0.8, team, 0.7),
    ];
    if (walls > 0) parts.push(...wallRing(1.8, 0.3 + 0.15 * walls, 16, COL.wood));
    return merge(parts);
  });
}
export function bladesGeo() {
  return cached('blades', () => merge([
    P(B(0.07, 2.0, 0.22), '#efe6cf', [0, 0, 0]), P(B(0.07, 0.22, 2.0), '#efe6cf', [0, 0, 0]).rotateX(0),
    P(CY(0.08, 0.08, 0.15, 6), COL.dark, [0, 0, 0], [0, 0, Math.PI / 2]),
  ]));
}

export function mineGeo(team, walls) {
  return cached(`mine:${team}:${walls}`, () => {
    const parts = [
      P(new THREE.DodecahedronGeometry(0.6), '#8a8378', [-0.5, 0.35, -0.3]),
      P(new THREE.DodecahedronGeometry(0.45), '#77706a', [0.6, 0.25, -0.5]),
      P(B(0.9, 0.7, 0.7), COL.wood, [0.2, 0.35, 0.5]), P(B(0.4, 0.45, 0.05), '#1a140f', [0.2, 0.25, 0.86]),
      P(B(0.6, 0.3, 0.4), '#5a4a3a', [-0.8, 0.25, 0.7]),
      P(new THREE.DodecahedronGeometry(0.15), '#e0b44c', [-0.8, 0.45, 0.7]),
      ...flag(1.0, 0, -0.2, team, 0.7),
    ];
    if (walls > 0) parts.push(...wallRing(1.8, 0.3 + 0.15 * walls, 16, COL.wood));
    return merge(parts);
  });
}

export function forestLodgeGeo(team, walls) {
  return cached(`lodge:${team}:${walls}`, () => {
    const parts = [
      P(B(1.1, 0.6, 0.7), '#6b4a2e', [0, 0.3, 0]), P(CO(0.8, 0.5, 4), '#4a3220', [0, 0.85, 0], [0, Math.PI / 4, 0], [1.4, 1, 1]),
      P(CY(0.15, 0.15, 0.9, 6), '#8a6a44', [0.9, 0.15, 0.4], [0, 0, Math.PI / 2]),
      P(CY(0.15, 0.15, 0.9, 6), '#8a6a44', [0.9, 0.42, 0.4], [0, 0, Math.PI / 2]),
      ...flag(-0.8, 0, -0.4, team, 0.7),
    ];
    if (walls > 0) parts.push(...wallRing(1.7, 0.3 + 0.15 * walls, 16, COL.wood));
    return merge(parts);
  });
}

export function treeGeo(kind = 0) {
  return cached(`tree:${kind}`, () => kind === 0
    ? merge([P(CY(0.08, 0.11, 0.5, 5), COL.wood, [0, 0.25, 0]), P(CO(0.5, 1.1, 7), COL.leafDark, [0, 0.95, 0]), P(CO(0.38, 0.85, 7), COL.leaf, [0, 1.4, 0])])
    : merge([P(CY(0.08, 0.11, 0.6, 5), COL.wood, [0, 0.3, 0]), P(new THREE.IcosahedronGeometry(0.5, 0), '#4f7a3a', [0, 0.95, 0])]));
}
export function rockGeo() {
  return cached('rock', () => merge([P(new THREE.DodecahedronGeometry(0.5), '#8c857a', [0, 0.2, 0], [0.3, 0.5, 0], [1, 0.7, 1])]));
}

/** A little marching host: banner bearer plus a few soldiers. */
export function armyTokenGeo(team, withGeneral) {
  return cached(`token:${team}:${withGeneral}`, () => {
    const parts = [];
    const sp = soldierGeo('spear', team), ml = soldierGeo('militia', team);
    const place = (geo, x, z, s = 0.55) => { const g = geo.clone(); g.scale(s, s, s); g.translate(x, 0, z); parts.push(g); };
    place(sp, 0.5, 0); place(sp, 0, 0.55); place(ml, 0, -0.55); place(ml, -0.5, 0.3); place(sp, -0.5, -0.3);
    parts.push(P(CY(0.05, 0.05, 2.4, 4), COL.wood, [0.15, 1.2, 0]), P(B(0.9, 0.6, 0.04), team, [0.62, 2.1, 0]));
    if (withGeneral) { const k = soldierGeo('knight', team).clone(); k.scale(0.6, 0.6, 0.6); k.translate(1.0, 0, 0.6); parts.push(k); parts.push(P(SP(0.12), COL.gold, [0.95, 1.65, 0.6])); }
    return merge(parts);
  });
}
