"""Turns three buildings from Kay Lousberg's KayKit Medieval Hexagon Pack
(CC0) into the game-ready files in game/models/buildings/ (phase 4B building
prototype, GRAPHICS_BUILDING_PROTOTYPE.md).

Usage:
  python3 -I prepare_building_models.py <pack>/addons/kaykit_medieval_hexagon_pack/Assets/gltf/buildings <game/models/buildings>

For each building it:
  * merges every node of the model into one mesh with one surface (they all
    use the pack's one texture atlas), applying the node transforms;
  * scales and turns it (1 tile = 1 m, the front facing +z like the old
    models). Cottages and towers are drawn larger than their tile, which only
    changes how they look: collision and placement stay on the one tile;
  * for the wall, keeps a 1 m section of the pack's 2 m wall (the pack's
    walls follow hexagon edges; the game's walls are one tile long);
  * writes a .glb with no textures (the game loads the shared atlas itself);
  * for the cottage, adds a second surface: copies of its window glass, just
    in front of it, which the game draws with the shared glowing material the
    old cottage's window used (its night-time glow).
It also writes the atlas, hexagons_medieval.png. The pack's is a 1024x1024
palette of flat colour blocks; at 128x128 no colour the three models use moves
by more than 1/255, and it's 64 times less texture memory and download.
"""
import json
import math
import os
import struct
import sys

from PIL import Image

# kind -> (source model, scale (x, y, z), turn about y in degrees, keep x in [lo, hi] then centre)
MODELS = {
    "cottage": ("yellow/building_home_A_yellow", (2.58, 2.58, 2.58), 0.0, None),
    "stone_wall": ("neutral/wall_straight", (1.0, 2.08, 1.5), 0.0, (0.0, 1.0)),
    "archer_tower": ("red/building_tower_A_red", (1.75, 2.43, 1.75), 0.0, None),
}

ATLAS_SIZE = 128
# Buildings whose windows glow at night, and the greys of window glass in the game's atlas.
WINDOW_GLOW = {"cottage"}
GLASS = {(0x8f, 0x86, 0x7e), (0x92, 0x8a, 0x81), (0x99, 0x91, 0x89), (0x9a, 0x93, 0x8b)}

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


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = node.get("translation", (0, 0, 0))
    qx, qy, qz, qw = node.get("rotation", (0, 0, 0, 1))
    sx, sy, sz = node.get("scale", (1, 1, 1))
    r = [[1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
         [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
         [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)]]
    return [[r[0][0] * sx, r[0][1] * sy, r[0][2] * sz, tx],
            [r[1][0] * sx, r[1][1] * sy, r[1][2] * sz, ty],
            [r[2][0] * sx, r[2][1] * sy, r[2][2] * sz, tz],
            [0, 0, 0, 1]]


def apply(m, v, w=1.0):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] + m[i][3] * w for i in range(3))


def load(src_dir, name):
    """Every mesh of the model, in model space: positions, normals, uvs, indices."""
    gltf = json.load(open(os.path.join(src_dir, name + ".gltf")))
    blob = open(os.path.join(os.path.dirname(os.path.join(src_dir, name)), gltf["buffers"][0]["uri"]), "rb").read()
    pos, nrm, uv, idx = [], [], [], []
    ident = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]

    def walk(n, parent):
        node = gltf["nodes"][n]
        m = mat_mul(parent, node_matrix(node))
        if "mesh" in node:
            for p in gltf["meshes"][node["mesh"]]["primitives"]:
                a = p["attributes"]
                first = len(pos)
                for v in read_accessor(gltf, blob, a["POSITION"]):
                    pos.append(apply(m, v))
                for v in read_accessor(gltf, blob, a["NORMAL"]):
                    n2 = apply(m, v, 0.0)
                    length = max(sum(c * c for c in n2) ** 0.5, 1e-8)
                    nrm.append(tuple(c / length for c in n2))
                uv.extend(read_accessor(gltf, blob, a["TEXCOORD_0"]))
                idx.extend(first + i for i in read_accessor(gltf, blob, p["indices"]))
        for c in node.get("children", []):
            walk(c, m)
    for n in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(n, ident)
    return pos, nrm, uv, idx


