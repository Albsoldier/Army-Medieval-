## Developer benchmark: plays a fixed set of scenes and measures each one,
## for GRAPHICS_BASELINE.md. Never runs for players: it starts only when the
## web page is opened with ?bench (index.html?bench=1&perf=1) or the command
## line has --bench.
##
## While it runs, the game is offline and never saves, so it can't touch a
## real save or the island server. Results go to the console as lines that
## start with PERF_RESULT (JSON), and to window.perfResults on the web.
extends Node

const PerfOverlay = preload("res://scripts/perf_overlay.gd")
const WARMUP := 3.0  # seconds to settle before measuring
const SAMPLE := 6.0  # seconds measured per scene
const TRAVEL := 14.0  # seconds of travel for the area-transition run (about 6 chunks)

var main: Node
var results: Array = []


static func requested() -> bool:
	return "--bench" in OS.get_cmdline_user_args() or PerfOverlay.url_flag("bench")


func _ready() -> void:
	main = get_parent()
	main.bench_mode = true  # no saving
	main.api.base_url = ""  # no network
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	if main.hud.is_modal():
		main.hud._choose(0)  # "Begin", as a wanderer
	main.hud.toggle_help()
	main.world.set_season("spring")
	_day()
	main.rng.seed = 20261124  # the same standing spots and soldiers every run, so runs compare fairly
	var spots := _find_spots()
	_note("environment", {"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(), "renderer": RenderingServer.get_current_rendering_method(),
		"api": RenderingServer.get_video_adapter_api_version(), "viewport": str(get_viewport().get_visible_rect().size),
		"empty": str(spots["empty"]), "forest": str(spots["forest"]), "village": str(spots["village"])})

	# 1. Empty area: open grassland with few props.
	_go(spots["empty"])
	await _measure("empty_area")
	# 2. Forest: the densest woods near the start.
	_go(spots["forest"])
	await _measure("forest")
	# Diagnostics, not changes: where do the forest's primitives come from?
	main.sun.shadow_enabled = false
	await _measure("diag_forest_no_sun_shadows")
	main.sun.shadow_enabled = true
	_set_props_visible(false)
	await _measure("diag_forest_no_props")
	_set_props_visible(true)
	# 3. Village: a built-up base with cottages, fields, workshops, walls, settlers.
	_go(spots["village"])
	_build_village(spots["village"])
	await _measure("village")
	# 4–5. Soldiers following you around the village.
	_recruit(10)
	await _measure("village_10_soldiers")
	_recruit(20)
	await _measure("village_30_soldiers")
	# 6. The same at night, with the campfire, torch posts and your torch lit.
	main.clock = main.DAY_LENGTH * 0.85
	main.player.torch_time = 9999.0
	main._update_lighting()
	await _measure("night_village_30_soldiers")
	# 7. Area transitions: no army, crossing chunk after chunk at riding pace.
	for s in main.soldiers.duplicate():
		main.soldiers.erase(s)
		s.queue_free()
	main.player.torch_time = 0.0
	_day()
	await _measure_travel("area_transitions", spots["village"])

	print("PERF_DONE")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.perfDone = true;", true)
	else:
		get_tree().quit()


# ---------- Scenes ----------

func _day() -> void:
	main.clock = main.DAY_LENGTH * 0.25
	main._update_lighting()


## Picks an open meadow, the thickest forest, and a clearing for the village,
## all within a few chunks of the start (the same every run: the island is fixed).
func _find_spots() -> Dictionary:
	var w = main.world
	var start: Vector2i = w._chunk_of_cell(w.spawn_cell)
	var best_empty := Vector2i(-99, -99)
	var best_forest := Vector2i(-99, -99)
	var fewest := 1 << 30
	var most_trees := -1
	var counts := {}
	for dz in range(-7, 8):
		for dx in range(-7, 8):
			var ck: Vector2i = start + Vector2i(dx, dz)
			if w._chunk_in_bounds(ck):
				counts[ck] = _prop_counts(ck)
	for ck in counts:
		var props := 0
		var trees := 0
		var ok := true
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var c: Vector2i = ck + Vector2i(ox, oz)
				if not counts.has(c):
					ok = false
					continue
				props += int(counts[c][0])
				trees += int(counts[c][1])
		if not ok:
			continue
		var centre: Vector2i = ck * w.CHUNK + Vector2i(w.CHUNK / 2, w.CHUNK / 2)
		if w.terrain_at(centre) != w.GRASS or _near_camp(w.cell_center(centre)):
			continue
		if _land_share(ck) < 0.9:
			continue
		if props < fewest:
			fewest = props
			best_empty = ck
		if trees > most_trees:
			most_trees = trees
			best_forest = ck
	var empty_pos: Vector2 = w.cell_center(best_empty * w.CHUNK + Vector2i(w.CHUNK / 2, w.CHUNK / 2))
	var forest_pos: Vector2 = w.cell_center(best_forest * w.CHUNK + Vector2i(w.CHUNK / 2, w.CHUNK / 2))
	# Stand on open ground in the forest.
	var open: Vector2 = w.random_walkable_near(forest_pos, 0.0, 60.0, main.rng)
	return {"empty": empty_pos, "forest": open if open != Vector2.INF else forest_pos,
		"village": w.cell_center(w.spawn_cell), "empty_props": fewest, "forest_trees": most_trees}


