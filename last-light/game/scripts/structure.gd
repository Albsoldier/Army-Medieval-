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
		"about": "Recruit soldiers here (3 per barracks)."},
}
const ORDER := ["wood_wall", "stone_wall", "gate", "torch_post", "chest", "tent", "barracks"]
const TORCH_RADIUS := 80.0  # game pixels: wolves won't come closer to a lit torch post

var world: World
var kind := ""
var cell := Vector2i.ZERO
var pos := Vector2.ZERO  # centre of the tile, in game pixels
var hp := 100.0
var items: Dictionary = {}  # for chests
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
		"barracks":
			_add(Art.box(Vector3(1.0, 1.1, 1.0)), Color("7a5634"), Vector3(0, 0.55, 0))
			_add(Art.cylinder(0.0, 0.85, 0.8, 4), Color("8b2e2e"), Vector3(0, 1.5, 0), Vector3(0, PI / 4, 0))
			_add(Art.box(Vector3(0.3, 0.6, 0.04)), Color("2b1d12"), Vector3(0, 0.3, 0.51))
			_add(Art.cylinder(0.025, 0.025, 1.0, 4), Color("5a3d22"), Vector3(0.42, 2.1, 0.42))
			_add(Art.box(Vector3(0.35, 0.22, 0.02)), Color("b83a3a"), Vector3(0.6, 2.45, 0.42))
	_update_wear()
