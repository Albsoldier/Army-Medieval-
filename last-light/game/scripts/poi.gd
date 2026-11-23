## A place to discover: a lighthouse, shipwreck, ruins, cave, shrine or abandoned camp.
## Where they are comes from the island's seed (world.gd); whether you've found or
## looted one is saved.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

const TITLES := {
	"lighthouse": "Lighthouse", "shipwreck": "Shipwreck", "ruins": "Ruins",
	"cave": "Cave", "shrine": "Shrine", "camp": "Abandoned camp", "hoard": "Treasure hoard",
}
## What each kind of place holds, once.
const LOOT := {
	"lighthouse": {"iron": 3, "wood": 6, "stone": 4},
	"shipwreck": {"iron": 2, "wood": 8, "cooked_meat": 2},
	"ruins": {"stone": 8, "iron": 1, "berries": 6},
	"cave": {"ore": 4, "iron": 1, "stone": 5},
	"shrine": {},
	"camp": {"wood": 6, "berries": 5, "hide": 1, "cooked_meat": 1},
	"hoard": {"gold": 6, "iron": 6, "hide": 3, "smoked_meat": 3},
}
const LORE := {
	"lighthouse": [
		"The keeper's log ends mid-sentence: \"Lit the lamp again tonight. Nobody has come for us, but if anyone does, they will see it. The light stays on while one of us is left.\"",
		"Scratched into the stair rail: \"The ships never came back for the settlers. We kept the light for them anyway. Every night. Every single night.\"",
		"A brass plate by the door: \"Lantern Skerry Light. First lit by the Island Company. Keep it burning.\" Someone has added underneath, in pencil: \"We did.\"",
	],
	"shipwreck": [
		"The captain's chest holds a soaked letter: \"We made for the light in the storm. The rocks found us first. If you read this, the island has you too. Make your fires bright.\"",
		"A cargo list, still legible: \"Iron bars, rope, salt pork, lamp oil.\" Most of it is gone. Whoever came before you was hungry.",
		"Carved into the mast: \"Day 9. The wolves come at the third hour of night. They hate the fire. Keep it fed.\"",
	],
	"ruins": [
		"The settlers built this to last. A carved stone over the door reads: \"Whoever keeps a fire, keeps a home.\"",
		"Among the rubble, a child's slate: a drawing of a tall tower with a light on top, and a dozen little people holding hands.",
		"A rusted plaque: \"Company Granary. Rations by order of the Keeper.\" The shelves are bare, but not quite empty.",
	],
	"cave": [
		"The walls are scored with tally marks, hundreds of them, and above them in charcoal: \"Still here.\"",
		"Iron glints in the rock. Someone has already dug here and left their tools. A note under a stone: \"Take what you need. Leave the rest for the next one.\"",
		"Bones near the entrance, wolf and human both. Deeper in, a dry corner with a cold fire pit and a stack of ore.",
	],
	"shrine": [
		"Moss-covered stones in a ring. Sitting here, the island feels quieter. Your thoughts settle.",
		"The centre stone is warm to the touch, as if a fire burned under it. You feel steadier.",
		"Someone has left small offerings: shells, a button, a carved wolf. You add a pebble and feel better for it.",
	],
	"hoard": [
		"Under a cairn of stones, an iron-bound chest. The Island Company's seal is on the lid: they hid their pay chest out here, where no wolf could follow.",
		"A smugglers' cache, wrapped in tarred sailcloth. Gold, tools and salted meat. A scrap of paper: \"For whoever has a boat and the nerve.\"",
		"Buried in the sand above the tideline: a chest of gold and good iron, and a carving of a ship with a red sail.",
	],
	"camp": [
		"A cold fire, a torn tent, and a note pinned under a cup: \"Gone to find the lighthouse. Back by dark.\" The note is weathered. They didn't come back.",
		"Two bedrolls and one pack. A tally of days carved into a log stops at 12.",
		"Someone left in a hurry: the pot is still on the stones and the bag is half packed. Whatever they ran from, they left supplies behind.",
	],
}