func _prop_counts(ck: Vector2i) -> Array:
	var props: Dictionary = main.world._chunk_props(ck)
	var trees := 0
	for cell in props:
		if main.world.prop_type(cell) == "tree":
			trees += 1
	return [props.size(), trees]


func _land_share(ck: Vector2i) -> float:
	var w = main.world
	var land := 0
	var n := 0
	for z in range(0, w.CHUNK * 3, 4):
		for x in range(0, w.CHUNK * 3, 4):
			n += 1
			if w.is_land((ck - Vector2i(1, 1)) * w.CHUNK + Vector2i(x, z)):
				land += 1
	return float(land) / float(n)


func _near_camp(pos: Vector2) -> bool:
	for c in main.camps:
		if (c["pos"] as Vector2).distance_to(pos) < 700.0:
			return true
	return false


func _go(pos: Vector2) -> void:
	_clear_enemies()
	main.player.pos = pos
	main.player.facing = Vector2.UP
	main.world.update_view(pos, true)
	main._update_pois(0.0, true)


func _set_props_visible(on: bool) -> void:
	main.world.set_props_visible(on)


func _clear_enemies() -> void:
	for wolf in main.wolves.duplicate():
		main.wolves.erase(wolf)
		wolf.queue_free()
	main._camp_guards.clear()
	main.wolf_spawn_timer = 1e9


## A fixed village around `centre`: cottages, fields, workshops, a tower,
## chests, torch posts, a campfire, walls, and four settlers.
func _build_village(centre: Vector2) -> void:
	var w = main.world
	var plan := ["house", "house", "house", "house", "field", "field", "field", "field", "field", "field",
		"barracks", "workbench", "forge", "smokehouse", "vault", "archer_tower", "chest", "chest",
		"torch_post", "torch_post", "torch_post", "torch_post", "torch_post", "torch_post", "gate", "gate"]
	for i in 20:
		plan.append("wood_wall")
	var free: Array = []
	var c0: Vector2i = w.cell_of(centre)
	for r in range(2, 14):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) == r and free.size() < plan.size() and (dx + dz) % 2 == 0:
					var c: Vector2i = c0 + Vector2i(dx, dz)
					if w.can_build(c):
						free.append(c)
	for i in mini(free.size(), plan.size()):
		var b = main._add_structure(plan[i], free[i])
		if plan[i] == "chest":
			b.items["wheat"] = 60
		if plan[i] == "field":
			b.set_growth(fmod(0.3 + 0.12 * i, 1.0))
	main._add_campfire(centre + Vector2(0, 24), 9999.0, "")
	main._village_dawn()
	main._village_dawn()
	_note("village_built", {"structures": main.buildings.size(), "settlers": main.settlers.size()})


func _recruit(n: int) -> void:
	var kinds := ["legionary", "legionary", "legionary", "legionary", "legionary", "legionary", "archer", "archer", "cavalry", "centurion"]
	for i in n:
		var spot: Vector2 = main.world.random_walkable_near(main.player.pos, 20.0, 80.0, main.rng)
		main._spawn_soldier(spot if spot != Vector2.INF else main.player.pos, -1.0, "follow", main.player.pos,
			kinds[main.soldiers.size() % kinds.size()])
	main._reassign_slots()


# ---------- Measuring ----------

func _keep_alive() -> void:
	main.player.health = 100.0
	main.player.hunger = 100.0
	main.player.warmth = 100.0
	main.player.sanity = 100.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		_keep_alive()
		await get_tree().process_frame


## Measures the scene as it stands, standing still.
func _measure(scene: String) -> void:
	await _wait(WARMUP)
	await _sample(scene, Vector2.ZERO, Vector2.ZERO)


