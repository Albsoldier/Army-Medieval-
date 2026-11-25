# Islander: environment and vegetation prototype (phase 4A)

**Status:** step 1 (audit) done; step 2 (assets) waiting on the asset download; steps 3–6 to follow.

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

*(To be filled in once the assets are in.)*

Sources checked:
- **Poly Haven (CC0):** unsuitable. Its trees are photoscanned at 7–17 million triangles (pine_tree_01 17.4 M, fir_tree_01 7.9 M) and even its rocks at 60 k+, with high-resolution photo textures. That's photoreal against the game's flat low-poly style, and far beyond what a browser can draw thousands of.
- **Quaternius Stylized Nature MegaKit (CC0, confirmed on https://quaternius.com/packs/stylizednaturemegakit.html: "License CC0"):** 116 stylized models in glTF, including 40 trees, 27 rocks, and bushes. It matches the game's existing Quaternius characters. Its download goes through itch.io (https://quaternius.itch.io/stylized-nature-megakit).
- **Quaternius low-poly nature models** in the CC0 bundle the characters came from (`@netforge/asset-library-files`): tree_pine 230, tree_oak 196, rock_large 80 and bush 32 triangles. Simpler than today's shapes, so little visual gain.
