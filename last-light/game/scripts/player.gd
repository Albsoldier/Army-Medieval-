## The survivor: position, survival stats, inventory and the 3D model.
## `pos` is the position on the game grid (pixels); the model follows it.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
const Gear = preload("res://scripts/gear.gd")
const Horse = preload("res://scripts/horse.gd")
const RIDE_SPEED := 1.9  # how much faster you go on horseback
const HIPS := 0.84  # how high a standing survivor's hips are (for sitting in a saddle)

const SPEED := 95.0
const SPRINT := 1.5  # how much faster you go sprinting (Shift)
const MAX_STAMINA := 100.0
const SPRINT_COST := 20.0  # stamina per second of sprinting
const SWING_COST := 6.0  # stamina per attack
const TORCH_RADIUS := 85.0

var world: World
var pos := Vector2.ZERO
var health := 100.0
var hunger := 100.0
var warmth := 100.0
var sanity := 100.0
var stamina := MAX_STAMINA
var sprinting := false  # sprinting this frame
var _winded := false  # ran out: no sprinting until stamina recovers a little
var _rest_time := 0.0  # seconds since stamina was last spent
var inventory := {"wood": 0, "stone": 0, "berries": 0, "raw_meat": 0, "cooked_meat": 0,
	"smoked_meat": 0, "ore": 0, "iron": 0, "hide": 0, "salve": 0, "gold": 0, "steel": 0, "wheat": 0, "bread": 0}
## Your best spear, sword and armour, as tiers in gear.gd (-1: none).
var spear_tier := -1
var sword_tier := -1
var armour_tier := -1
var has_axe := false
var has_pickaxe := false
var lantern := false
## Older saves stored "has a spear", "has an iron spear" and "has armour".
var has_spear: bool:
	get:
		return spear_tier >= 0
	set(v):
		spear_tier = maxi(spear_tier, 1) if v else -1
var iron_spear: bool:
	get:
		return spear_tier >= 2
	set(v):
		if v:
			spear_tier = maxi(spear_tier, 2)
var armour: bool:
	get:
		return armour_tier >= 0
	set(v):
		armour_tier = maxi(armour_tier, 1) if v else -1
## What's in your hand: "hands", "spear", "axe", "pickaxe" or "sword" (the hotbar).
var equipped := "hands"
var armour_on := true  # armour can be taken off in the inventory
var lantern_on := true  # and the lantern shuttered
var torch_time := 0.0
var first_person := false
## Afloat: set by main.gd while you're on a boat.
var on_boat := false
var riding := false  # on horseback (set with mount())
var _mount: Node3D
var _mount_look: Dictionary = {}
var _saddle := 0.0  # how much higher you sit on your horse
var boat_deep := false  # a galley can cross the deep sea
var boat_speed := 1.0
var deck_height := 0.2  # set with set_first_person()
var facing := Vector2.DOWN
var hurt_flash := 0.0
var swing_time := 0.0

const CharacterModel = preload("res://scripts/character_model.gd")
const SURVIVOR := preload("res://models/adventurer.glb")

