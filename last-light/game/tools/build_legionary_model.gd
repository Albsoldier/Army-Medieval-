## Builds the standard Legionary's body (phase 4D, GRAPHICS_PHASE_4D_LEGIONARY.md)
## into models/soldiers/, from the same CC0 Quaternius kits as the player's
## ranger, so the two look alike and share one skeleton and animation set:
##   - the Male Peasant outfit (Modular Character Outfits - Fantasy): linen
##     tunic, forearm wraps, belt, trousers, laced boots; the tunic dyed legion
##     red at build time (its shading kept);
##   - iron plates over the chest, back and shoulders (a lorica segmentata),
##     made like the ranger's armour shell: the tunic's own triangles, moved out
##     along their normals, skinned with the body, drawn as plates by the shader;
##   - the head, eyes and eyebrows of Superhero_Male_FullBody and cropped hair
##     (Universal Base Characters);
##   - five animations from the Universal Animation Library, under the names
##     soldier.gd already asks for (Idle, Walk, Run, Sword_Slash, Death).
## Built for crowds: every part is simplified (Godot's own mesh simplifier) to
## about 6.5k triangles, less than the old adventurer's 10k; one skinned
## surface, one material (shaders/character_atlas.gdshader) with a small atlas
## shared by every legionary; Godot's mesh LODs for distant soldiers.
## Run it twice, importing in between (the second run points the material at
## the imported textures):
##   PACK_DIR=<folder with the extracted .gltf/.glb, .bin and .png files> \
##     godot --headless --path last-light/game --script res://tools/build_legionary_model.gd
##   godot --headless --path last-light/game --import   (then run the tool again)
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
## Small: a soldier is rarely more than a few dozen pixels tall on screen.
const COLOUR_SIZE := Vector2i(512, 256)
const DETAIL_SIZE := Vector2i(256, 128)  # normal and roughness/metal maps
const HAIR_TINT := Color(0.2, 0.15, 0.11)  # dark brown cropped hair
## Legion red, the colour the old legionary's tunic was tinted (soldier.gd).
const TUNIC_RED := Color("8b2e2e")
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
	_build_atlases(parts)
	_merge(parts)
	_add_armour(outfit.find_child("Male_Peasant_Body", true, false))
	_save_scene(outfit, _finish(), library)
	quit()


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "can't read " + path)
	return doc.generate_scene(state)


# ---------- Textures ----------

func _build_atlases(parts: Array) -> void:
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
			var size := Vector2i(int(r.size.x * COLOUR_SIZE.x), int(r.size.y * COLOUR_SIZE.y))
			albedo.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
			if mat.resource_name == "MI_Hair_1":
				_tint(albedo, HAIR_TINT * 1.6)
			elif mat.resource_name == "MI_Peasant":
				_dye_linen(albedo)
			colour.blit_rect(albedo, Rect2i(Vector2i.ZERO, size), Vector2i(int(r.position.x * COLOUR_SIZE.x), int(r.position.y * COLOUR_SIZE.y)))
			if mat.normal_enabled and mat.normal_texture:
				_blit(normal, _image(mat.normal_texture), r)
			var rough_img := _image(mat.roughness_texture) if mat.roughness_texture else null
			var metal_img := _image(mat.metallic_texture) if mat.metallic_texture else null
			var dsize := Vector2i(int(r.size.x * DETAIL_SIZE.x), int(r.size.y * DETAIL_SIZE.y))
			var region := Image.create(dsize.x, dsize.y, false, Image.FORMAT_RGBA8)
			if rough_img:
				rough_img.resize(dsize.x, dsize.y, Image.INTERPOLATE_LANCZOS)
			if metal_img:
				metal_img.resize(dsize.x, dsize.y, Image.INTERPOLATE_LANCZOS)
			for y in dsize.y:
				for x in dsize.x:
					var rough := _channel(rough_img.get_pixel(x, y), mat.roughness_texture_channel) if rough_img else mat.roughness
					var metal := _channel(metal_img.get_pixel(x, y), mat.metallic_texture_channel) if metal_img else mat.metallic
					region.set_pixel(x, y, Color(1.0, rough, metal))
			orm.blit_rect(region, Rect2i(Vector2i.ZERO, dsize), Vector2i(int(r.position.x * DETAIL_SIZE.x), int(r.position.y * DETAIL_SIZE.y)))
			print("atlas: ", mat.resource_name, " -> ", r)
	colour.save_png(ProjectSettings.globalize_path(OUT + "legionary_colour.png"))
	normal.save_png(ProjectSettings.globalize_path(OUT + "legionary_normal.png"))
	orm.save_png(ProjectSettings.globalize_path(OUT + "legionary_orm.png"))


## The peasant's undyed linen (light, unsaturated) becomes legion red, keeping
## its folds and shading: each texel is red scaled by its brightness relative
## to the linen's average. Leather, belts, trousers and boots are untouched.
func _dye_linen(img: Image) -> void:
	var total := 0.0
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if _is_linen(c):
				total += c.get_luminance()
				count += 1
	var mean := total / maxf(count, 1)
	var dyed := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if _is_linen(c):
				var k := clampf(c.get_luminance() / mean, 0.4, 1.4)
				img.set_pixel(x, y, Color(TUNIC_RED.r * k, TUNIC_RED.g * k, TUNIC_RED.b * k, c.a))
				dyed += 1
	print("dyed ", dyed, " linen texels of ", img.get_width() * img.get_height())


func _is_linen(c: Color) -> bool:
	return c.v > 0.5 and c.s < 0.32


func _tint(img: Image, tint: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))


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
		var kept := _append(a, binds, REGIONS[mat.resource_name], tri_part, ARMOUR_OFFSET, plate)
		_counts["armour"] = [0, kept]
		print("armour: ", kept, " triangles, ", lo, " .. ", hi)


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


## One material for every legionary: the shared character shader with this
## model's atlas. Textures are set once they've been imported.
func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "Legionary_Atlas"
	m.shader = load("res://shaders/character_atlas.gdshader")
	if ResourceLoader.exists(OUT + "legionary_colour.png"):
		m.set_shader_parameter("albedo_tex", load(OUT + "legionary_colour.png"))
		m.set_shader_parameter("normal_tex", load(OUT + "legionary_normal.png"))
		m.set_shader_parameter("orm_tex", load(OUT + "legionary_orm.png"))
	else:
		print("(atlas not imported yet: run --import, then this tool again)")
	return m


# ---------- Scene ----------

func _save_scene(outfit: Node, merged: Array, library_scene: Node) -> void:
	var root_node := Node3D.new()
	root_node.name = "Legionary"
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
	var err := ResourceSaver.save(packed, OUT + "legionary.scn", ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, "legionary.scn: ", error_string(err))


func _own(node: Node, root_node: Node) -> void:
	for c in node.get_children():
		c.owner = root_node
		_own(c, root_node)
