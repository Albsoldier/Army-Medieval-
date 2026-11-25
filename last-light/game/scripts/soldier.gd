## A soldier in your army: a legionary, archer, cavalryman or centurion.
## Follows you in formation, guards a spot, or holds where you send it, and
## fights wolves. Soldiers have names and rise through the ranks with kills.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const Wolf = preload("res://scripts/wolf.gd")
const SURVIVOR := preload("res://models/adventurer.glb")
const Horse = preload("res://scripts/horse.gd")

const MAX_ARMY := 100
const PER_BARRACKS := 10
const DRAW_DISTANCE := 720.0  # game pixels (45 m): farther soldiers aren't drawn or animated
const INSPIRE_RADIUS := 110.0
const WORK_STROKE := 2.0  # seconds between strokes of work  # a centurion makes soldiers this close fight harder

## Unit types. Costs are paid at a barracks.
const KINDS := {
	"legionary": {"name": "Legionary", "hp": 60.0, "damage": 1, "reach": 26.0, "cooldown": 0.8, "speed": 92.0,
		"sight": 170.0, "cost": {"wood": 3, "stone": 2, "berries": 5},
		"about": "Shield and spear: the backbone of the legion."},
	"archer": {"name": "Archer", "hp": 40.0, "damage": 1, "reach": 130.0, "cooldown": 1.3, "speed": 95.0,
		"sight": 200.0, "cost": {"wood": 6, "berries": 5},
		"about": "Shoots wolves from a distance. Best behind the line or on the walls."},
	"cavalry": {"name": "Cavalry", "hp": 90.0, "damage": 2, "reach": 30.0, "cooldown": 0.9, "speed": 150.0,
		"sight": 260.0, "cost": {"wood": 6, "berries": 12, "hide": 2},
		"about": "Fast riders who run wolves down."},
	"centurion": {"name": "Centurion", "hp": 110.0, "damage": 2, "reach": 26.0, "cooldown": 0.8, "speed": 92.0,
		"sight": 170.0, "cost": {"iron": 3, "gold": 1, "berries": 5},
		"about": "An officer. Soldiers near him hit harder (+1) and heal faster. One per barracks."},
}
## Front to back in a formation.
const KIND_ORDER := ["centurion", "legionary", "cavalry", "archer"]
## [rank name, kills needed]. Each rank adds 20% health; Elite and Hero hit harder.
const RANKS := [["Recruit", 0], ["Veteran", 3], ["Elite", 8], ["Hero", 15]]
const FORMATIONS := ["line", "shield wall", "wedge"]
const PRAENOMINA := ["Marcus", "Gaius", "Lucius", "Titus", "Quintus", "Publius", "Gnaeus", "Aulus", "Decimus",
	"Sextus", "Servius", "Tiberius", "Manius", "Spurius", "Numerius", "Appius", "Kaeso", "Vibius"]
const NOMINA := ["Varro", "Cassius", "Flavius", "Junius", "Valerius", "Antonius", "Cornelius", "Aurelius",
	"Fabius", "Licinius", "Claudius", "Domitius", "Sulpicius", "Pompeius", "Octavius", "Marius", "Vettius",
	"Sertorius", "Calpurnius", "Petronius", "Rufus", "Naso", "Crassus", "Brutus"]

var world: World
var kind := "legionary"
var soldier_name := ""
var kills := 0
var pos := Vector2.ZERO
var hp := 60.0
## "follow" (behind you in formation), "guard" (rings round a point),
## "hold" (in formation at a point you sent them to) or "work" (at a job).
var mode := "follow"
## Workers: "wood", "stone" or "farm", and what they're working on.
var job := ""
var work_at := Vector2.ZERO
var worked := false  # finished a stroke of work this frame
var guard_point := Vector2.ZERO  # the guard or hold point
var order_facing := Vector2.UP  # which way a holding group faces
var formation := "line"
var slot := 0  # place in the formation
var group_size := 1  # how many share the formation
var facing := Vector2.DOWN
var dead := false
var inspired := false  # a centurion is close
var selected := false
var ranked_up := ""  # the new rank, for one frame after a promotion

