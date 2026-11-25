## Real-GPU validation of the environment prototype (phase 4A,
## GRAPHICS_ENVIRONMENT_GPU_VALIDATION.md). Starts only when the web page is
## opened with ?gpuval=1. Never runs for players.
##
## One URL runs the whole test by itself: six page loads, three rounds of
## the nature models and the old props (?nature=0), in alternating order
## (A B, B A, A B) so warm-up and heat don't favour either. Each load waits
## for shaders and assets, then measures the same forest scenes with the
## same seed, spot, camera, season and settings. Results are kept in the
## browser's localStorage between loads; the last load shows the medians on
## screen and downloads them as islander-gpu-validation.json.
##
## Like the benchmark, it runs offline and never saves.
extends "res://scripts/perf_bench.gd"

const KEY := "islander_gpuval"
const PLAN := ["1", "0", "0", "1", "1", "0"]  # nature models on/off per page load
const SETTLE := 2.0  # seconds after a change before measuring
const MEASURE := 6.0  # seconds measured per scene
const WALK := 10.0  # seconds walking through the forest
const WALK_SPEED := 120.0  # game units a second: about walking pace

var _label: Label
var _step := -1
var _spinning := false
var _quick := false  # ?quick=1: two short page loads, only for checking the test itself


static func requested() -> bool:
	return PerfOverlay.url_flag("gpuval")


func _run() -> void:
	_make_label()
	_quick = PerfOverlay.url_flag("quick")
	if not OS.has_feature("web"):
		_show("GPU validation runs in the browser only (index.html?gpuval=1).")
		return
	var step_text := PerfOverlay.url_value("step")
	if step_text == "":
		# A fresh start: clear old results and load the first version.
		_js("try { localStorage.setItem('%s', JSON.stringify({results: [], started: Date.now()})); } catch (e) {}" % KEY)
		_goto_step(0)
		return
	_step = int(step_text)
	var on: bool = main.world.nature_models
	_show("GPU validation: page %d of %d (%s). Measuring, please don't touch the mouse or keyboard." % [
		_step + 1, _pages(), "nature models" if on else "old props"])
	await _frames(5)
	if main.hud.is_modal():
		main.hud._choose(0)
	main.hud.toggle_help()
	main.rng.seed = 20261124  # the same standing spots every run
	var spots := _find_spots()
	var forest: Vector2 = spots["forest"]
	_note("environment", _environment(on, forest))

	# Let shaders compile and assets load: visit every view and season once.
	var warm_start := Time.get_ticks_usec()
	var warm_ms: Array = []
	_set_season("spring")
	_day()
	_go(forest)
	for zoom in [1.6, 3.2, 0.55]:
		main.zoom = zoom
		warm_ms.append_array(await _spin(_secs(1.5)))
	for season in ["summer", "winter", "spring"]:
		_set_season(season)
		warm_ms.append_array(await _hold(_secs(1.0)))
	_night(true)
	warm_ms.append_array(await _hold(_secs(1.0)))
	_night(false)
	warm_ms.append_array(await _hold(_secs(1.0)))
	warm_ms.sort()
	_note("warmup", {"scene": "warmup", "seconds": snappedf((Time.get_ticks_usec() - warm_start) / 1e6, 0.01),
		"frame_ms_max": snappedf(float(warm_ms[-1]), 0.1), "frames_over_100ms": warm_ms.filter(func(f): return f > 100.0).size(),
		"frames_over_250ms": warm_ms.filter(func(f): return f > 250.0).size(), "frames": warm_ms.size()})

	# The scenes. Every one starts from the same spot and camera direction.
	await _scene("forest_mid", forest, 1.6)
	await _scene("forest_zoom_max", forest, 3.2)
	await _scene("forest_zoom_min", forest, 0.55)
	_reset(forest, 1.6)
	await _wait(_secs(SETTLE))
	await _sample_rotating("forest_rotate")
	_reset(forest, 1.6)
	await _wait(_secs(SETTLE))
	await _sample("forest_walk", forest, _walk_direction(forest) * WALK_SPEED, _secs(WALK))
	_night(true)
	await _scene("forest_night", forest, 1.6)
	_night(false)
	_set_season("summer")
	await _scene("forest_summer", forest, 1.6)
	_set_season("winter")
	await _scene("forest_winter", forest, 1.6)
	_set_season("spring")

	_save_results()
	if _step + 1 < _pages():
		_show("GPU validation: page %d of %d done, loading the next one..." % [_step + 1, _pages()])
		await _frames(10)
		_goto_step(_step + 1)
	else:
		_finish()


