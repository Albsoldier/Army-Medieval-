## Wolves hunt at night, keep away from firelight and slink off at dawn.
extends Node2D

const World = preload("res://scripts/world.gd")

const SPEED := 70.0
const BITE_DAMAGE := 12.0

var hp := 3
var bite_cooldown := 0.0
var hurt_flash := 0.0
var knock := Vector2.ZERO
var facing := Vector2.RIGHT


## Moves the wolf. Returns true when it bites the player this frame.
func tick(delta: float, world: World, target: Vector2, fires: Array, night: bool) -> bool:
	bite_cooldown = maxf(bite_cooldown - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)

	var dir := target - position
	var scared := not night
	if not night:
		dir = position - target
	for fire in fires:
		if fire.is_lit() and position.distance_to(fire.position) < fire.radius:
			dir = position - fire.position
			scared = true
			break

	if dir.length() > 1.0:
		facing = dir.normalized()
	var velocity := facing * SPEED + knock
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	_slide(world, velocity * delta)
	queue_redraw()

	if not scared and bite_cooldown <= 0.0 and position.distance_to(target) < 13.0:
		bite_cooldown = 1.3
		return true
	return false


func hurt(damage: int, from: Vector2) -> void:
	hp -= damage
	hurt_flash = 0.15
	knock = (position - from).normalized() * 260.0


func _slide(world: World, step: Vector2) -> void:
	var next_x := position + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		position = next_x
	var next_y := position + Vector2(0, step.y)
	if world.is_walkable(next_y):
		position = next_y


func _draw() -> void:
	var fur := Color("5d5a58")
	if hurt_flash > 0.0:
		fur = Color(0.9, 0.35, 0.35)
	draw_circle(Vector2(0, 3), 6.0, Color(0, 0, 0, 0.25))
	draw_circle(-facing * 4.0, 5.0, fur)
	draw_circle(facing * 3.0, 4.0, fur.lightened(0.1))
	draw_line(-facing * 8.0, -facing * 13.0 + facing.orthogonal() * 2.0, fur, 2.0)
	var side := facing.orthogonal() * 1.6
	draw_circle(facing * 5.0 + side, 0.9, Color(1.0, 0.85, 0.2))
	draw_circle(facing * 5.0 - side, 0.9, Color(1.0, 0.85, 0.2))