var _model: Node3D
var _body: CharacterModel
var _right_hand: Node3D
var _left_hand: Node3D
var _head: Node3D
var _kit: Array = []  # top-level pieces that follow the body
var _shield: Node3D
var _helmet: Node3D
var _spear: Node3D
var _bow: Node3D
var _horse: Node3D
var _horse_look: Dictionary = {}
var _ring: MeshInstance3D
var _label: Label3D
var _cooldown := 0.0
var _hurt := 0.0
var _moving := false
var _shown := true
var _thrust := 0.0
var _detour_time := 0.0
var _detour_side := 1.0
var _work_timer := 1.0


static func info(k: String) -> Dictionary:
	return KINDS.get(k, KINDS["legionary"])


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [PRAENOMINA[rng.randi() % PRAENOMINA.size()], NOMINA[rng.randi() % NOMINA.size()]]


static func rank_for(kill_count: int) -> int:
	var r := 0
	for i in RANKS.size():
		if kill_count >= int(RANKS[i][1]):
			r = i
	return r


func rank() -> int:
	return rank_for(kills)


func rank_name() -> String:
	return str(RANKS[rank()][0])


func title() -> String:
	return "%s %s, %s" % [rank_name(), soldier_name, str(info(kind)["name"]).to_lower()]


func max_hp() -> float:
	return float(info(kind)["hp"]) * (1.0 + 0.2 * rank())


func damage() -> int:
	var r := rank()
	return int(info(kind)["damage"]) + (1 if inspired else 0) + (1 if r >= 2 else 0) + (1 if r >= 3 else 0)


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	var tunic := {"legionary": "8b2e2e", "archer": "4f5d2f", "cavalry": "7a2a3a", "centurion": "6e1f1f"}
	var cloth := Color(tunic.get(kind, "8b2e2e"))
	_body.build(SURVIVOR, 1.62, false, {
		"idle": ["Man_Idle", "Idle"], "run": ["Man_Run", "Run"], "slash": ["Man_SwordSlash", "Sword_Slash"],
		"death": ["Man_Death", "Death"],
	}, {"Shirt": {"color": cloth}, "Green": {"color": cloth}, "LightGreen": {"color": cloth.lightened(0.12)},
		"Pants": {"color": Color("3a2a1a")}, "Brown": {"color": Color("3a2a1a")}})
	_right_hand = _body.bone_follower("Palm.R")
	_left_hand = _body.bone_follower("Palm.L")
	_head = _body.bone_follower("Head")
	match kind:
		"archer":
			_build_archer()
		"cavalry":
			_build_horse()
			_build_helmet(Color("8f8f95"), false)
			_build_spear()
		"centurion":
			_build_helmet(Color("b8b8bf"), true)
			_build_shield(Color("6e1f1f"))
			_build_spear()
			var cloak := Art.part(_model, Art.box(Vector3(0.42, 0.75, 0.04)), Color("9e2a24"), Vector3(0, 0.95, -0.17), Vector3(0.12, 0, 0))
			cloak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_:
			_build_helmet(Color("a07a3a"), false)
			_build_shield(Color("8e2323"))
			_build_spear()
	# Each piece of kit is one mesh (fewer draw calls), and so are the pieces
	# worn on the body (a cloak, a quiver of arrows).
	# Every soldier of a kind wears the same kit, so they share the merged meshes.
	for i in _kit.size():
		Art.bake(_kit[i], Art.parts_of(_kit[i]), "kit:%s:%d" % [kind, i])
	Art.bake(_model, Art.parts_of(_model), "worn:" + kind)
	# With up to a hundred soldiers, shadows cost too much.
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring = Art.part(self, _ring_mesh(), Color(0.45, 1.0, 0.45), Vector3(0, 0.06, 0), Vector3.ZERO, 0.0, true)
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0, 2.5 if kind == "cavalry" else 2.15, 0)
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)
	hp = minf(hp, max_hp())
	position = world.to_3d(pos)


static func _ring_mesh() -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.52
	torus.rings = 16
	torus.ring_segments = 4
	return torus


