"""Turns four models from Quaternius's Stylized Nature MegaKit (CC0) into the
small, game-ready files in game/models/nature/ (phase 4A environment prototype).

Usage:  python3 -I prepare_nature_models.py <MegaKit glTF folder> <game/models/nature>

For each model it:
  * scales it to the size of the procedural prop it replaces (1 tile = 1 m);
  * keeps positions, normals, texture UVs and indices, and drops the vertex
    colours (only bark has any: a dark-at-the-base shading, kept below);
  * writes per-vertex data the prop shaders read from UV2:
        rigid surfaces (bark, rock):  (0, shading)
        leaves and needles:           (1, sway)   sway grows with height
        flowers (the bush's "berries"): (-1, sway)
  * writes a .glb with no textures (the game loads the textures itself and
    shares them between models).
It also shrinks the textures those models use to browser-friendly sizes.
Normal maps are not used.
"""
import json
import os
import struct
import sys

from PIL import Image, ImageStat

# file, output name, scale (x, y, z), sway amplitude for leaves (m at the top)
MODELS = [
    ("Pine_5", "pine", (0.68, 0.68, 0.68), 0.06),
    ("CommonTree_5", "oak", (0.75, 0.75, 0.75), 0.07),
    ("Rock_Medium_2", "rock", (0.62, 0.45, 0.62), 0.0),
    ("Bush_Common_Flowers", "bush", (0.6, 0.6, 0.6), 0.03),
]
# Source texture -> (output file, size in pixels)
TEXTURES = {
    "Bark_NormalTree.png": ("bark.png", 256),
    "Leaf_Pine_C.png": ("pine_needles.png", 256),
    "Leaves_NormalTree_C.png": ("leaves.png", 512),
    "Flowers.png": ("flowers.png", 128),
    "Rocks_Diffuse.png": ("rock.png", 256),
}
# Far versions (drawn beyond NATURE_NEAR metres, see world.gd): share of leaf
# cards kept, how much each kept card grows, and the grid bark is merged on.
FAR = {
    "pine": (0.4, 1.45, 0.22),
    "oak": (0.25, 1.8, 0.3),
    "bush": (0.3, 1.6, 0.2),
}
CROWN_NORMALS = 0.8  # how far leaf normals are bent to point out of the crown
LEAF_MATERIALS = {"Leaves_Pine", "Leaves_NormalTree", "Leaves_TwistedTree"}
FLOWER_MATERIALS = {"Flowers"}

FMT = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    code, size = FMT[acc["componentType"]]
    width = WIDTH[acc["type"]]
    stride = view.get("byteStride", size * width)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<" + code * width, blob, start + i * stride)
        out.append(vals if width > 1 else vals[0])
    return out


