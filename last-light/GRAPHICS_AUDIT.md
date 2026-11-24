# Islander: graphics audit

Phase 1: inspection only. No game files were changed for this audit.

The audit covers the Godot project in `last-light/game` as of `main` at f7f7304, after PR #24. Numbers come from three sources:

- `project.godot` and `export_presets.cfg`;
- the `.glb` files, inspected with glTF-Transform;
- the scripts that build the world.

Nothing was profiled in a browser. Frame times and draw-call counts below are estimates from the code, and **[measure]** marks where a real measurement is needed before acting.

---

## 1. What the project is

| Item | Finding |
|---|---|
| **Godot version** | 4.4.1 stable. `config/features` is `"4.4", "GL Compatibility"`, and CI installs 4.4.1. |
| **Rendering method** | **Compatibility (OpenGL ES 3 / WebGL 2)**. Set for desktop and mobile: `renderer/rendering_method="gl_compatibility"` and `rendering_method.mobile="gl_compatibility"`. ✅ This is correct for browser export: Forward+ and Mobile don't run on the web. |
| **Web export** | One preset, "Web". Threads are off (`variant/thread_support=false`), so Cloudflare Pages needs no COOP/COEP headers. Desktop VRAM texture compression is on; **mobile (ETC2/ASTC) is off**. The wasm ships gzipped through `wasm-gz.js`: `index.wasm.gz` is 9.4 MB and `index.pck` is 2.6 MB. |
| **Viewport** | 1280×720, stretch `canvas_items`/`expand`. No 3D render scale, no MSAA and no FXAA are set, so 3D is drawn at full resolution with no anti-aliasing. |

## 2. Main environment scenes

There is effectively one scene. `scenes/main.tscn` is a single `Node3D` with `main.gd` attached. Everything else is built in code at runtime:

| Part | Built in | How |
|---|---|---|
| Sky, fog, tonemap | `main.gd` `_setup_environment()` | `ProceduralSkyMaterial`, ACES tonemap at exposure 0.92, depth fog from 32 m to 120 m, ambient light from a flat colour (not the sky) |
| Sun and moon | `main.gd` `_update_lighting()` | One `DirectionalLight3D` with shadows on. Colour, angle and energy are re-lerped every frame for day, dusk and night. |
| Terrain | `world.gd` `_build_chunk_mesh()` | 1024×1024 tiles in 32×32 chunks. A **7×7 chunk** window (VIEW = 3) is streamed, 2 chunks per frame, each an `ArrayMesh` with vertex-colour blend weights and `terrain.gdshader`. |
| Water | `world.gd` `_build_water()` | One 640×640 m plane with 96×96 subdivisions and `water.gdshader` (alpha blended, vertex swell). A flat seabed plane sits under it. |
| Trees, rocks, bushes | `world.gd` `_build_prop_layers()`, `_refresh_props()` | **One `MultiMesh` per part per prop type**, about 30 layers, filled for a **5×5 chunk** window (160×160 tiles). Trees are 5–6 primitive cylinders or spheres each. Sway comes from `foliage.gdshader`. |
| Grass | `world.gd` `_refresh_grass()` | One `MultiMesh` of 5-blade clumps in a 34-tile radius (up to 3 per grass tile). `grass.gdshader`, no shadows. |
| Buildings, POIs, camps | `structure.gd`, `poi.gd`, `main.gd` | Built from Godot primitives (`BoxMesh`, `CylinderMesh`, `SphereMesh`) through `art.gd`. **Each part is its own `MeshInstance3D` with its own new `StandardMaterial3D`.** |
| Characters | `character_model.gd` plus the `.glb` files | Animated glTF models, recoloured by duplicating materials per instance, plus primitive "kit": helmets, shields, spears, hats and a horse for cavalry. |

## 3. Character models and animations

All models are glTF binary, CC0 (see `models/CREDITS.md`). **None has a texture.** They are coloured with flat material colours, or vertex colours for the horse.