## Moves and fights. `leader`/`leader_facing` are where you are and face.
## Returns a wolf this soldier killed this frame, or null.
func tick(delta: float, leader: Vector2, leader_facing: Vector2, wolves: Array) -> Wolf:
	ranked_up = ""
	worked = false
	if dead:
		_body.tick(delta)
		return null
	var stats := info(kind)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_thrust = maxf(_thrust - delta * 4.0, 0.0)
	hp = minf(hp + delta * (2.5 if inspired else 1.0), max_hp())

	var home := _post(leader, leader_facing)
	var sight: float = stats["sight"]
	var reach: float = stats["reach"]
	var target: Wolf = null
	var best := sight
	for wolf in wolves:
		var d: float = wolf.pos.distance_to(pos)
		# Guards and holding groups don't chase far from their post.
		if d < best and (mode == "follow" or wolf.pos.distance_to(guard_point) < sight * 1.3):
			best = d
			target = wolf

	var killed: Wolf = null
	var goal := home
	if target != null:
		goal = target.pos
		var dist := pos.distance_to(target.pos)
		if dist <= reach:
			goal = pos
			facing = (target.pos - pos).normalized()
			if _cooldown <= 0.0:
				_cooldown = float(stats["cooldown"])
				_strike(target)
				target.hurt(damage(), pos)
				if target.hp <= 0:
					killed = target
					_add_kill()
		elif kind == "archer":
			# Archers close in only until the wolf is in range.
			goal = pos + (target.pos - pos).normalized() * (dist - reach * 0.85)
	_move_toward(goal, delta, (4.0 if mode == "work" else 10.0) if target == null else 2.0, float(stats["speed"]))
	# Workers swing their axe, pick or hoe when they're at the job.
	if mode == "work" and target == null and pos.distance_to(home) < 8.0:
		if work_at.distance_to(pos) > 1.0:
			facing = (work_at - pos).normalized()
		_work_timer -= delta
		if _work_timer <= 0.0:
			_work_timer = WORK_STROKE
			_body.play_once("slash", 1.1)
			worked = true
	_animate(delta)
	return killed


func _add_kill() -> void:
	var before := rank()
	kills += 1
	if rank() > before:
		ranked_up = rank_name()
		hp = max_hp()
		_update_label()


func _strike(target: Wolf) -> void:
	match kind:
		"archer":
			_body.play_once("slash", 2.2)
			_shoot(target.position + Vector3(0, 0.4, 0))
		"cavalry":
			_thrust = 1.0  # a lance thrust from the saddle
		_:
			_body.play_once("slash", 1.6)


## An arrow that flies to the target (the hit itself is instant).
func _shoot(at: Vector3) -> void:
	var arrow := Node3D.new()
	arrow.top_level = true
	add_child(arrow)
	Art.part(arrow, Art.cylinder(0.012, 0.012, 0.7, 4), Color("caa472"), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	Art.part(arrow, Art.cylinder(0.0, 0.03, 0.08, 4), Color("8a8f95"), Vector3(0, 0, 0.38), Vector3(PI / 2, 0, 0))
	var from := global_position + Vector3(0, 1.35, 0)
	arrow.global_position = from
	if from.distance_to(at) > 0.1:
		arrow.look_at(at, Vector3.UP, true)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "global_position", at, clampf(from.distance_to(at) / 30.0, 0.08, 0.4))
	tween.tween_callback(arrow.queue_free)


func hurt(amount: float) -> bool:
	hp -= amount
	_hurt = 0.2
	if hp <= 0.0 and not dead:
		dead = true
		selected = false
		for piece in _kit:
			(piece as Node3D).visible = false
		_ring.visible = false
		_label.visible = false
		_body.flash(false)
		_body.play_once("death")
		return true
	return false


var show_name := false  # name tags only when few are picked, or for veterans


func set_selected(on: bool, with_name: bool = true) -> void:
	selected = on and not dead
	show_name = with_name
	_ring.visible = selected and _shown
	_update_label()


func _update_label() -> void:
	_label.text = "%s\n%s" % [soldier_name, rank_name()] if rank() > 0 else soldier_name
	_label.modulate = Color(1.0, 0.85, 0.4) if rank() >= 2 else Color(1, 1, 1)
	_label.visible = selected and show_name and _shown