var dead := false
var _model: Node3D  # turns to face the walking direction
var _body: CharacterModel
var _right_hand: Node3D
var _left_hand: Node3D
var _spear: Node3D
var _sword: Node3D
var _gear_look := ""  # which tiers the models are coloured for
var _axe: Node3D
var _pickaxe: Node3D
var _armour: Node3D
var _torso: Node3D
var _fp_swing := 0.0  # first-person swing animation, counts down from 1
var _bob := 0.0
var _neck: Node3D
var _torch: Node3D
var _torch_light: OmniLight3D
var _moving := false
var _moving_last := false
var _lantern: Node3D


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_body = CharacterModel.new()
	_model.add_child(_body)
	_body.build(SURVIVOR, 1.62, false, {
		"idle": ["Man_Idle", "Idle"],
		"walk": ["Man_Walk", "Walk"],
		"run": ["Man_Run", "Run"],
		"punch": ["Man_Punch", "Punch_Right"],
		"slash": ["Man_SwordSlash", "Sword_Slash"],
		"death": ["Man_Death", "Death"],
	}, {"Shirt": {"color": Color("3b4f35")}})  # a dark green field jacket
	_right_hand = _body.bone_follower("Palm.R")
	_left_hand = _body.bone_follower("Palm.L")
	_torso = _body.bone_follower("Torso")
	_neck = _body.bone_follower("Neck")

	# Spear and torch follow the hands but keep their own size and direction.
	_spear = Node3D.new()
	_spear.top_level = true
	add_child(_spear)
	Art.part(_spear, Art.cylinder(0.022, 0.022, 1.6, 5), Color("caa472"), Vector3(0, 0.3, 0))
	Art.part(_spear, Art.cylinder(0.0, 0.05, 0.2, 5), Color("c9ccd1"), Vector3(0, 1.2, 0))
	_spear.visible = false

	# The sword: a straight blade, a cross-guard and a wrapped grip.
	_sword = Node3D.new()
	_sword.top_level = true
	add_child(_sword)
	Art.part(_sword, Art.box(Vector3(0.05, 0.75, 0.012)), Color("9ea2a8"), Vector3(0, 0.5, 0))
	Art.part(_sword, Art.cylinder(0.0, 0.025, 0.08, 4), Color("9ea2a8"), Vector3(0, 0.91, 0))
	Art.part(_sword, Art.box(Vector3(0.2, 0.035, 0.04)), Color("5a3d22"), Vector3(0, 0.12, 0))
	Art.part(_sword, Art.cylinder(0.018, 0.018, 0.16, 5), Color("3d2a18"), Vector3(0, 0.03, 0))
	Art.part(_sword, Art.sphere(0.03, 3, 6), Color("5a3d22"), Vector3(0, -0.06, 0))
	_sword.visible = false

	# The axe: a short haft with an iron head on one side.
	_axe = Node3D.new()
	_axe.top_level = true
	add_child(_axe)
	Art.part(_axe, Art.cylinder(0.03, 0.03, 0.85, 6), Color("a07548"), Vector3(0, 0.3, 0))
	Art.part(_axe, Art.box(Vector3(0.06, 0.22, 0.28)), Color("c4c8ce"), Vector3(0, 0.62, 0.13))
	_axe.visible = false

	# The pickaxe: a haft with a curved iron head across the top.
	_pickaxe = Node3D.new()
	_pickaxe.top_level = true
	add_child(_pickaxe)
	Art.part(_pickaxe, Art.cylinder(0.03, 0.03, 0.85, 6), Color("8f6640"), Vector3(0, 0.3, 0))
	Art.part(_pickaxe, Art.box(Vector3(0.07, 0.08, 0.62)), Color("b9bdc3"), Vector3(0, 0.7, 0))
	_pickaxe.visible = false

	# Worn iron armour: a breastplate and shoulder guards that follow the chest.
	_armour = Node3D.new()
	_armour.top_level = true
	add_child(_armour)
	Art.part(_armour, Art.box(Vector3(0.3, 0.26, 0.08)), Color("7d8186"), Vector3(0, 0, 0.1))
	Art.part(_armour, Art.box(Vector3(0.3, 0.26, 0.06)), Color("6a6e73"), Vector3(0, 0, -0.1))
	Art.part(_armour, Art.box(Vector3(0.12, 0.05, 0.2)), Color("8c9095"), Vector3(0.19, 0.14, 0))
	Art.part(_armour, Art.box(Vector3(0.12, 0.05, 0.2)), Color("8c9095"), Vector3(-0.19, 0.14, 0))
	_armour.visible = false

	_torch = Node3D.new()
	_torch.top_level = true
	add_child(_torch)
	Art.part(_torch, Art.cylinder(0.03, 0.025, 0.55, 5), Color("6b4a2b"), Vector3(0, 0.12, 0))
	Art.part(_torch, Art.sphere(0.08, 3, 6), Color(1.0, 0.65, 0.2), Vector3(0, 0.44, 0), Vector3.ZERO, 4.0, true)
	_torch_light = Art.omni(Color(1.0, 0.72, 0.4), TORCH_RADIUS / World.TILE * 1.3, 2.2)
	_torch_light.position = Vector3(0, 0.6, 0)
	_torch.add_child(_torch_light)
	_torch.visible = false

	# The lantern hangs at the hip and lights the way for good.
	_lantern = Node3D.new()
	_lantern.position = Vector3(-0.2, 0.75, 0.15)
	_model.add_child(_lantern)
	Art.part(_lantern, Art.box(Vector3(0.12, 0.16, 0.12)), Color(1.0, 0.8, 0.4), Vector3.ZERO, Vector3.ZERO, 3.0, true)
	Art.part(_lantern, Art.cylinder(0.08, 0.08, 0.03, 6), Color("2e2e30"), Vector3(0, 0.1, 0))
	var lantern_light := Art.omni(Color(1.0, 0.82, 0.55), TORCH_RADIUS / World.TILE * 1.1, 1.6)
	lantern_light.position = Vector3(0, 0.6, 0)
	_lantern.add_child(lantern_light)
	_lantern.visible = false

	# A faint glow so you can always see yourself at night.
	var glow := Art.omni(Color(0.6, 0.7, 1.0), 2.6, 0.35)
	glow.position = Vector3(0, 1.9, 0)
	add_child(glow)
	position = ground_point()


