# Graphics Phase 5A: terrain and landscape

Branch `claude/terrain-5a`, from `main` at `b8a953a`. It has not been merged and there is no pull request. It is waiting for review.

**In short:** the ground now uses real, photo-sourced textures for grass, forest floor, dirt, sand and rock. These are laid into the game's own colour palette, so the art direction, seasons, snow, wet shore and night all behave as before. Edges between ground types no longer follow the 1 m tile grid. Close up, the ground has relief. Tiling is not visible at maximum zoom.

This is a **shader-only change**:
- The terrain data, heights, meshes, collision, world generation and vegetation placement are byte-for-byte unchanged, and a test checks this.
- `?terrain=0` shows the original look on the same world.
- Cost:
  - **+0.92 MB** to the gzipped download;
  - **+1.1 MB** of GPU texture memory;
  - a heavier ground fragment shader: on the software renderer, the scene that isolates the terrain is about 46% slower to draw, and full scenes are 3–7% slower at p50.

## 1. Audit: what the terrain was

| Area | Finding |
|---|---|
| Generation | `world.gd` builds tile data from noise (continent, height, moisture). Deterministic per seed. Left untouched. |
| Meshes | 32×32 m chunks, VIEW=3, so 49 chunks around the player, built a few per frame. One smooth surface per chunk with shared corners and smooth normals. Vertex COLOR carries blend weights: r = sand/water, g = forest, b = rock, and grass is the remainder. **No UVs, no tangents.** |
| Material | One `ShaderMaterial` (`terrain.gdshader`) shared by every chunk. Palette colours tinted by value noise, plus dry patches, bare earth, slope→rock, the seasons (snow, autumn, summer), and darker wet ground at the waterline. |
| Textures | **None.** All of the ground's colour came from noise. |
| Vegetation | Trees, bushes, rocks and grass clumps are separate prop chunks (MultiMesh). They are placed from tile data, not from the material. |
| Transitions | Blend weights are per vertex on a 1 m grid, so with only `smoothstep` on them, sand/grass/forest borders showed **stair-step edges along the tile grid**. |
| Collision | Grid-based (`height_at`, `terrain_at`). It doesn't use the render mesh. |
| Culling / LOD | Chunks outside the view are hidden. There is no terrain LOD, and none is needed at this size. |

**Biggest weaknesses, in order:**
1. No surface detail anywhere. Close up, grass, dirt and rock are smooth gradients, which looks like a toy.
2. Blocky, grid-aligned transitions between ground types.
3. Rock and sand are pale and flat. Rock looks like grey putty (see `close.jpg`, third row, left).
4. Constant roughness and no normal detail, so light falls on the ground the same way everywhere.

## 2. What changed

### Approach

- **New shader:** `shaders/terrain_detail.gdshader` keeps the original shader's palette maths line for line and lays texture detail into it.
- **Textures:** five Poly Haven CC0 ground textures form a 5-layer `Texture2DArray` (grass, forest floor, dirt, sand, rock).
  - Each one was **normalised to an average of 0.5 grey**, keeping half of its own hue variation, with a per-layer contrast (rock 0.6).
  - The shader multiplies the texture ×2 into the palette colour. On average the colour is therefore the original palette colour, so the art direction and the seasons are preserved. Mean screen brightness is within 2.5% of the original in every shot (§5).
- **Anti-tiling:** each layer is sampled at two scales, 3.5 m and a 9.45 m rotated copy, mixed by low-frequency noise.
- **Transitions:**
  - Blend weights are perturbed by 1.3 m noise and by the textures' own brightness, which acts as a height map. Stones show through sand first, and grass gives way to its own earth patches.
  - The 1 m grid no longer shows.
- **Relief:**
  - The dominant layer's normal map perturbs the normal in world space. The mesh has no tangents, and adding them would have changed the mesh data, so the shader doesn't use tangent space.
  - Relief fades out by 80 m and is suppressed under snow.
- **Distance:** detail fades to 55% between 25 and 90 m from the camera, against shimmer and visible repeats.
- **Material:**
  - Roughness is set per ground type (0.82–0.95), varies slightly with brightness, and drops to 0.55 when wet.
  - SPECULAR is 0.25 and there's no metallic.
  - One shared material, as before.
- **Unchanged:**
  - snow;
  - the wet shore;
  - autumn and summer tints;
  - `set_season` (same uniform names).

### Files