## Where this soldier should stand.
func _post(leader: Vector2, leader_facing: Vector2) -> Vector2:
	if mode == "work":
		return guard_point
	if mode == "guard":
		# Rings around the guard point: 6 soldiers in the first ring, 12 in the next, and so on.
		var ring := 1
		var index := slot
		while index >= ring * 6:
			index -= ring * 6
			ring += 1
		var angle := index * TAU / (ring * 6) + ring * 0.5
		return guard_point + Vector2.from_angle(angle) * (18.0 * ring)
	var spot := formation_offset(slot, group_size, formation)  # x: to the side, y: rows back
	if mode == "hold":
		var ahead := order_facing.normalized() if order_facing.length() > 0.1 else Vector2.UP
		return guard_point - ahead * spot.y + ahead.orthogonal() * spot.x
	var back := -leader_facing.normalized() if leader_facing.length() > 0.1 else Vector2.UP
	return leader + back * (22.0 + spot.y) + back.orthogonal() * spot.x


## A place in a formation, in game pixels: x is to the side of the centre,
## y is how far behind the front row.
static func formation_offset(i: int, n: int, shape: String) -> Vector2:
	match shape:
		"shield wall":
			# A tight block, shoulder to shoulder.
			var cols := maxi(int(ceil(sqrt(float(maxi(n, 1))))), 1)
			var row := i / cols
			var in_row := mini(n - row * cols, cols)
			return Vector2((float(i % cols) - (in_row - 1) / 2.0) * 10.0, row * 10.0)
		"wedge":
			# A point at the front, widening row by row.
			var row := 0
			var first := 0
			while first + row + 1 <= i:
				first += row + 1
				row += 1
			return Vector2((float(i - first) - row / 2.0) * 14.0, row * 13.0)
	# Line: ranks of ten.
	var r := i / 10
	var in_line := mini(n - r * 10, 10)
	return Vector2((float(i % 10) - (in_line - 1) / 2.0) * 14.0, r * 16.0)


func _move_toward(goal: Vector2, delta: float, stop_at: float, speed: float) -> void:
	var to_goal := goal - pos
	_moving = to_goal.length() > stop_at
	if not _moving:
		if mode == "hold" and order_facing.length() > 0.1:
			facing = order_facing.normalized()
		return
	facing = to_goal.normalized()
	var pace := speed * (1.4 if to_goal.length() > 120.0 else 1.0)
	var step := facing * minf(pace * delta, to_goal.length())
	var before := pos
	var next_x := pos + Vector2(step.x, 0)
	if world.is_walkable(next_x):
		pos = next_x
	var next_y := pos + Vector2(0, step.y)
	if world.is_walkable(next_y):
		pos = next_y
	if pos.distance_to(before) < step.length() * 0.3:
		# Blocked by a tree or a rock: step round it, keeping to one side.
		if _detour_time <= 0.0:
			_detour_side = 1.0 if (slot + int(Time.get_ticks_msec() / 2000)) % 2 == 0 else -1.0
		_detour_time = 0.6
	if _detour_time > 0.0:
		_detour_time -= delta
		var around := pos + facing.orthogonal() * _detour_side * pace * delta
		if world.is_walkable(around):
			pos = around
		else:
			_detour_side = -_detour_side
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


# ---------- Looks ----------

func _build_helmet(metal: Color, transverse: bool) -> void:
	_helmet = _piece()
	var dome := Art.part(_helmet, Art.sphere(0.155, 6, 12), metal, Vector3(0, 0.1, -0.01))
	dome.scale = Vector3(1.0, 0.9, 1.08)
	Art.part(_helmet, Art.box(Vector3(0.34, 0.03, 0.04)), metal.darkened(0.15), Vector3(0, 0.02, -0.15))  # neck guard
	if transverse:
		# A centurion's crest runs side to side.
		Art.part(_helmet, Art.box(Vector3(0.42, 0.13, 0.05)), Color("c42f2a"), Vector3(0, 0.28, 0.0))
	else:
		Art.part(_helmet, Art.box(Vector3(0.045, 0.12, 0.3)), Color("a32626"), Vector3(0, 0.27, -0.02))


## A tall red shield with gold trim.
func _build_shield(color: Color) -> void:
	_shield = _piece()
	Art.part(_shield, Art.box(Vector3(0.52, 0.86, 0.05)), color, Vector3.ZERO)
	Art.part(_shield, Art.box(Vector3(0.56, 0.05, 0.06)), Color("c9a24a"), Vector3(0, 0.42, 0))
	Art.part(_shield, Art.box(Vector3(0.56, 0.05, 0.06)), Color("c9a24a"), Vector3(0, -0.42, 0))
	Art.part(_shield, Art.box(Vector3(0.04, 0.8, 0.06)), Color("c9a24a"), Vector3(0, 0, 0.005))
	Art.part(_shield, Art.sphere(0.075, 5, 8), Color("d8b45a"), Vector3(0, 0, 0.04), Vector3.ZERO, 0.4)


