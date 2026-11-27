## Renders the ship for comparing the modelled ship (GRAPHICS_SHIPS.md) with
## the old galley and wreck: the galley afloat from the front, side, back and
## above, close up, with the player aboard, at the game's camera by day and
## at night; a shipwreck. Run it twice, with and without --ships=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/ship_shots.gd [-- --ships=0]
## Images go to $SHOT_DIR (default: user://ship_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("ship_shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1200.0).timeout.connect(func(): quit(1))
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
	var bench = PerfBench.new()
	bench.main = main
	var w = main.world
	var p = main.player
	# Open sea near the start: the nearest deep water with deep water all round.
	var sea := Vector2.INF
	for r in range(200, 6000, 80):
		for i in 48:
			var at: Vector2 = w.cell_center(w.spawn_cell) + Vector2.from_angle(i * TAU / 48.0) * r
			var clear := true
			for k in 8:
				clear = clear and w.is_sailable(at + Vector2.from_angle(k * TAU / 8.0) * 110.0, true)
			if clear and w.is_sailable(at, true):
				sea = at
				break
		if sea != Vector2.INF:
			break
	print("sea at ", sea, ", ships: ", "new" if main.Boat.use_new_ship else "old")
	bench._go(sea + Vector2(0, 160))
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	await _frames(10)
	var boat = main._spawn_boat("galley", sea, Vector2.LEFT)
	await _frames(20)
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	main.hud.visible = false
	var centre: Vector3 = boat.global_position + Vector3(0, 1.2, 0)
	for view in [["side", Vector3(0, 0.25, 1), 11.0], ["front", Vector3(-1, 0.3, 0.35), 10.0],
			["back", Vector3(1, 0.3, -0.3), 10.0], ["above", Vector3(0.3, 1.0, 0.5), 12.0],
			["close-bow", Vector3(-0.6, 0.15, 1), 4.5], ["close-stern", Vector3(0.7, 0.35, 0.8), 4.5]]:
		var at: Vector3 = centre
		if str(view[0]) == "close-bow":
			at = boat.global_position + Vector3(-2.6, 0.6, 0)
		elif str(view[0]) == "close-stern":
			at = boat.global_position + Vector3(2.4, 1.0, 0)
		cam.global_position = at + (view[1] as Vector3).normalized() * float(view[2])
		cam.look_at(at)
		await _frames(4)
		_save("ship-" + str(view[0]))
	# Aboard, from the game's camera, by day and at night.
	main._board(boat)
	await _frames(10)
	cam.current = false
	main.camera.make_current()
	main.hud.visible = true
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		p.torch_time = 999.0 if t[0] == "night" else 0.0
		for z in [0.55, 1.2]:
			main.zoom = z
			main.cam_yaw = 0.6
			await _frames(30)
			_save("aboard-%s-z%.1f" % [t[0], z])
	main._leave_boat()
	# A shipwreck.
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	p.torch_time = 0.0
	var wreck := {}
	for data in w.pois:
		if data["type"] == "shipwreck":
			wreck = data
			break
	var at_wreck: Vector2 = w.cell_center(wreck["cell"])
	bench._go(at_wreck + Vector2(0, 90))
	await _frames(30)
	var node = main.poi_nodes.get(wreck["id"])
	cam.make_current()
	main.hud.visible = false
	var wc: Vector3 = node.global_position + Vector3(0, 0.8, 0)
	for view in [["wreck-side", Vector3(0.2, 0.35, 1), 9.0], ["wreck-front", Vector3(1, 0.4, 0.4), 9.0]]:
		cam.global_position = wc + (view[1] as Vector3).normalized() * float(view[2])
		cam.look_at(wc)
		await _frames(4)
		_save(str(view[0]))
	cam.current = false
	main.camera.make_current()
	main.hud.visible = true
	main.zoom = 0.8
	await _frames(30)
	_save("wreck-game")
	print("SHIP_SHOTS_DONE ", _dir)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
