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
	# Phase 4E.1 (GRAPHICS_PHASE_4E1_SWORDS.md), only with ?swordbench=1 (or
	# --swordbench): you hold the iron sword from here on, and ten raiders with
	# their axes stand round you (out of the fight: drawn, not hunting).
	if "--swordbench" in OS.get_cmdline_user_args() or PerfOverlay.url_flag("swordbench"):
		main.player.sword_tier = 0
		main.player.equip("sword")
		await _measure("player_sword")
		var bench_raiders := []
		for k in 10:
			var spot: Vector2 = main.world.random_walkable_near(main.player.pos, 30.0, 90.0, main.rng)
			var r = main._spawn_raider("raider_chief" if k == 0 else "raider", spot if spot != Vector2.INF else main.player.pos)
			main.wolves.erase(r)
			r._animate(0.016)
			bench_raiders.append(r)
		await _measure("raiders_10")
		for r in bench_raiders:
			r.queue_free()
	# Phase 4D (GRAPHICS_PHASE_4D_LEGIONARY.md), only with ?legionbench=1 (or
	# --legionbench): 1, 10 and 30 legionaries following you on open ground.
	# Phase 4D.2 (GRAPHICS_PHASE_4D2_CENTURION.md), only with ?centurionbench=1
	# (or --centurionbench): the same with centurions (more than the game allows,
	# one per barracks, to measure a crowd of them).
	for bench_kind in [["legionbench", "legionary", "legion"], ["centurionbench", "centurion", "centurion"]]:
		if not ("--" + bench_kind[0] in OS.get_cmdline_user_args() or PerfOverlay.url_flag(bench_kind[0])):
			continue
		for n in [1, 10, 30]:
			_recruit(n - main.soldiers.size(), bench_kind[1])
			await _measure("%s_%d" % [bench_kind[2], n])
		for s in main.soldiers.duplicate():
			main.soldiers.erase(s)
			s.queue_free()
	# Ships (GRAPHICS_SHIPS.md), only with ?shipbench=1 (or --shipbench): open
	# sea, then you aboard a galley, then four more galleys round you, then a
	# shipwreck on its shore.
	if "--shipbench" in OS.get_cmdline_user_args() or PerfOverlay.url_flag("shipbench"):
		await _ship_scenes()
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
	# Phase 5A (GRAPHICS_PHASE_5A_TERRAIN.md), only with ?zoombench=1 (or
	# --zoombench): the village and its army by day from the farthest zoom, then
	# the open field there, where the most terrain is on screen.
	if "--zoombench" in OS.get_cmdline_user_args() or PerfOverlay.url_flag("zoombench"):
		main.clock = main.DAY_LENGTH * 0.3
		main.player.torch_time = 0.0
		main._update_lighting()
		main.zoom = 3.2
		await _measure("village_max_zoom")
		_go(spots["empty"])
		await _measure("field_max_zoom")
		main.zoom = 1.0
		_go(spots["village"])
		main.clock = main.DAY_LENGTH * 0.85
		main.player.torch_time = 9999.0
		main._update_lighting()
	# 7. Area transitions: no army, crossing chunk after chunk at riding pace.
	for s in main.soldiers.duplicate():
		main.soldiers.erase(s)
		s.queue_free()
	main.player.torch_time = 0.0
	_day()
	await _measure_travel("area_transitions", spots["village"])
	# Phase 5B.1 (GRAPHICS_PHASE_5B1_WATER_SURFACE.md), only with ?waterbench=1
	# (or --waterbench): the water, after everything else so the other scenes
	# are as before.
	if "--waterbench" in OS.get_cmdline_user_args() or PerfOverlay.url_flag("waterbench"):
		await _water_scenes()

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


