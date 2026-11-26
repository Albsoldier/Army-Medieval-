## Renders the swords and axes for comparing the phase 4E.1 weapons with the
## old ones (GRAPHICS_PHASE_4E1_SWORDS.md): each weapon on its own, front and
## side; the player holding each sword tier and the axe (idle and mid-swing,
## front and side); first person; raiders and a chief with their axes, close
## and at the game's distance, by day and at night. Run it twice, with and
## without --swords=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/weapon_shots.gd [-- --swords=0]
## Images go to $SHOT_DIR (default: user://weapon_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("weapon_shots")
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
	for wolf in main.wolves.duplicate():
		main.wolves.erase(wolf)
		wolf.queue_free()
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	var p = main.player
	p.facing = Vector2.DOWN
	p.sword_tier = 2
	p.has_axe = true
	await _frames(20)
	print("weapons: ", "new" if p.use_new_weapons else "old")
	cam = Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	main.hud.visible = false
	# Each weapon on its own, standing upright beside the player: a copy of the
	# player's own weapon node for each sword tier, then the axe and a raider's.
	var stand := Node3D.new()
	root.add_child(stand)
	var base: Vector3 = p.global_position + Vector3(2.0, 1.1, 0.0)  # above the grass
	var shown := []
	for tier in 3:
		p.sword_tier = tier
		p._restyle_gear()
		shown.append(_copy(p._sword, stand))
	shown.append(_copy(p._axe, stand))
	var raider = main._spawn_raider("raider", p.pos + Vector2(0, -60))
	main.wolves.erase(raider)
	await _frames(3)
	shown.append(_copy(raider._axe, stand))
	var names := ["iron-sword", "steel-sword", "gilded-sword", "axe", "raider-axe"]
	for i in shown.size():
		var n: Node3D = shown[i]
		n.visible = true
		n.global_transform = Transform3D(Basis.IDENTITY, base + Vector3(i * 0.32, 0, 0))
	await _frames(3)
	# All together, then each close up: front (the flat of the blade) and side (the edge).
	_aim(base + Vector3(0.64, 0.4, 0), Vector3(0, 0.1, 1.0), 2.4)
	await _frames(3)
	_save("lineup")
	for i in shown.size():
		var centre: Vector3 = base + Vector3(i * 0.32, 0.38, 0)
		if names[i].ends_with("axe"):
			centre = base + Vector3(i * 0.32, 0.5, 0.1)  # between the head and the haft
		# Swords show their flat from +z; an axe's head faces +z, so its flat is seen from +x.
		var axe: bool = names[i].ends_with("axe")
		for view in [["front", Vector3(1, 0.05, 0.12) if axe else Vector3(0, 0.05, 1)], ["side", Vector3(0, 0.05, 1) if axe else Vector3(1, 0.05, 0.12)]]:
			for other in shown:
				(other as Node3D).visible = other == shown[i]
			_aim(centre, view[1], 1.25)
			await _frames(3)
			_save("weapon-%s-%s" % [names[i], view[0]])
		# The hilt, closer.
		var hilt_y := 0.62 if names[i].ends_with("axe") else 0.05  # an axe's head, a sword's hilt
		_aim(base + Vector3(i * 0.32, hilt_y, 0), Vector3(1, 0.15, 0.35) if names[i].ends_with("axe") else Vector3(0.35, 0.15, 1), 0.45)
		await _frames(3)
		_save("weapon-%s-hilt" % names[i])
	stand.queue_free()
	# The player holding each: idle and mid-swing, front and side.
	for held in [["iron-sword", "sword", 0], ["steel-sword", "sword", 1], ["gilded-sword", "sword", 2], ["axe", "axe", 0]]:
		p.sword_tier = int(held[2])
		p.equip(str(held[1]))
		p._restyle_gear()
		for pose in [["idle", 0.6], ["slash", 0.32]]:
			await _pose(p._body, str(pose[0]), float(pose[1]))
			for view in [["front", Vector3(0.25, 0.12, 1)], ["side", Vector3(1, 0.12, 0.2)]]:
				_aim(p.global_position + Vector3(0, 1.05, 0), view[1], 2.6)
				await _frames(3)
				_save("held-%s-%s-%s" % [held[0], pose[0], view[0]])
	# The raiders and a chief with their axes, close and from the game's camera.
	p._body._oneshot = 0.0
	var chief = main._spawn_raider("raider_chief", p.pos + Vector2(-20, -60))
	main.wolves.erase(chief)
	raider.pos = p.pos + Vector2(20, -60)
	for r in [raider, chief]:
		r.facing = Vector2.DOWN
		r._animate(0.016)
	await _frames(3)
	for r in [raider, chief]:
		await _pose(r._body, "attack", 0.35)
		r._animate(0.0)
	var mid: Vector3 = (raider.global_position + chief.global_position) * 0.5
	_aim(mid + Vector3(0, 1.0, 0), Vector3(0.3, 0.12, 1), 4.6)
	await _frames(3)
	_save("raiders-close")
	for r in [raider, chief]:
		r._body._oneshot = 0.0
		r._body.play("idle")
	for k in 6:
		var more = main._spawn_raider("raider", p.pos + Vector2(-50 + k * 20, -90))
		main.wolves.erase(more)
		more.facing = Vector2.DOWN
	await _frames(30)
	for r in get_nodes_in_group_raiders():
		r._animate(0.016)
	cam.current = false
	main.camera.make_current()
	main.hud.visible = true
	p.equip("sword")
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		p.torch_time = 999.0 if t[0] == "night" else 0.0
		for z in [0.55, 1.2]:
			main.zoom = z
			main.cam_yaw = 0.3
			for k in 20:
				for r in get_nodes_in_group_raiders():
					r._animate(0.016)
				await process_frame
			_save("game-%s-z%.1f" % [t[0], z])
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.set_first_person(true, false)
	main.cam_yaw = 0.5
	main.fp_pitch = -0.2
	for tool in ["sword", "axe"]:
		p.equip(tool)
		await _frames(20)
		_save("first-person-%s" % tool)
	main.set_first_person(false, false)
	print("WEAPON_SHOTS_DONE ", _dir)
	quit(0)


func get_nodes_in_group_raiders() -> Array:
	return main.entities.get_children().filter(func(n): return n.has_method("_build_kit") and not n.is_queued_for_deletion())


## A copy of a weapon node (its meshes and materials), as a stand-alone node.
func _copy(node: Node3D, parent: Node3D) -> Node3D:
	var c := node.duplicate() as Node3D
	c.top_level = false
	# Its own materials: the old swords are tinted per tier on their materials.
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = true  # (4E.5: a batched piece's own mesh is hidden)
		if (mi as MeshInstance3D).material_override:
			(mi as MeshInstance3D).material_override = (mi as MeshInstance3D).material_override.duplicate()
	parent.add_child(c)
	return c


func _aim(centre: Vector3, from: Vector3, dist: float) -> void:
	cam.global_position = centre + from.normalized() * dist
	cam.look_at(centre)


func _pose(body, action: String, t: float) -> void:
	body._oneshot = 0.0
	body.play_once(action)
	var anim: AnimationPlayer = body.anim
	anim.play(body._actions[action], 0.0)
	anim.seek(minf(t, anim.current_animation_length - 0.01), true)
	anim.pause()
	body._oneshot = 1e9
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
