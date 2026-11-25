## Builds the player's character model (phase 4C, GRAPHICS_CHARACTER_PROTOTYPE.md)
## from Quaternius's CC0 character kits, into models/player/:
##   - the Male Ranger outfit (Modular Character Outfits - Fantasy);
##   - the head and eyes of Superhero_Male_FullBody, eyebrows and a beard
##     (Universal Base Characters; only the head and neck: the outfit covers
##     the rest, and the full body would show through);
##   - six animations from the Universal Animation Library, renamed to the
##     names player.gd already asks for (Idle, Walk, Run, Punch_Right,
##     Sword_Slash, Death).
## All of them share one 65-bone humanoid skeleton, so no retargeting is needed.
## Refinement (GRAPHICS_PLAYER_REFINEMENT.md) adds, in the same surface: hair
## for the hood down (Hair_SimpleParted), a fitted armour shell made from the
## tunic's chest, the old adventurer's backpack moved onto this skeleton, and a
## second outfit texture (the kit's beige and brown dye, T_Ranger_3). Each
## vertex is labelled with its part in UV2, and shaders/character_atlas.gdshader
## shows or hides the parts per character (character_appearance.gd). The boots
## and bracers are simplified: small on screen, and the costliest parts.
## Every part is merged into ONE skinned surface with ONE material: the textures
## are packed into one atlas (colour, normal, roughness/metal), and Godot's mesh
## LODs are generated. Run it twice, importing in between (the second run
## points the material at the imported atlas textures):
##   PACK_DIR=<folder with the extracted .gltf/.glb, .bin and .png files> \
##     godot --headless --path last-light/game --script res://tools/build_player_model.gd
##   godot --headless --path last-light/game --import   (then run the tool again)
extends SceneTree

const OUT := "res://models/player/"
const ANIMS := {"Idle": "Idle", "Walk": "Walk", "Run": "Jog_Fwd", "Punch_Right": "Punch_Jab",
	"Sword_Slash": "Sword_Attack", "Death": "Death01"}
## Atlas regions (x, y, w, h as fractions) for each source material.
const REGIONS := {
	"MI_Ranger": Rect2(0.0, 0.0, 0.5, 1.0),
	"MI_Regular_Male": Rect2(0.5, 0.0, 0.25, 0.5),
	"MI_Superhero_Male": Rect2(0.75, 0.0, 0.25, 0.5),
	"MI_Hair_1": Rect2(0.5, 0.5, 0.25, 0.5),
	"MI_Eyes": Rect2(0.75, 0.5, 0.125, 0.25),
}
const COLOUR_SIZE := Vector2i(1024, 512)  # the outfit gets 512 x 512 of it
const DETAIL_SIZE := Vector2i(512, 256)  # normal and roughness/metal maps
const HAIR_TINT := Color(0.36, 0.25, 0.17)  # the base hair texture is grey: a dark brown beard
const HEAD_BONES := ["Head", "neck_01"]
## Parts (UV2.x), as character_atlas.gdshader knows them.
const PART_CLOTH := 0
const PART_SKIN := 1
const PART_HOOD := 2  # drawn with the hood up
const PART_HAIR := 3  # drawn with the hood down
const PART_ARMOUR := 4
const PART_BACKPACK := 5
## Parts simplified (the share of triangles kept at most): small on screen,
## and modelled finely enough to cost far more than they show.
const SIMPLIFY := {"Male_Ranger_Feet_Boots": 0.3, "Male_Ranger_Arms_Bracer": 0.55}
## The tunic triangles that become the armour shell, and how far out it sits.
const ARMOUR_BONES := ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"]
const ARMOUR_OFFSET := 0.014
## How far the backpack presses into the clothes on the back (none showing between).
const BACKPACK_SNUG := 0.015
## The backpack's flat colours, as atlas swatches: [colour (sRGB), roughness, metal].
const SWATCHES := [
	[Color(0.4143, 0.3516, 0.2239), 0.9, 0.0],
	[Color(0.2442, 0.2221, 0.1289), 0.9, 0.0],
	[Color(0.311, 0.2889, 0.1885), 0.9, 0.0],
	[Color(0.5097, 0.4096, 0.1952), 0.4, 0.7],
]
const SWATCH_OF := {"Brown": 0, "Green": 1, "LightGreen": 2, "Gold": 3}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := OS.get_environment("PACK_DIR")
	if dir == "":
		printerr("Set PACK_DIR to the folder with the Quaternius files.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ranger := _load(dir.path_join("Male_Ranger.gltf"))
	var body := _load(dir.path_join("Superhero_Male_FullBody.gltf"))
	var beard := _load(dir.path_join("Hair_Beard.gltf"))
	var hair := _load(dir.path_join("Hair_SimpleParted.gltf"))
	var library := _load(dir.path_join("UAL1_Standard.glb"))
	# The parts: [MeshInstance3D, how its triangles are kept and labelled].
	var parts := []
	for mi in ranger.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "outfit"])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "head" if mi.name == "SuperHero_Male" else "whole"])  # eyes and eyebrows whole, the body cut to the head
	for mi in beard.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "whole"])
	for mi in hair.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, "hair"])
	_build_atlases(parts, dir)
	_merge(parts)
	_add_armour(ranger.find_child("Male_Ranger_Body", true, false))
	await _add_backpack(ranger)
	_save_scene(ranger, _finish(), library)
	quit()


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "can't read " + path)
	return doc.generate_scene(state)


