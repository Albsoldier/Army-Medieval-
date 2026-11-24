# Islander: graphics performance baseline

Phase 2: measurements only. No graphics were optimised for this, and gameplay, networking, the Cloudflare Workers and Turso are unchanged.

This baseline is the reference that each later phase in [GRAPHICS_AUDIT.md](GRAPHICS_AUDIT.md) is compared against.

## Labels used in this document

Every number carries one of these tags.

| Tag | Meaning |
|---|---|
| **[M]** | **Measured, and valid on any machine.** It doesn't depend on the GPU: draw calls, primitives, objects, instance counts, buffer and texture memory, node counts, download sizes. |
| **[M-sw]** | **Measured, but on a software GPU** (Mesa llvmpipe running on the CPU). Real numbers from a real web build, **but not representative of a player's machine**. Useful only to compare scenes with each other. |
| **[M-cpu]** | **Measured natively** (Godot 4.4.1 desktop, headless, no rendering). It isolates the game's CPU-side cost. The web build runs the same code as WebAssembly, which is typically 1.5–3× slower. |
| **[N/A]** | **Unavailable**: the browser or the release build doesn't expose it. |
| **[E]** | **Estimate**: reasoning from the measured numbers, not a measurement. |

---

## 1. Summary

1. **Every frame draws 9.4–11 million primitives (triangles) [M].** Even an empty meadow draws 9.4 M.
2. **About 80% of them are the sun's shadow pass [M].** Switching sun shadows off in the forest drops primitives from 10.9 M to 2.23 M and draw calls from 314 to 122. The sun uses **4 shadow cascades** (`SHADOW_PARALLEL_4_SPLITS`) **[M]** with a 4096 atlas **[M]**, so the scene's props are drawn about four extra times.
3. **About 98% of all primitives are the trees, rocks and bushes [M].** Hiding the prop MultiMeshes drops the forest from 10.9 M to 0.18 M primitives. About 4,000–4,800 props are drawn wherever you stand **[M]** (the 160 m window), because a MultiMesh is never partly culled. This confirms audit finding #1.
4. **Draw calls grow with buildings and soldiers [M]:**

   | Scene | Draw calls |
   |---|---|
   | Open land | about 310 |
   | Village of 46 structures and 4 settlers | **2,623** |
   | Village plus 10 soldiers | 2,836 |
   | Village plus 30 soldiers | **3,323** |
   | The same at night | **3,431** |

   **Each soldier adds about 21–24 draw calls**, and each building part is drawn for colour and again for shadows. Browsers handle a few hundred draw calls comfortably; **3,000+ is far beyond that [E]**.
5. **Crossing into a new area costs 140–209 ms of CPU per chunk [M-cpu],** against 6.9 ms for normal frames. That is a visible stutter every 32 m you travel. It's pure game-side CPU work, and in WebAssembly it's likely **200–600 ms [E]**.
6. **Memory is modest [M]:**

   | Memory | Range |
   |---|---|
   | Video memory | 30–52 MB |
   | Textures | 8.6–9.4 MB (mostly the UI, map and fonts) |
   | Vertex and instance buffers | 21–43 MB |
   | Chrome JS heap | 62–137 MB |

   Memory is not the problem; triangle count and draw calls are.

---

## 2. How this was measured

### Tools added on this branch

| File | What it does |
|---|---|
| `game/scripts/perf_overlay.gd` | A developer overlay that F3 shows and hides. It shows FPS, frame time (average and worst over the last second), Godot's process time, render CPU and GPU time, draw calls, primitives, objects, video, texture and buffer memory, static memory, Chrome's JS heap, node count, and the renderer. |
| `game/scripts/perf_bench.gd` | A scripted benchmark. It visits each scene, waits 3 s for things to settle, then records every frame for 6 s (14 s for travel). Results go to the console as `PERF_RESULT {json}` and to `window.perfResults`. |
| `perf/run_web_bench.cjs` | The Playwright script that opened the web build in Chromium and collected the results |
| `perf/*.json*` | The raw results behind every table here |
| `perf/overlay.png` | The overlay in the web build |

**Normal players never see any of it:**

- The overlay exists only in a debug (editor) build, where it starts hidden, or when explicitly asked for with `index.html?perf=1`, `-- --perf`, or the project setting `last_light/debug/perf_overlay`.
- The benchmark runs only with `?bench=1` or `-- --bench`.
- While it runs, the game is **offline and never saves**. `save_game()` returns early in bench mode, which is the one line changed in game code, so a benchmark can't touch a real save or the island server.
- F3 isn't bound to anything else.

