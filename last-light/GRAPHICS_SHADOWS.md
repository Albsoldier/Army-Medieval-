# Islander: sun-shadow optimisation

One controlled change. Only the sun's shadow **cascades** and **shadow-map atlas size** are varied; everything else is identical between the configurations. The shadow distance (70 m), blur, bias, lights, models, terrain, gameplay, networking, the Cloudflare Workers and Turso are untouched, and no other optimisation is combined with this.

The starting point is [GRAPHICS_BASELINE.md](GRAPHICS_BASELINE.md), which found that about 80% of each frame's 9–11 M primitives are the sun's shadow pass.

## Recommendation

**Ship C: 2 cascades with a 2048 atlas.** It's now the default.

- **About 40% fewer primitives** in every scene **[M]**: 10.9 M → 6.6 M in the forest.
- **31–43% fewer draw calls** **[M]**: 2,592 → 1,470 in the village.
- **A quarter of the shadow-map memory** **[E]**: about 8 MiB instead of 32 MiB.
- **Shadows look the same** at normal camera distances, and it **keeps the fine close-range shadows** that B and D lose.
- **The cost** is slightly more crawling at shadow edges as the sun moves. It's measurable but small.

D (1 cascade) is the fastest, but it visibly drops small shadows near the camera. B gives the same performance as C at four times the memory, and in this test it also lost those close shadows.

### Tags used below

| Tag | Meaning |
|---|---|
| **[M]** | Measured, and valid on any machine (draw calls, primitives) |
| **[M-sw]** | Measured on a software GPU: compare the configurations, don't read it as real FPS |
| **[E]** | Estimate |

---

## 1. The configurations

| | Shadow mode | Cascades (0–70 m) | Atlas | Approx. atlas memory [E] |
|---|---|---|---|---|
| **A** (old default) | `SHADOW_PARALLEL_4_SPLITS` | 4: 0–7, 7–14, 14–35, 35–70 m | 4096² | 32 MiB |
| **B** | `SHADOW_PARALLEL_2_SPLITS` | 2: 0–7, 7–70 m | 4096² | 32 MiB |
| **C** (new default) | `SHADOW_PARALLEL_2_SPLITS` | 2: 0–7, 7–70 m | 2048² | 8 MiB |
| **D** | `SHADOW_ORTHOGONAL` | 1: 0–70 m | 2048² | 8 MiB |

- The split points are Godot's defaults (`directional_shadow_split_1/2/3` = 0.1, 0.2, 0.5 of 70 m).
- Atlas memory assumes 16-bit depth (`directional_shadow/16_bits`, the default). Godot's video-memory counter doesn't include the shadow atlas: it read the same (about 30–52 MB) under every configuration, so the memory column is calculated, not measured.

### How the presets are switched

`main.gd` now has a `SUN_SHADOWS` table (A–D) and `apply_sun_shadows(preset)`, and the default is `SUN_SHADOW_DEFAULT = "C"`. Developers can try another preset without rebuilding:
- in the browser, with `index.html?shadows=B`;
- natively, with `-- --shadows=B`.

`project.godot` now sets `rendering/lights_and_shadows/directional_shadow/size=2048`, so the atlas isn't first allocated at 4096.

## 2. Method

- **Performance:** the existing browser benchmark (`?bench=1`). It used the exported web build in Chromium, on Mesa llvmpipe through ANGLE, at 1280×720, exactly as in the baseline. It ran once per preset with `&shadows=A`, `B`, `C` and `D`. Raw data: `perf/shadows/web-bench-*.json`.
- **Visual quality:** `tools/shadow_shots.gd` (new) renders five views under each preset at evening light, when the sun is low and shadows are long, which is the hardest case:
  - close up;
  - a base overview;
  - zoomed all the way out;
  - forest;
  - first person.

  It builds the same village with 10 soldiers as the benchmark. **The scene is frozen while the presets are switched**, so the four images of each view show exactly the same moment and differ only in shadows. Comparison images are in `perf/shadows/`, built by `perf/shadow_analysis.py`.
