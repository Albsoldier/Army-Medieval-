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
	_run_game.call_deferred()


func _run_game() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame

	var world = main.world
	_check(world.land_tile_count() > 3000, "island has enough land (%d tiles)" % world.land_tile_count())
	_check(world.props.size() > 300, "island has props (%d)" % world.props.size())
	_check(world.is_walkable(main.player.position), "player spawns on walkable ground")

	# Same seed, same island.
	var copy = load("res://scripts/world.gd").new()
	copy.generate(main.seed_value)
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
	main.player.position = main.campfires[0].position + Vector2(10, 0)
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