func move(dir: Vector2, delta: float, sprint: bool = false) -> void:
	_moving = dir != Vector2.ZERO and not dead
	sprinting = sprint and _moving and not on_boat and not _winded and stamina > 0.0
	if sprinting:
		spend_stamina(SPRINT_COST * delta)
	if not _moving:
		return
	facing = dir.normalized()
	var pace := boat_speed if on_boat else (RIDE_SPEED if riding else 1.0)
	if sprinting:
		pace *= SPRINT
	var step := facing * SPEED * pace * delta
	var next_x := pos + Vector2(step.x, 0)
	if _can_be_at(next_x):
		pos = next_x
	var next_y := pos + Vector2(0, step.y)
	if _can_be_at(next_y):
		pos = next_y


## Gets on a horse of the given coat colour, or off it (coat ignored).
func mount(on: bool, coat_color: Color = Color.BLACK) -> void:
	riding = on
	if _mount:
		_mount.queue_free()
		_mount = null
		_mount_look = {}
	if on:
		_mount = Node3D.new()
		_model.add_child(_mount)
		_mount_look = Horse.build_model(_mount, coat_color, true)
		if first_person:
			for mi in _mount.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Hips on the saddle: the legs hang down either side.
	_saddle = 0.62 if on else 0.0  # refined from the horse's back each frame
	_body.position = Vector3(0, _saddle, -0.05) if on else Vector3.ZERO


## How far above the ground your eyes are lifted (by a horse).
func ride_height() -> float:
	return _saddle if riding else 0.0


## Uses up stamina. Running out leaves you winded until it recovers to 25.
func spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_rest_time = 0.0
	if stamina <= 0.0:
		_winded = true


## Stamina comes back after a moment's rest: fastest standing still, slower
## when you're starving.
func recover_stamina(delta: float) -> void:
	_rest_time += delta
	if _rest_time < 0.8:
		return
	var rate := 22.0 if not _moving_last else 12.0
	if hunger < 20.0:
		rate *= 0.5
	stamina = minf(stamina + rate * delta, MAX_STAMINA)
	if _winded and stamina >= 25.0:
		_winded = false


func is_winded() -> bool:
	return _winded


func _can_be_at(p: Vector2) -> bool:
	return world.is_sailable(p, boat_deep) if on_boat else world.is_walkable(p)


## Where the survivor stands in 3D: on the ground, or on the deck of a boat.
func ground_point() -> Vector3:
	if on_boat:
		return Vector3(pos.x / World.TILE, World.WATER_LEVEL + deck_height, pos.y / World.TILE)
	return world.to_3d(pos)


