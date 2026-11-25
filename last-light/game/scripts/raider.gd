## Raiders: human enemies who live in camps scattered over the island and the
## islets. They share the wolves' rules (so soldiers, weapons and armour all
## work on them), but they don't fear fire or daylight. They only ever defend
## their own camp: they never leave it and never touch your buildings.
extends "res://scripts/wolf.gd"

const Art = preload("res://scripts/art.gd")
const SURVIVOR := preload("res://models/raider.glb")  # a hooded fighter in leather and iron

const RAIDERS := {
	"raider": {"name": "raider", "hp": 14, "bite": 14.0, "speed": 80.0, "height": 1.66,
		"shirt": Color("4a3a2a"), "pants": Color("2a241e"), "shield": Color("6b4a2b"),
		"loot": {"iron": 1, "wood": 4, "cooked_meat": 1}},
	"raider_chief": {"name": "raider chief", "hp": 45, "bite": 24.0, "speed": 76.0, "height": 1.85,
		"shirt": Color("2e2a3a"), "pants": Color("1e1a22"), "shield": Color("7a1f1f"),
		"loot": {"gold": 2, "iron": 3, "steel": 1}},
}
const GUARD_LEASH := 260.0  # guards don't chase further than this from camp

## The camp this raider guards.
var home := Vector2.INF
var purge := false  # one of a purge wave: comes for your vault and breaks walls on the way
var camp := -1  # the islet a guard belongs to

var _right_hand: Node3D
var _left_hand: Node3D
var _head: Node3D
var _kit: Array = []
var _axe: Node3D
var _shield: Node3D
var _helmet: Node3D
var _moving := false
var _detour := 0.0  # purge raiders sidestep things in their way for this long
var _detour_dir := Vector2.ZERO


static func raider_info(k: String) -> Dictionary:
	return RAIDERS.get(k, RAIDERS["raider"])


func is_raider() -> bool:
	return true


func display_name() -> String:
	return str(raider_info(kind)["name"])


func loot() -> Dictionary:
	return raider_info(kind)["loot"]


func _ready() -> void:
	if not RAIDERS.has(kind):
		kind = "raider"
	var stats := raider_info(kind)
	hp = int(stats["hp"])
	bite = float(stats["bite"])
	speed = float(stats["speed"])
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(SURVIVOR, float(stats["height"]), false, {
		"idle": ["Man_Idle", "Idle"], "run": ["Man_Run", "Run"], "attack": ["Man_SwordSlash", "Sword_Slash"],
		"death": ["Man_Death", "Death"],
	}, {"Shirt": {"color": stats["shirt"]}, "Pants": {"color": stats["pants"]},
		"LightBrown": {"color": stats["shirt"]}, "DarkBrown": {"color": stats["pants"]}})
	_right_hand = _body.bone_follower("Palm.R")
	_left_hand = _body.bone_follower("Palm.L")
	_head = _body.bone_follower("Head")
	_build_kit(stats)
	# Each piece of kit is one mesh (fewer draw calls), and so is a chief's mantle and cloak.
	for i in _kit.size():
		Art.bake(_kit[i], Art.parts_of(_kit[i]), "raider-kit:%s:%d" % [kind, i])
	Art.bake(_model, Art.parts_of(_model), "raider-worn:" + kind)
	position = world.to_3d(pos)