| File | Change |
|---|---|
| `game/shaders/terrain_detail.gdshader` | **New.** The upgraded terrain shader. |
| `game/textures/terrain/ground_albedo.png` (+`.import`) | **New.** 512×512 × 5 layers, VRAM-compressed array (874 KB imported). |
| `game/textures/terrain/ground_normal.png` (+`.import`) | **New.** 256×256 × 5 layers (219 KB imported). |
| `game/tools/build_terrain_textures.gd` | **New.** Builds both arrays from the Poly Haven 1k maps. |
| `game/tools/terrain_shots.gd` | **New.** The before/after renders. |
| `game/tools/terrain_timing.gd` | **New.** Generation and chunk-build timing. |
| `game/scripts/world.gd` | `terrain_detail` flag; picks the shader and sets the two textures. Nothing else. |
| `game/scripts/main.gd` | Reads `?terrain=` / `--terrain=` before `world.generate`. |
| `game/scripts/perf_bench.gd` | Opt-in `?zoombench=1` scenes, `village_max_zoom` and `field_max_zoom`. The default bench is unchanged. |
| `game/tools/smoke_test.gd` | Phase 5A checks (§6). |
| `game/models/CREDITS.md` | Terrain textures section. |
| `perf/terrain/*` | Screenshots and web bench JSON. |

Not touched:
- `terrain.gdshader`
- world generation
- collision
- movement
- props and vegetation
- NPCs
- building
- combat
- networking
- save/load
- Workers and Turso

## 3. Assets and licences

All five textures are from Poly Haven and licensed **CC0 1.0**. The licence page says: "Our assets are all licensed as CC0". Authors were confirmed with `api.polyhaven.com/info/<id>`, and the 1k files' MD5s were checked against the API.

| Layer | Texture | Author | Page |
|---|---|---|---|
| grass | Rocky Terrain 02 | Amal Kumar | https://polyhaven.com/a/rocky_terrain_02 |
| forest floor | Forest Leaves 02 | Rob Tuytel | https://polyhaven.com/a/forest_leaves_02 |
| dirt | Dirt | Charlotte Baglioni | https://polyhaven.com/a/dirt |
| sand | Coast Sand 01 | Rob Tuytel | https://polyhaven.com/a/coast_sand_01 |
| rock | Aerial Rocks 02 | Rob Tuytel | https://polyhaven.com/a/aerial_rocks_02 |

These are recorded in `game/models/CREDITS.md`. The original 1k files are not in the repository. Only the processed arrays are, about 3.6 MB of source PNG.

The grass layer is "Rocky Terrain 02", a grassy ground with small stones. Out of about 20 candidates, it read best as meadow once it was multiplied into the palette. The 3D grass clumps on top supply the blades.

## 4. Screenshots

These are in `perf/terrain/`. Every sheet has the **original on the left and the upgrade on the right**. They were rendered at 1280×720 with the OpenGL Compatibility renderer under Xvfb (Mesa llvmpipe).

| Sheet | Rows |
|---|---|
| `close.jpg` | Eye level: field, forest, rocky ground, beach, hillside |
| `zoom-near.jpg` | Game camera, closest zoom (0.55), same five places |
| `zoom-normal.jpg` | Default zoom (1.0) |
| `zoom-max.jpg` | Farthest zoom (3.2) |
| `seasons-night.jpg` | Field in summer, autumn, winter (snow), and at night with a torch |

**What to look at:**
- **Rocky ground:** grey putty becomes mossy, cracked rock slabs.
- **Beach:** the sand gains grain and pebbles, and the seabed under shallow water is textured. The sand–grass edge is irregular rather than stepped.
- **Fields and hills:** soil and small stones show between the grass clumps, and there are bare-earth patches with natural edges.
- **Forest floor:** leaf litter, darker under the canopy.
- **Maximum zoom:** no repeating pattern is visible. Colours match the original at a distance, with no sudden colour change between near and far.
- **Seasons and night:** unchanged in character. Snow covers the detail, autumn and summer tints apply over it, and the torch-lit night reads the same.

Mean screen brightness (0–255), original → upgrade:

| Shot | Original | Upgrade |
|---|---|---|
| field z1.0 | 68.5 | 66.7 |
| forest z1.0 | 65.9 | 64.5 |
| rocky z1.0 | 70.5 | 70.4 |
| beach z1.0 | 86.2 | 86.3 |
| field summer | 76.7 | 75.2 |
| field winter | 184.2 | 184.5 |
| field night | 3.9 | 4.1 |

