## A soldier in your army. Follows you or guards a spot, and fights wolves.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const Wolf = preload("res://scripts/wolf.gd")
const SURVIVOR := preload("res://models/survivor.glb")

const SPEED := 92.0
const MAX_HP := 60.0
const SIGHT := 170.0  # how far a soldier looks for wolves, in game pixels
const REACH := 26.0
const ATTACK_DAMAGE := 1
const ATTACK_COOLDOWN := 0.8
const MAX_ARMY := 100
const PER_BARRACKS := 10
const ROW := 10  # soldiers per row when following
const DRAW_DISTANCE := 720.0  # game pixels (45 m): farther soldiers aren't drawn or animated

var world: World
var pos := Vector2.ZERO
var hp := MAX_HP
var mode := "follow"  # "follow" or "guard"
var guard_point := Vector2.ZERO
var slot := 0  # place in the formation behind the player
var facing := Vector2.DOWN
var dead := false

var _model: Node3D
var _body: CharacterModel
var _right_hand: Node3D
var _spear: Node3D
var _cooldown := 0.0
var _hurt := 0.0
var _moving := false
var _shown := true


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(SURVIVOR, 1.62, false, {
		"idle": ["Man_Idle"], "run": ["Man_Run"], "slash": ["Man_SwordSlash"], "death": ["Man_Death"],
	}, {"Shirt": {"color": Color("8b2e2e")}, "Pants": {"color": Color("3a2a1a")}})  # red tunic
	_right_hand = _body.bone_follower("Palm.R")
	# With up to a hundred soldiers, shadows cost too much.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spear = Node3D.new()
	_spear.top_level = true
	add_child(_spear)
	Art.part(_spear, Art.cylinder(0.022, 0.022, 1.6, 5), Color("caa472"), Vector3(0, 0.3, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.2, 5), Color("c9ccd1"), Vector3(0, 1.2, 0))
	position = world.to_3d(pos)


## Moves and fights. `wolves` are the living wolves. Returns a wolf this soldier
## killed this frame, or null.
func tick(delta: float, leader: Vector2, leader_facing: Vector2, wolves: Array) -> Wolf:
	if dead:
		_body.tick(delta)
		return null
	_cooldown = maxf(_cooldown - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	hp = minf(hp + delta * 1.0, MAX_HP)

	var home := _post(leader, leader_facing)
	var target: Wolf = null
	var best := SIGHT
	for wolf in wolves:
		var d: float = wolf.pos.distance_to(pos)
		# Guards don't chase too far from their post.
		if d < best and (mode == "follow" or wolf.pos.distance_to(guard_point) < SIGHT * 1.3):
			best = d
			target = wolf

	var killed: Wolf = null
	var goal := home
	if target != null:
		goal = target.pos
		if pos.distance_to(target.pos) <= REACH:
			goal = pos
			facing = (target.pos - pos).normalized()
			if _cooldown <= 0.0:
				_cooldown = ATTACK_COOLDOWN
				_body.play_once("slash", 1.6)
				target.hurt(ATTACK_DAMAGE, pos)
				if target.hp <= 0:
					killed = target
	_move_toward(goal, delta, 10.0 if target == null else 2.0)
	_animate(delta)
	return killed


func hurt(amount: float) -> bool:
	hp -= amount
	_hurt = 0.2
	if hp <= 0.0 and not dead:
		dead = true
		_spear.visible = false
		_body.flash(false)
		_body.play_once("death")
		return true
	return false


func _post(leader: Vector2, leader_facing: Vector2) -> Vector2:
	if mode == "guard":
		# Rings around the guard point: 6 soldiers in the first ring, 12 in the next, and so on.
		var ring := 1
		var index := slot
		while index >= ring * 6:
			index -= ring * 6
			ring += 1
		var angle := index * TAU / (ring * 6) + ring * 0.5
		return guard_point + Vector2.from_angle(angle) * (18.0 * ring)
	# Follow in rows of ROW behind the player.
	var back := -leader_facing.normalized() if leader_facing.length() > 0.1 else Vector2.UP
	var side := back.orthogonal()
	var row := 1 + slot / ROW
	var col := float(slot % ROW) - (ROW - 1) / 2.0
	return leader + back * (16.0 * row + 6.0) + side * (14.0 * col)


func _move_toward(goal: Vector2, delta: float, stop_at: float) -> void:
	var to_goal := goal - pos
	_moving = to_goal.length() > stop_at
	if not _moving:
		return
	facing = to_goal.normalized()
	var speed := SPEED * (1.4 if to_goal.length() > 120.0 else 1.0)
	var step := facing * minf(speed * delta, to_goal.length())
	var next_x := pos + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		pos = next_x
	var next_y := pos + Vector2(0, step.y)
	if world.is_walkable(next_y):
		pos = next_y
	# Stuck far behind (behind a wall, across water): catch up with the player,
	# landing on solid ground near your place in the formation.
	if mode == "follow" and to_goal.length() > 400.0:
		var landing := goal
		if not world.is_walkable(landing):
			var rng := RandomNumberGenerator.new()
			rng.seed = slot * 7919 + 1
			landing = world.random_walkable_near(goal, 4.0, 60.0, rng)
		if landing != Vector2.INF and world.is_walkable(landing):
			pos = landing


## Hides soldiers far from the player so a big army stays fast.
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	_model.visible = shown
	_spear.visible = shown and not dead
	if _body.anim:
		_body.anim.active = shown


func _animate(delta: float) -> void:
	if not _shown:
		return
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 10.0, 1.0))
	_body.tick(delta)
	_body.play("run" if _moving else "idle")
	_body.flash(_hurt > 0.0)
	if _right_hand:
		var turn := Basis(Vector3.UP, _model.rotation.y)
		_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.3), _right_hand.global_position)
