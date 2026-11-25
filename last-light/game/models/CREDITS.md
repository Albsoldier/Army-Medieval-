# Model credits

`horse.glb` is the **Barded War Horse**, a free CC0 model (vertex-coloured, rigged, with walk, idle and run
animations). Its tack (scale barding, saddle, plumed bridle) is shown on tame and war horses and hidden on wild ones,
and its coat is tinted in code.

All other models are by **Quaternius** (https://quaternius.com) and released under
**CC0 1.0** (public domain). They come from the `@netforge/asset-library-files`
CC0 bundle. No attribution is required, but credit is given anyway.

Each was decompressed (meshopt) and dequantized with glTF-Transform so Godot can import it.

| File | Original | Used for | Changes in code |
|---|---|---|---|
| `adventurer.glb` | `lowpoly/adventurer.glb` (animated adventurer) | the survivor and your soldiers | soldiers' clothes are recoloured by unit type |
| `raider.glb` | `lowpoly/hooded_adventurer.glb` | raiders and raider chiefs | leathers recoloured; chiefs get a helmet and mantle |
| `wolf.glb` | `lowpoly/wolf.glb` (animated wolf) | wolves | eyes glow; timber and dire wolves are recoloured and larger |

All characters get softer, more natural materials in `scripts/character_model.gd` (rim light on skin and fur, shiny metal).

## Nature models (`nature/`, environment prototype)

From the **Stylized Nature MegaKit** (Standard, free edition) by **Quaternius**,
https://quaternius.com/packs/stylizednaturemegakit.html, downloaded from
https://quaternius.itch.io/stylized-nature-megakit. Licence: **CC0 1.0 Universal**
(public domain dedication, stated in the kit's `License_Standard.txt`): commercial use and
redistribution allowed, no attribution required.

They were converted by `last-light/tools/prepare_nature_models.py`: scaled to the props they
replace, vertex colours replaced by per-vertex shader data, leaf normals bent outward, textures
shrunk and normal maps dropped. See `last-light/GRAPHICS_ENVIRONMENT_PROTOTYPE.md`.

| File | Original | Used for |
|---|---|---|
| `pine.glb` | `glTF/Pine_5.gltf` | pine trees |
| `oak.glb` | `glTF/CommonTree_5.gltf` | broad-leaved trees |
| `rock.glb` | `glTF/Rock_Medium_2.gltf` | boulders |
| `bush.glb` | `glTF/Bush_Common_Flowers.gltf` | berry bushes (flowers hidden once picked) |
| `bark.png` | `glTF/Bark_NormalTree.png` (2048 → 256 px) | pine and oak bark |
| `pine_needles.png` | `glTF/Leaf_Pine_C.png` (2048 → 256 px) | pine needles |
| `leaves.png` | `glTF/Leaves_NormalTree_C.png` (1024 → 512 px) | oak and bush leaves |
| `flowers.png` | `glTF/Flowers.png` (1008×981 → 128 px) | bush flowers |
| `rock.png` | `glTF/Rocks_Diffuse.png` (2048 → 256 px) | boulders |

## Building models (`buildings/`, building prototype)

From the **KayKit Medieval Hexagon Pack (1.0)** by **Kay Lousberg** (www.kaylousberg.com),
https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 (also on
https://kaylousberg.itch.io/kaykit-medieval-hexagon). Licence: **CC0 1.0 Universal**, as stated in the
pack's `LICENSE.txt`: "This content is free to use in personal, educational and commercial projects."
Redistribution allowed; crediting Kay Lousberg is appreciated but not required.

Converted by `last-light/tools/prepare_building_models.py`: every node merged into one mesh, scaled
to the one-tile buildings they replace, and the wall cut to a 1 m section. See
`last-light/GRAPHICS_BUILDING_PROTOTYPE.md`.

| File | Original | Used for |
|---|---|---|
| `cottage.glb` | `Assets/gltf/buildings/yellow/building_home_A_yellow.gltf` | cottages |
| `stone_wall.glb` | `Assets/gltf/buildings/neutral/wall_straight.gltf` (one half) | stone walls |
| `archer_tower.glb` | `Assets/gltf/buildings/red/building_tower_A_red.gltf` | archer towers |
| `hexagons_medieval.png` | `Assets/gltf/buildings/neutral/hexagons_medieval.png` (1024 → 128 px) | the shared palette atlas |

## Player model (`player/`, character prototype)

`player/ranger.scn` is built by `game/tools/build_player_model.gd` from three kits by **Quaternius**
(https://quaternius.com), free Standard editions downloaded from quaternius.itch.io. Each kit's own
`License` file states **CC0 1.0 Universal** (public domain dedication): commercial use and redistribution
allowed, no attribution required.

| Kit | Files used | For |
|---|---|---|
| Modular Character Outfits – Fantasy (https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | `Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf` and its `.bin` and textures (`T_Ranger_*`, `T_Regular_Male_*`) | the outfit and hands |
| Universal Base Characters (https://quaternius.com/packs/universalbasecharacters.html) | `Base Characters/Godot - UE/Superhero_Male_FullBody.gltf` (head, eyes and eyebrows only) and `Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Beard.gltf`, with their textures | the head and beard |
| Universal Animation Library (https://quaternius.com/packs/universalanimationlibrary.html) | `Unreal-Godot/UAL1_Standard.glb` (Idle, Walk, Jog_Fwd, Punch_Jab, Sword_Attack, Death01) | the animations |

The textures were packed into `player/player_colour.png`, `player_normal.png` and `player_orm.png` (one
atlas, downscaled) and every part merged into one skinned mesh. See `last-light/GRAPHICS_CHARACTER_PROTOTYPE.md`.
