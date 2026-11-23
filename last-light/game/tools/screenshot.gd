## Renders screenshots of the game for CI (needs a real renderer, e.g. under xvfb):
##   godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 \
##         --script res://tools/screenshot.gd
## Images are written to $SHOT_DIR (default: user://shots).
extends SceneTree

var DAY: float = load("res://scripts/main.gd").DAY_LENGTH

var _dir := ""


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(1300.0).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	printerr("Screenshot run timed out")
	quit(1)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	await _shot("1-welcome")
	if main.hud.is_modal():
		main.hud._choose(0)
	main.hud.toggle_help()

	# Midday: walk a little so the camera settles, then look around.
	main.clock = DAY * 0.25
	await _frames(40)
	await _shot("2-day")
	main.zoom = 0.55
	await _frames(40)
	await _shot("2b-day-close")
	main.zoom = 1.0

	# Build a camp and wait for dusk.
	main.player.add_item("wood", 20)
	main.player.add_item("stone", 10)
	main._craft("spear")
	main._craft("campfire")
	main.clock = DAY * 0.62
	await _frames(20)
	await _shot("3-dusk")

	# Night, with a torch, a wolf nearby and a few traces from "other players".
	main._craft("torch")
	main.clock = DAY * 0.8
	var p: Vector2 = main.player.pos
	main._spawn_trace({"id": "a", "kind": "grave", "x": p.x + 40, "y": p.y - 10, "player_name": "Ada", "days": 3, "text": "Build the fire first."})
	main._spawn_trace({"id": "b", "kind": "note", "x": p.x - 36, "y": p.y + 20, "player_name": "Bo", "text": "Berries to the east."})
	main._spawn_trace({"id": "c", "kind": "stash", "x": p.x + 10, "y": p.y + 44, "player_name": "Cy", "items": {"wood": 3}})
	# A wolf held still at the edge of the firelight (not added to the game's
	# wolf list, so it doesn't run off before the picture is taken).
	var wolf = load("res://scripts/wolf.gd").new()
	wolf.world = main.world
	wolf.pos = p + Vector2(-34, 30)
	wolf.facing = (p - wolf.pos).normalized()
	main.entities.add_child(wolf)
	await _frames(2)
	wolf._model.rotation.y = atan2(wolf.facing.x, wolf.facing.y)
	wolf._body.play("idle")
	await _frames(30)
	await _shot("4-night")

	main.zoom = 0.6
	await _frames(30)
	await _shot("5-night-close")

	# Daylight close-up of the wolf, for checking its size and look.
	main.clock = DAY * 0.3
	main._update_lighting()
	await _frames(20)
	await _shot("6-wolf-day")
	# A walled base with a gate, torch posts, tent, chest and barracks, and an army.
	wolf.queue_free()
	var w = main.world
	main.player.add_item("wood", 600)
	main.player.add_item("stone", 300)
	main.player.add_item("berries", 300)
	var c: Vector2i = w.cell_of(main.player.pos)
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			if maxi(absi(dx), absi(dz)) != 5:
				continue
			var kind := "wood_wall"
			if absi(dx) == 5 and absi(dz) == 5:
				kind = "torch_post"
			elif dz == 5 and dx == 0:
				kind = "gate"
			elif dz == -5:
				kind = "stone_wall"
			main._try_build(kind, c + Vector2i(dx, dz))
	main._try_build("barracks", c + Vector2i(-3, -3))
	main._try_build("barracks", c + Vector2i(3, -3))
	main._try_build("tent", c + Vector2i(-3, 2))
	main._try_build("chest", c + Vector2i(3, 2))
	main._try_build("forge", c + Vector2i(0, -3))
	main._try_build("workbench", c + Vector2i(-1, 3))
	main._try_build("smokehouse", c + Vector2i(1, 3))
	main._recruit(20)
	main.clock = DAY * 0.3
	main.zoom = 1.6
	for i in 90:
		main._tick_army(0.1)
	await _frames(40)
	await _shot("7-base-day")
	# Tools: the axe in hand, the hotbar and the inventory screen.
	main.player.has_axe = true
	main.player.has_pickaxe = true
	main.player.armour = true
	main.player.lantern = true
	main.player.add_item("cooked_meat", 3)
	main._on_hotbar_slot(2)
	main.player.facing = Vector2(1, 0.4).normalized()  # side on, so the tool shows
	main.zoom = 0.6
	await _frames(30)
	await _shot("7b-axe-in-hand")
	main._on_hotbar_slot(3)
	await _frames(10)
	await _shot("7c-pickaxe-in-hand")
	main._open_inventory()
	await _frames(10)
	await _shot("7d-inventory")
	main.hud.close_inventory()
	main.player.pos = w.cell_center(c + Vector2i(-1, 3)) + Vector2(0, -16)
	main._ask_demolish()
	await _frames(10)
	await _shot("7e-take-down")
	main.hud._choose(1)
	# Gear by material: the forge, then a survivor in gilded armour with a gilded sword.
	main.player.add_item("steel", 20)
	main.player.add_item("gold", 10)
	main.player.add_item("iron", 10)
	main.player.add_item("hide", 10)
	main._make_gear("spear", 3)
	main._make_gear("armour", 2)
	main._open_station("forge")
	await _frames(10)
	await _shot("7h-forge-gear")
	main.hud.close_inventory()
	main._make_gear("armour", 3)
	main._make_gear("sword", 2)
	main.player.facing = Vector2.DOWN
	main.cam_yaw = 0.0
	main.zoom = 0.55
	await _frames(20)
	await _shot("7i-gilded-gear")
	# First person: the base by day with the axe in hand, then at night with a torch.
	main.player.pos = w.cell_center(c + Vector2i(0, 2))
	main._on_hotbar_slot(2)
	main.set_first_person(true, false)
	main.cam_yaw = 0.0  # looking north, at the legion and the stone wall
	main.fp_pitch = -0.08
	await _frames(30)
	await _shot("7f-first-person-day")
	main._on_hotbar_slot(1)
	main.player.torch_time = 120.0
	main.clock = DAY * 0.8
	await _frames(30)
	await _shot("7g-first-person-night")
	main.clock = DAY * 0.3
	main.set_first_person(false, false)
	main.clock = DAY * 0.8
	main.zoom = 1.3
	await _frames(30)
	await _shot("8-base-night")

	# The legion: all four kinds of soldier, a selection, and a shield wall.
	var extra := 0
	for off in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(2, -1), Vector2i(-2, -1), Vector2i(3, -1), Vector2i(-3, -1),
			Vector2i(2, 2), Vector2i(-2, 2), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(4, 1), Vector2i(-4, 1)]:
		if extra < 2 and main._try_build("barracks", c + off):
			extra += 1
	main.player.add_item("iron", 20)
	main.player.add_item("gold", 4)
	main.player.add_item("hide", 20)
	main._recruit(6, "archer")
	main._recruit(4, "cavalry")
	main._recruit(2, "centurion")
	main.soldiers[0].kills = 9  # an elite, to show the name label
	main.player.pos = w.cell_center(c + Vector2i(0, 1))
	main.player.facing = Vector2.DOWN
	main.cam_yaw = 0.0
	main.clock = DAY * 0.32
	main.zoom = 0.85
	for i in 120:
		main._tick_army(0.1)
	await _frames(30)
	await _shot("14-legion-units")
	# Close up, in open ground: a horseman, an archer and a centurion.
	var field: Vector2 = _open_meadow(w, w.cell_of(main.player.pos))
	if field != Vector2.INF:
		for so in main.soldiers:  # the rest of the army stays at the fort
			so.mode = "guard"
			so.guard_point = w.cell_center(c)
		var trio := []
		var spots := [Vector2(-22, 0), Vector2(0, -4), Vector2(22, 0)]
		var kinds := ["archer", "cavalry", "centurion"]
		for k in 3:
			var so = main._spawn_soldier(field + spots[k], -1.0, "hold", field + spots[k], kinds[k])
			so.order_facing = Vector2.DOWN
			so.group_size = 1
			so.slot = 0
			trio.append(so)
		main.player.pos = field + Vector2(0, 45)
		main.player.facing = Vector2.UP
		main.cam_yaw = 0.0
		main.zoom = 0.55
		w.update_view(main.player.pos, true)
		await _frames(40)
		await _shot("14b-unit-types")
		main.cam_yaw = 1.2
		await _frames(20)
		await _shot("14c-cavalry-side")
		main.cam_yaw = 0.0
		for so in trio:
			main.soldiers.erase(so)
			so.queue_free()
		main._reassign_slots()
		for so in main.soldiers:
			so.mode = "follow"
		main._reassign_slots()
	main.player.pos = w.cell_center(c + Vector2i(0, 1))
	main.player.facing = Vector2.DOWN
	main.zoom = 0.85
	await _frames(10)
	main._set_selection(main.soldiers.slice(0, 14))
	await _frames(10)
	await _shot("15-selected")
	main._set_selection([])
	main._cycle_formation()  # shield wall
	for i in 60:
		main._tick_army(0.1)
	await _frames(20)
	await _shot("16-shield-wall")
	# A raider camp out on the island, with its chief and guards.
	var rc: Dictionary = main.camps[0]
	var base_pos: Vector2 = main.player.pos
	for so in main.soldiers:  # the legion stays home for this one
		so.mode = "guard"
		so.guard_point = base_pos
	main.player.pos = (rc["pos"] as Vector2) + Vector2(0, 150)
	main.player.facing = Vector2.UP
	w.update_view(main.player.pos, true)
	main.zoom = 1.9  # high enough to see over the trees around the meadow
	await _frames(40)
	await _shot("16b-raider-camp")
	# Wild horses in their meadow, then riding one.
	var herd: Dictionary = main.herds[0]
	main.player.pos = (herd["pos"] as Vector2) + Vector2(0, 90)
	main.player.facing = Vector2.UP
	w.update_view(main.player.pos, true)
	main._tick_horses(0.1)
	main.zoom = 1.5
	await _frames(30)
	await _shot("16c-wild-horses")
	if not main._wild_horses.is_empty():
		var mare = main._wild_horses.values()[0]
		main.player.add_item("berries", 10)
		for k in 3:
			main._use_horse(mare)
		main._mount(mare)
		main.player.facing = Vector2(1, 0.3).normalized()
		main.cam_yaw = 0.6
		main.zoom = 0.6
		await _frames(25)
		await _shot("16d-riding")
		main._dismount()
		main.cam_yaw = 0.0
	for r in main.wolves.duplicate():
		if r.is_raider():
			main.wolves.erase(r)
			r.queue_free()
	main._camp_guards.clear()
	main.player.pos = base_pos
	w.update_view(base_pos, true)
	for so in main.soldiers:
		so.mode = "follow"
	main.cam_yaw = 0.0
	main._cycle_formation()
	main._cycle_formation()  # back to a line

	# Winter and autumn.
	main.day = 10
	w.set_season("winter")
	main._update_weather()
	main.zoom = 1.4
	await _frames(40)
	await _shot("17-winter-base")
	main.day = 7
	w.set_season("autumn")
	main._update_weather()
	await _frames(40)
	await _shot("18-autumn-base")
	main.day = 1
	w.set_season("spring")
	main._update_weather()

	# A galley at sea off an islet, then ashore at the treasure hoard.
	if not w.islets.is_empty():
		var isle: Dictionary = w.islets[0]
		var ic: Vector2 = w.cell_center(isle["cell"])
		var toward := (Vector2(1024, 1024) * 8.0 - ic).normalized()  # from the islet toward the main island
		var sea := ic + toward * (float(isle["r"]) * 1.45 + 6.0) * 16.0
		var galley = main._spawn_boat("galley", sea, -toward)
		main._board(galley)
		main.player.pos = sea
		main.player.facing = -toward
		main.cam_yaw = atan2(toward.x, toward.y)
		main.zoom = 1.1
		w.update_view(sea, true)
		await _frames(40)
		await _shot("19-galley-at-sea")
		main._leave_boat()
		for poi in w.pois:
			if poi["type"] == "hoard" and poi["id"] == "hoard-0":
				var stand: Vector2 = w.random_walkable_near(w.cell_center(poi["cell"]), 30.0, 50.0, main.rng)
				if stand != Vector2.INF:
					main.player.pos = stand
					main.player.facing = (w.cell_center(poi["cell"]) - stand).normalized()
					main.cam_yaw = atan2(-main.player.facing.x, -main.player.facing.y)
					main.zoom = 0.7
					w.update_view(stand, true)
					main._update_pois(0.0, true)
					await _frames(40)
					await _shot("20-islet-hoard")
		main.player.pos = w.cell_center(c + Vector2i(0, 1))
		w.update_view(main.player.pos, true)

	# Places to discover: a lighthouse at night and a shipwreck by day, then the map.
	for kind in ["lighthouse", "shipwreck"]:
		for poi in w.pois:
			if poi["type"] != kind:
				continue
			var spot: Vector2 = w.random_walkable_near(w.cell_center(poi["cell"]), 70.0, 110.0, main.rng)
			if spot == Vector2.INF:
				continue
			main.player.pos = spot
			main.player.facing = (w.cell_center(poi["cell"]) - spot).normalized()
			w.update_view(spot, true)
			main._update_pois(0.0, true)
			main.clock = DAY * (0.8 if kind == "lighthouse" else 0.3)
			main.zoom = 1.7
			await _frames(40)
			await _shot("9-lighthouse-night" if kind == "lighthouse" else "10-shipwreck-day")
			break
	main.hud.toggle_map()
	await _frames(10)
	await _shot("11-island-map")
	main.hud.toggle_map()

	# A wide, turned view of the landscape.
	main.clock = DAY * 0.22
	main.zoom = 3.0
	main.cam_yaw = 0.7
	await _frames(45)
	await _shot("12-landscape-wide")
	main.zoom = 1.0
	main.cam_yaw = -0.4
	await _frames(45)
	await _shot("13-landscape-close")

	# Clean shots for a portfolio: no on-screen panels, framed like a strategy game.
	main.hud.visible = false
	var base_cell: Vector2i = c
	var outside: Vector2 = w.cell_center(base_cell + Vector2i(0, 9))
	if not w.is_walkable(outside):
		outside = w.random_walkable_near(w.cell_center(base_cell + Vector2i(0, 9)), 4.0, 40.0, main.rng)
	main.player.pos = outside
	main.player.facing = Vector2.UP
	w.update_view(outside, true)
	main._update_pois(0.0, true)
	for i in 120:
		main._tick_army(0.1)
	main.clock = DAY * 0.6  # low golden sun, just before dusk
	main.zoom = 1.45
	main.cam_yaw = 0.45
	await _frames(45)
	await _shot("p1-legion-golden-hour")
	main.clock = DAY * 0.82
	main.zoom = 2.1
	main.cam_yaw = -0.35
	await _frames(45)
	await _shot("p2-fort-at-night")

	var meadow: Vector2 = w.random_walkable_near(w.cell_center(base_cell + Vector2i(18, -14)), 0.0, 60.0, main.rng)
	if meadow != Vector2.INF:
		main.player.pos = meadow
		main.player.facing = Vector2(0.6, 0.8).normalized()
		w.update_view(meadow, true)
		for i in 120:
			main._tick_army(0.1)
		main.army_mode = "guard"
		for s in main.soldiers:
			s.mode = "guard"
			s.guard_point = w.cell_center(base_cell)
		main.clock = DAY * 0.32
		main.zoom = 0.8
		main.cam_yaw = -0.7
		await _frames(45)
		await _shot("p3-meadow")

	for poi in w.pois:
		if poi["type"] != "lighthouse":
			continue
		var spot: Vector2 = w.random_walkable_near(w.cell_center(poi["cell"]), 90.0, 130.0, main.rng)
		if spot == Vector2.INF:
			continue
		main.player.pos = spot
		main.player.facing = (w.cell_center(poi["cell"]) - spot).normalized()
		w.update_view(spot, true)
		main._update_pois(0.0, true)
		main.clock = DAY * 0.64
		main.zoom = 1.9
		main.cam_yaw = atan2(-main.player.facing.x, -main.player.facing.y)
		await _frames(45)
		await _shot("p4-lighthouse-dusk")
		break
	main.hud.visible = true

	print("Screenshots written to ", _dir)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _dir.path_join(label + ".png")
	var err := img.save_png(path)
	print("shot ", label, " -> ", path, " (", error_string(err), ")")


## The centre of a treeless patch of land near `around`, or INF.
func _open_meadow(w, around: Vector2i) -> Vector2:
	for r in range(12, 160, 3):
		for dz in range(-r, r + 1, 3):
			for dx in range(-r, r + 1, 3):
				if maxi(absi(dx), absi(dz)) < r - 2:
					continue
				var cell: Vector2i = around + Vector2i(dx, dz)
				var clear := true
				for oz in range(-9, 10):
					for ox in range(-6, 7):
						var c2: Vector2i = cell + Vector2i(ox, oz)
						if not w.is_land(c2) or w.structures.has(c2) or w.terrain_at(c2) == 5:
							clear = false
							break
					if not clear:
						break
				if clear:
					# Clear the trees and rocks here, for the picture only.
					for oz in range(-9, 10):
						for ox in range(-6, 7):
							if w.prop_type(cell + Vector2i(ox, oz)) != "":
								w.prop_changes[cell + Vector2i(ox, oz)] = {"type": "cleared", "hp": 0, "regrow_day": 0}
					w._props_dirty = true
					return w.cell_center(cell) + Vector2(0, -48)  # the units stand north of centre, the camera to the south
	return Vector2.INF