## Moves at riding pace through new chunks and measures the hitches.
func _measure_travel(scene: String, from: Vector2) -> void:
	# Head whichever way stays on land longest.
	var w = main.world
	var best_dir := Vector2.RIGHT
	var best_land := -1
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		var land := 0
		for step in 40:
			if w.is_land(w.cell_of(from + d * step * 80.0)):
				land += 1
		if land > best_land:
			best_land = land
			best_dir = d
	_go(from)
	await _wait(WARMUP)
	await _sample(scene, from, best_dir * 220.0, TRAVEL)


func _sample(scene: String, from: Vector2, velocity: Vector2, seconds_to_run: float = SAMPLE) -> void:
	var ms: Array = []
	var draws: Array = []
	var prims: Array = []
	var objs: Array = []
	var crossing_ms: Array = []
	var render_cpu: Array = []
	var render_gpu: Array = []
	var vp := get_viewport().get_viewport_rid()
	var chunks := 0
	var start := Time.get_ticks_usec()
	var last := start
	var last_chunk: Vector2i = main.world._view_chunk
	while Time.get_ticks_usec() - start < int(seconds_to_run * 1e6):
		_keep_alive()
		if velocity != Vector2.ZERO:
			main.player.pos = from + velocity * ((Time.get_ticks_usec() - start) / 1e6)
			main.player.facing = velocity.normalized()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame := (now - last) / 1000.0
		last = now
		ms.append(frame)
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		if main.world._view_chunk != last_chunk:
			last_chunk = main.world._view_chunk
			chunks += 1
			crossing_ms.append(frame)
	var seconds := (Time.get_ticks_usec() - start) / 1e6
	var sorted := ms.duplicate()
	sorted.sort()
	var r := {
		"scene": scene,
		"seconds": snappedf(seconds, 0.01),
		"frames": ms.size(),
		"fps_avg": snappedf(ms.size() / seconds, 0.1),
		"frame_ms_avg": snappedf(_avg(ms), 0.01),
		"frame_ms_p50": snappedf(_pct(sorted, 0.5), 0.01),
		"frame_ms_p95": snappedf(_pct(sorted, 0.95), 0.01),
		"frame_ms_p99": snappedf(_pct(sorted, 0.99), 0.01),
		"frame_ms_max": snappedf(float(sorted[-1]) if not sorted.is_empty() else 0.0, 0.01),
		"frames_over_33ms": ms.filter(func(f): return f > 33.4).size(),
		"frames_over_50ms": ms.filter(func(f): return f > 50.0).size(),
		"draw_calls_avg": roundi(_avg(draws)),
		"draw_calls_max": int(draws.max()) if not draws.is_empty() else 0,
		"primitives_avg": roundi(_avg(prims)),
		"primitives_max": int(prims.max()) if not prims.is_empty() else 0,
		"objects_avg": roundi(_avg(objs)),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"render_cpu_ms_avg": snappedf(_avg(render_cpu), 0.01),
		"render_gpu_ms_avg": snappedf(_avg(render_gpu), 0.01),
		"shadow_preset": main.sun_shadow_preset,
		"shadow_mode": main.sun.directional_shadow_mode,
		"shadow_atlas": int(main.SUN_SHADOWS[main.sun_shadow_preset]["atlas"]),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"props_drawn": _props_drawn(),
		"grass_clumps": main.world._grass.multimesh.instance_count,
		"prop_view": main.world.props_in_view(main.camera),
		"soldiers": main.soldiers.size(),
		"buildings": main.buildings.size(),
		"settlers": main.settlers.size(),
		"night": main.is_night(),
	}
	if OS.has_feature("web"):
		var heap: Variant = JavaScriptBridge.eval(PerfOverlay.JS_MEMORY, true)
		r["js_heap_mb"] = snappedf(float(heap) / 1048576.0, 0.1) if typeof(heap) in [TYPE_INT, TYPE_FLOAT] and float(heap) > 0.0 else -1.0
	if velocity != Vector2.ZERO:
		r["chunks_crossed"] = chunks
		r["crossing_frame_ms"] = crossing_ms.map(func(f): return snappedf(f, 0.1))
	_note(scene, r)


func _note(label: String, data: Dictionary) -> void:
	data["label"] = label
	results.append(data)
	var line := JSON.stringify(data)
	print("PERF_RESULT " + line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(window.perfResults = window.perfResults || []).push(%s);" % line, true)


## Trees, rocks and bushes currently in the prop MultiMeshes (one per prop, not per part).
func _props_drawn() -> int:
	return main.world.drawn_prop_count()


static func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(a.size(), 1.0)


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)])