## The water scenes (?waterbench=1): a narrow channel, a wide one, a lake, a
## beach, a village by the water, boats off the beach, the farthest zoom and
## night, all at the default zoom and by day unless named.
func _water_scenes() -> void:
	var w = main.world
	var ws := _find_water_spots()
	_note("water_spots", ws)
	main.zoom = 1.0
	_day()
	for k in ["small_channel", "large_channel", "lake", "shore"]:
		if ws[k] != Vector2.INF:
			_go(ws[k])
			await _measure("water_" + k)
	if ws["village_shore"] != Vector2.INF:
		_go(ws["village_shore"])
		_build_village(ws["village_shore"])
		await _measure("water_village")
	if ws["shore"] == Vector2.INF:
		return
	var sh: Vector2 = ws["shore"]
	var fleet := [main._spawn_boat("galley", sh + Vector2(40, 22 * w.TILE), Vector2.LEFT),
		main._spawn_boat("raft", sh + Vector2(-60, 7 * w.TILE), Vector2.RIGHT),
		main._spawn_boat("raft", sh + Vector2(90, 9 * w.TILE), Vector2.LEFT)]
	_go(sh + Vector2(0, 2 * w.TILE))
	await _measure("water_boats")
	main.zoom = 3.2
	await _measure("water_max_zoom")
	main.zoom = 1.0
	main.clock = main.DAY_LENGTH * 0.85
	main.player.torch_time = 9999.0
	main._update_lighting()
	await _measure("water_night")
	main.player.torch_time = 0.0
	_day()
	for b in fleet:
		main.boats.erase(b)
		b.queue_free()


## Phase 5B.1 (GRAPHICS_PHASE_5B1_WATER_SURFACE.md): water to look at, nearest
## the start first. The island has no rivers as such (water is only shallow
## water and deep sea), so a narrow channel of water between land stands in
## for a small river and a wider one for a large river. Returns positions:
## "small_channel", "large_channel", "lake" (water not joined to the sea),
## "shore" (a beach on open water) and "village_shore" (land by the water
## with room for the benchmark's village). A missing one is Vector2.INF.
func _find_water_spots() -> Dictionary:
	var w = main.world
	var start: Vector2i = w.spawn_cell
	var found := {"small_channel": Vector2.INF, "large_channel": Vector2.INF, "lake": Vector2.INF,
		"shore": Vector2.INF, "village_shore": Vector2.INF}
	var seen_lake := {}
	for r in range(4, 500, 3):
		var steps := maxi(16, r)
		for i in steps:
			var c: Vector2i = start + Vector2i(roundi(cos(i * TAU / steps) * r), roundi(sin(i * TAU / steps) * r))
			var t: int = w.terrain_at(c)
			if t != w.WATER and t != w.DEEP:
				if found["village_shore"] == Vector2.INF and (t == w.GRASS or t == w.SAND):
					var share := _land_around(c, 10)
					if share >= 0.6 and share <= 0.8:
						found["village_shore"] = w.cell_center(c)
				if found["shore"] == Vector2.INF and t == w.SAND and _water_width(c + Vector2i(0, 6), 40) >= 40 \
						and _water_width(c + Vector2i(0, 10), 40) >= 40:
					found["shore"] = w.cell_center(c)
				continue
			var width := _water_width(c, 40)
			if found["small_channel"] == Vector2.INF and width >= 3 and width <= 7 and _channel_runs(c, width):
				found["small_channel"] = w.cell_center(c)
			if found["large_channel"] == Vector2.INF and width >= 10 and width <= 24 and _channel_runs(c, width):
				found["large_channel"] = w.cell_center(c)
			if found["lake"] == Vector2.INF and not seen_lake.has(c):
				var size := _water_body(c, 5000, seen_lake)
				if size >= 150 and size < 5000:
					found["lake"] = w.cell_center(c)
		var done := true
		for k in found:
			done = done and found[k] != Vector2.INF
		if done:
			break
	return found


## The narrower of the runs of water through `cell` across and along (capped).
func _water_width(cell: Vector2i, cap: int) -> int:
	var best := cap
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		var n := 1
		for s in [1, -1]:
			var k := 1
			while k < cap and not main.world.is_land(cell + d * s * k):
				k += 1
				n += 1
		best = mini(best, n)
	return best


## Whether the water through `cell` goes on along some direction for at least
## twice its width each way, like a river, rather than being a round pond or a
## narrow gap in one place.
func _channel_runs(cell: Vector2i, width: int) -> bool:
	var w = main.world
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var ok := true
		for s in [1, -1]:
			for k in range(1, mini(width * 2, 30) + 1):
				if w.is_land(cell + d * s * k):
					ok = false
					break
		if ok:
			return true
	return false


