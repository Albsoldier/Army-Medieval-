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
	var wolf = load("res://scripts/wolf.gd").new()
	wolf.world = main.world
	wolf.pos = main.world.random_walkable_near(p, 60.0, 90.0, main.rng)
	if wolf.pos != Vector2.INF:
		main.entities.add_child(wolf)
		main.wolves.append(wolf)
	await _frames(30)
	await _shot("4-night")

	main.zoom = 0.6
	if wolf.pos != Vector2.INF:
		wolf.pos = p + Vector2(30, 18)
	await _frames(30)
	await _shot("5-night-close")
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
