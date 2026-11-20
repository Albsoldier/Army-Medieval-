## On-screen interface: survival bars, inventory, hints, messages and dialogs.
## Everything is built in code so the project has no hand-edited scene files.
extends CanvasLayer

const HELP_TEXT := """[ Controls ]
WASD / arrows   move
E (hold)          chop, mine, pick, use, read
Space / click   attack
1 – 4              hands, spear, axe, pickaxe
                      (press again to put away)
I / Tab            inventory and crafting
F                    eat         Q   healing salve
C                    campfire   R   torch
M                    island map
N / G              leave a note / a stash
Mouse wheel     zoom
B                    build (1–0 to choose)
X                    take down a building
T                    army: follow me / guard here
Esc                 pause: save, account, sound
H                    show / hide this help

Build a workbench, forge and smokehouse
for tools, iron gear and smoked meat.

Wolves fear fire. Explore to find ruins,
wrecks, caves, shrines and a lighthouse."""
const Minimap = preload("res://scripts/minimap.gd")


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
var minimap: Minimap
var _map_center: CenterContainer
var _big_map: Minimap
var _hurt_overlay: ColorRect
var _dim: ColorRect
var _dialog_center: CenterContainer
var _dialog_title: Label
var _dialog_body: Label
var _dialog_input: LineEdit
var _dialog_buttons: HBoxContainer
var _on_choice := Callable()
var _dismissable := true
var _hotbar: HBoxContainer
var _hotbar_buttons: Array = []
var _on_hotbar := Callable()
var _inv_center: CenterContainer
var _inv_columns: HBoxContainer
var _inv_footer: Label
var _on_inv_action := Callable()


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
	_build_maps()
	_build_hotbar()
	_build_inventory()
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
	_hint_label.offset_top = -112
	_hint_label.offset_bottom = -84
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	_toasts.offset_top = -360
	_toasts.offset_bottom = -140
	_root.add_child(_toasts)


func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _panel_style())
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.anchor_left = 1.0
	_help.anchor_right = 1.0
	_help.offset_left = -300
	_help.offset_right = -12
	_help.offset_top = 214
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
	return _dialog_center.visible or _map_center.visible or _inv_center.visible


# ---------- Hotbar ----------

const HOTBAR_SLOTS := ["Hands", "Spear", "Axe", "Pickaxe"]


func _build_hotbar() -> void:
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	_hotbar.offset_left = -190
	_hotbar.offset_right = 190
	_hotbar.offset_top = -72
	_hotbar.offset_bottom = -14
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hotbar)
	for i in HOTBAR_SLOTS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 54)
		b.focus_mode = Control.FOCUS_NONE  # number keys and Space must not "press" it
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(state, _slot_style(state))
		b.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.55, 0.55))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.9, 0.65))
		b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.9, 0.65))
		b.pressed.connect(_on_slot_pressed.bind(i))
		_hotbar.add_child(b)
		_hotbar_buttons.append(b)


func _slot_style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(4)
	sb.set_border_width_all(2)
	match state:
		"pressed", "hover_pressed":
			sb.bg_color = Color(0.25, 0.17, 0.08, 0.9)
			sb.border_color = Color(1.0, 0.75, 0.35)
		"hover":
			sb.bg_color = Color(0.14, 0.11, 0.08, 0.88)
			sb.border_color = Color(0.85, 0.6, 0.3, 0.8)
		"disabled":
			sb.bg_color = Color(0.05, 0.05, 0.05, 0.55)
			sb.border_color = Color(0.4, 0.4, 0.4, 0.3)
		_:
			sb.bg_color = Color(0.07, 0.06, 0.05, 0.82)
			sb.border_color = Color(0.85, 0.6, 0.3, 0.45)
	return sb


## `on_select` is called with the slot index (0 hands, 1 spear, 2 axe, 3 pickaxe).
func setup_hotbar(on_select: Callable) -> void:
	_on_hotbar = on_select


## `slots`: one {"label": String, "owned": bool} per slot; `active` is the slot in hand.
func update_hotbar(slots: Array, active: int) -> void:
	for i in _hotbar_buttons.size():
		var b: Button = _hotbar_buttons[i]
		var slot: Dictionary = slots[i]
		var text := "%d\n%s" % [i + 1, slot["label"]]
		if b.text != text:
			b.text = text
		b.disabled = not bool(slot["owned"])
		b.set_pressed_no_signal(i == active)
		b.tooltip_text = "" if slot["owned"] else "You don't have one yet."


func hotbar_slot_label(i: int) -> String:
	return (_hotbar_buttons[i] as Button).text


func _on_slot_pressed(i: int) -> void:
	if _on_hotbar.is_valid():
		_on_hotbar.call(i)


func set_hotbar_visible(shown: bool) -> void:
	_hotbar.visible = shown


# ---------- Inventory ----------

func _build_inventory() -> void:
	_inv_center = CenterContainer.new()
	_inv_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_inv_center.visible = false
	_root.add_child(_inv_center)
	var panel := PanelContainer.new()
	var sb := _panel_style()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.94)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	_inv_center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label(22, Color(1.0, 0.85, 0.6))
	title.text = "Inventory"
	box.add_child(title)
	_inv_columns = HBoxContainer.new()
	_inv_columns.add_theme_constant_override("separation", 28)
	box.add_child(_inv_columns)
	_inv_footer = _label(12, Color(0.75, 0.72, 0.66))
	_inv_footer.text = "Click to use, equip or craft.   1–4 hotbar   ·   I, Tab or Esc to close"
	box.add_child(_inv_footer)


