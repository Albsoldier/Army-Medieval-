## A settler in your village. Settlers move into cottages when your chests
## hold food, wander between the fields and houses, tend the wheat, and pay
## taxes in gold each morning. When a wolf or raider comes near they run home
## and hide until it's gone.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const SURVIVOR := preload("res://models/adventurer.glb")

const MAX_HP := 30.0
const SPEED := 38.0
const FLEE_SPEED := 85.0
const DANGER := 150.0  # an enemy this close sends them running home
const NAMES := ["Wenna", "Bran", "Elowen", "Tobin", "Maud", "Osric", "Hild", "Corin", "Ysolde", "Edric",
	"Morwen", "Aldo", "Briony", "Garth", "Isolde", "Rowan", "Tamsin", "Wat", "Agnes", "Piers"]
const SHIRTS := ["9a7b4f", "6e7f5a", "8a5a44", "5f6f86", "a88f5c", "7a6a8a"]

var world: World
var settler_name := ""
var pos := Vector2.ZERO
var home := Vector2.ZERO  # their cottage
var hp := MAX_HP
var look := 0  # which clothes
var dead := false
var hidden := false  # indoors, out of harm's way
var tending := false  # standing at a field this frame

var _model: Node3D
var _body: CharacterModel
var _hat: Node3D
var _head: Node3D
var _goal := Vector2.INF
var _goal_is_field := false
var _rest := 0.0
var _moving := false
var _hurt := 0.0
var _work_timer := 0.0
var _rng := RandomNumberGenerator.new()
var facing := Vector2.DOWN


func _ready() -> void:
	_rng.seed = hash(settler_name) + look
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	var shirt := Color(SHIRTS[look % SHIRTS.size()])
	_body.build(SURVIVOR, 1.58, false, {
		"idle": ["Man_Idle", "Idle"], "walk": ["Man_Walk", "Walk", "Man_Run", "Run"], "run": ["Man_Run", "Run"],
		"work": ["Man_SwordSlash", "Sword_Slash"], "death": ["Man_Death", "Death"],
	}, {"Shirt": {"color": shirt}, "Green": {"color": shirt}, "LightGreen": {"color": shirt.lightened(0.15)},
		"Pants": {"color": Color("4a3a2a")}, "Brown": {"color": Color("4a3a2a")}})
	_head = _body.bone_follower("Head")
	if look % 2 == 0:
		# A wide straw hat.
		_hat = Node3D.new()
		_hat.top_level = true
		add_child(_hat)
		Art.part(_hat, Art.cylinder(0.26, 0.26, 0.03, 10), Color("d9c27a"), Vector3(0, 0.1, 0))
		Art.part(_hat, Art.cylinder(0.1, 0.13, 0.12, 8), Color("cdb46c"), Vector3(0, 0.17, 0))
	position = world.to_3d(pos)


## danger: the nearest enemy (Vector2.INF if none). spots: places worth
## walking to (fields first, then houses and chests). fields: field positions.
func tick(delta: float, danger: Vector2, spots: Array, fields: Array) -> void:
	tending = false
	if dead:
		_body.tick(delta)
		return
	_hurt = maxf(_hurt - delta, 0.0)
	hp = minf(hp + delta * 0.5, MAX_HP)
	var threatened := danger != Vector2.INF and danger.distance_to(pos) < DANGER
	if threatened:
		# Run home and bar the door.
		_goal = Vector2.INF
		if pos.distance_to(home) < 14.0:
			_set_hidden(true)
		else:
			_walk(home, delta, FLEE_SPEED)
		_animate(delta, "run")
		return
	if hidden:
		_set_hidden(false)
		_rest = _rng.randf_range(1.0, 3.0)
	if _goal == Vector2.INF:
		_rest -= delta
		if _rest <= 0.0 and not spots.is_empty():
			var spot: Vector2 = spots[_rng.randi() % spots.size()]
			_goal_is_field = spot in fields
			_goal = spot + Vector2.from_angle(_rng.randf() * TAU) * (_rng.randf_range(2.0, 6.0) if _goal_is_field else _rng.randf_range(14.0, 26.0))
	var action := "idle"
	if _goal != Vector2.INF:
		if pos.distance_to(_goal) < 4.0:
			_goal = Vector2.INF
			_rest = _rng.randf_range(5.0, 12.0) if _goal_is_field else _rng.randf_range(3.0, 7.0)
		elif not _walk(_goal, delta, SPEED):
			_goal = Vector2.INF  # can't get there
			_rest = 1.0
		else:
			action = "walk"
	if _goal == Vector2.INF and _goal_is_field and _rest > 0.0:
		tending = true  # hoeing the wheat
		action = "work"
	_animate(delta, action)


func _walk(goal: Vector2, delta: float, speed: float) -> bool:
	var to_goal := goal - pos
	if to_goal.length() < 1.0:
		return true
	facing = to_goal.normalized()
	var before := pos
	var step := facing * minf(speed * delta, to_goal.length())
	if world.is_walkable(pos + Vector2(step.x, 0)):
		pos += Vector2(step.x, 0)
	if world.is_walkable(pos + Vector2(0, step.y)):
		pos += Vector2(0, step.y)
	_moving = pos.distance_to(before) > step.length() * 0.2
	return _moving


func _set_hidden(on: bool) -> void:
	hidden = on
	visible = not on
	if on:
		pos = home


func hurt(amount: float) -> bool:
	if dead or hidden:
		return false
	hp -= amount
	_hurt = 0.2
	if hp <= 0.0:
		dead = true
		if _hat:
			_hat.visible = false
		_body.flash(false)
		_body.play_once("death")
		return true
	return false


func _animate(delta: float, action: String) -> void:
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 8.0, 1.0))
	_body.tick(delta)
	_work_timer -= delta
	if action == "work":
		if _work_timer <= 0.0:
			_work_timer = 2.2
			_body.play_once("work", 0.7)
	else:
		_body.play(action, 0.75 if action == "walk" else 1.0)
	_body.flash(_hurt > 0.0)
	if _hat and _head:
		_hat.global_transform = Transform3D(Basis(Vector3.UP, _model.rotation.y), _head.global_position + Vector3(0, 0.04, 0))