var world: World
var data: Dictionary = {}
var kind := ""
var pos := Vector2.ZERO
var discovered := false
var looted := false

var _marker: MeshInstance3D
var _lid: Node3D
var _beam: SpotLight3D
var _beam_pivot: Node3D
var _t := 0.0


func setup(p_world: World, p_data: Dictionary) -> void:
	world = p_world
	data = p_data
	kind = str(data["type"])
	pos = world.cell_center(data["cell"])


func poi_id() -> String:
	return str(data["id"])


func display_name() -> String:
	return str(data["name"])


func lore() -> String:
	var lines: Array = LORE[kind]
	return lines[int(data.get("seed", 0)) % lines.size()]


func loot() -> Dictionary:
	return LOOT[kind]


func _ready() -> void:
	position = world.to_3d(pos)
	rotation.y = float(int(data.get("seed", 0)) % 628) / 100.0
	match kind:
		"lighthouse":
			_build_lighthouse()
		"shipwreck":
			_build_shipwreck()
		"ruins":
			_build_ruins()
		"cave":
			_build_cave()
		"shrine":
			_build_shrine()
		"camp":
			_build_camp()
		"hoard":
			_build_hoard()
	_marker = Art.part(self, Art.sphere(0.12, 3, 6), Color(1.0, 0.85, 0.4), Vector3(0, 3.2, 0), Vector3.ZERO, 3.0, true)
	refresh()


## Updates the marker and chest to match `discovered` and `looted`.
func refresh() -> void:
	if _marker:
		_marker.visible = not looted and kind != "shrine"
	if _lid:
		_lid.rotation.x = -1.1 if looted else 0.0


## Lights the lighthouse lamp at night. night: 0 by day, 1 at night.
func set_night(night: float) -> void:
	if _beam:
		_beam.visible = night > 0.3
		_beam.light_energy = 6.0 * night


func _process(delta: float) -> void:
	_t += delta
	if _marker and _marker.visible:
		_marker.position.y = 3.2 + sin(_t * 2.5) * 0.15
	if _beam_pivot:
		_beam_pivot.rotation.y += delta * 0.9


func _chest(at: Vector3) -> void:
	var chest := Node3D.new()
	chest.position = at
	add_child(chest)
	Art.part(chest, Art.box(Vector3(0.7, 0.42, 0.48)), Color("6a4528"), Vector3(0, 0.21, 0))
	Art.part(chest, Art.box(Vector3(0.72, 0.05, 0.05)), Color("c9a24a"), Vector3(0, 0.3, 0.25), Vector3.ZERO, 1.2)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.42, -0.24)
	chest.add_child(_lid)
	Art.part(_lid, Art.box(Vector3(0.74, 0.12, 0.5)), Color("7d5330"), Vector3(0, 0.06, 0.24))


