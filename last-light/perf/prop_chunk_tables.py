# Builds the GRAPHICS_PROP_CHUNKS.md tables from the benchmark JSON files.
# Usage: python3 prop_chunk_tables.py <dir with web-g{0,1}-s{N}.json> <baseline json>
import json, sys, glob, os, re
d, base = sys.argv[1], sys.argv[2]
SCENES = [("empty_area", "Empty area"), ("forest", "Forest"), ("village", "Village"),
          ("village_30_soldiers", "Village + 30 soldiers"), ("night_village_30_soldiers", "Night village + 30"),
          ("area_transitions", "Area transitions")]
def load(p):
    return {r["label"]: r for r in json.load(open(p))["results"] if "draw_calls_avg" in r}
runs = {}
for p in glob.glob(os.path.join(d, "web-g*-s*.json")):
    g, s = re.search(r"web-g(\d)-s(\d+)\.json", p).groups()
    runs[(int(g), int(s))] = load(p)
B = load(base)
order = sorted(runs, key=lambda k: (-k[0], k[1]))
def name(k): return f"{k[1]} m {'grouped' if k[0] else 'per-part'}"
print("### Forest and village at a glance\n")
print("| Configuration | Forest primitives | Forest draw calls | Village primitives | Village draw calls | Props drawn (forest) | Prop MultiMeshes (forest) |")
print("|---|---|---|---|---|---|---|")
print(f"| Before (one MultiMesh per part, 160 m blocks) | {B['forest']['primitives_avg']:,} | {B['forest']['draw_calls_avg']:,} | {B['village']['primitives_avg']:,} | {B['village']['draw_calls_avg']:,} | {B['forest']['props_drawn']:,} | 36 |")
for k in order:
    f, v = runs[k]["forest"], runs[k]["village"]
    print(f"| {name(k)} | {f['primitives_avg']:,} | {f['draw_calls_avg']:,} | {v['primitives_avg']:,} | {v['draw_calls_avg']:,} | {f['prop_view']['props_drawn']:,} | {f['prop_view']['multimeshes']:,} |")
for key, label in SCENES:
    print(f"\n### {label}\n")
    print("| Configuration | Primitives | Draw calls | Frame ms [M-sw] | Props generated (built) | Props drawn | Props in view | Chunks in view | Chunks drawn / built |")
    print("|---|---|---|---|---|---|---|---|---|")
    b = B[key]
    print(f"| Before | {b['primitives_avg']:,} | {b['draw_calls_avg']:,} | {b['frame_ms_avg']:,.0f} | {b['props_drawn']:,} | {b['props_drawn']:,} | (all) | (1 block) | 1 / 1 |")
    for k in order:
        r = runs[k][key]; v = r["prop_view"]
        print(f"| {name(k)} | {r['primitives_avg']:,} | {r['draw_calls_avg']:,} | {r['frame_ms_avg']:,.0f} | {v['props_built']:,} | {v['props_drawn']:,} | {v['props_in_view']:,} | {v['chunks_in_view']} | {v['chunks_drawn']} / {v['chunks_built']} |")
print("\n### Culling check: forest with sun shadows off\n")
print("| Configuration | Measured primitives | Terrain, grass and characters (no props) | Prop triangles in drawn chunks | Prop triangles in view | Measured − no-props |")
print("|---|---|---|---|---|---|")
for k in order:
    a = runs[k]["diag_forest_no_sun_shadows"]; n = runs[k]["diag_forest_no_props"]; v = a["prop_view"]
    print(f"| {name(k)} | {a['primitives_avg']:,} | {n['primitives_avg']:,} | {v['tris_drawn']:,} | {v['tris_in_view']:,} | {a['primitives_avg'] - n['primitives_avg']:,} |")