## Shows (or refreshes) the inventory. `columns` is an Array of columns; each column
## is an Array of sections {"title": String, "rows": [{"name", "detail", "button", "action", "enabled", "dim"}]}.
## `on_action` is called with a row's "action" when its button is pressed.
func show_inventory(columns: Array, on_action: Callable) -> void:
	_on_inv_action = on_action
	for child in _inv_columns.get_children():
		_inv_columns.remove_child(child)
		child.queue_free()
	for column in columns:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.custom_minimum_size = Vector2(330, 0)
		_inv_columns.add_child(col)
		for section in column:
			var head := _label(15, Color(1.0, 0.78, 0.45))
			head.text = section["title"]
			col.add_child(head)
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 4)
			col.add_child(grid)
			for row in section["rows"]:
				var dim: bool = row.get("dim", false)
				var name_label := _label(14, Color(0.95, 0.92, 0.85, 0.45 if dim else 1.0))
				name_label.text = row["name"]
				name_label.custom_minimum_size = Vector2(120, 0)
				grid.add_child(name_label)
				var detail := _label(13, Color(0.8, 0.78, 0.72, 0.45 if dim else 0.95))
				detail.text = row.get("detail", "")
				detail.custom_minimum_size = Vector2(110, 0)
				grid.add_child(detail)
				var label: String = row.get("button", "")
				if label == "":
					grid.add_child(Control.new())
					continue
				var b := Button.new()
				b.text = label
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(84, 26)
				b.add_theme_font_size_override("font_size", 13)
				b.disabled = not row.get("enabled", true)
				b.set_meta("action", str(row.get("action", "")))
				b.pressed.connect(_on_inv_pressed.bind(str(row.get("action", ""))))
				grid.add_child(b)
			if section["rows"].is_empty():
				var none := _label(13, Color(0.7, 0.68, 0.62))
				none.text = "Nothing yet."
				col.add_child(none)
	_inv_center.visible = true


func close_inventory() -> void:
	_inv_center.visible = false


func is_inventory_open() -> bool:
	return _inv_center.visible


## The buttons currently in the inventory, by action (for tests).
func inventory_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _inv_columns.find_children("*", "Button", true, false):
		if not (b as Button).disabled:
			out.append(str((b as Button).get_meta("action", "")))
	return out


func _on_inv_pressed(action: String) -> void:
	if _on_inv_action.is_valid():
		_on_inv_action.call(action)


func _build_maps() -> void:
	minimap = Minimap.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -202
	minimap.offset_right = -12
	minimap.offset_top = 12
	minimap.offset_bottom = 202
	_root.add_child(minimap)

	_map_center = CenterContainer.new()
	_map_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_center.visible = false
	_root.add_child(_map_center)
	var panel := PanelContainer.new()
	var parchment := StyleBoxFlat.new()  # the island map is drawn on old parchment
	parchment.bg_color = Color(0.86, 0.79, 0.63)
	parchment.border_color = Color(0.36, 0.27, 0.17)
	parchment.set_border_width_all(3)
	parchment.set_corner_radius_all(4)
	parchment.set_content_margin_all(16)
	parchment.shadow_color = Color(0, 0, 0, 0.5)
	parchment.shadow_size = 12
	panel.add_theme_stylebox_override("panel", parchment)
	_map_center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := _label(22, Color(0.27, 0.19, 0.11))
	title.text = "Lantern Skerry"
	box.add_child(title)
	_big_map = Minimap.new()
	_big_map.full = true
	_big_map.custom_minimum_size = Vector2(560, 560)
	box.add_child(_big_map)
	var legend := _label(12, Color(0.3, 0.22, 0.13))
	legend.text = "◆ places you've found   ■ your buildings   ● campfires   ✝ graves   ▲ you      M or Esc to close"
	box.add_child(legend)


## Connects both maps to the world and to a function that returns the markers.
func setup_maps(world: Node3D, markers: Callable) -> void:
	minimap.world = world
	minimap.get_markers = markers
	_big_map.world = world
	_big_map.get_markers = markers


func toggle_map() -> void:
	_map_center.visible = not _map_center.visible


func is_map_open() -> bool:
	return _map_center.visible


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
	if _inv_center.visible and not _dialog_center.visible:
		var inv_key := event as InputEventKey
		if inv_key and inv_key.pressed and not inv_key.echo:
			if inv_key.keycode == KEY_ESCAPE or inv_key.physical_keycode in [KEY_I, KEY_TAB]:
				_inv_center.visible = false
				get_viewport().set_input_as_handled()
			elif inv_key.physical_keycode >= KEY_1 and inv_key.physical_keycode <= KEY_4:
				_on_slot_pressed(inv_key.physical_keycode - KEY_1)
				get_viewport().set_input_as_handled()
		return
	if _map_center.visible and not _dialog_center.visible:
		var map_key := event as InputEventKey
		if map_key and map_key.pressed and not map_key.echo and (map_key.keycode == KEY_ESCAPE or map_key.physical_keycode == KEY_M):
			_map_center.visible = false
			get_viewport().set_input_as_handled()
		return
	if not _dialog_center.visible or not _dismissable:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_choose(-1)
		get_viewport().set_input_as_handled()
