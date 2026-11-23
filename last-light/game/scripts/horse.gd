## A horse. Wild horses graze in herds in the meadows; feed one berries a few
## times and it trusts you. A tame horse waits where you leave it, and you can
## ride it (E to mount and dismount).
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

const COATS := [Color("5b3a22"), Color("2f2620"), Color("8a6a48"), Color("c9b8a0"), Color("6e4e32")]
const FEEDS_TO_TAME := 3  # berries are offered this many times before a horse trusts you
const BERRIES_PER_FEED := 2
const WANDER := 70.0  # how far a wild horse strays from its herd
const SPEED := 28.0  # grazing pace

var world: World
var pos := Vector2.ZERO
var facing := Vector2.DOWN
var coat := 0  # index into COATS
var wild := true
var trust := 0  # feeds so far
var herd_id := ""  # "herd-3:1" for wild horses, so a tamed one doesn't come back
var home := Vector2.ZERO  # where the herd grazes

var _model: Node3D
var _legs: Array = []
var _goal := Vector2.INF
var _rest := 0.0
var _gait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(herd_id) + int(pos.x) * 7 + int(pos.y)
	_model = Node3D.new()
	add_child(_model)
	_legs = build_model(_model, COATS[coat % COATS.size()], not wild)
	position = world.to_3d(pos)
	_model.rotation.y = atan2(facing.x, facing.y)


## A low-poly horse on `parent`. Returns the four leg pivots to swing.
## With `saddled`, it wears a red saddle cloth.
static func build_model(parent: Node3D, coat_color: Color, saddled: bool) -> Array:
	var legs := []
	Art.part(parent, Art.box(Vector3(0.46, 0.55, 1.35)), coat_color, Vector3(0, 1.1, 0))
	Art.part(parent, Art.box(Vector3(0.3, 0.75, 0.32)), coat_color, Vector3(0, 1.5, 0.68), Vector3(0.55, 0, 0))  # neck
	Art.part(parent, Art.box(Vector3(0.26, 0.28, 0.55)), coat_color, Vector3(0, 1.82, 0.98), Vector3(0.35, 0, 0))  # head
	Art.part(parent, Art.box(Vector3(0.06, 0.55, 0.12)), Color("1f1a16"), Vector3(0, 1.7, 0.55), Vector3(0.55, 0, 0))  # mane
	Art.part(parent, Art.box(Vector3(0.1, 0.55, 0.1)), Color("1f1a16"), Vector3(0, 1.0, -0.78), Vector3(-0.4, 0, 0))  # tail
	if saddled:
		Art.part(parent, Art.box(Vector3(0.52, 0.08, 0.6)), Color("8b2e2e"), Vector3(0, 1.4, -0.05))
	for x in [-0.17, 0.17]:
		for z in [-0.5, 0.5]:
			var hip := Node3D.new()
			hip.position = Vector3(x, 0.92, z)
			parent.add_child(hip)
			Art.part(hip, Art.box(Vector3(0.12, 0.9, 0.14)), coat_color.darkened(0.1), Vector3(0, -0.45, 0))
			Art.part(hip, Art.box(Vector3(0.13, 0.08, 0.16)), Color("1f1a16"), Vector3(0, -0.88, 0))
			legs.append(hip)
	return legs


## Swings the legs; `pace` 0 stands still.
static func animate_legs(legs: Array, gait: float, pace: float) -> void:
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sin(gait + (PI if i % 3 == 0 else 0.0)) * 0.55 * pace


## Wild horses wander and graze near their herd; tame ones stand and wait.
func tick(delta: float) -> void:
	var moving := false
	if wild:
		_rest -= delta
		if _goal == Vector2.INF and _rest <= 0.0:
			_goal = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, WANDER)
		if _goal != Vector2.INF:
			var to_goal := _goal - pos
			if to_goal.length() < 4.0:
				_goal = Vector2.INF
				_rest = _rng.randf_range(3.0, 8.0)  # graze a while
			else:
				facing = to_goal.normalized()
				var next := pos + facing * minf(SPEED * delta, to_goal.length())
				if world.is_walkable(next):
					pos = next
					moving = true
				else:
					_goal = Vector2.INF
					_rest = 1.0
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 4.0, 1.0))
	_gait += delta * (6.0 if moving else 0.0)
	animate_legs(_legs, _gait, 0.6 if moving else 0.0)
	# Grazing: the head dips while resting.
	if _model.get_child_count() > 2:
		var head := _model.get_child(2) as Node3D
		head.position.y = 1.82 - (0.35 if wild and not moving and _rest > 0.0 else 0.0)


## Offers berries. Returns true when this feeding tames the horse.
func feed() -> bool:
	trust += 1
	if trust >= FEEDS_TO_TAME:
		wild = false
		for child in _model.get_children():
			child.queue_free()
		_legs = build_model(_model, COATS[coat % COATS.size()], true)
		return true
	return false
