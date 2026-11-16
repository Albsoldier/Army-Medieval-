// 3D campaign map. Builds terrain, buildings, forests and armies from the
// same province map the rules engine uses, and draws the 2D province texture
// (owners, borders, selection, fog) onto the terrain.
import * as THREE from 'three';
import { MapControls } from 'three/addons/controls/MapControls.js';
import * as M from './models.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const ease = x => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const lerp = (a, b, k) => a + (b - a) * k;
function mulberry(a) {
  return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}

const DAY = [
  { name: 'Dawn', sun: '#ffd2a6', i: 1.35, sky: '#d3bfae', pos: [-70, 30, 20] },
  { name: 'Morning', sun: '#fff1dc', i: 1.8, sky: '#a9cde2', pos: [-45, 60, 35] },
  { name: 'Noon', sun: '#ffffff', i: 2.0, sky: '#9cc8e8', pos: [-10, 80, 30] },
  { name: 'Afternoon', sun: '#fff0d6', i: 1.8, sky: '#a7c5d8', pos: [35, 60, 35] },
  { name: 'Dusk', sun: '#ffab73', i: 1.35, sky: '#d9a585', pos: [70, 28, 20] },
  { name: 'Night', sun: '#9fb2ff', i: 0.7, sky: '#3b4a68', pos: [40, 60, -30] },
];

