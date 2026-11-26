## Builds the Centurion's body (phase 4D.2, GRAPHICS_PHASE_4D2_CENTURION.md)
## into models/soldiers/centurion.scn. It is the standard legionary's body
## (tools/build_legionary_model.gd: the same CC0 Quaternius parts, the same
## simplification, so the two match) with an officer's kit added into the same
## single skinned surface:
##   - a galea: a helmet bowl with a gold rim, cheek guards and a neck guard,
##     drawn as armour (instance-uniform colours), skinned to the head;
##   - a tall transverse crest, side to side (an officer's mark), in legion red;
##   - phalerae: three gold discs on the chest armour;
##   - a red cloak over the shoulders, two-sided, skinned down the back.
## It writes no textures: every part points into the legionary's atlas
## (models/soldiers/legionary_*.png): the crest and cloak into its dyed-red
## linen, the helmet and discs are armour, coloured per soldier. At runtime
## soldier.gd draws it with the legionary's own material, so legionaries and
## centurions share one material and one set of textures.
##   PACK_DIR=<folder with the extracted .gltf/.glb, .bin and .png files> \
##     godot --headless --path last-light/game --script res://tools/build_centurion_model.gd
extends SceneTree

const OUT := "res://models/soldiers/"
const ANIMS := {"Idle": "Idle", "Walk": "Walk", "Run": "Jog_Fwd", "Sword_Slash": "Sword_Attack", "Death": "Death01"}
## Atlas regions (x, y, w, h as fractions) for each source material.
const REGIONS := {
	"MI_Peasant": Rect2(0.0, 0.0, 0.5, 1.0),
	"MI_Regular_Male": Rect2(0.5, 0.0, 0.25, 0.5),
	"MI_Superhero_Male": Rect2(0.75, 0.0, 0.25, 0.5),
	"MI_Hair_1": Rect2(0.5, 0.5, 0.25, 0.5),
	"MI_Eyes": Rect2(0.75, 0.5, 0.125, 0.25),
}
const HEAD_BONES := ["Head", "neck_01"]
const PART_CLOTH := 0
const PART_SKIN := 1
const PART_ARMOUR := 4
## Plates over the chest, back and shoulders: the tunic triangles moved mostly
## by these bones, and how far out they sit.
const ARMOUR_BONES := ["spine_02", "spine_03", "clavicle_l", "clavicle_r"]
const ARMOUR_OFFSET := 0.016
## Each part's share of triangles kept at most (Godot's simplifier picks the
## nearest level at or below it). Mesh name -> share.
const SIMPLIFY := {
	"Male_Peasant_Arms": 0.3, "Male_Peasant_Body": 0.35, "Male_Peasant_Feet": 0.2, "Male_Peasant_Legs": 0.5,
	"SuperHero_Male": 0.5, "Eyes": 0.3, "Eyebrows": 0.3, "Hair_Buzzed": 0.6,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := OS.get_environment("PACK_DIR")
	if dir == "":
		printerr("Set PACK_DIR to the folder with the Quaternius files.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var outfit := _load(dir.path_join("Male_Peasant.gltf"))
	var body := _load(dir.path_join("Superhero_Male_FullBody.gltf"))
	var hair := _load(dir.path_join("Hair_Buzzed.gltf"))
	var library := _load(dir.path_join("UAL1_Standard.glb"))
	var parts := []
	for mi in outfit.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "outfit"])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "head" if mi.name == "SuperHero_Male" else "whole"])
	for mi in hair.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "whole"])
	assert(ResourceLoader.exists(OUT + "legionary_colour.png"), "build the legionary first (its atlas is shared)")
	_merge(parts)
	_add_armour(outfit.find_child("Male_Peasant_Body", true, false))
	_measure_body(outfit, body)
	_add_helmet()
	_add_crest()
	_add_phalerae()
	_add_cloak()
	_save_scene(outfit, _finish(), library)
	quit()


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "can't read " + path)
	return doc.generate_scene(state)


# ---------- Geometry ----------

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _t := PackedFloat32Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()  # (part + across, height): see character_atlas.gdshader
var _b := PackedInt32Array()
var _w := PackedFloat32Array()
var _idx := PackedInt32Array()
var _skin := Skin.new()
var _bind_index := {}  # "bone|pose" -> bind
var _counts := {}  # part name -> [triangles before, after]


