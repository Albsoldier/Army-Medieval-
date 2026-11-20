## The survivor: position, survival stats, inventory and the 3D model.
## `pos` is the position on the game grid (pixels); the model follows it.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

const SPEED := 95.0
const TORCH_RADIUS := 85.0

var world: World
var pos := Vector2.ZERO
var health := 100.0
var hunger := 100.0
var warmth := 100.0
var sanity := 100.0
var inventory := {"wood": 0, "stone": 0, "berries": 0, "raw_meat": 0, "cooked_meat": 0,
	"smoked_meat": 0, "ore": 0, "iron": 0, "hide": 0, "salve": 0}
var has_spear := false
var iron_spear := false
var has_axe := false
var has_pickaxe := false
var armour := false
var lantern := false
## What's in your hand: "hands", "spear", "axe" or "pickaxe" (the hotbar).
var equipped := "hands"
var armour_on := true  # armour can be taken off in the inventory
var lantern_on := true  # and the lantern shuttered
var torch_time := 0.0
var first_person := false  # set with set_first_person()
var facing := Vector2.DOWN
var hurt_flash := 0.0
var swing_time := 0.0

const CharacterModel = preload("res://scripts/character_model.gd")
const SURVIVOR := preload("res://models/survivor.glb")

var dead := false
var _model: Node3D  # turns to face the walking direction
var _body: CharacterModel
var _right_hand: Node3D
var _left_hand: Node3D
var _spear: Node3D
var _axe: Node3D
var _pickaxe: Node3D
var _armour: Node3D
var _torso: Node3D
var _fp_swing := 0.0  # first-person swing animation, counts down from 1
var _bob := 0.0
var _neck: Node3D
var _torch: Node3D
var _torch_light: OmniLight3D
var _moving := false
var _moving_last := false
var _lantern: Node3D


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(SURVIVOR, 1.62, false, {
		"idle": ["Man_Idle"],
		"walk": ["Man_Walk"],
		"run": ["Man_Run"],
		"punch": ["Man_Punch"],
		"slash": ["Man_SwordSlash"],
		"death": ["Man_Death"],
	}, {"Shirt": {"color": Color("3b4f35")}})  # a dark green field jacket
	_right_hand = _body.bone_follower("Palm.R")
	_left_hand = _body.bone_follower("Palm.L")
	_torso = _body.bone_follower("Torso")
	_neck = _body.bone_follower("Neck")

	# Spear and torch follow the hands but keep their own size and direction.
	_spear = Node3D.new()
	_spear.top_level = true
	add_child(_spear)
	Art.part(_spear, Art.cylinder(0.022, 0.022, 1.6, 5), Color("caa472"), Vector3(0, 0.3, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.2, 5), Color("c9ccd1"), Vector3(0, 1.2, 0))
	_spear.visible = false

	# The axe: a short haft with an iron head on one side.
	_axe = Node3D.new()
	_axe.top_level = true
	add_child(_axe)
	Art.part(_axe, Art.cylinder(0.03, 0.03, 0.85, 6), Color("a07548"), Vector3(0, 0.3, 0))
	Art.part(_axe, Art.box(Vector3(0.06, 0.22, 0.28)), Color("c4c8ce"), Vector3(0, 0.62, 0.13))
	_axe.visible = false

	# The pickaxe: a haft with a curved iron head across the top.
	_pickaxe = Node3D.new()
	_pickaxe.top_level = true
	add_child(_pickaxe)
	Art.part(_pickaxe, Art.cylinder(0.03, 0.03, 0.85, 6), Color("8f6640"), Vector3(0, 0.3, 0))
	Art.part(_pickaxe, Art.box(Vector3(0.07, 0.08, 0.62)), Color("b9bdc3"), Vector3(0, 0.7, 0))
	_pickaxe.visible = false

	# Worn iron armour: a breastplate and shoulder guards that follow the chest.
	_armour = Node3D.new()
	_armour.top_level = true
	add_child(_armour)
	Art.part(_armour, Art.box(Vector3(0.3, 0.26, 0.08)), Color("7d8186"), Vector3(0, 0, 0.1))
	Art.part(_armour, Art.box(Vector3(0.3, 0.26, 0.06)), Color("6a6e73"), Vector3(0, 0, -0.1))
	Art.part(_armour, Art.box(Vector3(0.12, 0.05, 0.2)), Color("8c9095"), Vector3(0.19, 0.14, 0))
	Art.part(_armour, Art.box(Vector3(0.12, 0.05, 0.2)), Color("8c9095"), Vector3(-0.19, 0.14, 0))
	_armour.visible = false

	_torch = Node3D.new()
	_torch.top_level = true
	add_child(_torch)
	Art.part(_torch, Art.cylinder(0.03, 0.025, 0.55, 5), Color("6b4a2b"), Vector3(0, 0.12, 0))
	Art.part(_torch, Art.sphere(0.08, 3, 6), Color(1.0, 0.65, 0.2), Vector3(0, 0.44, 0), Vector3.ZERO, 4.0, true)
	_torch_light = Art.omni(Color(1.0, 0.72, 0.4), TORCH_RADIUS / World.TILE * 1.3, 2.2)
	_torch_light.position = Vector3(0, 0.6, 0)
	_torch.add_child(_torch_light)
	_torch.visible = false

	# The lantern hangs at the hip and lights the way for good.
	_lantern = Node3D.new()
	_lantern.position = Vector3(-0.2, 0.75, 0.15)
	_model.add_child(_lantern)
	Art.part(_lantern, Art.box(Vector3(0.12, 0.16, 0.12)), Color(1.0, 0.8, 0.4), Vector3.ZERO, Vector3.ZERO, 3.0, true)
	Art.part(_lantern, Art.cylinder(0.08, 0.08, 0.03, 6), Color("2e2e30"), Vector3(0, 0.1, 0))
	var lantern_light := Art.omni(Color(1.0, 0.82, 0.55), TORCH_RADIUS / World.TILE * 1.1, 1.6)
	lantern_light.position = Vector3(0, 0.6, 0)
	_lantern.add_child(lantern_light)
	_lantern.visible = false

	# A faint glow so you can always see yourself at night.
	var glow := Art.omni(Color(0.6, 0.7, 1.0), 2.6, 0.35)
	glow.position = Vector3(0, 1.9, 0)
	add_child(glow)
	position = world.to_3d(pos)


