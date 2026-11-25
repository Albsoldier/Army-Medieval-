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