## [bone names, index of each bind in the merged skin]; identical binds shared.
func _binds(mi: MeshInstance3D) -> Array:
	var part_skel := mi.get_node(mi.skeleton) as Skeleton3D
	var names := []
	var map := []
	for b in mi.skin.get_bind_count():
		var bone_name := mi.skin.get_bind_name(b)
		if bone_name == "":
			bone_name = part_skel.get_bone_name(mi.skin.get_bind_bone(b))
		names.append(bone_name)
		var key := "%s|%s" % [bone_name, mi.skin.get_bind_pose(b)]
		if not _bind_index.has(key):
			_bind_index[key] = _skin.get_bind_count()
			_skin.add_named_bind(bone_name, mi.skin.get_bind_pose(b))
		map.append(_bind_index[key])
	return [names, map]


func _dominant(names: Array, pb: PackedInt32Array, pw: PackedFloat32Array, i: int) -> String:
	var best := 0
	for k in 4:
		if pw[i * 4 + k] > pw[i * 4 + best]:
			best = k
	return names[pb[i * 4 + best]]


## Adds the triangles of one surface; tri_part[t] is triangle t's part (-1: left out).
func _append(a: Array, binds: Array, r: Rect2, tri_part: PackedInt32Array, offset := 0.0,
		plate := Callable(), uv_wrap := false) -> int:
	var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var pt: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
	var pu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var pw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var remap := {}
	var kept := 0
	for t in tri_part.size():
		var part := tri_part[t]
		if part < 0:
			continue
		for k in 3:
			var i := pi[t * 3 + k]
			var key := i * 8 + part
			if not remap.has(key):
				remap[key] = _v.size()
				_v.append(pv[i] + pn[i] * offset)
				_n.append(pn[i])
				for c in 4:
					_t.append(pt[i * 4 + c] if pt.size() > 0 else (1.0 if c == 0 or c == 3 else 0.0))
				var u := Vector2(fposmod(pu[i].x, 1.0), fposmod(pu[i].y, 1.0)) if uv_wrap else pu[i]
				_uv.append(r.position + u * r.size)
				var p2: Vector2 = plate.call(pv[i]) if plate.is_valid() else Vector2(0.5, 0.0)
				_uv2.append(Vector2(part + 0.05 + 0.9 * clampf(p2.x, 0.0, 1.0), p2.y))
				for c in 4:
					_b.append(binds[1][pb[i * 4 + c]])
					_w.append(pw[i * 4 + c])
			_idx.append(remap[key])
		kept += 1
	return kept


## The triangles of a simplified version of a surface: the first level of
## Godot's simplifier with at most `share` of them.
func _simplified(a: Array, share: float) -> PackedInt32Array:
	var full: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	if share >= 1.0:
		return full
	var im := ImporterMesh.new()
	var only := []
	only.resize(Mesh.ARRAY_MAX)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		only[k] = a[k]
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, only)
	im.generate_lods(25.0, 60.0, [])
	var best := full
	for l in im.get_surface_lod_count(0):
		var lod := im.get_surface_lod_indices(0, l)
		best = lod
		if lod.size() <= full.size() * share:
			break
	return best