- **Stability:** for each preset, ten frames with the camera and scene frozen while the sun moves 1.5 game-seconds per frame. A pixel "flickers" if its brightness jumps one way and then back between consecutive frames. A run with shadows **off** gives the noise floor (grass sway is shader-animated and keeps moving).
- **Missing shadows:** the share of dark pixels in each view, plus zoomed crops of thin casters (spears, palisade spikes, wheat stalks, eaves, soldiers' legs).
- The visual run was repeated **with the presets in reverse order**, and the results held.

## 3. Performance

### Primitives per frame [M]

| Scene | A (4×4096) | B (2×4096) | C (2×2048) | D (1×2048) |
|---|---|---|---|---|
| Empty area | 9,371,791 | 5,660,397 (−40%) | 5,660,506 (−40%) | 3,825,138 (−59%) |
| Forest | 10,895,623 | 6,577,497 (−40%) | 6,577,135 (−40%) | 4,436,204 (−59%) |
| Village | 10,681,145 | 6,429,617 (−40%) | 6,432,666 (−40%) | 4,346,222 (−59%) |
| Village + 10 soldiers | 10,752,984 | 6,492,185 (−40%) | 6,501,182 (−40%) | 4,431,972 (−59%) |
| Village + 30 soldiers | 10,964,001 | 6,686,792 (−39%) | 6,696,274 (−39%) | 4,617,095 (−58%) |
| Night (village + 30) | 10,989,841 | 6,709,549 (−39%) | 6,737,344 (−39%) | 4,636,544 (−58%) |
| Area transitions | 10,248,130 | 6,175,940 (−40%) | 6,168,392 (−40%) | 4,175,794 (−59%) |

### Draw calls per frame [M]

| Scene | A | B | C | D |
|---|---|---|---|---|
| Empty area | 310 | 212 (−32%) | 212 (−32%) | 185 (−40%) |
| Forest | 313 | 219 (−30%) | 217 (−31%) | 192 (−39%) |
| Village | 2,592 | 1,473 (−43%) | 1,470 (−43%) | 1,279 (−51%) |
| Village + 10 soldiers | 2,819 | 1,656 (−41%) | 1,659 (−41%) | 1,555 (−45%) |
| Village + 30 soldiers | 3,325 | 2,158 (−35%) | 2,159 (−35%) | 2,060 (−38%) |
| Night (village + 30) | 3,417 | 2,238 (−35%) | 2,265 (−34%) | 2,070 (−39%) |
| Area transitions | 546 | 337 (−38%) | 331 (−39%) | 306 (−44%) |

### Frame time, average ms [M-sw]

On a software GPU, so these are only for comparing the configurations.

| Scene | A | B | C | D |
|---|---|---|---|---|
| Empty area | 1,054 | 763 (−28%) | 711 (−33%) | 652 (−38%) |
| Forest | 1,474 | 917 (−38%) | 836 (−43%) | 830 (−44%) |
| Village | 1,070 | 895 (−16%) | 871 (−19%) | 722 (−32%) |
| Village + 10 soldiers | 1,249 | 911 (−27%) | 817 (−35%) | 779 (−38%) |
| Village + 30 soldiers | 1,379 | 1,109 (−20%) | 1,049 (−24%) | 953 (−31%) |
| Night (village + 30) | 1,401 | 1,134 (−19%) | 1,222 (−13%) | 1,045 (−25%) |
| Area transitions | 1,237 | 944 (−24%) | 1,013 (−18%) | 864 (−30%) |

What the numbers show:

- **Cascades drive the cost, not atlas size.** B and C are identical in primitives and draw calls; the atlas size only changes memory and texel density.
- Going from 4 to 2 cascades saves about 40% of all primitives. Going to 1 saves about 59%.
- The draw-call savings are largest where there are many separate objects, as in the village, because every building part is drawn again into each cascade it touches.
- With fewer cascades, the frame-time savings on the software GPU (13–44%) roughly follow the primitive savings. On real GPUs the shadow pass is cheaper relative to the rest, so the gain in milliseconds will be smaller, but the primitive and draw-call savings are the same everywhere **[E]**.

## 4. Visual quality

The images are in `perf/shadows/`:
- `grid-<view>.jpg` shows all four presets side by side at half size;
- `crop-<view>.jpg` shows 1:1 crops;
- `crop-fp-*.jpg` are the first-person close-ups.

| View | A | B | C | D |
|---|---|---|---|---|
| **Base overview** (zoom 1.5) | Reference | Same | Same | Same |
| **Zoomed all the way out** (zoom 3.2) | Reference | Same | Same | Same: tree and rock shadows all present out to the edge |
| **Forest** | Reference | Same | Same | Same |
| **Close up** (zoom 0.55): soldiers, spears, palisade | Crispest | Very slightly softer | Very slightly softer | Softer; still present |
| **First person**: wheat stalks on their bed, shadow under the cottage eaves | Present and sharp | **Stalk shadows gone** | Present, about as sharp as A | **Stalk and eave shadows gone** |

The share of dark (shadowed) pixels per view differs by at most 2.1 points between presets in either run (usually under 1) **[M]**. No preset loses shadows wholesale: every building, tree and character casts in every configuration. The losses in B and D are the *fine contact shadows of thin objects close to the camera*, and they were the same in the forward and reversed runs.

C keeping them while B, with the bigger atlas, loses them was unexpected. The likely cause is how Godot scales shadow bias to each cascade's texel size **[E]**. It is reported as observed.

### Stability: shadow-edge crawl as the sun moves [M-sw]

Percentage of pixels that flicker between consecutive frames. Lower is better; "off" is the noise floor.

| Run | Off (noise floor) | A | B | C | D |
|---|---|---|---|---|---|
| 1 | 2.58 | 4.31 | 5.91 | 7.16 | 5.93 |
| 2 (reversed) | 2.76 | 3.74 | 5.53 | 6.22 | 6.65 |
| Above the floor, mean of both | — | **1.4** | **3.1** | **4.0** | **3.6** |

- A's four cascades give the most stable edges.
- B, C and D crawl about 2–3× as much as A above the floor, and are close to each other.
- In play the sun moves about 0.24° per real second, so this is a slow creep along shadow edges rather than flashing **[E]**.
- No preset showed shadows popping in or out in the still frames.
- **Not tested:** shimmer while the *camera* moves. All of this was measured with a still camera.

## 5. Decision

| Preset | Performance | Close-range shadows | Stability | Memory | Verdict |
|---|---|---|---|---|---|
| A | Baseline (worst) | Best | Best | 32 MiB | Too expensive for the browser |
| B | −40% primitives | Loses thin contact shadows | Good | 32 MiB | No advantage over C |
| **C** | **−40% primitives, −31 to −43% draw calls** | **Kept** | **Good** | **8 MiB** | **Recommended** |
| D | −59% primitives, −38 to −51% draw calls | Loses thin contact shadows, softer close up | Good | 8 MiB | Good fallback for a future "Low" quality setting |

**C is now the default.** D is worth offering later as the shadow part of a "Low" quality option (audit item A9), where frame rate matters more than fine shadows. That is out of scope here.

## 6. Confirming the default

After switching the default to C, the benchmark was run once more with **no** `?shadows=` override, to confirm the shipped build uses C. The results are in `perf/shadows/web-bench-default.json` and summarised in §6.1.

The smoke test has a new check, "the sun casts shadows with 2 cascades on a 2048 atlas", and it passes.

### 6.1 Default build results

The default build reported preset **C** in every scene, and matched the `?shadows=C` run to within 0.2% **[M]**:

| Scene | Preset reported | Draw calls | Primitives (default build) | Primitives (`?shadows=C`) |
|---|---|---|---|---|
| Empty area | C | 212 | 5,660,852 | 5,660,506 |
| Forest | C | 218 | 6,575,780 | 6,577,135 |
| Village | C | 1,465 | 6,425,153 | 6,432,666 |
| Village + 10 soldiers | C | 1,652 | 6,490,428 | 6,501,182 |
| Village + 30 soldiers | C | 2,166 | 6,688,001 | 6,696,274 |
| Night (village + 30) | C | 2,260 | 6,722,202 | 6,737,344 |
| Area transitions | C | 345 | 6,178,473 | 6,168,392 |

### How this changes the baseline targets

Against the targets in GRAPHICS_BASELINE.md §8, the forest falls from 10.9 M to 6.6 M primitives. The rest of the way to under 2 M is per-chunk prop culling, the audit's next phase, which is not part of this change.
