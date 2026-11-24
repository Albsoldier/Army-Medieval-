# Islander: environmental prop culling (phase 3B)

Trees, rocks and bushes are now drawn in **32 m chunks**, with **one MultiMesh per prop type per chunk**. The renderer can cull each chunk against the camera and the shadow cascades, and draw calls stay close to what they were.

Unchanged: gameplay, collision and interaction (they use the prop grid, not these meshes), world generation, the sun-shadow settings (preset C), lighting, networking, the Cloudflare Workers and Turso.

**Not merged.** This is for review.

### Tags used below

| Tag | Meaning |
|---|---|
| **[M]** | Measured, and valid on any machine (primitives, draw calls, prop and chunk counts) |
| **[M-sw]** | Measured on a software GPU: only for comparing configurations |
| **[M-cpu]** | Measured natively with no rendering (CPU only) |
| **[E]** | Estimate |

## Result: 32 m grouped chunks (the new default)

Compared with `main`, same benchmark, same spots, same shadow preset **[M]**:

| Scene | Primitives before → after | Draw calls before → after |
|---|---|---|
| Empty area | 5,660,775 → **2,138,914** (−62%) | 212 → 335 |
| Forest | 6,573,733 → **2,706,958** (−59%) | 217 → 342 |
| Village | 6,431,877 → **2,298,093** (−64%) | 1,478 → 1,575 (+7%) |
| Village + 30 soldiers | 6,691,272 → **2,564,148** (−62%) | 2,162 → 2,278 (+5%) |
| Night village + 30 soldiers | 6,722,114 → **3,099,691** (−54%) | 2,255 → 2,412 (+7%) |
| Area transitions | 6,178,571 → **1,836,244** (−70%) | 349 → 408 |

- **Same props, same draw distance.** Every tree, rock and bush that was drawn before is still drawn: 4,723 in the forest and 4,842 in the village. The 32 m chunks tile the original 160 m view window exactly.
- **Culling works.** Only 7 of the 25 forest chunks are in the camera's view, and the renderer draws only those (see §4).
- **Chunk crossings cost less.** Crossing into a new area now builds 5 small chunks, one per frame, instead of rebuilding all 4,700 props in one frame.
- **The forest target was not reached.** The target was under 2 M primitives; the forest is at 2.71 M. 16 m chunks reach 2.04 M, but at +373 draw calls (§5). Most of what remains is the shadow pass (§6).

---

## 1. Why the first version had too many draw calls

The first version (32 m chunks, one MultiMesh per *part*) took the forest from 6.58 M to 2.47 M primitives, but from 218 to 631 draw calls.

Every prop type is built from several parts, and each part was its own MultiMesh:
- a pine: trunk and 4 needle tiers;
- an oak: trunk and 5 crown lumps;
- a rock: 3 lumps;
- a bush: 3 leaf lumps and berries.

That made about **25 MultiMeshes in every forest chunk**. Each is a separate draw in the colour pass, and again in each shadow cascade that covers the chunk. Because the cascades see more chunks than the camera does, the draws multiply quickly. In the old single-block layout the same 36 part-layers were drawn once per pass, no matter how many props they held.

## 2. What changed

### 2.1 Spatial chunks

- **Separate from terrain chunks.** Props have their own chunk grid (`world.prop_chunk`, 32 tiles = 32 m by default). Each prop chunk is a `Node3D` under `World/Props`, gathering its props from the terrain chunks beneath it.
- **The same drawn area as before.** Props are drawn for the prop chunks overlapping the same window as before: the player's terrain chunk ±2, which is 160 m.
- **Incremental.** When you cross a chunk, only the chunks that came into view are queued, nearest first, and built one per frame (`PROP_BUILDS_PER_FRAME`). Chunks that leave the view are **hidden, not freed**, for one more ring, so walking back and forth over a boundary rebuilds nothing. Chunks beyond that are freed.
- **Local rebuilds.** Felling a tree, picking a bush, regrowth or building over a prop marks **only its chunk** for rebuilding (`_mark_props_dirty`). A season change or a loaded save rebuilds all built chunks, as before.
- **Unchanged collision and interaction.** They read `prop_type()` and `is_walkable()` on the prop grid, which this doesn't touch. The smoke test checks that trees still block and that a stump can be walked over.

### 2.2 One MultiMesh per prop type per chunk

- **Merged meshes.** All parts of a prop type are merged once into one `ArrayMesh` (`_merge_parts`), with two surfaces: rigid parts (trunks, rocks, stumps, berries) and leaves. Each vertex carries its part's base colour and sway amount.
- **One instance per prop.** Each chunk has one MultiMesh per prop type present, so a forest chunk has about 4–6 MultiMeshes instead of about 25. Rigid-only types such as rocks are one draw; leafy types are two.
- **Per-instance seasonal data.** Each instance carries the season's leaf tint, the prop's light/dark shade, frost on rocks and stumps, and winter hiding of oak crowns and berries (`_prop_instance_params`).
- **The same look.** Two shaders, `prop_rigid.gdshader` and `prop_leaves.gdshader` (sharing `props.gdshaderinc`), apply exactly the colour rules the old code ran per part per prop. The leaf shader keeps the original wind sway.
- **Fewer objects.** Forest MultiMeshes: 114 with grouping, against 508 per-part at the same chunk size **[M]**.

