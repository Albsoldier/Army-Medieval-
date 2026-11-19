## Headless smoke test, run in CI:
##   godot --headless --path last-light/game --script res://tools/smoke_test.gd
## Checks every script compiles, then plays a few in-game days offline.
extends SceneTree

var _failed := false


func _initialize() -> void:
	for file in DirAccess.get_files_at("res://scripts"):
		if not file.ends_with(".gd"):
			continue
		var script: GDScript = load("res://scripts/" + file)
		if script == null or not script.can_instantiate():
			_fail("script did not compile: " + file)
	if _failed:
		quit(1)
		return
	# If a script error stops the test part-way, fail instead of hanging.
	create_timer(120.0).timeout.connect(_on_watchdog)
	_run_game.call_deferred()


func _on_watchdog() -> void:
	_fail("timed out: the test stopped part-way (see errors above)")
	quit(1)


func _run_game() -> void:
	var started := Time.get_ticks_msec()
	print("  ..   loading the main scene")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	print("  ..   main scene ready in %d ms" % (Time.get_ticks_msec() - started))
	if main.get_script() == null or not ("world" in main):
		_fail("main scene's script did not attach (check the root node type in main.tscn)")
		quit(1)
		return

	var world = main.world
	_check(world.land_tile_count() > 3000, "island has enough land (%d tiles)" % world.land_tile_count())
	_check(world.props.size() > 300, "island has props (%d)" % world.props.size())
	_check(world.is_walkable(main.player.pos), "player spawns on walkable ground")
	_check(world.get_node_or_null("Terrain") != null, "3D terrain built")
	var body = main.player._body
	_check(body.anim != null, "survivor model has animations")
	for action in ["idle", "run", "punch", "slash", "death"]:
		_check(body.has_action(action), "survivor can play '%s'" % action)
	var wolf = load("res://scripts/wolf.gd").new()
	wolf.world = world
	wolf.pos = main.player.pos + Vector2(200, 0)
	main.entities.add_child(wolf)
	for action in ["run", "attack", "death"]:
		_check(wolf._body.has_action(action), "wolf can play '%s'" % action)
	wolf.queue_free()
	var ground: float = world.height_at(main.player.pos)
	_check(ground > -0.5 and ground < 6.0, "spawn height looks sane (%.2f m)" % ground)

	# Same seed, same island.
	var gen_start := Time.get_ticks_msec()
	var copy = load("res://scripts/world.gd").new()
	copy.generate(main.seed_value)
	print("  ..   island generated in %d ms" % (Time.get_ticks_msec() - gen_start))
	_check(copy.props.size() == world.props.size(), "generation is deterministic")
	copy.free()

	# Get past the name prompt if this machine has no profile yet.
	if main.hud.is_modal():
		main.hud._choose(0)
	_check(main.started, "run started")

	# Gather, craft and use things.
	main.player.add_item("wood", 20)
	main.player.add_item("stone", 10)
	main._craft("campfire")
	_check(main.campfires.size() == 1, "campfire crafted")
	main._craft("torch")
	_check(main.player.torch_time > 0.0, "torch crafted")
	main._craft("spear")
	_check(main.player.has_spear, "spear crafted")
	main.player.add_item("raw_meat", 2)
	main.player.pos = main.campfires[0].pos + Vector2(10, 0)
	main._interact()
	_check(main.player.count("cooked_meat") == 2, "meat cooked at the fire")
	main._eat()
	_check(main.player.count("cooked_meat") == 1, "ate cooked meat")

	# Simulate three in-game days by stepping the loop.
	var steps := int(240.0 * 3 / 0.25)
	for i in steps:
		if not main.alive:
			break
		main._process(0.25)
		if i % 200 == 0:
			print("  ..   step %d/%d, day %d, %d ms" % [i, steps, main.day, Time.get_ticks_msec() - started])
			await process_frame
	_check(main.day >= 2 or not main.alive, "time passes (day %d, alive %s)" % [main.day, main.alive])

	# Starve to death and check the death flow opens the epitaph dialog.
	if main.alive:
		main.player.health = 0.0
		main._process(0.1)
	_check(not main.alive and main.hud.is_modal(), "death opens the epitaph dialog")

	print("Smoke test %s." % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed = true
	printerr("  FAIL ", label)