### The test setup

| Item | Value |
|---|---|
| Build | `--export-release "Web"` with Godot 4.4.1 and the official 4.4.1 web templates (no threads), gzipped wasm plus `wasm-gz.js` exactly as CI ships it. Same file sizes as the CI build. Offline (no server URL). |
| Browser | **Chromium** 153 (Playwright's build of Chrome's engine), headful under Xvfb. Not Google-branded Chrome, but the same Blink, V8 and ANGLE WebGL stack. |
| GPU | **None.** The container has no GPU. WebGL 2 ran through ANGLE on **Mesa llvmpipe** (`ANGLE (Mesa, llvmpipe (LLVM 20.1.2 256 bits), OpenGL 4.5)`), a CPU software rasteriser on 4 cores. SwiftShader was tried first and was about 7× slower still (9–11 s per frame). |
| Resolution | 1280×720 at 1× device pixel ratio |
| Godot renderer | `gl_compatibility`: WebGL 2.0 / OpenGL ES 3.0, as reported by the build **[M]** |
| Shadows | Sun: 4 cascades, 4096 atlas, 70 m max distance **[M]** |
| Native reference | Godot 4.4.1 Linux, `--headless` (no rendering; frames capped at 144 Hz) |
| Island | The permanent island (seed 20261119), spring, midday unless noted |

### The scenes

All are within a few chunks of the start, chosen automatically and the same every run.

| Scene | What it is |
|---|---|
| **Empty area** | The open grass chunk with the fewest props around it, at about (11528, 7432) px. It still has 4,037 props in the drawn window. |
| **Forest** | The chunk with the most trees around it, at about (7425, 5381). 4,723 props drawn. |
| **Village** | At the start position: 46 structures (4 cottages, 6 fields, barracks, workbench, forge, smokehouse, vault, archer tower, 2 chests, 6 torch posts, 2 gates, 20 wall pieces), a campfire, and 4 settlers. |
| **10 soldiers / 30 soldiers** | The village plus soldiers following you (mostly legionaries, with archers, cavalry and a centurion) |
| **Nighttime** | The village with 30 soldiers at the dead of night: campfire, 6 torch posts, the archer tower and your torch lit |
| **Area transitions** | Travelling in a straight line over land at riding pace (220 px/s) for 14 s, crossing 5–6 chunks |
| **Diagnostics** | The forest again with sun shadows off, then with props hidden. Measurement only, put back right after. |

---

## 3. Results: the web build in Chromium

Hardware-independent columns are **[M]**. Frame-time columns are **[M-sw]**: they measure a software GPU and **should be read only relative to each other**.

| Scene | Draw calls (avg) [M] | Primitives (avg) [M] | Objects [M] | Props drawn [M] | Grass clumps [M] | Frame ms, avg [M-sw] | Frame ms, p95 [M-sw] | FPS [M-sw] |
|---|---|---|---|---|---|---|---|---|
| Empty area | **310** | **9,372,517** | 791 | 4,037 | 8,293 | 1,402 | 1,616 | 0.7 |
| Forest | **314** | **10,897,338** | 818 | 4,723 | 7,289 | 1,364 | 1,565 | 0.7 |
| *Forest, no sun shadows (diagnostic)* | 122 | 2,234,338 | 623 | 4,723 | 7,289 | 303 | 353 | 3.3 |
| *Forest, no props (diagnostic)* | 174 | 181,501 | 566 | (hidden) | 7,289 | 261 | 279 | 3.8 |
| Village | **2,623** | **10,688,572** | 3,347 | 4,842 | 7,188 | 1,087 | 1,213 | 0.9 |
| Village + 10 soldiers | **2,836** | 10,743,894 | 3,563 | 4,842 | 7,188 | 1,195 | 1,257 | 0.8 |
| Village + 30 soldiers | **3,323** | 10,928,104 | 4,050 | 4,842 | 7,188 | 1,396 | 1,458 | 0.7 |
| Nighttime (village + 30, lights) | **3,431** | 10,975,790 | 4,165 | 4,842 | 7,188 | 1,452 | 1,509 | 0.7 |
| Area transitions (14 s travel) | 563 avg / 2,607 max | 10,233,098 | 1,084 | 4,407 | 8,291 | 1,510 | 1,839 | 0.7 |