# ---------- Textures ----------

func _build_atlases(parts: Array, dir: String) -> void:
	var colour := Image.create(COLOUR_SIZE.x, COLOUR_SIZE.y, false, Image.FORMAT_RGBA8)
	var normal := Image.create(DETAIL_SIZE.x, DETAIL_SIZE.y, false, Image.FORMAT_RGBA8)
	var orm := Image.create(DETAIL_SIZE.x, DETAIL_SIZE.y, false, Image.FORMAT_RGBA8)
	colour.fill(Color(0.5, 0.5, 0.5))
	normal.fill(Color(0.5, 0.5, 1.0))
	orm.fill(Color(1.0, 0.8, 0.0))
	var done := {}
	for part in parts:
		var mesh: Mesh = (part[0] as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or done.has(mat.resource_name) or not REGIONS.has(mat.resource_name):
				continue
			done[mat.resource_name] = true
			var r: Rect2 = REGIONS[mat.resource_name]
			var albedo := _image(mat.albedo_texture)
			if mat.resource_name == "MI_Hair_1":
				for y in albedo.get_height():
					for x in albedo.get_width():
						var c := albedo.get_pixel(x, y)
						albedo.set_pixel(x, y, Color(c.r * HAIR_TINT.r * 1.6, c.g * HAIR_TINT.g * 1.6, c.b * HAIR_TINT.b * 1.6, c.a))
			_blit(colour, albedo, r)
			if mat.normal_enabled and mat.normal_texture:
				_blit(normal, _image(mat.normal_texture), r)
			# Roughness and metal into G and B, from whichever channels the material reads.
			var rough_img := _image(mat.roughness_texture) if mat.roughness_texture else null
			var metal_img := _image(mat.metallic_texture) if mat.metallic_texture else null
			var size := Vector2i(int(r.size.x * DETAIL_SIZE.x), int(r.size.y * DETAIL_SIZE.y))
			var region := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			if rough_img:
				rough_img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
			if metal_img:
				metal_img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
			for y in size.y:
				for x in size.x:
					var rough := _channel(rough_img.get_pixel(x, y), mat.roughness_texture_channel) if rough_img else mat.roughness
					var metal := _channel(metal_img.get_pixel(x, y), mat.metallic_texture_channel) if metal_img else mat.metallic
					region.set_pixel(x, y, Color(1.0, rough, metal))
			orm.blit_rect(region, Rect2i(Vector2i.ZERO, size), Vector2i(int(r.position.x * DETAIL_SIZE.x), int(r.position.y * DETAIL_SIZE.y)))
			print("atlas: ", mat.resource_name, " -> ", r, " normal ", mat.normal_enabled, " rough ", rough_img != null, " metal ", metal_img != null)
	# Plain colours for the backpack (it had flat materials, not textures).
	for k in SWATCHES.size():
		var sw: Array = SWATCHES[k]
		colour.fill_rect(_swatch_rect(k, COLOUR_SIZE), sw[0])
		orm.fill_rect(_swatch_rect(k, DETAIL_SIZE), Color(1.0, float(sw[1]), float(sw[2])))
	# The second outfit: the same clothing, dyed beige and brown, for the clothing half of the atlas.
	var earth := Image.load_from_file(dir.path_join("T_Ranger_3_BaseColor.png"))
	earth.convert(Image.FORMAT_RGBA8)
	earth.resize(int(REGIONS["MI_Ranger"].size.x * COLOUR_SIZE.x), int(REGIONS["MI_Ranger"].size.y * COLOUR_SIZE.y), Image.INTERPOLATE_LANCZOS)
	earth.save_png(ProjectSettings.globalize_path(OUT + "player_outfit_earth.png"))
	colour.save_png(ProjectSettings.globalize_path(OUT + "player_colour.png"))
	normal.save_png(ProjectSettings.globalize_path(OUT + "player_normal.png"))
	orm.save_png(ProjectSettings.globalize_path(OUT + "player_orm.png"))


func _image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _channel(c: Color, channel: int) -> float:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED: return c.r
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return c.g
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return c.b
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return c.a
	return c.r


func _blit(atlas: Image, src: Image, r: Rect2) -> void:
	var size := Vector2i(int(r.size.x * atlas.get_width()), int(r.size.y * atlas.get_height()))
	var img := src.duplicate() as Image
	img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i(int(r.position.x * atlas.get_width()), int(r.position.y * atlas.get_height())))


