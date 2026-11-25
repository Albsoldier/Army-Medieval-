# Islander: draw-call optimisation (phase 3D)

Buildings, equipment and characters are now drawn with far fewer meshes, surfaces and materials. **All three targets are met**, and the look is unchanged.

[GRAPHICS_DRAWCALL_AUDIT.md](GRAPHICS_DRAWCALL_AUDIT.md) covers what was found first.

Unchanged: gameplay, movement, combat, networking, the Workers, Turso, world generation, phase 3B prop culling, phase 3C terrain and grass streaming, lighting and shadow settings, collision and interaction, skeletons, and animations.

**Not merged.** This is for review.

### Tags used below

| Tag | Meaning |
|---|---|
| **[M]** | Measured, and valid on any machine |
| **[M-sw]** | Measured on a software GPU: only for comparing configurations |
| **[E]** | Estimate |

## Results

The browser benchmark ran on the exported web build in Chromium, with identical settings: shadow preset C, fixed seed and the same scenes. `main` is the "before" **[M]**.

| Scene | Draw calls | Target | Primitives | Frame ms [M-sw] |
|---|---|---|---|---|
| Empty area | 337 → **307** | — | 2,144,535 → 2,141,931 | 466 → 482 |
| Forest | 338 → **310** | — | 2,676,377 → 2,673,645 | 563 → 579 |
| Village | 1,556 → **567** (−64%) | < 1,000 ✅ | 2,300,780 → 2,315,289 | 507 → 505 |
| Village + 10 soldiers | 1,772 → **608** (−66%) | — | 2,364,499 → 2,410,980 | 548 → 505 |
| Village + 30 soldiers | 2,273 → **705** (−69%) | < 1,500 ✅ | 2,563,663 → 2,629,250 | 764 → 625 |
| Night village + 30 soldiers | 2,427 → **790** (−67%) | < 1,700 ✅ | 3,105,852 → 3,188,115 | 845 → 747 |

### Meshes, surfaces and memory [M]

| Scene | Visible mesh nodes | Surfaces | Video memory | Buffers | JS heap* |
|---|---|---|---|---|---|
| Empty area | 188 → 184 | 273 → 259 | 29.2 → 30.3 MB | 20.6 → 21.8 MB | 127.7 → 54.8 MB |
| Forest | 184 → 180 | 269 → 255 | 28.9 → 30.1 MB | 20.2 → 21.4 MB | 136.2 → 63.2 MB |
| Village | 739 → **339** | 864 → **414** | 32.8 → 38.2 MB | 24.0 → 29.4 MB | 107.2 → 107.4 MB |
| Village + 10 soldiers | 891 → **390** | 1,116 → **465** | 38.9 → 48.9 MB | 29.9 → 40.0 MB | 71.3 → 73.8 MB |
| Village + 30 soldiers | 1,195 → **492** | 1,620 → **567** | 51.2 → 60.9 MB | 41.8 → 51.7 MB | 116.2 → 73.6 MB |
| Night village + 30 | 1,197 → **494** | 1,622 → **569** | 51.2 → 60.9 MB | 41.8 → 51.7 MB | 114.7 → 67.4 MB |

\*Chrome's JS heap moves with garbage collection and is only a rough figure.

- **Primitives** are 0–3% higher. A merged building or character is culled as one unit, so a part that used to be culled on its own is now drawn with the rest.
- **Frame time** on the software GPU is the same or better. The saving is mostly CPU-side, in WebGL and ANGLE call overhead, which a software GPU underplays. Real-GPU frame times need the benchmark run in Chrome (`?bench=1&perf=1`).
- **Memory:** about +5 MB for the village, and about +10 MB once soldiers are present. See Limitations.

### The village in numbers [M]

From `tools/drawcall_audit.gd`, counting the whole village scene:

| | Before | After |
|---|---|---|
| Mesh nodes | 804 | **359** |
| Surfaces | 984 | **439** |
| Distinct materials | 738 | **102** |

