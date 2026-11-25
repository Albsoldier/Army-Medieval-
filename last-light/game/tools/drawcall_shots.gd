## Renders fixed scenes for comparing how buildings and characters look before
## and after a rendering change (GRAPHICS_DRAWCALL_OPTIMIZATION.md):
##   - the benchmark village, buildings only, by day and at night, from four sides;
##   - a line-up of every kind of character, frozen at set animation poses,
##     from the front and the back.
## Needs a real renderer, e.g.:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/drawcall_shots.gd
## Images go to $SHOT_DIR (default: user://drawcall_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("drawcall_shots")
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
	main.rng.seed = 20261124
	var spots: Dictionary = bench._find_spots()
	var village: Vector2 = spots["village"]
	bench._go(village)
	bench._build_village(village)
	for st in main.settlers:
		st.visible = false  # buildings only: settlers wander
	main.player.visible = false
	# The village from four sides, by day and at night.
	for t in [["day", 0.3], ["night", 0.85]]:
		for k in 4:
			main.zoom = 1.2
			main.cam_yaw = k * TAU / 4.0 + 0.4
			await _hold(float(t[1]), 25)
			_save("village-%s-%d" % [t[0], k])
	# A line-up of characters on open ground, frozen at the same poses.
	main.player.visible = true
	var line: Vector2 = spots["empty"]
	bench._go(line)
	var cast := []
	var kinds := ["legionary", "archer", "cavalry", "centurion"]
	for i in kinds.size():
		var s = main._spawn_soldier(line + Vector2(-60 + i * 24, 0), -1.0, "hold", line + Vector2(-60 + i * 24, 0), kinds[i])
		cast.append(s)
	for k in ["raider", "raider_chief"]:
		var r = main._spawn_raider(k, line + Vector2(40 + cast.size() * 2, 0) + Vector2((cast.size() - 4) * 24, 0))
		r.home = r.pos
		cast.append(r)
	var st = main._spawn_settler("Wenna", 0, line + Vector2(100, 0), line + Vector2(100, 0), 30.0)
	cast.append(st)
	main.player.pos = line + Vector2(-90, 0)
	main.player.facing = Vector2.DOWN
	await _hold(0.3, 20)
	main.process_mode = Node.PROCESS_MODE_DISABLED  # freeze: same moment, every run
	for c in cast:
		c.facing = Vector2.DOWN
		var model: Node3D = c._model
		model.rotation.y = 0.0
		c.position = main.world.to_3d(c.pos)
	main.player._model.rotation.y = 0.0
	for pose in [["idle", 0.4], ["run", 0.25], ["attack", 0.3]]:
		for c in cast + [main.player]:
			_pose(c._body, str(pose[0]), float(pose[1]))
		for side in [["front", PI], ["back", 0.0]]:
			main.zoom = 0.75
			main.cam_yaw = float(side[1])
			main._update_camera(1.0)
			await _frames(4)
			_save("cast-%s-%s" % [pose[0], side[0]])
	print("DRAWCALL_SHOTS_DONE ", _dir)
	quit(0)


## Puts a character in a fixed pose: an animation at a set time, held still.
func _pose(body, action: String, at: float) -> void:
	var anim: AnimationPlayer = body.anim
	if anim == null:
		return
	var names := {"idle": ["Man_Idle", "Idle"], "run": ["Man_Run", "Run", "Gallop"], "attack": ["Man_SwordSlash", "Sword_Slash", "Attack"]}
	for ending in names.get(action, []):
		for n in anim.get_animation_list():
			if str(n).ends_with(ending):
				anim.play(n)
				anim.seek(at, true)
				anim.pause()
				return


func _hold(day_fraction: float, n: int) -> void:
	for i in n:
		main.clock = main.DAY_LENGTH * day_fraction
		main._update_lighting()
		main.player.health = 100.0
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(label: String) -> void:
	root.get_texture().get_image().save_png(_dir.path_join(label + ".png"))