func _merge(parts: Array) -> void:
	for part in parts:
		var mi: MeshInstance3D = part[0]
		var mode: String = part[1]
		var binds := _binds(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var r: Rect2 = REGIONS[mat.resource_name]
			var a := mi.mesh.surface_get_arrays(s)
			var before: int = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var pw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			if mode == "head":
				# Only the head and neck of the full body: the outfit covers the rest.
				# Cut first, then simplify what's left.
				var pi0: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var keep := PackedInt32Array()
				for t in range(0, pi0.size(), 3):
					var on := true
					for k in 3:
						on = on and _dominant(binds[0], pb, pw, pi0[t + k]) in HEAD_BONES
					if on:
						keep.append_array(PackedInt32Array([pi0[t], pi0[t + 1], pi0[t + 2]]))
				a[Mesh.ARRAY_INDEX] = keep
			a[Mesh.ARRAY_INDEX] = _simplified(a, float(SIMPLIFY.get(_simplify_key(mi.name), 1.0)))
			var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var skin_mat: bool = mat.resource_name in ["MI_Regular_Male", "MI_Superhero_Male"]
			var tri_part := PackedInt32Array()
			tri_part.resize(pi.size() / 3)
			tri_part.fill(PART_SKIN if skin_mat else PART_CLOTH)
			var kept := _append(a, binds, r, tri_part, 0.0, Callable(), mat.resource_name == "MI_Eyes")
			_counts["%s/%d" % [mi.name, s]] = [before, kept]
			print("part: ", mi.name, "/", s, " ", before, " -> ", kept, " triangles")


func _simplify_key(mesh_name: String) -> String:
	for key in SIMPLIFY:
		if mesh_name.begins_with(key):
			return key
	return mesh_name


## Iron plates: the simplified tunic's chest, back and shoulders, moved out
## along their normals and skinned like the tunic; the shader draws them as
## plates (lames) in the armour colour set per soldier (instance uniforms).
func _add_armour(body_mi: MeshInstance3D) -> void:
	var binds := _binds(body_mi)
	for s in body_mi.mesh.get_surface_count():
		var mat := body_mi.mesh.surface_get_material(s) as BaseMaterial3D
		var a := body_mi.mesh.surface_get_arrays(s)
		a[Mesh.ARRAY_INDEX] = _simplified(a, float(SIMPLIFY["Male_Peasant_Body"]))
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var pw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var tri_part := PackedInt32Array()
		tri_part.resize(pi.size() / 3)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for t in tri_part.size():
			var on := true
			for k in 3:
				on = on and _dominant(binds[0], pb, pw, pi[t * 3 + k]) in ARMOUR_BONES
			tri_part[t] = PART_ARMOUR if on else -1
			if on:
				for k in 3:
					lo = lo.min(pv[pi[t * 3 + k]])
					hi = hi.max(pv[pi[t * 3 + k]])
		var size := hi - lo
		var plate := func(p: Vector3) -> Vector2: return Vector2((p.x - lo.x) / size.x, (p.y - lo.y) / size.y)
		# The plates on the back are under the cloak: left out (they would only
		# be skinned unseen, and poke through it when the back bends). The
		# plates' pattern is mapped before this, so the rest look as on a legionary.
		var hidden := 0
		for t in tri_part.size():
			if tri_part[t] != PART_ARMOUR:
				continue
			var c := (pv[pi[t * 3]] + pv[pi[t * 3 + 1]] + pv[pi[t * 3 + 2]]) / 3.0
			if c.z < -0.02 and absf(c.x) < 0.22 and c.y < _cloak_top(c.x) - 0.03:
				tri_part[t] = -1
				hidden += 1
		var kept := _append(a, binds, REGIONS[mat.resource_name], tri_part, ARMOUR_OFFSET, plate)
		_counts["armour"] = [0, kept]
		print("armour: ", kept, " triangles (", hidden, " under the cloak left out), ", lo, " .. ", hi)


## [ArrayMesh with LODs, Skin]: everything in one surface.
func _finish() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TANGENT] = _t
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_BONES] = _b
	arrays[Mesh.ARRAY_WEIGHTS] = _w
	arrays[Mesh.ARRAY_INDEX] = _idx
	var im := ImporterMesh.new()
	# Not ARRAY_FLAG_COMPRESS_ATTRIBUTES: it breaks skinned meshes when animated (phase 4C).
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _material(), "Body")
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	print("merged: ", _idx.size() / 3, " triangles, ", _v.size(), " vertices, ", _skin.get_bind_count(), " binds, LODs ", im.get_surface_lod_count(0))
	for l in im.get_surface_lod_count(0):
		print("  LOD ", l, ": ", im.get_surface_lod_indices(0, l).size() / 3, " triangles")
	return [mesh, _skin]


## The legionary's material, rebuilt with the same shader and textures (the
## game swaps in the legionary's own instance, so both share one).
func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "Legionary_Atlas"  # the same textures; soldier.gd shares the legionary's material
	m.shader = load("res://shaders/character_atlas.gdshader")
	if ResourceLoader.exists(OUT + "legionary_colour.png"):
		m.set_shader_parameter("albedo_tex", load(OUT + "legionary_colour.png"))
		m.set_shader_parameter("normal_tex", load(OUT + "legionary_normal.png"))
		m.set_shader_parameter("orm_tex", load(OUT + "legionary_orm.png"))
	return m


