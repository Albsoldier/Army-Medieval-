## Wolves hunt at night, keep away from firelight and slink off at dawn.
extends Node3D

const World = preload("res://scripts/world.gd")

const SPEED := 70.0
const BITE_DAMAGE := 12.0

var world: World
var pos := Vector2.ZERO
var hp := 3
var bite_cooldown := 0.0
var hurt_flash := 0.0
var knock := Vector2.ZERO
var facing := Vector2.RIGHT

const CharacterModel = preload("res://scripts/character_model.gd")
const WOLF_MODEL := preload("res://models/wolf.glb")

var dead := false
var _model: Node3D
var _body: CharacterModel


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(WOLF_MODEL, 1.5, true, {
		"idle": ["Idle"],
		"walk": ["Walk"],
		"run": ["Gallop"],
		"attack": ["Attack"],
		"death": ["Death"],
	}, {"Eyes_Black": {"color": Color(1.0, 0.8, 0.2), "emission": 4.0}})  # eyes glow in the dark
	position = world.to_3d(pos)


## Moves the wolf. Returns true when it bites the player this frame.
func tick(delta: float, target: Vector2, fires: Array, night: bool) -> bool:
	if dead:
		_body.tick(delta)
		return false
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
		_body.play_once("attack", 1.5)
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
	_body.tick(delta)
	_body.play("run")
	_body.flash(hurt_flash > 0.0)


## Plays the death animation; the caller removes the wolf afterwards.
func die() -> float:
	dead = true
	_body.flash(false)
	return _body.play_once("death")
