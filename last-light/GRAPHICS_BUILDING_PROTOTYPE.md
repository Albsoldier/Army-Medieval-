# Islander: medieval building prototype (phase 4B)

**Status:** prototype on branch `claude/building-prototype`, not merged. **One cottage, one stone wall segment and one archer tower** are drawn with CC0 models from Kay Lousberg's **KayKit Medieval Hexagon Pack**. The other 14 building types are unchanged. `?buildings=0` (or `-- --buildings=0` natively) shows the old buildings for comparison.

This is a visual change only. Unchanged:
- gameplay, placement rules, costs, hit points, destruction;
- collision and navigation, saves;
- networking, the Workers, Turso;
- the prop chunks (3B), terrain and grass (3C) and the draw-call work (3D).

## Step 1: audit of the current buildings

All of it is in `scripts/structure.gd` and `scripts/art.gd`.

| Topic | How it works today |
|---|---|
| **Building types** | 17, in `Structure.TYPES`: wooden wall, stone wall, gate, torch post, chest, tent, barracks, workbench, forge, smokehouse, dock, treasure vault, archer tower, spike trap, boiling-oil gate, farm field, cottage. **Every one fills one tile (1 m).** |
| **Models** | Built in code by `_build_model()` from Godot primitive meshes (`Art.box`, `Art.cylinder`, `Art.sphere`), one `Art.part()` per piece with its own colour. A cottage is 7 parts (whitewashed box, two posts, a thatch cone, door, window, chimney). A stone wall is 6 boxes. The archer tower is 17 parts: four legs, braces, a platform, rails, a roof and a little archer. |
| **`Art.bake()` (phase 3D)** | After `_build_model()`, the parts are merged into **one mesh per building type**, cached by key (`"structure:" + kind`) and shared by every building of that type. It's drawn with one shared vertex-colour `StandardMaterial3D`. Parts that glow or are unshaded can't share it: they stay separate on **shared** materials (`Art.shared_material`). Examples: the cottage window, torch flames, forge coals, the oil cauldron, chest and vault locks. So the cottage is 2 surfaces, the wall 1, the tower 1. |
| **Shared materials** | One vertex-colour material for every baked building, plus one shared material per glow colour. |
| **Build preview** | Build mode places a real `Structure` as a ghost: `make_ghost(valid)` overrides every drawn mesh with a see-through green or red unshaded material, turns off its shadows and hides its lights. |
| **Collision and navigation** | None on meshes. The tile grid (`world.structures`) decides it: `is_walkable()` and `Structure.TYPES[kind]["blocks"]` ("all", "wolves" or "none"). The settlers' route-finding and the wolves' blocked cells use the same grid. |
| **Damage** | `damage()` lowers `hp` and flashes: the node shrinks briefly (`_flash`). `_update_wear()` leans the building as it loses hit points (`rotation.z`, `rotation.x`). Both are transforms of the building's node, so they work for any model. |
| **Destruction** | At 0 hp (purge raiders hacking through), or when taken down in build mode, `_remove_structure()` frees the node and clears the tile. There is no debris model. |
| **Construction** | Instant on paying the cost; `built_ms` gives a full refund for a few seconds. There is no construction animation or scaffolding stage. |
| **Upgrades and variants** | No upgrade levels. Walls and gates turn to line up with their neighbours (`line_up()`, a 90° turn). The boiling-oil gate is the gate with stone towers and a cauldron added. Docks turn to face the water. |
| **MultiMesh** | Only the farm field's 20 wheat stalks (one MultiMesh per field, phase 3D). Buildings are otherwise one `MeshInstance3D` each. |
| **Saves** | A building saves its type, cell, hit points and stored items. Nothing about its model. |

Sizes of the three prototyped types (old):

| Type | Footprint | Height | Surfaces | Triangles |
|---|---|---|---|---|
| Cottage (`house`) | 0.95 × 0.85 m | 1.65 m (roof peak) | 2 (baked body + glowing window) | 92 |
| Stone wall (`stone_wall`) | 1.0 × 0.8 m | 1.65 m (merlons) | 1 | 72 |
| Archer tower (`archer_tower`) | 1.05 × 1.05 m | 3.95 m (roof tip) | 1 | 436 |

## Step 2: asset research

