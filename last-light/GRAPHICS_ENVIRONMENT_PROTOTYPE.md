# Islander: environment and vegetation prototype (phase 4A)

**Status:** prototype complete on branch `claude/env-prototype`, not merged. One pine, one oak, one boulder and one bush are replaced by textured CC0 models. Everything else is unchanged. `?nature=0` (or `-- --nature=0` natively) shows the old procedural props for comparison.

Constraints for this phase: no changes to gameplay, combat, movement, networking, the Workers, Turso, saves, world generation, 3B prop culling, 3C terrain and grass streaming, or 3D draw-call work. Only four prop types are prototyped (one pine, one oak, one rock, one bush); everything else stays as it is.

## Step 1: the current environment system

### What exists and where it comes from

All of it is in `scripts/world.gd`.

| Prop | Where it grows (`_chunk_props`, from the seed) | Drawn as (`DRAW_TYPES`) | Built from (`_prop_parts`) | Triangles |
|---|---|---|---|---|
| Tree | Forest tiles 30%, grass tiles 3% | `tree_pine` (70% in forest, 25% in the open, by `_tree_kind`) | A trunk cylinder and 4 cone tiers | 285 |
| | | `tree_oak` (the rest) | A trunk and 5 squashed spheres | 748 |
| Stump | Where a tree was felled (regrows in 5 days) | `stump` | 2 cylinders | 108 |
| Rock | Grass 1%, rock 16.5%, sand 1.2% | `rock` | 3 squashed spheres | 274 |
| Iron rock | Grass 0.2%, rock 3.5%, islets 4.5% | `iron_rock` | A sphere and 3 ore nuggets | 288 |
| Gold rock | Islets 4.5% | `gold_rock` | A sphere and 3 gold nuggets | 288 |
| Rubble | Where a rock was broken (regrows in 6 days) | `rubble` | 3 small spheres | 180 |
| Bush | Forest 3%, grass 2.5% | `bush` (berries) / `bush_empty` (picked, regrows in 2 days) | 3 leaf spheres and 4 berries / 2 leaf spheres | 540 / 204 |
| Fallen logs | — | — | **None exist** in the game | — |
| Grass | Grass and forest tiles near you | A MultiMesh of 7-blade clumps (`_refresh_grass`, phase 3C) | — | 21 per clump |

Each prop's place, turn (one of 360°) and size (0.8–1.25×) come from hashes of its tile, so they're fixed by the seed. Only changes (felled, picked, built over) are saved, in `prop_changes`.

### How props are drawn (phases 3B and 3D)

- **Chunks.** Props are drawn in **32 m chunks** (`_prop_chunks`). The 25 chunks of the 160 m view window are drawn; one more ring is kept hidden. New chunks are built one a frame; a change to a prop rebuilds only its chunk.
- **One MultiMesh per prop type per chunk.** Each type's parts are merged once into a mesh with two surfaces, rigid and leaves (`_merge_parts`). Each vertex carries its part's base colour (UV.xy, UV2.x) and sway (UV2.y: sway amount, 0 for rigid, −1 for berries).
- **Shaders.** `shaders/prop_rigid.gdshader` and `shaders/prop_leaves.gdshader` (sharing `props.gdshaderinc`) compute each part's colour from per-instance data:
  - the season's leaf tint;
  - the prop's light/dark shade;
  - frost on rocks and stumps in winter;
  - winter hiding of oak crowns and berries.

  The leaf shader adds wind sway.
- **Shared materials.** One rigid and one leaf `ShaderMaterial` for all props.
- **Culling.** Godot culls each chunk's MultiMeshes against the camera and each shadow cascade. All props cast shadows.

### Seasons (`_prop_instance_params`)

| Season | Change |
|---|---|
| Summer | Leaves lean 15% toward olive |
| Autumn | Oak crowns turn red, orange or gold by tile (75%); bush leaves go brown (45%) |
| Winter | Oak crowns and berries hidden; pine and bush leaves frosted (55% toward white); rocks, iron and gold rocks and stumps frosted (30%) |

