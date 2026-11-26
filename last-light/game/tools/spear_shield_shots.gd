## Renders the spears and shields for comparing the phase 4E.2 models with the
## old ones (GRAPHICS_PHASE_4E2_SPEARS_SHIELDS.md): every spear and shield on
## its own (front, side, back) and close up; a legionary, a centurion, a
## cavalryman and raiders holding them in idle, run, attack and death from the
## front, side and back; the player with each spear tier; a legion led by a
## centurion by day and at night. Run it twice, with and without
## --spears=0 --shields=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/spear_shield_shots.gd [-- --spears=0 --shields=0]
## Images go to $SHOT_DIR (default: user://spear_shield_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("spear_shield_shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1700.0).timeout.connect(func(): quit(1))
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
	p.has_spear = true
	await _frames(20)
	print("spears: ", "new" if p.use_new_spears else "old", ", shields: ", "new" if main.Soldier.use_new_shields else "old")
	cam = Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	main.hud.visible = false
	# The kit on its own, standing above the grass: copies of the real pieces.
	var leg = main._spawn_soldier(p.pos + Vector2(-40, -70), -1.0, "hold", p.pos + Vector2(-40, -70), "legionary")
	var cen = main._spawn_soldier(p.pos + Vector2(0, -70), -1.0, "hold", p.pos + Vector2(0, -70), "centurion")
	var cav = main._spawn_soldier(p.pos + Vector2(40, -70), -1.0, "hold", p.pos + Vector2(40, -70), "cavalry")
	var raider = main._spawn_raider("raider", p.pos + Vector2(80, -70))
	var chief = main._spawn_raider("raider_chief", p.pos + Vector2(110, -70))
	for r in [raider, chief]:
		main.wolves.erase(r)
	await _frames(5)
	var stand := Node3D.new()
	root.add_child(stand)
	var base: Vector3 = p.global_position + Vector3(2.2, 1.1, 0.0)
	var spears := []
	var spear_names := ["wooden", "flint", "iron", "steel", "gilded"]
	for tier in 5:
		p.spear_tier = tier
		p._restyle_gear()
		spears.append(_copy(p._spear, stand))
	spears.append(_copy(leg._spear, stand))
	spears.append(_copy(cen._spear, stand))
	spears.append(_copy(cav._spear, stand))
	spear_names.append_array(["legionary", "centurion", "cavalry"])
	for i in spears.size():
		(spears[i] as Node3D).global_transform = Transform3D(Basis.IDENTITY, base + Vector3(i * 0.16, -0.3, 0))
		(spears[i] as Node3D).visible = true
	await _frames(3)
	_aim(base + Vector3(0.56, 0.45, 0), Vector3(0, 0.08, 1), 3.4)
	await _frames(3)
	_save("spears-lineup")
	# The heads, close.
	for i in spears.size():
		for other in spears:
			(other as Node3D).visible = other == spears[i]
		_aim(base + Vector3(i * 0.16, 0.88, 0), Vector3(0.3, 0.1, 1), 0.55)
		await _frames(3)
		_save("spearhead-%s" % spear_names[i])
	for s in spears:
		(s as Node3D).visible = false
	var shields := [_copy(leg._shield, stand), _copy(cen._shield, stand), _copy(raider._shield, stand), _copy(chief._shield, stand)]
	var shield_names := ["legionary", "centurion", "raider", "chief"]
	for i in shields.size():
		(shields[i] as Node3D).global_transform = Transform3D(Basis.IDENTITY, base + Vector3(i * 0.75, 0.3, 0))
		(shields[i] as Node3D).visible = true
	await _frames(3)
	_aim(base + Vector3(1.12, 0.3, 0), Vector3(0, 0.08, 1), 4.2)
	await _frames(3)
	_save("shields-lineup")
	for i in shields.size():
		for other in shields:
			(other as Node3D).visible = other == shields[i]
		var centre: Vector3 = base + Vector3(i * 0.75, 0.3, 0)
		for view in [["front", Vector3(0.25, 0.1, 1)], ["side", Vector3(1, 0.1, 0.05)], ["back", Vector3(-0.25, 0.1, -1)]]:
			_aim(centre, view[1], 1.9)
			await _frames(3)
			_save("shield-%s-%s" % [shield_names[i], view[0]])
		_aim(centre + Vector3(0.1, 0.1, 0.0), Vector3(0.3, 0.2, 1), 0.6)  # the boss and paint, close
		await _frames(3)
		_save("shield-%s-close" % shield_names[i])
	stand.queue_free()
	# Carried: the legionary and the centurion in each pose, from three sides.
	for s in [leg, cen]:
		s.order_facing = Vector2.DOWN
	await _frames(10)
	for pair in [["legionary", leg], ["centurion", cen]]:
		var s = pair[1]
		for pose in [["idle", 0.6], ["run", 0.25], ["slash", 0.32], ["death", 99.0]]:
			await _pose(s._body, str(pose[0]), float(pose[1]))
			s._animate(0.0)
			for view in [["front", Vector3(0.15, 0.12, 1)], ["side", Vector3(1, 0.12, 0.1)], ["back", Vector3(-0.15, 0.12, -1)]]:
				_aim(s.global_position + Vector3(0, 0.95, 0), view[1], 3.3)
				await _frames(3)
				_save("carried-%s-%s-%s" % [pair[0], pose[0], view[0]])
	# The cavalryman's lance, and raiders' shields.
	_aim(cav.global_position + Vector3(0, 1.3, 0), Vector3(0.6, 0.15, 1), 4.5)
	await _frames(3)
	_save("carried-cavalry")
	for r in [raider, chief]:
		r.facing = Vector2.DOWN
		r._animate(0.016)
	_aim((raider.global_position + chief.global_position) * 0.5 + Vector3(0, 1.0, 0), Vector3(0.2, 0.12, 1), 4.6)
	await _frames(3)
	_save("carried-raiders")
	# The player with each spear tier.
	p.equip("spear")
	for tier in 5:
		p.spear_tier = tier
		p._restyle_gear()
		await _pose(p._body, "idle", 0.6)
		p.tick_visuals(0.0)
		_aim(p.global_position + Vector3(0, 1.1, 0), Vector3(0.35, 0.1, 1), 2.8)
		await _frames(3)
		_save("player-spear-%s" % spear_names[tier])
	p._body._oneshot = 0.0
	# A legion led by a centurion, by day and at night.
	for s in [leg, cen, cav]:
		s._body._oneshot = 0.0
		main.soldiers.erase(s)
		s.queue_free()
	for r in [raider, chief]:
		r.queue_free()
	for i in 30:
		var near: Vector2 = main.world.random_walkable_near(p.pos, 20.0, 80.0, main.rng)
		main._spawn_soldier(near if near != Vector2.INF else p.pos, -1.0, "follow", p.pos, "centurion" if i == 0 else "legionary")
	main.formation = "shield wall"
	main._reassign_slots()
	p.facing = Vector2.UP
	await _frames(240)
	cam.current = false
	main.camera.make_current()
	main.hud.visible = true
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		p.torch_time = 999.0 if t[0] == "night" else 0.0
		for z in [0.55, 1.2]:
			main.zoom = z
			main.cam_yaw = 2.6
			await _frames(30)
			_save("legion-%s-z%.1f" % [t[0], z])
	print("SPEAR_SHIELD_SHOTS_DONE ", _dir)
	quit(0)


## A copy of a kit node (its meshes and materials), as a stand-alone node.
func _copy(node: Node3D, parent: Node3D) -> Node3D:
	var c := node.duplicate() as Node3D
	c.top_level = false
	for mi in c.find_children("*", "MeshInstance3D", true, false):
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
