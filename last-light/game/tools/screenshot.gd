## Renders screenshots of the game for CI (needs a real renderer, e.g. under xvfb):
##   godot --path last-light/game --rendering-driver opengl3 --resolution 1280x720 \
##         --script res://tools/screenshot.gd
## Images are written to $SHOT_DIR (default: user://shots).
extends SceneTree

var _dir := ""


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	create_timer(240.0).timeout.connect(_on_watchdog)
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
	main.clock = 240.0 * 0.25
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
	main.clock = 240.0 * 0.62
	await _frames(20)
	await _shot("3-dusk")

	# Night, with a torch, a wolf nearby and a few traces from "other players".
	main._craft("torch")
	main.clock = 240.0 * 0.8
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
	main.clock = 240.0 * 0.3
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
	main._recruit(20)
	main.clock = 240.0 * 0.3
	main.zoom = 1.6
	for i in 90:
		main._tick_army(0.1)
	await _frames(40)
	await _shot("7-base-day")
	main.clock = 240.0 * 0.8
	main.zoom = 1.3
	await _frames(30)
	await _shot("8-base-night")

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
