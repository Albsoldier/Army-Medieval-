# Islander: character prototype, the player (phase 4C)

**Status:** prototype on branch `claude/character-prototype`, not merged. Only the player's model is replaced, by a **ranger** built from Quaternius's CC0 character kits. Soldiers, settlers, raiders, wolves and horses are unchanged. `?player=0` (or `-- --player=0` natively) shows the old adventurer for comparison.

Unchanged:
- movement, combat, damage, health, stamina and statistics;
- networking, saves, the Workers, Turso and world generation;
- the prop chunks (3B), terrain and grass (3C);
- the draw-call architecture (3D). The player is still one skinned mesh, one surface and one material.

## Phase 1: the character system before this change

| Part | How it works |
|---|---|
| **The model** | `player.gd` builds a `CharacterModel` (`scripts/character_model.gd`) from `models/adventurer.glb`: Quaternius's low-poly adventurer, from the CC0 `@netforge` bundle. It has 5 meshes (feet, legs, body, head, backpack), 15 surfaces, 11 plain-colour materials, 10,198 triangles, and a 62-bone skeleton (`Root`, `Hips`, `Torso`, `Chest`, `Neck`, `Head`, `Wrist.L/R`, fingers, legs). Soldiers and settlers use the same model. |
| **`CharacterModel.build()`** | Instances the scene, then: **`_fit`** scales it so its bones span the target height (1.62 m for the player); **`_map_actions`** maps game actions to the model's own animations by name ending (`idle` → `Man_Idle` or `Idle`, `run`, `walk`, `punch`, `slash`, `death`), looping idle, walk and run; **`_recolor`** recolours materials by name (the player's shirt is dark green); **`_enhance`** gives each material a finish by name (rim light on skin and hair, shiny metal); **`_merge_meshes`** merges the meshes. |
| **Mesh merging (phase 3D)** | `_merge_meshes` joins every skinned mesh into **one skinned surface** drawn with `shaders/character.gdshader`. Each vertex carries its old material's colour, roughness, metallic, specular and rim, and the skins are joined (5 × 62 = 310 binds) with re-numbered bone indices. So the player went from **5 meshes, 15 surfaces and 15 materials to 1, 1 and 1**. It only handles plain-colour materials, refusing textures, glow and transparency. |
| **Animation** | The model's own `AnimationPlayer`. `play()` loops, cross-fading 0.2 s; `play_once()` plays attacks and death (0.1 s cross-fade) and blocks loops until done. `player.gd` plays idle or run each frame, punch or slash on a swing, and death. |
| **Equipment** | `bone_follower(bone)` adds a `BoneAttachment3D`. The player follows `Palm.R` and `Palm.L` (this model has `Wrist.R/L`, a built-in fallback), `Torso` and `Neck`. The spear, sword, axe and pickaxe (right hand), torch (left hand) and armour (between chest and neck) are separate procedural models placed on those followers every frame (`tick_visuals`). The lantern hangs at the hip; a ridden horse is its own model. The player has no shield, bow or helmet; those are soldiers' kit. |
| **Third person** | The model turns to face the way you walk and casts shadows (soldiers don't, phase 3D). |
| **First person** | `set_first_person(true)` sets the body's meshes to **shadows only**: you see your shadow but not your body. The held tool and torch are drawn in front of the camera (`place_view_model`). |
| **Hurt flash** | `flash(on)` puts a see-through red `material_overlay` on the model's meshes while `hurt_flash` counts down. |

## Phase 2: assets

| Candidate | Licence | Verdict |
|---|---|---|
| **KayKit Adventurers 1.0** (Kay Lousberg): Knight, Barbarian, Rogue, Rogue (hooded), Mage | CC0 (`LICENSE.txt`) | Well made, with 76 animations each and one texture each, and the same artist as the phase 4B buildings. But the characters are **chibi**: huge heads, stubby bodies, big hands. Next to the realistic-proportioned soldiers, settlers and raiders, a chibi player would clash, and the brief asks for better body proportions. |
| **Quaternius: Modular Character Outfits – Fantasy**, **Universal Base Characters** and **Universal Animation Library** (Standard, free editions) | **CC0 1.0** for each, stated in each kit's own licence file (checked separately for all three) | **Chosen.** Realistic proportions and detailed textured outfits (the ranger: leather tunic, belts, buckled bracers, a metal pauldron, laced boots, a hood). **All three use the same 65-bone humanoid skeleton**, so the library's animations play on the outfit with no retargeting. Same artist as the phase 4A nature models. |

Downloaded once from itch.io (quaternius.itch.io; 15, 122 and 280 MB). **Only these files were used:**

| From | File | Used for |
|---|---|---|
| Modular Character Outfits – Fantasy | `Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf` (+ `.bin`, `T_Ranger_BaseColor/Normal/ORM.png`, `T_Regular_Male_Dark_BaseColor/Normal/Roughness.png`) | the outfit and hands |
| Universal Base Characters | `Base Characters/Godot - UE/Superhero_Male_FullBody.gltf` (+ textures) | the head (only the head and neck), eyes, eyebrows |
| Universal Base Characters | `Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Beard.gltf` | the beard |
| Universal Animation Library | `Unreal-Godot/UAL1_Standard.glb` | six animations |

Source and licence are recorded in `game/models/CREDITS.md`.

## Phase 3: the prototype

`game/tools/build_player_model.gd` (run headless, twice, importing in between) builds `models/player/ranger.scn`:

- **The parts:**
  - all 10 ranger outfit meshes;
  - from the base body, **only triangles mostly on the head or neck bones** (2,852 of 12,566); the outfit covers the rest, and the full body shows through it;
  - the eyes and eyebrows;
  - a beard, its grey hair texture tinted dark brown.
- **One surface, one material.** Every part is merged into a single skinned surface:
  - identical skin binds are shared: 123 binds, not 65 per part;
  - UVs are moved into a **texture atlas**: colour 2048 × 1024 with the outfit at 1024², normal and roughness/metal at 1024 × 512, all cut down from the kit's 4096² and 2048² textures;
  - one `StandardMaterial3D` uses the atlas, its normal map, and roughness (G) and metal (B) from the ORM atlas;
  - Godot's mesh LODs are generated (3 levels).
- **Animations.** Six from the Universal Animation Library, renamed to the names `player.gd` already looks for, so **the animation system is unchanged**:

  | Game action | Animation name in the model | From the library |
  |---|---|---|
  | idle | `Idle` | `Idle_Loop` |
  | walk | `Walk` | `Walk_Loop` |
  | run | `Run` | `Jog_Fwd_Loop` |
  | punch | `Punch_Right` | `Punch_Jab` |
  | slash | `Sword_Slash` | `Sword_Attack` |
  | death | `Death` | `Death01` |

- **Size.** `_fit` scales the ranger like the adventurer: bones spanning 1.62 m. Movement, collision and hit distances are in game units and unaffected.

The game's changes are small:

- `player.gd` loads `models/player/ranger.scn` (or the adventurer with `?player=0`). The action map and everything else stay the same.
- `character_model.gd`:
  - **bone aliases**, so equipment follows the same body parts on the humanoid rig: `Palm.R/L` → `hand_r/l`, `Torso` → `spine_01`, `Neck` → `neck_01`;
  - a model that arrives as one skinned surface counts as `merged`, so the phase 3D check holds.

## Skeleton compatibility

| | Old adventurer | Ranger |
|---|---|---|
| Skeleton | 62 bones, Quaternius "CharacterArmature" (`Torso`, `Wrist.R`, …) | 65 bones, humanoid (`spine_01–03`, `neck_01`, `Head`, `hand_r`, full fingers, `ball_l/r`) |
| Animations | 24, in the model | 6 from the Universal Animation Library, same skeleton (verified: the bone lists are identical in the outfit, the base body, the hair and the library) |
| Retargeting | — | **None needed** |

## Phases 4–6: equipment and function

Smoke test (`tools/smoke_test.gd`, run by CI): every existing check passes. They include combat, damage, the hurt timer, equipping tools, armour and lantern, riding, death and respawn, and save/load. New checks:

| Check | Result |
|---|---|
| The player is the ranger model (its humanoid rig) | ok |
| One skinned surface with one material, all six animations, and the hand, chest and neck followers for equipment | ok |
| In first person the ranger only casts a shadow | ok |
| After loading a save, the player is the same ranger model, with its animations | ok |
| The phase 3D check, "the player is one skinned surface too" | ok |

Renders (`tools/player_shots.gd`, `perf/character/`):

| Image | Shows |
|---|---|
| `before-after-poses.jpg` | idle, walk, run, punch, sword slash, death; front, side and back |
| `before-after-gear.jpg` | sword, spear, axe and pickaxe in the right hand, at rest and mid-swing; torch in the left hand; armour on; the hurt flash |
| `before-after-views.jpg` | the game camera close and middle, day and night (torch lit); first person |

Equipment follows the hands through every animation. The armour breastplate and the lantern are the game's existing procedural pieces, placed on the ranger's chest and hip.

PERF_SECTION

## Known limitations

- **Heavier mesh.** 32,620 triangles against the adventurer's 10,198. Godot's LODs reduce it at a distance. There's one player, so it's a small share of a frame (see above), but the same model for 30 soldiers would need a lighter version.
- **Coarse armour.** The procedural iron breastplate is coarse next to the detailed outfit. A proper armour piece, such as the kit's pauldrons or a breastplate model, would suit it better.
- **Hood always up.** The ranger always wears his hood, with hair under it. The kit's hairstyles are available if a hood-down variant is wanted.
- **Second colourway unused.** The kit's second ranger colourway (beige linen and browns, `T_Ranger_3_BaseColor`) would work as an alternative look.
- **Soldiers, settlers, raiders and wolves are unchanged** by design. They still use the old low-poly models.
