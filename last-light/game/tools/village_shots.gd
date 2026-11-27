## Renders the village buildings for comparing the MegaKit models
## (GRAPHICS_VILLAGE_BUILDINGS.md) with the previous ones: each building close
## up (front and back), and the benchmark's built-up village from the game's
## camera, close and far, by day and at night. Run it twice, with and without
## --village=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/village_shots.gd [-- --village=0]
## Images go to $SHOT_DIR (default: user://village_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("village_shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1200.0).timeout.connect(func(): quit(1))
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
	main.rng.seed = 20261124
	var bench = PerfBench.new()
	bench.main = main
	var spots: Dictionary = bench._find_spots()
	print("village: ", "new" if main.Structure.use_village else "old")
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	main.hud.visible = false
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	# Each kind on its own on open ground, front and back (cleared of trees).
	var w = main.world
	var at_empty: Vector2 = spots["empty"]
	var c0: Vector2i = w.cell_of(at_empty)
	for dz in range(-12, 13):
		for dx in range(-16, 17):
			if w.prop_type(c0 + Vector2i(dx, dz)) != "":
				w.prop_changes[c0 + Vector2i(dx, dz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
	w._props_dirty = true
	bench._go(at_empty + Vector2(0, 200))
	await _frames(20)
	var kinds := ["house", "house", "workbench", "smokehouse", "barracks"]
	var alone := []
	for i in kinds.size():
		alone.append(main._add_structure(kinds[i], c0 + Vector2i(-12 + i * 6, -4 + (i % 2))))
	await _frames(20)
	for b in alone:
		var at: Vector3 = b.global_position + Vector3(0, 0.7 if b.kind != "workbench" else 0.3, 0)
		var dist := 3.4 if b.kind != "workbench" else 2.0
		if b.kind == "barracks":
			at.y += 0.45
			dist = 4.3
		var tag := "%s-%s" % [b.kind, str(b._model.mesh.resource_path.get_file().get_basename()) if b._model and b._model.mesh.resource_path != "" else "old"]
		for view in [["front", Vector3(0.45, 0.35, 1)], ["back", Vector3(-0.5, 0.45, -1)]]:
			cam.global_position = at + (view[1] as Vector3).normalized() * dist
			cam.look_at(at)
			cam.make_current()
			await _frames(4)
			_save("%s-%s-%s" % [tag, view[0], str(b.cell)])
	for b in alone:
		main._remove_structure(b.cell)
	# The benchmark's built-up village, from the game's camera.
	bench._go(spots["village"])
	bench._build_village(spots["village"])
	await _frames(30)
	cam.current = false
	main.camera.make_current()
	main.hud.visible = true
	for t in [["day", 0.3], ["night", 0.85]]:
		main.clock = main.DAY_LENGTH * float(t[1])
		main._update_lighting()
		main.player.torch_time = 999.0 if t[0] == "night" else 0.0
		for z in [0.55, 1.2]:
			main.zoom = z
			main.cam_yaw = 0.8
			await _frames(30)
			_save("village-%s-z%.1f" % [t[0], z])
	print("VILLAGE_SHOTS_DONE ", _dir)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
