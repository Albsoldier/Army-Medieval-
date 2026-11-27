## A boat: a raft for lakes and the shallows, or a galley that can cross the
## open sea to the islets. Moored where you leave it; saved with the game.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")
## The galley is a modelled sailing ship (GRAPHICS_SHIPS.md): Poly Haven's
## "Dutch Ship Large 01" (CC0), decimated (tools/decimate_ship.py,
## tools/build_ship_model.gd): the hull (shared with the shipwrecks) and the
## rigging and sails, one surface each on one material: two draw calls.
## Off with ?ships=0, to compare with the old galley.
const SHIP_MODELS := ["res://models/ships/ship_hull.res", "res://models/ships/ship_rigging.res"]
## The rigging casts no shadow of its own (its ropes, drawn again in each
## shadow cascade, cost more than they show); its sails cast it, unseen.
const SHIP_SHADOW := "res://models/ships/ship_sails_shadow.res"
static var use_new_ship := true
## The modelled ship's main deck, above the water (the hull's waist).
const SHIP_DECK := 0.6

const KINDS := {
	"raft": {"name": "Raft", "cost": {"wood": 12}, "speed": 1.2, "deep": false,
		"about": "Logs lashed together. Crosses lakes and the shallows along the coast."},
	"galley": {"name": "Galley", "cost": {"wood": 40, "iron": 4, "hide": 4}, "speed": 1.7, "deep": true,
		"about": "A long ship with a red sail. Crosses the open sea to the islets, and your legion sails with you."},
}

var world: World
var kind := "raft"
var pos := Vector2.ZERO
var facing := Vector2.DOWN
var crewed := false  # the player is aboard

var _model: Node3D
var _sail: MeshInstance3D
var _oars: Array = []
var _t := 0.0


static func info(k: String) -> Dictionary:
	return KINDS.get(k, KINDS["raft"])


func display_name() -> String:
	return str(info(kind)["name"])


func can_cross_deep() -> bool:
	return bool(info(kind)["deep"])


func speed_factor() -> float:
	return float(info(kind)["speed"])


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	if kind == "galley":
		_build_galley()
	else:
		_build_raft()
	_place(0.0)


func _process(delta: float) -> void:
	_t += delta
	_place(delta)


func _place(delta: float) -> void:
	var bob := sin(_t * 1.6 + pos.x * 0.01) * 0.04
	position = Vector3(pos.x / World.TILE, World.WATER_LEVEL + bob, pos.y / World.TILE)
	var target := atan2(facing.x, facing.y)
	rotation.y = lerp_angle(rotation.y, target, minf(delta * 4.0, 1.0)) if delta > 0.0 else target
	_model.rotation.z = sin(_t * 1.1) * 0.03
	for i in _oars.size():
		var oar: Node3D = _oars[i]
		oar.rotation.x = sin(_t * (3.0 if crewed else 0.0) + i * 0.3) * 0.35


## Deck height above the water, for whoever stands on it.
func deck_height() -> float:
	if kind == "galley":
		return SHIP_DECK if use_new_ship else 0.35
	return 0.18


func _build_raft() -> void:
	for i in 5:
		var x := -0.6 + i * 0.3
		Art.part(_model, Art.cylinder(0.14, 0.14, 2.4, 7), Color("7a5634").darkened(i % 2 * 0.08), Vector3(x, 0.05, 0), Vector3(PI / 2, 0, 0))
	for z in [-0.8, 0.8]:
		Art.part(_model, Art.box(Vector3(1.6, 0.06, 0.12)), Color("4d3420"), Vector3(0, 0.2, z))
	Art.part(_model, Art.cylinder(0.04, 0.04, 1.8, 5), Color("6b4a2b"), Vector3(0.45, 0.6, -0.9), Vector3(0.5, 0, 0))  # a pole


func _build_galley() -> void:
	if use_new_ship:
		for path in SHIP_MODELS:
			var part := MeshInstance3D.new()
			part.mesh = load(path)
			if path.ends_with("rigging.res"):
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_model.add_child(part)
		var shadow := MeshInstance3D.new()
		shadow.mesh = load(SHIP_SHADOW)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_model.add_child(shadow)
		return
	var hull := Color("5a3d22")
	var trim := Color("c9a24a")
	# A long hull with a pointed bow and a raised stern.
	Art.part(_model, Art.box(Vector3(1.6, 0.6, 5.2)), hull, Vector3(0, 0.0, 0))
	Art.part(_model, Art.box(Vector3(1.3, 0.08, 5.0)), Color("8f6239"), Vector3(0, 0.32, 0))  # deck
	var bow := Art.part(_model, Art.cylinder(0.0, 1.13, 1.5, 4), hull, Vector3(0, 0.0, 3.3), Vector3(PI / 2, PI / 4, 0))
	bow.scale = Vector3(1.0, 1.0, 0.53)
	Art.part(_model, Art.box(Vector3(0.12, 0.12, 0.9)), Color("8a8f95"), Vector3(0, -0.15, 4.2))  # the ram
	Art.part(_model, Art.box(Vector3(1.6, 0.5, 0.9)), hull, Vector3(0, 0.45, -2.3))  # stern deck
	Art.part(_model, Art.box(Vector3(1.66, 0.08, 5.2)), trim, Vector3(0, 0.28, 0))
	Art.part(_model, Art.cylinder(0.08, 0.6, 0.8, 6), hull, Vector3(0, 0.95, -2.75), Vector3(-0.6, 0, 0))  # curled stern post
	# Mast and a big red square sail.
	Art.part(_model, Art.cylinder(0.08, 0.1, 4.2, 6), Color("6b4a2b"), Vector3(0, 2.3, 0.3))
	Art.part(_model, Art.cylinder(0.05, 0.05, 2.8, 5), Color("6b4a2b"), Vector3(0, 3.9, 0.35), Vector3(0, 0, PI / 2))
	_sail = Art.part(_model, Art.box(Vector3(2.6, 2.2, 0.04)), Color("9e2a24"), Vector3(0, 2.75, 0.4))
	Art.part(_model, Art.box(Vector3(0.9, 0.9, 0.05)), Color("d8b45a"), Vector3(0, 2.8, 0.43), Vector3(0, 0, PI / 4))
	# Oars along both sides.
	for side in [-1.0, 1.0]:
		for i in 5:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.82, 0.25, -1.4 + i * 0.75)
			_model.add_child(pivot)
			Art.part(pivot, Art.box(Vector3(1.4, 0.05, 0.08)), Color("8f6239"), Vector3(side * 0.6, -0.25, 0), Vector3(0, 0, side * 0.45))
			_oars.append(pivot)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
