## Renders the water for comparing the phase 5B.1 water surface
## (GRAPHICS_PHASE_5B1_WATER_SURFACE.md) with the original: a narrow channel
## (the island's stand-in for a small river), a wide one (a large river), a
## lake, a beach on open water, the water by the village, and boats moored
## at the shore; each from low over the water and from the game's camera at
## the closest, normal and farthest zoom; the shore at night, in every
## season and from a low sun. With WINTER=1, every place in winter instead
## (the ice), and nothing else. Run it twice, with and without --water=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/water_shots.gd [-- --water=0]
## Images go to $SHOT_DIR (default: user://water_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("water_shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1500.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	if main.hud.is_modal():
		main.hud._choose(0)
	main.hud.toggle_help()
	main.bench_mode = true
	# WINTER=1: every place in winter instead (the ice), and nothing else.
	var winter_only := OS.get_environment("WINTER") == "1"
	main.world.set_season("winter" if winter_only else "spring")
	main.rng.seed = 20261124
	var bench = PerfBench.new()
	bench.main = main
	var w = main.world
	var spots: Dictionary = bench._find_water_spots()
	var places := {}
	for k in ["small_channel", "large_channel", "lake", "shore", "village_shore"]:
		if spots[k] != Vector2.INF:
			places[k] = spots[k]
	print("water: ", "new" if w.water_detail else "old", " places ", places)
	for so in main.soldiers.duplicate():
		main.soldiers.erase(so)
		so.queue_free()
	for wolf in main.wolves.duplicate():
		wolf.queue_free()
	main.wolves.clear()
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	# Boats moored off the beach.
	var boats := []
	if places.has("shore"):
		var sh: Vector2 = places["shore"]
		boats.append(main._spawn_boat("galley", sh + Vector2(40, 22 * w.TILE), Vector2.LEFT))
		boats.append(main._spawn_boat("raft", sh + Vector2(-60, 7 * w.TILE), Vector2.RIGHT))
		places["boats"] = sh + Vector2(0, 2 * w.TILE)
	for place: String in places:
		var at: Vector2 = places[place]
		var look: Vector2 = _water_near(w, at)
		bench._go(at)
		if place == "village_shore":
			bench._build_village(at)
		await _frames(30)
		# From low over the water, looking across it.
		main.hud.visible = false
		main.player.visible = false
		var target: Vector3 = w.to_3d(look)
		target.y = 0.0
		var from: Vector3 = target + Vector3(0, 0, 9.0)
		from.y = maxf(w.height_at(Vector2(from.x, from.z) * w.TILE), 0.0) + 1.8
		cam.global_position = from
		cam.look_at(target + Vector3(0, 0.0, -8.0))
		cam.make_current()
		await _frames(4)
		_save("%s-close" % place)
		cam.current = false
		main.player.visible = true
		main.camera.make_current()
		for z in [0.55, 1.0, 3.2]:
			main.zoom = z
			main.cam_yaw = 0.6
			await _frames(25)
			_save("%s-z%.2f" % [place, z])
	if winter_only:
		print("WATER_SHOTS_DONE ", _dir)
		quit(0)
		return
	# The shore at night, from a low sun, and in every season.
	var sh_at: Vector2 = places.get("shore", places.values()[0])
	bench._go(sh_at)
	main.zoom = 1.0
	await _frames(20)
	main.clock = main.DAY_LENGTH * 0.85
	main._update_lighting()
	main.player.torch_time = 999.0
	await _frames(25)
	_save("shore-night")
	main.player.torch_time = 0.0
	main.clock = main.DAY_LENGTH * 0.7
	main._update_lighting()
	await _frames(25)
	_save("shore-evening")
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	for s in ["summer", "autumn", "winter"]:
		w.set_season(s)
		main._update_weather()
		await _frames(25)
		_save("shore-%s" % s)
	print("WATER_SHOTS_DONE ", _dir)
	quit(0)


## The open water nearest `at` (or `at` itself).
func _water_near(w, at: Vector2) -> Vector2:
	var c: Vector2i = w.cell_of(at)
	for r in range(0, 30):
		for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			if not w.is_land(c + d * r):
				return w.cell_center(c + d * r)
	return at


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
