# Builds comparison images and a shimmer score from tools/shadow_shots.gd output.
import sys, os, json
import numpy as np
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
P = ["A", "B", "C", "D"]
NAMES = {"A": "A: 4 cascades, 4096", "B": "B: 2 cascades, 4096", "C": "C: 2 cascades, 2048", "D": "D: 1 cascade, 2048"}
def label(img, text):
    d = ImageDraw.Draw(img); d.rectangle([0, 0, 8 + 7 * len(text), 22], fill=(0, 0, 0)); d.text((5, 5), text, fill=(255, 230, 150)); return img
# 2x2 grid per scene at half size
for scene in ["near", "base", "far", "forest", "first_person"]:
    tiles = [label(Image.open(f"{src}/{scene}-{p}.png").convert("RGB").resize((640, 360), Image.LANCZOS), NAMES[p]) for p in P]
    grid = Image.new("RGB", (1280, 720))
    for i, t in enumerate(tiles):
        grid.paste(t, ((i % 2) * 640, (i // 2) * 360))
    grid.save(f"{out}/grid-{scene}.jpg", quality=86)
# Full-resolution crops of shadow detail, side by side
CROPS = {"near": (380, 260, 780, 560), "base": (520, 260, 920, 560), "far": (480, 230, 880, 530), "forest": (440, 250, 840, 550)}
for scene, box in CROPS.items():
    strip = Image.new("RGB", (1600, 300))
    for i, p in enumerate(P):
        strip.paste(label(Image.open(f"{src}/{scene}-{p}.png").convert("RGB").crop(box), NAMES[p]), (i * 400, 0))
    strip.save(f"{out}/crop-{scene}.jpg", quality=88)
# Shimmer: pixels whose brightness flips back and forth between consecutive frames
REGION = (500, 220, 1060, 630)  # the 3D view, clear of the HUD and toasts
res = {}
for p in P + ["off"]:
    fr = [np.asarray(Image.open(f"{src}/shimmer-{p}-{k:02d}.png").convert("L").crop(REGION), dtype=np.float32) for k in range(10)]
    d = [fr[k + 1] - fr[k] for k in range(9)]
    flips = [((np.abs(d[k]) > 8) & (np.abs(d[k + 1]) > 8) & (np.sign(d[k]) != np.sign(d[k + 1]))).mean() for k in range(8)]
    changed = [(np.abs(x) > 8).mean() for x in d]
    res[p] = {"flicker_pct": round(100 * float(np.mean(flips)), 3), "changed_pct": round(100 * float(np.mean(changed)), 3),
              "mean_abs_diff": round(float(np.mean([np.abs(x).mean() for x in d])), 3)}
# Shadow difference from A (how much each preset changes the picture)
for scene in ["near", "base", "far", "forest", "first_person"]:
    a = np.asarray(Image.open(f"{src}/{scene}-A.png").convert("L").crop(REGION), dtype=np.float32)
    for p in P[1:]:
        b = np.asarray(Image.open(f"{src}/{scene}-{p}.png").convert("L").crop(REGION), dtype=np.float32)
        res.setdefault("diff_vs_A", {}).setdefault(scene, {})[p] = round(float((np.abs(a - b) > 12).mean() * 100), 2)
# How much of the view is in shadow (dark pixels), to catch missing shadows
for scene in ["near", "base", "far", "forest"]:
    for p in P:
        g = np.asarray(Image.open(f"{src}/{scene}-{p}.png").convert("L").crop(REGION), dtype=np.float32)
        res.setdefault("dark_pct", {}).setdefault(scene, {})[p] = round(float((g < 60).mean() * 100), 2)
json.dump(res, open(f"{out}/analysis.json", "w"), indent=1)
print(json.dumps(res, indent=1))