# ---------- The officer's kit ----------

## The dyed-red linen in the legionary's atlas (an all-red patch, found by
## scanning the atlas): the crest and cloak take their cloth from here.
const RED_LINEN := Rect2(0.085, 0.475, 0.11, 0.175)
## The helmet's shape around the head, measured from the head mesh (_measure_body).
const HELMET_CLEARANCE := 0.016
const CREST_HALF_WIDTH := 0.2  # ear to ear and a little beyond
const CREST_HEIGHT := 0.15  # above the helmet
const CREST_THICKNESS := 0.022
## The cloak: from the shoulders to just above the knee, standing off the back
## (more towards the hem, so the legs swing under it).
const CLOAK_TOP := 1.5
const CLOAK_HEM := 0.74
const CLOAK_CLEARANCE := 0.045
const CLOAK_FLARE := 0.11
const CLOAK_COLUMNS := 8
const CLOAK_ROWS := 9

var _head_box := AABB()
var _brow := 0.0  # the top of the eyebrows
var _back := {}  # Vector2i(x bin, y bin) -> furthest-back z of the clothes
var _front := {}  # the same, furthest-forward z


## Where the head and the clothes are, at rest.
func _measure_body(outfit: Node, body: Node) -> void:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if mi.name == "SuperHero_Male":
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for v in verts:
				if v.y > 1.55:
					lo = lo.min(v)
					hi = hi.max(v)
			_head_box = AABB(lo, hi - lo)
		elif mi.name == "Eyebrows":
			for v in verts:
				_brow = maxf(_brow, v.y)
	for mi in outfit.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				_profile_add(v)
	# The iron plates are already in the surface (part 4): the cloak and discs
	# must clear them, not just the tunic under them.
	for i in _v.size():
		if int(_uv2[i].x) == PART_ARMOUR:
			_profile_add(_v[i])
	print("head ", _head_box, " brow ", _brow)


## Adds a point of the clothes to the back profile (if it is behind the body's
## middle) or the front one (if in front): a bin with only chest points must
## not count as the back.
func _profile_add(v: Vector3) -> void:
	var key := Vector2i(int(floor(v.x / 0.04)), int(floor(v.y / 0.04)))
	if v.z < -0.02:
		_back[key] = minf(_back.get(key, INF), v.z)
	elif v.z > 0.02:
		_front[key] = maxf(_front.get(key, -INF), v.z)


## The clothes' furthest-back (or forward) z near (x, y), searching outward.
func _surface_z(x: float, y: float, back: bool) -> float:
	var table := _back if back else _front
	var key := Vector2i(int(floor(x / 0.04)), int(floor(y / 0.04)))
	for r in 4:
		var best := INF if back else -INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var k := key + Vector2i(dx, dy)
				if table.has(k):
					best = minf(best, table[k]) if back else maxf(best, table[k])
		if absf(best) < INF:
			return best
	return -0.15 if back else 0.12


func _bind_of(bone: String) -> int:
	for b in _skin.get_bind_count():
		if _skin.get_bind_name(b) == bone:
			return b
	assert(false, "no bind for " + bone)
	return 0


## Adds one vertex skinned to up to four bones ({bone name: weight}).
func _vertex(p: Vector3, n: Vector3, uv: Vector2, part: int, plate: Vector2, bones: Dictionary) -> int:
	_v.append(p)
	_n.append(n.normalized())
	var tg := n.cross(Vector3.UP)
	tg = (tg if tg.length() > 0.01 else Vector3.RIGHT).normalized()
	_t.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, 1.0]))
	_uv.append(uv)
	_uv2.append(Vector2(part + 0.05 + 0.9 * clampf(plate.x, 0.0, 1.0), plate.y))
	var names := bones.keys()
	var total := 0.0
	for k in names:
		total += float(bones[k])
	for c in 4:
		_b.append(_bind_of(names[c]) if c < names.size() else 0)
		_w.append(float(bones[names[c]]) / total if c < names.size() else 0.0)
	return _v.size() - 1


