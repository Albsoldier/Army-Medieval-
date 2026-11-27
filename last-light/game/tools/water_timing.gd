## Times the water shaders' first use for GRAPHICS_PHASE_5B1_WATER_SURFACE.md:
## for the original and the upgraded water shader in turn, a fresh copy of the
## shader (so nothing is cached) is put on a sheet of water in front of the
## camera, and the frame that first draws it is timed against the frames
## around it. That frame's extra time is the shader's compile and first-render cost.
##   xvfb-run godot --path last-light/game --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/water_timing.gd
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")


func _initialize() -> void:
	create_timer(900.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	if main.hud.is_modal():
		main.hud._choose(0)
	var bench = PerfBench.new()
	bench.main = main
	bench._go(bench._find_water_spots()["shore"])
	await _frames(30)
	var out := {}
	for rep in 3:
		for path in ["res://shaders/water.gdshader", "res://shaders/water_detail.gdshader"]:
			var sh := Shader.new()
			sh.code = (load(path) as Shader).code + "\n// fresh copy %d %d\n" % [rep, Time.get_ticks_usec()]
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("ripples", load("res://textures/water/ripples_normal.png"))
			var plane := PlaneMesh.new()
			plane.size = Vector2(40, 40)
			var mi := MeshInstance3D.new()
			mi.mesh = plane
			mi.material_override = mat
			mi.position = main.world.to_3d(main.player.pos) + Vector3(0, 0.3, 0)
			var before := await _frame_ms(10)
			root.add_child(mi)
			var t0 := Time.get_ticks_usec()
			await process_frame
			var first := (Time.get_ticks_usec() - t0) / 1000.0
			var after := await _frame_ms(10)
			mi.queue_free()
			await _frames(3)
			var key := path.get_file().get_basename()
			if not out.has(key):
				out[key] = []
			out[key].append({"first_frame_ms": first, "frame_ms_before": before, "frame_ms_after": after})
	print("WATER_TIMING ", JSON.stringify(out))
	quit(0)


func _frame_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	await _frames(n)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _frames(n: int) -> void:
	for i in n:
		await process_frame
