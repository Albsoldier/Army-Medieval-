## Times the terrain for GRAPHICS_PHASE_5A_TERRAIN.md: world generation, building
## the 49 terrain chunks around the start again from scratch, and drawing the
## first frames after that (where a new shader would compile). Run it with and
## without --terrain=0:
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/terrain_timing.gd [-- --terrain=0]
extends SceneTree

var main: Node


func _initialize() -> void:
	create_timer(900.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var startup_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(5)
	if main.hud.is_modal():
		main.hud._choose(0)
	var w = main.world
	var gen := []
	for i in 3:
		var g0 := Time.get_ticks_usec()
		w.generate(w.seed_value)
		gen.append((Time.get_ticks_usec() - g0) / 1000.0)
	await _frames(10)
	# Rebuild every terrain chunk mesh around the player, several times.
	var builds := []
	for rep in 5:
		var cks: Array = w._meshes.keys()
		for ck in cks:
			w._meshes[ck].free()
		w._meshes.clear()
		var b0 := Time.get_ticks_usec()
		for ck in cks:
			w._build_chunk_mesh(ck)
		builds.append([cks.size(), (Time.get_ticks_usec() - b0) / 1000.0])
		var f0 := Time.get_ticks_usec()
		await _frames(1)
		builds[-1].append((Time.get_ticks_usec() - f0) / 1000.0)
	print("TERRAIN_TIMING ", JSON.stringify({
		"terrain": "new" if w.terrain_detail else "old",
		"startup_ms": startup_ms, "generate_ms": gen,
		"chunk_builds": builds}))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