def load_surfaces(src_dir, name, scale, sway_amp):
    """The model's surfaces, game-sized, as dicts of plain lists."""
    gltf = json.load(open(os.path.join(src_dir, name + ".gltf")))
    blob = open(os.path.join(src_dir, gltf["buffers"][0]["uri"]), "rb").read()
    prims = gltf["meshes"][0]["primitives"]
    # Height of the whole model, for scaling sway with height.
    top = 0.0
    for p in prims:
        for v in read_accessor(gltf, blob, p["attributes"]["POSITION"]):
            top = max(top, v[1] * scale[1])
    surfaces = []
    for p in prims:
        mat = gltf["materials"][p["material"]]["name"]
        a = p["attributes"]
        pos = [(v[0] * scale[0], v[1] * scale[1], v[2] * scale[2]) for v in read_accessor(gltf, blob, a["POSITION"])]
        nrm = []
        for n in read_accessor(gltf, blob, a["NORMAL"]):
            n = (n[0] / scale[0], n[1] / scale[1], n[2] / scale[2])
            length = max(sum(c * c for c in n) ** 0.5, 1e-8)
            nrm.append(tuple(c / length for c in n))
        uv = read_accessor(gltf, blob, a["TEXCOORD_0"])
        if mat in LEAF_MATERIALS:
            # Leaf cards face every way, so many are lit from behind or below
            # and the crown looks dark and blotchy. Bend each card's normal
            # towards "out from the middle of the crown", the usual trick for
            # stylised foliage, so the crown is lit like one soft shape.
            n_verts = len(pos)
            centre = tuple(sum(v[i] for v in pos) / n_verts for i in range(3))
            bent = []
            for v, n in zip(pos, nrm):
                out = tuple(v[i] - centre[i] for i in range(3))
                length = max(sum(c * c for c in out) ** 0.5, 1e-6)
                b = tuple(n[i] * (1 - CROWN_NORMALS) + out[i] / length * CROWN_NORMALS for i in range(3))
                length = max(sum(c * c for c in b) ** 0.5, 1e-6)
                bent.append(tuple(c / length for c in b))
            nrm = bent
        if mat in LEAF_MATERIALS or mat in FLOWER_MATERIALS:
            part = 1.0 if mat in LEAF_MATERIALS else -1.0
            uv2 = [(part, sway_amp * min(max(v[1] / top, 0.0), 1.0)) for v in pos]
        else:
            if "COLOR_0" in a:
                shade = [c[0] for c in read_accessor(gltf, blob, a["COLOR_0"])]
            else:
                shade = [1.0] * len(pos)
            uv2 = [(0.0, s) for s in shade]
        idx = read_accessor(gltf, blob, p["indices"])
        surfaces.append({"mat": mat, "pos": pos, "nrm": nrm, "uv": uv, "uv2": uv2, "idx": idx})
    return surfaces


def compact(s, idx, pos=None):
    """Keeps only the vertices `idx` uses (renumbered)."""
    pos = pos or s["pos"]
    remap = {}
    out = {"mat": s["mat"], "pos": [], "nrm": [], "uv": [], "uv2": [], "idx": []}
    for i in idx:
        if i not in remap:
            remap[i] = len(out["pos"])
            out["pos"].append(pos[i])
            for k in ("nrm", "uv", "uv2"):
                out[k].append(s[k][i])
        out["idx"].append(remap[i])
    return out


def far_cards(s, keep, grow):
    """A far version of a leaf or flower surface: every card (connected
    piece) is kept or dropped as a whole, evenly spread through the crown,
    and each kept card is enlarged about its middle so the crown stays as full."""
    idx = s["idx"]
    parent = list(range(len(s["pos"])))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for t in range(0, len(idx), 3):
        a, b, c = idx[t:t + 3]
        parent[find(a)] = find(b)
        parent[find(c)] = find(b)
    cards = {}
    for t in range(0, len(idx), 3):
        cards.setdefault(find(idx[t]), []).append(t)
    pos = list(s["pos"])
    kept = []
    for n, (root, tris) in enumerate(sorted(cards.items())):
        if (n * 0.6180339887) % 1.0 >= keep:  # golden-ratio steps: an even spread
            continue
        verts = sorted({idx[t + k] for t in tris for k in range(3)})
        mid = tuple(sum(pos[v][i] for v in verts) / len(verts) for i in range(3))
        for v in verts:
            pos[v] = tuple(mid[i] + (pos[v][i] - mid[i]) * grow for i in range(3))
        for t in tris:
            kept.extend(idx[t:t + 3])
    return compact(s, kept, pos)


def far_bark(s, cell):
    """A far version of bark: vertices merged on a grid `cell` metres wide
    (thin twigs collapse away, the trunk and main limbs stay)."""
    key_of = {}
    rep = []
    sums = {}
    for i, p in enumerate(s["pos"]):
        key = tuple(round(c / cell) for c in p)
        if key not in key_of:
            key_of[key] = i
            sums[key] = [0.0, 0.0, 0.0, 0]
        rep.append(key_of[key])
        acc = sums[key]
        for k in range(3):
            acc[k] += p[k]
        acc[3] += 1
    pos = list(s["pos"])
    for key, i in key_of.items():
        acc = sums[key]
        pos[i] = (acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3])
    idx = []
    seen = set()
    for t in range(0, len(s["idx"]), 3):
        a, b, c = (rep[s["idx"][t + k]] for k in range(3))
        if a == b or b == c or a == c:
            continue
        tri = tuple(sorted((a, b, c)))
        if tri in seen:
            continue
        seen.add(tri)
        idx.extend((a, b, c))
    return compact(s, idx, pos)