The forest's frame time with no shadows (303 ms) and no props (261 ms) is still high. The remaining cost on llvmpipe is mostly per-pixel work: the terrain shader and full-screen grass.

### Memory: web build

| Scene | Video memory [M] | Textures [M] | Buffers [M] | JS heap (Chrome) [M] | Nodes [M] |
|---|---|---|---|---|---|
| Empty area | 30.2 MB | 8.6 MB | 21.6 MB | 65.9 MB | 256 |
| Forest | 30.1 MB | 8.7 MB | 21.4 MB | 61.7 MB | 246 |
| Village | 33.9 MB | 8.8 MB | 25.1 MB | 81.1 MB | 953 |
| Village + 10 soldiers | 40.0 MB | 9.0 MB | 31.1 MB | 108.6 MB | 1,284 |
| Village + 30 soldiers | 52.4 MB | 9.4 MB | 43.0 MB | 104.5 MB | 1,946 |
| Nighttime | 52.4 MB | 9.4 MB | 43.0 MB | 84.7 MB | 1,946 |
| Area transitions | 32.3 MB | 8.8 MB | 23.5 MB | 106.9 MB | 853 |

- Video, texture and buffer memory are what Godot itself has allocated through WebGL, as reported by `RenderingServer`. **Each soldier adds about 0.6 MB of buffers [M]**, probably per-instance skinning buffers and the per-instance materials **[E]**.
- The **JS heap** is Chrome's `performance.memory.usedJSHeapSize`. It is Chrome-only, coarse, and moves with garbage collection, so treat it as a rough range of 60–140 MB. It does **not** include the WebAssembly linear memory.

### Download and load [M]

| Item | Size |
|---|---|
| `index.wasm.gz` (engine) | 9.40 MB |
| `index.pck` (game data: models, scripts, sounds) | 2.65 MB |
| `index.js` and the rest | about 0.37 MB |
| **Total** | **about 12.4 MB** |

From opening the page to the benchmark's first result took **18.4 s [M-sw]** on localhost. That covers wasm compilation, world generation, the first frames on llvmpipe and the benchmark's own scene search, so it is an upper bound for this machine, not a player's load time.

---

## 4. Results: native CPU-side cost (Godot desktop, headless, no rendering) [M-cpu]

These isolate the game's own CPU work: scripts, world streaming and MultiMesh rebuilds. Frames are capped at 144 Hz (6.9 ms), so steady scenes show 6.9 ms; what matters is the spikes and the process time.

| Scene | Frame ms, avg | Frame ms, p99 | Frame ms, max | Frames over 50 ms | Godot process time |
|---|---|---|---|---|---|
| Empty area | 6.92 | 7.61 | 34.8 | 0 | 4.4 ms |
| Forest | 6.90 | 7.08 | 15.9 | 0 | 2.7 ms |
| Village | 6.97 | 7.30 | 54.9 | 1 | 4.2 ms |
| Village + 10 soldiers | 6.90 | 7.13 | 13.7 | 0 | 3.1 ms |
| Village + 30 soldiers | 6.90 | 7.11 | 12.1 | 0 | 7.5 ms |
| Nighttime | 6.90 | 7.21 | 14.2 | 0 | 7.9 ms |
| **Area transitions** | 7.59 | 27.6 | **209.4** | **6** | 2.1 ms |

On the transition run, the **frames that crossed into a new chunk took 181, 143, 156, 156, 140 and 209 ms [M-cpu]**, against 6.9 ms for every other frame. That frame is `_refresh_props()` and `_refresh_grass()` rebuilding every prop and grass instance in GDScript, plus building new terrain chunks.

---

## 5. Unavailable metrics [N/A]

