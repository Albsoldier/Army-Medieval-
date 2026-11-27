## Builds the game's ship from Poly Haven's "Dutch Ship Large 01" (CC0,
## models/CREDITS.md; GRAPHICS_SHIPS.md). Step 2 of 2, after
## tools/decimate_ship.py has decimated the hull, rigging and sails to OBJs.
##
## Makes, in models/ships/:
##   ship_hull.res     the hull: scaled to the game (about 7 m long with the
##                     bowsprit), its bow to +z, the waterline at y = 0. The
##                     shipwrecks use it on its own.
##   ship_rigging.res  the masts, yards, ropes and sails, in the same frame.
##   ship_sails_shadow.res  the sails alone: they cast the rigging's shadow.
##                     Each is one surface on one material; the vertex data
##                     is compressed (16-bit).
##   ship.tres         the material (shaders/ship.gdshader): one draw call
##                     for any mix of the parts, each with its own small texture.
##   ship_hull.png (512²), ship_rigging.png (256²), ship_sails.png (512²):
##                   Poly Haven's colour maps, the ambient occlusion baked in,
##                   downsized (no normal or roughness maps).
##
##   WORK=<decimated OBJs> TEX=<Poly Haven textures folder> \
##   godot --headless --path last-light/game --script res://tools/build_ship_model.gd
## Run it once to paint the textures, then `godot --import`, then again.
extends SceneTree

const OUT := "res://models/ships/"
## Model metres to game metres: the hull's 30.4 m become 6.1 m (6.9 m with the bowsprit).
const SCALE := 0.2
## The hull's middle along its length (model x), put at the boat's origin.
const MID_X := 2.16
## Parts: OBJ name, texture size, part id (UV2.x, read by the shader).
const PARTS := [["dutch_ship_large_01_hull", "hull", 512, 0], ["dutch_ship_large_01_rigging", "rigging", 256, 1],
	["dutch_ship_large_01_sails", "sails", 512, 2]]
## Normals: faces meeting at more than this are a crease (planks, rails, decks).
const CREASE_DEG := 50.0
## How strongly the ambient occlusion darkens the colour.
const AO_STRENGTH := 0.8


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var work := OS.get_environment("WORK")
	var tex := OS.get_environment("TEX")
	if not FileAccess.file_exists(ProjectSettings.globalize_path(OUT + "ship_hull.png")) or OS.get_environment("REPAINT") == "1":
		for p in PARTS:
			_bake_texture(tex, str(p[1]), int(p[2]))
		print("(textures written: run --import, then this tool again)")
		quit()
		return
	var material := _material()
	var parts := []
	for p in PARTS:
		parts.append(_load_part(work.path_join(str(p[0]) + ".obj"), int(p[3])))
	var hull := _build([parts[0]], material)
	var rigging := _build([parts[1], parts[2]], material)
	# The rigging's shadow is cast by the sails alone (boat.gd): its thousand
	# ropes and spars, drawn again in each shadow cascade, cost more than their
	# thin shadows show. (The Compatibility renderer doesn't use shadow_mesh.)
	var sails := _build([parts[2]], material)
	for item in [["ship_hull", hull], ["ship_rigging", rigging], ["ship_sails_shadow", sails]]:
		var mesh: ArrayMesh = item[1]
		var err := ResourceSaver.save(mesh, OUT + str(item[0]) + ".res", ResourceSaver.FLAG_COMPRESS)
		print("%s: %d triangles, %d vertices, aabb %s, %s" % [item[0], mesh.surface_get_array_index_len(0) / 3,
			mesh.surface_get_array_len(0), mesh.get_aabb(), error_string(err)])
	quit()