| Building | In village | Surfaces each | Total surfaces | Materials (all of this kind) |
|---|---|---|---|---|
| Wooden wall | 20 | 9 → **1** | 180 → **20** | 180 → **1** |
| Farm field | 6 | 25 → **2** | 150 → **12** | 150 → **1** |
| Cottage | 4 | 7 → 2 | 28 → 8 | 28 → 2 |
| Torch post | 6 | 3 → 2 | 18 → 12 | 18 → 2 |
| Archer tower | 1 | 17 → **1** | 17 → 1 | 17 → 1 |
| Gate | 2 | 7 → 1 | 14 → 2 | 14 → 1 |
| Treasure vault | 1 | 12 → 7 | 12 → 7 | 12 → 3 |
| Storage chest | 2 | 4 → 2 | 8 → 4 | 8 → 2 |
| Workbench | 1 | 8 → 1 | 8 → 1 | 8 → 1 |
| Barracks | 1 | 5 → 1 | 5 → 1 | 5 → 1 |
| Forge | 1 | 4 → 2 | 4 → 2 | 4 → 2 |
| Smokehouse | 1 | 4 → 1 | 4 → 1 | 4 → 1 |
| **All 46** | | | **448 → 71** | |

| Character | Mesh nodes | Surfaces (draws per pass) | Materials |
|---|---|---|---|
| Legionary | 15 → 5 | 25 → **5** | 25 → 3 |
| Archer | 16 → 4 | 26 → **4** | 26 → 2 |
| Centurion | 16 → 6 | 26 → **6** | 26 → 3 |
| Cavalry | 14 → 7 | 24 → **7** (the horse is unchanged) | 24 → 6 |
| Settler | 7 → 2 | 17 → **2** | 17 → 2 |
| Raider | 10 → 4 | 22 → **6** | 22 → 5 |
| Player | 5 → 1 | 15 → **1** | 15 → 1 |
| Wolf | 1 → 1 | 4 → 4 (unchanged) | 4 → 4 |

## The optimisations

### 1. Buildings: one mesh, one shared material (`Art.bake`, `structure.gd`)

- **Merging.** After a building is built from its parts, `Art.bake()` merges every plain part into **one `ArrayMesh`**. Each part's vertices are moved by the part's own position, turn and scale, so every part keeps its place.
- **Colour.** Each part's colour becomes the **vertex colour** of its vertices.
- **One material.** The whole mesh is drawn with **one material shared by every building**: `vertex_color_use_as_albedo` and `vertex_color_is_srgb`, at roughness 0.9.
  - I checked this with the real OpenGL renderer: a vertex colour renders exactly like the same albedo colour (`7a5633` both, for `7a5634`).
- **Glowing and unshaded parts.** Torch flames, forge coals, the oil cauldron, the vault's gold, chest locks and cottage windows can't share that material, because their glow colour is per-material. They stay separate meshes, but on **shared** materials (one per colour and glow) instead of a copy each.
- **Shared meshes.** Every building of a kind is built the same way, so they share one merged mesh (cached by kind).
- **Wheat.** A field's 20 wheat stalks are **one MultiMesh**. Growing updates the 20 instances' height and colour in place, with the same height, position and colour formula as before.
- **Unchanged:**
  - **Building transforms:** placement, the north-south turn of walls, a dock's turn, the lean when damaged, and the shrink when hit.
  - **Shadows:** the merged mesh casts and receives them like the parts did.
  - **The build preview:** the ghost swaps the merged mesh's material just as it swapped each part's.
  - **Lights:** the `OmniLight3D` nodes are untouched.
  - **Collision and interaction:** they use the tile grid, not meshes.

### 2. Equipment: one mesh per piece (`soldier.gd`, `raider.gd`, `settler.gd`)

