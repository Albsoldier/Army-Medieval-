## The minimap (top-right corner) and the full island map (M).
## Draws the explored map from world.gd plus markers that main.gd provides.
extends Control

const World = preload("res://scripts/world.gd")

const COLORS := {
	"player": Color(1, 1, 1),
	"home": Color(1.0, 0.82, 0.35),
	"wall": Color(0.75, 0.72, 0.66),
	"building": Color(0.85, 0.55, 0.3),
	"fire": Color(1.0, 0.55, 0.15),
	"soldiers": Color(0.85, 0.25, 0.25),
	"grave": Color(0.8, 0.8, 0.85),
	"note": Color(0.95, 0.92, 0.8),
	"stash": Color(0.95, 0.75, 0.25),
	"bag": Color(0.7, 0.5, 0.3),
	"poi": Color(0.45, 0.85, 1.0),
	"poi_looted": Color(0.45, 0.6, 0.7),
}

var world: World
## Returns {"player": Vector2, "facing": Vector2, "items": [[kind, Vector2 pos, label], ...]}
var get_markers := Callable()
var full := false  # true for the big island map
var span_tiles := 160.0  # how many tiles the minimap shows across

var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # smooth coastlines, not squares


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if world == null or world.map_texture == null or not get_markers.is_valid():
		return
	var m: Dictionary = get_markers.call()
	var player: Vector2 = m["player"]
	var map_px := Vector2(world.map_image.get_size())
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, World.UNEXPLORED)

	# Which part of the map (in map pixels) is shown in this control.
	var src: Rect2
	if full:
		src = Rect2(Vector2.ZERO, map_px)
	else:
		var center := player / World.TILE / World.MAP_SCALE
		var half := span_tiles / World.MAP_SCALE / 2.0
		src = Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_texture_rect_region(world.map_texture, rect, src)

	var to_screen := func(game_pos: Vector2) -> Vector2:
		var map_pos := game_pos / World.TILE / World.MAP_SCALE
		return (map_pos - src.position) / src.size * size

	var labels := []
	for item in m["items"]:
		var kind: String = item[0]
		var p: Vector2 = to_screen.call(item[1])
		if not rect.grow(-2).has_point(p):
			continue
		var c: Color = COLORS.get(kind, Color.WHITE)
		match kind:
			"wall":
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c)
			"building":
				draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), c)
			"home":
				_draw_house(p, c)
			"fire":
				draw_circle(p, 3.0, c)
			"soldiers":
				draw_circle(p, 2.0, c)
			"grave":
				draw_line(p + Vector2(0, -4), p + Vector2(0, 4), c, 1.5)
				draw_line(p + Vector2(-2.5, -1.5), p + Vector2(2.5, -1.5), c, 1.5)
			"poi", "poi_looted":
				var d := 6.0 if full else 4.5
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), c)
				draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), Color(0, 0, 0, 0.6), 1.0)
				if full and item.size() > 2:
					labels.append([p, str(item[2])])
			_:
				draw_circle(p, 2.2, c)

	for l in labels:
		var at: Vector2 = l[0] + Vector2(9, 4)
		draw_string_outline(_font, at, l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, at, l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))

	# You: an arrow pointing the way you face.
	var me: Vector2 = to_screen.call(player)
	var f: Vector2 = m["facing"]
	if f.length() < 0.1:
		f = Vector2.DOWN
	f = f.normalized()
	var s := 7.0 if full else 6.0
	var tip := me + f * s
	var left := me - f * s * 0.6 + f.orthogonal() * s * 0.65
	var right := me - f * s * 0.6 - f.orthogonal() * s * 0.65
	draw_colored_polygon(PackedVector2Array([tip, left, right]), COLORS["player"])
	draw_polyline(PackedVector2Array([tip, left, right, tip]), Color(0, 0, 0, 0.8), 1.2)

	# North marker and frame.
	draw_string_outline(_font, Vector2(size.x / 2 - 4, 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(size.x / 2 - 4, 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.92, 0.75))
	draw_rect(rect, Color(0.36, 0.27, 0.17, 0.9), false, 2.0)


func _draw_house(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 5)), c)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4.5, -1), p + Vector2(0, -5), p + Vector2(4.5, -1)]), c)
