## Renders the ranger with the hood up and the hood down, side by side, for
## comparing the two (phase 4C, GRAPHICS_PLAYER_HOOD.md): head close-ups all
## round (clipping), each animation from four sides, armour and every tool,
## the game's camera turning around the player by day and at night, and first
## person. QUICK=1 renders only the close-ups and a few poses.
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/hood_shots.gd
## Images go to $SHOT_DIR (default: user://hood_shots), named <shot>-up.png and <shot>-down.png.
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D
var mi: GeometryInstance3D
var quick := false


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("hood_shots")
	quick = OS.get_environment("QUICK") == "1"
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
	var at: Vector2 = spots["empty"]
	var w = main.world
	var c0: Vector2i = w.cell_of(at)
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			if w.prop_type(c0 + Vector2i(dx, dz)) != "":
				w.prop_changes[c0 + Vector2i(dx, dz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
	w._props_dirty = true
	bench._go(at)
	for s in main.soldiers.duplicate():
		main.soldiers.erase(s)
		s.queue_free()
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	var p = main.player
	mi = p._look_mesh
	if mi == null:
		print("not the ranger (?player=0?): nothing to compare")
		quit(1)
		return
	p.facing = Vector2.DOWN
	await _frames(20)
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	# Head close-ups all round, standing: where the hood could clip the head, face or hair.
	await _pose("idle", 0.6)
	for view in [["front", 0.0], ["three-quarter", 0.8], ["side", PI / 2], ["back-quarter", 2.3], ["back", PI]]:
		await _both("head-%s" % view[0], float(view[1]), 1.1, 1.55)
	# Each animation from four sides.
	var poses := [["idle", "idle", 0.6], ["walk", "walk", 0.3], ["run", "run", 0.25], ["punch", "punch", 0.25],
		["slash", "slash", 0.35], ["death", "death", 99.0]]
	if quick:
		poses = [["run", "run", 0.25], ["slash", "slash", 0.35]]
	for pose in poses:
		await _pose(str(pose[1]), float(pose[2]))
		for view in [["front", 0.0], ["side", PI / 2], ["back", PI], ["quarter", 2.4]]:
			await _both("pose-%s-%s" % [pose[0], view[0]], float(view[1]), 3.2, 1.0)
	if quick:
		print("HOOD_SHOTS_DONE ", _dir)
		quit(0)
		return
	# Armour (the approved shell) and each tool, idle and mid-swing.
	p.has_spear = true
	p.sword_tier = 1
	p.has_axe = true
	p.has_pickaxe = true
	p.armour = true
	p.armour_on = true
	p.armour_tier = 2
	p.torch_time = 999.0
	for tool in ["sword", "spear", "axe", "pickaxe"]:
		p.equip(tool)
		for pose in [["idle", 0.6], ["slash", 0.35]]:
			await _pose(str(pose[0]), float(pose[1]))
			await _both("gear-%s-%s" % [tool, pose[0]], 0.6, 3.0, 1.1)
	await _pose("idle", 0.6)
	for view in [["front", 0.35], ["back", PI - 0.35]]:
		await _both("armour-%s" % view[0], float(view[1]), 2.2, 1.2)
	# The game's own camera turning around the player, by day and at night, and first person.
	p.equip("sword")
	p._body._oneshot = 0.0
	p._body.anim.play()
	cam.current = false
	main.camera.make_current()
	p.torch_time = 0.0
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		if t[0] == "night":
			p.torch_time = 999.0
		for yaw in [0.5, 2.1, 3.7, 5.3]:
			main.zoom = 0.55
			main.cam_yaw = yaw
			await _both("game-%s-yaw%.1f" % [t[0], yaw], -1.0, 0.0, 0.0, 30)
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.set_first_person(true, false)
	main.cam_yaw = 0.5
	main.fp_pitch = -0.35
	await _both("first-person", -1.0, 0.0, 0.0, 30)
	main.fp_pitch = -1.2  # looking down at your own body
	await _both("first-person-down", -1.0, 0.0, 0.0, 30)
	main.set_first_person(false, false)
	print("HOOD_SHOTS_DONE ", _dir)
	quit(0)


## Saves the same view with the hood up, then down. yaw < 0: keep the current camera.
func _both(name: String, yaw: float, dist: float, height: float, settle := 3) -> void:
	for hood in [["up", {}], ["down", {"hood": "down"}]]:
		main.player.Appearance.apply(mi, main.player.Appearance.from_options(hood[1]))
		if yaw >= 0.0:
			_look(yaw, dist, height)
		await _frames(settle)
		root.get_viewport().get_texture().get_image().save_png(_dir.path_join("%s-%s.png" % [name, hood[0]]))
	print("saved ", name)


## Holds the player in `action` at `t` seconds (the end, for a large t).
func _pose(action: String, t: float) -> void:
	var p = main.player
	var body = p._body
	body._oneshot = 0.0
	body.play_once(action)
	var anim: AnimationPlayer = body.anim
	anim.play(body._actions[action], 0.0)
	anim.seek(minf(t, anim.current_animation_length - 0.01), true)
	anim.pause()
	body._oneshot = 1e9
	p.facing = Vector2.DOWN
	await _frames(3)


func _look(yaw: float, dist: float, height: float) -> void:
	var centre: Vector3 = main.player.global_position + Vector3(0, height, 0)
	var dir := Vector3(sin(yaw), 0.15, cos(yaw)).normalized()
	cam.global_position = centre + dir * dist
	cam.look_at(centre)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
