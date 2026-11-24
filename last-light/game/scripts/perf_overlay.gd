## Developer performance overlay: FPS, frame time, draw calls, primitives and
## memory, from Godot's own monitors (Performance and RenderingServer).
##
## Off for players. It exists only when one of these is true:
##   - a debug build (running from the editor),
##   - the web page was opened with ?perf in the URL (index.html?perf=1),
##   - the command line has --perf (godot ... -- --perf),
##   - the project setting last_light/debug/perf_overlay is true.
## When it exists, F3 shows and hides it. It starts visible only when asked
## for (?perf, --perf or the setting); in a plain debug build it starts hidden.
extends CanvasLayer

const SAMPLE_WINDOW := 1.0  # seconds of frames behind the "worst" and "avg" figures
const REFRESH := 0.25  # seconds between text updates
const JS_MEMORY := "(performance && performance.memory) ? performance.memory.usedJSHeapSize : -1"

var shown := true
var _label: Label
var _panel: PanelContainer
var _last_usec := 0
var _frames: Array = []  # [time_s, frame_ms] for the last SAMPLE_WINDOW seconds
var _clock := 0.0
var _refresh := 0.0
var _js_heap := -1.0
var _js_timer := 0.0


## Whether this build/page should have the overlay at all.
static func enabled() -> bool:
	return OS.is_debug_build() or requested()


## Whether someone asked for it explicitly (then it starts visible).
static func requested() -> bool:
	if bool(ProjectSettings.get_setting("last_light/debug/perf_overlay", false)):
		return true
	if "--perf" in OS.get_cmdline_user_args():
		return true
	return url_flag("perf")


## The value of ?<name>=... in the web page URL, or "".
static func url_value(name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % name, true)
	return str(v) if typeof(v) == TYPE_STRING else ""


## True if the web page URL has ?<flag> (with any value but "0").
static func url_flag(flag: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("(function(){var p=new URLSearchParams(window.location.search);return p.has('%s')?(p.get('%s')||'1'):'';})()" % [flag, flag], true)
	return typeof(v) == TYPE_STRING and str(v) != "" and str(v) != "0"


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	# Top right, out of the way of the status card.
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(get_viewport().get_visible_rect().size.x - 300, 8)
	_last_usec = Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_set_shown(shown)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		_set_shown(not shown)
		get_viewport().set_input_as_handled()


func _set_shown(on: bool) -> void:
	shown = on
	_panel.visible = on


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_clock += delta
	_frames.append([_clock, frame_ms])
	while not _frames.is_empty() and _clock - float(_frames[0][0]) > SAMPLE_WINDOW:
		_frames.pop_front()
	if OS.has_feature("web"):
		_js_timer -= delta
		if _js_timer <= 0.0:
			_js_timer = 1.0
			var v: Variant = JavaScriptBridge.eval(JS_MEMORY, true)
			_js_heap = float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else -1.0
	_refresh -= delta
	if shown and _refresh <= 0.0:
		_refresh = REFRESH
		# Top right, under the minimap.
		_panel.position = Vector2(get_viewport().get_visible_rect().size.x - _panel.size.x - 8, 214)
		_label.text = _text(snapshot())


## Everything the overlay knows right now. -1 means "not available here".
func snapshot() -> Dictionary:
	var avg := 0.0
	var worst := 0.0
	for f in _frames:
		avg += float(f[1])
		worst = maxf(worst, float(f[1]))
	avg /= maxf(_frames.size(), 1.0)
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": avg,
		"frame_ms_worst": worst,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu(),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture_mem": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_mem": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"static_mem": static_mem if static_mem > 0.0 else -1.0,  # only tracked in debug builds
		"js_heap": _js_heap,  # Chrome's performance.memory; -1 elsewhere
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}


static func _mb(bytes: float) -> String:
	return "n/a" if bytes < 0.0 else "%.1f MB" % (bytes / 1048576.0)


func _text(s: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		"FPS %d   frame %.1f ms (worst %.1f)" % [s["fps"], s["frame_ms"], s["frame_ms_worst"]],
		"Process %.1f ms   render CPU %.1f   GPU %s" % [s["process_ms"], s["render_cpu_ms"],
			"%.1f ms" % s["render_gpu_ms"] if s["render_gpu_ms"] > 0.0 else "n/a"],
		"Draw calls %d" % s["draw_calls"],
		"Primitives %s   objects %d" % [_thousands(int(s["primitives"])), s["objects"]],
		"Video mem %s (tex %s, buf %s)" % [_mb(s["video_mem"]), _mb(s["texture_mem"]), _mb(s["buffer_mem"])],
		"Static mem %s   JS heap %s" % [_mb(s["static_mem"]), _mb(s["js_heap"])],
		"Nodes %d   %s" % [s["nodes"], str(s["renderer"])],
		"F3 hide",
	]))


static func _thousands(n: int) -> String:
	var t := str(n)
	var out := ""
	while t.length() > 3:
		out = "," + t.right(3) + out
		t = t.left(t.length() - 3)
	return t + out
