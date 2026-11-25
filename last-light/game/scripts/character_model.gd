## An animated character loaded from a rigged glTF model (see models/CREDITS.md).
## Sizes the model from its skeleton, maps game actions ("run", "death", ...)
## to the model's own animation names, and can recolour or flash it.
extends Node3D

const LOOPING := ["idle", "walk", "run"]
## Other names for a bone in other rigs (the humanoid rig of the player's
## ranger model, phase 4C), tried in order when a model lacks the first name.
const BONE_ALIASES := {"Palm.R": ["Wrist.R", "hand_r"], "Palm.L": ["Wrist.L", "hand_l"],
	"Torso": ["spine_01"], "Neck": ["neck_01"]}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var _model: Node3D
var _meshes: Array = []
var _actions: Dictionary = {}  # action -> animation name in the model
var _current := ""
var _oneshot := 0.0
var _flash_mat: StandardMaterial3D
var _flashing := false
var merged := false  # the model is one skinned surface (merged here, or ahead of time)

## Merged meshes and skins, shared by every character with the same model and colours.
static var _merged_cache: Dictionary = {}
static var _merged_mat: ShaderMaterial


## scene: the imported model. target: wanted height in metres (or length, when
## measure_length is true). actions: action -> list of animation-name endings to
## look for. recolor: material name -> {"color": Color, "emission": float}.
func build(scene: PackedScene, target: float, measure_length: bool, actions: Dictionary,
		recolor: Dictionary = {}, merge: bool = true) -> void:
	_model = scene.instantiate()
	add_child(_model)
	anim = _find(_model, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_fit(target, measure_length)
	_map_actions(actions)
	_recolor(recolor)
	_enhance()
	if merge:
		merged = _merge_meshes(scene.resource_path)
	if not merged and _meshes.size() == 1 and (_meshes[0] as MeshInstance3D).skin != null \
			and (_meshes[0] as MeshInstance3D).mesh.get_surface_count() == 1:
		merged = true  # merged ahead of time (the player's ranger, tools/build_player_model.gd)

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.45)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func has_action(action: String) -> bool:
	return _actions.has(action)


## Plays a looping or held animation. Does nothing while a one-shot is playing.
func play(action: String, speed: float = 1.0) -> void:
	if anim == null or _oneshot > 0.0 or not _actions.has(action):
		return
	var anim_name: String = _actions[action]
	anim.speed_scale = speed
	if anim_name != _current:
		_current = anim_name
		anim.play(anim_name, 0.2)


## Plays an animation once (an attack, a death). Returns its length in seconds.
func play_once(action: String, speed: float = 1.0) -> float:
	if anim == null or not _actions.has(action):
		return 0.0
	var anim_name: String = _actions[action]
	_current = anim_name
	anim.speed_scale = speed
	anim.play(anim_name, 0.1)
	anim.seek(0.0, true)
	_oneshot = anim.get_animation(anim_name).length / maxf(speed, 0.01)
	return _oneshot


func tick(delta: float) -> void:
	_oneshot = maxf(_oneshot - delta, 0.0)


func flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for mi in _meshes:
		(mi as MeshInstance3D).material_overlay = _flash_mat if on else null


## A node that follows a bone, e.g. a hand. Returns null if the bone is missing.
func bone_follower(bone: String) -> Node3D:
	if skeleton == null:
		return null
	# Models name their bones differently: the adventurer's names first, then
	# the stand-ins other models use (Wrist for Palm; the humanoid rig's names).
	for name in [bone] + BONE_ALIASES.get(bone, []):
		if skeleton.find_bone(name) >= 0:
			bone = name
			break
	if skeleton.find_bone(bone) < 0:
		return null
	var follower := BoneAttachment3D.new()
	follower.bone_name = bone
	skeleton.add_child(follower)
	return follower


func _find(root: Node, type_name: String) -> Node:
	var found := root.find_children("*", type_name, true, false)
	return found[0] if found.size() > 0 else null


func _fit(target: float, measure_length: bool) -> void:
	if skeleton == null or target <= 0.0:
		return  # a target of 0 keeps the model's own size (it's already in metres)
	# Bone rest positions in the model's own space.
	var to_model := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != null and node != _model:
		to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skeleton.get_bone_count():
		var p := to_model * skeleton.get_bone_global_rest(i).origin
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var extent := hi - lo
	var measured := maxf(extent.x, extent.z) if measure_length else extent.y
	if measured <= 0.0001:
		return
	var s := target / measured
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(-(lo.x + hi.x) * 0.5 * s, -lo.y * s, -(lo.z + hi.z) * 0.5 * s)


func _map_actions(actions: Dictionary) -> void:
	if anim == null:
		return
	var names := anim.get_animation_list()
	for action in actions:
		for ending in actions[action]:
			for anim_name in names:
				if str(anim_name).to_lower().ends_with(str(ending).to_lower()):
					_actions[action] = anim_name
					break
			if _actions.has(action):
				break
		if _actions.has(action) and action in LOOPING:
			anim.get_animation(_actions[action]).loop_mode = Animation.LOOP_LINEAR


func _recolor(recolor: Dictionary) -> void:
	if recolor.is_empty():
		return
	for mi in _meshes:
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(s) as BaseMaterial3D
			if mat == null or not recolor.has(mat.resource_name):
				continue
			var spec: Dictionary = recolor[mat.resource_name]
			var copy := mat.duplicate() as BaseMaterial3D
			copy.albedo_color = spec.get("color", copy.albedo_color)
			if spec.has("emission"):
				copy.emission_enabled = true
				copy.emission = copy.albedo_color
				copy.emission_energy_multiplier = float(spec["emission"])
			mesh_instance.set_surface_override_material(s, copy)


