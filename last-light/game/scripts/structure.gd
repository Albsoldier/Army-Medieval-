## Something the player built: a wall, gate, torch post, chest, tent or barracks.
## Each structure fills one tile. Its data (type, hp, stored items) is saved.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

## Everything that can be built, in build-menu order.
## blocks: "all" (nobody passes), "wolves" (only wolves are stopped) or "none".
const TYPES := {
	"wood_wall": {"name": "Wooden wall", "cost": {"wood": 4}, "hp": 100, "blocks": "all",
		"about": "Keeps wolves out."},
	"stone_wall": {"name": "Stone wall", "cost": {"stone": 3, "wood": 1}, "hp": 250, "blocks": "all",
		"about": "Much tougher than wood."},
	"gate": {"name": "Gate", "cost": {"wood": 6}, "hp": 120, "blocks": "wolves",
		"about": "You and your soldiers can pass. Wolves can't."},
	"torch_post": {"name": "Torch post", "cost": {"wood": 2, "stone": 1}, "hp": 60, "blocks": "all",
		"about": "Burns forever. Wolves keep away from its light."},
	"chest": {"name": "Storage chest", "cost": {"wood": 8}, "hp": 80, "blocks": "all",
		"about": "Store items safely."},
	"tent": {"name": "Tent", "cost": {"wood": 10, "berries": 3}, "hp": 80, "blocks": "all",
		"about": "You wake here after dying, and can sleep through the night."},
	"barracks": {"name": "Barracks", "cost": {"wood": 20, "stone": 10}, "hp": 300, "blocks": "all",
		"about": "Recruit soldiers here (10 per barracks)."},
	"workbench": {"name": "Workbench", "cost": {"wood": 8, "stone": 4}, "hp": 120, "blocks": "all",
		"about": "Make an axe, a pickaxe, healing salve and hide armour."},
	"forge": {"name": "Forge", "cost": {"stone": 12, "wood": 6}, "hp": 200, "blocks": "all",
		"about": "Smelt iron and steel; forge spears, swords, armour and a lantern."},
	"smokehouse": {"name": "Smokehouse", "cost": {"wood": 10, "stone": 4}, "hp": 150, "blocks": "all",
		"about": "Smokes all your raw meat at once. Smoked meat is the best food."},
	"dock": {"name": "Dock", "cost": {"wood": 12, "stone": 2}, "hp": 150, "blocks": "none",
		"about": "Build at the water's edge. Builds and launches a raft or a galley."},
	"vault": {"name": "Treasure vault", "cost": {"wood": 16, "iron": 6, "gold": 2}, "hp": 400, "blocks": "all",
		"about": "Store gold. With 50 gold inside, start a purge: waves of raiders come for it."},
	# Defences: they fight back.
	"archer_tower": {"name": "Archer tower", "cost": {"wood": 20, "stone": 8}, "hp": 350, "blocks": "all",
		"about": "Shoots wolves and raiders that come within range."},
	"spike_trap": {"name": "Spike trap", "cost": {"wood": 6, "iron": 1}, "hp": 100, "blocks": "none",
		"about": "Wounds wolves and raiders that step on it. Safe for you and your people."},
	"oil_gate": {"name": "Boiling-oil gate", "cost": {"wood": 10, "stone": 4, "iron": 4}, "hp": 260, "blocks": "wolves",
		"about": "A gate that scalds enemies at it or trying to break it."},
	# The village.
	"field": {"name": "Farm field", "cost": {"wood": 4, "berries": 2}, "hp": 60, "blocks": "none",
		"about": "Grows wheat in half a day (not in winter). E to harvest when golden."},
	"house": {"name": "Cottage", "cost": {"wood": 24, "stone": 6}, "hp": 250, "blocks": "all",
		"about": "Two settlers can live here, if your chests hold food. They pay taxes in gold."},
}
## Build menu pages (Tab in build mode turns the page).
const PAGES := [["wood_wall", "stone_wall", "gate", "torch_post", "chest", "tent", "barracks",
	"workbench", "forge", "smokehouse", "dock", "vault"],
	["archer_tower", "spike_trap", "oil_gate", "field", "house"]]
const ORDER := ["wood_wall", "stone_wall", "gate", "torch_post", "chest", "tent", "barracks",
	"workbench", "forge", "smokehouse", "dock", "vault", "archer_tower", "spike_trap", "oil_gate", "field", "house"]
