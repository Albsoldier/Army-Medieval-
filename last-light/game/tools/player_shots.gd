## Renders the player for comparing the character prototype (phase 4C,
## GRAPHICS_CHARACTER_PROTOTYPE.md) before and after: front, side and back in
## each pose (idle, walk, run, punch, sword slash, death), every piece of
## equipment, the hurt flash, first person, and the game's camera by day and
## at night. Run it twice, with and without --player=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/player_shots.gd [-- --player=0]
## Images go to $SHOT_DIR (default: user://player_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("player_shots")
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
	p.facing = Vector2.DOWN
	await _frames(20)
	# Close-ups with our own camera; each pose is held as a paused one-shot.
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	var poses := [["idle", "idle", 0.6], ["walk", "walk", 0.3], ["run", "run", 0.25], ["punch", "punch", 0.25],
		["slash", "slash", 0.35], ["death", "death", 99.0]]
	for pose in poses:
		await _pose(str(pose[1]), float(pose[2]))
		for view in [["front", 0.0], ["side", PI / 2], ["back", PI]]:
			_look(float(view[1]), 3.4, 1.0)
			await _frames(3)
			_save("pose-%s-%s" % [pose[0], view[0]])
	# Equipment: each tool in hand, armour on, torch lit; idle and mid-swing.
	p.has_spear = true
	p.sword_tier = 1
	p.has_axe = true
	p.has_pickaxe = true
	p.armour = true
	p.armour_on = true
	p.armour_tier = 1
	p.torch_time = 999.0
	for tool in ["sword", "spear", "axe", "pickaxe"]:
		p.equip(tool)
		for pose in [["idle", 0.6], ["slash", 0.35]]:
			await _pose(str(pose[0]), float(pose[1]))
			_look(0.6, 3.2, 1.0)
			await _frames(3)
			_save("gear-%s-%s" % [tool, pose[0]])
	# Refinement (GRAPHICS_PLAYER_REFINEMENT.md): the ranger's armour in every
	# tier, hood down, skin tones, the second outfit and the backpack.
	if p._look_mesh != null:
		var mi: GeometryInstance3D = p._look_mesh
		p.equip("sword")
		await _pose("idle", 0.6)
		for tier in 4:
			p.armour_tier = tier
			for view in [["front", 0.35], ["back", PI - 0.35]]:
				_look(float(view[1]), 2.4, 1.15)
				await _frames(3)
				_save("armour-%d-%s" % [tier, view[0]])
		p.armour_on = false
		await _frames(2)
		for look in [["hood-up", {}], ["hood-down", {"hood": "down"}], ["earth", {"outfit": "earth"}],
				["earth-hood-down", {"outfit": "earth", "hood": "down"}], ["no-backpack", {"backpack": "0"}]]:
			p.Appearance.apply(mi, p.Appearance.from_options(look[1]))
			for view in [["front", 0.35], ["side", PI / 2], ["back", PI - 0.35]]:
				_look(float(view[1]), 2.6, 1.1)
				await _frames(3)
				_save("look-%s-%s" % [look[0], view[0]])
		for tone in p.Appearance.SKIN_TONES:
			p.Appearance.apply(mi, p.Appearance.from_options({"skin": tone, "hood": "down"}))
			_look(0.25, 1.0, 1.5)
			await _frames(3)
			_save("skin-%s" % tone)
		# Hood down through the animations: nothing comes loose.
		p.Appearance.apply(mi, p.Appearance.from_options({"hood": "down"}))
		p.armour_on = true
		p.armour_tier = 1
		for pose in [["run", 0.25], ["slash", 0.35], ["death", 99.0]]:
			await _pose(str(pose[0]), float(pose[1]))
			_look(0.8, 3.0, 1.0)
			await _frames(3)
			_save("hood-down-%s" % pose[0])
		p.Appearance.apply(mi, p.appearance)
		p.armour_on = true
		p.armour_tier = 1
	# Task 6: the mesh LODs a soldier version could start from, forced with
	# the viewport's LOD threshold (higher: coarser levels sooner).
	await _pose("idle", 0.6)
	for lod in [["lod-full", 0.0], ["lod-1", 12.0], ["lod-2", 200.0]]:
		root.get_viewport().mesh_lod_threshold = float(lod[1])
		_look(0.35, 3.0, 1.0)
		await _frames(3)
		_save(lod[0])
	root.get_viewport().mesh_lod_threshold = 1.0
	# Hurt flash.
	p.equip("sword")
	await _pose("idle", 0.6)
	p.hurt_flash = 99.0
	_look(0.6, 3.2, 1.0)
	await _frames(3)
	_save("hurt-flash")
	p.hurt_flash = 0.0
	# The game's own camera, by day and at night, and first person.
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
		for z in [0.55, 1.6]:
			main.zoom = z
			main.cam_yaw = 0.5
			await _frames(30)
			_save("game-%s-z%.1f" % [t[0], z])
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.set_first_person(true, false)
	main.cam_yaw = 0.5
	main.fp_pitch = -0.35
	p.torch_time = 999.0
	await _frames(30)
	_save("first-person")
	main.set_first_person(false, false)
	print("PLAYER_SHOTS_DONE ", _dir)
	quit(0)


## Holds the player in `action` at `t` seconds (the end, for a large t).
func _pose(action: String, t: float) -> void:
	var p = main.player
	var body = p._body
	if not body.has_action(action):
		print("missing action ", action)
		return
	body._oneshot = 0.0
	body.play_once(action)
	var anim: AnimationPlayer = body.anim
	anim.play(body._actions[action], 0.0)  # no cross-fade: frozen time would never finish one
	anim.seek(minf(t, anim.current_animation_length - 0.01), true)
	anim.pause()
	body._oneshot = 1e9  # hold it: the game's own idle/run won't take over
	p.facing = Vector2.DOWN
	await _frames(3)


## Puts our camera around the player: `yaw` from the front, `dist` away, at `height`.
func _look(yaw: float, dist: float, height: float) -> void:
	var p = main.player
	var centre: Vector3 = p.global_position + Vector3(0, height, 0)
	var dir := Vector3(sin(yaw), 0.15, cos(yaw)).normalized()
	cam.global_position = centre + dir * dist
	cam.look_at(centre)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
