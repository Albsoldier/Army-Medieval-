## A horse. Wild horses graze in herds in the meadows; feed one berries a few
## times and it trusts you. A tame horse waits where you leave it, and you can
## ride it (E to mount and dismount).
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const HORSE_MODEL := preload("res://models/horse.glb")

const COATS := [Color("5b3a22"), Color("2f2620"), Color("8a6a48"), Color("c9b8a0"), Color("6e4e32")]
const FEEDS_TO_TAME := 3  # berries are offered this many times before a horse trusts you
const BERRIES_PER_FEED := 2
const WANDER := 70.0  # how far a wild horse strays from its herd
const SPEED := 28.0  # grazing pace
const CAPACITY := 300  # how much a tame horse's saddlebags hold

var world: World
var pos := Vector2.ZERO
var facing := Vector2.DOWN
var coat := 0  # index into COATS
var wild := true
var trust := 0  # feeds so far
var herd_id := ""  # "herd-3:1" for wild horses, so a tamed one doesn't come back
var home := Vector2.ZERO  # where the herd grazes
var items: Dictionary = {}  # what's in the saddlebags (tame horses)

var _model: Node3D
var _look: Dictionary = {}
var _goal := Vector2.INF
var _rest := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(herd_id) + int(pos.x) * 7 + int(pos.y)
	_model = Node3D.new()
	add_child(_model)
	_look = build_model(_model, COATS[coat % COATS.size()], not wild)
	position = world.to_3d(pos)
	_model.rotation.y = atan2(facing.x, facing.y)


## A horse on `parent`: the animated deer-family model, recoloured to a horse
## coat, built stockier, with a dark mane (and a saddle cloth when tame).
## Returns a "look" to pass to animate().
static func build_model(parent: Node3D, coat_color: Color, saddled: bool) -> Dictionary:
	var body: CharacterModel = CharacterModel.new()
	parent.add_child(body)
	body.build(HORSE_MODEL, 2.25, true, {
		"idle": ["Idle"], "walk": ["Walk"], "run": ["Gallop"], "graze": ["Eating"], "death": ["Death"],
	}, {"Main": {"color": coat_color}, "Main_Light": {"color": coat_color.lightened(0.22)},
		"Main_Dark": {"color": coat_color.darkened(0.35)}, "Hooves": {"color": Color("2a2420")}})
	body.scale = Vector3(1.35, 1.0, 1.0)  # a horse is broader than a deer
	var look := {"body": body, "torso": body.bone_follower("Torso"), "neck": body.bone_follower("Neck2"),
		"head": body.bone_follower("Head")}
	var mane := Node3D.new()
	mane.top_level = true
	parent.add_child(mane)
	for k in 4:
		Art.part(mane, Art.box(Vector3(0.07, 0.16, 0.18)), Color("1f1a16"), Vector3(0, 0.1 - k * 0.02, -0.16 * k))
	look["mane"] = mane
	if saddled:
		var saddle := Node3D.new()
		saddle.top_level = true
		parent.add_child(saddle)
		Art.part(saddle, Art.box(Vector3(0.62, 0.05, 0.62)), Color("8b2e2e"), Vector3(0, 0, 0))
		Art.part(saddle, Art.box(Vector3(0.64, 0.02, 0.06)), Color("c9a24a"), Vector3(0, 0.03, 0.29))
		Art.part(saddle, Art.box(Vector3(0.64, 0.02, 0.06)), Color("c9a24a"), Vector3(0, 0.03, -0.29))
		Art.part(saddle, Art.box(Vector3(0.34, 0.1, 0.4)), Color("5a3d22"), Vector3(0, 0.07, 0))
		look["saddle"] = saddle
	return look


## Plays the right gait (pace 0 still, ~0.5 walking, 1 galloping) and keeps the
## mane and saddle on the horse.
static func animate(look: Dictionary, delta: float, pace: float, grazing: bool = false) -> void:
	var body: CharacterModel = look["body"]
	body.tick(delta)
	if pace > 0.7:
		body.play("run", 1.0)
	elif pace > 0.05:
		body.play("walk", 1.2)
	else:
		body.play("graze" if grazing else "idle")
	var yaw := Basis(Vector3.UP, body.get_parent_node_3d().global_rotation.y) if body.get_parent_node_3d() else Basis()
	var neck: Node3D = look.get("neck")
	var head: Node3D = look.get("head")
	if neck and head:
		var mane: Node3D = look["mane"]
		var along := (neck.global_position - head.global_position)
		mane.global_transform = Transform3D(yaw * Basis(Vector3.RIGHT, -atan2(along.y, maxf(Vector2(along.x, along.z).length(), 0.001))),
			head.global_position.lerp(neck.global_position, 0.25) + Vector3(0, 0.12, 0))
	var torso: Node3D = look.get("torso")
	if torso and look.has("saddle"):
		(look["saddle"] as Node3D).global_transform = Transform3D(yaw, torso.global_position + Vector3(0, 0.2, 0))


## How high the saddle sits above the horse's feet, in metres.
static func saddle_height(look: Dictionary) -> float:
	var torso: Node3D = look.get("torso")
	var body: CharacterModel = look["body"]
	if torso == null or not torso.is_inside_tree():
		return 1.2
	return torso.global_position.y - body.global_position.y + 0.2


static func set_visible_look(look: Dictionary, shown: bool) -> void:
	(look["body"] as Node3D).visible = shown
	for key in ["mane", "saddle"]:
		if look.has(key):
			(look[key] as Node3D).visible = shown


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
	animate(_look, delta, 0.5 if moving else 0.0, wild and not moving and _rest > 0.0)


## Offers berries. Returns true when this feeding tames the horse.
func feed() -> bool:
	trust += 1
	if trust >= FEEDS_TO_TAME:
		wild = false
		for child in _model.get_children():
			child.queue_free()
		_look = build_model(_model, COATS[coat % COATS.size()], true)
		return true
	return false


## How many things are in the saddlebags.
func load_count() -> int:
	var n := 0
	for item in items:
		n += int(items[item])
	return n


## Room left in the saddlebags.
func room() -> int:
	return maxi(CAPACITY - load_count(), 0)
