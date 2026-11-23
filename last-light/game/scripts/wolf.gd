## Wolves hunt at night, keep away from firelight and slink off at dawn.
extends Node3D

const World = preload("res://scripts/world.gd")

const SPEED := 70.0
const BITE_DAMAGE := 12.0  # a grey wolf's bite
## Wolves get tougher as the days go by, so better weapons and armour matter.
const KINDS := {
	"grey": {"name": "grey wolf", "hp": 3, "bite": 12.0, "speed": 70.0, "size": 1.5, "fur": Color("8a8580"), "belly": Color("c9c2b8"), "meat": 2, "hide": 1},
	"timber": {"name": "timber wolf", "hp": 10, "bite": 18.0, "speed": 78.0, "size": 1.8, "fur": Color("5e4a36"), "belly": Color("9c8466"), "meat": 3, "hide": 2},
	"dire": {"name": "dire wolf", "hp": 26, "bite": 30.0, "speed": 84.0, "size": 2.3, "fur": Color("2a2624"), "belly": Color("4a4440"), "meat": 5, "hide": 3},
}

var world: World
var kind := "grey"
var pos := Vector2.ZERO
var hp := 3
var bite := BITE_DAMAGE
var speed := SPEED
var bite_cooldown := 0.0
var hurt_flash := 0.0
var knock := Vector2.ZERO
var facing := Vector2.RIGHT
## The tile of a wall or building this wolf bumped into this frame, if any.
var blocked_cell := Vector2i(-1, -1)

const CharacterModel = preload("res://scripts/character_model.gd")
const WOLF_MODEL := preload("res://models/wolf.glb")

var dead := false
var _model: Node3D
var _body: CharacterModel


## Which kind of wolf comes out on a given night: grey wolves at first, then
## timber wolves from day 4 and dire wolves from day 9 (more often in winter).
static func pick_kind(day: int, winter: bool, roll: float) -> String:
	var dire := clampf((day - 8) * 0.06, 0.0, 0.35) + (0.1 if winter and day >= 9 else 0.0)
	var timber := clampf((day - 3) * 0.1, 0.0, 0.5)
	if roll < dire:
		return "dire"
	if roll < dire + timber:
		return "timber"
	return "grey"


## Glowing eyes for all; timber and dire wolves get darker coats.
func _colours(stats: Dictionary) -> Dictionary:
	var out := {"Eyes_Black": {"color": Color(1.0, 0.2, 0.1) if kind == "dire" else Color(1.0, 0.8, 0.2), "emission": 4.0}}
	if kind != "grey":
		out["Main"] = {"color": stats["fur"]}
		out["Main_Light"] = {"color": stats["belly"]}
	return out


static func info(k: String) -> Dictionary:
	return KINDS.get(k, KINDS["grey"])


func _ready() -> void:
	var stats := info(kind)
	hp = int(stats["hp"])
	bite = float(stats["bite"])
	speed = float(stats["speed"])
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(WOLF_MODEL, float(stats["size"]), true, {
		"idle": ["Idle"],
		"walk": ["Walk"],
		"run": ["Gallop"],
		"attack": ["Attack"],
		"death": ["Death"],
	}, _colours(stats))
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
	var velocity := facing * speed + knock
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
	knock = (pos - from).normalized() * 260.0 / (1.0 + float(info(kind)["size"]) - 1.5)  # big wolves barely budge


func _slide(step: Vector2) -> void:
	blocked_cell = Vector2i(-1, -1)
	var next_x := pos + Vector2(step.x, 0)
	if world.is_walkable(next_x, true):
		pos = next_x
	elif world.structures.has(world.cell_of(next_x)):
		blocked_cell = world.cell_of(next_x)
	var next_y := pos + Vector2(0, step.y)
	if world.is_walkable(next_y, true):
		pos = next_y
	elif world.structures.has(world.cell_of(next_y)):
		blocked_cell = world.cell_of(next_y)


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
