# Islander: environment prototype, real-GPU validation (phase 4A)

**Status: waiting for a run on real hardware.** The test is built and checked, but no real-GPU measurements have been recorded yet. The cloud machine these changes were made on has no GPU, only Mesa's software renderer. The results section will be filled in from the file the test downloads.

This validates the nature models from [GRAPHICS_ENVIRONMENT_PROTOTYPE.md](GRAPHICS_ENVIRONMENT_PROTOTYPE.md) (branch `claude/env-prototype`) against the old procedural props, on a real GPU. Nothing in the assets or rendering settings was changed for this test.

## How the test works

Open the game with `?gpuval=1`. The test then runs by itself, with no input:

- **Six page loads, three rounds per version, alternating:** models, old, old, models, models, old (A B · B A · A B). Each version is measured once early, once in the middle and once late, so warm-up and a heating laptop don't favour either.
- **Each version is a fresh page load.** The page reloads with `?nature=1` or `?nature=0`, because the choice is made when the world is generated.
- **Identical conditions every time:**

  | Setting | Value |
  |---|---|
  | World | Fixed island |
  | Seed and spot | Same seed (20261124), so the same standing spot in the densest forest near the start |
  | Camera | Same direction (yaw 0.6, north-west) |
  | Season and time | Spring, midday (except the scenes that test season and night) |
  | Weather | Set by the season: none in spring and summer, snow in winter |
  | Shadows | The game's default preset (C) |
  | Window size | Whatever the browser window is; it's recorded, so keep the window the same for the whole run |

- **Shaders and assets settle first.** Before measuring, each load visits every view once: three zooms, with the camera turning a full circle at each, then summer, winter, night and day. Godot compiles shaders the first time something is drawn, so this is where any stutter shows. It's recorded separately as `warmup`.
- **Then it measures these scenes**, each after a 2-second settle:

  | Scene | What | Length |
  |---|---|---|
  | `forest_mid` | Default strategy zoom (1.6), standing still | 6 s |
  | `forest_zoom_max` | Furthest zoom (3.2) | 6 s |
  | `forest_zoom_min` | Closest zoom (0.55) | 6 s |
  | `forest_rotate` | Camera turns a full circle | 8 s |
  | `forest_walk` | Walking pace through the forest, in the direction that stays in the forest longest | 10 s |
  | `forest_night` | Night, your torch lit | 6 s |
  | `forest_summer` | Summer, midday | 6 s |
  | `forest_winter` | Winter, midday, with snowfall | 6 s |

- **Recorded per scene:**
  - average FPS and frame time, median and 95th/99th percentile frame time;
  - **1% low FPS** (frame rate of the slowest 1% of frames);
  - longest frame and frames over 33/50 ms;
  - draw calls and primitives;
  - GPU memory (video, texture, buffer);
  - CPU time for game logic (`cpu_process_ms_avg`) and the renderer's CPU time;
  - the renderer's GPU time (WebGL usually reports 0 here).
- **Recorded per load:**
  - GPU name and vendor (WebGL's unmasked renderer);
  - browser (user agent);
  - CPU cores, device memory, window size and pixel ratio;
  - page load time to the start of the test;
  - shader warm-up stutter.
- **At the end** the page shows a table of **medians across the three rounds** and downloads `islander-gpu-validation.json` with every run.

The runs take about 2 minutes per page load on a laptop GPU, so roughly 12–15 minutes in all.

`?gpuval=1&quick=1` is a short two-load version, only for checking that the test works.

## How to run it on a laptop

1. **Get the build of this branch.**
   - **Option A (works now):** download the `last-light-web` artifact from the latest *Islander* workflow run of pull request #32 (Actions tab → the run → Artifacts). Unzip it and serve the folder:
     ```bash
     python3 -m http.server 8000
     ```
     Then open http://localhost:8000/index.html?gpuval=1
   - **Option B:** a preview deployment of the branch on Cloudflare Pages. This needs a change to the deploy workflow, so it isn't set up yet.
2. **Use Chrome with hardware acceleration on.** Check `chrome://gpu`: "WebGL2: Hardware accelerated".
3. **Prepare the laptop:**
   - plug it in;
   - close other heavy tabs and apps;
   - keep the window the same size, and in front, for the whole run (background tabs are throttled).
4. **Don't touch the mouse or keyboard** until the summary appears. Then send back the downloaded `islander-gpu-validation.json`, or a screenshot of the summary.

## Results

*Waiting for the run on real hardware.*

| | |
|---|---|
| Hardware | |
| GPU | |
| Browser | |
| Window / pixel ratio | |

### Medians across three runs per version

| Scene | Version | Avg FPS | Avg frame time | 1% low FPS | Draw calls | Primitives | GPU memory | CPU frame time |
|---|---|---|---|---|---|---|---|---|
| forest_mid | old props | | | | | | | |
| forest_mid | nature models | | | | | | | |

### Visual issues

### Stutter and asset-loading delays

## Check of the test itself (software renderer, not a GPU result)

The quick version (`?gpuval=1&quick=1`) was run in headless Chromium on the build machine, which has no GPU: WebGL reported `ANGLE (Mesa, llvmpipe ...)`. It confirmed that:
- the page reloads between versions, with nature models on the first load and old props on the second;
- the hardware details are recorded (GPU string, user agent, 4 cores, 16 GB, 1280×720, pixel ratio 1, S3TC available);
- the page load time is recorded (13.6 s and 8.4 s; the first includes a cold cache);
- the shader warm-up is recorded;
- all eight scenes are measured;
- the summary table appears on screen and the results file downloads.

Files: `perf/environment/gpu-validation-selfcheck-llvmpipe.json` and `gpu-validation-selfcheck-summary.png`.

**Its numbers are not GPU measurements.** A software rasterizer runs at 1–3 FPS in every scene and overstates per-vertex and per-pixel costs. The quick mode also measures for 1 second per scene instead of 6–10. On this machine the models ran at roughly 0.55–0.65× the old props' frame rate in every scene. That is consistent with GRAPHICS_ENVIRONMENT_PROTOTYPE.md, and it is exactly what the real-GPU run has to confirm or refute.

`cpu_process_ms_avg` and `render_cpu_ms_avg` are only meaningful on a real GPU. With a software renderer, the "GPU" work is done by the CPU, so it shows up in the CPU numbers too.