| Source | Licence | What it has | Verdict |
|---|---|---|---|
| **Poly Haven** | CC0 | 522 models; nothing like a cottage, tower or castle wall. The nearest are `modular_fort_01` (28,000 triangles), `large_castle_door` and `large_iron_gate` (12,600–38,100 triangles), all photoscanned. | Not suitable: no buildings, and photoreal and far too heavy. |
| **Quaternius: Medieval Village MegaKit** (Standard, free) | CC0 (quaternius.com, `License`) | 300+ **modular** pieces: walls (brick, plaster, timber), floors, roofs, doors, windows, chimneys, balconies. 153 MB zip. | Good-looking and the same artist as the nature models, but every building would have to be assembled from pieces. It uses several materials (one per surface type), and has no defensive towers or fortification walls. The better choice for a later, fuller pass at cottages. |
| Quaternius: Medieval Village Pack, Modular Medieval Buildings, Ultimate Fantasy RTS | CC0 | Ready-made medieval houses, walls and towers | Distributed through Google Drive folders, which this session can't download from. |
| **KayKit Medieval Hexagon Pack 1.0** (Kay Lousberg) | **CC0** (`LICENSE.txt`: "free to use in personal, educational and commercial projects") | 200+ medieval buildings, walls and props, each a **single mesh on one shared palette atlas** (1024², 16 KB), glTF. Includes cottages (`building_home_A/B`), towers (`building_tower_A/B`), walls (`wall_straight`, corners, gates). Published by the author on GitHub. | **Chosen.** Ready-made, already close to the game's one-tile scale, one material for everything, light enough for the browser. |

**Licence check.** KayKit's CC0 allows commercial use and redistribution, and attribution is optional. Credit is given in `game/models/CREDITS.md` anyway, with the source path of every file.

## Step 3: the prototype