## Merges all the model's meshes and materials into one skinned surface drawn
## with one shared shader (character.gdshader): one draw call instead of one
## per surface (15 for the adventurer). Every vertex keeps its old material's
## colour, roughness, metallic, specular and rim, and its bone weights; each
## part keeps its own bind poses (the skins are joined, bones re-numbered), so
## animation is unchanged. Returns false, changing nothing, for a model this
## can't express (textures, glow, transparency, unlike skins).
func _merge_meshes(path: String) -> bool:
	if skeleton == null:
		return false
	# Only skinned meshes are merged; anything else (a sword on a bone) stays as it is.
	var skinned := _meshes.filter(func(mi): return (mi as MeshInstance3D).skin != null)
	var others := _meshes.filter(func(mi): return (mi as MeshInstance3D).skin == null)
	if skinned.size() < 1:
		return false
	var first := skinned[0] as MeshInstance3D
	var key := path
	for mi in skinned:
		var m := mi as MeshInstance3D
		if m.skin == null or m.mesh == null or m.skeleton != first.skeleton or m.get_parent() != first.get_parent() \
				or not m.transform.is_equal_approx(first.transform) or m.mesh.get_blend_shape_count() > 0:
			return false
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture != null or mat.emission_enabled or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or mat.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or mat.cull_mode != BaseMaterial3D.CULL_BACK \
					or mat.vertex_color_use_as_albedo:
				return false
			key += "|%s %s %s %s %s %s" % [mat.albedo_color.to_html(), mat.roughness, mat.metallic, mat.metallic_specular,
				mat.rim if mat.rim_enabled else 0.0, mat.rim_tint]
	if not _merged_cache.has(key):
		_merged_cache[key] = _build_merged(skinned)
	var built: Array = _merged_cache[key]
	var one := MeshInstance3D.new()
	one.name = "Merged"
	one.mesh = built[0]
	one.skin = built[1]
	one.transform = first.transform
	one.cast_shadow = first.cast_shadow
	if _merged_mat == null:
		_merged_mat = ShaderMaterial.new()
		_merged_mat.shader = preload("res://shaders/character.gdshader")
	one.material_override = _merged_mat
	var parent := first.get_parent()
	parent.add_child(one)
	one.skeleton = one.get_path_to(skeleton)
	for mi in skinned:
		parent.remove_child(mi)
		(mi as Node).queue_free()
	_meshes = [one] + others
	return true


## [ArrayMesh, Skin]: every surface of every mesh in one, with the material
## values in the vertices and the bone indices moved past the earlier meshes' binds.
func _build_merged(skinned: Array) -> Array:
	var eight := false
	for mi in skinned:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			eight = eight or ((mi as MeshInstance3D).mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0
	var per := 8 if eight else 4
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var skin := Skin.new()
	for mi in skinned:
		var m := mi as MeshInstance3D
		var base := skin.get_bind_count()
		for b in m.skin.get_bind_count():
			var bind_name := m.skin.get_bind_name(b)
			if bind_name != "":
				skin.add_named_bind(bind_name, m.skin.get_bind_pose(b))
			else:
				skin.add_bind(m.skin.get_bind_bone(b), m.skin.get_bind_pose(b))
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			var colour := Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.roughness)
			var uv := Vector2(mat.metallic, mat.metallic_specular)
			var uv2 := Vector2(mat.rim if mat.rim_enabled else 0.0, mat.rim_tint)
			var arrays := m.mesh.surface_get_arrays(s)
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var pb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var pw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var their := pb.size() / maxi(pv.size(), 1)  # bones per vertex in this surface
			var first := verts.size()
			verts.append_array(pv)
			normals.append_array(pn)
			for i in pv.size():
				colors.append(colour)
				uvs.append(uv)
				uv2s.append(uv2)
				for k in per:
					if k < their:
						bones.append(pb[i * their + k] + base)
						weights.append(pw[i * their + k])
					else:
						bones.append(0)
						weights.append(0.0)
			for i in pi:
				indices.append(first + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_TEX_UV2] = uv2s
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight else 0)
	return [mesh, skin]


## Gives every material a more natural finish: soft rim light on skin, hair
## and fur (which reads as fuzz and subsurface light), and shiny metal.
func _enhance() -> void:
	for mi in _meshes:
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var own := mesh_instance.get_surface_override_material(s) as BaseMaterial3D
			var m: BaseMaterial3D = own if own != null else mat.duplicate() as BaseMaterial3D
			var label := mat.resource_name.to_lower()
			m.metallic_specular = 0.35
			m.roughness = 0.85
			m.rim_enabled = true
			m.rim = 0.18
			m.rim_tint = 0.6
			if "skin" in label:
				m.roughness = 0.62
				m.rim = 0.32
				m.rim_tint = 0.85
				m.metallic_specular = 0.45
			elif "hair" in label or "eyebrow" in label:
				m.roughness = 0.5
				m.rim = 0.25
			elif "metal" in label or "gold" in label or "grey" in label:
				m.metallic = 0.75
				m.roughness = 0.34
				m.rim = 0.1
			elif "eye" in label or "pupil" in label:
				m.roughness = 0.2
				m.metallic_specular = 0.8
				m.rim_enabled = false
			elif "main" in label or "fur" in label:
				m.roughness = 0.95
				m.rim = 0.45  # fur catches the light at the edges
				m.rim_tint = 0.75
			elif "hoof" in label or "hooves" in label or "nose" in label:
				m.roughness = 0.45
			mesh_instance.set_surface_override_material(s, m)