| Model | Used for | Triangles | Vertices | Surfaces (draw calls) | Materials | Joints | Animations | Anim data | File |
|---|---|---|---|---|---|---|---|---|---|
| `adventurer.glb` | You, every soldier, every settler | 10,198 | 20,569 | **15** | 11 | 62 | 24 (≈5 used) | 204 KB | 1.37 MB |
| `raider.glb` | Raiders and chiefs | 7,276 | 14,628 | **17** | 10 | 62 | 24 (≈4 used) | 225 KB | 1.07 MB |
| `horse.glb` (Barded War Horse) | Wild and tame horses, cavalry | 3,990 | 11,970 | 4 | 1 (vertex colour) | 24 | 3 | **843 KB** | **2.55 MB** |
| `wolf.glb` | Wolves (grey, timber, dire) | 1,962 | 3,994 | 4 | 4 | 51 | 24 (**12 are duplicates** with an `AnimalArmature|` prefix) | 336 KB | 0.58 MB |

Notes:

- **The horse's `Idle` clip alone has 34,608 keyframes (623 KB)**: it is sampled every frame instead of keyed. The horse is the largest file in the build, mostly because of animation data.
- The adventurer and raider each carry about 19 clips the game never plays: gun, kick, punch, roll and others.
- One soldier costs roughly 15 surfaces for the body, plus 6–10 kit parts (helmet dome and crest, shield and boss, spear, bow, horse), plus a selection ring and a `Label3D`. **That is about 25 draw calls per soldier, each with its own material.** A 30-soldier army is about 750 draw calls before the world is counted.
- `CharacterModel._recolor()` and `_enhance()` **duplicate every material per instance**. So 30 soldiers means about 330 unique `StandardMaterial3D`s, and Godot can't batch any of them.

## 4. Materials and textures

| Kind | Where | Notes |
|---|---|---|
| `StandardMaterial3D`, flat colour | `art.gd` `material()`: every building part, kit piece, POI and camp | Roughness 0.9, some emission. **A new material for every single part.** |
| `StandardMaterial3D` per character surface | `character_model.gd` | Rim lighting, roughness and metallic tweaks, duplicated per instance |
| `ShaderMaterial` `terrain.gdshader` | Terrain chunks | Procedural colour. Per pixel it runs **4 × fbm (4 octaves each) + 1 vnoise**. That is 17 value-noise lookups, each with 4 `sin()`-based hashes, so **68 `sin` calls per pixel**. The terrain covers most of the screen. |
| `ShaderMaterial` `water.gdshader` | Water | Analytic normals from 6 sines, fresnel, alpha blend |
| `ShaderMaterial` `foliage.gdshader` | Tree crowns, bushes | Vertex sway that calls `inverse(MODEL_MATRIX)` **per vertex**, plus rim |
| `ShaderMaterial` `grass.gdshader` | Grass | Vertex sway that also calls `inverse(MODEL_MATRIX)` per vertex |
| Textures | none in 3D | The only images are `icon.svg` and the runtime map (`ImageTexture` from `world.map_image`). |

## 5. Lighting and shadows

| Setting | Value | Comment |
|---|---|---|
| Directional light | 1, with shadows on | Doubles as the moon at night |
| `directional_shadow_max_distance` | 70 m | Reasonable for the strategy camera. Generous at zoom-in. |
| `shadow_blur` | 1.5 | Soft PCF. Costs extra samples. |
| Directional shadow atlas size | Project default (4096) | **Large for WebGL**, especially on integrated and mobile GPUs. **[measure]** |
| Shadow casters | Everything by default | Every tree, rock and bush layer, building, character and kit piece casts. Only grass, water and ice opt out. Each MultiMesh layer casts as a whole: **every prop in the 160 m window is drawn into the shadow map**, not just the ones within 70 m. |
| Omni lights | Campfires, torch posts (up to 24), the forge, oil gates, lighthouse beams, the player's torch, lantern and self-glow, shrines | No shadows (good). But in the Compatibility renderer **each omni light that touches an object adds another lighting pass for that object**. A lit base at night re-draws its walls, buildings and soldiers once per nearby light. The 24 torch-post cap exists for this reason. |
| Ambient | Flat colour, energy 0.45 by day and 1.0 at night | No sky contribution, so shaded sides look grey and flat |
| Tonemap | ACES, exposure 0.92 | Fine |
| Fog | Depth fog from 32 m to 120 m | Hides chunk pop-in well |
| Glow, SSAO, SSR, SDFGI, volumetric fog | Not used | SSAO, SSR, SDFGI and volumetric fog are **not available in Compatibility**. Whether glow works in Compatibility on 4.4 needs checking. **[measure]** |