### 2.3 Developer switches (no effect for players)

These exist for comparisons like the one in this document:
- `?propchunk=N` or `-- --propchunk=N`: prop chunk size in metres.
- `?propgroup=0` or `-- --propgroup=0`: one MultiMesh per part, the first version.
- The benchmark now uses a **fixed random seed**, so every run stands in exactly the same spots.

## 3. Chunk sizes compared

The same browser benchmark ran for every configuration: exported web build, Chromium, 1280×720, sun-shadow preset C, fixed seed. All tables, and the raw JSON, are in `perf/prop_chunks/`.

### 3.1 Summary [M]

| Configuration | Forest primitives | Forest draw calls | Village primitives | Village draw calls | Props drawn (forest) | Prop MultiMeshes (forest) |
|---|---|---|---|---|---|---|
| **Before** (`main`: one MultiMesh per part, 160 m blocks) | 6,573,733 | 217 | 6,431,877 | 1,478 | 4,723 | 36 |
| 16 m grouped | 2,041,734 | 715 | 1,619,229 | 1,834 | 4,723 | 382 |
| 20 m grouped | 2,547,720 | 627 | 1,958,759 | 1,757 | 5,985 | 337 |
| 30 m grouped | 3,282,476 | 437 | 2,699,971 | 1,648 | 6,895 | 194 |
| **32 m grouped (chosen)** | **2,706,958** | **342** | **2,298,093** | **1,575** | **4,723** | **114** |
| 40 m grouped | 3,521,041 | 327 | 3,283,560 | 1,571 | 7,132 | 119 |
| 50 m grouped | 4,270,974 | 286 | 4,577,832 | 1,566 | 7,131 | 78 |
| 16 m per-part | 1,928,531 | 1,568 | 1,524,429 | 2,513 | 4,723 | 1,765 |
| 32 m per-part (first version) | 2,480,522 | 637 | 2,127,712 | 1,876 | 4,723 | 508 |

### 3.2 What the sizes show

- **Sizes that don't divide the 32 m window draw extra props.** The view window is 160 m, made of 32 m terrain chunks. Chunks of 20, 30, 40 and 50 m don't line up with its edges, so the chunks overhanging the window are drawn whole.
  - The forest draws 5,985–7,132 props instead of 4,723, and the village up to 11,651.
  - That's extra work beyond the original draw distance, out in the fog, so these sizes look worse than they would with an aligned window.
  - **Only 16 m and 32 m tile the window exactly.**
- **Smaller chunks:** fewer primitives, more draw calls. Going from 32 m to 16 m saves 0.67 M primitives in the forest for 373 more draw calls.
- **Larger chunks:** fewer draw calls, more primitives. Coarser culling plus overhang means 50 m draws 4.27 M primitives in the forest.
- **Grouping cuts prop draw calls about 2.5× at every size,** for 5–10% more primitives. In the forest at 32 m, prop draws (total minus the about 132 non-prop draws) fall from 505 to 210. Each merged tree is culled as a whole, so a trunk can't be culled while its crown is kept.

### 3.3 Every scene

The six scenes, with frame time **[M-sw]**, total generated props (built, including the hidden spare ring), props drawn, props in view, chunks in view, and chunks drawn / built, are in `perf/prop_chunks/tables.md`.

The 32 m grouped rows:

| Scene | Primitives | Draw calls | Frame ms [M-sw] | Props built | Props drawn | Props in view | Chunks in view | Chunks drawn / built |
|---|---|---|---|---|---|---|---|---|
| Empty area | 2,138,914 | 335 | 507 (before 811) | 4,037 | 4,037 | 894 | 6 | 25 / 25 |
| Forest | 2,706,958 | 342 | 699 (before 945) | 4,723 | 4,723 | 1,286 | 7 | 25 / 25 |
| Village | 2,298,093 | 1,575 | 602 (before 965) | 4,842 | 4,842 | 1,971 | 10 | 25 / 25 |
| Village + 30 soldiers | 2,564,148 | 2,278 | 882 (before 1,330) | 4,842 | 4,842 | 1,971 | 10 | 25 / 25 |
| Night village + 30 | 3,099,691 | 2,412 | 1,022 (before 1,534) | 4,842 | 4,842 | 1,971 | 10 | 25 / 25 |
| Area transitions | 1,836,244 | 408 | 650 (before 1,192) | 4,169 | 3,187* | 977 | 5 | 18 / 23* |