## 5. Distance, LOD and chunk boundaries

- **Chunk boundaries:** texture coordinates come from world position, so they're continuous across chunks by construction, and no seam shows in any shot.
- **Popping and flicker:**
  - Chunks still build a few per frame, as before, and the material is the same.
  - The distance fade is continuous (`smoothstep`), with no switch at a distance.
  - Mipmapped arrays stop shimmer at maximum zoom.
- **Colour at distance:** at 90 m and beyond, the colour is 55% plain palette and 45% textured. Because the textures average to the palette colour, distant ground matches what's near, which `zoom-max.jpg` shows.

## 6. Regression tests

`tools/smoke_test.gd`, run headless:

| Run | Result |
|---|---|
| Default (upgraded terrain) | **325 ok, 0 FAIL — "Smoke test passed."** |
| `--terrain=0` | **passed** |

New checks:
- **Terrain heights, normals and blends are exactly the same as before** (an existing check, 4 chunks, difference 0.0). It passes both ways.
- **The spawn chunk's mesh hash** (vertices, normals, colours, indices) is the same with and without the upgrade: `1279805263` both times.
- The terrain meshes are built as before, with the same vertex count and no new attributes (no UVs).
- The upgraded run uses `terrain_detail.gdshader` with both texture arrays, and `--terrain=0` uses the original `terrain.gdshader`.

Existing checks that still pass include:
- world generation and the island's places;
- tree collision ("trees still block the way");
- felling and rebuilding a chunk;
- building placement and refusal;
- chunk hiding and rebuilding at boundaries;
- formations;
- seasons and ice walking;
- boats;
- save, reload and resume.

**Multiplayer:** no networking, Worker or Turso code was touched. Terrain rendering is local and doesn't take part in sync. There is no multiplayer test harness in the repository, so this wasn't run live.

**Pre-existing engine messages:** `Parameter "material" is null` (in `material_get_instance_shader_parameters`) and a MultiMesh `set_buffer` size message appear in **both** runs, including `--terrain=0`. They come from the equipment and kit code, not the terrain. These are unchanged from `main` and have nothing to do with this phase.

## 7. Performance

> **Software renderer.** Every frame time below comes from **Chromium + ANGLE on Mesa llvmpipe**, a CPU rasteriser, at 1280×720. These are **not real-GPU numbers**. llvmpipe makes fragment-shader cost look far bigger than on any GPU. Frame times are also noisy at this level (±10% run to run). Draw calls, triangles and memory are exact.

Web build: `?bench=1&perf=1&zoombench=1`, with and without `&terrain=0`. Data: `perf/terrain/web-old.json` and `web-new.json`.

| Scene | Draw calls (old → new) | Triangles (old → new) | p50 ms (old → new) | p95 ms (old → new) |
|---|---|---|---|---|
| Open field (`empty_area`) | 312 → 312 | 2.08 M → 2.07 M | 677 → 714 | 1034 → 945 |
| Forest | 334 → 334 | 2.39 M → 2.37 M | 889 → 937 | 1394 → 1369 |
| Forest, props hidden: mostly terrain (`diag_forest_no_props`) | 104 → 104 | 160 k → 160 k | **183 → 268** | **215 → 307** |
| Village | 577 → 579 | 2.09 M → 2.10 M | 663 → 708 | 791 → 786 |
| Village + 30 soldiers | 619 → 622 | 2.15 M → 2.16 M | 856 → 827 | 958 → 887 |
| Night village + 30 soldiers | 702 → 702 | 2.68 M → 2.68 M | 873 → 933 | 956 → 1017 |
| Village, max zoom | 593 → 593 | 2.03 M → 2.03 M | 917 → 949 | 1110 → 1003 |
| Field, max zoom | 385 → 385 | 2.34 M → 2.34 M | 899 → 924 | 1167 → 1143 |
| Chunk transitions (`area_transitions`) | 298 → 291 | 1.53 M → 1.49 M | 827 → 811 | 1080 → 949 |

Crossing frames during chunk transitions (ms):

| Terrain | Frames |
|---|---|
| Old | 769, 1042, 1004, 906, 698 |
| New | 854, 947, 811, 817, 700 |

There are no new spikes when crossing chunks.

**Memory:**