## The share of land within `r` cells of `cell`.
func _land_around(cell: Vector2i, r: int) -> float:
	var land := 0
	var n := 0
	for dz in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			n += 1
			if main.world.is_land(cell + Vector2i(dx, dz)):
				land += 1
	return float(land) / float(n)


## The size of the body of water at `cell`, up to `cap` cells (cap = joined to the sea).
func _water_body(cell: Vector2i, cap: int, seen: Dictionary) -> int:
	var w = main.world
	var todo := [cell]
	var body := {cell: true}
	while not todo.is_empty() and body.size() < cap:
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if body.has(n) or w.is_land(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= w.SIZE or n.y >= w.SIZE:
				return cap
			body[n] = true
			todo.append(n)
	for c in body:
		seen[c] = true
	return body.size()


func _ship_scenes() -> void:
	var w = main.world
	var sea := Vector2.INF
	for r in range(200, 6000, 80):
		for i in 48:
			var at: Vector2 = w.cell_center(w.spawn_cell) + Vector2.from_angle(i * TAU / 48.0) * r
			var clear: bool = w.is_sailable(at, true)
			for k in 8:
				clear = clear and w.is_sailable(at + Vector2.from_angle(k * TAU / 8.0) * 110.0, true)
			if clear:
				sea = at
				break
		if sea != Vector2.INF:
			break
	if sea == Vector2.INF:
		return
	_go(sea)
	await _measure("sea")
	var fleet := [main._spawn_boat("galley", sea, Vector2.LEFT)]
	main._board(fleet[0])
	await _measure("ship_1")
	for k in 4:
		var at: Vector2 = sea + Vector2.from_angle(k * TAU / 4.0 + 0.4) * 95.0
		if w.is_sailable(at, true):
			fleet.append(main._spawn_boat("galley", at, Vector2.from_angle(k * 1.3)))
	await _measure("ships_%d" % fleet.size())
	main._leave_boat()
	for b in fleet:
		main.boats.erase(b)
		b.queue_free()
	for data in w.pois:
		if data["type"] == "shipwreck":
			_go(w.cell_center(data["cell"]) + Vector2(0, 90))
			await _measure("shipwreck")
			break


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


## Recruits n soldiers, a mixed army (or only `only`, a kind).
func _recruit(n: int, only := "") -> void:
	var kinds := ["legionary", "legionary", "legionary", "legionary", "legionary", "legionary", "archer", "archer", "cavalry", "centurion"]
	for i in n:
		var spot: Vector2 = main.world.random_walkable_near(main.player.pos, 20.0, 80.0, main.rng)
		main._spawn_soldier(spot if spot != Vector2.INF else main.player.pos, -1.0, "follow", main.player.pos,
			only if only != "" else kinds[main.soldiers.size() % kinds.size()])
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
	var process_ms: Array = []
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
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
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
		# 1% low: the frame rate of the slowest 1% of frames (their average frame time).
		"fps_1pct_low": snappedf(1000.0 / maxf(_avg(sorted.slice(sorted.size() - maxi(sorted.size() / 100, 1))), 0.001), 0.1),
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
		"cpu_process_ms_avg": snappedf(_avg(process_ms), 0.01),  # game logic per frame (CPU)
		"shadow_preset": main.sun_shadow_preset,
		"shadow_mode": main.sun.directional_shadow_mode,
		"shadow_atlas": int(main.SUN_SHADOWS[main.sun_shadow_preset]["atlas"]),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scene_meshes": _scene_meshes()[0],
		"scene_surfaces": _scene_meshes()[1],
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


## Visible mesh nodes (MeshInstance3D and MultiMeshInstance3D) in the game,
## and their surfaces: each surface is a draw call per pass it's drawn in.
func _scene_meshes() -> Array:
	var meshes := 0
	var surfaces := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			meshes += 1
			surfaces += mesh.get_surface_count()
	return [meshes, surfaces]


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
