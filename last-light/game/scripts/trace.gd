## Something another survivor left on this island: a grave, a note or a stash.
extends Node2D

var data: Dictionary = {}
var kind := ""
var was_read := false


func setup(d: Dictionary) -> void:
	data = d
	kind = str(d.get("kind", ""))
	position = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	queue_redraw()


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


func _draw() -> void:
	draw_circle(Vector2(0, 4), 5.0, Color(0, 0, 0, 0.2))
	match kind:
		"grave":
			draw_rect(Rect2(-5, -7, 10, 11), Color("8d8a85"))
			draw_circle(Vector2(0, -7), 5.0, Color("8d8a85"))
			draw_line(Vector2(0, -9), Vector2(0, 0), Color("4a4846"), 1.2)
			draw_line(Vector2(-3, -6), Vector2(3, -6), Color("4a4846"), 1.2)
			draw_rect(Rect2(-6, 3, 12, 3), Color("4d3a26"))
		"note":
			draw_set_transform(Vector2.ZERO, -0.2)
			draw_rect(Rect2(-4, -5, 8, 10), Color("efe6cf"))
			for i in 3:
				draw_line(Vector2(-2.5, -2.5 + i * 2.5), Vector2(2.5, -2.5 + i * 2.5), Color("7a6f5c"), 0.8)
			draw_set_transform(Vector2.ZERO, 0.0)
			if not was_read:
				draw_circle(Vector2(5, -7), 1.6, Color(1, 0.9, 0.4))
		"stash":
			draw_rect(Rect2(-6, -4, 12, 9), Color("7a5230"))
			draw_rect(Rect2(-6, -4, 12, 3), Color("8f6239"))
			draw_rect(Rect2(-1, -2, 2, 3), Color("d4b25a"))