# ---------- Geometry ----------

# The merged surface, filled part by part.
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


## This mesh's binds as [bone names, index of the same bind in the merged skin].
## Every part is bound to the same skeleton, so identical binds are shared:
## ~65 binds, not 65 per part.
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


## The bone that moves vertex i most.
func _dominant(names: Array, pb: PackedInt32Array, pw: PackedFloat32Array, i: int) -> String:
	var best := 0
	for k in 4:
		if pw[i * 4 + k] > pw[i * 4 + best]:
			best = k
	return names[pb[i * 4 + best]]


## Adds the triangles of one surface. tri_part[t] is the part of triangle t
## (-1: left out). Vertices are split where parts meet, so that hiding one
## part (collapsing its vertices) never pulls at its neighbours.
## offset moves vertices out along their normals; plate maps a position to
## the armour's (across, height); uv_wrap wraps UVs into 0..1 (the eyes).
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
					_t.append(pt[i * 4 + c])
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


## Every kit part, labelled: clothing, skin, the hood over the head, hair.
func _merge(parts: Array) -> void:
	for part in parts:
		var mi: MeshInstance3D = part[0]
		var mode: String = part[1]
		var binds := _binds(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var r: Rect2 = REGIONS[mat.resource_name]
			var a := mi.mesh.surface_get_arrays(s)
			if SIMPLIFY.has(mi.name):
				a[Mesh.ARRAY_INDEX] = _simplified(a, float(SIMPLIFY[mi.name]), mi.name)
			var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var pw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var skin_mat: bool = mat.resource_name in ["MI_Regular_Male", "MI_Superhero_Male"]
			var tri_part := PackedInt32Array()
			tri_part.resize(pi.size() / 3)
			for t in tri_part.size():
				var on_head := 0
				for k in 3:
					if _dominant(binds[0], pb, pw, pi[t * 3 + k]) in HEAD_BONES:
						on_head += 1
				var label := PART_SKIN if skin_mat else PART_CLOTH
				if mode == "head" and on_head < 3:
					label = -1  # the rest of the full body: the outfit covers it
				elif mode == "hair":
					label = PART_HAIR
				elif mode == "outfit" and mi.name == "Male_Ranger_Head_Hood" and on_head >= 1:
					label = PART_HOOD  # over the head; the part on the shoulders stays
				tri_part[t] = label
			var kept := _append(a, binds, r, tri_part, 0.0, Callable(), mat.resource_name == "MI_Eyes")
			print("part: ", mi.name, "/", s, " ", kept, " of ", tri_part.size(), " triangles")


## The triangles of a simplified version of a surface (Godot's own mesh
## simplifier, as for LODs): the first level with at most `share` of them.
func _simplified(a: Array, share: float, label: String) -> PackedInt32Array:
	var im := ImporterMesh.new()
	var only := []
	only.resize(Mesh.ARRAY_MAX)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		only[k] = a[k]
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, only)
	im.generate_lods(25.0, 60.0, [])
	var full: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for l in im.get_surface_lod_count(0):
		var lod := im.get_surface_lod_indices(0, l)
		if lod.size() <= full.size() * share:
			print("simplified ", label, ": ", full.size() / 3, " -> ", lod.size() / 3, " triangles")
			return lod
	return full