| Measure | Old | New | Change |
|---|---|---|---|
| Texture memory | 9.9 MB | 10.9 MB | +1.0 to 1.1 MB in every scene |
| Video memory | 33.3 MB | 34.4 MB | about the same increase |

**Download:**

| File | Village baseline (`main`) | This branch | Change |
|---|---|---|---|
| `index.pck` raw | 8,776,864 B | 9,878,768 B | **+1.10 MB** |
| `index.pck` gzipped | 7,136,193 B | 8,052,389 B | **+0.92 MB** |

**Load:** load time in the web run went from 11.7 s to 14.7 s on llvmpipe, which includes compiling the larger shader. Expect a much smaller difference on a real GPU.

**Terrain generation**, native, OpenGL3 on llvmpipe, from `tools/terrain_timing.gd`:

| Measure | Old | New |
|---|---|---|
| `world.generate` | 31 ms | 31 ms |
| Build 49 chunk meshes (median of 5) | 157 ms | 200 ms |
| First frame after the rebuild | 200–230 ms | 280–310 ms |

- **Generation:** identical, since the same code runs either way.
- **Chunk meshes:** the build code is identical in both modes, so the 43 ms gap is noise between runs. The mesh build doesn't depend on the shader.
- **First frame after the rebuild:** this is the terrain fragment cost, on the CPU rasteriser.

**Reading it:**
- Draw calls and triangles are unchanged. The material is still one shared material, and the meshes are identical.
- The whole cost is fragment-shader work: per pixel, 10 texture-array samples, 1 normal sample, and a few noise calls.
- On llvmpipe this shows plainly in the terrain-only scene (+46%). In full scenes it is lost in prop and shadow cost: −3% to +7% at p50, within noise.
- On a real GPU this kind of shader is cheap. Validating it on a real GPU is recommended (§9).

## 8. Known limitations

- **Normals are approximate.** With no tangents, the normal maps perturb the normal in world XZ. That's correct on flat and gentle ground, and slightly off on steep slopes, which is barely visible because relief is already modest there.
- **Only the dominant layer's normal map is used.** At a blend edge the relief switches from one layer's map to the other's. This is hidden by the noisy edges, but it can be spotted close up on a sand/grass border.
- **Shallow seabed is textured too.** Ground below the waterline uses the same shader, now with sand texture. It looks right through the clear water, but it is a visible difference.
- **Cost on weak GPUs:** 11 array texture fetches per terrain pixel. On integrated or mobile GPUs this is the most expensive part of the change. `detail` and `relief` are uniforms and could be lowered or switched off by a quality setting (§9).
- **The repository grows** by about 3.6 MB of source PNG for the two arrays. Only the imported arrays ship in the build.
- **Night** is unchanged in tone (within 0.2 brightness levels), but torch-lit ground now shows texture. That's intended, but noted.
- **No new vegetation or wetness.** Mud is the darker wet ground at the waterline plus the dirt layer. There is no dedicated mud texture, because that would have needed a new terrain type in world generation, which this phase doesn't allow.

## 9. Recommendations for Phase 5B

1. **Real-GPU check:** run the web bench on a real integrated GPU (Intel UHD / Apple M) with and without `?terrain=0` before shipping. The llvmpipe numbers can't tell us the true cost.
2. **Quality setting:** a low setting could use `terrain.gdshader`, or set `detail=0` and `relief=0` with a single-scale sample, for weak devices.
3. **Grass clump colour:** match the 3D grass clump colour to the textured ground under it, sampling the same palette in `grass.gdshader`, so the clumps and the ground read as one surface.
4. **Mud near water and paths:** a dedicated mud/path layer, driven by distance to water and by player buildings (worn ground around the village), using the free sixth array slot.
5. **Tangents:** if a later phase may change mesh data, adding tangents would allow correct tangent-space normals and blending all layers' normals.
6. **Far terrain:** a cheaper far-distance path, palette only beyond about 120 m, to cut fragment cost at maximum zoom.
7. **Rock props:** retexture the rock props with the same rock texture so the props match the rocky ground.

## How to compare

- In the browser: open the game with `?terrain=0` for the original terrain. The default is the upgrade.
- Native:

```bash
godot --path last-light/game -- --terrain=0
```

- Screenshots, rendered once without and once with the flag:

```bash
xvfb-run godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 --script res://tools/terrain_shots.gd -- --terrain=0
```

```bash
xvfb-run godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 --script res://tools/terrain_shots.gd
```