- **Per piece.** Each piece of kit (helmet, shield, spear or lance, bow, cap, axe, straw hat) is merged into one mesh with `Art.bake()`. Each piece still follows its own bone (head, left hand, right hand), as before.
- **Worn pieces.** The pieces worn on the body (an archer's quiver and arrows, a centurion's cloak, a raider chief's mantle and cloak) are merged into one mesh on the body.
- **Shared meshes.** Every soldier of a kind wears the same kit, so the merged meshes are shared by kind.
- **Glowing parts.** A shield's gold boss glows slightly, so it stays a separate mesh on a shared material.

### 3. Characters: one skinned surface (`character_model.gd`, `shaders/character.gdshader`)

The adventurer model had 15 surfaces in 5 meshes with 11 materials, duplicated for every character. `CharacterModel._merge_meshes()`, called after recolouring and finishing, now:

1. **Merges every skinned mesh and surface into one `ArrayMesh`, one surface.** Each vertex carries its old material's values:

   | Attribute | Holds |
   |---|---|
   | `COLOR.rgb` | Albedo |
   | `COLOR.a` | Roughness |
   | `UV` | Metallic and specular |
   | `UV2` | Rim and rim tint |

   That covers everything `_recolor()` and `_enhance()` set.
2. **Keeps skinning exact.** Each original mesh had its own `Skin` with its own bind poses. They're joined into one `Skin` (5 × 62 = 310 binds), and each vertex's bone indices are shifted to its own mesh's binds. Every vertex keeps exactly its old bones, weights and bind poses on the same `Skeleton3D`, so **animations and skeletons are unchanged**.
3. **Draws it with one shared `ShaderMaterial`** (`character.gdshader`). It sets `ALBEDO`, `ROUGHNESS`, `METALLIC`, `SPECULAR`, `RIM` and `RIM_TINT` from those attributes, with `StandardMaterial3D`'s default lighting: Burley diffuse, Schlick-GGX specular, and back faces culled.
4. **Caches the merged mesh and skin** per model and colour set: one per soldier kind, settler look, and so on.

Some things are left alone, because they need per-mesh control:
- **Unskinned meshes** (a raider model's sword on a bone).
- **Horses:** barding, saddle and bridle are shown or hidden mesh by mesh, and tinted separately.
- **Wolves:** their eyes glow, and the shader has no per-vertex glow.

`CharacterModel.build(..., merge = false)` keeps the old behaviour, and the horse uses it. The hurt flash still works: it's an overlay material on the mesh. The player's first-person shadow-only switch still finds the merged mesh.

A pitfall found and fixed during testing: the first version converted the vertex colour from sRGB to linear in the shader, and every character came out much darker. Godot hands vertex colours to a shader **already converted**. That matches the earlier tests, where a vertex colour with `vertex_color_is_srgb` equals the albedo colour. The shader now uses them as they come.

## Validation

### Smoke test (Godot 4.4.1, all pass)

The existing checks cover building placement and taking buildings down, fields growing, harvesting, combat, horses and the save and load cycle. The new ones:

| Check | Result |
|---|---|
| A wooden wall is one mesh, one surface | Was 9 |
| The build preview still shows a merged building as a see-through ghost | Pass |
| A field's wheat is one MultiMesh of 20 stalks that still grows and ripens | Pass |
| A soldier's body is one skinned surface, every part keeping its bones | Was 15 |
| The player is one skinned surface too | Pass |
| The merged body is skinned to the soldier's skeleton | 310 of 310 binds resolve to its bones |
| Wolves and horses are left as they were | Pass |

### Looks: before and after, same frozen scenes (`tools/drawcall_shots.gd`) [M]

The same scenes were rendered on `main` and on this branch with the real OpenGL renderer:
- the benchmark village with characters hidden, from four sides, by day and at night;
- a line-up of every character type (legionary, archer, cavalry, centurion, raider, raider chief, settler and the player), frozen at the same idle, running and attack poses, from the front and the back.

| Scene | What differs |
|---|---|
| **Village, day and night** | **The buildings are pixel-identical.** All differences are on wind-swayed grass and tree edges and the chimney smoke, which move with time. Torchlight and shadows match. |
| **Characters, every pose and side** | Same colours, skin, clothing, hoods, helmets, shields, spears, bows and hats. The mean difference over each character's box, grass behind it included, is **2–4 out of 255**. The equipment sits on the same bones in every pose. |

Images are in `perf/drawcalls/`:
- `before-after-village.jpg` and `before-after-characters.jpg` show the renders side by side;
- `difference-map-*.jpg` mark every changed pixel in red;
- `characters-zoomed.png` shows individual characters at 2× zoom.

### Browser export

The web build was exported with the official 4.4.1 templates and run in Chromium for every benchmark run above, including the new shaders.

## Limitations

- **About +10 MB of video memory** with soldiers present (about +5 MB in the village without them). The extra per-character cost is unchanged (about 11.7 MB for 20 more soldiers, the same as before). The rest is a roughly fixed amount per **character look**: each merged mesh carries extra per-vertex data (colour, two UV sets, bones). There's one per soldier kind, settler look, player and raider kind, roughly 1–1.5 MB each **[E]**. Could be cut later by putting the colours in a small per-look palette instead of per vertex.
- **Primitives are 0–3% higher,** because merged objects are culled as a whole.
- **Horses and wolves are unchanged.** A cavalryman's horse is still 4 surfaces, and a wolf 4. They'd need per-vertex tack visibility (horses) and glow (wolves).
- **Lights still multiply draws at night** (about +85 draw calls in the night village with 30 soldiers, against about +150 before). Lighting was out of scope.
- **A hurt character's flash** draws one extra pass over the merged surface while it lasts (0.15 s). Before, it drew one extra pass per surface.
- **No real-GPU numbers yet:** run `?bench=1&perf=1` in Chrome.