## Two triangles for the quad a-b-c-d (counter-clockwise seen from outside).
func _quad(a: int, b: int, c: int, d: int) -> void:
	_idx.append_array(PackedInt32Array([a, c, b, a, d, c]))


## A grid of vertices (rows x cols, row-major) into quads; flip reverses the faces.
func _grid(first: int, rows: int, cols: int, flip := false) -> int:
	var tris := 0
	for r in rows - 1:
		for c in cols - 1:
			var a := first + r * cols + c
			if flip:
				_quad(a, a + cols, a + cols + 1, a + 1)
			else:
				_quad(a, a + 1, a + cols + 1, a + cols)
			tris += 2
	return tris


## The galea: a bowl over the head, its rim above the brow at the front and
## lower at the back, a gold rim, a flared neck guard and two cheek guards.
## Drawn as armour (the soldier's armour colours); plate y keeps the bowl clear
## of the plate seams and puts the rim, neck guard and cheeks in the gold trim
## band; plate x gives the centre ridge, front to back.
func _add_helmet() -> void:
	var head := _head_box.get_center()
	var radius := _head_box.size * 0.5 + Vector3.ONE * HELMET_CLEARANCE
	var centre := Vector3(0.0, _head_box.end.y - radius.y, head.z)
	var front_rim := _brow + 0.012
	var back_rim := _head_box.position.y + 0.1
	var cols := 24
	var rows := 7
	var first := _v.size()
	var start := _idx.size()
	var head_only := {"Head": 1.0}
	# The bowl: rows from the crown down to the rim, all the way round.
	for r in rows:
		for c in cols + 1:
			var phi := TAU * c / cols  # 0: the front (+z)
			var rim_y := lerpf(front_rim, back_rim, (1.0 - cos(phi)) * 0.5)
			var lowest := acos(clampf((rim_y - centre.y) / radius.y, -1.0, 1.0))
			var t := lowest * r / (rows - 1)
			var dir := Vector3(sin(t) * sin(phi), cos(t), sin(t) * cos(phi))
			var p := centre + dir * radius
			var trim := r == rows - 1
			_vertex(p, dir / radius, Vector2(0.5, 0.5), PART_ARMOUR,
				Vector2(0.5 + p.x / 0.3, 0.03 if trim else 0.14), head_only)
	_grid(first, rows, cols + 1, true)
	# The neck guard and brim: a lip round the rim, wide at the back.
	var lip := _v.size()
	for c in cols + 1:
		var rim := first + (rows - 1) * (cols + 1) + c
		var phi := TAU * c / cols
		var out := Vector3(sin(phi), 0.0, cos(phi))
		var wide := lerpf(0.008, 0.05, pow((1.0 - cos(phi)) * 0.5, 2.0))
		_vertex(_v[rim] + out * wide + Vector3.DOWN * wide * 0.5, Vector3.UP + out, Vector2(0.5, 0.5), PART_ARMOUR,
			Vector2(0.5, 0.03), head_only)
	for c in cols:
		var rim := first + (rows - 1) * (cols + 1) + c
		_quad(rim, lip + c, lip + c + 1, rim + 1)
	# Cheek guards: plates hanging from the rim at the sides, in front of the ears.
	for side in [-1.0, 1.0]:
		var x: float = side * (radius.x - 0.004)
		var top := lerpf(front_rim, back_rim, 0.5) + 0.01
		var corners := [Vector3(x, top, head.z + 0.06), Vector3(x, top, head.z - 0.02),
			Vector3(x * 0.92, top - 0.085, head.z - 0.01), Vector3(x * 0.88, top - 0.075, head.z + 0.06)]
		var nrm := Vector3(side, -0.15, 0.0)
		var ids := []
		for k in 4:
			ids.append(_vertex(corners[k], nrm, Vector2(0.5, 0.5), PART_ARMOUR, Vector2(0.5, 0.03), head_only))
		if side > 0.0:
			_quad(ids[0], ids[1], ids[2], ids[3])
		else:
			_quad(ids[0], ids[3], ids[2], ids[1])
	print("helmet: ", (_idx.size() - start) / 3, " triangles, bowl ", centre, " ", radius)