func _build_lighthouse() -> void:
	# A striped tower with a lamp room. Its beam sweeps the sea at night.
	var stripes := [Color("f2efe6"), Color("b8322a")]
	for i in 5:
		var r_bottom := 1.25 - i * 0.14
		Art.part(self, Art.cylinder(r_bottom - 0.14, r_bottom, 1.6, 12), stripes[i % 2], Vector3(0, 0.8 + i * 1.6, 0))
	Art.part(self, Art.cylinder(0.85, 0.85, 0.12, 12), Color("2e2e2e"), Vector3(0, 8.06, 0))
	Art.part(self, Art.cylinder(0.55, 0.55, 0.9, 10), Color(1.0, 0.86, 0.45), Vector3(0, 8.55, 0), Vector3.ZERO, 3.0, true)
	Art.part(self, Art.cylinder(0.0, 0.7, 0.7, 10), Color("b8322a"), Vector3(0, 9.35, 0))
	Art.part(self, Art.box(Vector3(2.0, 1.3, 1.6)), Color("e7e2d6"), Vector3(2.0, 0.65, 0.4))
	Art.part(self, Art.cylinder(0.0, 1.5, 0.8, 4), Color("5b4636"), Vector3(2.0, 1.7, 0.4), Vector3(0, PI / 4, 0))
	_chest(Vector3(1.6, 0, 1.6))
	_beam_pivot = Node3D.new()
	_beam_pivot.position = Vector3(0, 8.55, 0)
	add_child(_beam_pivot)
	_beam = SpotLight3D.new()
	_beam.light_color = Color(1.0, 0.92, 0.7)
	_beam.spot_range = 55.0
	_beam.spot_angle = 14.0
	_beam.rotation.x = -0.12
	_beam.visible = false
	_beam_pivot.add_child(_beam)
	var glow := Art.omni(Color(1.0, 0.85, 0.5), 9.0, 1.5)
	glow.position = Vector3(0, 8.6, 0)
	add_child(glow)


func _build_shipwreck() -> void:
	var wood := Color("5b4027")
	var hull := Node3D.new()
	hull.rotation = Vector3(0.0, 0.0, 0.35)  # keeled over on the sand
	add_child(hull)
	Art.part(hull, Art.box(Vector3(5.0, 0.25, 1.8)), wood.darkened(0.1), Vector3(0, 0.2, 0))
	Art.part(hull, Art.box(Vector3(5.0, 1.3, 0.18)), wood, Vector3(0, 0.85, 0.9))
	Art.part(hull, Art.box(Vector3(3.6, 1.0, 0.18)), wood.lightened(0.05), Vector3(-0.5, 0.7, -0.9))
	Art.part(hull, Art.cylinder(0.0, 0.95, 1.6, 4), wood, Vector3(3.1, 0.75, 0), Vector3(0, 0, -PI / 2))
	for i in 5:
		Art.part(hull, Art.cylinder(0.06, 0.06, 1.9, 5), wood.darkened(0.2), Vector3(-2.0 + i * 0.9, 1.0, -0.9), Vector3(0.3, 0, 0))
	Art.part(self, Art.cylinder(0.12, 0.15, 5.0, 6), wood.darkened(0.15), Vector3(0.4, 1.8, -0.2), Vector3(0, 0, -0.9))
	Art.part(self, Art.box(Vector3(1.6, 1.2, 0.03)), Color("d8cdb2"), Vector3(1.5, 1.6, -0.2), Vector3(0, 0, -0.9))
	_chest(Vector3(-1.5, 0, 1.8))


func _build_ruins() -> void:
	var stone := Color("8b867b")
	var heights := [1.8, 1.1, 0.6, 1.5, 0.9, 0.4, 1.3, 0.7]
	for i in 8:
		var a := TAU * i / 8.0
		var h: float = heights[i]
		Art.part(self, Art.box(Vector3(1.3, h, 0.5)), stone.darkened(0.05 * (i % 3)),
			Vector3(cos(a) * 2.2, h / 2, sin(a) * 2.2), Vector3(0, -a + PI / 2, 0))
	Art.part(self, Art.cylinder(0.3, 0.3, 2.4, 8), stone.lightened(0.1), Vector3(0.6, 0.3, 0.2), Vector3(0, 0.4, PI / 2))
	Art.part(self, Art.cylinder(0.32, 0.32, 1.6, 8), stone.lightened(0.1), Vector3(-1.4, 0.8, -1.0))
	for i in 4:
		Art.part(self, Art.sphere(0.35, 2, 6), Color("4f7a3a"), Vector3(-1.5 + i, 0.05, 1.4 - i * 0.7))
	_chest(Vector3(-0.4, 0, -0.6))


