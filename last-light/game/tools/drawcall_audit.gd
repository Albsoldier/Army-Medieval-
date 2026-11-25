## Counts what each building and character costs to draw: mesh nodes, surfaces
## (each is a draw per pass), distinct materials and lights. For
## GRAPHICS_DRAWCALL_AUDIT.md. Runs headless:
##   godot --headless --path last-light/game --script res://tools/drawcall_audit.gd
## Prints AUDIT {json}.
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
	bench._go(spots["village"])
	bench._build_village(spots["village"])
	var out := {"buildings": {}, "characters": {}, "village_total": {}}
	# Buildings, by type.
	for b in main.buildings.values():
		var row: Dictionary = out["buildings"].get(b.kind, {"count": 0, "meshes": 0, "surfaces": 0, "materials": {}, "lights": 0})
		row["count"] += 1
		var c := _count(b)
		row["meshes"] += c["meshes"]
		row["surfaces"] += c["surfaces"]
		row["lights"] += c["lights"]
		for m in c["materials"]:
			row["materials"][m] = true
		out["buildings"][b.kind] = row
	for kind in out["buildings"]:
		var row: Dictionary = out["buildings"][kind]
		row["materials"] = row["materials"].size()
		row["meshes_each"] = row["meshes"] / row["count"]
		row["surfaces_each"] = row["surfaces"] / row["count"]
	# Characters: one of each soldier kind, a settler, a raider, a wolf, the player.
	for kind in ["legionary", "archer", "cavalry", "centurion"]:
		var s = main._spawn_soldier(main.player.pos + Vector2(20, 0), -1.0, "follow", main.player.pos, kind)
		await process_frame
		out["characters"]["soldier_" + kind] = _count(s)
	if not main.settlers.is_empty():
		out["characters"]["settler"] = _count(main.settlers[0])
	var r = main._spawn_raider("raider", main.player.pos + Vector2(200, 0))
	await process_frame
	out["characters"]["raider"] = _count(r)
	var wolf = load("res://scripts/wolf.gd").new()
	wolf.world = main.world
	wolf.pos = main.player.pos + Vector2(220, 0)
	main.entities.add_child(wolf)
	await process_frame
	out["characters"]["wolf"] = _count(wolf)
	out["characters"]["player"] = _count(main.player)
	for k in out["characters"]:
		out["characters"][k]["materials"] = out["characters"][k]["materials"].size()
	# The character model itself: one skin for all its meshes?
	var model: Node = load("res://models/adventurer.glb").instantiate()
	var skins := {}
	var mesh_info := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		skins[str(m.skin.get_instance_id()) if m.skin else "none"] = true
		var mats := []
		for sidx in m.mesh.get_surface_count():
			var mat := m.get_active_material(sidx)
			mats.append(mat.resource_name if mat else "")
		mesh_info.append({"name": str(m.name), "surfaces": m.mesh.get_surface_count(), "materials": mats,
			"skin_binds": m.skin.get_bind_count() if m.skin else 0, "skeleton": str(m.skeleton)})
	out["adventurer_model"] = {"meshes": mesh_info, "distinct_skins": skins.size()}
	# Everything in the village scene.
	var all := _count(main)
	all["materials"] = all["materials"].size()
	out["village_total"] = all
	print("AUDIT ", JSON.stringify(out))
	quit()


## Mesh nodes, surfaces, distinct materials and lights under `node`.
func _count(node: Node) -> Dictionary:
	var meshes := 0
	var surfaces := 0
	var lights := 0
	var materials := {}
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Light3D:
			lights += 1
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree():
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			meshes += 1
			surfaces += mi.mesh.get_surface_count()
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat:
					materials[mat.get_instance_id()] = true
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
			meshes += 1
			surfaces += (n as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
	return {"meshes": meshes, "surfaces": surfaces, "materials": materials, "lights": lights}