| Metric | Why it's unavailable |
|---|---|
| **Real-GPU FPS and frame time** | The test machine has no GPU. Only software rendering was possible. See §6 for estimates, and §7 for how to measure on a real machine. |
| **GPU render time** | `viewport_get_measured_render_time_gpu` returned 0 in every web scene. WebGL in Chrome doesn't expose GPU timer queries to the page by default (`EXT_disjoint_timer_query_webgl2` is disabled for security). The overlay shows "GPU n/a". |
| **Render CPU time on the web** | Measured, but **unreliable**: it varied from 2 to 684 ms between similar frames. On the single-threaded web build, WebGL calls are asynchronous, so the cost lands wherever the browser happens to block. It is recorded in the JSON but not used here. |
| **Godot process time on the web** | Measured, but on llvmpipe it is about the same as the whole frame (the GL driver's work blocks inside it), so it isn't a clean "script time" there. The native table above is the clean version. |
| **Static (heap) memory** | `Performance.MEMORY_STATIC` is only tracked in debug builds; release web exports report 0. The overlay shows "n/a". |
| **WebAssembly heap size** | Not exposed to the game. Chrome's JS heap figure excludes it. |
| **JS heap in other browsers** | `performance.memory` is Chrome-only. Firefox and Safari show "n/a". |

---

## 6. What this likely means on real hardware [E]

These are **estimates**, reasoned from the measured triangle and draw-call counts and typical browser and GPU throughput. They are not measurements.

- **About 10 M triangles per frame** means about 600 M triangles per second at 60 FPS. A desktop discrete GPU can probably do it. **Integrated laptop GPUs (Intel UHD/Iris, AMD APUs) and phones very likely can't hold 60 FPS, and may sit around 15–30 FPS in forests [E].** Because about 80% of the triangles are shadow cascades, this is also the cheapest big win: see the audit's phase 3 (shadow tuning) and phase 4 (per-chunk prop culling).
- **3,000+ draw calls** in a built-up base with an army: each WebGL draw call goes through JavaScript and ANGLE validation. Typically about 1,000–2,000 per frame is where mid-range laptops in Chrome start to drop below 60 FPS from CPU submission alone **[E]**. A large base with a 30–100 soldier army is likely CPU-bound on any machine.
- **Chunk-crossing stalls:** 140–209 ms natively suggests roughly **200–600 ms freezes in the browser [E]** each time you cross 32 m of ground. The game will feel like it stutters while travelling and riding, regardless of GPU.
- **Night** adds about 100 draw calls here (the lights' extra passes on what they touch) **[M]**. With more torch posts lighting more buildings, this grows with the base **[E]**.

---

## 7. Reproducing and adding real-GPU numbers

### On your own machine, in Google Chrome (recommended next step)

Once this branch is deployed:

1. Open `https://last-light-6uv.pages.dev/?perf=1`. The overlay appears; F3 hides and shows it.
2. Walk around: open land, forest, your base by day and night. Note the FPS, frame ms, draw calls and primitives.
3. Or open `https://last-light-6uv.pages.dev/?bench=1&perf=1` and wait about 2 minutes. The benchmark visits every scene in this document. Then, in DevTools, run `copy(JSON.stringify(window.perfResults))` and paste the result into a file.

The benchmark **runs offline and never saves**, so your real game is untouched (it is restored from your save the next time you open the page normally). Record the GPU name from `chrome://gpu` alongside the numbers.

### Locally, exactly as done here

From `last-light/game`, with Godot 4.4.1 and the 4.4.1 web templates installed:

```bash
godot --headless --path . --export-release "Web" /tmp/web/index.html
```

```bash
gzip -9 -n /tmp/web/index.wasm && cp ../web/wasm-gz.js /tmp/web/
```

```bash
(cd /tmp/web && python3 -m http.server 8792)
```

In another terminal, from `last-light`:

```bash
HEADFUL=1 xvfb-run -a node perf/run_web_bench.cjs "http://localhost:8792/index.html?bench=1&perf=1" /tmp/result "--use-gl=angle --use-angle=gl"
```

For the native CPU-side run:

```bash
godot --headless --path . -- --bench
```

### Real-GPU results (to fill in)

| Machine / GPU | Browser | Empty | Forest | Village | +10 soldiers | +30 soldiers | Night | Worst transition frame |
|---|---|---|---|---|---|---|---|---|
| *(your machine)* | Chrome | – FPS | – FPS | – FPS | – FPS | – FPS | – FPS | – ms |

---

## 8. Baseline targets for the next phases

Compare every graphics phase against these **[M]** numbers, from the same benchmark and the same scenes.

| Metric | Baseline | Where it should go after the audit's phases 3–5 |
|---|---|---|
| Primitives in the forest | 10.9 M | Under 2 M (from shadow tuning and per-chunk culling) **[E]** |
| Primitives in an empty area | 9.4 M | Under 1 M **[E]** |
| Draw calls, village + 30 soldiers | 3,323 | Under 1,000 (from merged buildings and kit, and shared materials) **[E]** |
| Draw calls per soldier | about 21–24 | About 10 **[E]** |
| Chunk-crossing frame (native) | 140–209 ms | Under 20 ms (from incremental prop and grass updates) **[E]** |
| Web download | 12.4 MB | About 11 MB (from trimmed animations) **[E]** |
