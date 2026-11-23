# Model credits

All models are by **Quaternius** (https://quaternius.com) and released under
**CC0 1.0** (public domain). They come from the `@netforge/asset-library-files`
CC0 bundle. No attribution is required, but credit is given anyway.

Each was decompressed (meshopt) and dequantized with glTF-Transform so Godot can import it.

| File | Original | Used for | Changes in code |
|---|---|---|---|
| `adventurer.glb` | `lowpoly/adventurer.glb` (animated adventurer) | the survivor and your soldiers | soldiers' clothes are recoloured by unit type |
| `raider.glb` | `lowpoly/hooded_adventurer.glb` | raiders and raider chiefs | leathers recoloured; chiefs get a helmet and mantle |
| `horse.glb` | `lowpoly/deer.glb` (animated deer) | horses | reshaped into a horse in code (thicker neck, long head, small ears, deep chest, sturdy legs), horse coats, a mane, a long tail and a saddle |
| `wolf.glb` | `lowpoly/wolf.glb` (animated wolf) | wolves | eyes glow; timber and dire wolves are recoloured and larger |

All characters get softer, more natural materials in `scripts/character_model.gd` (rim light on skin and fur, shiny metal).
