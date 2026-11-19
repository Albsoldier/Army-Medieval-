## The survivor: position, survival stats and inventory.
extends Node2D

const World = preload("res://scripts/world.gd")
const Lighting = preload("res://scripts/lighting.gd")

const SPEED := 95.0
const TORCH_RADIUS := 85.0

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

var _torch_light: PointLight2D
var _glow: PointLight2D


func _ready() -> void:
	# A faint glow so you can always see yourself, and a brighter torch light.
	_glow = Lighting.make_light(Color(0.75, 0.8, 1.0), 0.35, 34.0)
	add_child(_glow)
	_torch_light = Lighting.make_light(Color(1.0, 0.75, 0.4), 0.95, TORCH_RADIUS)
	_torch_light.enabled = false
	add_child(_torch_light)


func move(dir: Vector2, delta: float, world: World) -> void:
	if dir == Vector2.ZERO:
		return
	facing = dir.normalized()
	var step := facing * SPEED * delta
	var next_x := position + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		position = next_x
	var next_y := position + Vector2(0, step.y)
	if world.is_walkable(next_y):
		position = next_y


func tick_visuals(delta: float) -> void:
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	swing_time = maxf(swing_time - delta, 0.0)
	_torch_light.enabled = torch_time > 0.0
	if _torch_light.enabled:
		_torch_light.energy = 0.95 + sin(Time.get_ticks_msec() / 90.0) * 0.05
	queue_redraw()


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


func _draw() -> void:
	draw_circle(Vector2(0, 3), 6.0, Color(0, 0, 0, 0.25))
	var cloak := Color("35507a")
	if hurt_flash > 0.0:
		cloak = Color(0.9, 0.3, 0.3)
	draw_circle(Vector2.ZERO, 6.0, cloak)
	draw_circle(facing * 2.5, 3.5, Color("e8d3a8"))

	var hand := facing.orthogonal() * 5.0
	if has_spear:
		var reach := 16.0 if swing_time > 0.0 else 11.0
		draw_line(hand - facing * 4.0, hand + facing * reach, Color("caa472"), 1.5)
		draw_line(hand + facing * reach, hand + facing * (reach + 3.0), Color("c9ccd1"), 2.0)
	elif swing_time > 0.0:
		draw_arc(Vector2.ZERO, 11.0, facing.angle() - 0.8, facing.angle() + 0.8, 8, Color(1, 1, 1, 0.6), 1.5)
	if torch_time > 0.0:
		var torch_pos := -hand
		draw_line(torch_pos, torch_pos + Vector2(0, -5), Color("6b4a2b"), 1.5)
		draw_circle(torch_pos + Vector2(0, -6), 2.2, Color(1.0, 0.7, 0.2))
