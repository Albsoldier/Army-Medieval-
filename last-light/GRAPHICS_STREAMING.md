# Islander: smoother travel (terrain and grass streaming)

This follows [GRAPHICS_PROP_CHUNKS.md](GRAPHICS_PROP_CHUNKS.md) and is built on that branch. Once prop chunks made props cheap, the stutter when you cross into a new 32 m chunk came from building terrain and grass. This change makes both cheaper. They produce **exactly the same data as before**, and nothing about the look, gameplay, world generation, lighting, shadows, networking, the Workers or Turso changes.

### Tags used below

| Tag | Meaning |
|---|---|
| **[M]** | Measured, and valid on any machine |
| **[M-cpu]** | Measured natively with no rendering (CPU only) |
| **[E]** | Estimate |

## What a crossing cost [M-cpu]

Measured natively (Godot 4.4.1, headless) on the prop-chunks branch, on chunks never visited before:

| Work when you cross into a new chunk | Time |
|---|---|
| Terrain chunk: corner heights, including generating the neighbouring chunks' tile data the first time | about 20 ms |
| Terrain chunk: assembling the mesh | 13–21 ms (and 2 chunks are built per frame) |
| Grass patch rebuild (about 7,800 clumps, one call each) | 16–20 ms |
| Prop chunk (grouped) | about 1 ms |

## What changed (`world.gd`)

### Terrain: look things up once

- **Corner heights.** Each corner's height is the average of the 4 tiles around it, so every tile height was looked up 4 times. Now a chunk's tile heights (34 × 34, including a one-tile border) are read once into a grid, and the corners average from it. The additions run in the same order at the same (64-bit) precision, so the result is bit-for-bit the same.
- **Mesh assembly.** Each vertex's normal used 4 neighbour-corner lookups, and its blend weights 4 terrain lookups. Now a corner grid with a one-corner border, and a grid of terrain types, are built once per chunk, and each vertex reads from them.
- **Result:** mesh assembly takes 4–11 ms instead of 13–21 ms per chunk **[M-cpu]**.
- The mesh data is built in a new `_terrain_arrays()`, so the test can compare it before the GPU packs it.

### Grass: prepared ahead, copied on arrival

- **Prepared per chunk.** Each terrain chunk's grass is worked out once, per season, as ready-made MultiMesh data (a 3×4 transform and a colour per clump), stored row by row and sorted by x.
- **Prepared ahead of time.** The chunks just beyond the patch around you are worked out **6 rows a frame** (`GRASS_ROWS_PER_FRAME`) while you move. By the time you cross, they're ready.
- **Assembled by slicing rows.** On a crossing, the circular patch (radius 34 tiles, centred on your chunk, exactly as before) is assembled by slicing whole rows. It's handed to the MultiMesh in **one** buffer upload, instead of about 7,800 transform and colour calls.
- **Rebuilt only when needed:** when you move to a new chunk, the season changes (the grass is tinted by season), or something is built or taken down (that chunk's grass is redone). Harvesting a tree or a bush no longer rebuilds the grass, since grass never depended on props.
- **Memory:** the cache holds only chunks near you (up to 4 chunks away), at about 0.2 MB a chunk **[E]**.

### A small fix that came with it

Building on an empty grass tile didn't refresh the grass, so grass showed through new buildings until you moved to another chunk. Building or removing anything now updates that spot at once. In the benchmark village, that removes the 138 clumps (46 buildings × 3) that were showing through floors and walls **[M]**.

## Results

### Travel: native, CPU only, 14 s at riding pace, crossing 6 chunks [M-cpu]

Two runs each, on the same machine. The "before" is the prop-chunks branch.

| | Before | After |
|---|---|---|
| Crossing frames (ms) | 31.9, 39.2, 41.6, 46.6, 43.0, 59.3 / 34.9, 69.0, 41.7, 43.2, 43.9, 48.6 | **11.2, 10.7, 18.1, 18.0, 18.7, 13.9 / 13.2, 11.0, 11.1, 12.0, 9.1, 12.1** |
| Worst frame | 59.3 / 69.0 ms | **26.9 / 19.6 ms** |
| Frames over 33 ms | 5 / 7 | **0 / 0** |
| Frames over 50 ms | 1 / 1 | **0 / 0** |
| 99th percentile | 14.1 / 15.0 ms | **10.7 / 9.3 ms** |

Machine speed varies between sessions: yesterday's baseline crossings on the same code were 52–96 ms. Always compare runs from the same session.

The WebAssembly build runs the same code more slowly, typically 1.5–3× **[E]**. So in the browser a crossing frame is likely about 15–55 ms, against roughly 50–200 ms before **[E]**.

### Rendering: browser, Chromium [M]

There's no change to what is drawn. Primitives and draw calls match the prop-chunks branch within run-to-run noise, in every scene. Raw data: `perf/streaming/web-bench.json`.

| Scene | Primitives | Draw calls | Grass clumps |
|---|---|---|---|
| Empty area | 2,128,126 | 334 | 8,293 |
| Forest | 2,647,367 | 336 | 7,289 |
| Village | 2,300,410 | 1,554 | 7,050 (138 fewer: no longer under buildings) |
| Village + 30 soldiers | 2,558,513 | 2,270 | 7,050 |
| Night village + 30 | 3,100,217 | 2,425 | 7,050 |

## How "exactly the same" is checked

The smoke test ports the **old** algorithms and compares:

| Check | Result |
|---|---|
| Terrain, on 4 chunks around the start: every corner height, vertex, normal and blend weight, against the old code (computed before the GPU packs it) | Difference **0.0**, and 0 blend weights differ |
| Grass, in spring and in autumn: every clump's position, rotation, scale and colour, against the old algorithm | **7,188 of 7,188** match |
| Winter | No grass |
| Building a wall on grass, then removing it | Removes exactly 3 clumps, then restores them, matching the old algorithm |

The MultiMesh buffer layout (rows of the 3×4 transform, then the colour) was confirmed against Godot's own `set_instance_transform` with the real OpenGL renderer.

## Remaining limitations

- **Crossings still cost 9–19 ms natively.** That's new terrain chunks, still built 2 per frame at 4–11 ms each, and the grass row copy. It's under two 60 fps frames natively. The browser will be slower **[E]**.
- **Terrain data generation** (the noise sampling for chunks never seen before) is unchanged. It's world generation, so it was left alone.
- **No real-GPU numbers yet.** These timings are CPU-side; run `?bench=1&perf=1` in Chrome for real-hardware frame times.