## Armour: a shell over the tunic's chest, back and shoulders, made from the
## tunic's own triangles moved out along their normals, so it is skinned
## exactly like the body under it and follows every animation. The shader
## draws it as plates in the worn armour's colours (instance uniforms).
func _add_armour(body_mi: MeshInstance3D) -> void:
	var binds := _binds(body_mi)
	for s in body_mi.mesh.get_surface_count():
		var mat := body_mi.mesh.surface_get_material(s) as BaseMaterial3D
		var a := body_mi.mesh.surface_get_arrays(s)
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
		var kept := _append(a, binds, REGIONS[mat.resource_name], tri_part, ARMOUR_OFFSET, plate)
		print("armour: ", kept, " triangles, ", lo, " .. ", hi)


## The adventurer's backpack (models/adventurer.glb, the old player model),
## moved onto this skeleton: placed from its old chest bone to this one's
## upper spine, scaled by the two characters' heights, pushed against the
## outfit's back, and bound wholly to spine_03, as it was to the chest.
## Its flat colours point at swatches painted into the atlas.
func _add_backpack(ranger: Node) -> void:
	var adv: Node3D = load("res://models/adventurer.glb").instantiate()
	root.add_child(adv)
	await process_frame
	var ask: Skeleton3D = adv.find_children("*", "Skeleton3D", true, false)[0]
	var rsk: Skeleton3D = ranger.find_children("*", "Skeleton3D", true, false)[0]
	var bone_at := func(sk: Skeleton3D, xf: Transform3D, bone: String) -> Vector3:
		return (xf * sk.get_bone_global_rest(sk.find_bone(bone))).origin
	var scale := float(bone_at.call(rsk, Transform3D(), "Head").y) / float(bone_at.call(ask, ask.global_transform, "Head").y)
	var from: Vector3 = bone_at.call(ask, ask.global_transform, "Chest")
	var to: Vector3 = bone_at.call(rsk, Transform3D(), "spine_03")
	var pack: MeshInstance3D = adv.find_child("Backpack", true, false)
	var src := []  # [positions, normals, indices, swatch] per surface, in the ranger's model space
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s in pack.mesh.get_surface_count():
		var a := pack.mesh.surface_get_arrays(s)
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		for i in pv.size():
			var bind := pb[i * 4]
			var bone := ask.find_bone(pack.skin.get_bind_name(bind)) if pack.skin.get_bind_name(bind) != "" else pack.skin.get_bind_bone(bind)
			var xf: Transform3D = ask.global_transform * ask.get_bone_global_rest(bone) * pack.skin.get_bind_pose(bind)
			var p := to + (xf * pv[i] - from) * scale
			pos.append(p)
			nrm.append((xf.basis * pn[i]).normalized())
			lo = lo.min(p)
			hi = hi.max(p)
		var swatch := SWATCH_OF.get(pack.mesh.surface_get_material(s).resource_name, 0) as int
		src.append([pos, nrm, a[Mesh.ARRAY_INDEX], swatch])
	adv.queue_free()
	# Against the back: the outfit's furthest-back point behind the pack.
	var back := INF
	for mi in ranger.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			for p in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				if absf(p.x) < 0.12 and p.y > lo.y and p.y < hi.y:
					back = minf(back, p.z)
	var shift := Vector3(0, 0, back - hi.z + BACKPACK_SNUG)
	var spine := -1
	for b in _skin.get_bind_count():
		if _skin.get_bind_name(b) == "spine_03":
			spine = b
	assert(spine >= 0, "no spine_03 bind")
	var tris := 0
	for part in src:
		var pos: PackedVector3Array = part[0]
		var nrm: PackedVector3Array = part[1]
		var pi: PackedInt32Array = part[2]
		var base := _v.size()
		var uv := _swatch_uv(int(part[3]))
		for i in pos.size():
			_v.append(pos[i] + shift)
			_n.append(nrm[i])
			var tan := nrm[i].cross(Vector3.UP)
			tan = (tan if tan.length() > 0.01 else Vector3.RIGHT).normalized()
			_t.append_array(PackedFloat32Array([tan.x, tan.y, tan.z, 1.0]))
			_uv.append(uv)
			_uv2.append(Vector2(PART_BACKPACK + 0.5, 0.0))
			_b.append_array(PackedInt32Array([spine, 0, 0, 0]))
			_w.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		for i in pi:
			_idx.append(base + i)
		tris += pi.size() / 3
	print("backpack: ", tris, " triangles, scale ", scale, ", ", lo + shift, " .. ", hi + shift)