func tick_visuals(delta: float) -> void:
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	swing_time = maxf(swing_time - delta, 0.0)
	position = ground_point()
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(facing.x, facing.y), minf(delta * 12.0, 1.0))
	_body.tick(delta)
	if not dead:
		_body.play("idle" if riding else ("run" if _moving else "idle"))
	if riding:
		Horse.animate(_mount_look, delta, 1.0 if _moving else 0.0)
		# Sit in the saddle, whatever the horse's gait.
		_saddle = maxf(Horse.saddle_height(_mount_look) - HIPS, 0.2)
		_body.position = Vector3(0, _saddle, -0.05)
	_moving_last = _moving
	_moving = false
	_body.flash(hurt_flash > 0.0)

	var turn := Basis(Vector3.UP, _model.rotation.y)
	_lantern.visible = lantern and lantern_on and not dead
	_armour.visible = armour and armour_on and not dead
	_restyle_gear()
	_spear.visible = equipped == "spear" and has_spear and not dead
	_sword.visible = equipped == "sword" and sword_tier >= 0 and not dead
	_axe.visible = equipped == "axe" and has_axe and not dead
	_pickaxe.visible = equipped == "pickaxe" and has_pickaxe and not dead
	if _armour.visible and _torso and _neck:
		_armour.global_transform = Transform3D(turn, _torso.global_position.lerp(_neck.global_position, 0.45))
	if _right_hand:
		if _spear.visible:
			# Held low and pointing forward, tipped slightly up.
			_spear.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, PI / 2 - 0.3), _right_hand.global_position)
		if _sword.visible:
			_sword.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, 0.7), _right_hand.global_position)
		for tool in [_axe, _pickaxe]:
			if tool.visible:
				# Held by the end of the haft, head up and a little forward.
				tool.global_transform = Transform3D(turn * Basis(Vector3.RIGHT, 0.5), _right_hand.global_position - turn * Vector3(0, 0.08, 0))
	_torch.visible = torch_time > 0.0 and not dead
	if _torch.visible and _left_hand:
		_torch.global_transform = Transform3D(turn, _left_hand.global_position)
		_torch_light.light_energy = 2.2 + sin(Time.get_ticks_msec() / 90.0) * 0.15


func die() -> void:
	dead = true
	_body.play_once("death")


func count(item: String) -> int:
	return int(inventory.get(item, 0))


func add_item(item: String, amount: int) -> void:
	inventory[item] = count(item) + amount


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < int(cost[item]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for item in cost:
		inventory[item] = count(item) - int(cost[item])


## In first person the body is hidden (it still casts a shadow) and the held
## tool and torch are drawn in front of the camera by place_view_model().
func set_first_person(on: bool) -> void:
	first_person = on
	if not on:
		_torch_light.position = Vector3(0, 0.6, 0)
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = mode


## How far the view bobs up and down while walking, in metres.
func head_bob() -> float:
	return sin(_bob) * 0.035


## First person: puts the held tool at the lower right of the view and the torch
## at the lower left. Called after the camera has moved this frame.
func place_view_model(cam: Camera3D, delta: float) -> void:
	if not first_person or dead:
		return
	_fp_swing = maxf(_fp_swing - delta * 3.5, 0.0)
	if _moving_last:
		_bob += delta * 9.0
	var b := cam.global_transform.basis
	var o := cam.global_transform.origin
	var sway := Vector3(sin(_bob * 0.5) * 0.012, absf(sin(_bob * 0.5)) * 0.012, 0)
	# A swing chops down and forward.
	var chop := sin(_fp_swing * PI) * 1.0
	var hand := o + b * (Vector3(0.34, -0.52, -0.75) + sway + Vector3(-0.08 * chop, -0.04 * chop, -0.12 * chop))
	_armour.visible = false
	if _spear.visible:
		# Held low and pointing ahead; a swing is a thrust.
		var thrust := o + b * (Vector3(0.26, -0.4, -0.35 - 0.35 * chop) + sway)
		_spear.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -PI / 2 + 0.12) * Basis(Vector3.FORWARD, 0.08), thrust)
	for tool in [_axe, _pickaxe, _sword]:
		if tool.visible:
			# Head forward and up, not in your face; a swing tips it further forward.
			tool.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -0.9 - 0.8 * chop) * Basis(Vector3.FORWARD, 0.3), hand)
	if _torch.visible:
		_torch.global_transform = Transform3D(b * Basis(Vector3.RIGHT, -0.35) * Basis(Vector3.FORWARD, -0.2), o + b * (Vector3(-0.42, -0.6, -0.8) + sway))
		# Light the way ahead rather than the hands, which would glare white.
		_torch_light.global_position = o + b * Vector3(0, 0.4, -1.6)