## The transverse crest: a tall red half-ring standing side to side on the
## helmet, the centurion's mark (legionaries' crests, when worn, run front to
## back). Two faces and the outer edge; the inner edge sits in the helmet.
func _add_crest() -> void:
	var radius := _head_box.size * 0.5 + Vector3.ONE * HELMET_CLEARANCE
	var centre := Vector3(0.0, _head_box.end.y - radius.y, _head_box.get_center().z)
	var inner := Vector2(radius.x * 0.95, radius.y * 0.95)
	var outer := Vector2(CREST_HALF_WIDTH, radius.y + CREST_HEIGHT)
	var segs := 16
	var start := _idx.size()
	var head_only := {"Head": 1.0}
	var faces := []  # per side: first vertex of the 2 x (segs + 1) grid
	for side in [1.0, -1.0]:
		var first := _v.size()
		for ring in 2:
			var e: Vector2 = outer if ring == 0 else inner
			for s in segs + 1:
				var a := PI * s / segs
				var p := centre + Vector3(e.x * cos(a), e.y * sin(a), side * CREST_THICKNESS * 0.5)
				var uv := RED_LINEN.position + RED_LINEN.size * Vector2(float(s) / segs, 0.2 + 0.6 * ring)
				_vertex(p, Vector3(0, 0, side), uv, PART_CLOTH, Vector2(0.5, 0.0), head_only)
		faces.append(first)
		_grid(first, 2, segs + 1, side < 0.0)
	# The outer edge, joining the two faces' outer rings.
	var edge := _v.size()
	for s in segs + 1:
		var a := PI * s / segs
		for side in [1.0, -1.0]:
			var p := centre + Vector3(outer.x * cos(a), outer.y * sin(a), side * CREST_THICKNESS * 0.5)
			var uv := RED_LINEN.position + RED_LINEN.size * Vector2(float(s) / segs, 0.1 if side > 0.0 else 0.15)
			_vertex(p, Vector3(cos(a), sin(a), 0.0), uv, PART_CLOTH, Vector2(0.5, 0.0), head_only)
	for s in segs:
		var a0 := edge + s * 2
		_quad(a0, a0 + 2, a0 + 3, a0 + 1)
	print("crest: ", (_idx.size() - start) / 3, " triangles")


## Phalerae: three gold discs on the front of the chest armour (decorations
## for valour), in the armour's gold trim colour.
func _add_phalerae() -> void:
	var start := _idx.size()
	var chest := {"spine_03": 1.0}
	for spot in [Vector2(-0.07, 1.36), Vector2(0.07, 1.36), Vector2(0.0, 1.27)]:
		var z := _surface_z(spot.x, spot.y, false) + 0.008  # the plates are in the profile
		var centre := Vector3(spot.x, spot.y, z)
		var middle := _vertex(centre + Vector3(0, 0, 0.006), Vector3.BACK, Vector2(0.5, 0.5), PART_ARMOUR, Vector2(0.5, 0.03), chest)
		var ring := _v.size()
		var segs := 10
		for s in segs:
			var a := TAU * s / segs
			_vertex(centre + Vector3(cos(a), sin(a), 0.0) * 0.032, Vector3(cos(a), sin(a), 2.0), Vector2(0.5, 0.5),
				PART_ARMOUR, Vector2(0.5, 0.03), chest)
		for s in segs:
			_idx.append_array(PackedInt32Array([middle, ring + (s + 1) % segs, ring + s]))
	print("phalerae: ", (_idx.size() - start) / 3, " triangles")


