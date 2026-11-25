## Renders the views used to compare the building prototype (phase 4B,
## GRAPHICS_BUILDING_PROTOTYPE.md) before and after. On cleared open ground:
##   - three cottages, one of them badly damaged (it leans);
##   - a stone wall running east-west that turns a corner north-south;
##   - an archer tower and a torch post;
##   - build previews: a cottage where it fits (green) and a tower where it
##     doesn't (red);
## seen close, middle and far, in first person, at night and in winter, and the
## benchmark village. Run it twice, with and without --buildings=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/building_shots.gd [-- --buildings=0]
## Images go to $SHOT_DIR (default: user://building_shots).
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")
const Structure = preload("res://scripts/structure.gd")

var _dir := ""
var main: Node


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("building_shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1500.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _hold(0.0, 5)
	if main.hud.is_modal():
		main.hud._choose(0)
	main.hud.toggle_help()
	main.bench_mode = true
	main.world.set_season("spring")
	var bench = PerfBench.new()
	bench.main = main
	main.rng.seed = 20261124
	var spots: Dictionary = bench._find_spots()
	var w = main.world
	var at: Vector2 = spots["empty"]
	var c0: Vector2i = w.cell_of(at)
	# Clear the trees and rocks around the showcase, for the picture only.
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			if w.prop_type(c0 + Vector2i(dx, dz)) != "":
				w.prop_changes[c0 + Vector2i(dx, dz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
	w._props_dirty = true
	bench._go(at)
	for i in 3:
		main._add_structure("house", c0 + Vector2i(-3 + i * 2, -3))
	(main.buildings[c0 + Vector2i(1, -3)] as Structure).damage(Structure.max_hp("house") * 0.7)  # leans
	for i in 6:
		main._add_structure("stone_wall", c0 + Vector2i(-4 + i, 2))
	for i in 3:
		main._add_structure("stone_wall", c0 + Vector2i(1, 3 + i))
	main._add_structure("archer_tower", c0 + Vector2i(4, -1))
	main._add_structure("torch_post", c0 + Vector2i(3, 1))
	_ghost("house", c0 + Vector2i(-3, -1), true)
	_ghost("archer_tower", c0 + Vector2i(-1, -1), false)
	main.player.pos = w.cell_center(c0 + Vector2i(0, 0))
	main.player.facing = Vector2.UP
	main.player.visible = true
	for t in [["close", 0.55, 0.5], ["close2", 0.55, 2.6], ["mid", 1.2, 0.5], ["mid2", 1.2, 3.6], ["far", 3.2, 0.5]]:
		main.zoom = float(t[1])
		main.cam_yaw = float(t[2])
		await _hold(0.3, 25)
		_save("showcase-%s" % t[0])
	main.set_first_person(true, false)
	main.cam_yaw = PI  # looking north at the cottages
	main.fp_pitch = -0.05
	await _hold(0.3, 25)
	_save("showcase-first-person")
	main.cam_yaw = 0.0  # south, along the wall
	await _hold(0.3, 25)
	_save("showcase-first-person-wall")
	main.set_first_person(false, false)
	main.zoom = 1.2
	main.cam_yaw = 0.5
	await _hold(0.85, 40)
	_save("showcase-night")
	main.world.set_season("winter")
	main._update_weather()
	main.world.update_view(main.player.pos, true)
	await _hold(0.3, 40)
	_save("showcase-winter")
	main.world.set_season("spring")
	main._update_weather()
	# The benchmark village (four cottages and a tower among other buildings).
	var village: Vector2 = spots["village"]
	bench._go(village)
	bench._build_village(village)
	for st in main.settlers:
		st.visible = false
	main.player.visible = false
	for k in 2:
		main.zoom = 1.2
		main.cam_yaw = k * PI + 0.4
		await _hold(0.3, 30)
		_save("village-%d" % k)
	await _hold(0.85, 40)
	_save("village-night")
	print("BUILDING_SHOTS_DONE ", _dir)
	quit(0)


## A build preview, as the game shows one in build mode.
func _ghost(kind: String, cell: Vector2i, valid: bool) -> void:
	var g := Structure.new()
	g.setup(main.world, kind, cell)
	main.entities.add_child(g)
	g.make_ghost(valid)
	g.position = main.world.to_3d(main.world.cell_center(cell))


## Sets the time of day (0..1), then waits `n` frames.
func _hold(day: float, n: int) -> void:
	if day > 0.0:
		main.clock = main.DAY_LENGTH * day
		main._update_lighting()
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	print("saved ", name)
