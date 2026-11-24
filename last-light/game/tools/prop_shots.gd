## Renders fixed views around the forest and the start (8 camera turns at
## three zooms, plus first person), to compare prop rendering before and after
## a change (see GRAPHICS_PROP_CHUNKS.md). Needs a real renderer, e.g.:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/prop_shots.gd
## Images go to $SHOT_DIR (default: user://prop_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("prop_shots")
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
	var bench = PerfBench.new()
	bench.main = main
	var spots: Dictionary = bench._find_spots()
	for place in ["forest", "village"]:
		bench._go(spots[place])
		for zoom in [0.55, 1.6, 3.2]:
			for k in 8:
				main.zoom = zoom
				main.cam_yaw = k * TAU / 8.0
				await _hold(30)
				_save("%s-z%.1f-%d" % [place, zoom, k])
		main.set_first_person(true, false)
		for k in 4:
			main.cam_yaw = k * TAU / 4.0
			main.fp_pitch = -0.05
			await _hold(20)
			_save("%s-fp-%d" % [place, k])
		main.set_first_person(false, false)
	print("PROP_SHOTS_DONE ", _dir)
	quit(0)


func _hold(n: int) -> void:
	for i in n:
		main.clock = main.DAY_LENGTH * 0.3
		main._update_lighting()
		main.player.health = 100.0
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(label: String) -> void:
	root.get_texture().get_image().save_png(_dir.path_join(label + ".png"))
