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
var inventory := {"wood": 0, "stone": 0, "berries": 0, "raw_meat": 0, "cooked_meat": 0}
var has_spear := false
var torch_time := 0.0
var facing := Vector2.DOWN
var hurt_flash := 0.0
var swing_time := 0.0

var _model: Node3D
var _cloak: StandardMaterial3D
var _spear: Node3D
var _torch: Node3D
var _torch_light: OmniLight3D
var _moving := false
var _step := 0.0


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	# Model faces +Z; the whole model turns to face the walking direction.
	var body := Art.part(_model, Art.capsule(0.22, 0.85), Color("35507a"), Vector3(0, 0.45, 0))
	_cloak = body.material_override
	Art.part(_model, Art.box(Vector3(0.32, 0.36, 0.16)), Color("6b4a2b"), Vector3(0, 0.6, -0.2))  # pack
	Art.part(_model, Art.sphere(0.17, 5, 10), Color("e8d3a8"), Vector3(0, 1.0, 0))
	Art.part(_model, Art.cylinder(0.0, 0.21, 0.28, 8), Color("2b4266"), Vector3(0, 1.2, -0.02))  # hood
	Art.part(_model, Art.sphere(0.028, 2, 4), Color("1a1a1a"), Vector3(0.06, 1.02, 0.15))
	Art.part(_model, Art.sphere(0.028, 2, 4), Color("1a1a1a"), Vector3(-0.06, 1.02, 0.15))

	# Spear, held at the right side and pointing forward.
	_spear = Node3D.new()
	_spear.position = Vector3(-0.27, 0.55, 0.0)
	_spear.rotation = Vector3(PI / 2 - 0.25, 0, 0)
	_model.add_child(_spear)
	Art.part(_spear, Art.cylinder(0.022, 0.022, 1.5, 5), Color("caa472"), Vector3(0, 0.35, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.18, 5), Color("c9ccd1"), Vector3(0, 1.17, 0))
	_spear.visible = false

	# Torch in the left hand, with its own light.
	_torch = Node3D.new()
	_torch.position = Vector3(0.28, 0.55, 0.12)
	_model.add_child(_torch)
	Art.part(_torch, Art.cylinder(0.03, 0.025, 0.5, 5), Color("6b4a2b"), Vector3(0, 0.15, 0))
	Art.part(_torch, Art.sphere(0.07, 3, 6), Color(1.0, 0.65, 0.2), Vector3(0, 0.45, 0), Vector3.ZERO, 4.0, true)
	_torch_light = Art.omni(Color(1.0, 0.72, 0.4), TORCH_RADIUS / World.TILE * 1.3, 2.2)
	_torch_light.position = Vector3(0, 0.6, 0)
	_torch.add_child(_torch_light)
	_torch.visible = false

	# A faint glow so you can always see yourself at night.
	var glow := Art.omni(Color(0.6, 0.7, 1.0), 2.6, 0.35)
	glow.position = Vector3(0, 1.6, 0)
	add_child(glow)
	position = world.to_3d(pos)


func move(dir: Vector2, delta: float) -> void:
	_moving = dir != Vector2.ZERO
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
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 14.0, 1.0))
	if _moving:
		_step += delta * 13.0
		_model.position.y = absf(sin(_step)) * 0.07
	else:
		_model.position.y = move_toward(_model.position.y, 0.0, delta)
	_moving = false
	_cloak.albedo_color = Color(0.9, 0.3, 0.3) if hurt_flash > 0.0 else Color("35507a")

	_spear.visible = has_spear
	_spear.position.z = 0.3 if swing_time > 0.0 else 0.0
	_model.position.z = 0.12 if swing_time > 0.0 and not has_spear else 0.0
	_torch.visible = torch_time > 0.0
	if _torch.visible:
		_torch_light.light_energy = 2.2 + sin(Time.get_ticks_msec() / 90.0) * 0.15


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
