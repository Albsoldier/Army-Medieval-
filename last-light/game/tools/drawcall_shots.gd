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
	# Clear the trees and rocks around the line-up, for the picture only.
	var w = main.world
	var c0: Vector2i = w.cell_of(line)
	for dz in range(-14, 15):
		for dx in range(-14, 15):
			if w.prop_type(c0 + Vector2i(dx, dz)) != "":
				w.prop_changes[c0 + Vector2i(dx, dz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
	w._props_dirty = true
	bench._go(line)
	main.player.pos = line
	var cast := []
	var spots_x := [-56, -40, -24, 24, 40, 56, 72]  # the player stands in the middle, at 0
	var kinds := ["legionary", "archer", "cavalry", "centurion"]
	for i in kinds.size():
		var at: Vector2 = line + Vector2(spots_x[i], 0)
		cast.append(main._spawn_soldier(at, -1.0, "hold", at, kinds[i]))
	for k in ["raider", "raider_chief"]:
		var r = main._spawn_raider(k, line + Vector2(spots_x[cast.size()], 0))
		r.home = r.pos
		cast.append(r)
	var at_s: Vector2 = line + Vector2(spots_x[cast.size()], 0)
	cast.append(main._spawn_settler("Wenna", 0, at_s, at_s, 30.0))
	main.player.facing = Vector2.DOWN
	# Raiders and settlers aren't run by the game here, so they stand still.
	for c in cast:
		if main.wolves.has(c):
			main.wolves.erase(c)
		if main.settlers.has(c):
			main.settlers.erase(c)
	await _hold(0.3, 20)
	main.process_mode = Node.PROCESS_MODE_DISABLED  # freeze: same moment, every run
	for i in cast.size():
		cast[i].pos = line + Vector2(spots_x[i], 0)  # exactly in line
	main.player.pos = line
	for c in cast:
		c.facing = Vector2.DOWN
		var model: Node3D = c._model
		model.rotation.y = 0.0
		c.position = main.world.to_3d(c.pos)
	main.player._model.rotation.y = 0.0
	main.player.position = main.world.to_3d(line)
	for pose in [["idle", 0.4], ["run", 0.25], ["attack", 0.3]]:
		for c in cast + [main.player]:
			_pose(c._body, str(pose[0]), float(pose[1]))
		await _frames(2)  # the skeletons update
		for c in cast:
			# Re-attach helmets, shields, spears and hats to the posed bones.
			if c.has_method("set_shown"):
				c._animate(0.0)
			elif c is Node3D and c.get_script() == load("res://scripts/settler.gd"):
				c._animate(0.0, "idle")
			else:
				c._animate(0.0)
		for side in [["front", 0.0], ["back", PI]]:
			main.zoom = 0.75
			main.cam_yaw = float(side[1])
			main._update_camera(1.0)
			await _frames(4)
			_save("cast-%s-%s" % [pose[0], side[0]])
	print("DRAWCALL_SHOTS_DONE ", _dir)
	quit(0)


## Puts a character in a fixed pose: an animation at a set time, held still.
## It's played as a one-shot, so the character's own update doesn't replace it.
func _pose(body, action: String, at: float) -> void:
	var anim: AnimationPlayer = body.anim
	if anim == null:
		return
	var tries := {"idle": ["idle"], "run": ["run", "walk"], "attack": ["slash", "attack", "punch", "work"]}
	for a in tries.get(action, []):
		if body.has_action(a):
			body.play_once(a, 1.0)
			body._oneshot = 1e9  # held
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
