## Something the player built: a wall, gate, torch post, chest, tent or barracks.
## Each structure fills one tile. Its data (type, hp, stored items) is saved.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

## Everything that can be built, in build-menu order.
## blocks: "all" (nobody passes), "wolves" (only wolves are stopped) or "none".
const TYPES := {
	"wood_wall": {"name": "Wooden wall", "cost": {"wood": 4}, "hp": 100, "blocks": "all",
		"about": "Keeps wolves out. They gnaw through it slowly."},
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
		"about": "Make an axe, a pickaxe and healing salve."},
	"forge": {"name": "Forge", "cost": {"stone": 12, "wood": 6}, "hp": 200, "blocks": "all",
		"about": "Smelt iron ore, then forge an iron spear, armour and a lantern."},
	"smokehouse": {"name": "Smokehouse", "cost": {"wood": 10, "stone": 4}, "hp": 150, "blocks": "all",
		"about": "Smokes all your raw meat at once. Smoked meat is the best food."},
	"dock": {"name": "Dock", "cost": {"wood": 12, "stone": 2}, "hp": 150, "blocks": "none",
		"about": "Build at the water's edge. Builds and launches a raft or a galley."},
}
const ORDER := ["wood_wall", "stone_wall", "gate", "torch_post", "chest", "tent", "barracks",
	"workbench", "forge", "smokehouse", "dock"]
## What each crafting station makes. "gives" is an item, or a tool you keep.
const RECIPES := {
	"workbench": [
		{"id": "axe", "name": "Axe", "cost": {"wood": 4, "stone": 3}, "about": "3 wood for every hit on a tree, while it's in your hand."},
		{"id": "pickaxe", "name": "Pickaxe", "cost": {"wood": 4, "stone": 4},
			"about": "3 stone for every hit on a rock, and 2 iron ore or gold. Needed to mine ore."},
		{"id": "salve", "name": "Healing salve", "cost": {"berries": 6}, "about": "Press Q to heal 30 health."},
	],
	"forge": [
		{"id": "iron", "name": "Smelt iron", "cost": {"ore": 2, "wood": 1}, "about": "Turns 2 iron ore into 1 iron."},
		{"id": "iron_spear", "name": "Iron spear", "cost": {"iron": 3, "wood": 2}, "about": "Hits wolves 3 times as hard as your fists."},
		{"id": "armour", "name": "Iron armour", "cost": {"iron": 5, "hide": 3}, "about": "Wolf bites hurt half as much."},
		{"id": "lantern", "name": "Lantern", "cost": {"iron": 2, "wood": 1}, "about": "A light that never runs out."},
	],
	"smokehouse": [
		{"id": "smoke", "name": "Smoke all raw meat", "cost": {}, "about": "Smoked meat fills 45 hunger."},
	],
}
const TORCH_RADIUS := 80.0
## Walls and gates turn to line up with the walls next to them.
const LINES_UP := ["wood_wall", "stone_wall", "gate"]  # game pixels: wolves won't come closer to a lit torch post

var world: World
var kind := ""
var cell := Vector2i.ZERO
var pos := Vector2.ZERO  # centre of the tile, in game pixels
var hp := 100.0
var items: Dictionary = {}  # for chests
var built_ms := -1  # Time.get_ticks_msec() when built this session; -1 if loaded from a save
var radius := 0.0  # light radius (torch posts only), so wolves treat it like a fire

var _flash := 0.0
var _parts: Array = []


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
		"gate":
			_add(Art.cylinder(0.12, 0.13, 2.1, 6), Color("5a3d22"), Vector3(-0.45, 1.05, 0))
			_add(Art.cylinder(0.12, 0.13, 2.1, 6), Color("5a3d22"), Vector3(0.45, 1.05, 0))
			_add(Art.box(Vector3(1.05, 0.14, 0.14)), Color("4d3420"), Vector3(0, 2.0, 0))
			for i in 3:
				_add(Art.box(Vector3(0.24, 1.2, 0.06)), Color("8f6239"), Vector3(-0.26 + i * 0.26, 0.75, 0))
			_add(Art.box(Vector3(0.8, 0.08, 0.08)), Color("4d3420"), Vector3(0, 0.95, 0.05), Vector3(0, 0, 0.6))
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
		"barracks":
			_add(Art.box(Vector3(1.0, 1.1, 1.0)), Color("7a5634"), Vector3(0, 0.55, 0))
			_add(Art.cylinder(0.0, 0.85, 0.8, 4), Color("8b2e2e"), Vector3(0, 1.5, 0), Vector3(0, PI / 4, 0))
			_add(Art.box(Vector3(0.3, 0.6, 0.04)), Color("2b1d12"), Vector3(0, 0.3, 0.51))
			_add(Art.cylinder(0.025, 0.025, 1.0, 4), Color("5a3d22"), Vector3(0.42, 2.1, 0.42))
			_add(Art.box(Vector3(0.35, 0.22, 0.02)), Color("b83a3a"), Vector3(0.6, 2.45, 0.42))
	_update_wear()