## The cloak: a grid from the shoulders down the back to above the knee,
## standing off the clothes (more towards the hem), wider at the hem. Each row
## is skinned to the bones at its height (clavicles and upper spine at the
## top, down to the pelvis), so it follows the body. Both sides are drawn.
func _add_cloak() -> void:
	var start := _idx.size()
	var outer := _v.size()
	for r in CLOAK_ROWS:
		var f := float(r) / (CLOAK_ROWS - 1)
		for c in CLOAK_COLUMNS + 1:
			var u := float(c) / CLOAK_COLUMNS
			var x := lerpf(-0.2, 0.2, u) * (1.0 + 0.3 * f)
			var y_here := lerpf(_cloak_top(lerpf(-0.2, 0.2, u)), CLOAK_HEM, f)
			var z := _surface_z(x, y_here, true) - CLOAK_CLEARANCE - CLOAK_FLARE * pow(f, 1.4)
			var p := Vector3(x, y_here, z)
			var uv := RED_LINEN.position + RED_LINEN.size * Vector2(u, f)
			_vertex(p, Vector3(0.0, 0.15, -1.0), uv, PART_CLOTH, Vector2(0.5, 0.0), _cloak_bones(x, y_here))
	if OS.get_environment("CLOAK_DEBUG") == "1":
		for r in CLOAK_ROWS:
			var i := outer + r * (CLOAK_COLUMNS + 1) + CLOAK_COLUMNS / 2
			print("cloak row ", r, " y %.3f z %.3f  clothes back z %.3f" % [_v[i].y, _v[i].z, _surface_z(_v[i].x, _v[i].y, true)])
	# The outside faces back (-z); the inside, a copy just inward, faces the body.
	_grid(outer, CLOAK_ROWS, CLOAK_COLUMNS + 1, true)
	var inner := _v.size()
	for i in CLOAK_ROWS * (CLOAK_COLUMNS + 1):
		var src := outer + i
		var bones := {}
		for c in 4:
			if _w[src * 4 + c] > 0.0:
				bones[_skin.get_bind_name(_b[src * 4 + c])] = _w[src * 4 + c]
		_vertex(_v[src] + Vector3(0, 0, 0.004), Vector3(0.0, -0.15, 1.0), _uv[src], PART_CLOTH, Vector2(0.5, 0.0), bones)
	_grid(inner, CLOAK_ROWS, CLOAK_COLUMNS + 1, false)
	print("cloak: ", (_idx.size() - start) / 3, " triangles")


## The cloak's top edge at x: across the shoulders, sloping down to the sides.
func _cloak_top(x: float) -> float:
	return CLOAK_TOP - 0.05 * pow(clampf(absf(x) / 0.2, 0.0, 1.0), 2.0)


## The bones a point of the cloak follows, by its height (and side, at the top).
func _cloak_bones(x: float, y: float) -> Dictionary:
	# Long, gradual blends down the back: the cloth bends smoothly with the
	# spine instead of folding at one height (the plates under it are left out).
	var spine := [["spine_03", 1.32], ["spine_02", 1.14], ["spine_01", 1.0], ["pelvis", 0.86]]
	var bones := {}
	if y >= spine[0][1]:
		var shoulder := clampf(absf(x) / 0.2, 0.0, 1.0) * 0.5
		bones["spine_03"] = 1.0 - shoulder
		if shoulder > 0.0:
			bones["clavicle_l" if x > 0.0 else "clavicle_r"] = shoulder
		return bones
	for k in spine.size() - 1:
		var hi: float = spine[k][1]
		var lo: float = spine[k + 1][1]
		if y >= lo:
			var t := (hi - y) / (hi - lo)
			bones[spine[k][0]] = 1.0 - t
			bones[spine[k + 1][0]] = t
			return bones
	return {"pelvis": 1.0}


# ---------- Scene ----------

func _save_scene(outfit: Node, merged: Array, library_scene: Node) -> void:
	var root_node := Node3D.new()
	root_node.name = "Centurion"
	var armature: Node3D = outfit.get_node("Armature")
	armature.owner = null
	var skeleton: Skeleton3D = armature.get_node("Skeleton3D")
	for c in skeleton.get_children():
		skeleton.remove_child(c)
		c.free()
	armature.get_parent().remove_child(armature)
	root_node.add_child(armature)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = merged[0]
	body.skin = merged[1]
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	var source: AnimationPlayer = library_scene.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for new_name in ANIMS:
		var from: String = ANIMS[new_name] if source.has_animation(ANIMS[new_name]) else ANIMS[new_name] + "_Loop"
		lib.add_animation(new_name, source.get_animation(from).duplicate(true) as Animation)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root_node.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", lib)
	_own(root_node, root_node)
	var packed := PackedScene.new()
	packed.pack(root_node)
	var err := ResourceSaver.save(packed, OUT + "centurion.scn", ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, "centurion.scn: ", error_string(err))


func _own(node: Node, root_node: Node) -> void:
	for c in node.get_children():
		c.owner = root_node
		_own(c, root_node)