## 6. Texture and model sizes

- **Textures:** none in the 3D scene, so VRAM use for textures is close to zero.
- **Models on disk:** 5.57 MB in total. The horse is 46% of it.
- **Web download:** about 9.4 MB of gzipped wasm (the engine) plus a 2.6 MB `.pck` (models, scripts, sounds). Sounds are 0.5 MB.
- **Runtime geometry, estimated:**

| What | Estimate |
|---|---|
| Terrain | 49 chunks × 2,048 triangles ≈ **100k triangles**, 49 draw calls |
| Props | 25 chunks × 1,024 cells. Forests may hold a few thousand trees at about 300–600 triangles each, so **plausibly 0.5–1.5 M triangles**, drawn twice (colour and shadow). **[measure]** |
| Grass | Up to about 10k clumps × 10 triangles ≈ 100k triangles |
| Water | 96×96×2 ≈ 18k triangles, alpha blended over a 640 m plane |

## 7. Browser performance bottlenecks, most likely first

1. **Props are never culled.** Each prop layer is one `MultiMesh` covering 160×160 m. Godot culls a `MultiMesh` as one box, so every tree and rock in the window is drawn whether or not it's on screen, and again into the shadow map. This is probably the largest GPU cost. **[measure]**
2. **Draw calls from characters and buildings.** There are about 25 per soldier, each primitive building part is its own mesh and material, and per-instance material duplication defeats batching. WebGL draw calls are expensive in the browser because each one is a JavaScript-to-GPU call. A big army or a big base will be CPU-bound on draw submission.
3. **Omni lights in Compatibility** multiply the draws of everything they touch at night.
4. **The terrain fragment shader** runs 68 `sin` calls per pixel at full resolution, which is costly on integrated and mobile GPUs.
5. **Shadow pass size:** a 4096 atlas with PCF blur, and every prop layer casting.
6. **Full-resolution rendering** with no render scale on high-DPI screens. `canvas_resize_policy=2` sizes the canvas to the window, so a 4K laptop renders a very large back buffer.
7. **CPU stalls when chunks change.** `_refresh_props()` and `_refresh_grass()` rebuild every prop and grass instance in GDScript each time you cross into a new chunk. That is tens of thousands of `set_instance_transform` calls, a visible hitch, and worse on the web because there are no threads.
8. **Per-vertex `inverse(MODEL_MATRIX)`** in the foliage and grass shaders: cheap to fix, wasted work on every swaying vertex.
9. **Download size:** 2.5 MB of horse, much of it a densely sampled idle clip, plus unused animation clips.

## 8. Current graphics quality

A clean, readable low-poly style. Lighting by day and dusk is pleasant, the terrain colour variation and seasons work well, and depth fog gives good distance. The recent CI screenshots (`2-day`, `7-base-day`, `16f-purge`, `16g-village`) show the strengths and weaknesses:

- **Strong:** the time-of-day palette, seasonal terrain, wind sway on trees and grass, the procedural terrain, and characters with rim lighting.
- **Middling:** water (a nice fresnel, but no shoreline foam or depth fade, so coasts look abrupt) and the sky (procedural, no clouds).
- **Weak:** everything built from primitives. Buildings, walls, props, kit and POIs are visibly boxes, cylinders and spheres with flat, untextured colour. They sit oddly next to the more detailed glTF characters and horse.

## 9. Weakest visual elements, worst first

