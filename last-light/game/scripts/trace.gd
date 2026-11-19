## Something another survivor left on this island: a grave, a note or a stash.
extends Node3D

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/art.gd")

var world: World
var pos := Vector2.ZERO
var data: Dictionary = {}
var kind := ""
var was_read := false
var _marker: MeshInstance3D
var _t := 0.0


func setup(d: Dictionary) -> void:
	data = d
	kind = str(d.get("kind", ""))
	pos = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))


func _ready() -> void:
	position = world.to_3d(pos)
	rotation.y = float(absi(hash(trace_id())) % 628) / 100.0
	match kind:
		"grave":
			var mound := Art.part(self, Art.sphere(0.45, 3, 8), Color("5b4430"), Vector3(0, 0.0, 0.1))
			mound.scale = Vector3(0.9, 0.4, 1.5)
			Art.part(self, Art.box(Vector3(0.5, 0.7, 0.12)), Color("8d8a85"), Vector3(0, 0.38, -0.55), Vector3(-0.08, 0, 0.05))
			Art.part(self, Art.cylinder(0.25, 0.25, 0.12, 10), Color("8d8a85"), Vector3(0, 0.73, -0.57), Vector3(PI / 2 - 0.08, 0, 0))
			Art.part(self, Art.box(Vector3(0.05, 0.3, 0.02)), Color("4a4846"), Vector3(0, 0.55, -0.48))
			Art.part(self, Art.box(Vector3(0.2, 0.05, 0.02)), Color("4a4846"), Vector3(0, 0.6, -0.48))
		"note":
			Art.part(self, Art.cylinder(0.025, 0.03, 0.8, 5), Color("6b4a2b"), Vector3(0, 0.4, 0))
			Art.part(self, Art.box(Vector3(0.32, 0.4, 0.015)), Color("efe6cf"), Vector3(0, 0.62, 0.035), Vector3(0, 0, 0.06))
			for i in 3:
				Art.part(self, Art.box(Vector3(0.22, 0.015, 0.005)), Color("7a6f5c"), Vector3(0, 0.7 - i * 0.07, 0.045))
		"stash":
			Art.part(self, Art.box(Vector3(0.62, 0.36, 0.42)), Color("7a5230"), Vector3(0, 0.18, 0))
			Art.part(self, Art.box(Vector3(0.66, 0.1, 0.46)), Color("8f6239"), Vector3(0, 0.41, 0))
			Art.part(self, Art.box(Vector3(0.66, 0.06, 0.06)), Color("3d2a18"), Vector3(0, 0.22, 0.2))
			Art.part(self, Art.box(Vector3(0.08, 0.1, 0.03)), Color("d4b25a"), Vector3(0, 0.33, 0.23), Vector3.ZERO, 1.5)
		"bag":
			# Your own belongings, left where you fell.
			var sack := Art.part(self, Art.sphere(0.3, 4, 8), Color("8a6a43"), Vector3(0, 0.22, 0))
			sack.scale = Vector3(1.0, 0.85, 0.9)
			Art.part(self, Art.cylinder(0.06, 0.12, 0.16, 6), Color("7a5c38"), Vector3(0, 0.5, 0))
			Art.part(self, Art.cylinder(0.075, 0.075, 0.04, 6), Color("3d2a18"), Vector3(0, 0.46, 0))
	# A small glowing marker over things you haven't looked at yet.
	_marker = Art.part(self, Art.sphere(0.08, 3, 6), Color(1.0, 0.9, 0.45), Vector3(0, 1.3, 0), Vector3.ZERO, 3.0, true)
	_marker.visible = not was_read


func _process(delta: float) -> void:
	if _marker.visible:
		_t += delta
		_marker.position.y = 1.3 + sin(_t * 3.0) * 0.1


func mark_read() -> void:
	was_read = true
	if _marker:
		_marker.visible = kind == "stash"


func trace_id() -> String:
	return str(data.get("id", ""))


func author() -> String:
	var n := str(data.get("player_name", ""))
	return n if n != "" else "a stranger"


func message() -> String:
	return str(data.get("text", ""))


func days() -> int:
	return int(data.get("days", 0))


func items() -> Dictionary:
	var v: Variant = data.get("items", {})
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


func is_own(player_id: String) -> bool:
	return player_id != "" and str(data.get("player_id", "")) == player_id
