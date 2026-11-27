# Graphics Phase 5B.1: water surface

Branch `claude/water-5b1`, from `main` at `9b0a223`, which already includes Phase 5A. Phase 5A was confirmed merged (#46) before this branch was created. The branch has not been merged and there is no pull request; it is waiting for review.

**In short:** the water now takes its colour from how deep it is.
- **Shallows:** clear, green-turquoise water where the textured seabed of Phase 5A shows through.
- **Offshore:** the water deepens to a dark blue-green.
- **Shoreline:** the water fades out at the waterline instead of ending in a hard, stepped line, with a faint broken lap of light water.
- **Surface:** small wind ripples drift across it.
- **Highlights:** softer, and the old white glare at low angles is gone.

This is a **shader-only change**. The water sheet, its level, the swell, the seabed, boats, collision, walking, sailing and world generation are all unchanged, and a test checks this. `?water=0` shows the original look on the same world.

What it costs:
- **Download:** +97 KB gzipped.
- **GPU memory:** about +2.9 MB at 720p, for the scene-depth copy.
- **Frame time:** 3–9% at p50 in water scenes on the software renderer.

## 1. Audit: how the water worked

| Part | How it works |
|---|---|
| Water types | `world.gd` has two water terrain types: `WATER` (shallow, sailable by rafts, frozen in winter) and `DEEP` (galleys only). **There are no rivers or a river system**: lakes, bays and channels are all shallow water shaped by the generator's noise. |
| Surface | **One** 640×640 m `PlaneMesh` (96×96 quads, 18,432 triangles) at `WATER_LEVEL` = 0. It follows the player, snapped to 8 m, and casts no shadow. The terrain mesh dips under it, so the shoreline is wherever the terrain crosses y = 0. |
| Seabed | A flat, dark 640 m plane at −3.05 m under the open sea, where no terrain is built. Elsewhere the seabed is the terrain itself, textured since 5A and darkened when wet. |
| Shader | `water.gdshader`: alpha-blended, with a vertex swell of ±0.1 m (two sines). There are three sine ripples for the normal and a fixed colour (shallow and deep mixed 60%) blended towards a sky tint by Fresnel. Alpha is 0.76–0.95, roughness 0.06 and specular 0.7. It has **no depth awareness**: the same colour everywhere, and a hard edge where it meets the shore. |
| Animation | Vertex swell plus moving normal sines. |
| Ice | In winter, each chunk's shallow-water tiles got an ice mesh (`_build_ice`, `StandardMaterial3D`): **one flat square per frozen tile** at y = 0.04. Where you can walk on ice and where boats can't sail is decided by the frozen tiles (`is_ice`, `is_sailable`, `to_3d`), not by the mesh, and that is **untouched**. The ice's **look** was restyled on request after review (§2b). |
| Boats | `boat.gd` places boats at `WATER_LEVEL` with their own bob, independent of the shader. Sailing uses `is_sailable` (terrain type and season). **Untouched.** |
| Collision / navigation | Tile-based: `is_walkable` and `is_sailable` read terrain types, not meshes. **Untouched.** |
| Cost | One draw call for the water and one for the seabed. Alpha blending over the whole visible water. |

**Weaknesses, as rendered (`perf/water/close.jpg`, left):**
1. Uniform colour: shallow and deep water look the same, and the seabed barely shows.
2. Hard, stepped shorelines following the terrain's crossing of y = 0.
3. Strong white sky glare at low angles (roughness 0.06, specular 0.7, plus a sky tint up to 60%), which looked glossy and plastic.
4. Few surface details close up: three regular sines.

## 2. What changed

### `game/shaders/water_detail.gdshader` (new)

The original shader is kept as it was. The new one is used by default.

- **Same geometry and motion.** The vertex function is the original swell, character for character, which the smoke test checks. The water sheet, its size, position, level and shadow setting are as before.
- **Depth from the scene.** The shader reads the scene depth (`hint_depth_texture`). It works out the world position of what lies behind each water pixel and takes the vertical depth of water over it. The depth uses 70% vertical depth and 30% line-of-sight distance through the water, so steep views into deep water stay deep.
  - This **works in the Compatibility renderer**, both native and **in WebGL 2 in the browser** (`perf/water/browser.jpg`).
- **Colour by depth.**
  - Shallow green-turquoise `(0.11, 0.35, 0.34)`, then mid `(0.05, 0.22, 0.28)` by about 1.4 m, then deep blue-green `(0.03, 0.12, 0.19)` between 1 and 4 m.
  - A slow drift over about 55 m makes some areas slightly greener and others slightly bluer.
  - The colours are muted to sit with the medieval palette and the 5A terrain.
- **Transparency by depth.**
  - Opacity follows `1 − exp(−depth / 0.75 m)`, from 0.18 up to 0.94, with a little extra at grazing angles.
  - At the waterline it fades to zero over the last 6 cm, so the shore meets the water softly and the seabed shows through the shallows.
- **Lap at the waterline.** A faint, noise-broken band of light water in the last 12 cm of depth, drifting slowly. It also forms around anything standing in the water: people, rocks and hulls.
- **Ripples.** A tileable 256² ripple normal map is sampled twice:
  - 5.5 m, drifting one way;
  - 13 m, rotated, drifting another way.

  These are laid over the original broad swell normals, softened. The ripples fade to 25% beyond 35–140 m, so far water doesn't shimmer.
- **Highlights.**
  - Roughness 0.10–0.16 (was 0.06) and specular 0.5 (was 0.7).
  - Schlick Fresnel (F0 0.02), with the sky tint capped at 32% (was up to 60%).
  - Highlights are softer and there's no white glare.
- **No reflections are rendered.** The sky sheen is a colour, as before. No screen texture, no planar or SSR reflections, and no extra passes.

### Other files

| File | Change |
|---|---|
| `game/textures/water/ripples_normal.png` (+`.import`) | **New.** 256² tileable ripple normal map (92 KB imported). |
| `game/tools/build_water_textures.gd` | **New.** Generates that map from seamless noise. It's **original work**, with no third-party asset. |
| `game/scripts/world.gd` | `water_detail` flag. `_build_water` picks the shader and sets the ripple map. Nothing else. |
| `game/scripts/main.gd` | Reads `?water=` / `--water=` before `world.generate`. |
| `game/scripts/perf_bench.gd` | Opt-in `?waterbench=1` water scenes, run after all the default scenes so those are unchanged. Also a water spot finder: channels, lake, shore, and village by the water. |
| `game/tools/water_shots.gd` | **New.** Before/after renders. |
| `game/tools/water_timing.gd` | **New.** First-use cost of each water shader. |
| `game/tools/smoke_test.gd` | Phase 5B.1 checks (§6). |
| `perf/water/*` | Screenshots and browser benchmark JSON. |

### 2b. Winter ice without square tiles (added after review)

The original ice was one flat square per frozen tile. That showed three problems in winter (`perf/water/ice.jpg`, left):
- **stepped, square edges** everywhere;
- **dark-blue strips** of water between the ice squares and the shore;
- **blue blotches** where the water's swell (up to +0.1 m) rose through the ice sheet at +0.04 m.

The ice is now drawn differently, with `?water=0` still showing the old ice. Only the look changed: walking on the ice, boats stopping at it, and where it is for gameplay are still the frozen tiles.

- **`world.gd` `_build_ice_smooth`** (used when `water_detail` is on) builds each chunk's ice as a grid:
  - **At the shore:** it also reaches over the land tiles beside frozen water, and over low ground under the ice level near it. So the terrain cuts the ice off along the real, smooth shoreline, with no water strips.
  - **Towards open deep water:** each grid corner carries how much ice is there: the share of non-deep tiles among the 4×4 tiles around it. The edge against unfrozen water is therefore a smooth curve instead of tile steps.
  - It reads the chunk's terrain types once into a small array.
- **`shaders/ice.gdshader`** (new):
  - **Edge:** alpha-scissor, so the ice stays solid and writes depth. It cuts a ragged, noise-broken edge where the ice fades towards open water.
  - **Look:** pale grey-blue ice with clearer, darker patches, drifts of powder snow, faint thin cracks here and there (fading by 45 m), and gentle unevenness from the ripple map. Roughness is 0.22 on ice and 0.85 on snow.
  - **Because the ice writes depth,** the new water shader reads the water above it as zero depth and fades out. The swell no longer shows through the ice, and open water meets the ice edge with the same soft lap as a shore.
- **Cost:**
  - **Ice triangles:** 9,118 → 13,518 (+48%) for the 53 chunks around a frozen lake. The extra quads are the shore fringe, mostly hidden under the ground.
  - **Build time:** building all their ice went from 55 to 119 ms in total, about 1 ms more per chunk. That's spread over chunk builds, a few per frame, and only in chunks with frozen water.
  - **Draw calls:** unchanged, one per chunk with ice.

**Not touched:**
- water, boat and ice physics (where the ice is for walking and sailing);
- `is_walkable` and `is_sailable`;
- water level and placement;
- world generation;
- terrain geometry, collision and shader;
- player movement, NPC AI and combat;
- networking, save/load, Workers and Turso.

## 3. Assets and licences

- **One new texture, `ripples_normal.png`.** It is made by `tools/build_water_textures.gd` from Godot's `FastNoiseLite` seamless noise, so it is original work for this project with no third-party licence.
- **No downloaded assets** are used in this phase. `CREDITS.md` doesn't need a new entry.
- The shallow seabed's look comes from the Phase 5A terrain textures, which are Poly Haven CC0 and already credited.

## 4. Screenshots

These are in `perf/water/`, with the **original on the left and the upgrade on the right**. They were rendered at 1280×720 with the Compatibility renderer under Xvfb (llvmpipe), except `browser.jpg`.

| Sheet | Rows |
|---|---|
| `close.jpg` | Low over the water: small channel, large channel, lake, beach, water by the village, boats off the beach |
| `zoom-near.jpg` / `zoom-normal.jpg` / `zoom-max.jpg` | Same six places from the game camera at zoom 0.55 / 1.0 / 3.2 |
| `seasons-light.jpg` | The beach in summer, autumn, winter (ice) and at night by torchlight |
| `ice.jpg` | Winter: the beach, lake and small channel at zoom 1.0, the large channel at 3.2, and the beach from low down: square tiles → smooth ice |
| `browser.jpg` | The final benchmark frame in Chromium (WebGL 2, ANGLE), old and new: the depth effects work in the browser |

The places come from the seed's own map; the island has no rivers, see §1:
- **"small channel"**: a 3–7 m strip of water running on for at least twice its width;
- **"large channel"**: a 10–24 m strip;
- **"lake"**: a body of water not joined to the sea;
- **"village"**: the benchmark's full village built on the nearest land by the water with room for it.

**What to look at:**
- **Shorelines:** soft, irregular waterlines instead of hard stepped polygons.
- **Shallows:** they show the 5A sand and rock under clear turquoise water.
- **Depth:** deep holes and channels read as darker blue.
- **Low views:** at eye level, ripples instead of white glare.
- **Boats:** the raft, galley and wreck sit in the water with a soft lap around them.
- **Brightness:** mean screen brightness is within about 2% of the original in every shot (beach z1.0: 103.7 → 105.2; lake: 96.6 → 98.9; night: 4.6 → 4.9; winter: 215.7 → 218.0).

## 5. Terrain, seasons and lighting

- **Terrain integration:**
  - There are no gaps at the shore. The water still ends exactly where the terrain crosses the water level; it now fades in over the last few centimetres.
  - No terrain shows through as clipping, because the terrain is underneath by construction, unchanged.
  - The 5A wet-shore darkening and the textured seabed stay visible through the shallows.
  - Checked against sand, grass, forest and rock shores in the shots.
- **Summer and autumn:** the water has no seasonal tint, as before. Autumn leaves fall as before.
- **Winter:** the ice now meets the shore along the ground's own contour. The edge against open deep water is a ragged curve, with no squares, water strips or swell showing through (§2b, `ice.jpg`). A few small steps remain where the terrain's own shoreline is stepped; that's terrain geometry, which this phase doesn't change.
- **Night:** the water is lit by the scene as before. By torchlight the shallows show the seabed.
- **Weather and lighting:** the game has seasonal particles (snow, leaves) and a day/night clock. There is no rain or storm system, and nothing else changes.
- **Not checked:** a low-sun "evening" frame came out fully dark at that clock time in both versions, so it was left out.

## 6. Regression tests

`tools/smoke_test.gd`, run headless:

| Run | Result |
|---|---|
| Default (upgraded water) | **328 ok, 0 FAIL — "Smoke test passed."** |
| `--water=0` | **328 ok, 0 FAIL — passed** |

New checks:
- **Shader in use:** the upgraded run uses `water_detail.gdshader` with its ripple map, and `--water=0` uses `water.gdshader`.
- **Ice material:** the upgraded run's winter ice uses `ice.gdshader`, and `--water=0` keeps the original ice material.
- **Water sheet unchanged:** the water plane (640 m, 96×96), its level, the seabed level, no shadow, and the **identical swell line in both shaders**.
- **Walking and sailing unchanged:** terrain type, `is_walkable`, `is_sailable` (raft and galley) and height over a 320 m area around spawn give the **same hash in both runs: `3082881264`**. The Phase 5A terrain mesh hash is unchanged too: `1279805263`.

Existing checks that pass both ways include:
- shallow water can't be walked on in spring;
- in winter the water freezes and you walk on the ice;
- boats can't sail on ice;
- the ice melts in spring;
- docks: built at the water's edge, not inland, building a raft and a galley;
- boat speeds and the raft are unchanged;
- you board the raft;
- only a galley sails the deep sea;
- you go ashore and the boat stays moored;
- the save remembers your boats and that you're aboard;
- save, reload and resume;
- the ship and wreck models;
- everything from earlier phases.

**Multiplayer:** no networking, Worker or Turso code was touched. The water's look is local rendering and takes no part in sync. There is no multiplayer test harness in the repository, so this wasn't run live.

**Pre-existing engine messages:** `Parameter "material" is null` and the MultiMesh `set_buffer` size message appear in **both** runs. They were already in `main` and come from equipment code; they have nothing to do with water.

## 7. Performance

> **Software renderer.** All frame times are from **Chromium + ANGLE on Mesa llvmpipe**, a CPU rasteriser, at 1280×720. **These are not real-GPU measurements.** llvmpipe exaggerates per-pixel cost, and frame times vary ±10% between runs. Draw calls, triangles and memory are exact. **No real GPU was available for this phase.**

Browser build: `?bench=1&perf=1&waterbench=1`, with and without `&water=0`, run back to back. Data: `perf/water/web-old.json` and `web-new.json`.

| Scene | Draw calls (old → new) | Triangles (old → new) | p50 ms (old → new) | p95 ms (old → new) |
|---|---|---|---|---|
| 1. Small channel ("small river") | 244 → 245 | 1.26 M → 1.26 M | 538 → 582 | 663 → 674 |
| 2. Large channel ("large river") | 152 → 152 | 234 k → 234 k | 292 → 311 | 317 → 327 |
| 3. Lake | 335 → 336 | 1.80 M → 1.77 M | 649 → 698 | 957 → 1030 |
| 4. Shoreline (beach) | 252 → 251 | 985 k → 985 k | 509 → 537 | 530 → 606 |
| 5. Village by the water | 537 → 539 | 2.21 M → 2.21 M | 779 → 805 | 980 → 1165 |
| 6. Boats (galley + 2 rafts) | 284 → 284 | 986 k → 985 k | 468 → 513 | 565 → 550 |
| 7. Max zoom over water | 302 → 303 | 943 k → 946 k | 565 → 594 | 600 → 660 |
| 8. Night by the water (torch) | 433 → 433 | 1.31 M → 1.31 M | 547 → 543 | 1251 → 1243 |

The default scenes, with water mostly off screen, behave as before within noise:

| Scene | p50 ms (old → new) |
|---|---|
| Open field | 712 → 731 |
| Forest | 1059 → 1112 |
| Forest, props hidden | 291 → 274 |
| Village + 30 soldiers | 865 → 876 |
| Night village + 30 | 944 → 918 |
| Area transitions | 819 → 877 |

**Memory:**

| Measure | Old | New | Change |
|---|---|---|---|
| Texture memory | 10.9–12.5 MB | 13.8–15.4 MB | **+2.9 MB** in every scene |
| Video memory | | | the same +2.9 MB |

- **Where the extra memory goes:** almost all of it is the **scene-depth copy** that Godot's Compatibility renderer makes for a shader that reads depth: a screen-sized depth texture. The ripple map is 92 KB.
- **How it scales:** with resolution, about 6.5 MB at 1080p.

**Download:**

| File | Before (`main`, after 5A) | After | Change |
|---|---|---|---|
| `index.pck` raw | 9,878,768 B | 9,981,344 B | **+102.6 KB** |
| `index.pck` gzipped | 8,052,389 B | 8,148,969 B | **+96.6 KB** |

**Shader compilation and first render:**
- **Native**, OpenGL3 on llvmpipe, `tools/water_timing.gd`: the frame that first draws a fresh copy of each shader is 48–64 ms over the frames around it for the original shader, and 28–51 ms for the new one. **No measurable difference.**
- **Browser load to first frame:** 13.4 s → 13.7 s.

**Reading it:**
- **Draw calls and triangles:** unchanged. It is the same single water mesh, with one material.
- **Cost:** per-pixel work on the water: one depth read, two ripple reads, two noise calls and a matrix multiply. Plus the depth copy per frame, which is one full-screen depth blit.
- **On llvmpipe:** water-heavy scenes are 3–9% slower at p50, and night is unchanged.
- **On a real GPU:** this kind of shader and a depth copy are cheap, but this should be confirmed on integrated graphics (§9).

## 8. Known limitations

1. **Depth copy cost and memory.** Reading the scene depth makes the Compatibility renderer copy the depth buffer each frame: about 2.9 MB at 720p and about 6.5 MB at 1080p, plus a blit. That's fine on desktop GPUs, but it should be confirmed on weak or mobile GPUs. `?water=0` turns it off.
2. **The lap line also forms where things cross the water**: hulls, legs, rocks. That's intended and reads as contact, but it shows around a moored galley's hull too.
3. **No real reflections.** Trees, ships and the sky aren't mirrored; the sky sheen is a flat colour. This was ruled out by the brief: no expensive reflection systems.
4. **No flow.** Ripples drift the same way everywhere. The island has no rivers or flow data, so channels don't "run" in one direction.
5. **Transparent objects behind water aren't in the depth copy.** Nothing transparent sits under the water today.
6. **Ice:**
   - **Not exactly the gameplay tiles.** The smooth ice is drawn a little differently from the frozen tiles. Near open deep water, the last frozen tile can look like open water at the ragged edge (and the reverse), by up to about one tile. Walking still follows the tiles.
   - **Stepped shores remain stepped.** Where the terrain's shoreline is itself stepped, the ice edge follows it.
   - **Benchmark:** the web benchmark was run before the ice change; the ice's cost was measured natively (§2b).
7. **Very low sun wasn't checked.** The day/night clock has no visible low-sun frame at the tested time.
8. **Software-renderer numbers only.** No real-GPU measurement was possible here.

## 9. Recommendations for Phase 5B.2

1. **Real-GPU check:** run `?bench=1&waterbench=1` with and without `&water=0` on an integrated GPU (Intel UHD / Apple M1) and on a phone. If the depth copy hurts, a quality setting could fall back to `water.gdshader`.
2. **Ice:** if the one-tile difference at the deep-water edge matters for play, make the walkable edge match the drawn edge, or draw a crack line on the last walkable tile. Also add a winter scene to `?waterbench=1`.
3. **Shore foam on the open sea:** stronger, wave-timed foam only where the shore faces open `DEEP` water (beaches), not on lakes.
4. **Water near boats:** a small wake behind a moving boat, as a decal or particles following the boat, with no physics change.
5. **Reflections, cheaply:** a fixed sky colour gradient or a low-resolution baked sky cubemap for the sheen, still with no real-time reflection pass.
6. **Underwater tint:** tint the seabed by depth (absorption) using the screen texture. That's more correct than alpha blending, but it costs a colour copy, so it should be measured first.

## How to compare

- In the browser: open the game with `?water=0` for the original water. The default is the upgrade.
- Native:

```bash
godot --path last-light/game -- --water=0
```

- Screenshots, rendered once with the flag and once without:

```bash
xvfb-run godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 --script res://tools/water_shots.gd -- --water=0
```

```bash
xvfb-run godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 --script res://tools/water_shots.gd
```
