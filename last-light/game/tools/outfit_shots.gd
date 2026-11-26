## Renders the ranger in the original green outfit and the kit's beige and
## brown one, for comparing the two (phase 4C, GRAPHICS_PLAYER_OUTFITS.md):
## close-ups with the hood up and down, each animation, the armour in every
## tier, tools, the game's camera by day and at night, and first person. The
## backpack is hidden (it is not part of this work).
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/outfit_shots.gd
## Images go to $SHOT_DIR (default: user://outfit_shots), named
## <shot>-<outfit>[-<hood>].png. QUICK=1 renders only the close-ups.
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")
const OUTFITS := ["ranger", "earth"]

var _dir := ""
var main: Node
var cam: Camera3D
var mi: GeometryInstance3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("outfit_shots")
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
	var both_hoods := [true, false]
	# Close-ups, hood up and down: skin, hair and eyes stay as they are; only the clothes change.
	await _pose("idle", 0.6)
	for view in [["front", 0.3], ["side", PI / 2], ["back", PI - 0.3]]:
		await _shots("closeup-%s" % view[0], both_hoods, float(view[1]), 1.9, 1.3)
	if OS.get_environment("QUICK") == "1":
		print("OUTFIT_SHOTS_DONE ", _dir)
		quit(0)
		return
	# Each animation, front and back, hood up; run and slash also hood down.
	for pose in [["idle", 0.6], ["walk", 0.3], ["run", 0.25], ["punch", 0.25], ["slash", 0.35], ["death", 99.0]]:
		await _pose(str(pose[0]), float(pose[1]))
		var hoods := both_hoods if pose[0] in ["run", "slash"] else [true]
		for view in [["front", 0.0], ["back", PI]]:
			await _shots("pose-%s-%s" % [pose[0], view[0]], hoods, float(view[1]), 3.2, 1.0)
	# The approved armour in every tier: it keeps its own colours over either outfit.
	p.has_spear = true
	p.sword_tier = 1
	p.has_axe = true
	p.has_pickaxe = true
	p.armour = true
	p.armour_on = true
	p.equip("sword")
	await _pose("idle", 0.6)
	for tier in 4:
		p.armour_tier = tier
		p._restyle_ranger_armour()
		await _shots("armour-%d" % tier, [true], 0.35, 2.4, 1.15)
	p.armour_tier = 2
	p._restyle_ranger_armour()
	await _shots("armour-hood-down", [false], 0.35, 2.4, 1.15)
	# Tools mid-swing (with the torch lit).
	p.torch_time = 999.0
	for tool in ["sword", "axe", "spear", "pickaxe"]:
		p.equip(tool)
		await _pose("slash", 0.35)
		await _shots("gear-%s" % tool, [true], 0.6, 3.0, 1.1)
	# The game's camera, by day and at night with the torch, and first person.
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
		for z in [0.55, 1.6]:
			main.zoom = z
			main.cam_yaw = 0.5
			await _shots("game-%s-z%.1f" % [t[0], z], both_hoods, -1.0, 0.0, 0.0, 30)
	main.clock = main.DAY_LENGTH * 0.3
	main._update_lighting()
	main.set_first_person(true, false)
	main.cam_yaw = 0.5
	main.fp_pitch = -0.35
	await _shots("first-person", [true], -1.0, 0.0, 0.0, 30)
	main.fp_pitch = -1.2
	await _shots("first-person-down", [true], -1.0, 0.0, 0.0, 30)
	main.set_first_person(false, false)
	print("OUTFIT_SHOTS_DONE ", _dir)
	quit(0)


## Saves the same view in each outfit, for each hood given. yaw < 0: keep the current camera.
func _shots(name: String, hoods: Array, yaw: float, dist: float, height: float, settle := 3) -> void:
	for outfit in OUTFITS:
		for hood in hoods:
			main.player.Appearance.apply(mi, {"outfit": outfit, "hood": hood, "backpack": false, "skin": "medium"})
			if yaw >= 0.0:
				_look(yaw, dist, height)
			await _frames(settle)
			var file := "%s-%s%s.png" % [name, outfit, "" if hoods.size() == 1 else ("-up" if hood else "-down")]
			root.get_viewport().get_texture().get_image().save_png(_dir.path_join(file))
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