func _build_cave() -> void:
	var rock := Color("6f6b63")
	var mound := Art.part(self, Art.sphere(2.6, 4, 9), rock, Vector3(0, 0.6, -1.0))
	mound.scale = Vector3(1.2, 0.85, 1.0)
	Art.part(self, Art.sphere(1.3, 3, 7), rock.lightened(0.08), Vector3(-2.2, 0.4, 0.2))
	Art.part(self, Art.sphere(1.0, 3, 7), rock.darkened(0.1), Vector3(2.1, 0.3, 0.4))
	var mouth := Art.part(self, Art.sphere(1.05, 4, 8), Color("0d0c0b"), Vector3(0, 0.85, 1.2))
	mouth.scale = Vector3(1.0, 0.95, 0.35)
	for i in 3:
		Art.part(self, Art.cylinder(0.0, 0.14, 0.6, 5), rock.darkened(0.2), Vector3(-0.5 + i * 0.5, 1.75, 1.15), Vector3(PI, 0, 0))
	_chest(Vector3(1.4, 0, 1.9))


func _build_shrine() -> void:
	var stone := Color("7c7a72")
	for i in 6:
		var a := TAU * i / 6.0
		var h := 1.5 + (i % 2) * 0.5
		Art.part(self, Art.box(Vector3(0.5, h, 0.35)), stone.darkened(0.04 * i), Vector3(cos(a) * 2.0, h / 2, sin(a) * 2.0), Vector3(0, -a, 0.05))
	Art.part(self, Art.box(Vector3(0.9, 0.9, 0.9)), stone.lightened(0.1), Vector3(0, 0.45, 0))
	Art.part(self, Art.sphere(0.16, 3, 6), Color(0.45, 0.8, 1.0), Vector3(0, 1.05, 0), Vector3.ZERO, 3.5, true)
	var glow := Art.omni(Color(0.5, 0.8, 1.0), 6.0, 1.2)
	glow.position = Vector3(0, 1.4, 0)
	add_child(glow)


func _build_camp() -> void:
	Art.part(self, Art.cylinder(0.0, 1.0, 1.4, 4), Color("8f8366"), Vector3(-1.0, 0.7, -0.6), Vector3(0.12, PI / 4, 0.18))
	for i in 7:
		var a := TAU * i / 7.0
		Art.part(self, Art.sphere(0.12, 3, 6), Color("6c6860"), Vector3(1.0 + cos(a) * 0.4, 0.06, 0.4 + sin(a) * 0.4))
	Art.part(self, Art.cylinder(0.25, 0.25, 0.03, 8), Color("2b2522"), Vector3(1.0, 0.02, 0.4))
	Art.part(self, Art.box(Vector3(0.5, 0.4, 0.5)), Color("8a6a43"), Vector3(-0.2, 0.2, 1.1), Vector3(0, 0.3, 0))
	Art.part(self, Art.cylinder(0.07, 0.07, 1.2, 5), Color("5a3d22"), Vector3(0.2, 0.08, -1.2), Vector3(0, 0.5, PI / 2))
	_chest(Vector3(0.0, 0, -0.3))


func _build_hoard() -> void:
	# A cairn of stones beside a gold-banded chest, and a broken oar.
	for i in 6:
		var a := TAU * i / 6.0
		Art.part(self, Art.sphere(0.28, 4, 7), Color("77736b"), Vector3(-0.9 + cos(a) * 0.35, 0.18, sin(a) * 0.35))
	Art.part(self, Art.sphere(0.3, 4, 7), Color("858177"), Vector3(-0.9, 0.5, 0))
	Art.part(self, Art.box(Vector3(0.08, 0.08, 1.6)), Color("6b4a2b"), Vector3(0.9, 0.05, 0.4), Vector3(0, 0.6, 0))
	_chest(Vector3(0.2, 0, -0.2))
	for i in 4:
		Art.part(self, Art.cylinder(0.06, 0.06, 0.02, 8), Color("e5b844"), Vector3(0.55 + i * 0.09, 0.01 + i * 0.022, 0.25), Vector3.ZERO, 0.8)
