## Wolves hunt at night, keep away from firelight and slink off at dawn.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

const SPEED := 70.0
const BITE_DAMAGE := 12.0

var world: World
var pos := Vector2.ZERO
var hp := 3
var bite_cooldown := 0.0
var hurt_flash := 0.0
var knock := Vector2.ZERO
var facing := Vector2.RIGHT

var _model: Node3D
var _fur: StandardMaterial3D
var _legs: Array = []
var _gait := 0.0


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	var fur := Color("5d5a58")
	var body := Art.part(_model, Art.capsule(0.19, 0.95), fur, Vector3(0, 0.45, 0), Vector3(PI / 2, 0, 0))
	_fur = body.material_override
	Art.part(_model, Art.sphere(0.17, 4, 8), fur.lightened(0.08), Vector3(0, 0.62, 0.45))
	Art.part(_model, Art.box(Vector3(0.12, 0.1, 0.2)), fur.lightened(0.15), Vector3(0, 0.57, 0.62))
	Art.part(_model, Art.cylinder(0.0, 0.05, 0.13, 4), fur.darkened(0.2), Vector3(0.08, 0.8, 0.42))
	Art.part(_model, Art.cylinder(0.0, 0.05, 0.13, 4), fur.darkened(0.2), Vector3(-0.08, 0.8, 0.42))
	Art.part(_model, Art.cylinder(0.02, 0.06, 0.45, 5), fur.darkened(0.1), Vector3(0, 0.5, -0.6), Vector3(-PI / 3, 0, 0))
	# Eyes glow in the dark.
	Art.part(_model, Art.sphere(0.03, 2, 4), Color(1.0, 0.85, 0.2), Vector3(0.07, 0.66, 0.6), Vector3.ZERO, 3.0, true)
	Art.part(_model, Art.sphere(0.03, 2, 4), Color(1.0, 0.85, 0.2), Vector3(-0.07, 0.66, 0.6), Vector3.ZERO, 3.0, true)
	for leg_pos in [Vector3(0.11, 0.18, 0.3), Vector3(-0.11, 0.18, 0.3), Vector3(0.11, 0.18, -0.3), Vector3(-0.11, 0.18, -0.3)]:
		_legs.append(Art.part(_model, Art.cylinder(0.04, 0.035, 0.36, 5), fur.darkened(0.15), leg_pos))
	position = world.to_3d(pos)


## Moves the wolf. Returns true when it bites the player this frame.
func tick(delta: float, target: Vector2, fires: Array, night: bool) -> bool:
	bite_cooldown = maxf(bite_cooldown - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)

	var dir := target - pos
	var scared := not night
	if not night:
		dir = pos - target
	for fire in fires:
		if fire.is_lit() and pos.distance_to(fire.pos) < fire.radius:
			dir = pos - fire.pos
			scared = true
			break

	if dir.length() > 1.0:
		facing = dir.normalized()
	var velocity := facing * SPEED + knock
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	_slide(velocity * delta)
	_animate(delta)

	if not scared and bite_cooldown <= 0.0 and pos.distance_to(target) < 13.0:
		bite_cooldown = 1.3
		return true
	return false


func hurt(damage: int, from: Vector2) -> void:
	hp -= damage
	hurt_flash = 0.15
	knock = (pos - from).normalized() * 260.0


func _slide(step: Vector2) -> void:
	var next_x := pos + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		pos = next_x
	var next_y := pos + Vector2(0, step.y)
	if world.is_walkable(next_y):
		pos = next_y


func _animate(delta: float) -> void:
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 10.0, 1.0))
	_gait += delta * 14.0
	for i in _legs.size():
		var leg: MeshInstance3D = _legs[i]
		leg.rotation.x = sin(_gait + (PI if i % 3 == 0 else 0.0)) * 0.5
	_model.position.y = absf(sin(_gait)) * 0.04
	_fur.albedo_color = Color(0.9, 0.35, 0.35) if hurt_flash > 0.0 else Color("5d5a58")