## Defences
const TOWER_RANGE := 160.0  # game pixels
const TOWER_DAMAGE := 2
const TOWER_COOLDOWN := 1.1
const TRAP_DAMAGE := 5
const TRAP_COOLDOWN := 0.9
const OIL_RANGE := 28.0
const OIL_DAMAGE := 4
const OIL_COOLDOWN := 1.4
## Fields
const GROW_TIME := 480.0  # seconds from sowing to harvest (half a day)
const FIELD_YIELD := 10  # wheat per harvest
## What each crafting station makes. "gives" is an item, or a tool you keep.
const RECIPES := {
	"workbench": [
		{"id": "axe", "name": "Axe", "cost": {"wood": 4, "stone": 3}, "about": "20 wood for every hit on a tree, while it's in your hand."},
		{"id": "pickaxe", "name": "Pickaxe", "cost": {"wood": 4, "stone": 4},
			"about": "20 stone, iron ore or gold for every hit. Needed to mine ore."},
		{"id": "salve", "name": "Healing salve", "cost": {"berries": 6}, "about": "Press Q to heal 30 health."},
	],
	"forge": [
		{"id": "iron", "name": "Smelt iron", "cost": {"ore": 2, "wood": 1}, "about": "Turns 2 iron ore into 1 iron."},
		{"id": "steel", "name": "Make steel", "cost": {"iron": 2, "wood": 2}, "about": "Folds 2 iron with charcoal into 1 steel."},
		{"id": "lantern", "name": "Lantern", "cost": {"iron": 2, "wood": 1}, "about": "A light that never runs out."},
	],
	"smokehouse": [
		{"id": "smoke", "name": "Smoke all raw meat", "cost": {}, "about": "Smoked meat fills 45 hunger."},
		{"id": "bread", "name": "Bread", "cost": {"wheat": 2}, "about": "Bake a loaf from 2 wheat. Fills 30 hunger."},
	],
}
const TORCH_RADIUS := 80.0
## Walls and gates turn to line up with the walls next to them.
const LINES_UP := ["wood_wall", "stone_wall", "gate", "oil_gate"]  # game pixels: wolves won't come closer to a lit torch post

var world: World
var kind := ""
var cell := Vector2i.ZERO
var pos := Vector2.ZERO  # centre of the tile, in game pixels
var hp := 100.0
var items: Dictionary = {}  # for chests
var built_ms := -1  # Time.get_ticks_msec() when built this session; -1 if loaded from a save
var radius := 0.0  # light radius (torch posts only), so wolves treat it like a fire

var cooldown := 0.0  # defences: time until they strike again
var growth := 0.0  # fields: 0 just sown, 1 ripe

var _flash := 0.0
var _parts: Array = []
var _crops: Array = []  # fields: the wheat stalks
var _stage := -1


static func info(type_name: String) -> Dictionary:
	return TYPES.get(type_name, {})


static func max_hp(type_name: String) -> float:
	return float(info(type_name).get("hp", 100))


func setup(p_world: World, p_kind: String, p_cell: Vector2i) -> void:
	world = p_world
	kind = p_kind
	cell = p_cell
	pos = world.cell_center(cell)
	hp = max_hp(kind)
	if kind == "torch_post":
		radius = TORCH_RADIUS


func _ready() -> void:
	position = world.to_3d(pos)
	rotation.y = 0.0
	_build_model()


func is_lit() -> bool:
	return kind == "torch_post"


## Which way the open water lies from this tile (for docks).
func water_direction() -> Vector2:
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		if not world.is_land(cell + d):
			return Vector2(d)
	return Vector2.DOWN


func is_ripe() -> bool:
	return kind == "field" and growth >= 1.0


## Fields: how far the wheat has grown (0 to 1).
func set_growth(g: float) -> void:
	growth = clampf(g, 0.0, 1.0)
	var stage := int(growth * 20.0)
	if stage == _stage:
		return  # the wheat only looks different every 5%
	_stage = stage
	var ripe := growth >= 1.0
	for c in _crops:
		var stalk := c as MeshInstance3D
		stalk.scale = Vector3(1, 0.15 + growth * 0.85, 1)
		stalk.position.y = 0.12 + 0.3 * stalk.scale.y
		var mat := stalk.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color("d9b44a") if ripe else Color("6f9a3a").lerp(Color("a8a648"), growth)


