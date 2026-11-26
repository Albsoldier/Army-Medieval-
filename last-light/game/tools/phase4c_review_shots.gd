## Phase 4C final review (GRAPHICS_PHASE_4C_FINAL.md): renders every approved
## combination of the ranger's look together: the two outfits, hood up and
## down, and armour off and on (iron), each in idle, walk, run, punch and
## slash from a different side, and head close-ups for clipping. The excluded
## features stay off: no backpack, the default skin.
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/phase4c_review_shots.gd
## Images go to $SHOT_DIR (default: user://phase4c_review), named
## <shot>-<outfit>-<hood>-<armour>.png.
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")

var _dir := ""
var main: Node
var cam: Camera3D
var mi: GeometryInstance3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("phase4c_review")
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
		print("not the ranger (?player=0?)")
		quit(1)
		return
	p.facing = Vector2.DOWN
	p.sword_tier = 1
	p.armour = true
	p.armour_tier = 1
	p.equip("sword")
	await _frames(20)
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.make_current()
	for pose in [["idle", 0.6, 0.0], ["walk", 0.3, PI / 2], ["run", 0.25, 2.4], ["punch", 0.25, -PI / 2], ["slash", 0.35, 0.6]]:
		await _pose(str(pose[0]), float(pose[1]))
		await _all("pose-%s" % pose[0], float(pose[2]), 3.0, 1.0)
	await _pose("idle", 0.6)
	for view in [["front", 0.2], ["side", PI / 2], ["back", PI - 0.5]]:
		await _all("head-%s" % view[0], float(view[1]), 1.3, 1.45)
	print("REVIEW_SHOTS_DONE ", _dir)
	quit(0)


## The same view in all eight approved looks.
func _all(name: String, yaw: float, dist: float, height: float) -> void:
	var p = main.player
	for outfit in ["ranger", "earth"]:
		for hood in [true, false]:
			for armour in [false, true]:
				p.armour_on = armour
				p._restyle_ranger_armour()
				p.Appearance.apply(mi, {"outfit": outfit, "hood": hood, "backpack": false, "skin": "medium"})
				p.tick_visuals(0.0)
				_look(yaw, dist, height)
				await _frames(3)
				var file := "%s-%s-%s-%s.png" % [name, outfit, "up" if hood else "down", "armour" if armour else "plain"]
				root.get_viewport().get_texture().get_image().save_png(_dir.path_join(file))
	print("saved ", name)


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