## A conical iron helmet, a round shield and an axe. Chiefs wear a fur mantle.
func _build_kit(stats: Dictionary) -> void:
	# Raiders wear their hoods; a chief wears an iron helmet over his.
	if kind == "raider_chief":
		_helmet = _piece()
		Art.part(_helmet, Art.cylinder(0.0, 0.17, 0.24, 8), Color("6f7378"), Vector3(0, 0.16, 0))
		Art.part(_helmet, Art.cylinder(0.175, 0.175, 0.04, 8), Color("55595e"), Vector3(0, 0.05, 0))
		Art.part(_helmet, Art.box(Vector3(0.03, 0.12, 0.03)), Color("55595e"), Vector3(0, -0.01, 0.16))  # nose guard
	_shield = _piece()
	Art.part(_shield, Art.cylinder(0.3, 0.3, 0.04, 12), stats["shield"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
	Art.part(_shield, Art.sphere(0.07, 4, 8), Color("8a8f95"), Vector3(0, 0, 0.03))
	Art.part(_shield, Art.cylinder(0.31, 0.31, 0.02, 12), Color("3d2a18"), Vector3(0, 0, -0.005), Vector3(PI / 2, 0, 0))
	_axe = _piece()
	Art.part(_axe, Art.cylinder(0.025, 0.025, 0.8, 5), Color("6b4a2b"), Vector3(0, 0.28, 0))
	Art.part(_axe, Art.box(Vector3(0.04, 0.2, 0.22)), Color("8a8f95"), Vector3(0, 0.6, 0.1))
	if kind == "raider_chief":
		var mantle := Art.part(_model, Art.box(Vector3(0.62, 0.22, 0.4)), Color("3a2c20"), Vector3(0, 1.5, -0.02))
		mantle.scale = Vector3(1, 1, 1)
		Art.part(_model, Art.box(Vector3(0.5, 0.8, 0.05)), Color("3a2c20"), Vector3(0, 1.05, -0.2), Vector3(0.1, 0, 0))  # cloak
		Art.part(_helmet, Art.box(Vector3(0.05, 0.2, 0.05)), Color("d8b45a"), Vector3(0, 0.33, 0))  # a gold spike


func _piece() -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	add_child(n)
	_kit.append(n)
	return n


## Moves the raider. Returns true when it strikes `target` this frame.
## Raiders ignore fires and daylight. Camp guards go back to camp when you
## run too far from it.
func tick(delta: float, target: Vector2, _fires: Array, _night: bool) -> bool:
	if dead:
		_body.tick(delta)
		return false
	bite_cooldown = maxf(bite_cooldown - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	var goal := target
	var hunting := true
	if home != Vector2.INF and (target.distance_to(home) > GUARD_LEASH or pos.distance_to(home) > GUARD_LEASH * 1.2):
		goal = home
		hunting = false
	var to_goal := goal - pos
	_moving = to_goal.length() > (14.0 if hunting else 20.0)
	if to_goal.length() > 1.0:
		facing = to_goal.normalized()
	var heading := facing
	_detour = maxf(_detour - delta, 0.0)
	if _detour > 0.0:
		heading = (facing + _detour_dir * 1.6).normalized()
	var velocity := (heading * speed if _moving else Vector2.ZERO) + knock
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	var before := pos
	_slide(velocity * delta)
	# A purge raider stuck on a tree or rock (not a wall: walls get hacked) steps around it.
	if purge and _moving and _detour <= 0.0 and blocked_cell == Vector2i(-1, -1) \
			and pos.distance_to(before) < speed * delta * 0.3:
		_detour = 0.8
		_detour_dir = facing.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	_animate(delta)
	if hunting and bite_cooldown <= 0.0 and pos.distance_to(target) < 18.0:
		bite_cooldown = 1.1
		_body.play_once("attack", 1.7)
		return true
	return false


func _animate(delta: float) -> void:
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 10.0, 1.0))
	_body.tick(delta)
	_body.play("run" if _moving else "idle")
	_body.flash(hurt_flash > 0.0)
	var turn := Basis(Vector3.UP, _model.rotation.y)
	if _right_hand:
		_axe.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, 0.6), _right_hand.global_position)
	if _left_hand:
		_shield.global_transform = Transform3D(turn, _left_hand.global_position + turn * Vector3(0.04, 0.05, 0.12))
	if _head and _helmet:
		_helmet.global_transform = Transform3D(turn, _head.global_position + Vector3(0, 0.05, 0))


func die() -> float:
	for piece in _kit:
		(piece as Node3D).visible = false
	return super.die()