## Towers: an arrow that flies from the top of the tower to `at`.
func shoot(at: Vector3) -> void:
	var arrow := Node3D.new()
	arrow.top_level = true
	add_child(arrow)
	Art.part(arrow, Art.cylinder(0.012, 0.012, 0.7, 4), Color("caa472"), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	Art.part(arrow, Art.cylinder(0.0, 0.03, 0.08, 4), Color("8a8f95"), Vector3(0, 0, 0.38), Vector3(PI / 2, 0, 0))
	var from := global_position + Vector3(0, 3.0, 0)
	arrow.global_position = from
	if from.distance_to(at) > 0.1:
		arrow.look_at(at, Vector3.UP, true)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "global_position", at, clampf(from.distance_to(at) / 30.0, 0.08, 0.45))
	tween.tween_callback(arrow.queue_free)


## Oil gates: a puff of steam when it pours.
func pour() -> void:
	_flash = 0.15


func display_name() -> String:
	return str(info(kind).get("name", kind))


func damage(amount: float) -> bool:
	hp -= amount
	_flash = 0.15
	_update_wear()
	return hp <= 0.0


func repair(amount: float) -> void:
	hp = minf(hp + amount, max_hp(kind))
	_update_wear()


## Turns the model into a see-through preview, green or red.
func make_ghost(valid: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if valid else Color(1.0, 0.25, 0.2, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in _parts:
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in get_children():
		var light := child as Light3D
		if light:
			light.visible = false


## Turns a wall or gate so it runs north-south when its neighbours do.
func line_up(structures: Dictionary) -> void:
	if not kind in LINES_UP:
		return
	var east_west := _joins(structures, Vector2i(1, 0)) or _joins(structures, Vector2i(-1, 0))
	var north_south := _joins(structures, Vector2i(0, 1)) or _joins(structures, Vector2i(0, -1))
	rotation.y = PI / 2 if north_south and not east_west else 0.0


func _joins(structures: Dictionary, offset: Vector2i) -> bool:
	return str(structures.get(cell + offset, "")) in LINES_UP


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		scale = Vector3.ONE * (1.0 - _flash * 0.3)


func _update_wear() -> void:
	# Damaged structures lean a little, so you can see what needs repair.
	var wear := 1.0 - clampf(hp / max_hp(kind), 0.0, 1.0)
	rotation.z = wear * 0.12
	rotation.x = wear * 0.06


func _add(mesh: Mesh, color: Color, offset: Vector3, rot: Vector3 = Vector3.ZERO,
		emission: float = 0.0, unshaded: bool = false) -> MeshInstance3D:
	var mi := Art.part(self, mesh, color, offset, rot, emission, unshaded)
	_parts.append(mi)
	return mi


func _build_model() -> void:
	match kind:
		"wood_wall":
			# A palisade of sharpened logs.
			for i in 4:
				var x := -0.375 + i * 0.25
				_add(Art.cylinder(0.12, 0.13, 1.6, 6), Color("6b4a2b").darkened(i * 0.04), Vector3(x, 0.8, 0))
				_add(Art.cylinder(0.0, 0.12, 0.3, 6), Color("7a5634"), Vector3(x, 1.75, 0))
			_add(Art.box(Vector3(1.0, 0.12, 0.1)), Color("4d3420"), Vector3(0, 1.0, 0.13))
		"stone_wall":
			_add(Art.box(Vector3(1.0, 1.4, 0.8)), Color("8a8577"), Vector3(0, 0.7, 0))
			for row in 3:
				_add(Art.box(Vector3(1.02, 0.04, 0.82)), Color("5d5a52"), Vector3(0, 0.35 + row * 0.4, 0))
			_add(Art.box(Vector3(0.3, 0.25, 0.8)), Color("8a8577"), Vector3(-0.35, 1.52, 0))
			_add(Art.box(Vector3(0.3, 0.25, 0.8)), Color("8a8577"), Vector3(0.35, 1.52, 0))
		"gate", "oil_gate":
			_add(Art.cylinder(0.12, 0.13, 2.1, 6), Color("5a3d22"), Vector3(-0.45, 1.05, 0))
			_add(Art.cylinder(0.12, 0.13, 2.1, 6), Color("5a3d22"), Vector3(0.45, 1.05, 0))
			_add(Art.box(Vector3(1.05, 0.14, 0.14)), Color("4d3420"), Vector3(0, 2.0, 0))
			for i in 3:
				_add(Art.box(Vector3(0.24, 1.2, 0.06)), Color("8f6239"), Vector3(-0.26 + i * 0.26, 0.75, 0))
			_add(Art.box(Vector3(0.8, 0.08, 0.08)), Color("4d3420"), Vector3(0, 0.95, 0.05), Vector3(0, 0, 0.6))
			if kind == "oil_gate":
				# Stone towers either side and a cauldron of boiling oil over the gate.
				for x in [-0.45, 0.45]:
					_add(Art.box(Vector3(0.3, 2.4, 0.4)), Color("7d786d"), Vector3(x, 1.2, 0))
				_add(Art.box(Vector3(1.2, 0.2, 0.5)), Color("6a665e"), Vector3(0, 2.4, 0))
				_add(Art.cylinder(0.2, 0.15, 0.3, 8), Color("2e2e30"), Vector3(0, 2.65, 0))
				_add(Art.cylinder(0.17, 0.17, 0.02, 8), Color(1.0, 0.55, 0.15), Vector3(0, 2.8, 0), Vector3.ZERO, 2.5, true)
				var glow := Art.omni(Color(1.0, 0.55, 0.2), 2.5, 0.8)
				glow.position = Vector3(0, 3.0, 0)
				add_child(glow)
		"torch_post":
			_add(Art.cylinder(0.06, 0.08, 1.8, 6), Color("5a3d22"), Vector3(0, 0.9, 0))
			_add(Art.cylinder(0.14, 0.1, 0.2, 6), Color("4a4846"), Vector3(0, 1.85, 0))
			_add(Art.sphere(0.14, 3, 6), Color(1.0, 0.6, 0.2), Vector3(0, 2.0, 0), Vector3.ZERO, 4.0, true)
			var light := Art.omni(Color(1.0, 0.7, 0.4), TORCH_RADIUS / World.TILE * 1.4, 2.0)
			light.position = Vector3(0, 2.1, 0)
			add_child(light)
		"chest":
			_add(Art.box(Vector3(0.8, 0.5, 0.55)), Color("7a5230"), Vector3(0, 0.25, 0))
			_add(Art.box(Vector3(0.84, 0.14, 0.59)), Color("8f6239"), Vector3(0, 0.56, 0))
			_add(Art.box(Vector3(0.84, 0.06, 0.06)), Color("3d2a18"), Vector3(0, 0.3, 0.28))
			_add(Art.box(Vector3(0.1, 0.12, 0.04)), Color("d4b25a"), Vector3(0, 0.46, 0.3), Vector3.ZERO, 1.5)
		"tent":
			_add(Art.cylinder(0.0, 0.85, 1.5, 4), Color("c9b48a"), Vector3(0, 0.75, 0), Vector3(0, PI / 4, 0))
			_add(Art.box(Vector3(0.36, 0.7, 0.02)), Color("3d2f22"), Vector3(0, 0.35, 0.47))
			_add(Art.cylinder(0.03, 0.03, 0.3, 4), Color("5a3d22"), Vector3(0, 1.6, 0))
		"workbench":
			_add(Art.box(Vector3(1.0, 0.1, 0.6)), Color("8f6239"), Vector3(0, 0.8, 0))
			for corner in [Vector3(-0.42, 0.38, -0.22), Vector3(0.42, 0.38, -0.22), Vector3(-0.42, 0.38, 0.22), Vector3(0.42, 0.38, 0.22)]:
				_add(Art.box(Vector3(0.08, 0.76, 0.08)), Color("5a3d22"), corner)
			_add(Art.box(Vector3(0.4, 0.04, 0.12)), Color("b9bcc2"), Vector3(-0.15, 0.87, 0.05), Vector3(0, 0.4, 0))
			_add(Art.cylinder(0.025, 0.025, 0.32, 5), Color("6b4a2b"), Vector3(0.25, 0.87, -0.05), Vector3(0, 0, PI / 2))
			_add(Art.box(Vector3(0.12, 0.07, 0.07)), Color("4a4846"), Vector3(0.4, 0.87, -0.05))
		"forge":
			_add(Art.box(Vector3(1.0, 0.8, 0.9)), Color("6f6b63"), Vector3(0, 0.4, 0))
			_add(Art.box(Vector3(0.6, 0.12, 0.5)), Color(1.0, 0.45, 0.1), Vector3(0, 0.82, 0), Vector3.ZERO, 3.0, true)
			_add(Art.cylinder(0.18, 0.22, 1.3, 8), Color("5d5a52"), Vector3(0.3, 1.45, -0.25))
			_add(Art.box(Vector3(0.36, 0.22, 0.18)), Color("2e2e30"), Vector3(-0.2, 0.92, 0.48))
			var coals := Art.omni(Color(1.0, 0.5, 0.2), 3.5, 1.2)
			coals.position = Vector3(0, 1.1, 0)
			add_child(coals)
		"smokehouse":
			_add(Art.box(Vector3(0.95, 1.0, 0.95)), Color("6b4a2b"), Vector3(0, 0.5, 0))
			_add(Art.cylinder(0.0, 0.8, 0.6, 4), Color("4d3420"), Vector3(0, 1.3, 0), Vector3(0, PI / 4, 0))
			_add(Art.cylinder(0.1, 0.12, 0.5, 6), Color("5d5a52"), Vector3(0.25, 1.65, 0.2))
			_add(Art.box(Vector3(0.36, 0.5, 0.03)), Color("2b1d12"), Vector3(0, 0.3, 0.49))
			var smoke := CPUParticles3D.new()
			var puff := Art.sphere(0.12, 3, 6)
			var smoke_mat := Art.material(Color(0.6, 0.6, 0.6, 0.35))
			smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			puff.material = smoke_mat
			smoke.mesh = puff
			smoke.amount = 8
			smoke.lifetime = 3.0
			smoke.direction = Vector3.UP
			smoke.spread = 15.0
			smoke.gravity = Vector3(0.15, 0.25, 0)
			smoke.initial_velocity_min = 0.3
			smoke.initial_velocity_max = 0.5
			smoke.scale_amount_min = 0.8
			smoke.scale_amount_max = 2.0
			smoke.position = Vector3(0.25, 1.95, 0.2)
			add_child(smoke)
		"dock":
			# Planks on posts, reaching out over the water.
			var out := water_direction()
			rotation.y = atan2(out.x, out.y)
			for i in 6:
				_add(Art.box(Vector3(1.1, 0.07, 0.36)), Color("8f6239").darkened((i % 2) * 0.08), Vector3(0, 0.22, -0.3 + i * 0.37))
			for x in [-0.5, 0.5]:
				for z in [-0.3, 0.7, 1.6]:
					_add(Art.cylinder(0.07, 0.08, 1.6, 6), Color("5a3d22"), Vector3(x, -0.5, z))
			_add(Art.cylinder(0.09, 0.09, 0.5, 6), Color("4d3420"), Vector3(0.45, 0.45, 1.7))  # mooring post
		"vault":
			# A heavy iron-bound chest on a stone plinth, gold spilling from the lid.
			_add(Art.box(Vector3(1.0, 0.18, 0.8)), Color("77736b"), Vector3(0, 0.09, 0))
			_add(Art.box(Vector3(0.86, 0.5, 0.62)), Color("5a3d22"), Vector3(0, 0.43, 0))
			_add(Art.box(Vector3(0.9, 0.16, 0.66)), Color("6b4a2b"), Vector3(0, 0.74, 0))
			for x in [-0.32, 0.0, 0.32]:
				_add(Art.box(Vector3(0.07, 0.68, 0.66)), Color("4a4846"), Vector3(x, 0.5, 0))
			_add(Art.box(Vector3(0.14, 0.14, 0.04)), Color("d8b45a"), Vector3(0, 0.5, 0.33), Vector3.ZERO, 1.2)
			for k in 5:
				_add(Art.cylinder(0.07, 0.07, 0.02, 8), Color("e8c25a"), Vector3(-0.2 + k * 0.1, 0.83 + (k % 2) * 0.02, 0.05 * (k % 3)), Vector3.ZERO, 0.8)
		"archer_tower":
			# A timber tower with a railed platform, a roof and an archer on watch.
			for x in [-0.36, 0.36]:
				for z in [-0.36, 0.36]:
					_add(Art.cylinder(0.07, 0.09, 2.6, 6), Color("5a3d22"), Vector3(x, 1.3, z))
			_add(Art.box(Vector3(0.8, 0.06, 0.06)), Color("4d3420"), Vector3(0, 1.0, 0.36), Vector3(0, 0, 0.9))
			_add(Art.box(Vector3(0.8, 0.06, 0.06)), Color("4d3420"), Vector3(0, 1.0, -0.36), Vector3(0, 0, -0.9))
			_add(Art.box(Vector3(1.05, 0.1, 1.05)), Color("8f6239"), Vector3(0, 2.4, 0))
			for side in [Vector3(0, 2.7, 0.5), Vector3(0, 2.7, -0.5)]:
				_add(Art.box(Vector3(1.05, 0.5, 0.05)), Color("6b4a2b"), side)
			for side in [Vector3(0.5, 2.7, 0), Vector3(-0.5, 2.7, 0)]:
				_add(Art.box(Vector3(0.05, 0.5, 1.05)), Color("6b4a2b"), side)
			_add(Art.cylinder(0.0, 0.78, 0.6, 4), Color("8b2e2e"), Vector3(0, 3.65, 0), Vector3(0, PI / 4, 0))
			for x in [-0.45, 0.45]:
				_add(Art.cylinder(0.03, 0.03, 0.9, 4), Color("5a3d22"), Vector3(x, 3.0, 0.45))
			_add(Art.box(Vector3(0.22, 0.42, 0.16)), Color("4f5d2f"), Vector3(0.1, 2.85, 0.1))  # the archer
			_add(Art.sphere(0.1, 4, 8), Color("d9a77f"), Vector3(0.1, 3.15, 0.1))
			_add(Art.cylinder(0.11, 0.11, 0.05, 8), Color("7d8186"), Vector3(0.1, 3.24, 0.1))
		"spike_trap":
			# A board of sharpened iron spikes, low enough to step on.
			_add(Art.box(Vector3(0.9, 0.06, 0.9)), Color("5a3d22"), Vector3(0, 0.03, 0))
			for i in 4:
				for j in 4:
					_add(Art.cylinder(0.0, 0.05, 0.28, 4), Color("8a8f95"), Vector3(-0.3 + i * 0.2, 0.2, -0.3 + j * 0.2))
		"field":
			# Tilled earth in furrows, with rows of wheat.
			_add(Art.box(Vector3(1.0, 0.1, 1.0)), Color("5b4030"), Vector3(0, 0.05, 0))
			for r in 4:
				_add(Art.box(Vector3(1.0, 0.05, 0.08)), Color("4a3326"), Vector3(0, 0.11, -0.375 + r * 0.25))
				for k in 5:
					var stalk := _add(Art.cylinder(0.035, 0.045, 0.6, 4), Color("6f9a3a"),
						Vector3(-0.4 + k * 0.2 + (r % 2) * 0.05, 0.3, -0.375 + r * 0.25))
					stalk.material_override = Art.material(Color("6f9a3a"))
					_crops.append(stalk)
			set_growth(growth)
		"house":
			# A whitewashed cottage with a thatched roof and a chimney.
			_add(Art.box(Vector3(0.95, 0.9, 0.85)), Color("d9cfb8"), Vector3(0, 0.45, 0))
			for x in [-0.46, 0.46]:
				_add(Art.box(Vector3(0.06, 0.9, 0.06)), Color("5a3d22"), Vector3(x, 0.45, 0.43))
			_add(Art.cylinder(0.0, 0.82, 0.75, 4), Color("c2a25a"), Vector3(0, 1.27, 0), Vector3(0, PI / 4, 0))
			_add(Art.box(Vector3(0.24, 0.5, 0.03)), Color("5a3d22"), Vector3(-0.18, 0.25, 0.44))
			_add(Art.box(Vector3(0.2, 0.18, 0.03)), Color(1.0, 0.85, 0.5), Vector3(0.22, 0.55, 0.44), Vector3.ZERO, 0.8)
			_add(Art.box(Vector3(0.16, 0.5, 0.16)), Color("77736b"), Vector3(0.28, 1.4, -0.2))
		"barracks":
			_add(Art.box(Vector3(1.0, 1.1, 1.0)), Color("7a5634"), Vector3(0, 0.55, 0))
			_add(Art.cylinder(0.0, 0.85, 0.8, 4), Color("8b2e2e"), Vector3(0, 1.5, 0), Vector3(0, PI / 4, 0))
			_add(Art.box(Vector3(0.3, 0.6, 0.04)), Color("2b1d12"), Vector3(0, 0.3, 0.51))
			_add(Art.cylinder(0.025, 0.025, 1.0, 4), Color("5a3d22"), Vector3(0.42, 2.1, 0.42))
			_add(Art.box(Vector3(0.35, 0.22, 0.02)), Color("b83a3a"), Vector3(0.6, 2.45, 0.42))
	_update_wear()
