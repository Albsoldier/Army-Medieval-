## A campfire: warmth, light, cooking, and wolves keep their distance.
## A fire with no fuel is a cold pit, like the abandoned camps of other players.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

const MAX_FUEL := 300.0

var world: World
var pos := Vector2.ZERO
var radius := 110.0  # warmth and safety radius, in game pixels
var fuel := 180.0
var owner_name := ""  # set for camps built by other players
var _t := 0.0
var _flame: Node3D
var _light: OmniLight3D
var _embers: CPUParticles3D


func _ready() -> void:
	position = world.to_3d(pos)
	for i in 8:
		var a := TAU * i / 8.0
		Art.part(self, Art.sphere(0.13, 3, 6), Color("77736a"), Vector3(cos(a) * 0.45, 0.07, sin(a) * 0.45))
	Art.part(self, Art.cylinder(0.27, 0.27, 0.03, 10), Color("2b2522"), Vector3(0, 0.02, 0))
	Art.part(self, Art.cylinder(0.065, 0.075, 0.75, 6), Color("5a3d22"), Vector3(0, 0.1, 0), Vector3(PI / 2, 0.7, 0))
	Art.part(self, Art.cylinder(0.065, 0.075, 0.75, 6), Color("4d3420"), Vector3(0, 0.14, 0), Vector3(PI / 2, -0.7, 0))

	_flame = Node3D.new()
	_flame.position = Vector3(0, 0.12, 0)
	add_child(_flame)
	Art.part(_flame, Art.cylinder(0.0, 0.24, 0.65, 7), Color(1.0, 0.45, 0.08), Vector3(0, 0.3, 0), Vector3.ZERO, 3.0, true)
	Art.part(_flame, Art.cylinder(0.0, 0.13, 0.4, 7), Color(1.0, 0.85, 0.35), Vector3(0, 0.2, 0), Vector3.ZERO, 3.0, true)

	_light = Art.omni(Color(1.0, 0.6, 0.3), radius / World.TILE * 1.25, 2.6)
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)

	_embers = CPUParticles3D.new()
	var spark := Art.sphere(0.025, 2, 4)
	spark.material = Art.material(Color(1.0, 0.6, 0.2), 4.0, true)
	_embers.mesh = spark
	_embers.amount = 14
	_embers.lifetime = 1.4
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 0.15
	_embers.direction = Vector3.UP
	_embers.spread = 20.0
	_embers.gravity = Vector3(0, 0.3, 0)
	_embers.initial_velocity_min = 0.4
	_embers.initial_velocity_max = 1.0
	_embers.position = Vector3(0, 0.4, 0)
	add_child(_embers)
	_update_visuals()


func is_lit() -> bool:
	return fuel > 0.0


func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, MAX_FUEL)
	_update_visuals()


func tick(delta: float) -> void:
	_t += delta
	if fuel > 0.0:
		fuel = maxf(fuel - delta, 0.0)
	_update_visuals()


func _update_visuals() -> void:
	var lit := is_lit()
	_flame.visible = lit
	_light.visible = lit
	_embers.emitting = lit
	if lit:
		# Fires shrink as they run low on fuel.
		var strength := clampf(fuel / 60.0, 0.45, 1.0)
		var flicker := 1.0 + sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.05
		_flame.scale = Vector3(strength, strength * flicker, strength)
		_light.light_energy = 2.6 * strength * (1.0 + sin(_t * 11.0) * 0.06)
