## An animated character loaded from a rigged glTF model (see models/CREDITS.md).
## Sizes the model from its skeleton, maps game actions ("run", "death", ...)
## to the model's own animation names, and can recolour or flash it.
extends Node3D

const LOOPING := ["idle", "walk", "run"]

var anim: AnimationPlayer
var skeleton: Skeleton3D
var _model: Node3D
var _meshes: Array = []
var _actions: Dictionary = {}  # action -> animation name in the model
var _current := ""
var _oneshot := 0.0
var _flash_mat: StandardMaterial3D
var _flashing := false


## scene: the imported model. target: wanted height in metres (or length, when
## measure_length is true). actions: action -> list of animation-name endings to
## look for. recolor: material name -> {"color": Color, "emission": float}.
func build(scene: PackedScene, target: float, measure_length: bool, actions: Dictionary,
		recolor: Dictionary = {}) -> void:
	_model = scene.instantiate()
	add_child(_model)
	anim = _find(_model, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_fit(target, measure_length)
	_map_actions(actions)
	_recolor(recolor)

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
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return null
	var follower := BoneAttachment3D.new()
	follower.bone_name = bone
	skeleton.add_child(follower)
	return follower


func _find(root: Node, type_name: String) -> Node:
	var found := root.find_children("*", type_name, true, false)
	return found[0] if found.size() > 0 else null


func _fit(target: float, measure_length: bool) -> void:
	if skeleton == null:
		return
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
