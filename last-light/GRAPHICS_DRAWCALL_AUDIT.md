# Islander: draw-call audit (phase 3D, task 1)

This audit is what the changes in [GRAPHICS_DRAWCALL_OPTIMIZATION.md](GRAPHICS_DRAWCALL_OPTIMIZATION.md) were based on. It describes the code on `main` after phases 3B and 3C (prop culling, and terrain and grass streaming).

The counts come from `tools/drawcall_audit.gd`. It builds the benchmark village, spawns one character of each kind, and counts mesh nodes, **surfaces** (one draw call per pass the object is drawn in), distinct materials and lights. The draw calls are from the browser benchmark.

**[M]** marks measured values and **[E]** estimates.

## 1. Where the draw calls come from

A **surface** costs one draw call in every pass that draws it:
- the colour pass;
- each sun-shadow cascade it falls in (buildings cast shadows; soldiers don't: `soldier.gd` turns their shadows off);
- each omni light whose range it touches, at night or near torches and the forge. In the Compatibility renderer every such light is an extra pass.

Browser measurements on `main` **[M]**:

| Scene | Draw calls | Visible mesh nodes | Their surfaces |
|---|---|---|---|
| Empty area | 337 | 188 | 273 |
| Forest | 338 | 184 | 269 |
| Village (46 buildings, 4 settlers) | 1,556 | 739 | 864 |
| Village + 10 soldiers | 1,772 | 891 | 1,116 |
| Village + 30 soldiers | 2,273 | 1,195 | 1,620 |
| Night village + 30 soldiers | 2,427 | 1,197 | 1,622 |

Building the village adds about 1,200 draw calls, and each soldier adds about 23.

## 2. Buildings [M]

Every building is assembled from Godot primitive meshes by `Art.part()`. **Each part is its own `MeshInstance3D` with its own new `StandardMaterial3D`**, so a building costs one surface, and one material, per part.

| Building | In village | Mesh nodes each | Surfaces each | Total surfaces | Distinct materials | Lights |
|---|---|---|---|---|---|---|
| Wooden wall | 20 | 9 | 9 | **180** | 180 | 0 |
| Farm field | 6 | 25 | 25 | **150** | 150 | 0 |
| Cottage | 4 | 7 | 7 | 28 | 28 | 0 |
| Torch post | 6 | 3 | 3 | 18 | 18 | 6 |
| Archer tower | 1 | 17 | 17 | 17 | 17 | 0 |
| Gate | 2 | 7 | 7 | 14 | 14 | 0 |
| Treasure vault | 1 | 12 | 12 | 12 | 12 | 0 |
| Storage chest | 2 | 4 | 4 | 8 | 8 | 0 |
| Workbench | 1 | 8 | 8 | 8 | 8 | 0 |
| Barracks | 1 | 5 | 5 | 5 | 5 | 0 |
| Forge | 1 | 4 | 4 | 4 | 4 | 1 |
| Smokehouse | 1 | 4 | 4 | 4 | 4 | 0 |
| **46 buildings** | | | | **448** | **448** | 7 |

- **Most draw calls:** wooden walls (9 parts each: 4 logs, 4 tips, 1 rail) and farm fields (a soil box, 4 furrows and **20 separate wheat stalks**). Together they're 330 of the 448 surfaces.
- **Static vs. moving.** A building's parts never move relative to each other. The building as a whole leans when damaged, shrinks briefly when hit, and docks and walls turn. All of those are transforms of the building's own node, so the parts can share one mesh.
- **Parts that change.**
  - **Wheat stalks** change height and colour as the field grows (20 stages), so they need their own instances.
  - **Glowing parts** (torch flames, forge coals, the oil cauldron, the vault's gold lock and coins, chest locks, cottage windows) use an emissive or unshaded `StandardMaterial3D`. Their glow colour is a per-material setting, so they can't share a plain material.
  - **Lights** (torch posts, the forge, oil gates) are `OmniLight3D` nodes, not meshes.
- **The build preview** (`make_ghost`) swaps every part's material for a see-through one.
- **Collision and interaction** don't use these meshes. They use the tile grid (`world.structures`, `is_walkable`, `buildings`).

## 3. Characters [M]

### The model

`models/adventurer.glb` is used for the player, soldiers and settlers. `raider.glb` is used for raiders.

| Model mesh | Surfaces | Materials |
|---|---|---|
| Adventurer_Feet | 2 | Black, Grey |
| Adventurer_Legs | 2 | Brown2, Brown |
| Adventurer_Body | 3 | Green, LightGreen, Skin |
| Adventurer_Head | 4 | Skin, Eyebrows, Eye, Hair |
| Backpack | 4 | Brown, Green, LightGreen, Gold |
| **Total** | **15 surfaces** | **11 materials** |

- **Skins:** each mesh has its **own `Skin`**, 62 binds each, with different bind poses, all on one `Skeleton3D`.
- **Materials are plain colours.** Every material is a `StandardMaterial3D` with no texture, opaque, back-face culled, and per-pixel shaded. They differ only in albedo colour, roughness, metallic and specular. `CharacterModel._enhance()` then sets per-material roughness, metallic, specular and rim light by material name (skin, hair, metal, eyes, fur).
- **Materials are copied per character.** `CharacterModel._recolor()` and `_enhance()` **duplicate every material for every character**, so 30 soldiers carry about 450 material copies.
- `raider.glb` has 4 skinned meshes and 1 unskinned one (a sword on a bone), 17 surfaces in all.
- **Horses** (`horse.glb`, 4 meshes, 1 vertex-colour material) show or hide their barding, saddle and bridle **mesh by mesh**, and tint the horse and tack differently.
- **Wolves** (1 mesh, 4 surfaces) have **glowing eyes**, an emissive material.

### Surfaces per character (draw calls per pass)

| Character | Mesh nodes | Surfaces | Materials | Made of |
|---|---|---|---|---|
| Legionary | 15 | **25** | 25 | Model 15, helmet 3, shield 5, spear 2 |
| Archer | 16 | **26** | 26 | Model 15, cap 1, bow 6, quiver 1, arrows 3 |
| Centurion | 16 | **26** | 26 | Model 15, helmet 3, shield 5, spear 2, cloak 1 |
| Cavalry | 14 | **24** | 24 | Model 15, horse 4, helmet 3, lance 2 |
| Settler | 7 | 17 | 17 | Model 15, straw hat 2 |
| Raider | 10 | 22 | 22 | Model 17, shield 3, axe 2 |
| Player | 5 | 15 | 15 | Model 15 (plus tools in hand) |
| Wolf | 1 | 4 | 4 | Model 4 |

**Static vs. independent transforms:**
- **The kit follows bones.** Helmets, shields, spears, bows and hats are separate top-level nodes that follow a bone each frame: the head, or the left or right hand. Within one piece the parts never move relative to each other. Between pieces they do, so each piece needs its own transform.
- **Worn pieces follow the body.** The archer's quiver and arrows, the centurion's cloak and a raider chief's mantle are attached to the character's body node.
- **The model is skinned and animated.** It must stay skinned to its skeleton.
- **Other nodes:** the selection ring (shown only when selected) and the name label are separate and rarely visible.

## 4. Lights

- **Torch posts:** 6 in the village, always lit.
- **The forge:** 1.
- **The player:** torch, lantern and a faint self-glow.

In the Compatibility renderer each light touching an object adds a pass for it. That's the main source of the about 150 extra draw calls between the day and night village with 30 soldiers **[M]**. This phase leaves lights unchanged.

## 5. What can be merged safely

| What | Can merge? | Why |
|---|---|---|
| A building's plain parts | **Yes, into one mesh, one shared material** | Static relative to each other; per-part colour can be a vertex colour |
| A building's glowing parts | Separate, but can **share** a material per colour and glow | Glow colour is per-material |
| Wheat stalks | **Into one MultiMesh per field** | Same mesh; height and colour per instance |
| Each kit piece's parts | **Yes, one mesh per piece** | Move together; each piece follows its own bone |
| Worn pieces (quiver, cloak, mantle) | **Yes, one mesh per character** | Move with the body |
| A character's skinned meshes and materials | **Yes, one skinned surface**, if each part keeps its own bind poses | Plain colours only; per-material values can be stored per vertex |
| Horse meshes | No | Tack shown and hidden mesh by mesh, and tinted separately |
| Wolf | No | Glowing eyes (emissive) |
| Kit pieces with each other | No | Each follows a different bone |
| Character into static geometry | No | It's skinned and animated |