## A colour map with its ambient occlusion baked in, downsized.
func _bake_texture(dir: String, part: String, size: int) -> void:
	var colour := Image.load_from_file(dir.path_join("dutch_ship_large_01_%s_diff_1k.jpg" % part))
	var arm := Image.load_from_file(dir.path_join("dutch_ship_large_01_%s_arm_1k.jpg" % part))
	colour.convert(Image.FORMAT_RGB8)
	arm.convert(Image.FORMAT_RGB8)
	for y in colour.get_height():
		for x in colour.get_width():
			var ao := arm.get_pixel(x, y).r
			colour.set_pixel(x, y, colour.get_pixel(x, y) * lerpf(1.0, ao, AO_STRENGTH))
	colour.resize(size, size, Image.INTERPOLATE_LANCZOS)
	colour.save_png(ProjectSettings.globalize_path(OUT + "ship_%s.png" % part))
	print("ship_%s.png: %dx%d" % [part, size, size])


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ship.gdshader")
	for part in ["hull", "rigging", "sails"]:
		m.set_shader_parameter(part + "_texture", load(OUT + "ship_%s.png" % part))
	ResourceSaver.save(m, OUT + "ship.tres")
	return load(OUT + "ship.tres")


## An OBJ's triangles (positions and UVs, one corner each), moved into the
## game's frame: bow to +z, scaled, centred, wound clockwise (Godot's front).
func _load_part(path: String, id: int) -> Dictionary:
	var v := PackedVector3Array()
	var vt := PackedVector2Array()
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		var w := line.split(" ", false)
		if w.size() < 3:
			continue
		match w[0]:
			"v":
				var p := Vector3(float(w[1]), float(w[2]), float(w[3]))
				v.append(Vector3(-p.z, p.y, p.x - MID_X) * SCALE)
			"vt":
				vt.append(Vector2(float(w[1]), float(w[2])))  # (decimate_ship.py writes the glTF's UVs as they are: v down)
			"f":
				var corners := []
				for k in range(1, w.size()):
					var ids := w[k].split("/")
					corners.append([int(ids[0]) - 1, int(ids[1]) - 1])
				for k in range(1, corners.size() - 1):
					for c in [corners[0], corners[k + 1], corners[k]]:  # reversed: counter-clockwise to clockwise
						pos.append(v[c[0]])
						uv.append(vt[c[1]])
	return {"pos": pos, "uv": uv, "id": id}


## One surface from parts: welded corners, crease-aware normals, the part id
## in UV2.x, LODs.
func _build(parts: Array, material: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()
	var crease := cos(deg_to_rad(CREASE_DEG))
	for part: Dictionary in parts:
		var pos: PackedVector3Array = part["pos"]
		var uv: PackedVector2Array = part["uv"]
		var tri_count := pos.size() / 3
		var face_n := PackedVector3Array()
		var at := {}  # position -> triangles there
		for t in tri_count:
			var a := pos[t * 3]
			var b := pos[t * 3 + 1]
			var c := pos[t * 3 + 2]
			face_n.append((c - a).cross(b - a))  # area-weighted, Godot's front
			for k in 3:
				var key := pos[t * 3 + k].snapped(Vector3.ONE * 0.0001)
				if not at.has(key):
					at[key] = []
				(at[key] as Array).append(t)
		var welded := {}
		for t in tri_count:
			var fn := face_n[t].normalized()
			for k in 3:
				var p := pos[t * 3 + k]
				var n := Vector3.ZERO
				for o: int in at[p.snapped(Vector3.ONE * 0.0001)]:
					if face_n[o].normalized().dot(fn) >= crease:
						n += face_n[o]
				n = n.normalized() if n.length_squared() > 0.0 else fn
				var key := [p, uv[t * 3 + k], n.snapped(Vector3.ONE * 0.01), int(part["id"])]
				if not welded.has(key):
					welded[key] = verts.size()
					verts.append(p)
					normals.append(n)
					uvs.append(uv[t * 3 + k])
					uv2s.append(Vector2(float(part["id"]), 0.0))
				index.append(welded[key])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = index
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, "Ship", Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	im.generate_lods(25.0, 60.0, [])
	var lods := []
	for l in im.get_surface_lod_count(0):
		lods.append(im.get_surface_lod_indices(0, l).size() / 3)
	print("  LODs: ", lods)
	return im.get_mesh()