func move(dir: Vector2, delta: float) -> void:
	_moving = dir != Vector2.ZERO and not dead
	if not _moving:
		return
	facing = dir.normalized()
	var step := facing * SPEED * delta
	var next_x := pos + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		pos = next_x
	var next_y := pos + Vector2(0, step.y)
	if world.is_walkable(next_y):
		pos = next_y


func tick_visuals(delta: float) -> void:
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	swing_time = maxf(swing_time - delta, 0.0)
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 12.0, 1.0))
	_body.tick(delta)
	if not dead:
		_body.play("run" if _moving else "idle")
	_moving_last = _moving
	_moving = false
	_body.flash(hurt_flash > 0.0)

	var turn := Basis(Vector3.UP, _model.rotation.y)
	_lantern.visible = lantern and lantern_on and not dead
	_armour.visible = armour and armour_on and not dead
	_spear.visible = equipped == "spear" and has_spear and not dead
	_axe.visible = equipped == "axe" and has_axe and not dead
	_pickaxe.visible = equipped == "pickaxe" and has_pickaxe and not dead
	if _armour.visible and _torso and _neck:
		_armour.global_transform = Transform3D(turn, _torso.global_position.lerp(_neck.global_position, 0.45))
	if _right_hand:
		if _spear.visible:
			# Held low and pointing forward, tipped slightly up.
			_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.3), _right_hand.global_position)
		for tool in [_axe, _pickaxe]:
			if tool.visible:
				# Held by the end of the haft, head up and a little forward.
				tool.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, 0.5), _right_hand.global_position - turn * Vector3(0, 0.08, 0))
	_torch.visible = torch_time > 0.0 and not dead
	if _torch.visible and _left_hand:
		_torch.global_transform = Transform3D(turn, _left_hand.global_position)
		_torch_light.light_energy = 2.2 + sin(Time.get_ticks_msec() / 90.0) * 0.15


func die() -> void:
	dead = true
	_body.play_once("death")


func count(item: String) -> int:
	return int(inventory.get(item, 0))


func add_item(item: String, amount: int) -> void:
	inventory[item] = count(item) + amount


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < int(cost[item]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for item in cost:
		inventory[item] = count(item) - int(cost[item])


## In first person the body is hidden (it still casts a shadow) and the held
## tool and torch are drawn in front of the camera by place_view_model().
func set_first_person(on: bool) -> void:
	first_person = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = mode


## How far the view bobs up and down while walking, in metres.
func head_bob() -> float:
	return sin(_bob) * 0.035


## First person: puts the held tool at the lower right of the view and the torch
## at the lower left. Called after the camera has moved this frame.
func place_view_model(cam: Camera3D, delta: float) -> void:
	if not first_person or dead:
		return
	_fp_swing = maxf(_fp_swing - delta * 3.5, 0.0)
	if _moving_last:
		_bob += delta * 9.0
	var b := cam.global_transform.basis
	var o := cam.global_transform.origin
	var sway := Vector3(sin(_bob * 0.5) * 0.012, absf(sin(_bob * 0.5)) * 0.012, 0)
	# A swing chops down and forward.
	var chop := sin(_fp_swing * PI) * 1.0
	var hand := o + b * (Vector3(0.3, -0.36, -0.55) + sway + Vector3(-0.08 * chop, -0.06 * chop, -0.1 * chop))
	_armour.visible = false
	if _spear.visible:
		# Held low and pointing ahead; a swing is a thrust.
		var thrust := o + b * (Vector3(0.24, -0.3, -0.35 - 0.35 * chop) + sway)
		_spear.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -PI / 2 + 0.12) * Basis(Vector3.FORWARD, 0.08), thrust)
	for tool in [_axe, _pickaxe]:
		if tool.visible:
			tool.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -0.35 - chop) * Basis(Vector3.FORWARD, 0.25), hand)
	if _torch.visible:
		_torch.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -0.2), o + b * (Vector3(-0.32, -0.42, -0.6) + sway))


func swing() -> void:
	swing_time = 0.15
	_fp_swing = 1.0
	if not dead:
		_body.play_once("punch" if equipped == "hands" else "slash", 1.6)


## Puts a tool in your hand ("hands" puts it away). Returns false if you don't have it.
func equip(tool: String) -> bool:
	if not owns(tool):
		return false
	equipped = tool
	return true


func owns(tool: String) -> bool:
	match tool:
		"hands": return true
		"spear": return has_spear
		"axe": return has_axe
		"pickaxe": return has_pickaxe
	return false


func holding(tool: String) -> bool:
	return equipped == tool and owns(tool)


## Damage a swing does with what's in your hand.
func attack_damage() -> int:
	match equipped:
		"spear": return (3 if iron_spear else 2) if has_spear else 1
		"axe": return 2 if has_axe else 1
	return 1


func attack_reach() -> float:
	return 34.0 if holding("spear") else 24.0


func wearing_armour() -> bool:
	return armour and armour_on


func lantern_lit() -> bool:
	return lantern and lantern_on