func _build_spear() -> void:
	_spear = _piece()
	var length := 2.2 if kind == "cavalry" else 1.6
	Art.part(_spear, Art.cylinder(0.022, 0.022, length, 5), Color("caa472"), Vector3(0, length * 0.19, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.2, 5), Color("c9ccd1"), Vector3(0, length * 0.69 + 0.1, 0))


## A leather cap, a bow and a quiver of arrows.
func _build_archer() -> void:
	_helmet = _piece()
	var cap := Art.part(_helmet, Art.sphere(0.15, 5, 10), Color("6b4a2b"), Vector3(0, 0.08, -0.01))
	cap.scale = Vector3(1.0, 0.75, 1.05)
	_bow = _piece()
	for i in 5:
		var a := (i - 2) * 0.32
		Art.part(_bow, Art.box(Vector3(0.03, 0.24, 0.03)), Color("6b4a2b"), Vector3(0, sin(a) * 0.55, (cos(a) - 1.0) * 0.18 + 0.06), Vector3(-a, 0, 0))
	Art.part(_bow, Art.box(Vector3(0.006, 1.05, 0.006)), Color("e8e0cc"), Vector3(0, 0, -0.1))  # string
	var quiver := Art.part(_model, Art.cylinder(0.07, 0.06, 0.55, 6), Color("5a3d22"), Vector3(0.12, 1.15, -0.18), Vector3(0.3, 0, 0.2))
	quiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 3:
		Art.part(_model, Art.cylinder(0.008, 0.008, 0.25, 4), Color("e0dccf"), Vector3(0.1 + i * 0.03, 1.48, -0.25), Vector3(0.3, 0, 0.2))


## The horse a cavalryman rides (horse.gd).
func _build_horse() -> void:
	_horse = Node3D.new()
	_model.add_child(_horse)
	_horse_look = Horse.build_model(_horse, Horse.COATS[randi() % Horse.COATS.size()], true)
	_body.position = Vector3(0, 0.62, -0.05)


func _piece() -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	add_child(n)
	_kit.append(n)
	return n


## Hides soldiers far from the player so a big army stays fast.
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	_model.visible = shown
	for piece in _kit:
		(piece as Node3D).visible = shown and not dead
	_ring.visible = shown and selected
	_label.visible = shown and selected and show_name
	if _body.anim:
		_body.anim.active = shown


func _animate(delta: float) -> void:
	if not _shown:
		return
	position = world.to_3d(pos)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 10.0, 1.0))
	_body.tick(delta)
	if kind == "cavalry":
		_body.play("idle")
		Horse.animate(_horse_look, delta, 1.0 if _moving else 0.0)
		_body.position = Vector3(0, maxf(Horse.saddle_height(_horse_look) - 0.84, 0.2), -0.05)
	else:
		_body.play("run" if _moving else "idle")
	_body.flash(_hurt > 0.0)
	var turn := Basis(Vector3.UP, _model.rotation.y)
	if _spear and _right_hand:
		if kind == "cavalry":
			# A lance held level, thrust forward when striking.
			_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.08), _right_hand.global_position + turn * Vector3(0, 0, 0.5 * _thrust))
		else:
			_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.3), _right_hand.global_position)
	if _shield and _left_hand:
		# Held in front, slightly turned; a shield wall locks them square.
		var angle := 0.0 if formation == "shield wall" and mode != "guard" else 0.35
		_shield.global_transform = Transform3D(turn * Basis(Vector3.UP, angle), _left_hand.global_position + turn * Vector3(0.05, 0.05, 0.14))
	if _bow and _left_hand:
		_bow.global_transform = Transform3D(turn * Basis(Vector3.UP, PI / 2), _left_hand.global_position)
	if _helmet and _head:
		_helmet.global_transform = Transform3D(turn, _head.global_position + Vector3(0, 0.06, 0))
