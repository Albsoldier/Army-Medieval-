"""Decimates Poly Haven's "Dutch Ship Large 01" (CC0) for the game's ship
(GRAPHICS_SHIPS.md). Step 1 of 2; step 2 is tools/build_ship_model.gd.

Reads the 1k glTF (hull, rigging, sails), welds each part, decimates it with
MeshLab's texture-preserving quadric edge collapse, and writes one OBJ per
part (positions, UVs) to OUT_DIR, for build_ship_model.gd.

    python3 -m venv venv && venv/bin/pip install pymeshlab numpy
    venv/bin/python -I last-light/game/tools/decimate_ship.py SRC.gltf OUT_DIR

(pymeshlab needs libOpenGL.so.0: apt-get install libopengl0.)
"""
import json
import os
import sys

import numpy as np
import pymeshlab

# Triangles kept per part (of 68,984 / 34,084 / 7,548). The rigging is mostly
# rope, a centimetre thick at the game's scale: it keeps its masts, yards and
# furled sails and loses most rope sides.
TARGETS = {
    "dutch_ship_large_01_hull": 7000,
    "dutch_ship_large_01_rigging": 5000,
    "dutch_ship_large_01_sails": 1200,
}

COMPONENTS = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(gltf, binary, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    dtype = COMPONENTS[acc["componentType"]]
    width = WIDTH[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    data = np.frombuffer(binary, dtype=dtype, count=acc["count"] * width, offset=start)
    return data.reshape(acc["count"], width) if width > 1 else data


def main(src, out_dir):
    gltf = json.load(open(src))
    binary = open(os.path.join(os.path.dirname(src), gltf["buffers"][0]["uri"]), "rb").read()
    os.makedirs(out_dir, exist_ok=True)
    for node in gltf["nodes"]:
        prim = gltf["meshes"][node["mesh"]]["primitives"][0]
        pos = accessor(gltf, binary, prim["attributes"]["POSITION"]).astype(np.float64)
        uv = accessor(gltf, binary, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
        faces = accessor(gltf, binary, prim["indices"]).astype(np.int32).reshape(-1, 3)
        ms = pymeshlab.MeshSet()
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pos, face_matrix=faces, v_tex_coords_matrix=uv))
        ms.compute_texcoord_transfer_vertex_to_wedge()
        # Weld the split (flat-shaded) vertices: wedge UVs keep the seams.
        ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.001))
        ms.meshing_remove_duplicate_faces()
        ms.meshing_remove_null_faces()
        target = TARGETS[node["name"]]
        if node["name"].endswith("rigging"):
            # Hundreds of separate ropes, masts and yards. Decimated together, a
            # net of ropes collapses into a filled sheet; each piece on its own
            # (the same share of its triangles) stays what it is.
            share = target / len(faces)
            ms.generate_splitting_by_connected_components(delete_source_mesh=True)
            ids = [i for i in range(ms.mesh_number() * 2 + 8) if ms.mesh_id_exists(i)]
            print("  rigging: %d pieces" % len(ids))
            kept_whole = 0
            for i in ids:
                ms.set_current_mesh(i)
                n = ms.current_mesh().face_number()
                if n <= 12:
                    continue
                area = ms.get_geometric_measures()["surface_area"]
                ms.generate_copy_of_current_mesh()
                ms.meshing_decimation_quadric_edge_collapse_with_texture(
                    targetfacenum=max(8, int(n * share)), qualitythr=0.1, extratcoordw=1.0,
                    preserveboundary=False, optimalplacement=True, preservenormal=True, planarquadric=True)
                copy = ms.current_mesh_id()
                # A net of ropes (shrouds, ratlines) whose holes closed gains area:
                # keep that piece as it was.
                if ms.get_geometric_measures()["surface_area"] > area * 1.15:
                    ms.delete_current_mesh()
                    kept_whole += 1
                else:
                    ms.set_current_mesh(i)
                    ms.delete_current_mesh()
                    ms.set_current_mesh(copy)
            print("  rigging: %d pieces kept whole (they would close up)" % kept_whole)
            ms.generate_by_merging_visible_meshes(mergevisible=True, deletelayer=True, alsounreferenced=False)
        else:
            ms.meshing_decimation_quadric_edge_collapse_with_texture(
                targetfacenum=target, qualitythr=0.3, extratcoordw=1.0, preserveboundary=True,
                boundaryweight=2.0, optimalplacement=True, preservenormal=True, planarquadric=True)
        m = ms.current_mesh()
        out = os.path.join(out_dir, node["name"] + ".obj")
        ms.save_current_mesh(out, save_vertex_normal=False, save_wedge_texcoord=True, save_vertex_color=False,
                             save_textures=False, save_wedge_normal=False)
        print("%s: %d -> %d triangles" % (node["name"], len(faces), m.face_number()))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
