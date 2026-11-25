## Renders the views used to compare the environment prototype (phase 4A,
## GRAPHICS_ENVIRONMENT_PROTOTYPE.md) before and after: a forest edge and a
## rocky area at three zooms and in first person, the forest in every season,
## and at night. Run it twice, with and without --nature=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/env_shots.gd [-- --nature=0]
## Images go to $SHOT_DIR (default: user://env_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("env_shots")
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
	var bench = PerfBench.new()
	bench.main = main
	main.rng.seed = 12345  # the same standing spots every run
	var spots: Dictionary = bench._find_spots()
	var places := {"forest": spots["forest"], "rocks": _rocky_spot()}
	main.clock = main.DAY_LENGTH * 0.3
	_season("spring")
	for place in places:
		bench._go(places[place])
		for zoom in [0.55, 1.6, 3.2]:
			for k in 2:
				main.zoom = zoom
				main.cam_yaw = 0.6 + k * PI
				await _hold(30)
				_save("%s-z%.1f-%d" % [place, zoom, k])
		main.set_first_person(true, false)
		main.cam_yaw = 0.6
		await _hold(30)
		_save("%s-first-person" % place)
		main.set_first_person(false, false)
	bench._go(places["forest"])
	main.zoom = 1.0
	main.cam_yaw = 0.6
	for season in ["spring", "summer", "autumn", "winter"]:
		_season(season)
		await _hold(30)
		_save("season-%s" % season)
	main.clock = main.DAY_LENGTH * 0.85
	for season in ["summer", "winter"]:
		_season(season)
		await _hold(40)
		_save("night-%s" % season)
	print("ENV_SHOTS_DONE ", _dir)
	quit(0)


## Somewhere a few tiles from a cluster of boulders, to see rocks close up.
func _rocky_spot() -> Vector2:
	var w = main.world
	var start: Vector2i = w.cell_of(main.player.pos)
	for r in range(4, 260, 3):
		for k in 24:
			var a := k * TAU / 24.0
			var c := start + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			if w.prop_type(c) != "rock":
				continue
			var near := 0
			for dz in range(-5, 6):
				for dx in range(-5, 6):
					if w.prop_type(c + Vector2i(dx, dz)) == "rock":
						near += 1
			if near < 4:
				continue
			for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3)]:
				var spot: Vector2 = w.cell_center(c + d)
				if w.is_walkable(spot):
					return spot
	return main.player.pos


func _season(season: String) -> void:
	main.world.set_season(season)
	main.world.update_view(main.player.pos, true)


func _hold(n: int) -> void:
	for i in n:
		await process_frame


func _frames(n: int) -> void:
	await _hold(n)


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
