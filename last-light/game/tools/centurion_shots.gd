## Renders the centurion for comparing the phase 4D.2 body with the old one
## (GRAPHICS_PHASE_4D2_CENTURION.md): one centurion in idle, run, attack and
## death from the front, side, back and three-quarter back; a close-up; the
## hurt flash; a real death; the centurion beside a standard legionary, close
## and from the game's camera; then a centurion leading 29 legionaries in a
## shield wall by day and at night. Run it twice, with and without --centurion=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/centurion_shots.gd [-- --centurion=0]
## Images go to $SHOT_DIR (default: user://centurion_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("centurion_shots")
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
	for dz in range(-14, 15):
		for dx in range(-14, 15):
			if w.prop_type(c0 + Vector2i(dx, dz)) != "":
				w.prop_changes[c0 + Vector2i(dx, dz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
	w._props_dirty = true
	bench._go(at)
	for s in main.soldiers.duplicate():
		main.soldiers.erase(s)
		s.queue_free()
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.player.visible = false
	# One legionary, holding a spot 3 m from where the player was.
	var p = main.player
	var spot: Vector2 = p.pos + Vector2(0, -48)
	var one = main._spawn_soldier(spot, -1.0, "hold", spot, "centurion")
	one.order_facing = Vector2.DOWN
	await _frames(20)
	print("centurion model: ", "new" if one.uses_new_model() else "old")
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	for pose in [["idle", 0.6], ["run", 0.25], ["slash", 0.3], ["slash-late", 0.6], ["death", 99.0]]:
		await _pose(one, str(pose[0]).trim_suffix("-late"), float(pose[1]))
		for view in [["front", 0.0], ["side", PI / 2], ["back", PI], ["quarter", 2.4]]:
			_look(one, float(view[1]), 3.6, 1.0)
			await _frames(3)
			_save("pose-%s-%s" % [pose[0], view[0]])
	await _pose(one, "idle", 0.6)
	_look(one, 0.5, 2.2, 1.3)
	await _frames(3)
	_save("closeup")
	one._hurt = 99.0
	one._body.flash(true)
	_look(one, 0.5, 3.6, 1.0)
	await _frames(3)
	_save("hurt-flash")
	one._hurt = 0.0
	one._body.flash(false)
	# Dying in play: hurt() hides the kit and plays the death (the game's own path).
	one._body._oneshot = 0.0
	one._body.anim.play()
	one.hurt(9999.0)
	await _frames(150)
	for view in [["front", 0.0], ["side", PI / 2]]:
		_look(one, float(view[1]), 3.6, 0.6)
		await _frames(3)
		_save("died-%s" % view[0])
	main.soldiers.erase(one)
	one.queue_free()
	# Beside a standard legionary, idle, facing the camera.
	var cen = main._spawn_soldier(spot + Vector2(-12, 0), -1.0, "hold", spot + Vector2(-12, 0), "centurion")
	var leg = main._spawn_soldier(spot + Vector2(12, 0), -1.0, "hold", spot + Vector2(12, 0), "legionary")
	cen.order_facing = Vector2.DOWN
	leg.order_facing = Vector2.DOWN
	await _frames(20)
	for s in [cen, leg]:
		await _pose(s, "idle", 0.6)
	var mid: Vector3 = (cen.global_position + leg.global_position) * 0.5
	main.hud.visible = false
	for view in [["front", 0.15, 5.0], ["side", 0.9, 5.0], ["back", PI - 0.3, 5.0], ["far", 0.5, 11.0]]:
		var dir := Vector3(sin(float(view[1])), 0.2, cos(float(view[1]))).normalized()
		cam.global_position = mid + Vector3(0, 1.0, 0) + dir * float(view[2])
		cam.look_at(mid + Vector3(0, 1.0, 0))
		await _frames(3)
		_save("beside-%s" % view[0])
	main.hud.visible = true
	for s in [cen, leg]:
		s._body._oneshot = 0.0
		main.soldiers.erase(s)
		s.queue_free()
	# A centurion leading 29 legionaries, following the player in a shield wall, then a line.
	p.visible = true
	for i in 30:
		var near: Vector2 = main.world.random_walkable_near(p.pos, 20.0, 80.0, main.rng)
		main._spawn_soldier(near if near != Vector2.INF else p.pos, -1.0, "follow", p.pos, "centurion" if i == 0 else "legionary")
	main.formation = "shield wall"
	main._reassign_slots()
	main.player.facing = Vector2.UP
	await _settle(240)
	cam.current = false
	main.camera.make_current()
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		p.torch_time = 999.0 if t[0] == "night" else 0.0
		for z in [0.55, 1.2, 2.2]:
			main.zoom = z
			main.cam_yaw = 2.6
			await _frames(30)
			_save("legion-%s-z%.1f" % [t[0], z])
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	p.torch_time = 0.0
	main.formation = "line"
	main._reassign_slots()
	await _settle(240)
	main.zoom = 1.0
	main.cam_yaw = 2.9
	await _frames(30)
	_save("legion-line-day")
	print("CENTURION_SHOTS_DONE ", _dir)
	quit(0)


## Lets the soldiers walk to their places (the game's own loop moves them).
func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _pose(s, action: String, t: float) -> void:
	var body = s._body
	body._oneshot = 0.0
	body.play_once(action)
	var anim: AnimationPlayer = body.anim
	anim.play(body._actions[action], 0.0)
	anim.seek(minf(t, anim.current_animation_length - 0.01), true)
	anim.pause()
	body._oneshot = 1e9
	await _frames(3)


func _look(s, yaw: float, dist: float, height: float) -> void:
	var centre: Vector3 = s.global_position + Vector3(0, height, 0)
	var dir := Vector3(sin(yaw), 0.15, cos(yaw)).normalized()
	cam.global_position = centre + dir * dist
	cam.look_at(centre)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