func _swatch_rect(k: int, size: Vector2i) -> Rect2i:
	var w := size.x / 16
	return Rect2i(size.x * 3 / 4 + k * w, size.y * 3 / 4, w, size.y / 4)


func _swatch_uv(k: int) -> Vector2:
	return Vector2(0.75 + (k + 0.5) / 16.0, 0.875)


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
	# Not ARRAY_FLAG_COMPRESS_ATTRIBUTES: tried, and it breaks this skinned mesh when animated.
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _material(), "Body")
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	var counts := {}
	for t in range(0, _idx.size(), 3):
		var part := int(_uv2[_idx[t]].x)
		counts[part] = counts.get(part, 0) + 1
	print("merged: ", _idx.size() / 3, " triangles (by part ", counts, "), ", _v.size(), " vertices, ",
		_skin.get_bind_count(), " binds, LODs ", im.get_surface_lod_count(0))
	for l in im.get_surface_lod_count(0):
		print("  LOD ", l, ": ", im.get_surface_lod_indices(0, l).size() / 3, " triangles")
	return [mesh, _skin]


## One material for the whole character (see shaders/character_atlas.gdshader).
## Textures are set once they've been imported.
func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "Player_Atlas"
	m.shader = load("res://shaders/character_atlas.gdshader")
	if ResourceLoader.exists(OUT + "player_colour.png") and ResourceLoader.exists(OUT + "player_outfit_earth.png"):
		m.set_shader_parameter("albedo_tex", load(OUT + "player_colour.png"))
		m.set_shader_parameter("outfit_tex", load(OUT + "player_outfit_earth.png"))
		m.set_shader_parameter("normal_tex", load(OUT + "player_normal.png"))
		m.set_shader_parameter("orm_tex", load(OUT + "player_orm.png"))
	else:
		print("(atlas not imported yet: run --import, then this tool again)")
	return m


# ---------- Scene ----------

func _save_scene(ranger: Node, merged: Array, library_scene: Node) -> void:
	var root := Node3D.new()
	root.name = "Player"
	var armature: Node3D = ranger.get_node("Armature")
	armature.owner = null
	var skeleton: Skeleton3D = armature.get_node("Skeleton3D")
	for c in skeleton.get_children():
		skeleton.remove_child(c)
		c.free()
	armature.get_parent().remove_child(armature)
	root.add_child(armature)
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
		var anim := source.get_animation(from).duplicate(true) as Animation
		lib.add_animation(new_name, anim)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", lib)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT + "ranger.scn", ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, "ranger.scn: ", error_string(err))


func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)