\*The transitions snapshot is taken mid-travel. On the software GPU (about 1.5 frames per second), building one chunk per frame lags behind a player moving at riding pace, so some chunks were still queued. At a real 60 fps, the 5 chunks per crossing are built in about 0.1 s **[E]**. The same lag makes the 16 m and 20 m transition rows look better than they would be.

## 4. Is culling really working? [M]

The forest ran with sun shadows **off**, so the primitives are the colour pass only. The no-props run gives everything else (terrain, grass, the player).

| Configuration | Measured primitives | Without props | Prop triangles drawn by the GPU | Prop triangles in view (predicted) | Prop triangles in all drawn chunks |
|---|---|---|---|---|---|
| 32 m grouped | 664,512 | 145,025 | **519,487** | **515,526** | 2,138,051 |
| 32 m per-part | 620,439 | 145,025 | 475,414 | 515,526 | 2,138,051 |
| 16 m grouped | 529,738 | 145,025 | 384,713 | 429,347 | 2,138,051 |

- **The GPU draws only the chunks in view.** The prop triangles it drew match the triangles in the chunks inside the camera's frustum, as computed by `world.props_in_view()` from the camera's planes and each chunk's bounds: 519 k against 516 k.
- **Out-of-view props are excluded.** The drawn figure is about a quarter of the 2.14 M in all drawn chunks.
- Per-part comes in slightly under the prediction, because its many small part-meshes are culled individually.

The smoke test also checks this with the camera: "only some prop chunks are in the camera's view (8 of 25)".

## 5. Recommendation: 32 m, grouped

| | 16 m grouped | **32 m grouped** | 32 m per-part |
|---|---|---|---|
| Forest primitives | 2.04 M | **2.71 M** | 2.48 M |
| Forest draw calls | 715 | **342** | 637 |
| Village draw calls | 1,834 | **1,575** | 1,876 |
| Prop MultiMeshes in the forest | 382 | **114** | 508 |
| Chunks to build per crossing | 20 | **5** | 5 |

32 m grouped is the best balance:
- **Primitives:** 59–70% fewer than before in every scene.
- **Draw calls:** only 5–7% more in built-up scenes (+97 to +157), and about +125 in open land and forest. The first version added +420 in the forest.
- **Coverage and objects:** it tiles the view window exactly (no extra props) and has the fewest chunk objects for the coverage.

16 m would get the forest to about 2 M primitives, but each 0.67 M primitives saved would cost about 370 more draw calls. In a browser, each WebGL draw call costs CPU time in JavaScript and ANGLE, while 0.67 M triangles are cheap for a GPU. So 16 m is likely to be slower on most machines **[E]**. It stays available behind `?propchunk=16` for testing on real hardware.

## 6. Remaining limitations

- **The forest is above the 2 M target (2.71 M).** About three-quarters of what's left is the shadow pass: 2.71 M with shadows against 0.66 M without **[M]**. The far shadow cascade (7–70 m) also draws casters from chunks outside the camera's view, because their shadows can fall into view. Options for later:
  - turn off shadow casting for prop chunks beyond about 40 m;
  - simpler meshes for distant props (LOD).

  Both change the shadow look or the models, so they're out of scope here.
- **Draw calls are still slightly higher than before**: +97 to +157 in built-up scenes. Merging buildings and character kit (audit phase 5) is the bigger draw-call lever.
- **Grass still rebuilds** its whole 34-tile patch when you cross a chunk. It's a separate system, unchanged here, and now the largest part of the crossing stall.
- **Chunk crossing is cheaper but not free** **[M-cpu]**. The crossing frame was 140–209 ms in the baseline; with 32 m chunks it's 50–84 ms (first version, one chunk per frame). Most of the rest is the grass rebuild and new terrain chunks.
- **Frame times are from a software GPU.** Real-hardware numbers need the benchmark run in Chrome on a real machine (`?bench=1&perf=1`).

## 7. Testing

- **Smoke test** (local, Godot 4.4.1; all pass). The new checks:
  - props are drawn in 25 chunks of 32 m covering the whole view distance;
  - every tree, rock and bush within view distance is drawn (4,842 of 4,842);
  - only some prop chunks are in the camera's view (8 of 25);
  - moving one chunk keeps every built chunk and builds only the new edge (kept 25, rebuilt 0, new 5);
  - stepping back over the boundary builds nothing new;
  - felling a tree rebuilds only its chunk (1 rebuilt), and the stump can be walked over;
  - trees still block the way.
- **Browser:** the exported web build ran in Chromium for every configuration above, including the shaders and their include.
- **Seasons:** grouped and per-part rendering compared in spring, summer, autumn and winter, in the same scene. They look the same: autumn colours, bare winter oaks with trunks, snowy pines, frosted rocks, no winter berries. The remaining pixel differences are within the frame-to-frame variation from moving grass and wind.
- **Before/after views:** `tools/prop_shots.gd` renders the same views on `main` and on this branch (seeded): 8 camera turns at 3 zooms plus first person, in the forest and the village. See §8.

## 8. Before/after views

*(Filled in below from the render comparison.)*