1. **Buildings and walls:** primitive boxes and cones, flat colour, no texture or bevel. They dominate the base view, which is where players spend the most time.
2. **Trees and rocks:** stacked cones and squashed spheres. Readable, but the most "programmer art" element on screen, and there are thousands of them.
3. **Kit on characters:** helmets, shields and spears are primitives bolted onto bones. They float or clip during animation, and the material doesn't match the model.
4. **Shading reads flat:** ambient is a flat colour and there's no ambient occlusion, so contact points (bases of walls, trees and characters) have no grounding.
5. **Aliasing:** no MSAA or FXAA, so thin palisade spikes, spears and grass shimmer.
6. **Coastlines:** water meets sand with no foam, depth fade or wet-sand band.
7. **Night:** a flat bluish fill. Torches pool light nicely, but there is no glow or bloom on flames.
8. **UI against the 3D world:** fine. Out of scope here.

## 10. Recommended improvements

All of these keep gameplay, networking, the Cloudflare Workers and Turso untouched. They change visuals and rendering only.

### A. Performance first: frees budget for everything else

| # | Change | Expected win | Risk |
|---|---|---|---|
| A1 | **Split prop MultiMeshes per chunk.** One `MultiMeshInstance3D` per chunk per layer, so frustum culling and the shadow distance work. Only rebuild the chunks that changed. | Large GPU win. Removes most of the chunk-crossing hitch. | Low to medium |
| A2 | **Shadow tuning:** directional atlas 2048; props beyond about 40 m `cast_shadow = off` (the per-chunk split makes that possible); `shadow_blur` 1.0. | Large on integrated GPUs | Low |
| A3 | **Share materials.** Cache `Art.material()` by colour, emission and unshaded, and recolour characters with one shared material per (model, colour) instead of a duplicate per instance. | Fewer state changes. Lets Godot batch. | Low |
| A4 | **Merge static building parts.** Bake each `Structure` into one `ArrayMesh` with vertex colours and one shared material, so a building is one draw call instead of 5–20. | Large CPU win for big bases | Medium |
| A5 | **Merge character kit.** Build each soldier's helmet, shield and weapon into one mesh per bone attachment. Hide kit and labels beyond about 25 m. | About 25 → 17 calls per soldier | Low |
| A6 | **Character LOD and impostors.** Beyond about 35 m, freeze the animation (`AnimationPlayer` paused or updated at a low rate). Consider a cheaper soldier mesh for crowds. | CPU, at large armies | Medium |
| A7 | **Light budget:** cap active omni lights near the camera (about 8), turning far torches into emissive-only meshes. Set `omni_range` tightly. | Large at night in big bases | Low |
| A8 | **Cheaper terrain shader:** bake the noise into a small tiling 256² texture, or compute it per vertex, and keep only one cheap per-pixel octave for detail. | Large on mobile and integrated GPUs | Low; looks nearly the same |
| A9 | **Resolution control:** a "Quality" option (Low, Medium, High) that sets `scaling_3d_scale` (0.67, 0.85, 1.0), the shadow size and the grass radius, defaulting by `OS.get_screen_dpi()` or a quick frame-time probe. | Keeps 4K and HiDPI laptops smooth | Low |
| A10 | **Shader fixes:** replace `inverse(MODEL_MATRIX) * wind` with a model-space wind (`MODEL_MATRIX` is a rotation times a uniform scale here, so a transpose divided by the scale squared works, or apply the offset in world space through `world_vertex_coords`). | Small | Very low |
| A11 | **Asset trimming:** strip unused clips from the adventurer, raider and wolf (the wolf has duplicates); resample the horse clips to keyframes (`gltf-transform resample`). | About 1.5–2 MB off the download, and faster import | Low |
| A12 | **Spread the grass rebuild over frames,** or move it to a cached per-chunk MultiMesh like A1. | Removes the hitch | Low |

### B. Visual quality: affordable in Compatibility and WebGL 2