# ---------- Scenes ----------

func _scene(scene: String, at: Vector2, zoom: float) -> void:
	_reset(at, zoom)
	await _wait(_secs(SETTLE))
	await _sample(scene, Vector2.ZERO, Vector2.ZERO, _secs(MEASURE))


## Back to the spot, the same zoom and camera direction (north-west, like the
## report's screenshots).
func _reset(at: Vector2, zoom: float) -> void:
	_go(at)
	main.zoom = zoom
	main.cam_yaw = 0.6
	main._update_camera(1.0)


func _set_season(season: String) -> void:
	main.world.set_season(season)
	main._update_weather()
	main.world.update_view(main.player.pos, true)


func _night(on: bool) -> void:
	main.clock = main.DAY_LENGTH * (0.85 if on else 0.25)
	main.player.torch_time = 9999.0 if on else 0.0  # your torch lit at night, as you'd play
	main._update_lighting()


## A full turn of the camera over `seconds`; returns the frame times.
func _spin(seconds: float) -> Array:
	var ms: Array = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		_keep_alive()
		main.cam_yaw = 0.6 + TAU * (Time.get_ticks_usec() - start) / (seconds * 1e6)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	main.cam_yaw = 0.6
	return ms


func _hold(seconds: float) -> Array:
	var ms: Array = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		_keep_alive()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	return ms


## The camera turns once around the player while measuring (8 seconds).
func _sample_rotating(scene: String) -> void:
	_spinning = true
	_turn_camera()
	await _sample(scene, Vector2.ZERO, Vector2.ZERO, _secs(8.0))
	_spinning = false
	main.cam_yaw = 0.6


func _turn_camera() -> void:
	var start := Time.get_ticks_usec()
	while _spinning:
		main.cam_yaw = 0.6 + TAU * (Time.get_ticks_usec() - start) / 8e6
		await get_tree().process_frame


## The direction from `from` that stays in the forest longest (the same every run).
func _walk_direction(from: Vector2) -> Vector2:
	var w = main.world
	var best := Vector2.RIGHT
	var best_score := -1
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		var score := 0
		for s in 40:
			var c: Vector2i = w.cell_of(from + d * s * 32.0)
			if w.is_land(c):
				score += 2 if w.terrain_at(c) == w.FOREST else 1
		if score > best_score:
			best_score = score
			best = d
	return best


# ---------- Results ----------

func _environment(on: bool, forest: Vector2) -> Dictionary:
	var info: Variant = JavaScriptBridge.eval("""(function () {
		var r = {ua: navigator.userAgent, cores: navigator.hardwareConcurrency || -1,
			memory_gb: navigator.deviceMemory || -1, dpr: window.devicePixelRatio,
			window: window.innerWidth + 'x' + window.innerHeight, screen: screen.width + 'x' + screen.height,
			page_load_ms: Math.round(performance.now())};
		try {
			var g = document.createElement('canvas').getContext('webgl2');
			var d = g.getExtension('WEBGL_debug_renderer_info');
			r.gpu = d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER);
			r.gpu_vendor = d ? g.getParameter(d.UNMASKED_VENDOR_WEBGL) : g.getParameter(g.VENDOR);
			r.s3tc = !!g.getExtension('WEBGL_compressed_texture_s3tc');
		} catch (e) { r.gpu = 'unknown'; }
		return JSON.stringify(r);
	})()""", true)
	var d: Dictionary = JSON.parse_string(str(info)) if info != null else {}
	d["version"] = "nature models" if on else "old props"
	d["nature"] = on
	d["step"] = _step
	d["round"] = _step / 2 + 1
	d["viewport"] = str(get_viewport().get_visible_rect().size)
	d["shadow_preset"] = main.sun_shadow_preset
	d["forest_spot"] = str(forest)
	return d