| Type | KayKit model | Changes | Size (w × h × d) | Triangles | Surfaces |
|---|---|---|---|---|---|
| Cottage | `building_home_A_yellow` (half-timbered, straw-yellow roof like the old thatch) | Scaled 2.58× | 2.04 × 2.40 × 2.20 m | 1,011 (Godot LOD 727) | 1 |
| Stone wall | `wall_straight` | Cut to 1 m (the pack's walls run 2 m along hexagon edges; only 3 of its 504 triangles crossed the cut), raised 2.08× and thickened 1.5× | 1.00 × 2.29 × 1.20 m | 259 | 1 |
| Archer tower | `building_tower_A_red` (stone tower, red roof like the old one) | Tower and roof merged into one mesh; 1.75× wide, 2.43× tall | 1.74 × 5.33 × 2.02 m | 2,138 (Godot LOD 1,376) | 1 |

- **Same tile, same placement, drawn larger.** Each model is centred on its tile like the old one, with the front facing +z. After review ("make them larger", then "bigger still") they were scaled up twice, so they now tower over the people. The cottage and tower overhang their tile by up to 0.5 m each side. That changes only how they look: collision, placement and building rules still use the one tile. Two cottages built side by side overlap, and cottages two tiles apart touch at the roofs.
- **Walls still turn.** They run east–west, and turn north–south with `line_up()` exactly as before.
- **The tower is taller than the old one** (5.33 m against 3.95 m). Its arrows now start from the top-floor windows (4.4 m), a one-line visual change in `shoot()`; the old tower's arrows still start at 3 m.

## Step 4: implementation and optimisation

- **Asset preparation (offline, repeatable):** `last-light/tools/prepare_building_models.py <pack>/Assets/gltf/buildings game/models/buildings`. It:
  - merges every node into one mesh with one surface, applying the node transforms;
  - scales and cuts the models, and keeps only the vertices used;
  - writes a texture-less `.glb` per building;
  - writes the shared atlas at **128 × 128**. The pack's 1024² palette is made of flat colour blocks: at 128² no colour the three models use changes by more than 1/255, for 1/64th of the texture memory. The first build used the full 1024² atlas, and its GPU-compressed copy with mipmaps added 0.8 MB to the download and 0.6 MB of texture memory.

  The output is 190 KB in all: cottage 56 KB, wall 18 KB, tower 114 KB, atlas 1.7 KB (11 KB as a GPU texture).
- **In the game** (`structure.gd`, `BUILDING_MODELS`):
  - `_build_model()` adds one `MeshInstance3D` named `Model`, using a mesh loaded once and shared by every building of that type, with **one `StandardMaterial3D` shared by all three types** (the atlas, roughness 0.9 like every other building).
  - It skips the primitive parts entirely. `Art.bake()` finds nothing to merge, and the model is added to the building's drawn parts afterwards. So previews, the hit flash, the damage lean and removal all work on it unchanged.
- **Phase 3D architecture kept.** One surface and one shared material per building, no more than the baked buildings. The cottage has a second small surface for its glowing windows, drawn with the old window's shared glow material, exactly like the old cottage.
- **Texture atlas.** All three share one 128² palette atlas, imported with mipmaps and GPU (S3TC/BPTC) compression. No normal maps, no transparency.
- **LOD.** Godot's automatic mesh LOD, generated at import, verified working in the Compatibility renderer in phase 4A. The cottage drops to 727 triangles and the tower to 1,376 at a distance. The wall is too simple to reduce.
- **Collision** stays tile-based, as before. The models have no collision shapes and need none.
- **`?buildings=0`** turns the models off (set in `main.gd` before any building is made).

## Step 5: functional validation

The smoke test (`tools/smoke_test.gd`, run by CI) has four new checks, and every existing check still passes:

| Check | Result |
|---|---|
| A cottage, a stone wall and an archer tower build as the new models: one mesh and one surface each, sharing one material, with the same hit points; they block movement on their tile | ok |
| A second cottage reuses the same mesh | ok |
| A damaged cottage leans; a tower's build preview is see-through and casts no shadow | ok |
| Taking a new cottage down removes it | ok |
| After saving and reloading, the cottage, wall and tower load back as models, with the same damage | ok |

The existing checks also cover:
- building on grass clears it, and taking the building down brings it back;
- walls block, before and after a reload;
- purge raiders break walls;
- settlers move into cottages;
- the vault keeps its gold.

Seen in the renders (`tools/building_shots.gd`), at close, middle and far zoom and in first person, day and night, spring and winter:
- previews tint green and red;
- the damaged cottage leans;
- the walls turn the corner;
- the torch post still lights the buildings at night.

**Differences found:**
- **Night window glow: restored.** The first build lost the old cottage's softly glowing window. The prep script now copies the cottage model's window-glass triangles (5 arched windows, 45 triangles, told apart by their grey in the atlas) 4 mm in front of the glass, into a second surface of the same mesh. The game draws that surface with **the very same shared glowing material the old cottage window used** (`Art.shared_material(Color(1.0, 0.85, 0.5), 0.8)`), so it adds no new material. A cottage is again 2 surfaces, exactly like the old one. See `perf/buildings/night-window-glow.png`.
- **Headless test noise.** In headless test runs only (Godot's dummy renderer), the phase 4A far-version and shadow-proxy instances log "Cannot set a buffer on a Multimesh…" because the dummy renderer doesn't keep instance buffers. It never appears with a real renderer (browser benchmark, native renders, the GPU-validation self-check), so players are unaffected.

## Step 6: visual validation

Images in `perf/buildings/`:

| Image | Shows |
|---|---|
| `before-after-showcase.jpg` | Three cottages (the middle one badly damaged), a stone wall turning a corner, an archer tower, a torch post, and green/red build previews, at close, middle and far zoom from two sides |
| `before-after-views.jpg` | First person at the cottages and behind the wall; night; winter |
| `before-after-village.jpg` | The benchmark village (4 cottages and a tower among the other buildings), day and night |

- **Fit:** the half-timbered cottages, crenellated stone wall and stone tower read clearly as medieval. They sit well with the stylised low-poly Quaternius characters and the MegaKit nature.
- **Style:** KayKit's palette is brighter and more pastel than the old flat colours, most noticeably the wall's terracotta walkway and pale stone. The unconverted buildings around them (wooden walls, gates, barracks) still look like the old primitives, which is expected until more types are converted.
- **Scale:** the models were enlarged twice after review. Cottages (2.40 m) and walls (2.29 m) now stand well above a 1.58 m character, and the tower is 5.33 m. Cottages and towers overhang their tile by up to 0.5 m each side, so cottages built close together overlap (images are of the final sizes).

## Step 7: performance

### One of each building (`tools/building_audit.gd`)

| Type | Surfaces (draw calls per pass) | Materials | Triangles | Godot LOD | Lights |
|---|---|---|---|---|---|
| Cottage | 2 → 2 (building + glowing windows) | 2 → 2 (both shared) | 92 → 1,056 (1,011 + 45 glass) | 727 | 0 → 0 |
| Stone wall | 1 → 1 | 1 → 1 | 72 → 259 | — | 0 → 0 |
| Archer tower | 1 → 1 | 1 → 1 | 436 → 2,138 | 1,376 | 0 → 0 |

All three new models share **one** building material. The cottage's windows reuse the old window's shared glow material. The audit and benchmark below were measured before the window glow was restored, which adds one 45-triangle surface per cottage: the same as the old cottage's window.

### Browser benchmark

Measured before the models were enlarged. Enlarging changes only their vertex positions, not their triangles, surfaces or materials; only their shadows and screen coverage grow a little.


The same web build, with `?buildings=0` (old) and without, run in the project's benchmark (`perf/run_web_bench.cjs`, Chromium and ANGLE on Mesa llvmpipe, 1280×720, fixed seed). Results are in `perf/buildings/web-buildings0.json` and `web-buildings1.json`. The benchmark village has 4 cottages and an archer tower among 46 buildings (its walls are wooden), so the village rows measure 5 converted buildings.

| Scene | Draw calls | Primitives | Mesh surfaces | Frame time p50 | Frame time p95 | Video memory | Texture memory |
|---|---|---|---|---|---|---|---|
| Village | 592 → 582 | 2.17 → 2.18 M | 714 → 710 | 798 → 816 ms | 2,059 → 2,053 ms | 39.6 → 39.8 MB | 9.3 → 9.3 MB |
| Village + 10 soldiers | 613 → 605 | 1.96 → 1.97 M | 765 → 761 | 798 → 795 ms | 922 → 840 ms | 50.3 → 50.4 MB | 9.4 → 9.4 MB |
| Village + 30 soldiers | 713 → 705 | 2.18 → 2.19 M | 867 → 863 | 918 → 939 ms | 979 → 1,114 ms | 62.3 → 62.5 MB | 9.8 → 9.8 MB |
| Night village + 30 soldiers | 793 → 786 | 2.68 → 2.70 M | 869 → 865 | 1,050 → 1,051 ms | 1,227 → 1,168 ms | 62.3 → 62.5 MB | 9.8 → 9.8 MB |
| Forest (no buildings) | 339 → 340 | 2.40 → 2.42 M | 555 → 555 | 1,482 → 1,403 ms | 1,672 → 1,758 ms | 31.6 → 31.6 MB | 9.2 → 9.2 MB |

| | Old | New | Change |
|---|---|---|---|
| Download: `index.pck` (vs `main` at 5a9f738) | 3.59 MB | 3.70 MB | **+110 KB** (+101 KB gzipped); `index.wasm` unchanged |
| Load to first frame (same build) | 13.4 s | 14.2 s | +0.8 s, within run-to-run variation (12.1–13.8 s in the earlier pair) |
| Texture memory | 9.3 MB | 9.3 MB | +11 KB (the atlas) |
| Video memory, village | 39.6 MB | 39.8 MB | +0.2 MB (vertex buffers) |

How to read this:
- **Draw calls fell slightly** (−1%) and mesh surfaces by 4, because the first build had no glowing-window surface. With the glow restored, cottages are back to 2 surfaces, so draw calls match the old buildings.
- **Primitives rose by 0.5–1%** in the village scenes. The models have more triangles, but 5 buildings are a small share of a village frame, and Godot's LOD trims them at a distance.
- **Frame times are within noise.** Differences go both ways, and the same scene varied by up to ±10% between runs on this software renderer.
- **Memory and download cost almost nothing**, once the atlas was shrunk. With the pack's 1024² atlas, the first run cost +0.8 MB of download and +0.6 MB of texture memory.
- **Converting every building type would cost more.** With all 17 types converted at similar triangle counts, a village of 46 buildings would draw about 40,000–60,000 more triangles. That's small next to the 2 million primitives in a village frame, but worth measuring again at that point.

## Recommendation

1. **Review the look** in the images, or live with `?buildings=0` for comparison after a merge. In particular: the brighter KayKit palette, and buildings now overhanging their tile.
2. **If the style is right**, the same pipeline (`prepare_building_models.py`, `BUILDING_MODELS`) converts the other types. KayKit has matching models for most of them: barracks, blacksmith (forge), market, tavern, well, wooden fences and gates, walls with gates, and destroyed and scaffolding states for future damage and construction visuals.
3. **For richer cottages later,** Quaternius's Medieval Village MegaKit can assemble larger, more detailed houses, at the cost of a few materials per building.