| # | Change | Why |
|---|---|---|
| B1 | **MSAA 2×** (`msaa_3d`), or FXAA if MSAA is too slow on a target. | Kills the shimmer on palisades, spears and grass. **[measure]** cost on integrated GPUs. |
| B2 | **Blend sky into ambient** (`AMBIENT_SOURCE_SKY` with a contribution of about 0.5, or two-tone ambient from top and horizon colours) plus a little **vertex AO** baked into building and prop meshes (darker at the base). | Grounds objects. The cheap stand-in for SSAO, which Compatibility lacks. |
| B3 | **Better props:** replace primitive trees and rocks with a small CC0 low-poly set (2–3 variants each, 150–400 triangles, vertex-coloured), through the per-chunk MultiMesh from A1. | Biggest single look upgrade for the landscape |
| B4 | **Better buildings:** a CC0 medieval kit (walls, gate, tower, cottage, barracks), vertex-coloured or with a single shared 512² atlas, merged per building (A4). | Biggest look upgrade for the base |
| B5 | **Shoreline:** a depth-fade foam band in `water.gdshader` (from the terrain height, since screen depth reads are limited in Compatibility), plus a wet-sand band in the terrain shader (it already darkens below the waterline; widen it and add a highlight). | Coasts look finished |
| B6 | **Fire and night:** emissive flames with a cheap flickering vertex animation, a soft additive billboard halo around flames, and glow if Compatibility supports it. | Night bases look warm instead of flat |
| B7 | **Kit fitting:** move helmet and shield offsets per model, or use the models' own sword and shield meshes where they exist (the raider has a `Sword` mesh). | No floating helmets |
| B8 | **Sky:** a cheap cloud layer, either a scrolling noise texture in a custom sky shader or a few billboard cloud sprites. | Adds life to wide shots |
| B9 | **Colour grade:** a slight saturation and contrast curve with `adjustment_*` in `Environment` (supported in Compatibility). Tune per season. | Cohesive look for nearly no cost |

## 11. Suggested implementation order

Each phase should ship as its own PR with before-and-after CI screenshots, plus a simple FPS overlay (a debug key) to compare.

| Phase | Work | Why in this order |
|---|---|---|
| **2. Measure** | Add a debug overlay (F3): FPS, draw calls, objects and primitives from `RenderingServer.get_rendering_info()`, and frame time. Record numbers for three fixed scenes (forest, base at night, army of 50) in the CI screenshot job, and in one desktop and one laptop browser by hand. | Every later step needs a baseline. Confirms or refutes the **[measure]** items. |
| **3. Cheap wins** | A2 shadows, A9 quality setting and render scale, A10 shader fixes, A11 asset trimming, B1 MSAA (if affordable), B9 colour grade | Small, safe, immediately noticeable |
| **4. Batching** | A1 per-chunk props with culling, A12 grass, A3 shared materials | Largest performance gain. Unblocks richer props. |
| **5. Draw-call diet** | A4 merged buildings, A5 merged kit, A7 light budget, A6 character LOD | Makes big bases and armies scale |
| **6. Terrain** | A8 cheaper shader, B5 shoreline | Mobile and integrated-GPU frame time, plus a visible upgrade |
| **7. Lighting look** | B2 ambient and AO, B6 fire and night | Better mood without new assets |
| **8. Assets** | B3 props, B4 buildings, B7 kit fitting, B8 sky | Biggest visual change. Do it after batching so the richer meshes are affordable. Every new asset must be CC0 or similarly re-uploadable, because the repository is public. |

### Guardrails for every phase

- Stay on the **Compatibility** renderer. Don't use Forward+ or Mobile-only features: SDFGI, SSAO, SSR, volumetric fog, decals and GPU particles beyond what Compatibility supports.
- Keep `variant/thread_support=false`, so hosting needs no COOP/COEP headers.
- Keep every file under Cloudflare Pages' 25 MiB limit; the wasm ships gzipped.
- Keep game logic in "pixels" (`world.gd`), so saves and the server are unaffected.
- Leave `api.gd`, `server/` (Workers and Turso), `save_game.gd` and gameplay rules alone.
- Keep the smoke test and screenshot CI green, and compare screenshots before and after each phase.
