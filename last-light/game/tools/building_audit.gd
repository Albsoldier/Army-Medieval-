## What the prototype buildings (cottage, stone wall, archer tower) cost to
## draw, before and after phase 4B (GRAPHICS_BUILDING_PROTOTYPE.md): mesh
## nodes, surfaces, triangles, distinct materials and lights for one of each,
## and the triangles of each LOD level Godot generated. Runs headless:
##   godot --headless --path last-light/game --script res://tools/building_audit.gd [-- --buildings=0]
## Prints BUILDING_AUDIT {json}.
extends SceneTree

const PerfBench = preload("res://scripts/perf_bench.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	if main.hud.is_modal():
		main.hud._choose(0)
	main.bench_mode = true
	var bench = PerfBench.new()
	bench.main = main
	main.rng.seed = 20261124
	var spots: Dictionary = bench._find_spots()
	bench._go(spots["empty"])
	var w = main.world
	var out := {}
	var c0: Vector2i = w.cell_of(spots["empty"])
	var n := 0
	for kind in ["house", "stone_wall", "archer_tower"]:
		var cell := c0
		for r in range(2, 20):
			cell = c0 + Vector2i(r, n * 3)
			if w.can_build(cell):
				break
		n += 1
		var b = main._add_structure(kind, cell)
		await process_frame
		var row := {"meshes": 0, "surfaces": 0, "triangles": 0, "materials": {}, "lights": 0, "lod_triangles": []}
		for node in b.find_children("*", "", true, false):
			if node is Light3D:
				row["lights"] += 1
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			row["meshes"] += 1
			for s in mi.mesh.get_surface_count():
				row["surfaces"] += 1
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				row["triangles"] += ((idx as PackedInt32Array).size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(s)
				row["materials"][str(mat.get_instance_id()) if mat else "none"] = true
				var sd: Variant = mi.mesh.get("_surfaces")
				if sd is Array and (sd[s] as Dictionary).has("lods"):
					var lods: Array = sd[s]["lods"]
					for k in range(0, lods.size(), 2):
						row["lod_triangles"].append((lods[k + 1] as PackedByteArray).size() / (4 if int(sd[s]["vertex_count"]) > 65535 else 2) / 3)
		row["materials"] = row["materials"].size()
		out[kind] = row
	print("BUILDING_AUDIT ", JSON.stringify(out))
	quit()
