## A campfire: warmth, light, cooking, and wolves keep their distance.
## A fire with no fuel is a cold pit, like the abandoned camps of other players.
extends Node2D

const Lighting = preload("res://scripts/lighting.gd")

const MAX_FUEL := 300.0

var radius := 110.0
var fuel := 180.0
var owner_name := ""  # set for camps built by other players
var _light: PointLight2D
var _t := 0.0


func _ready() -> void:
	_light = Lighting.make_light(Color(1.0, 0.62, 0.3), 1.15, radius * 1.15)
	add_child(_light)
	_light.enabled = is_lit()


func is_lit() -> bool:
	return fuel > 0.0


func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, MAX_FUEL)


func tick(delta: float) -> void:
	_t += delta
	if fuel > 0.0:
		fuel = maxf(fuel - delta, 0.0)
	_light.enabled = is_lit()
	if is_lit():
		# Fires shrink as they run low on fuel.
		var strength := clampf(fuel / 60.0, 0.45, 1.0)
		var flicker := 1.0 + sin(_t * 9.0) * 0.03 + sin(_t * 23.0) * 0.02
		_light.texture_scale = radius * 1.15 / 128.0 * strength * flicker
	queue_redraw()


func _draw() -> void:
	for i in 7:
		var a := TAU * i / 7.0
		draw_circle(Vector2.from_angle(a) * 7.0, 2.2, Color("77736a"))
	draw_line(Vector2(-5, 3), Vector2(5, -2), Color("4d3420"), 2.5)
	draw_line(Vector2(-5, -2), Vector2(5, 3), Color("5a3d22"), 2.5)
	if is_lit():
		var h := 7.0 + sin(_t * 12.0) * 1.5
		draw_colored_polygon(PackedVector2Array([Vector2(-4, 1), Vector2(0, -h), Vector2(4, 1)]), Color(1.0, 0.55, 0.1))
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 1), Vector2(0, -h * 0.55), Vector2(2, 1)]), Color(1.0, 0.9, 0.4))
	else:
		draw_circle(Vector2.ZERO, 3.0, Color("2b2522"))