Spring is the base colours. Grass turns golden in summer and russet in autumn, and is hidden in winter.

### Collision and interaction

Props have **no physics bodies**:
- **Blocking:** `is_walkable()` checks the prop on a tile against `SOLID_PROPS` (tree, rock, iron rock, gold rock).
- **Harvesting:** `find_prop_near()` and `harvest()` look at the tile grid.
- **Building:** `can_build()` checks `BUILD_OVER`.

So the meshes can change freely without affecting collision or interaction, as long as each prop keeps its tile.


## Step 2: assets

### Sources checked

| Source | Licence | Verdict |
|---|---|---|
| **Poly Haven** | CC0 | Unsuitable. Its trees are photoscans of 7–17 million triangles (`pine_tree_01` 17.4 M, `fir_tree_01` 7.9 M), its rocks 60 k+, all with large photo textures. That's photoreal against the game's stylised look, and far too heavy for thousands of instances in a browser. |
| **Quaternius, Stylized Nature MegaKit** (Standard, free edition, 68 of 116 models) | **CC0 1.0** | **Chosen.** Stylised, game-ready, and the same author as the game's characters. The licence is stated on https://quaternius.com/packs/stylizednaturemegakit.html and in the kit's `License_Standard.txt`: "CC0 1.0 Universal ... Public Domain Dedication". That allows commercial use and redistribution, with no attribution required (credit is given anyway). |
| Quaternius low-poly models in the `@netforge/asset-library-files` CC0 bundle | CC0 | Usable, but simpler than today's shapes (bush 32 triangles, rock 80), so little visual gain. |

The kit was downloaded once, from https://quaternius.itch.io/stylized-nature-megakit (99 MB zip). **Only four models and five textures from it are in the repository.** The whole library was not imported.

### The four assets

Triangle counts are as used in the game. The far versions are described in step 4.

| Replaces | MegaKit model | Surfaces | Triangles (near / far) | Vertices (near / far) | Procedural prop it replaces |
|---|---|---|---|---|---|
| `tree_pine` | `Pine_5` | bark + needles | 1,646 / 622 | 2,315 / 787 | 285 triangles, 269 vertices |
| `tree_oak` | `CommonTree_5` | bark + leaves | 3,182 / 487 | 4,873 / 760 | 748 triangles, 487 vertices |
| `rock` | `Rock_Medium_2` | rock | 244 (Godot LOD down to 31) | 249 | 274 triangles, 181 vertices |
| `bush`, `bush_empty` | `Bush_Common_Flowers` | leaves + flowers | 1,368 / 413 | 2,515 / 760 | 540 + 204 triangles |

Why these four:
- **Pine:** the lightest of the five pines (`Pine_1` 3,947 triangles to `Pine_3` 4,964).
- **Oak:** the lightest broad-leaved tree (`CommonTree_1` 6,265, `TwistedTree_*` 9,000–10,000).
- **Rock:** lighter than the old one.
- **Bush:** its flowers can play the berries: shown on a full bush, hidden once picked and in winter.

| Texture | From | Size in game | Used by |
|---|---|---|---|
| `bark.png` | `Bark_NormalTree.png` (2048²) | 256² | pine and oak bark (one shared material) |
| `pine_needles.png` | `Leaf_Pine_C.png` (2048²) | 256² | pine needles |
| `leaves.png` | `Leaves_NormalTree_C.png` (1024²) | 512² | oak and bush leaves (one shared material) |
| `flowers.png` | `Flowers.png` (1008×981) | 128² | bush flowers |
| `rock.png` | `Rocks_Diffuse.png` (2048²) | 256² | boulders |

Normal maps are not used. The textures are imported with mipmaps and GPU (S3TC/BPTC) compression. Source and licence for every file are also recorded in `game/models/CREDITS.md`.

## Steps 3 and 4: integration and optimisation

### Asset preparation (offline, repeatable)