export function createMap3D(canvas, api) {
  const W = api.MAP_W, H = api.MAP_H;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  const sky = new THREE.Color(DAY[1].sky);
  scene.background = sky;
  scene.fog = new THREE.Fog(sky, 140, 300);
  const camera = new THREE.PerspectiveCamera(40, 1.5, 0.5, 900);
  camera.position.set(0, 70, 60);
  const controls = new MapControls(camera, canvas);
  Object.assign(controls, { enableDamping: true, dampingFactor: 0.12, maxPolarAngle: 1.2, minDistance: 14, maxDistance: 140, screenSpacePanning: false, zoomSpeed: 1.2 });

  const hemi = new THREE.HemisphereLight(0xe2f0ff, 0x5a4a32, 0.85);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xffffff, 1.8);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -62, right: 62, top: 45, bottom: -45, near: 5, far: 260 });
  sun.shadow.bias = -0.0008;
  scene.add(sun, sun.target);

  const texture = new THREE.CanvasTexture(api.baseCanvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = renderer.capabilities.getMaxAnisotropy();

  // sea
  const seaFloor = new THREE.Mesh(new THREE.PlaneGeometry(900, 900).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: '#1f4157' }));
  seaFloor.position.y = -3;
  scene.add(seaFloor);
  const waterGeo = new THREE.PlaneGeometry(400, 300, 80, 60).rotateX(-Math.PI / 2);
  const water = new THREE.Mesh(waterGeo, new THREE.MeshStandardMaterial({ color: '#2d6d8c', transparent: true, opacity: 0.88, roughness: 0.25, metalness: 0.15, flatShading: true }));
  water.position.y = -0.3;
  water.receiveShadow = true;
  scene.add(water);
  const waterBase = Float32Array.from(waterGeo.attributes.position.array);

  const mat = M.stdMaterial();
  const world = new THREE.Group();
  scene.add(world);

  let G = null, heightAt = () => 0, terrain = null;
  let labels = [], provGroups = [], armyGroups = [], blades = [], fires = [];
  const marchers = [];
  let active = true;

  // selection ring + target markers
  const ring = new THREE.Mesh(new THREE.TorusGeometry(3.1, 0.14, 8, 56), new THREE.MeshBasicMaterial({ color: '#ffe27a', fog: false }));
  ring.rotation.x = Math.PI / 2; ring.visible = false;
  scene.add(ring);
  const markerGeo = new THREE.ConeGeometry(0.55, 1.4, 8).rotateX(Math.PI);
  const markerMat = new THREE.MeshBasicMaterial({ color: '#ffd94a', fog: false });
  const markers = [];
  for (let i = 0; i < 16; i++) { const m = new THREE.Mesh(markerGeo, markerMat); m.visible = false; scene.add(m); markers.push(m); }

  const toWorld = (px, py) => [(px - W / 2) / 10, (py - H / 2) / 10];
  const labelPos = i => { const g = G.prov[i]; const [x, z] = toWorld(g.lx, g.ly); return new THREE.Vector3(x, heightAt(x, z), z); };

  // ---------------------------------------------------------------- terrain
  function makeHeight(types) {
    const gw = 250, gh = 160, land = new Float32Array(gw * gh);
    for (let gy = 0; gy < gh; gy++) for (let gx = 0; gx < gw; gx++) {
      let c = 0, n = 0;
      for (let oy = -8; oy <= 8; oy += 4) for (let ox = -8; ox <= 8; ox += 4) {
        const px = clamp(gx * 4 + 2 + ox, 0, W - 1), py = clamp(gy * 4 + 2 + oy, 0, H - 1);
        n++; if (G.ids[py * W + px] >= 0) c++;
      }
      land[gy * gw + gx] = c / n;
    }
    const feats = [];
    G.prov.forEach((g, i) => {
      const [x, z] = toWorld(g.lx, g.ly), t = types[i];
      if (t === 'castle') feats.push([x, z, 1.4, 2.6]);
      else if (t === 'mine') feats.push([x + 3.3, z - 2.5, 3.8, 1.9], [x + 0.6, z - 3.8, 2.7, 1.6], [x - 3.1, z - 2.3, 2.4, 1.7]);
      else if (t === 'forest') feats.push([x, z, 0.8, 4.5]);
      else if (t === 'town') feats.push([x, z, 0.5, 3]);
    });
    return (x, z) => {
      const px = x * 10 + W / 2, py = z * 10 + H / 2;
      const gx = clamp(px / 4 - 0.5, 0, gw - 1.001), gy = clamp(py / 4 - 0.5, 0, gh - 1.001);
      const x0 = Math.floor(gx), y0 = Math.floor(gy), fx = gx - x0, fy = gy - y0;
      const l = lerp(lerp(land[y0 * gw + x0], land[y0 * gw + x0 + 1], fx), lerp(land[(y0 + 1) * gw + x0], land[(y0 + 1) * gw + x0 + 1], fx), fy);
      const sh = G.shade[clamp(Math.round(py), 0, H - 1) * W + clamp(Math.round(px), 0, W - 1)] / 255;
      let h = 0.35 + (sh - 0.5) * 0.25;
      for (const f of feats) {
        const dx = x - f[0], dz = z - f[1], d2 = dx * dx + dz * dz, s2 = f[3] * f[3];
        if (d2 < s2 * 9) h += f[2] * Math.exp(-d2 / (2 * s2));
      }
      return lerp(-2.2, h, ease((l - 0.2) / 0.65));
    };
  }

  function disposeGroup(g) {
    g.traverse(o => {
      if (o.isSprite) { o.material.map && o.material.map.dispose(); o.material.dispose(); }
      if (o.isInstancedMesh) o.dispose();
    });
  }

  function rebuild() {
    G = api.geom();
    const types = G.prov.map((_, i) => api.view(i).type);
    disposeGroup(world);
    world.clear();
    if (terrain) terrain.geometry.dispose();
    heightAt = makeHeight(types);
    const geo = new THREE.PlaneGeometry(W / 10, H / 10, 250, 160).rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, heightAt(pos.getX(i), pos.getZ(i)));
    geo.computeVertexNormals();
    terrain = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: texture, roughness: 1, metalness: 0 }));
    terrain.receiveShadow = true;
    world.add(terrain);

    // forests and scattered trees / rocks
    const rnd = mulberry(G.seed || 1);
    const treePts = [[], []], rockPts = [];
    for (let k = 0; k < 26000 && treePts[0].length + treePts[1].length < 2600; k++) {
      const px = Math.floor(rnd() * W), py = Math.floor(rnd() * H), id = G.ids[py * W + px];
      if (id < 0 || G.border[py * W + px]) continue;
      const t = types[id], g = G.prov[id];
      const dl = Math.hypot(px - g.lx, py - g.ly);
      if (dl < 30) continue;
      const [x, z] = toWorld(px, py);
      if (t === 'forest') treePts[rnd() < 0.75 ? 0 : 1].push([x, z]);
      else if (t === 'mine' && rnd() < 0.08) rockPts.push([x, z]);
      else if (t !== 'farm' && t !== 'town' && rnd() < 0.035) treePts[rnd() < 0.5 ? 0 : 1].push([x, z]);
      else if (t === 'farm' && rnd() < 0.01) treePts[1].push([x, z]);
    }
    const inst = (geo2, pts, sMin, sMax) => {
      if (!pts.length) return;
      const im = new THREE.InstancedMesh(geo2, mat, pts.length);
      im.castShadow = true; im.receiveShadow = true;
      const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), s = new THREE.Vector3(), p = new THREE.Vector3();
      pts.forEach(([x, z], i) => {
        const sc = lerp(sMin, sMax, rnd());
        im.setMatrixAt(i, m.compose(p.set(x, heightAt(x, z) - 0.05, z), q.setFromEuler(e.set(0, rnd() * 6.3, 0)), s.set(sc, sc, sc)));
      });
      world.add(im);
    };
    inst(M.treeGeo(0), treePts[0], 0.9, 1.5);
    inst(M.treeGeo(1), treePts[1], 0.9, 1.4);
    inst(M.rockGeo(), rockPts, 0.8, 2.2);

    // names (static)
    labels = G.prov.map((g, i) => {
      const v = api.view(i);
      const s = textSprite(v.name, { height: 1.05, color: '#2b2118', stroke: 'rgba(250,242,222,0.92)' });
      const p = labelPos(i); s.position.set(p.x, p.y + 0.5, p.z + 2.5);
      world.add(s); return s;
    });
    provGroups = G.prov.map(() => null);
    armyGroups = G.prov.map(() => null);
    blades = []; fires = [];
  }

  // ---------------------------------------------------------------- sprites
  function textSprite(text, o) {
    const c = document.createElement('canvas'), x = c.getContext('2d');
    const font = `${o.bold ? 'bold ' : '600 '}40px ${o.font || 'Georgia, serif'}`;
    x.font = font;
    const w = Math.ceil(x.measureText(text).width) + (o.bg ? 34 : 20);
    c.width = w; c.height = 58;
    x.font = font; x.textAlign = 'center'; x.textBaseline = 'middle';
    if (o.bg) {
      x.fillStyle = o.bg; x.strokeStyle = 'rgba(0,0,0,0.6)'; x.lineWidth = 4;
      x.beginPath(); x.roundRect ? x.roundRect(3, 3, w - 6, 52, 12) : x.rect(3, 3, w - 6, 52); x.fill(); x.stroke();
    }
    if (o.stroke) { x.lineWidth = 8; x.strokeStyle = o.stroke; x.lineJoin = 'round'; x.strokeText(text, w / 2, 31); }
    x.fillStyle = o.color || '#fff'; x.fillText(text, w / 2, 31);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, depthWrite: false, transparent: true, fog: false }));
    sp.renderOrder = 10;
    sp.scale.set(o.height * w / 58, o.height, 1);
    return sp;
  }

  // ---------------------------------------------------------------- per-turn update
  function buildingGeo(v) {
    switch (v.type) {
      case 'castle': return M.castleGeo(v.color, v.walls, v.capital);
      case 'town': return M.townGeo(v.color, v.walls);
      case 'village': return M.villageGeo(v.color, v.walls);
      case 'farm': return M.farmGeo(v.color, v.walls);
      case 'mine': return M.mineGeo(v.color, v.walls);
      default: return M.forestLodgeGeo(v.color, v.walls);
    }
  }

  function update(sel, targets) {
    if (!G) return;
    texture.needsUpdate = true;
    blades = []; fires = [];
    for (let i = 0; i < G.n; i++) {
      const v = api.view(i), p = labelPos(i);
      // building
      const bkey = `${v.type}|${v.color}|${v.walls}|${v.capital}`;
      let pg = provGroups[i];
      if (!pg || pg.userData.key !== bkey) {
        if (pg) world.remove(pg);
        pg = new THREE.Group();
        pg.userData.key = bkey;
        const b = new THREE.Mesh(buildingGeo(v), mat);
        b.castShadow = true; b.receiveShadow = true;
        b.rotation.y = ((i * 2654435761) % 628) / 100;
        pg.add(b);
        if (v.type === 'farm') {
          const bl = new THREE.Mesh(M.bladesGeo(), mat);
          bl.position.set(0.48, 1.6, 0); bl.castShadow = true;
          b.add(bl); pg.userData.blades = bl;
        }
        pg.position.copy(p);
        world.add(pg);
        provGroups[i] = pg;
      }
      if (pg.userData.blades) blades.push(pg.userData.blades);
      // fire & smoke over pillaged land
      if (v.pillaged && !pg.userData.fire) {
        const f = new THREE.Group();
        for (let k = 0; k < 3; k++) {
          const fl = new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.9, 6), new THREE.MeshBasicMaterial({ color: k ? '#ff9a2e' : '#ffd25a' }));
          fl.position.set((k - 1) * 0.5, 0.45, (k % 2) * 0.4);
          f.add(fl);
        }
        for (let k = 0; k < 9; k++) {
          const sm = new THREE.Mesh(new THREE.SphereGeometry(0.35, 6, 5), new THREE.MeshStandardMaterial({ color: '#4a4440', transparent: true, opacity: 0.55, depthWrite: false }));
          sm.userData.seed = k / 9;
          f.add(sm);
        }
        f.position.set(-1.6, 0.2, -1.1);
        pg.add(f); pg.userData.fire = f;
      } else if (!v.pillaged && pg.userData.fire) {
        pg.remove(pg.userData.fire); pg.userData.fire = null;
      }
      if (pg.userData.fire) fires.push(pg.userData.fire);
      // army
      const akey = v.army ? `${v.color}|${v.army}|${v.ready}|${v.general}` : '';
      let ag = armyGroups[i];
      if (!ag || ag.userData.key !== akey) {
        if (ag) { disposeGroup(ag); world.remove(ag); }
        ag = new THREE.Group(); ag.userData.key = akey;
        if (v.army) {
          const tok = new THREE.Mesh(M.armyTokenGeo(v.color, v.general), mat);
          tok.castShadow = true;
          tok.rotation.y = -0.5;
          ag.add(tok);
          const badge = textSprite(`${v.ready ? '⚔ ' : ''}${fmt(v.army)}${v.general ? ' ★' : ''}`, { height: 1.25, bg: v.color, color: '#fff', bold: true, font: 'system-ui, sans-serif' });
          badge.position.set(0, 3.3, 0);
          ag.add(badge);
        }
        const ax = p.x + 2.4, az = p.z + 0.6;
        ag.position.set(ax, heightAt(ax, az), az);
        world.add(ag);
        armyGroups[i] = ag;
      }
    }
    // selection & targets
    if (sel != null) { ring.visible = true; ring.position.copy(labelPos(sel)).add(new THREE.Vector3(0, 0.25, 0)); } else ring.visible = false;
    markers.forEach((m, k) => {
      const t = targets[k];
      m.visible = t !== undefined;
      if (m.visible) { m.position.copy(labelPos(t)); m.userData.baseY = m.position.y + 4.6; }
    });
    // time of day follows the turn
    dayTarget = DAY[(api.turn() - 1) % DAY.length];
  }
  const fmt = n => n >= 10000 ? Math.round(n / 1000) + 'k' : n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n);

  // ---------------------------------------------------------------- camera
  let focusAnim = null;
  function focus(i, instant, towardCentre) {
    if (!G || i == null) return;
    const p = labelPos(i);
    if (towardCentre) { p.x *= 0.65; p.z *= 0.65; p.y = heightAt(p.x, p.z); }
    const offset = camera.position.clone().sub(controls.target);
    if (offset.length() < 1 || instant) offset.set(0, 42, 34);
    const to = { target: p.clone(), pos: p.clone().add(offset) };
    if (instant) { controls.target.copy(to.target); camera.position.copy(to.pos); controls.update(); return; }
    focusAnim = { t0: performance.now(), fromT: controls.target.clone(), fromP: camera.position.clone(), ...to };
  }

  // ---------------------------------------------------------------- marching
  function playMoves(evs, dur = 1100) {
    if (!G || !evs.length) return Promise.resolve();
    return new Promise(resolve => {
      const t0 = performance.now();
      for (const e of evs) {
        const a = labelPos(e.from), bb = labelPos(e.to);
        a.x += 2.4; a.z += 0.6;
        const end = e.kind === 'move' ? new THREE.Vector3(bb.x + 2.4, 0, bb.z + 0.6) : a.clone().lerp(bb, 0.72);
        const m = new THREE.Mesh(M.armyTokenGeo(e.color, !!e.general), mat);
        m.castShadow = true;
        m.rotation.y = Math.atan2(-(end.z - a.z), end.x - a.x);
        world.add(m);
        marchers.push({ m, a, end, t0, dur, resolve: null });
      }
      marchers[marchers.length - 1].resolve = resolve;
    });
  }

  // ---------------------------------------------------------------- picking
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  let down = null;
  function pick(ev) {
    const r = canvas.getBoundingClientRect();
    ndc.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ndc, camera);
    const hit = terrain && ray.intersectObject(terrain)[0];
    if (!hit) return -1;
    const px = Math.floor(hit.uv.x * W), py = Math.floor((1 - hit.uv.y) * H);
    if (px < 0 || py < 0 || px >= W || py >= H) return -1;
    return G.ids[py * W + px];
  }
  canvas.addEventListener('pointerdown', e => { down = { x: e.clientX, y: e.clientY, t: performance.now() }; });
  canvas.addEventListener('pointerup', e => {
    if (!down) return;
    const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
    const quick = performance.now() - down.t < 600;
    down = null;
    if (moved < 7 && quick && e.button === 0) api.onPick(pick(e));
  });
  let hoverT = 0;
  canvas.addEventListener('pointermove', e => {
    const now = performance.now();
    if (down || now - hoverT < 60) return;
    hoverT = now;
    const id = pick(e);
    canvas.style.cursor = id >= 0 ? 'pointer' : 'grab';
    if (api.onHover) api.onHover(id, e);
  });
  canvas.addEventListener('pointerleave', () => api.onHover && api.onHover(-1));

  // ---------------------------------------------------------------- loop
  function resize() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(canvas);

  let dayTarget = DAY[1];
  const sunCol = new THREE.Color(), skyCol = new THREE.Color(), tmp = new THREE.Vector3();
  function frame(now) {
    requestAnimationFrame(frame);
    if (!active || api.paused() || !G) return;
    const t = now * 0.001;
    // day / night
    sunCol.set(dayTarget.sun); skyCol.set(dayTarget.sky);
    sun.color.lerp(sunCol, 0.03); sky.lerp(skyCol, 0.03); scene.fog.color.copy(sky);
    sun.intensity = lerp(sun.intensity, dayTarget.i, 0.03);
    hemi.intensity = lerp(hemi.intensity, dayTarget.name === 'Night' ? 0.45 : 0.85, 0.03);
    tmp.set(...dayTarget.pos);
    sun.position.lerp(tmp.add(controls.target), 0.05);
    sun.target.position.copy(controls.target);
    // water
    const wp = waterGeo.attributes.position;
    for (let i = 0; i < wp.count; i++) {
      const x = waterBase[i * 3], z = waterBase[i * 3 + 2];
      wp.setY(i, Math.sin(x * 0.35 + t * 1.1) * 0.08 + Math.cos(z * 0.4 + t * 0.8) * 0.08);
    }
    wp.needsUpdate = true;
    for (const b of blades) b.rotation.x = t * 1.5;
    for (const f of fires) {
      f.children.forEach((c, k) => {
        if (c.geometry.type === 'ConeGeometry') { c.scale.y = 0.8 + 0.35 * Math.sin(t * 12 + k * 2); }
        else { const life = (t * 0.35 + c.userData.seed) % 1; c.position.set(Math.sin(c.userData.seed * 20) * 0.4 + life * 0.6, 0.6 + life * 3.6, Math.cos(c.userData.seed * 13) * 0.4); c.scale.setScalar(0.6 + life * 1.6); c.material.opacity = 0.55 * (1 - life); }
      });
    }
    if (ring.visible) { const s = 1 + Math.sin(t * 3) * 0.05; ring.scale.set(s, s, s); }
    for (const m of markers) if (m.visible) { m.position.y = m.userData.baseY + Math.sin(t * 4) * 0.35; m.rotation.y = t * 2; }
    // marching hosts
    for (let k = marchers.length - 1; k >= 0; k--) {
      const mr = marchers[k], p = (now - mr.t0) / mr.dur;
      const e = ease(p);
      const x = lerp(mr.a.x, mr.end.x, e), z = lerp(mr.a.z, mr.end.z, e);
      mr.m.position.set(x, heightAt(x, z) + Math.abs(Math.sin(now * 0.02)) * 0.15, z);
      if (p >= 1) { world.remove(mr.m); marchers.splice(k, 1); if (mr.resolve) mr.resolve(); }
    }
    if (focusAnim) {
      const k = ease((now - focusAnim.t0) / 650);
      controls.target.lerpVectors(focusAnim.fromT, focusAnim.target, k);
      camera.position.lerpVectors(focusAnim.fromP, focusAnim.pos, k);
      if (k >= 1) focusAnim = null;
    }
    // keep the camera over the realm
    controls.target.x = clamp(controls.target.x, -W / 20, W / 20);
    controls.target.z = clamp(controls.target.z, -H / 20, H / 20);
    controls.update();
    renderer.render(scene, camera);
  }
  requestAnimationFrame(frame);

  return {
    rebuild, update, focus, playMoves, resize,
    setActive(v) { active = v; if (v) resize(); },
    timeOfDay: () => dayTarget.name,
  };
}
