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
var torch_time := 0.0
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
var _torch: Node3D
var _torch_light: OmniLight3D
var _moving := false
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

	# Spear and torch follow the hands but keep their own size and direction.
	_spear = Node3D.new()
	_spear.top_level = true
	add_child(_spear)
	Art.part(_spear, Art.cylinder(0.022, 0.022, 1.6, 5), Color("caa472"), Vector3(0, 0.3, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.2, 5), Color("c9ccd1"), Vector3(0, 1.2, 0))
	_spear.visible = false

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
	_moving = false
	_body.flash(hurt_flash > 0.0)

	var turn := Basis(Vector3.UP, _model.rotation.y)
	_lantern.visible = lantern and not dead
	_spear.visible = has_spear and not dead
	if _spear.visible and _right_hand:
		# Held low and pointing forward, tipped slightly up.
		_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.3), _right_hand.global_position)
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


func swing() -> void:
	swing_time = 0.15
	if not dead:
		_body.play_once("slash" if has_spear else "punch", 1.6)
