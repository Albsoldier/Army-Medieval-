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
	load("res://scripts/save_game.gd").erase()  # start from a clean slate
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
	_check(world.SIZE >= 1024, "the island is big (%d m across)" % world.SIZE)
	_check(world.is_land(world.spawn_cell), "spawn is on land")
	_check(world.is_walkable(main.player.pos), "player spawns on walkable ground")
	_check(world.loaded_prop_count() > 300, "trees, rocks and bushes around spawn (%d)" % world.loaded_prop_count())
	var terrain_chunks := 0
	for child in world.get_children():
		if str(child.name).begins_with("Terrain_"):
			terrain_chunks += 1
	_check(terrain_chunks >= 20, "terrain chunks built around the player (%d)" % terrain_chunks)
	_check(world.terrain_at(Vector2i(2, 2)) == world.DEEP, "the far corner is open sea")
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
	copy.generate(world.seed_value)
	print("  ..   island generated in %d ms" % (Time.get_ticks_msec() - gen_start))
	var same: bool = copy.spawn_cell == world.spawn_cell
	for dz in range(-20, 21, 5):
		for dx in range(-20, 21, 5):
			var c: Vector2i = world.spawn_cell + Vector2i(dx * 3, dz * 3)
			same = same and copy.prop_type(c) == world.prop_type(c) and copy.terrain_at(c) == world.terrain_at(c)
	_check(same, "generation is deterministic")
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

	# Fell a tree, save, and load the game again in a second copy.
	var tree_cell := Vector2i(-1, -1)
	for r in range(1, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = world.spawn_cell + Vector2i(dx, dz)
				if tree_cell == Vector2i(-1, -1) and world.prop_type(c) == "tree":
					tree_cell = c
	_check(tree_cell != Vector2i(-1, -1), "found a tree near spawn")
	for i in 3:
		world.harvest(tree_cell, main.day)
	_check(world.prop_type(tree_cell) == "stump", "tree felled")

	# Build a small base and raise an army.
	main.player.add_item("wood", 300)
	main.player.add_item("stone", 150)
	main.player.add_item("berries", 150)
	var cells := _free_cells(world, world.cell_of(main.player.pos), 6, [tree_cell])
	_check(cells.size() == 6, "found room to build")
	_check(main._try_build("wood_wall", cells[0]), "built a wooden wall")
	_check(not world.is_walkable(world.cell_center(cells[0])), "walls block the way")
	_check(not main._try_build("stone_wall", cells[0]), "can't build on top of a building")
	_check(main._try_build("gate", cells[1]), "built a gate")
	var gate_pos: Vector2 = world.cell_center(cells[1])
	_check(world.is_walkable(gate_pos) and not world.is_walkable(gate_pos, true), "gates let people through but not wolves")
	_check(main._try_build("chest", cells[2]), "built a chest")
	var chest = main.buildings[cells[2]]
	var wood_before: int = main.player.count("wood")
	main._chest_store(chest)
	_check(main.player.count("wood") == 0 and int(chest.items.get("wood", 0)) == wood_before, "the chest stores items")
	main._chest_take(chest)
	_check(main.player.count("wood") == wood_before, "the chest gives them back")
	_check(main._recruit(1) == 0, "no soldiers without a barracks")
	_check(main._try_build("barracks", cells[3]), "built a barracks")
	_check(main._recruit(25) == 10, "one barracks houses 10 soldiers")
	_check(main._try_build("torch_post", cells[4]), "built a torch post")
	_check(main._try_build("tent", cells[5]), "pitched a tent")
	var line: Array = _free_line(world, world.cell_of(main.player.pos) + Vector2i(0, 13))
	_check(line.size() == 3, "found room for a north-south wall")
	for c in line:
		main._try_build("wood_wall", c)
	_check(is_equal_approx(main.buildings[line[1]].rotation.y, PI / 2), "walls in a north-south line turn to match")
	for c in line:
		main._demolish(c)
	_check(main.home == world.cell_center(cells[5]), "the tent is your new home")
	main._toggle_army_mode()
	_check(main.army_mode == "guard" and main.soldiers[0].mode == "guard", "soldiers can guard a spot")
	main._toggle_army_mode()
	for i in 60:
		main._tick_army(0.1)
	var near := 0
	for soldier in main.soldiers:
		if soldier.pos.distance_to(main.player.pos) < 120.0:
			near += 1
	_check(near >= 8, "soldiers gather behind you (%d of %d nearby)" % [near, main.soldiers.size()])
	var pup = load("res://scripts/wolf.gd").new()
	pup.world = world
	pup.pos = main.soldiers[0].pos + Vector2(12, 0)
	main.entities.add_child(pup)
	main.wolves.append(pup)
	var army_meat_before: int = main.player.count("raw_meat")
	for i in 80:
		main._tick_army(0.1)
	_check(not main.wolves.has(pup) and main.player.count("raw_meat") > army_meat_before, "soldiers kill wolves for you")
	# Far from the army, soldiers catch up but never land in the water.
	var far_spot: Vector2 = main.player.pos
	for poi in world.pois:
		if poi["type"] == "shipwreck":
			far_spot = world.random_walkable_near(world.cell_center(poi["cell"]), 60.0, 100.0, main.rng)
			break
	var back_home: Vector2 = main.player.pos
	main.player.pos = far_spot
	for i in 5:
		main._tick_army(0.1)
	var dry := 0
	for soldier in main.soldiers:
		if world.is_walkable(soldier.pos):
			dry += 1
	_check(dry == main.soldiers.size(), "soldiers catch up on dry land (%d of %d)" % [dry, main.soldiers.size()])
	main.player.pos = back_home
	for i in 5:
		main._tick_army(0.1)
	# Sound: playing effects must not break anything (headless has no audio device).
	_check(main.audio != null, "the sound system is running")
	for sound in ["chop", "mine", "wolf_howl", "discover"]:
		main.audio.play(sound, main.player.position)

	# Places to discover.
	_check(world.pois.size() >= 20, "places to discover are spread over the island (%d)" % world.pois.size())
	var first_camp: Dictionary = {}
	var shrine_data: Dictionary = {}
	for poi in world.pois:
		if poi["type"] == "camp" and first_camp.is_empty():
			first_camp = poi
		if poi["type"] == "shrine" and shrine_data.is_empty():
			shrine_data = poi
	_check(not first_camp.is_empty() and Vector2(first_camp["cell"]).distance_to(Vector2(world.spawn_cell)) < 40.0,
		"an abandoned camp waits near the start")
	var home_pos: Vector2 = main.player.pos
	main.player.pos = world.random_walkable_near(world.cell_center(first_camp["cell"]), 20.0, 40.0, main.rng)
	main._update_pois(0.0, true)
	_check(main.poi_found.has(first_camp["id"]), "walking up to a place discovers it")
	var camp_node = main.poi_nodes.get(first_camp["id"])
	_check(camp_node != null, "the place is built when you're near")
	var wood_before_loot: int = main.player.count("wood")
	main._on_poi_loot(0, "", camp_node)
	_check(main.poi_looted.has(first_camp["id"]) and main.player.count("wood") > wood_before_loot, "searching a place gives its loot")
	var loot_again: int = main.player.count("wood")
	main._on_poi_loot(0, "", camp_node)
	_check(main.player.count("wood") == loot_again, "a place can only be looted once")
	main.player.pos = world.random_walkable_near(world.cell_center(shrine_data["cell"]), 20.0, 40.0, main.rng)
	main._update_pois(0.0, true)
	main.player.sanity = 20.0
	main._use_poi(main.poi_nodes[shrine_data["id"]])
	main.hud._choose(-1)
	_check(main.player.sanity == 100.0, "resting at a shrine restores sanity")
	main.player.sanity = 20.0
	main._use_poi(main.poi_nodes[shrine_data["id"]])
	_check(main.player.sanity == 20.0, "a shrine works once a day")
	main.player.pos = home_pos

	# The explored map.
	_check(world.explored.size() >= 25, "the map reveals what you've explored (%d chunks)" % world.explored.size())
	var map_hex: String = world.export_explored()
	_check(map_hex.length() == 256, "the explored map fits in the save (%d characters)" % map_hex.length())
	_check(main._map_markers()["items"].size() > 0, "the map shows your buildings and places")

	# Crafting stations.
	var station_cells := _free_cells(world, world.cell_of(main.player.pos), 9, [tree_cell] + cells)
	_check(main._try_build("workbench", station_cells[6]), "built a workbench")
	_check(main._try_build("forge", station_cells[7]), "built a forge")
	_check(main._try_build("smokehouse", station_cells[8]), "built a smokehouse")
	var bench: Array = load("res://scripts/structure.gd").RECIPES["workbench"]
	var forge: Array = load("res://scripts/structure.gd").RECIPES["forge"]
	var smoke: Array = load("res://scripts/structure.gd").RECIPES["smokehouse"]
	_check(main._make(bench[0]) and main.player.has_axe, "the workbench makes an axe")
	_check(not main._make(bench[0]), "you can't make a second axe")
	_check(main._make(bench[1]) and main.player.has_pickaxe, "the workbench makes a pickaxe")
	main.player.add_item("ore", 2)
	var iron_before: int = main.player.count("iron")
	_check(main._make(forge[0]) and main.player.count("iron") == iron_before + 1 and main.player.count("ore") == 0, "the forge smelts iron ore into iron")
	main.player.add_item("iron", 10)
	main.player.add_item("hide", 3)
	_check(main._make(forge[2]) and main.player.armour, "the forge makes iron armour")
	_check(main._make(forge[3]) and main.player.lantern, "the forge makes a lantern")
	main.player.add_item("raw_meat", 4)
	var raw_before: int = main.player.count("raw_meat")
	var smoked_before: int = main.player.count("smoked_meat")
	_check(main._make(smoke[0]) and main.player.count("smoked_meat") == smoked_before + raw_before
		and main.player.count("raw_meat") == 0, "the smokehouse smokes all raw meat (%d)" % raw_before)
	var axe_tree := Vector2i(-1, -1)
	for r in range(1, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c2: Vector2i = world.spawn_cell + Vector2i(dx, dz)
				if axe_tree == Vector2i(-1, -1) and world.prop_type(c2) == "tree" and c2 != tree_cell and _alone(world, c2):
					axe_tree = c2
	main.player.pos = world.cell_center(axe_tree) + Vector2(0, 14)
	main.action_cooldown = 0.0
	var wood_axe: int = main.player.count("wood")
	main._interact()
	_check(main.player.count("wood") == wood_axe + 2, "with an axe, each hit gives 2 wood")
	main.player.pos = home_pos
	main.save_game()
	var saved: Dictionary = load("res://scripts/save_game.gd").read()
	_check(saved.get("props", {}).has("%d,%d" % [tree_cell.x, tree_cell.y]), "save remembers the felled tree")
	_check(main._save_fits(saved), "the save is a valid game for this island")
	_check(not main._save_fits({"version": 1, "world_seed": world.seed_value, "reset": true}), "a start-over marker is not a game")
	_check(not main.api.has_account(), "no account until the player makes one")
	var copy_main: Node = scene.instantiate()
	root.add_child(copy_main)
	await process_frame
	_check(copy_main._resumed, "a reload resumes the saved game")
	_check(copy_main.player.pos.distance_to(main.player.pos) < 1.0, "resumed at the same spot")
	_check(copy_main.player.count("wood") == main.player.count("wood"), "resumed with the same wood")
	_check(copy_main.player.has_spear, "resumed with the spear")
	_check(copy_main.world.prop_type(tree_cell) == "stump", "felled tree is still a stump after reload")
	_check(copy_main.campfires.size() == 1, "campfire is still there after reload")
	_check(copy_main.buildings.size() == main.buildings.size(), "buildings are still there after reload (%d)" % copy_main.buildings.size())
	_check(copy_main.soldiers.size() == main.soldiers.size(), "the army is still there after reload (%d)" % copy_main.soldiers.size())
	_check(not copy_main.world.is_walkable(world.cell_center(cells[0])), "walls still block after reload")
	_check(copy_main.player.has_axe and copy_main.player.armour and copy_main.player.lantern, "tools are still yours after reload")
	_check(copy_main.poi_looted.has(first_camp["id"]) and copy_main.poi_found.has(shrine_data["id"]), "found and looted places are remembered")
	_check(copy_main.world.explored.size() >= world.explored.size(), "the explored map is restored")
	copy_main.queue_free()
	await process_frame

	main._demolish(cells[0])
	_check(world.is_walkable(world.cell_center(cells[0])), "demolishing a wall frees the tile")

	# Stumps grow back into trees.
	world.regrow(main.day + 10)
	_check(world.prop_type(tree_cell) == "tree", "trees grow back")

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
	var after_death: Dictionary = load("res://scripts/save_game.gd").read()
	_check(after_death.get("player", {}).get("inventory", {"x": 1}).is_empty(), "after death you wake with empty hands")
	_check(after_death.get("bags", []).size() >= 1, "after death your belongings wait in a bag")

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


func _free_cells(world, around: Vector2i, n: int, avoid: Array = []) -> Array:
	var found := []
	for r in range(2, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := around + Vector2i(dx, dz)
				if found.size() < n and maxi(absi(dx), absi(dz)) == r and world.can_build(c) and not c in avoid:
					found.append(c)
	return found


## Three free tiles in a north-south line, searching around `start`.
func _free_line(world, start: Vector2i) -> Array:
	for r in range(0, 12):
		for dx in range(-r, r + 1):
			var top := start + Vector2i(dx, r)
			var line := [top, top + Vector2i(0, 1), top + Vector2i(0, 2)]
			var ok := true
			for c in line:
				ok = ok and world.can_build(c)
			if ok:
				return line
	return []


## True if no other prop is within two tiles of `cell`.
func _alone(world, cell: Vector2i) -> bool:
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if (dx != 0 or dz != 0) and world.prop_type(cell + Vector2i(dx, dz)) != "":
				return false
	return true
