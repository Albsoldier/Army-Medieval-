## On-screen interface: survival bars, inventory, hints, messages and dialogs.
## Everything is built in code so the project has no hand-edited scene files.
extends CanvasLayer

const HELP_TEXT := """[ Controls ]
WASD / arrows   move
E (hold)          chop, mine, pick, use, read
Space / click   attack
F                    eat
N                    write a note for others
G                    leave a stash for others
Mouse wheel     zoom
Esc                 pause menu: save, account
H                    show / hide this help

[ Crafting ]
1  Campfire    5 wood, 3 stone
2  Torch         2 wood
3  Spear         3 wood, 2 stone

Stay fed, stay warm, stay sane.
Wolves hunt at night but fear fire.
Cook raw meat at a fire."""


class StatBars extends Control:
	const NAMES := ["Health", "Hunger", "Warmth", "Sanity"]
	const COLORS := [Color("d9534f"), Color("e0a040"), Color("e07a2f"), Color("8e7cc3")]
	var values := [100.0, 100.0, 100.0, 100.0]

	func _draw() -> void:
		var font := get_theme_default_font()
		for i in 4:
			var y := i * 22.0
			draw_string(font, Vector2(0, y + 13), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
			var r := Rect2(62, y + 3, 150, 12)
			draw_rect(r, Color(0, 0, 0, 0.55))
			var v := clampf(float(values[i]) / 100.0, 0.0, 1.0)
			var col: Color = COLORS[i]
			if v < 0.25:
				col = col.lerp(Color.WHITE, 0.35 + 0.35 * sin(Time.get_ticks_msec() / 120.0))
			draw_rect(Rect2(r.position, Vector2(r.size.x * v, r.size.y)), col)
			draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


var _root: Control
var _bars: StatBars
var _island_label: Label
var _day_label: Label
var _inv_label: Label
var _conn_label: Label
var _hint_label: Label
var _toasts: VBoxContainer
var _help: PanelContainer
var _hurt_overlay: ColorRect
var _dim: ColorRect
var _dialog_center: CenterContainer
var _dialog_title: Label
var _dialog_body: Label
var _dialog_input: LineEdit
var _dialog_buttons: HBoxContainer
var _on_choice := Callable()
var _dismissable := true


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_hurt_overlay = ColorRect.new()
	_hurt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_overlay.color = Color(0.7, 0.0, 0.0, 0.0)
	_hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt_overlay)

	_build_status_panel()
	_build_hint_and_toasts()
	_build_help()
	_build_dialog()


func _build_status_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_island_label = _label(15, Color(1.0, 0.85, 0.6))
	box.add_child(_island_label)
	_day_label = _label(13, Color(0.9, 0.9, 0.9))
	box.add_child(_day_label)

	_bars = StatBars.new()
	_bars.custom_minimum_size = Vector2(215, 88)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_bars)

	_inv_label = _label(13, Color(0.95, 0.92, 0.85))
	box.add_child(_inv_label)
	_conn_label = _label(11, Color(0.7, 0.75, 0.8))
	box.add_child(_conn_label)


func _build_hint_and_toasts() -> void:
	_hint_label = _label(16, Color(1, 1, 1))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -64
	_hint_label.offset_bottom = -36
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint_label.add_theme_constant_override("outline_size", 5)
	_root.add_child(_hint_label)

	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = 14
	_toasts.offset_right = 640
	_toasts.offset_top = -300
	_toasts.offset_bottom = -80
	_root.add_child(_toasts)


func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _panel_style())
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.anchor_left = 1.0
	_help.anchor_right = 1.0
	_help.offset_left = -300
	_help.offset_right = -12
	_help.offset_top = 12
	_root.add_child(_help)
	var text := _label(13, Color(0.92, 0.9, 0.85))
	text.text = HELP_TEXT
	_help.add_child(text)


func _build_dialog() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_root.add_child(_dim)

	_dialog_center = CenterContainer.new()
	_dialog_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_center.visible = false
	_root.add_child(_dialog_center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(460, 0)
	_dialog_center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_dialog_title = _label(22, Color(1.0, 0.85, 0.6))
	box.add_child(_dialog_title)
	_dialog_body = _label(15, Color(0.92, 0.9, 0.85))
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_body.custom_minimum_size = Vector2(436, 0)
	box.add_child(_dialog_body)
	_dialog_input = LineEdit.new()
	_dialog_input.text_submitted.connect(_on_input_submitted)
	box.add_child(_dialog_input)
	_dialog_buttons = HBoxContainer.new()
	_dialog_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_dialog_buttons.add_theme_constant_override("separation", 10)
	box.add_child(_dialog_buttons)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.82)
	sb.border_color = Color(0.85, 0.6, 0.3, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


# ---------- Public API used by main.gd ----------

func set_island(island_name: String, subtitle: String) -> void:
	_island_label.text = "%s  ·  %s" % [island_name, subtitle]


func set_connection(text: String) -> void:
	_conn_label.text = text


func set_hint(text: String) -> void:
	_hint_label.text = text


func toggle_help() -> void:
	_help.visible = not _help.visible


func update_stats(stats: Array, day: int, time_label: String, inventory_text: String) -> void:
	_bars.values = stats
	_bars.queue_redraw()
	_day_label.text = "Day %d  ·  %s" % [day, time_label]
	_inv_label.text = inventory_text


func toast(text: String) -> void:
	var l := _label(14, Color(1, 1, 1))
	l.text = text
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 6:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	var tween := l.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(l.queue_free)


func flash() -> void:
	_hurt_overlay.color.a = 0.35
	var tween := _hurt_overlay.create_tween()
	tween.tween_property(_hurt_overlay, "color:a", 0.0, 0.4)


func is_modal() -> bool:
	return _dialog_center.visible


## Shows a dialog. `on_choice` is called with (button_index, typed_text);
## button_index is -1 when the player closes it with Esc.
func open_dialog(title: String, body: String, buttons: PackedStringArray, on_choice: Callable,
		input_hint: String = "", max_length: int = 140, dismissable: bool = true, secret: bool = false) -> void:
	_on_choice = on_choice
	_dismissable = dismissable
	_dialog_title.text = title
	_dialog_body.text = body
	_dialog_body.visible = body != ""
	_dialog_input.visible = input_hint != ""
	_dialog_input.text = ""
	_dialog_input.placeholder_text = input_hint
	_dialog_input.max_length = max_length
	_dialog_input.secret = secret
	for child in _dialog_buttons.get_children():
		_dialog_buttons.remove_child(child)
		child.queue_free()
	for i in buttons.size():
		var b := Button.new()
		b.text = buttons[i]
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(_choose.bind(i))
		_dialog_buttons.add_child(b)
	_dim.visible = true
	_dialog_center.visible = true
	if _dialog_input.visible:
		_dialog_input.grab_focus.call_deferred()
	elif _dialog_buttons.get_child_count() > 0:
		var first: Button = _dialog_buttons.get_child(0)
		first.grab_focus.call_deferred()


func _on_input_submitted(_text: String) -> void:
	_choose(0)


func _choose(index: int) -> void:
	if not _dialog_center.visible:
		return
	var text := _dialog_input.text.strip_edges()
	_dim.visible = false
	_dialog_center.visible = false
	get_viewport().gui_release_focus()
	var callback := _on_choice
	_on_choice = Callable()
	if callback.is_valid():
		callback.call(index, text)


func _input(event: InputEvent) -> void:
	if not _dialog_center.visible or not _dismissable:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_choose(-1)
		get_viewport().set_input_as_handled()
