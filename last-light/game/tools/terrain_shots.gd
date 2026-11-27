## Renders the terrain for comparing the phase 5A terrain (GRAPHICS_PHASE_5A_TERRAIN.md)
## with the original: an open field, a forest, rocky ground, a beach and a
## hillside, each close to the ground and from the game's camera at the
## closest, normal and farthest zoom; the field at night and in every season.
## Run it twice, with and without --terrain=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/terrain_shots.gd [-- --terrain=0]
## Images go to $SHOT_DIR (default: user://terrain_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("terrain_shots")
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
	main.world.set_season("spring")
	main.rng.seed = 20261124
	var bench = PerfBench.new()
	bench.main = main
	var w = main.world
	var spots: Dictionary = bench._find_spots()
	var places := {"field": spots["empty"], "forest": spots["forest"]}
	places["rocky"] = _find(w, w.ROCK, 0.5)
	places["beach"] = _find(w, w.SAND, 0.4)
	places["hill"] = _find_hill(w)
	print("terrain: ", "new" if w.terrain_detail else "old", " places ", places)
	for so in main.soldiers.duplicate():
		main.soldiers.erase(so)
		so.queue_free()
	for wolf in main.wolves.duplicate():
		main.wolves.erase(wolf)
		wolf.queue_free()
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	for place: String in places:
		var at: Vector2 = places[place]
		bench._go(at)
		await _frames(30)
		# Close to the ground, looking along it.
		main.hud.visible = false
		main.player.visible = false
		var ground: Vector3 = w.to_3d(at)
		cam.global_position = ground + Vector3(0, 1.6, 4.0)
		cam.look_at(ground + Vector3(0, 0.2, -3.0))
		cam.make_current()
		await _frames(4)
		_save("%s-close" % place)
		cam.current = false
		main.player.visible = true
		main.camera.make_current()
		main.hud.visible = false
		for z in [0.55, 1.0, 3.2]:
			main.zoom = z
			main.cam_yaw = 0.6
			await _frames(25)
			_save("%s-z%.2f" % [place, z])
	# The field at night and in every season.
	bench._go(places["field"])
	main.zoom = 1.0
	await _frames(20)
	main.clock = main.DAY_LENGTH * 0.85
	main._update_lighting()
	main.player.torch_time = 999.0
	await _frames(25)
	_save("field-night")
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.player.torch_time = 0.0
	for s in ["summer", "autumn", "winter"]:
		w.set_season(s)
		await _frames(25)
		_save("field-%s" % s)
	print("TERRAIN_SHOTS_DONE ", _dir)
	quit(0)


## The open ground of a type nearest the start with at least `share` of it around.
func _find(w, kind: int, share: float) -> Vector2:
	var start: Vector2i = w.spawn_cell
	for r in range(8, 300, 4):
		for i in 32:
			var c: Vector2i = start + Vector2i(roundi(cos(i * TAU / 32.0) * r), roundi(sin(i * TAU / 32.0) * r))
			if w.terrain_at(c) != kind:
				continue
			var n := 0
			for dz in range(-4, 5, 2):
				for dx in range(-4, 5, 2):
					if w.terrain_at(c + Vector2i(dx, dz)) == kind:
						n += 1
			if n >= 25 * share:
				return w.cell_center(c)
	return w.cell_center(start)


## A grassy slope: the grass tile near the start with the biggest height change around it.
func _find_hill(w) -> Vector2:
	var start: Vector2i = w.spawn_cell
	var best := start
	var best_drop := -1.0
	for r in range(6, 200, 6):
		for i in 24:
			var c: Vector2i = start + Vector2i(roundi(cos(i * TAU / 24.0) * r), roundi(sin(i * TAU / 24.0) * r))
			if w.terrain_at(c) != w.GRASS:
				continue
			var h: float = w.height_at(w.cell_center(c))
			var drop: float = absf(w.height_at(w.cell_center(c + Vector2i(4, 0))) - h) + absf(w.height_at(w.cell_center(c + Vector2i(0, 4))) - h)
			if drop > best_drop:
				best_drop = drop
				best = c
	return w.cell_center(best)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