def convert(pos, nrm, uv, idx, scale, turn, keep):
    if keep is not None:
        lo, hi = keep
        kept = []
        for t in range(0, len(idx), 3):
            xs = [pos[idx[t + k]][0] for k in range(3)]
            if sum(xs) / 3.0 >= lo and sum(xs) / 3.0 <= hi:
                kept.extend(idx[t:t + 3])
        idx = kept
        mid = (lo + hi) / 2.0
        pos = [(p[0] - mid, p[1], p[2]) for p in pos]
    c, s = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    out_pos, out_nrm = [], []
    for p, n in zip(pos, nrm):
        x, y, z = p[0] * scale[0], p[1] * scale[1], p[2] * scale[2]
        out_pos.append((x * c + z * s, y, -x * s + z * c))
        n = (n[0] / scale[0], n[1] / scale[1], n[2] / scale[2])
        length = max(sum(v * v for v in n) ** 0.5, 1e-8)
        n = tuple(v / length for v in n)
        out_nrm.append((n[0] * c + n[2] * s, n[1], -n[0] * s + n[2] * c))
    # Keep only the vertices used.
    remap, P, N, U, I = {}, [], [], [], []
    for i in idx:
        if i not in remap:
            remap[i] = len(P)
            P.append(out_pos[i])
            N.append(out_nrm[i])
            U.append(uv[i])
        I.append(remap[i])
    return P, N, U, I


def write_glb(path, name, surfaces):
    """surfaces: [(material name, positions, normals, uvs, indices)], one primitive each."""
    data = bytearray()
    views, accessors = [], []

    def add(values, comp, kind, target, minmax=False):
        code, _ = FMT[comp]
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

    prims, materials = [], []
    for mat, P, N, U, I in surfaces:
        prims.append({"attributes": {"POSITION": add(P, 5126, "VEC3", 34962, True), "NORMAL": add(N, 5126, "VEC3", 34962),
                                     "TEXCOORD_0": add(U, 5126, "VEC2", 34962)},
                      "indices": add(I, 5123 if len(P) < 65536 else 5125, "SCALAR", 34963), "material": len(materials)})
        materials.append({"name": mat})
    out = {"asset": {"version": "2.0", "generator": "Islander prepare_building_models.py"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
           "meshes": [{"name": name, "primitives": prims}], "materials": materials,
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(data)}]}
    js = json.dumps(out, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    data += b"\0" * (-len(data) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(data))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(data), 0x004E4942) + bytes(data)
    open(path, "wb").write(glb)


def window_panes(P, N, U, I, atlas):
    """Copies of the window-glass triangles, 4 mm in front of the glass, for the
    night-time glow (drawn by the game with the old cottage window's shared
    glowing material). Glass is told apart by its grey in the atlas, on walls."""
    W, H = atlas.size
    out_p, out_n, out_u, out_i = [], [], [], []
    for t in range(0, len(I), 3):
        n = N[I[t]]
        if abs(n[1]) > 0.2:
            continue  # floors, roofs and ledges, not walls
        u = sum(U[I[t + k]][0] for k in range(3)) / 3.0
        v = sum(U[I[t + k]][1] for k in range(3)) / 3.0
        if atlas.getpixel((min(int(u * W), W - 1), min(int(v * H), H - 1))) not in GLASS:
            continue
        for k in range(3):
            p, nk = P[I[t + k]], N[I[t + k]]
            out_p.append(tuple(p[j] + nk[j] * 0.004 for j in range(3)))
            out_n.append(nk)
            out_u.append(U[I[t + k]])
            out_i.append(len(out_i))
    return out_p, out_n, out_u, out_i


def main():
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    source_atlas = Image.open(os.path.join(src_dir, "neutral", "hexagons_medieval.png")).convert("RGB")
    atlas = source_atlas.resize((ATLAS_SIZE, ATLAS_SIZE), Image.BOX)  # the game's atlas
    for kind, (name, scale, turn, keep) in MODELS.items():
        P, N, U, I = convert(*load(src_dir, name), scale, turn, keep)
        surfaces = [("hexagons_medieval", P, N, U, I)]
        if kind in WINDOW_GLOW:
            panes = window_panes(P, N, U, I, atlas)
            surfaces.append(("WindowGlow", *panes))
            print("%-13s    window panes: %d triangles" % (kind, len(panes[3]) // 3))
        write_glb(os.path.join(out_dir, kind + ".glb"), kind, surfaces)
        size = [max(p[k] for p in P) - min(p[k] for p in P) for k in range(3)]
        print("%-13s <- %-34s %5d triangles %5d vertices  size %.2f x %.2f x %.2f m" % (
            kind, name, len(I) // 3, len(P), size[0], size[1], size[2]))
    atlas.save(os.path.join(out_dir, "hexagons_medieval.png"), optimize=True)


if __name__ == "__main__":
    main()