def write_glb(path, out_name, surfaces):
    data = bytearray()
    views, accessors, out_prims, materials = [], [], [], []

    def add(values, comp, kind, target, minmax=False):
        code, size = FMT[comp]
        width = WIDTH[kind]
        while len(data) % 4:
            data.append(0)
        offset = len(data)
        for v in values:
            data.extend(struct.pack("<" + code * width, *(v if width > 1 else (v,))))
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data) - offset, "target": target})
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(values), "type": kind}
        if minmax:
            acc["min"] = [min(v[i] for v in values) for i in range(width)]
            acc["max"] = [max(v[i] for v in values) for i in range(width)]
        accessors.append(acc)
        return len(accessors) - 1

    for s in surfaces:
        mat = s["mat"]
        attrs = {
            "POSITION": add(s["pos"], 5126, "VEC3", 34962, minmax=True),
            "NORMAL": add(s["nrm"], 5126, "VEC3", 34962),
            "TEXCOORD_0": add(s["uv"], 5126, "VEC2", 34962),
            "TEXCOORD_1": add(s["uv2"], 5126, "VEC2", 34962),
        }
        index_comp = 5123 if len(s["pos"]) < 65536 else 5125
        out_prims.append({"attributes": attrs, "indices": add(s["idx"], index_comp, "SCALAR", 34963),
                          "material": len(materials)})
        materials.append({"name": mat, "doubleSided": mat in LEAF_MATERIALS or mat in FLOWER_MATERIALS})
        print("  %-20s %5d triangles %5d vertices" % (mat, len(s["idx"]) // 3, len(s["pos"])))

    out = {
        "asset": {"version": "2.0", "generator": "Islander prepare_nature_models.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": out_name}],
        "meshes": [{"name": out_name, "primitives": out_prims}],
        "materials": materials, "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(data)}],
    }
    js = json.dumps(out, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    data += b"\0" * (-len(data) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(data))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js
    glb += struct.pack("<II", len(data), 0x004E4942) + bytes(data)
    open(path, "wb").write(glb)


def main():
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for name, out_name, scale, sway in MODELS:
        print(name, "->", out_name + ".glb")
        surfaces = load_surfaces(src_dir, name, scale, sway)
        write_glb(os.path.join(out_dir, out_name + ".glb"), out_name, surfaces)
        if out_name in FAR:
            keep, grow, cell = FAR[out_name]
            far = [far_bark(s, cell) if s["mat"] not in LEAF_MATERIALS | FLOWER_MATERIALS
                   else far_cards(s, keep, grow) for s in surfaces]
            print(name, "->", out_name + "_far.glb")
            write_glb(os.path.join(out_dir, out_name + "_far.glb"), out_name + "_far", far)
    for src, (dst, size) in TEXTURES.items():
        img = Image.open(os.path.join(src_dir, src))
        img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
        if img.mode == "RGBA":
            # Fill the see-through pixels with the leaves' average colour, so
            # the smaller mip levels used at a distance don't darken the edges.
            mask = img.getchannel("A").point(lambda a: 255 if a > 127 else 0)
            mean = tuple(int(c) for c in ImageStat.Stat(img.convert("RGB"), mask).mean)
            filled = Image.new("RGB", img.size, mean)
            filled.paste(img.convert("RGB"), mask=mask)
            filled.putalpha(img.getchannel("A"))
            img = filled
        img.resize((size, size), Image.LANCZOS).save(os.path.join(out_dir, dst), optimize=True)
        print(src, "->", dst, size)


if __name__ == "__main__":
    main()
