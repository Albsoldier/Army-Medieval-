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


func _initialize() -> void:
	var dir := OS.get_environment("PACK_DIR")
	if dir == "":
		printerr("Set PACK_DIR to the folder with the Quaternius files.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ranger := _load(dir.path_join("Male_Ranger.gltf"))
	var body := _load(dir.path_join("Superhero_Male_FullBody.gltf"))
	var beard := _load(dir.path_join("Hair_Beard.gltf"))
	var library := _load(dir.path_join("UAL1_Standard.glb"))
	# The parts: [MeshInstance3D, keep only head and neck?]
	var parts := []
	for mi in ranger.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, false])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, mi.name == "SuperHero_Male"])  # eyes and eyebrows whole, the body cut to the head
	for mi in beard.find_children("*", "MeshInstance3D", true, false):
		parts.append([mi, false])
	_build_atlases(parts)
	var merged := _merge(parts)
	_save_scene(ranger, merged, library)
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

## [ArrayMesh with LODs, Skin]: every part in one surface; UVs moved into the atlas.
func _merge(parts: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var skin := Skin.new()
	var bind_index := {}  # "bone|pose" -> bind
	for part in parts:
		var mi: MeshInstance3D = part[0]
		var head_only: bool = part[1]
		# This part's binds, by bone name, merged with the identical ones of the
		# parts before (every part is bound to the same skeleton): ~65 binds, not 65 per part.
		var part_skel := mi.get_node(mi.skeleton) as Skeleton3D
		var bind_names := []
		var bind_map := []
		for b in mi.skin.get_bind_count():
			var bone_name := mi.skin.get_bind_name(b)
			if bone_name == "":
				bone_name = part_skel.get_bone_name(mi.skin.get_bind_bone(b))
			bind_names.append(bone_name)
			var key := "%s|%s" % [bone_name, mi.skin.get_bind_pose(b)]
			if not bind_index.has(key):
				bind_index[key] = skin.get_bind_count()
				skin.add_named_bind(bone_name, mi.skin.get_bind_pose(b))
			bind_map.append(bind_index[key])
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var r: Rect2 = REGIONS[mat.resource_name]
			var a := mi.mesh.surface_get_arrays(s)
			var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var pt: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			var pu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var pb: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var pw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			# Which triangles to keep (head only: all three corners mostly on the head or neck).
			var keep_vertex := []
			keep_vertex.resize(pv.size())
			for i in pv.size():
				var best := 0
				for k in 4:
					if pw[i * 4 + k] > pw[i * 4 + best]:
						best = k
				keep_vertex[i] = not head_only or bind_names[pb[i * 4 + best]] in HEAD_BONES
			var remap := {}
			var kept := 0
			for t in range(0, pi.size(), 3):
				if not (keep_vertex[pi[t]] and keep_vertex[pi[t + 1]] and keep_vertex[pi[t + 2]]):
					continue
				for k in 3:
					var i := pi[t + k]
					if not remap.has(i):
						remap[i] = verts.size()
						verts.append(pv[i])
						normals.append(pn[i])
						for c in 4:
							tangents.append(pt[i * 4 + c])
						var u := Vector2(fposmod(pu[i].x, 1.0), fposmod(pu[i].y, 1.0)) if mat.resource_name == "MI_Eyes" else pu[i]
						uvs.append(r.position + u * r.size)
						for c in 4:
							bones.append(bind_map[pb[i * 4 + c]])
							weights.append(pw[i * 4 + c])
					indices.append(remap[i])
				kept += 1
			print("part: ", mi.name, "/", s, " ", kept, " of ", pi.size() / 3, " triangles")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _material(), "Body")
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	print("merged: ", indices.size() / 3, " triangles, ", verts.size(), " vertices, ", skin.get_bind_count(), " binds, LODs ", im.get_surface_lod_count(0))
	return [mesh, skin]


## One material for the whole character: the atlas, its normal map and its
## roughness (G) and metal (B). Textures are set once they've been imported.
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Player_Atlas"
	if ResourceLoader.exists(OUT + "player_colour.png"):
		m.albedo_texture = load(OUT + "player_colour.png")
		m.normal_enabled = true
		m.normal_texture = load(OUT + "player_normal.png")
		m.roughness_texture = load(OUT + "player_orm.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = load(OUT + "player_orm.png")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
		m.roughness = 1.0
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
