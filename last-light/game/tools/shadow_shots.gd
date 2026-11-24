## Renders the same scenes under each sun-shadow preset (main.SUN_SHADOWS),
## for comparing shadow quality. Needs a real renderer, e.g. under xvfb:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/shadow_shots.gd
## Images go to $SHOT_DIR (default: user://shadow_shots).
##
## Also renders a "shimmer" sequence per preset: a still camera while the sun
## creeps across the sky, so unstable (crawling, flickering) shadow edges show
## up as pixels that flip back and forth between frames.
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")
const PRESETS := ["A", "B", "C", "D"]
const SCENES := [
	# name, where, zoom, camera turn, time of day (fraction), first person
	["near", "village", 0.55, 0.7, 0.5, false],
	["base", "village", 1.5, 0.7, 0.5, false],
	["far", "village", 3.2, 0.7, 0.5, false],
	["forest", "forest", 1.2, 0.3, 0.45, false],
	["first_person", "village", 1.0, 2.3, 0.5, true],
]
const SHIMMER_FRAMES := 10
const SHIMMER_STEP := 1.5  # game seconds the sun moves per shimmer frame

var _dir := ""
var main: Node


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("shadow_shots")
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
	main.bench_mode = true  # never save
	main.world.set_season("spring")
	var bench = PerfBench.new()  # borrow its scene setup; not added to the tree, so it doesn't run
	bench.main = main
	var spots: Dictionary = bench._find_spots()
	bench._go(spots["village"])
	bench._build_village(spots["village"])
	bench._recruit(10)
	var day: float = main.DAY_LENGTH
	for scene in SCENES:
		var at: Vector2 = spots[scene[1]] + (Vector2(0, 40) if scene[1] == "village" else Vector2.ZERO)
		bench._go(at)
		main.zoom = scene[2]
		main.cam_yaw = scene[3]
		main.set_first_person(scene[5], false)
		main.fp_pitch = -0.12
		for st in main.settlers:
			st.visible = not scene[5]  # nobody wanders in front of the first-person camera
		main.apply_sun_shadows("A")
		await _hold(day * float(scene[4]), 40)  # let the camera and soldiers settle
		# Freeze the scene so every preset renders exactly the same moment.
		main.process_mode = Node.PROCESS_MODE_DISABLED
		var order: Array = PRESETS.duplicate()
		if OS.get_environment("SHOT_REVERSE") != "":
			order.reverse()  # to check the order of switching doesn't matter
		for preset in order:
			main.apply_sun_shadows(preset)
			await _hold(day * float(scene[4]), 6)
			_save("%s-%s" % [scene[0], preset])
		main.process_mode = Node.PROCESS_MODE_INHERIT
	main.set_first_person(false, false)
	for st in main.settlers:
		st.visible = true
	# Shimmer: a still camera over the village while the sun moves slowly.
	bench._go(spots["village"] + Vector2(0, 40))
	main.zoom = 1.5
	main.cam_yaw = 0.7
	await _hold(day * 0.5, 40)
	main.process_mode = Node.PROCESS_MODE_DISABLED  # only the sun moves
	# "off" is the noise floor: grass sway and idle animations, with no shadows at all.
	for preset in PRESETS + ["off"]:
		main.sun.shadow_enabled = preset != "off"
		if preset != "off":
			main.apply_sun_shadows(preset)
		await _hold(day * 0.5, 6)
		for k in SHIMMER_FRAMES:
			await _hold(day * 0.5 + k * SHIMMER_STEP, 3)
			_save("shimmer-%s-%02d" % [preset, k])
	main.sun.shadow_enabled = true
	print("SHADOW_SHOTS_DONE ", _dir)
	quit(0)


## Keeps the clock (and so the sun) fixed for `n` frames, so every preset sees the same light.
func _hold(clock: float, n: int) -> void:
	for i in n:
		main.clock = clock
		main._update_lighting()
		main.player.health = 100.0
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(label: String) -> void:
	var path := _dir.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	print("shot ", label)
