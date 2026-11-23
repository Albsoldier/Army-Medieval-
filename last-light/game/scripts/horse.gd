## A horse. Wild horses graze in herds in the meadows; feed one berries a few
## times and it trusts you. A tame horse waits where you leave it, and you can
## ride it (E to mount and dismount).
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const HORSE_MODEL := preload("res://models/horse.glb")

## Coat tints over the model's chestnut (it's coloured per vertex, so a tint
## shades it): natural chestnut, dark bay, black, light dun, liver.
const COATS := [Color(1, 1, 1), Color(0.72, 0.62, 0.58), Color(0.42, 0.4, 0.4), Color(1.18, 1.08, 0.9), Color(0.82, 0.7, 0.62)]
## The model's parts: the horse itself, and the tack a tame or war horse wears.
const TACK := ["attach-blanket-mesh", "attach-saddle-mesh", "attach-bridle-mesh"]
const SIZE := 1.08  # in proportion with people
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


## A horse on `parent`: the barded war horse (CC0), with its scale barding,
## saddle and plumed bridle when `saddled`; wild horses go bare. Returns a
## "look" to pass to animate().
static func build_model(parent: Node3D, coat_color: Color, saddled: bool) -> Dictionary:
	var body: CharacterModel = CharacterModel.new()
	parent.add_child(body)
	body.build(HORSE_MODEL, 0.0, false, {"idle": ["Idle"], "walk": ["Walk"], "run": ["Run"]})
	body.scale = Vector3.ONE * SIZE
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		var tack := mesh_instance.name in TACK
		mesh_instance.visible = saddled or not tack
		# The model is coloured per vertex; the coat tint shades the horse, not its tack.
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE if tack else coat_color
		mat.roughness = 0.5 if mesh_instance.name == "attach-blanket-mesh" else 0.85
		mat.metallic = 0.35 if mesh_instance.name == "attach-blanket-mesh" else 0.0
		mat.rim_enabled = true
		mat.rim = 0.3
		mat.rim_tint = 0.7
		mesh_instance.material_override = mat
	return {"body": body, "spine": body.bone_follower("Spine")}


## Plays the right gait: pace 0 standing, ~0.5 walking, 1 running.
static func animate(look: Dictionary, delta: float, pace: float, _grazing: bool = false) -> void:
	var body: CharacterModel = look["body"]
	body.tick(delta)
	if pace > 0.7:
		body.play("run", 1.0)
	elif pace > 0.05:
		body.play("walk", 1.1)
	else:
		body.play("idle")


## How high the saddle seat is above the horse's hooves, in metres.
static func saddle_height(look: Dictionary) -> float:
	var spine: Node3D = look.get("spine")
	var body: CharacterModel = look["body"]
	if spine == null or not spine.is_inside_tree():
		return 1.32 * SIZE
	return spine.global_position.y - body.global_position.y + 0.36 * SIZE


static func set_visible_look(look: Dictionary, shown: bool) -> void:
	(look["body"] as Node3D).visible = shown


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