`last-light/tools/prepare_nature_models.py <MegaKit glTF folder> game/models/nature` writes everything in `game/models/nature/`:

- **Scale.** Each model is scaled to the procedural prop it replaces (1 tile = 1 m): pine about 5.9 m tall, oak about 5.3 m, boulder 1.9 m × 0.85 m, bush 1.1 m. The game's own per-prop size (0.8–1.25×) and turn are applied on top, exactly as before.
- **Per-vertex shader data in UV2:**
  - bark and rock: (0, the kit's baked shading, dark where branches meet);
  - leaves: (1, sway in metres, growing with height);
  - flowers: (−1, sway).
- **Leaf normals** are bent 80% towards "out from the middle of the crown". Leaf cards face every way, and this lights a crown as one soft shape instead of a dark, blotchy one.
- **Textures** are shrunk. The see-through pixels of leaf textures are filled with the average leaf colour, so distant mip levels don't darken leaf edges.
- **Far versions** (`*_far.glb`):
  - leaf cards are kept or dropped whole: 40% of pine sprigs, 25% of oak cards, 30% of bush cards, spread evenly;
  - each kept card is enlarged around its centre (1.45–1.8×) so the crown stays full;
  - bark is merged on a 0.2–0.3 m grid, so thin twigs collapse and trunk and limbs remain.

### Rendering architecture

```
world.gd  _build_prop_layers()
  ├─ _merge_parts()          old procedural mesh per prop type (unchanged)
  └─ _use_nature_models()    if nature_models: for pine, oak, rock, bush(+empty)
        _merged_props[kind]  = models/nature/<name>.glb   (near model)
        _nature_far[kind]    = models/nature/<name>_far.glb
        _nature_shadow[kind] = the old procedural mesh     (shadow proxy; not rocks)
        5 ShaderMaterials, one per texture, shared by all models and chunks

world.gd  _build_prop_chunk(ck)   (phase 3B chunks, unchanged otherwise)
  per prop type in the chunk:
    MultiMeshInstance3D  kind           near model, no shadows, visible to 40 m
    MultiMeshInstance3D  kind_far       far model,  no shadows, visible from 40 m
    MultiMeshInstance3D  kind_shadow    old mesh,   shadows only
      (all three share one instance buffer: place, turn, size, season data)
```

- **Placement, collision and interaction are untouched.**
  - Instance transforms come from the same per-tile hashes.
  - Blocking, felling, picking and building still use the tile grid (`SOLID_PROPS`, `is_walkable()`, `harvest()`). None of them read meshes.
  - World generation, saves, 3C streaming and 3D merging don't change.
- **Shaders** (`shaders/prop_tex_rigid.gdshader`, `prop_tex_leaves.gdshader`) include the same `props.gdshaderinc` as the procedural props. So every seasonal rule applies unchanged:
  - summer olive tint;
  - autumn oak colours (red, orange and gold per tree) and browning bushes;
  - winter frost on pines, bushes and rocks;
  - bare oaks in winter (the leaf cards are hidden, leaving the real branches);
  - flowers hidden on picked bushes and in winter.

  Texture colours are used as stored, like every other prop colour in the game.
- **Leaves use cut-out (alpha scissor 0.35), not blending:** no sorting, depth writes, double-sided. Supported by the Compatibility renderer.

### Optimisations, and what each was worth

Measured on the forest view natively (Mesa llvmpipe, 1280×720, zoom 1.6):

| Step | Frame time | Primitives | Draw calls |
|---|---|---|---|
| Old procedural props | 395–429 ms | 3.15 M | 419 |
| Models, nothing else | 1,451 ms | 3.94 M | 423 |
| … without Godot's automatic LOD | — | 13.1 M | 423 |
| … leaves without cut-out (test only) | 1,170 ms | 3.94 M | 423 |
| … with far versions beyond 40 m | 1,153 ms | 3.19 M | 423 |
| **… and old shapes as shadow proxies (final)** | **679 ms** | **3.14 M** | **419** |
| (near distance 25 m instead of 40 m) | 650 ms | 3.07 M | 419 |

What the numbers showed:
1. **Godot's automatic mesh LOD works in the Compatibility renderer** for MultiMeshes. The importer generates it for bark and rock: pine bark 488 → 344 → 172 → 86 triangles. Without it the forest would draw 13 M primitives.
2. **Vertex count was the main cost, not the cut-out.** The kit's trees have 7–10× the vertices of the procedural ones, because leaf cards don't share corners. Every prop near the camera is drawn up to three times: the view plus two sun-shadow cascades. Collapsing every leaf in the shader saved little, because the vertices are still processed, and Godot's LOD only reduces triangles, not the vertex buffer. Hence the far versions, each with its own small vertex buffer.
3. **Shadow passes were most of the remaining cost.** The models cast no shadows. The old procedural shapes are drawn into the shadow maps only, from the same instance data, so the trees' shadows are the same as before the prototype. A crown sits inside its proxy's shadow, so the leaf shader softens the sun's shadow on leaves to 35%. Lamps and torches light leaves as usual.
4. **Draw calls are unchanged.** Each prop type is still one MultiMesh draw per surface per pass. The extra nodes are either hidden by visibility range (near/far) or drawn in place of the old shadow casters (proxies).
5. Changing objects (felled trees, picked bushes) still rebuild only their chunk. All three instances of a prop type share one instance buffer.

## Step 5: visual validation

`game/tools/env_shots.gd` renders the same views with the old props (`-- --nature=0`) and the new ones:
- a forest edge and a rocky area, each at three zooms and in first person;
- the forest in all four seasons;
- the forest at night in summer and winter.

Images are in `perf/environment/`:

| Image | What it shows |
|---|---|
| `before-after-forest.jpg` | Close, middle and far zoom, and first person. Textured bark and leaf crowns; bushes with flowers instead of red spheres. At far zoom the far versions are in use. |
| `before-after-rocks.jpg` | Boulders with the kit's mossy rock texture; slightly taller than the old ones. |
| `before-after-seasons.jpg` | Spring; summer olive; autumn oaks in red, orange and gold, and bushes browning; winter with frosted pines and rocks, and bare oaks showing their real branches. |
| `before-after-night.jpg` | Night in summer and winter: everything still present and lit by the moon. Lamps light leaves normally. |

Checked:
- **Nothing disappears.** Every prop in view is drawn: the smoke test's "every tree, rock and bush within view distance is drawn" still passes.
- **Same places.** Props sit on the same tiles with the same turn and size. Felling a tree, picking a bush and building over a prop behave as before.
- **No double drawing.** The near/far switch shows no gap or overlap; both versions use the same instances.

Known visual limits, for the next pass:
- **Far oaks look sparse and star-shaped at the highest zoom.** Only 25% of their cards remain, each enlarged 1.8×. Keeping 35% at 1.5× is the obvious next step; it costs a little more.
- **Shadows keep the old rounded shapes**, by design (the shadow proxies). They read well from the strategy camera.
- **The boulder is taller than the old rock** (0.85 m against 0.6 m). Its tile-based collision is unchanged.

## Step 6: performance against the baseline

The same web build, run with `?nature=0` (old props) and with the models, in the project's browser benchmark (`perf/run_web_bench.cjs`, Chromium + ANGLE on Mesa llvmpipe, 1280×720, fixed seed). Results are in `perf/environment/web-nature0.json` and `web-nature1.json`. The first run, before the far versions and shadow proxies, is kept as `first-web-nature*.json`.

| Scene | Draw calls | Primitives | Frame time p50 | Frame time p95 | Video memory | Texture memory |
|---|---|---|---|---|---|---|
| Empty area | 308 → 318 | 2.14 → 2.08 M | 512 → 673 ms | 601 → 1,224 ms | 30.3 → 31.8 MB | 8.6 → 9.1 MB |
| **Forest** | 314 → 334 | 2.71 → 2.37 M | **646 → 1,002 ms** | 922 → 1,489 ms | 30.1 → 31.6 MB | 8.7 → 9.2 MB |
| Forest, no sun shadows (diagnostic) | 126 → 146 | 0.67 → 0.58 M | 211 → 475 ms | 254 → 585 ms | 30.1 → 31.6 MB | 8.7 → 9.2 MB |
| Forest, no props (diagnostic) | 104 → 104 | 0.15 → 0.15 M | 200 → 187 ms | 238 → 221 ms | 30.1 → 31.6 MB | 8.7 → 9.2 MB |
| Village | 569 → 576 | 2.32 → 2.03 M | 529 → 744 ms | 671 → 904 ms | 38.2 → 39.6 MB | 8.8 → 9.3 MB |
| Village + 30 soldiers | 707 → 713 | 2.63 → 2.17 M | 722 → 951 ms | 847 → 986 ms | 60.9 → 62.3 MB | 9.2 → 9.8 MB |
| Night village + 30 soldiers | 791 → 791 | 3.19 → 2.68 M | 786 → 947 ms | 901 → 1,145 ms | 60.9 → 62.3 MB | 9.2 → 9.8 MB |

| | Old props | Models | Change |
|---|---|---|---|
| Download: `index.pck` (vs `main` at 86cf462) | 2.68 MB | 3.58 MB | **+0.91 MB** (+0.49 MB gzipped); `index.wasm` unchanged |
| Load to first frame (same build) | 13.1 s | 13.9 s | +0.8 s |
| Texture memory | 8.7 MB | 9.2 MB | +0.5 MB |
| Video memory | 30.1 MB | 31.6 MB | +1.5 MB |

How to read this:
- **Primitives fell** (−12% in the forest), because the far versions are lighter than the old shapes. **Draw calls rose by 6%** in the forest, and by 1% or nothing in the village scenes.
- **Frame time rose 1.2–1.6×**, most in the forest (1.55×). Without props, the forest is unchanged. The remaining cost is the main colour pass drawing textured, cut-out leaf cards. A software rasterizer (llvmpipe, used for every measurement in this project) pays for that per vertex and per pixel far more than a real GPU does. So the ratio is a warning sign rather than a prediction, but it is real extra work. Before the optimisations it was 6.7× (`first-web-nature1.json`).
- **Memory and download costs are small:** under 1 MB download, 0.5 MB textures and 1.5 MB video memory.

## Deliverables

| File | What it is |
|---|---|
| `game/models/nature/` | The four models, their far versions, and the five textures, with import settings |
| `game/models/CREDITS.md` | Source and licence for each file |
| `tools/prepare_nature_models.py` | Rebuilds `models/nature/` from the kit |
| `game/shaders/prop_tex_rigid.gdshader`, `prop_tex_leaves.gdshader` | Textured prop shaders on the shared seasonal code |
| `game/scripts/world.gd` | `_use_nature_models()`, `_prop_copy()`, and the near/far/shadow instances in `_build_prop_chunk()` |
| `game/scripts/main.gd` | The `?nature=0` / `--nature=0` comparison switch |
| `game/tools/env_shots.gd` | The before/after renders |
| `game/tools/smoke_test.gd` | Checks: models and shared materials in use, near/far switch and shadow proxies set up, picked bushes hide their flowers |

## Recommendation before replacing more objects

1. **Measure on a real GPU before deciding.** Open the site with and without `?nature=0` and `?perf=1` on a typical laptop. The llvmpipe ratio overstates leaf-card costs.
2. **If it needs to be cheaper:**
   - fewer leaf cards in the near models (keep 60–70%);
   - a shorter near distance (25 m saved 5% here);
   - fewer pine sprigs in the far version.
3. **Then extend** to stumps, iron and gold rocks (the kit's rocks plus ore nuggets), rubble and fallen logs, using the same pipeline (`prepare_nature_models.py`, `NATURE_MODELS`).