func _save_results() -> void:
	var mine := JSON.stringify(results)
	_js("""try { var s = JSON.parse(localStorage.getItem('%s') || '{"results":[]}');
		s.results.push(%s); localStorage.setItem('%s', JSON.stringify(s)); } catch (e) { console.log('GPUVAL storage error ' + e); }""" % [KEY, mine, KEY])


func _goto_step(step: int) -> void:
	_js("location.replace(location.pathname + '?gpuval=1&perf=1&step=%d&nature=%s%s');" % [step, PLAN[step], "&quick=1" if _quick else ""])


## Medians across the rounds, per version and scene; shown on screen and downloaded.
func _finish() -> void:
	var raw: Variant = JavaScriptBridge.eval("localStorage.getItem('%s')" % KEY, true)
	var all: Dictionary = JSON.parse_string(str(raw)) if raw != null else {}
	var runs: Array = all.get("results", [])
	var keys := ["fps_avg", "frame_ms_avg", "frame_ms_p50", "fps_1pct_low", "frame_ms_max", "draw_calls_avg",
		"primitives_avg", "video_mem_mb", "texture_mem_mb", "cpu_process_ms_avg", "render_cpu_ms_avg", "render_gpu_ms_avg"]
	var by: Dictionary = {}  # "version|scene" -> key -> [values]
	var env := {}
	for run in runs:
		var version := ""
		for rec in run:
			if rec.get("label") == "environment":
				version = rec.get("version", "")
				env = rec
				continue
			var id: String = "%s|%s" % [version, rec.get("scene", rec.get("label"))]
			if not by.has(id):
				by[id] = {}
			for k in keys + ["frames_over_100ms", "frames_over_250ms", "seconds", "frames_over_50ms"]:
				if rec.has(k):
					if not by[id].has(k):
						by[id][k] = []
					by[id][k].append(float(rec[k]))
	var medians := {}
	for id in by:
		medians[id] = {}
		for k in by[id]:
			medians[id][k] = _median(by[id][k])
	var summary := {"gpu": env.get("gpu", "?"), "browser": env.get("ua", "?"), "window": env.get("window", "?"),
		"dpr": env.get("dpr", "?"), "runs": runs.size(), "medians": medians, "runs_raw": runs}
	var text := "GPU validation finished (%d page loads).\nGPU: %s\n\n%-18s %-14s %8s %8s %8s %7s %9s\n" % [
		runs.size(), summary["gpu"], "scene", "version", "fps", "ms p50", "1% low", "draws", "prims"]
	var scenes := ["forest_mid", "forest_zoom_max", "forest_zoom_min", "forest_rotate", "forest_walk", "forest_night", "forest_summer", "forest_winter"]
	for scene in scenes:
		for version in ["old props", "nature models"]:
			var m: Dictionary = medians.get("%s|%s" % [version, scene], {})
			text += "%-18s %-14s %8.1f %8.1f %8.1f %7d %8.2fM\n" % [scene, version, m.get("fps_avg", 0.0),
				m.get("frame_ms_p50", 0.0), m.get("fps_1pct_low", 0.0), int(m.get("draw_calls_avg", 0)), m.get("primitives_avg", 0.0) / 1e6]
	text += "\nThe full results were downloaded as islander-gpu-validation.json.\nPlease attach that file (or paste this screen) in the chat."
	_show(text)
	var json := JSON.stringify(summary, " ")
	print("GPUVAL_DONE " + JSON.stringify(medians))
	JavaScriptBridge.eval("window.gpuValidation = %s; window.perfDone = true;" % JSON.stringify(summary), true)
	JavaScriptBridge.download_buffer(json.to_utf8_buffer(), "islander-gpu-validation.json", "application/json")


func _pages() -> int:
	return 2 if _quick else PLAN.size()


## Seconds for a measurement (much shorter in the quick check).
func _secs(seconds: float) -> float:
	return 1.0 if _quick else seconds


static func _median(values: Array) -> float:
	var v := values.duplicate()
	v.sort()
	if v.is_empty():
		return 0.0
	var mid := v.size() / 2
	return float(v[mid]) if v.size() % 2 == 1 else (float(v[mid - 1]) + float(v[mid])) / 2.0


func _js(code: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(code, true)


func _make_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace"])
	_label.add_theme_font_override("font", mono)
	panel.add_child(_label)


func _show(text: String) -> void:
	if _label:
		_label.text = text
	print("GPUVAL " + text)