func swing() -> void:
	swing_time = 0.15
	_fp_swing = 1.0
	if not dead:
		_body.play_once("punch" if equipped == "hands" else "slash", 2.2 if equipped == "sword" else 1.6)


## Puts a tool in your hand ("hands" puts it away). Returns false if you don't have it.
func equip(tool: String) -> bool:
	if not owns(tool):
		return false
	equipped = tool
	return true


func owns(tool: String) -> bool:
	match tool:
		"hands": return true
		"spear": return has_spear
		"sword": return sword_tier >= 0
		"axe": return has_axe
		"pickaxe": return has_pickaxe
	return false


func holding(tool: String) -> bool:
	return equipped == tool and owns(tool)


## Damage a swing does with what's in your hand.
func attack_damage() -> int:
	if holding("spear"):
		return int(Gear.info("spear", spear_tier)["damage"])
	if holding("sword"):
		return int(Gear.info("sword", sword_tier)["damage"])
	if holding("axe"):
		return 2
	return 1


func attack_reach() -> float:
	if holding("spear"):
		return Gear.SPEAR_REACH
	if holding("sword"):
		return Gear.SWORD_REACH
	return 24.0


## Seconds between swings: a sword is quicker than a spear or your fists.
func attack_cooldown() -> float:
	return Gear.SWORD_COOLDOWN if holding("sword") else Gear.SPEAR_COOLDOWN


func wearing_armour() -> bool:
	return armour and armour_on


## The share of a bite your armour stops (0 without armour).
func armour_reduction() -> float:
	return float(Gear.info("armour", armour_tier)["reduce"]) if wearing_armour() else 0.0


## How much your armour slows the cold (hide keeps you warm).
func armour_warmth() -> float:
	return float(Gear.info("armour", armour_tier)["warmth"]) if wearing_armour() else 0.0


## Colours the spear, sword and armour for the materials they're made of.
func _restyle_gear() -> void:
	var look := "%d/%d/%d" % [spear_tier, sword_tier, armour_tier]
	if look == _gear_look:
		return
	_gear_look = look
	if spear_tier >= 0:
		var g := Gear.info("spear", spear_tier)
		_tint(_spear, [g["shaft"], g["tip"]])
	if sword_tier >= 0:
		var g := Gear.info("sword", sword_tier)
		_tint(_sword, [g["blade"], g["blade"], g["hilt"], g["hilt"].darkened(0.3), g["hilt"]])
	if armour_tier >= 0:
		var g := Gear.info("armour", armour_tier)
		_tint(_armour, [g["color"], g["color"].darkened(0.12), g["trim"], g["trim"]])


func _tint(node: Node3D, colors: Array) -> void:
	var parts := node.get_children()
	for i in mini(parts.size(), colors.size()):
		var mi := parts[i] as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).albedo_color = colors[i]
			var shiny: bool = colors[i].s < 0.35 and colors[i].v > 0.55
			(mi.material_override as StandardMaterial3D).metallic = 0.6 if shiny else 0.0
			(mi.material_override as StandardMaterial3D).roughness = 0.35 if shiny else 0.9


func lantern_lit() -> bool:
	return lantern and lantern_on
