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
	_check(main.sun_shadow_preset == "C" and main.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		and int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")) == 2048,
		"the sun casts shadows with 2 cascades on a 2048 atlas")
	# Terrain and grass are built faster, but exactly as before.
	var tw0 = main.world
	var t_worst := 0.0
	var t_colour_steps := 0
	var t_checked := 0
	for tck in [tw0._view_chunk, tw0._view_chunk + Vector2i(1, 0), tw0._view_chunk + Vector2i(-2, 1), tw0._view_chunk + Vector2i(2, -2)]:
		if not tw0._meshes.has(tck) or (tw0._meshes[tck] as MeshInstance3D).mesh == null:
			continue
		var ref: Dictionary = _old_terrain(tw0, tck)
		var arrays: Array = tw0._terrain_arrays(tck, tw0._chunk_corners(tck))  # before the GPU packs it
		var corners: PackedFloat32Array = tw0._chunk_corners(tck)
		var cv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cc: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in corners.size():
			t_worst = maxf(t_worst, absf(corners[i] - float(ref["corners"][i])))
			t_worst = maxf(t_worst, (cv[i] - ref["verts"][i]).length())
			t_worst = maxf(t_worst, (cn[i] - ref["normals"][i]).length())
			if cc[i] != ref["colors"][i]:
				t_colour_steps += 1
		t_checked += 1
	_check(t_checked >= 2 and t_worst == 0.0 and t_colour_steps == 0,
		"terrain heights, normals and blends are exactly the same as before (%d chunks, difference %s, blends differing %d)" % [t_checked, str(t_worst), t_colour_steps])
	for gseason in ["spring", "autumn"]:
		tw0.set_season(gseason)
		tw0.update_view(main.player.pos, true)
		var got := _grass_records(tw0._grass.multimesh)
		var want := _old_grass(tw0)
		_check(got.size() > 1000 and got == want, "grass clumps are the same as before in %s (%d of %d)" % [gseason, got.size(), want.size()])
	tw0.set_season("winter")
	tw0.update_view(main.player.pos, true)
	_check(tw0._grass.multimesh.instance_count == 0, "no grass under the snow")
	tw0.set_season("spring")
	tw0.update_view(main.player.pos, true)
	# Environment prototype (phase 4A): pines, oaks, rocks and bushes are the
	# textured MegaKit models, two surfaces each like the merged props they
	# replace, sharing their materials and textures.
	var nm_ok := true
	var nm_mats := {}
	for nkind in tw0.NATURE_MODELS:
		var nmesh: Mesh = tw0._merged_props[nkind]
		nm_ok = nm_ok and nmesh.get_surface_count() == (1 if nkind == "rock" else 2)
		for ns in nmesh.get_surface_count():
			var nmat := nmesh.surface_get_material(ns) as ShaderMaterial
			nm_ok = nm_ok and nmat != null and nmat.get_shader_parameter("albedo") is Texture2D
			nm_mats[nmat] = true
	_check(nm_ok and nm_mats.size() == 5 and tw0._merged_props["bush"] == tw0._merged_props["bush_empty"]
		and tw0._merged_props["tree_pine"].surface_get_material(0) == tw0._merged_props["tree_oak"].surface_get_material(0),
		"trees, rocks and bushes use the textured nature models (%d shared materials)" % nm_mats.size())
	var nm_nodes := {}
	for nck in tw0._prop_chunks:
		for nchild in (tw0._prop_chunks[nck]["node"] as Node3D).get_children():
			nm_nodes[String(nchild.name)] = nchild
	_check(nm_nodes.has("tree_pine") and nm_nodes.has("tree_pine_far") and nm_nodes.has("tree_pine_shadow")
		and (nm_nodes["tree_pine"] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and (nm_nodes["tree_pine_shadow"] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		and (nm_nodes["tree_pine"] as GeometryInstance3D).visibility_range_end == (nm_nodes["tree_pine_far"] as GeometryInstance3D).visibility_range_begin
		and (nm_nodes["tree_pine_far"] as MultiMeshInstance3D).multimesh.buffer == (nm_nodes["tree_pine"] as MultiMeshInstance3D).multimesh.buffer,
		"near trees switch to their far version at %d m, and the old shapes cast their shadows" % int(tw0.NATURE_NEAR))
	var nm_cell := Vector2i(3, 4)
	_check(tw0._prop_instance_params("bush_empty", nm_cell)[1].a == 1.0 and tw0._prop_instance_params("bush", nm_cell)[1].a == 0.0,
		"picked bushes hide their flowers, unpicked ones show them")
	# Building on grass clears it there; taking the building down brings it back.
	var gcell := Vector2i(-1, -1)
	for gc in _free_cells(tw0, tw0.cell_of(main.player.pos), 12, []):
		if tw0.terrain_at(gc) == tw0.GRASS and gc != tw0.cell_of(main.player.pos):
			gcell = gc
			break
	if gcell.x >= 0:
		var before_g: int = tw0._grass.multimesh.instance_count
		main.player.add_item("wood", 4)
		main._try_build("wood_wall", gcell)
		tw0.update_view(main.player.pos, true)
		var with_wall: int = tw0._grass.multimesh.instance_count
		main._remove_structure(gcell)
		tw0.update_view(main.player.pos, true)
		_check(with_wall == before_g - 3 and tw0._grass.multimesh.instance_count == before_g and _grass_records(tw0._grass.multimesh) == _old_grass(tw0),
			"building on grass clears it, and taking the building down brings it back (%d, %d, %d)" % [before_g, with_wall, tw0._grass.multimesh.instance_count])
	# Fewer draw calls: buildings, kit and characters are merged meshes.
	var StructureScript = load("res://scripts/structure.gd")
	var ghost_wall = StructureScript.new()
	ghost_wall.setup(main.world, "wood_wall", main.world.cell_of(main.player.pos) + Vector2i(3, 3))
	main.add_child(ghost_wall)
	var wall_meshes: Array = ghost_wall.find_children("*", "MeshInstance3D", true, false)
	_check(wall_meshes.size() == 1 and (wall_meshes[0] as MeshInstance3D).mesh.get_surface_count() == 1,
		"a wooden wall is one mesh, one surface (was 9)")
	ghost_wall.make_ghost(true)
	_check((wall_meshes[0] as MeshInstance3D).material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"the build preview still shows a merged building as a see-through ghost")
	ghost_wall.queue_free()
	var test_field = StructureScript.new()
	test_field.setup(main.world, "field", main.world.cell_of(main.player.pos) + Vector2i(-3, 3))
	main.add_child(test_field)
	test_field.set_growth(0.0)
	test_field.set_growth(1.0)
	_check(test_field.is_ripe() and test_field._crop_field.multimesh.instance_count == 20 and test_field._stage == 20,
		"a field's wheat is one MultiMesh of 20 stalks that still grows and ripens")
	test_field.make_ghost(false)
	test_field.queue_free()
	var test_soldier = main._spawn_soldier(main.player.pos + Vector2(30, 0), -1.0, "follow", main.player.pos, "legionary")
	await process_frame
	var dc_body = test_soldier._body
	var body_mesh: MeshInstance3D = dc_body._meshes[0]
	_check(dc_body.merged and dc_body._meshes.size() == 1 and body_mesh.mesh.get_surface_count() == 1 and body_mesh.skin != null
		and body_mesh.skin.get_bind_count() == 5 * 62, "a soldier's body is one skinned surface, every part keeping its bones (was 15)")
	_check(main.player._body.merged, "the player is one skinned surface too")
	# The ranger-only checks below are skipped with --player=0 (the old adventurer, for comparing).
	if main.player.use_ranger:
		# Character prototype (phase 4C): the player is the ranger model, still one
		# skinned surface with one material, with every animation and equipment bone.
		var pc_body = main.player._body
		var pc_mesh: MeshInstance3D = pc_body._meshes[0]
		var pc_actions_ok := true
		for pc_action in ["idle", "walk", "run", "punch", "slash", "death"]:
			pc_actions_ok = pc_actions_ok and pc_body.has_action(pc_action)
		_check(main.player.use_ranger and pc_body.skeleton.find_bone("neck_01") >= 0, "the player is the ranger model (its humanoid rig)")
		_check(pc_body._meshes.size() == 1 and pc_mesh.mesh.get_surface_count() == 1 and pc_mesh.skin != null and pc_actions_ok
			and main.player._right_hand != null and main.player._left_hand != null and main.player._torso != null and main.player._neck != null,
			"the ranger is one skinned surface with one material, every animation, and hands, chest and neck for equipment")
		main.player.set_first_person(true)
		var pc_fp: bool = pc_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		main.player.set_first_person(false)
		_check(pc_fp and pc_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "in first person the ranger only casts a shadow")
		# Refinement (GRAPHICS_PLAYER_REFINEMENT.md): every part (clothing, skin,
		# hood, hair, armour, backpack) is in that one surface, labelled in UV2, and
		# one shared material draws them, chosen per character by instance uniforms.
		var pc_mat := pc_mesh.mesh.surface_get_material(0) as ShaderMaterial
		var pc_parts := {}
		for pc_uv2 in pc_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]:
			pc_parts[int(pc_uv2.x)] = true
		_check(pc_mat != null and pc_mat.shader.resource_path.ends_with("character_atlas.gdshader") and pc_parts.size() == 6,
			"the ranger's parts (clothing, skin, hood, hair, armour, backpack) share one surface and one material (%d parts)" % pc_parts.size())
		var pc_ap = main.player.Appearance
		var pc_look: Dictionary = pc_ap.from_options({"hood": "down", "skin": "dark", "outfit": "earth", "backpack": "0"})
		var pc_bad: Dictionary = pc_ap.from_options({"skin": "green", "outfit": "clown"})
		_check(not pc_look["hood"] and pc_look["skin"] == "dark" and pc_look["outfit"] == "earth" and not pc_look["backpack"]
			and pc_bad["skin"] == "medium" and pc_bad["outfit"] == "ranger" and pc_bad["hood"] and pc_bad["backpack"],
			"appearance options: hood, skin, outfit and backpack, unknown values ignored")
		_check(pc_ap.skin_gain("medium").is_equal_approx(Vector3.ONE) and pc_ap.skin_gain("deep").x < 1.0 and pc_ap.skin_gain("light").x > 1.0,
			"skin tones scale the skin texture; medium is the texture as made")
		pc_ap.apply(pc_mesh, pc_look)
		_check(float(pc_mesh.get_instance_shader_parameter("hood_up")) == 0.0 and float(pc_mesh.get_instance_shader_parameter("outfit")) == 1.0
			and float(pc_mesh.get_instance_shader_parameter("backpack_on")) == 0.0, "the look is set on the player's mesh")
		# Hood (GRAPHICS_PLAYER_HOOD.md): hood up has its hood and cropped hair;
		# hood down has the lowered hood (the same hood, folded) and its hair.
		var hd_count := {}
		var hd_uv2: PackedVector2Array = pc_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		var hd_idx: PackedInt32Array = pc_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		for t in range(0, hd_idx.size(), 3):
			var hd_part := int(hd_uv2[hd_idx[t]].x)
			hd_count[hd_part] = hd_count.get(hd_part, 0) + 1
		_check(int(hd_count.get(2, 0)) > 2000 and int(hd_count.get(3, 0)) > 2500 and not main.dev_look,
			"hood up and hood down are both in the one surface (%d and %d triangles); the F8 hood switch is off unless ?devlook=1" % [hd_count.get(2, 0), hd_count.get(3, 0)])
		# Outfits (GRAPHICS_PLAYER_OUTFITS.md): the kit's two colourways of the same
		# clothes, one texture each for the clothing only, chosen per character.
		var of_mat := pc_mesh.mesh.surface_get_material(0) as ShaderMaterial
		var of_alt := of_mat.get_shader_parameter("outfit_tex") as Texture2D
		var of_main := of_mat.get_shader_parameter("albedo_tex") as Texture2D
		_check(of_alt != null and of_alt.get_width() * 2 == of_main.get_width() and of_alt.get_height() == of_main.get_height()
			and pc_ap.OUTFIT_NAMES.size() == pc_ap.OUTFITS.size()
			and pc_ap.from_options({"outfit": "beige"})["outfit"] == "earth" and pc_ap.from_options({"outfit": "green"})["outfit"] == "ranger",
			"the beige and brown outfit is one texture for the clothing half of the atlas, chosen by name (earth or beige)")
		pc_ap.apply(pc_mesh, main.player.appearance)
		_check(float(pc_mesh.get_instance_shader_parameter("outfit")) == 0.0, "by default the ranger wears the original green outfit")
		_check(float(pc_mesh.get_instance_shader_parameter("hood_up")) == 1.0 and float(pc_mesh.get_instance_shader_parameter("backpack_on")) == 1.0,
			"by default the hood is up and the backpack on")
	# Skinning: every bind of the merged skin must still point at a bone of the skeleton.
	var dc_skin: Skin = body_mesh.skin
	var dc_bound := 0
	for b in dc_skin.get_bind_count():
		var bname := dc_skin.get_bind_name(b)
		if (bname != "" and dc_body.skeleton.find_bone(bname) >= 0) or (bname == "" and dc_skin.get_bind_bone(b) < dc_body.skeleton.get_bone_count()):
			dc_bound += 1
	_check(dc_bound == dc_skin.get_bind_count() and body_mesh.get_node_or_null(body_mesh.skeleton) == dc_body.skeleton,
		"the merged body is skinned to the soldier's skeleton (%d of %d binds)" % [dc_bound, dc_skin.get_bind_count()])
	main.soldiers.erase(test_soldier)
	test_soldier.queue_free()
	var test_wolf = load("res://scripts/wolf.gd").new()
	test_wolf.world = main.world
	test_wolf.pos = main.player.pos + Vector2(300, 0)
	main.entities.add_child(test_wolf)
	var dc_horse = main._spawn_horse(main.player.pos + Vector2(0, 300), 0, false)
	await process_frame
	_check(not test_wolf._body.merged and not (dc_horse._look["body"]).merged, "wolves (glowing eyes) and horses (tack shown piece by piece) are left as they were")
	test_wolf.queue_free()
	main.tame_horses.erase(dc_horse)
	dc_horse.queue_free()
	# Props are drawn in chunks the renderer can cull; moving only builds what came into view.
	var pw = main.world
	var pv_here: Vector2 = main.player.pos
	pw.update_view(pv_here, true)
	var pv: Dictionary = pw.props_in_view(main.camera)
	var view_chunks: Array = pw._prop_view_chunks()
	var expected_props := 0
	for ck in view_chunks:
		for cell in pw._prop_chunk_cells(ck):
			if pw.prop_type(cell) in pw.PROP_TYPES:
				expected_props += 1
	# Every tile of the old 5x5-chunk window is covered by drawn prop chunks.
	var window: Rect2i = pw._prop_window(0)
	var covered := true
	for corner in [window.position, window.end - Vector2i.ONE, Vector2i(window.position.x, window.end.y - 1), Vector2i(window.end.x - 1, window.position.y)]:
		covered = covered and pw._prop_chunks.has(pw._prop_chunk_of_cell(corner)) and pw._prop_chunks[pw._prop_chunk_of_cell(corner)]["node"].visible
	_check(pv["chunks_drawn"] == view_chunks.size() and covered,
		"props are drawn in %d chunks of %d m covering the whole view distance" % [pv["chunks_drawn"], pw.prop_chunk])
	_check(pv["props_drawn"] == expected_props, "every tree, rock and bush within view distance is drawn (%d of %d)" % [pv["props_drawn"], expected_props])
	_check(pv["chunks_in_view"] > 0 and pv["chunks_in_view"] < pv["chunks_drawn"],
		"only some prop chunks are in the camera's view (%d of %d)" % [pv["chunks_in_view"], pv["chunks_drawn"]])
	var before_nodes := {}
	for ck in pw._prop_chunks:
		before_nodes[ck] = pw._prop_chunks[ck]["node"]
	pw.update_view(pv_here + Vector2(pw.CHUNK * pw.TILE, 0), true)
	var pv_kept := 0
	var pv_rebuilt := 0
	for ck in pw._prop_chunks:
		if before_nodes.has(ck):
			if before_nodes[ck] == pw._prop_chunks[ck]["node"]:
				pv_kept += 1
			else:
				pv_rebuilt += 1
	var pv_fresh: int = pw._prop_chunks.size() - pv_kept - pv_rebuilt
	var now_view: Array = pw._prop_view_chunks()
	var all_built := now_view.all(func(ck): return pw._prop_chunks.has(ck) and pw._prop_chunks[ck]["node"].visible)
	_check(pv_rebuilt == 0 and pv_kept == view_chunks.size() and all_built and pv_fresh <= now_view.size(),
		"moving one chunk keeps every built chunk and builds only the new edge (kept %d, rebuilt %d, new %d)" % [pv_kept, pv_rebuilt, pv_fresh])
	_check(pw.props_in_view(main.camera)["chunks_drawn"] == now_view.size(), "chunks that left the view are hidden, not drawn")
	var after_step: int = pw._prop_chunks.size()
	pw.update_view(pv_here, true)
	_check(pw._prop_chunks.size() == after_step and pw.props_in_view(main.camera)["props_drawn"] == expected_props,
		"stepping back over the boundary builds nothing new")
	# Felling a tree rebuilds only its own chunk, and it still blocks you until it's pv_felled.
	var pv_felled := Vector2i(-1, -1)
	for cell in pw._chunk_props(pw._view_chunk):  # a tree near the player
		if pw.prop_type(cell) == "tree":
			pv_felled = cell
			break
	if pv_felled.x >= 0:
		_check(not pw.is_walkable(pw.cell_center(pv_felled)), "trees still block the way")
		var pv_nodes := {}
		for ck in pw._prop_chunks:
			pv_nodes[ck] = pw._prop_chunks[ck]["node"]
		for i in 60:
			if pw.prop_type(pv_felled) != "tree":
				break
			pw.harvest(pv_felled, main.day)
		pw.update_view(pv_here, true)
		var pv_changed := []
		for ck in pw._prop_chunks:
			if pv_nodes.get(ck) != pw._prop_chunks[ck]["node"]:
				pv_changed.append(ck)
		_check(pw.prop_type(pv_felled) == "stump" and pv_changed == [pw._prop_chunk_of_cell(pv_felled)] and pw.is_walkable(pw.cell_center(pv_felled)),
			"felling a tree rebuilds only its chunk (%d rebuilt), and the stump can be walked over" % pv_changed.size())
		pw.prop_changes.erase(pv_felled)
		pw._mark_props_dirty(pv_felled)
		pw.update_view(pv_here, true)
	main._craft("torch")
	_check(main.player.torch_time > 0.0, "torch crafted")
	main._craft("spear")
	_check(main.player.has_spear and main.player.equipped == "spear", "spear crafted and taken in hand")
	# Stamina: sprinting and fighting use it; rest brings it back.
	var P = load("res://scripts/player.gd")
	main.player.stamina = P.MAX_STAMINA
	main.player.move(Vector2.RIGHT, 0.5, true)
	_check(main.player.sprinting and main.player.stamina < P.MAX_STAMINA, "sprinting uses stamina")
	main.player.stamina = 1.0
	main.player.move(Vector2.RIGHT, 0.5, true)
	main.player.move(Vector2.RIGHT, 0.1, true)
	_check(not main.player.sprinting and main.player.is_winded(), "out of stamina, you can't sprint")
	for k in 30:
		main.player.recover_stamina(0.1)
	_check(main.player.stamina >= 25.0 and not main.player.is_winded(), "stamina comes back when you rest (%d)" % int(main.player.stamina))
	main.player.stamina = P.MAX_STAMINA
	main.attack_cooldown = 0.0
	main._attack()
	_check(main.player.stamina < P.MAX_STAMINA, "attacking uses stamina")
	main.player.stamina = P.MAX_STAMINA
	_check(main.player.spear_tier == 1 and main.player.attack_damage() == 3 and main.player.attack_reach() > 30.0, "a flint spear hits harder and further")
	main._on_hotbar_slot(1)
	_check(main.player.equipped == "hands" and main.player.attack_damage() == 1, "pressing 2 again puts the spear away")
	main._on_hotbar_slot(2)
	_check(main.player.equipped == "hands", "you can't equip an axe you don't have")
	main._on_hotbar_slot(1)
	_check(main.player.equipped == "spear", "pressing 2 takes the spear back in hand")

	# First person and back.
	main.set_first_person(true, false)
	main._update_camera(0.016)
	var eye: Vector3 = main.player.position + Vector3(0, main.EYE_HEIGHT, 0)
	_check(main.camera.global_position.distance_to(eye) < 0.4, "first person: the camera is at eye height")
	_check(main._look_2d().dot(main.player.facing.normalized()) > 0.99, "first person: you look the way you were facing")
	var cam_forward: Vector3 = -main.camera.global_transform.basis.z
	_check(Vector2(cam_forward.x, cam_forward.z).normalized().dot(main._look_2d()) > 0.99, "first person: the camera points where you look")
	main.cam_yaw += 1.0
	main._update_camera(0.016)
	var turned: Vector3 = -main.camera.global_transform.basis.z
	_check(Vector2(turned.x, turned.z).normalized().dot(main._look_2d()) > 0.99, "first person: turning turns the view")
	main.set_first_person(false, false)
	main._update_camera(1.0)
	_check(main.camera.global_position.distance_to(eye) > 4.0, "V again: back to the strategy camera")
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
	var purge_gold := -1
	var w_season_before := ""
	var village_count := -1
	var purge_cell := Vector2i(-1, -1)
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
	_check(main._make(bench[0]) and main.player.has_axe and main.player.equipped == "axe", "the workbench makes an axe, straight into your hand")
	_check(not main._make(bench[0]), "you can't make a second axe")
	_check(main._make(bench[1]) and main.player.has_pickaxe, "the workbench makes a pickaxe")
	main.player.add_item("ore", 2)
	var iron_before: int = main.player.count("iron")
	_check(main._make(forge[0]) and main.player.count("iron") == iron_before + 1 and main.player.count("ore") == 0, "the forge smelts iron ore into iron")
	main.player.add_item("iron", 10)
	main.player.add_item("hide", 3)
	_check(main._make_gear("armour", 1) and main.player.armour and main.player.armour_tier == 1, "the forge makes iron armour")
	_check(main._make(forge[2]) and main.player.lantern, "the forge makes a lantern")

	# Gear by material: better materials, better weapons and armour.
	var Gear = load("res://scripts/gear.gd")
	var Wolf = load("res://scripts/wolf.gd")
	main.player.add_item("iron", 30)
	main.player.add_item("wood", 30)
	main.player.add_item("hide", 10)
	main.player.add_item("gold", 10)
	var steel_before: int = main.player.count("steel")
	_check(main._make(forge[1]) and main.player.count("steel") == steel_before + 1, "the forge folds iron into steel")
	main.player.add_item("steel", 20)
	var flint_damage: int = Gear.SPEAR[1]["damage"]
	_check(not main._make_gear("spear", 0), "you can't make a worse spear than the one you have")
	_check(main._make_gear("spear", 3) and main.player.spear_tier == 3 and main.player.attack_damage() == Gear.SPEAR[3]["damage"]
		and main.player.attack_damage() > flint_damage, "a steel spear hits harder than flint (%d vs %d)" % [main.player.attack_damage(), flint_damage])
	_check(main._make_gear("sword", 0) and main.player.equipped == "sword" and main.player.attack_reach() < Gear.SPEAR_REACH
		and main.player.attack_cooldown() < Gear.SPEAR_COOLDOWN, "an iron sword: shorter reach, quicker swings")
	_check(main._make_gear("sword", 2) and main.player.attack_damage() == Gear.SWORD[2]["damage"], "a gilded sword, with gold from the islets")
	var iron_cut: float = main.player.armour_reduction()
	_check(main._make_gear("armour", 3) and main.player.armour_reduction() > iron_cut, "gilded armour stops more of a bite than iron (%d%%)" % int(main.player.armour_reduction() * 100))
	for k in Gear.ARMOUR.size() - 1:
		_check(Gear.ARMOUR[k + 1]["reduce"] > Gear.ARMOUR[k]["reduce"], "%s beats %s" % [Gear.ARMOUR[k + 1]["name"], Gear.ARMOUR[k]["name"]])
	for k in Gear.SPEAR.size() - 1:
		_check(Gear.SPEAR[k + 1]["damage"] > Gear.SPEAR[k]["damage"], "%s beats %s" % [Gear.SPEAR[k + 1]["name"], Gear.SPEAR[k]["name"]])
	main._on_hotbar_slot(4)  # the new sword is already in hand
	_check(main.player.equipped == "hands", "key 5 puts the sword away")
	main._on_hotbar_slot(4)
	_check(main.player.equipped == "sword", "key 5 takes the sword in hand")
	_check(Wolf.pick_kind(1, false, 0.01) == "grey" and Wolf.pick_kind(6, false, 0.01) == "timber" and Wolf.pick_kind(14, true, 0.01) == "dire",
		"wolves get tougher as the days go on")
	_check(Wolf.info("dire")["hp"] > Gear.SPEAR[1]["damage"] * 4 and Wolf.info("dire")["hp"] <= Gear.SWORD[2]["damage"] * 2,
		"a dire wolf shrugs off a flint spear but not a gilded sword")
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
	main._on_hotbar_slot(0)
	var wood_hands: int = main.player.count("wood")
	main._interact()
	_check(main.player.count("wood") == wood_hands + 1, "with the axe put away, a hit gives 1 wood")
	main._on_hotbar_slot(2)
	_check(main.player.equipped == "axe" and main.player.attack_damage() == 2, "key 3 takes the axe in hand")
	main.action_cooldown = 0.0
	var wood_axe: int = main.player.count("wood")
	main._interact()
	_check(main.player.count("wood") == wood_axe + 20, "with an axe in hand, each hit gives 20 wood")
	main._on_hotbar_slot(3)
	_check(main._tool_bonus("stone") == 20 and main._tool_bonus("ore") == 20 and main._tool_bonus("gold") == 20 and main._tool_bonus("wood") == 1,
		"with a pickaxe in hand: 20 stone, ore or gold per hit")
	main._on_hotbar_slot(2)

	# Inventory screen.
	main.player.add_item("berries", 2)
	main._open_inventory()
	var actions: PackedStringArray = main.hud.inventory_actions()
	_check(main.hud.is_inventory_open() and main.hud.is_modal(), "the inventory opens and pauses the game")
	_check("equip:spear" in actions and "equip:hands" in actions and "eat:berries" in actions and "armour" in actions,
		"the inventory offers equip, eat and armour buttons (%s)" % ", ".join(actions))
	var berries_before: int = main.player.count("berries")
	main._on_inventory_action("eat:berries")
	_check(main.player.count("berries") == berries_before - 1, "eating from the inventory")
	main._on_inventory_action("equip:pickaxe")
	_check(main.player.equipped == "pickaxe", "equipping from the inventory")
	main._on_inventory_action("armour")
	_check(not main.player.wearing_armour(), "armour can be taken off")
	var ar_mesh: GeometryInstance3D = main.player._look_mesh  # null for the adventurer (--player=0)
	if ar_mesh:
		main.player._restyle_ranger_armour()
		_check(float(ar_mesh.get_instance_shader_parameter("armour_on")) == 0.0, "the ranger's armour shell goes when it is taken off")
	main._on_inventory_action("armour")
	_check(main.player.wearing_armour(), "and put back on")
	main.player.tick_visuals(0.016)
	if ar_mesh:
		main.player._restyle_ranger_armour()
		var ar_want: Color = Gear.info("armour", main.player.armour_tier)["color"]
		_check(float(ar_mesh.get_instance_shader_parameter("armour_on")) == 1.0
			and (ar_mesh.get_instance_shader_parameter("armour_color") as Color).is_equal_approx(ar_want),
			"and comes back, in the colour of its tier")
		_check(not main.player._armour.visible, "the ranger wears its own armour, not the boxy breastplate")
	else:
		_check(main.player._armour.visible, "the adventurer (--player=0) wears the breastplate")
	main.hud.close_inventory()
	_check(not main.hud.is_modal(), "the inventory closes")
	main._on_hotbar_slot(2)

	# Taking buildings down: a mistake is refunded in full, an old building by half.
	var spot: Array = _free_cells(world, world.cell_of(main.player.pos), 1, [axe_tree])
	main.player.add_item("wood", 8)
	var wood_pre: int = main.player.count("wood")
	_check(main._try_build("wood_wall", spot[0]), "built a wall to take down")
	main.player.pos = world.cell_center(spot[0]) + Vector2(16, 0)
	main._ask_demolish()
	_check(main.hud.is_modal(), "X next to a building asks before taking it down")
	main.hud._choose(0)
	_check(not main.buildings.has(spot[0]) and main.player.count("wood") == wood_pre,
		"taking it down within a minute gives everything back (%d of %d wood)" % [main.player.count("wood"), wood_pre])
	main._try_build("wood_wall", spot[0])
	main.buildings[spot[0]].built_ms = -1  # as if built long ago
	var wood_mid: int = main.player.count("wood")
	main._demolish(spot[0])
	_check(main.player.count("wood") == wood_mid + 2, "an older building gives back half")

	# The legion: unit types, centurions, names, ranks, formations and orders.
	var Soldier = load("res://scripts/soldier.gd")
	main.player.pos = home_pos
	var more_room: Array = _free_cells(world, world.cell_of(main.player.pos), 12, [tree_cell] + cells)
	main.player.add_item("wood", 120)
	main.player.add_item("stone", 40)
	main.player.add_item("berries", 120)
	main.player.add_item("hide", 6)
	main.player.add_item("iron", 10)
	main.player.add_item("gold", 4)
	_check(main._try_build("barracks", more_room[11]), "built a second barracks")
	_check(main._recruit(2, "archer") == 2, "recruited archers")
	_check(main._recruit(1, "cavalry") == 1, "recruited a horseman")
	_check(main._recruit(5, "centurion") == 2 and main._count_kind("centurion") == 2, "one centurion per barracks")
	var named := 0
	for so in main.soldiers:
		if so.soldier_name.split(" ").size() == 2:
			named += 1
	_check(named == main.soldiers.size(), "every soldier has a Roman name (%s)" % main.soldiers[0].soldier_name)
	_check(Soldier.rank_for(0) == 0 and Soldier.rank_for(3) == 1 and Soldier.rank_for(8) == 2 and Soldier.rank_for(15) == 3, "kills make veterans, elites and heroes")
	var killer = null
	for so in main.soldiers:
		if so.kills > 0:
			killer = so
	_check(killer != null, "the soldier who killed the wolf is credited")
	var vet = main.soldiers[1]
	var base_hp: float = vet.max_hp()
	vet.kills = 8
	_check(vet.rank_name() == "Elite" and vet.max_hp() > base_hp and vet.damage() >= 2, "an elite has more health and hits harder")
	var archer_ok := false
	for so in main.soldiers:
		if so.kind == "archer" and Soldier.info("archer")["reach"] > 100.0:
			archer_ok = true
	_check(archer_ok, "archers shoot from a distance")
	for i in 30:
		main._tick_army(0.1)
	var inspired := 0
	for so in main.soldiers:
		if so.inspired:
			inspired += 1
	_check(inspired > 0, "soldiers near a centurion are inspired (%d)" % inspired)
	for shape in Soldier.FORMATIONS:
		var spots := {}
		for i in 30:
			spots[Soldier.formation_offset(i, 30, shape)] = true
		_check(spots.size() == 30, "the %s formation gives everyone their own place" % shape)
	main._cycle_formation()
	_check(main.formation == "shield wall" and main.soldiers[0].formation == "shield wall", "Z changes the formation")
	main._set_selection(main.soldiers.slice(0, 5))
	_check(main.selected.size() == 5 and main.soldiers[0].selected, "soldiers can be selected")
	# Somewhere with an open straight path, so the check is about orders, not the terrain.
	var march_to: Vector2 = main.player.pos
	for k in 16:
		var way := Vector2.from_angle(k * TAU / 16.0)
		var open_path := true
		for step in range(0, 150, 6):
			for side in [-24.0, 0.0, 24.0]:
				if not world.is_walkable(main.player.pos + way * step + way.orthogonal() * side):
					open_path = false
		if open_path:
			march_to = main.player.pos + way * 140.0
			break
	main._order_to(march_to)
	for i in 120:
		main._tick_army(0.1)
	var arrived := 0
	for so in main.selected:
		if so.mode == "hold" and so.pos.distance_to(march_to) < 70.0:
			arrived += 1
	_check(arrived >= 4, "selected soldiers march where you send them (%d of 5)" % arrived)
	main._toggle_army_mode()
	_check(main.soldiers.all(func(so): return so.mode == "follow") and main.selected.is_empty(), "T calls everyone back")

	# Seasons.
	var Main = load("res://scripts/main.gd")
	_check(Main.season_of(1) == "spring" and Main.season_of(4) == "summer" and Main.season_of(7) == "autumn"
		and Main.season_of(10) == "winter" and Main.season_of(13) == "spring", "the seasons turn every 3 days")
	var lake := Vector2i(-1, -1)
	for r in range(1, 400):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if lake == Vector2i(-1, -1) and maxi(absi(dx), absi(dz)) == r and world.terrain_at(world.spawn_cell + Vector2i(dx, dz)) == 1:  # shallow water
					lake = world.spawn_cell + Vector2i(dx, dz)
		if lake != Vector2i(-1, -1):
			break
	_check(lake != Vector2i(-1, -1), "found shallow water (%d, %d)" % [lake.x, lake.y])
	_check(lake != Vector2i(-1, -1) and not world.is_walkable(world.cell_center(lake)), "shallow water can't be walked on in spring")
	world.set_season("winter")
	_check(world.is_walkable(world.cell_center(lake)) and world.to_3d(world.cell_center(lake)).y > 0.0, "in winter the water freezes and you walk on the ice")
	_check(not world.is_sailable(world.cell_center(lake), true), "boats can't sail on ice")
	var bush := Vector2i(-1, -1)
	for r in range(1, 60):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if bush == Vector2i(-1, -1) and world.prop_type(world.spawn_cell + Vector2i(dx, dz)) == "bush":
					bush = world.spawn_cell + Vector2i(dx, dz)
		if bush != Vector2i(-1, -1):
			break
	_check(bush != Vector2i(-1, -1) and world.harvest(bush, main.day).is_empty(), "nothing grows in winter")
	world.set_season(Main.season_of(main.day))
	_check(not world.is_walkable(world.cell_center(lake)), "the ice melts in spring")

	# Islets out at sea, and boats to reach them.
	_check(world.islets.size() >= 3, "there are islets out at sea (%d)" % world.islets.size())
	var hoards := 0
	for poi in world.pois:
		if poi["type"] == "hoard":
			hoards += 1
	_check(hoards == world.islets.size(), "every islet has a treasure hoard")
	var gold := 0
	for islet in world.islets:
		var c: Vector2i = islet["cell"]
		var rr := int(islet["r"])
		for dz in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if world.prop_type(c + Vector2i(dx, dz)) == "gold_rock":
					gold += 1
	_check(gold > 0, "gold ore grows on the islets (%d)" % gold)
	# The islets must not change anything on the main island.
	var unchanged := true
	var check_rng := RandomNumberGenerator.new()
	check_rng.seed = 5
	for i in 400:
		var x := check_rng.randi_range(100, 924)
		var z := check_rng.randi_range(100, 924)
		var with_islets: Array = world._sample(x, z)
		world._islets_on = false
		var without: Array = world._sample(x, z)
		world._islets_on = true
		if world.islet_at(Vector2i(x, z)) < 0 and (with_islets[0] != without[0] or not is_equal_approx(with_islets[1], without[1])):
			unchanged = false
	_check(unchanged, "the main island is exactly as it was before the islets")
	var coast := Vector2i(-1, -1)
	for r in range(2, 200):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc: Vector2i = world.spawn_cell + Vector2i(dx, dz)
				if coast == Vector2i(-1, -1) and maxi(absi(dx), absi(dz)) == r and world.can_build(cc) and main._next_to_water(cc) and world.is_walkable(world.cell_center(cc)):
					coast = cc
		if coast != Vector2i(-1, -1):
			break
	_check(coast != Vector2i(-1, -1), "found a spot at the water's edge")
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		if world.is_walkable(world.cell_center(coast + d)):
			main.player.pos = world.cell_center(coast + d)
	main.player.add_item("wood", 80)
	main.player.add_item("iron", 6)
	main.player.add_item("hide", 6)
	_check(main._try_build("dock", coast), "built a dock at the water's edge")
	var inland: Vector2i = more_room[0]
	_check(not main._next_to_water(inland) and main._build_problem("dock", inland) == "A dock must be at the water's edge.", "docks can't be built inland")
	var dock = main.buildings[coast]
	var raft = main._build_boat("raft", dock)
	_check(raft != null and main.boats.size() == 1, "the dock builds a raft")
	var galley = main._build_boat("galley", dock)
	_check(galley != null and main.boats.size() == 2 and galley.can_cross_deep() and not raft.can_cross_deep(), "and a galley that crosses the open sea")
	main._board(raft)
	_check(main.sailing == raft and main.player.on_boat and world.is_sailable(main.player.pos, false), "you board the raft in shallow water")
	var deep_spot := Vector2(40, 40) * 16.0
	_check(world.is_sailable(deep_spot, true) and not world.is_sailable(deep_spot, false), "only a galley sails the deep sea")
	_check(main._go_ashore() and not main.player.on_boat and world.is_walkable(main.player.pos) and main.sailing == null, "you go ashore and the boat stays moored")
	main._board(galley)
	main.save_game()
	var afloat: Dictionary = load("res://scripts/save_game.gd").read()
	_check(int(afloat.get("sailing", -1)) == 1 and afloat.get("boats", []).size() == 2, "the save remembers your boats and that you're aboard")
	main._go_ashore()

	# Raiders live in their own camps around the island; they never come for your base.
	var Raider = load("res://scripts/raider.gd")
	var main_camps: Array = main.camps.filter(func(c): return int(c["islet"]) < 0)
	_check(main_camps.size() >= 5, "raider camps are scattered over the main island (%d)" % main_camps.size())
	_check(main_camps.all(func(c): return (c["pos"] as Vector2).distance_to(world.cell_center(world.spawn_cell)) > 140.0 * 16.0),
		"no raider camp is near where you start")
	_check(main.camps.size() == main_camps.size() + world.islets.size(), "every islet has a raider camp too")
	_check(not main.has_method("_start_raid"), "no war bands come raiding")
	var camp0: Dictionary = main_camps[0]
	var camp_at: Vector2 = camp0["pos"]
	main.player.pos = camp_at + Vector2(0, 200)
	main._tick_camps()
	var guards: Array = main._camp_guards.get(camp0["id"], [])
	_check(guards.size() >= 3 and guards.any(func(g): return g.kind == "raider_chief"), "a chief and his raiders guard the camp (%d)" % guards.size())
	_check(main.camps_found.has(camp0["id"]), "you discover a camp when you come near")
	_check(main._count_wolves() == main.wolves.filter(func(w): return not w.is_raider()).size(), "raiders don't count as wolves")
	var guard = guards[1]
	var gap: float = guard.pos.distance_to(camp_at + Vector2(0, 120))
	for i in 20:
		guard.tick(0.1, camp_at + Vector2(0, 120), main._lights(), false)
	_check(guard.pos.distance_to(camp_at + Vector2(0, 120)) < gap, "guards come for you by day if you trespass")
	for i in 80:
		guard.tick(0.1, home_pos, main._lights(), true)
	_check(guard.pos.distance_to(camp_at) < Raider.GUARD_LEASH * 1.3, "guards never leave their camp to chase you home")
	var iron_pre_raid: int = main.player.count("iron")
	main._kill_wolf(guard, false)
	_check(main.player.count("iron") > iron_pre_raid and not main.wolves.has(guard), "a fallen raider drops iron")
	_check(Raider.raider_info("raider_chief")["hp"] > Raider.raider_info("raider")["hp"] * 2, "raider chiefs are much tougher")
	var gold_pre_chest: int = main.player.count("gold")
	for g in guards.duplicate():
		if main.wolves.has(g):
			main._kill_wolf(g, false)
	main._tick_camps()
	_check(main.camps_cleared.has(camp0["id"]) and not main._camp_holds(camp0["id"]) and main.player.count("gold") > gold_pre_chest,
		"beating the guards clears the camp and wins its war chest")
	main.day = 1 + main.CAMP_REGROUP_DAYS
	_check(main._camp_holds(camp0["id"]), "raiders retake a camp after a while")
	main.day = 1
	# A camp next to anything you've built stays empty.
	var camp1: Dictionary = main_camps[1]
	var wall_cells: Array = _free_cells(world, world.cell_of(camp1["pos"]), 1, [])
	main.player.add_item("wood", 10)
	var wall_ok: bool = wall_cells.size() == 1 and main._try_build("wood_wall", wall_cells[0])
	main.player.pos = (camp1["pos"] as Vector2) + Vector2(0, 200)
	main._tick_camps()
	_check(wall_ok and not main._camp_guards.has(camp1["id"]), "no raiders appear near your buildings")
	# Nothing damages your buildings: a wolf pressed against a wall at night leaves it whole.
	if wall_ok:
		var wall_cell: Vector2i = wall_cells[0]
		var pup2 = load("res://scripts/wolf.gd").new()
		pup2.world = world
		pup2.pos = world.cell_center(wall_cell) + Vector2(-18, 0)
		main.entities.add_child(pup2)
		main.wolves.append(pup2)
		main.player.pos = world.cell_center(wall_cell) + Vector2(18, 0)
		main.clock = main.DAY_LENGTH * 0.8
		for i in 30:
			main._tick_wolves(0.1)
		var wall = main.buildings[wall_cell]
		_check(wall.hp >= wall.max_hp(wall.kind), "wolves never damage your walls")
		main.wolves.erase(pup2)
		pup2.queue_free()
		main._demolish(wall_cell)
		main.clock = main.DAY_LENGTH * 0.3
	# Islet camps guard their hoard.
	var isle_centre: Vector2 = world.cell_center(world.islets[0]["cell"])
	main.player.pos = isle_centre
	main._tick_camps()
	var isle_guards: Array = main._camp_guards.get("islet-0", [])
	_check(isle_guards.size() >= 3, "raiders guard the islet camp (%d)" % isle_guards.size())
	main._update_pois(0.0, true)
	if main.poi_nodes.has("hoard-0"):
		main._use_poi(main.poi_nodes["hoard-0"])
		_check(not main.poi_looted.has("hoard-0"), "the hoard can't be taken while its guards stand")
	for g in isle_guards.duplicate():
		main._kill_wolf(g, false)
	main._tick_camps()
	_check(main.camps_cleared.has("islet-0"), "beating the islet guards frees the hoard")
	for w in main.wolves.duplicate():
		if w.is_raider():
			main.wolves.erase(w)
			w.queue_free()
	main._camp_guards.clear()
	main.player.pos = home_pos
	# The purge: fill a treasure vault with gold, then hold it against waves of raiders.
	var row: Array = _free_row(world, world.cell_of(home_pos) + Vector2i(3, 3), 6)
	main.player.add_item("wood", 20)
	main.player.add_item("iron", 6)
	main.player.add_item("gold", 2)
	var vault_ok: bool = row.size() == 6 and main._try_build("vault", row[0])
	_check(vault_ok, "a treasure vault can be built")
	if vault_ok:
		var vault = main.buildings[row[0]]
		main.player.inventory["gold"] = 20
		main._open_vault(vault)
		main._on_vault_action("deposit")
		_check(main._vault_gold(vault) == 20 and main.player.count("gold") == 0, "your gold goes into the vault")
		_check(not main._start_purge(vault), "a purge needs %d gold in the vault" % main.PURGE_MIN_GOLD)
		main.player.add_item("gold", 80)
		main._on_vault_action("deposit")
		main.hud.close_inventory()
		var stake: int = main._vault_gold(vault)
		_check(stake == 100 and main._start_purge(vault), "with enough gold you can start a purge")
		_check(not main._start_purge(vault), "only one purge at a time")
		# Only purge raiders hack through walls, and they steal from the vault.
		var army: Array = main.soldiers.duplicate()
		main.soldiers.clear()
		main.player.pos = vault.pos + Vector2(0, 400)
		var wall_up: bool = main._try_build("wood_wall", row[2])
		var breaker = main._spawn_raider("raider", world.cell_center(row[5]))
		breaker.purge = true
		var stolen_before: int = main._vault_gold(vault)
		for i in 400:
			main._tick_wolves(0.1)
			if not main.buildings.has(row[2]) and main._vault_gold(vault) < stolen_before:
				break
		_check(wall_up and not main.buildings.has(row[2]), "purge raiders break through your walls to reach the vault")
		_check(main._vault_gold(vault) < stolen_before and int(main.purge.get("stolen", 0)) > 0, "a raider at the vault steals your gold")
		main._kill_wolf(breaker, false)
		# Waves come, bigger each time, and the purge is won when the last falls.
		main._tick_purge(9.0)
		var wave1: Array = main._purge_raiders()
		_check(int(main.purge.get("wave", 0)) == 1 and wave1.size() >= 5, "the first wave arrives (%d raiders)" % wave1.size())
		_check(wave1.all(func(r): return r.pos.distance_to(vault.pos) > 300.0 and r.home == Vector2.INF),
			"waves gather out of sight and aren't tied to a camp")
		var waves: int = int(main.purge.get("waves", 0))
		var purge_steel: int = main.player.count("steel")
		var gold_left: int = main._vault_gold(vault)
		var biggest: int = wave1.size()
		for i in 30:
			if main.purge.is_empty():
				break
			for r in main._purge_raiders():
				main._kill_wolf(r, true)
			main._tick_purge(13.0)
			biggest = maxi(biggest, main._purge_raiders().size())
		_check(main.purge.is_empty() and main._vault_gold(vault) == gold_left + stake / 2
			and main.player.count("steel") > purge_steel, "holding the vault through %d waves pays half again, and spoils" % waves)
		_check(biggest > wave1.size(), "later waves are bigger (%d)" % biggest)
		_check(not main._start_purge(vault), "one purge a day")
		main.soldiers.append_array(army)
		main.player.pos = home_pos
		purge_gold = main._vault_gold(vault)
		purge_cell = row[0]
	# Defences fight back: an archer tower shoots, a spike trap stabs, an oil gate scalds.
	w_season_before = world.season
	world.set_season("spring")
	var def_cells: Array = _free_cells(world, world.cell_of(home_pos) + Vector2i(-6, -6), 3, [world.cell_of(main.player.pos)])
	main.player.add_item("wood", 60)
	main.player.add_item("stone", 20)
	main.player.add_item("iron", 10)
	_check(def_cells.size() == 3, "found room for the defences")
	if def_cells.size() == 3:
		var tower_ok: bool = main._try_build("archer_tower", def_cells[0])
		var tower = main.buildings.get(def_cells[0])
		var target = main._spawn_raider("raider", tower.pos + Vector2(110, 0) if tower else home_pos)
		for i in 120:
			main._tick_defences(0.1)
		_check(tower_ok and not main.wolves.has(target), "an archer tower shoots down a raider in range")
		var far_foe = main._spawn_raider("raider", tower.pos + Vector2(400, 0) if tower else home_pos)
		var far_hp: int = far_foe.hp
		for i in 30:
			main._tick_defences(0.1)
		_check(far_foe.hp == far_hp, "but not one out of range")
		main.wolves.erase(far_foe)
		far_foe.queue_free()
		main._demolish(def_cells[0])
		var trap_ok: bool = main._try_build("spike_trap", def_cells[1])
		var trap_pos: Vector2 = world.cell_center(def_cells[1])
		_check(trap_ok and world.is_walkable(trap_pos, true) and world.is_walkable(trap_pos), "wolves, raiders and you can all step on a spike trap")
		var stepper = main._spawn_raider("raider", trap_pos + Vector2(3, 0))
		var hp0: int = stepper.hp
		for i in 12:
			main._tick_defences(0.1)
		_check(stepper.hp < hp0, "a spike trap wounds a raider who steps on it (%d → %d)" % [hp0, stepper.hp])
		if main.wolves.has(stepper):
			main.wolves.erase(stepper)
			stepper.queue_free()
		main._demolish(def_cells[1])
		var oil_ok: bool = main._try_build("oil_gate", def_cells[2])
		var oil_pos: Vector2 = world.cell_center(def_cells[2])
		_check(oil_ok and world.is_walkable(oil_pos) and not world.is_walkable(oil_pos, true), "an oil gate lets you through but not wolves")
		var basher = main._spawn_raider("raider", oil_pos + Vector2(16, 0))
		var hp1: int = basher.hp
		for i in 20:
			main._tick_defences(0.1)
		_check(basher.hp < hp1 or not main.wolves.has(basher), "boiling oil scalds raiders at the gate")
		if main.wolves.has(basher):
			main.wolves.erase(basher)
			basher.queue_free()
		main._demolish(def_cells[2])
	# Soldiers at work: woodcutters fill your chest, and T doesn't call them away.
	var idle_before: int = main._idle_soldiers().size()
	_check(main._set_job("wood", 1), "a soldier can be sent to cut wood")
	var cutters: Array = main.soldiers.filter(func(so): return so.mode == "work" and so.job == "wood")
	_check(cutters.size() == 1 and main._idle_soldiers().size() == idle_before - 1, "the woodcutter leaves the idle soldiers")
	if cutters.size() == 1:
		var cutter = cutters[0]
		_check(world.prop_type(world.cell_of(cutter.work_at)) == "tree" and cutter.guard_point.distance_to(cutter.work_at) < 20.0,
			"the woodcutter's place is next to a tree")
		cutter.pos = cutter.guard_point
		var wood_total: int = _wood_everywhere(main)
		for i in 50:
			main._tick_army(0.1)
		_check(_wood_everywhere(main) >= wood_total + 3, "the woodcutter brings in wood (%d → %d)" % [wood_total, _wood_everywhere(main)])
		main._toggle_army_mode()
		_check(cutter.mode == "work", "T leaves workers at their jobs")
		main._toggle_army_mode()
		_check(main._set_job("wood", -1) and cutter.mode != "work", "a worker can be called back")
	# Farming: sow a field, watch the wheat grow, harvest it, bake bread.
	var farm_cells: Array = _free_cells(world, world.cell_of(home_pos) + Vector2i(7, -7), 3, [world.cell_of(main.player.pos)])
	main.player.add_item("berries", 10)
	main.player.add_item("wood", 40)
	main.player.add_item("stone", 10)
	var field_ok: bool = farm_cells.size() == 3 and main._try_build("field", farm_cells[0])
	_check(field_ok, "a farm field can be built")
	if field_ok:
		var field = main.buildings[farm_cells[0]]
		_check(world.is_walkable(field.pos), "you can walk across a field")
		main._tick_village(main.Structure.GROW_TIME * 0.5)
		_check(absf(field.growth - 0.5) < 0.05 and not field.is_ripe(), "wheat grows over half a day (%.2f)" % field.growth)
		world.set_season("winter")
		main._tick_village(main.Structure.GROW_TIME * 0.2)
		_check(absf(field.growth - 0.5) < 0.05, "nothing grows in winter")
		world.set_season("spring")
		main._tick_village(main.Structure.GROW_TIME * 0.6)
		_check(field.is_ripe(), "the wheat ripens")
		var wheat0: int = main.player.count("wheat")
		main._use_building(field)
		_check(main.player.count("wheat") == wheat0 + main.Structure.FIELD_YIELD and field.growth == 0.0, "E harvests %d wheat and sows again" % main.Structure.FIELD_YIELD)
		main._make({"id": "bread", "name": "Bread", "cost": {"wheat": 2}})
		_check(main.player.count("bread") >= 1 and main.player.count("wheat") == wheat0 + main.Structure.FIELD_YIELD - 2, "the smokehouse bakes bread from wheat")
		main.player.hunger = 40.0
		main._eat_item("bread")
		_check(main.player.hunger >= 69.0, "bread is filling")
		_check(main._set_job("farm", 1), "a soldier can farm the field")
		var farmer = main.soldiers.filter(func(so): return so.job == "farm")[0]
		_check(farmer.work_at == field.pos, "the farmer goes to the field")
		farmer.pos = farmer.guard_point
		var g0: float = field.growth
		for i in 50:
			main._tick_army(0.1)
		_check(field.growth > g0, "a farmer makes the wheat grow")
		# The village: a cottage, food in a chest, and settlers come at dawn.
		var house_ok: bool = main._try_build("house", farm_cells[1])
		var pantry_ok: bool = main._try_build("chest", farm_cells[2])
		_check(house_ok and pantry_ok, "a cottage and a pantry chest can be built")
		if house_ok and pantry_ok:
			var pantry = main.buildings[farm_cells[2]]
			pantry.items["wheat"] = 30
			main._village_dawn()
			_check(main.settlers.size() == 2, "two settlers move into the cottage (%d)" % main.settlers.size())
			var gold_before: int = main.player.count("gold") + _vault_gold_total(main)
			var food_before: int = main._food_in_store()
			main._village_dawn()
			_check(main._food_in_store() == food_before - 4 and main.taxes_last == 4
				and main.player.count("gold") + _vault_gold_total(main) == gold_before + 4, "each morning settlers eat from your chests and pay 2 gold each")
			_check(main.settlers.size() == 2, "no more settlers than beds")
			# They run home when danger comes, and wolves and raiders go for them.
			var villager = main.settlers[0]
			var threat = main._spawn_raider("raider", villager.pos + Vector2(80, 0))
			for i in 40:
				main._tick_village(0.1)
			_check(villager.hidden, "a settler runs home and hides from a raider")
			main.wolves.erase(threat)
			threat.queue_free()
			for i in 5:
				main._tick_village(0.1)
			_check(not villager.hidden, "and comes out when it's gone")
			# A wall between a settler and the cottage: they run round it, not into it.
			var detour: Dictionary = _wall_between(world, world.cell_of(villager.home))
			_check(not detour.is_empty(), "found room to wall a settler off from the cottage")
			if not detour.is_empty():
				for c in detour["wall"]:
					main._add_structure("wood_wall", c)
				villager.pos = world.cell_center(detour["stand"])
				var blocker = main._spawn_raider("raider", villager.pos + Vector2(0, 90))
				var took := -1.0
				for i in 80:
					main._tick_village(0.1)
					if villager.hidden:
						took = (i + 1) * 0.1
						break
				_check(villager.hidden, "a settler walled off from the cottage runs round the wall and hides (%.1fs)" % took)
				main.wolves.erase(blocker)
				blocker.queue_free()
				for c in detour["wall"]:
					main._remove_structure(c)
				for i in 5:
					main._tick_village(0.1)
			village_count = main.settlers.size()
	world.set_season(w_season_before)
	# Wild horses: find a herd, win a horse's trust with berries, then ride it.
	var Horse = load("res://scripts/horse.gd")
	_check(main.herds.size() >= 5, "herds of wild horses graze around the island (%d)" % main.herds.size())
	var herd0: Dictionary = main.herds[0]
	_check((herd0["pos"] as Vector2).distance_to(world.cell_center(world.spawn_cell)) < 70.0 * 16.0, "one herd grazes near the start")
	main.player.pos = (herd0["pos"] as Vector2) + Vector2(0, 60)
	main._tick_horses(0.1)
	_check(main._wild_horses.size() >= 2, "wild horses appear in their meadow (%d)" % main._wild_horses.size())
	var wild = main._wild_horses.values()[0]
	var spare_berries: int = main.player.count("berries")
	main.player.add_item("berries", -spare_berries)
	main._use_horse(wild)
	_check(wild.trust == 0 and wild.wild, "a wild horse won't trust you without berries")
	main.player.add_item("berries", 20)
	for k in Horse.FEEDS_TO_TAME:
		main._use_horse(wild)
	_check(not wild.wild and main.tame_horses.has(wild) and main.horses_taken.has(wild.herd_id),
		"%d feeds of berries tame a horse" % Horse.FEEDS_TO_TAME)
	main.player.pos = wild.pos + Vector2(10, 0)
	main.action_cooldown = 0.0
	main._interact()
	_check(main.hud.is_inventory_open() and main._horse_open == wild, "E by your horse opens its saddlebags")
	# Saddlebags: store things on your horse and take them back.
	var stone_carried: int = main.player.count("stone")
	main._on_horse_action("store:stone")
	_check(main.player.count("stone") == 0 and int(wild.items.get("stone", 0)) == mini(stone_carried, Horse.CAPACITY), "you can store things in its saddlebags")
	main._on_horse_action("take:stone")
	_check(main.player.count("stone") == stone_carried and not wild.items.has("stone"), "and take them back")
	main.player.add_item("wood", Horse.CAPACITY + 50)
	main._on_horse_action("store:wood")
	_check(wild.load_count() == Horse.CAPACITY and wild.room() == 0, "saddlebags hold up to %d things" % Horse.CAPACITY)
	main._on_horse_action("take_all")
	main._on_horse_action("store:berries")
	var bag_berries: int = int(wild.items.get("berries", 0))
	main._on_horse_action("ride")
	_check(main.riding_horse == wild and main.player.riding and main.player.ride_height() > 0.0 and not main.hud.is_inventory_open(), "Ride: you're in the saddle")
	var start: Vector2 = main.player.pos
	main.player.move(Vector2.RIGHT, 0.05)
	var ridden: float = main.player.pos.distance_to(start)
	_check(ridden == 0.0 or ridden > main.player.SPEED * 0.05 * 1.5, "riding is faster than walking")
	main.action_cooldown = 0.0
	main._interact()
	_check(main.riding_horse == null and not main.player.riding and wild.visible, "E again: you get off, and the horse waits")
	# Building prototype (phase 4B): cottages, stone walls and archer towers are
	# KayKit models: one mesh and one shared material each, and otherwise the
	# same buildings (hit points, blocking, previews, damage).
	var bp_cells: Array = _free_cells(world, world.cell_of(home_pos) + Vector2i(5, -5), 3, cells)
	var bp: Array = []
	for bi in 3:
		bp.append(main._add_structure(["house", "stone_wall", "archer_tower"][bi], bp_cells[bi]))
	await process_frame
	var bp_ok := true
	for b in bp:
		bp_ok = bp_ok and b._model != null and b._parts == [b._model] and b._model.mesh.get_surface_count() == (2 if b.kind == "house" else 1) \
			and b._model.get_surface_override_material(0) == StructureScript._building_material() and b.hp == StructureScript.max_hp(b.kind) \
			and not world.is_walkable(world.cell_center(b.cell))
	var bp_house2 = main._add_structure("house", _free_cells(world, bp_cells[0], 1, cells + bp_cells)[0])
	await process_frame
	_check(bp_ok and bp_house2._model.mesh == bp[0]._model.mesh, "cottages, stone walls and towers are the new models: one shared mesh and material each, same hit points, and they block")
	var bp_glow: Material = bp[0]._model.get_surface_override_material(1)
	_check(bp_glow == load("res://scripts/art.gd").shared_material(Color(1.0, 0.85, 0.5), 0.8) and (bp_glow as BaseMaterial3D).emission_enabled
		and bp_house2._model.get_surface_override_material(1) == bp_glow,
		"cottage windows glow with the old window's shared material")
	bp[0].damage(StructureScript.max_hp("house") * 0.6)
	var bp_ghost = StructureScript.new()
	bp_ghost.setup(world, "archer_tower", bp_cells[2] + Vector2i(0, 1))
	main.entities.add_child(bp_ghost)
	bp_ghost.make_ghost(false)
	_check(bp[0].rotation.z > 0.05 and (bp_ghost._model.material_override as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and bp_ghost._model.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a damaged cottage leans, and a tower's build preview is see-through")
	bp_ghost.queue_free()
	main._remove_structure(bp_house2.cell)
	await process_frame
	_check(not is_instance_valid(bp_house2) and not main.buildings.values().has(bp_house2), "taking a new cottage down removes it")
	main._mount(wild)
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
	_check(copy_main.player.spear_tier == main.player.spear_tier and copy_main.player.sword_tier == main.player.sword_tier
		and copy_main.player.armour_tier == main.player.armour_tier, "your spear, sword and armour keep their materials after reload")
	_check(copy_main.player.equipped == main.player.equipped, "resumed holding the same tool (%s)" % copy_main.player.equipped)
	_check(copy_main.player._body.merged and copy_main.player._body._meshes[0].mesh == main.player._body._meshes[0].mesh
		and copy_main.player._body.has_action("slash"), "after loading, the player is the same model (%s), animations and all"
		% ("ranger" if main.player.use_ranger else "adventurer"))
	_check(copy_main.world.prop_type(tree_cell) == "stump", "felled tree is still a stump after reload")
	_check(copy_main.campfires.size() == 1, "campfire is still there after reload")
	_check(copy_main.buildings.size() == main.buildings.size(), "buildings are still there after reload (%d)" % copy_main.buildings.size())
	_check(copy_main.soldiers.size() == main.soldiers.size(), "the army is still there after reload (%d)" % copy_main.soldiers.size())
	_check(copy_main.soldiers[0].soldier_name == main.soldiers[0].soldier_name and copy_main._count_kind("archer") == main._count_kind("archer")
		and copy_main.soldiers[1].kills == main.soldiers[1].kills, "names, kinds and kills survive a reload")
	_check(copy_main.boats.size() == 2 and copy_main.formation == main.formation, "boats and the formation survive a reload")
	_check(int(copy_main.tame_horses[0].items.get("berries", 0)) == bag_berries and bag_berries > 0, "saddlebags keep their contents after a reload")
	_check(copy_main.tame_horses.size() == main.tame_horses.size() and copy_main.riding_horse != null
		and copy_main.horses_taken.has(wild.herd_id), "your horses, and riding one, survive a reload")
	_check(copy_main.camps_cleared.has("islet-0") and copy_main.camps_found.has(camp0["id"]), "found and cleared raider camps are remembered")
	_check(village_count < 0 or copy_main.settlers.size() == village_count, "settlers are still in the village after reload")
	_check(copy_main._fields.size() == main._fields.size() and copy_main._count_job("farm") == main._count_job("farm"),
		"fields and farmers survive a reload")
	_check(purge_gold < 0 or (copy_main.buildings.has(purge_cell) and copy_main._vault_gold(copy_main.buildings[purge_cell]) == main._vault_gold(main.buildings[purge_cell])
		and copy_main.purged_day == main.purged_day), "the vault keeps its gold after reload, and you can't purge twice in a day")
	_check(not copy_main.world.is_walkable(world.cell_center(cells[0])), "walls still block after reload")
	var bp_reloaded := true
	for b in bp:
		var rb = copy_main.buildings.get(b.cell)
		bp_reloaded = bp_reloaded and rb != null and rb.kind == b.kind and rb._model != null and is_equal_approx(rb.hp, b.hp)
	_check(bp_reloaded, "the new cottage, wall and tower load back as models with the same damage")
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
	var day_length: float = load("res://scripts/main.gd").DAY_LENGTH
	_check(day_length >= 900.0, "a day lasts about 16 minutes (%d s)" % int(day_length))
	var steps := int(day_length * 3 / 0.25)
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


## The terrain of one chunk worked out the old way (four lookups per corner).
func _old_terrain(w, ck: Vector2i) -> Dictionary:
	var size: int = w.CHUNK + 1
	var corners := []
	for cz in size:
		for cx in size:
			var x: int = ck.x * w.CHUNK + cx
			var z: int = ck.y * w.CHUNK + cz
			var h: float = (w._tile_height(x - 1, z - 1) + w._tile_height(x, z - 1)
				+ w._tile_height(x - 1, z) + w._tile_height(x, z)) / 4.0
			h += w._detail.get_noise_2d(x, z) * 0.28 * clampf(h * 2.0, 0.0, 1.0)
			corners.append(h)
	var stored := PackedFloat32Array(corners)  # the heights are kept as 32-bit floats
	var verts := []
	var normals := []
	var colors := []
	for cz in size:
		for cx in size:
			var gx: int = ck.x * w.CHUNK + cx
			var gz: int = ck.y * w.CHUNK + cz
			verts.append(Vector3(gx, stored[cz * size + cx], gz))
			normals.append(Vector3(w._corner_height(gx - 1, gz) - w._corner_height(gx + 1, gz), 2.0,
				w._corner_height(gx, gz - 1) - w._corner_height(gx, gz + 1)).normalized())
			colors.append(w._corner_blend(gx, gz))
	return {"corners": stored, "verts": verts, "normals": normals, "colors": colors}


## The grass around the player worked out the old way, as sorted records.
func _old_grass(w) -> Array:
	var out := []
	var center: Vector2i = w._view_chunk * w.CHUNK + Vector2i(w.CHUNK / 2, w.CHUNK / 2)
	var r: int = w.GRASS_RADIUS
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var cell: Vector2i = center + Vector2i(dx, dz)
			var t: int = w.terrain_at(cell)
			if t != w.GRASS and t != w.FOREST:
				continue
			if w.structures.has(cell) or w._poi_cells.has(cell):
				continue
			for c in (3 if t == w.GRASS else 1):
				var jx: float = w._hash01(cell.x, cell.y, 20 + c)
				var jz: float = w._hash01(cell.x, cell.y, 30 + c)
				var p := Vector2(cell.x + jx, cell.y + jz)
				var y: float = w.height_at(p * w.TILE)
				var sc: float = 0.7 + w._hash01(cell.x, cell.y, 40 + c) * 0.7
				var xf := Transform3D(Basis(Vector3.UP, jx * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(p.x, y - 0.02, p.y))
				var g: float = w._hash01(cell.x, cell.y, 50 + c)
				var tint: Color = Color("50652c").lerp(Color("7a7a42"), g * 0.8) if t == w.GRASS else Color("3b4c25")
				if w.season == "autumn":
					tint = tint.lerp(Color("8a6a34"), 0.45)
				elif w.season == "summer":
					tint = tint.lerp(Color("8a8040"), 0.2)
				out.append(_grass_key(xf, tint))
	out.sort()
	return out


## The grass in a MultiMesh, as sorted records (to compare whatever the order).
## Read from the raw buffer: a 3x4 transform (row by row) then a colour per
## clump. Headless Godot keeps the buffer but can't read transforms back.
func _grass_records(mm: MultiMesh) -> Array:
	var out := []
	var b: PackedFloat32Array = mm.buffer
	for i in mm.instance_count:
		var o := i * 16
		var xf := Transform3D(Basis(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]),
			Vector3(b[o + 2], b[o + 6], b[o + 10])), Vector3(b[o + 3], b[o + 7], b[o + 11]))
		out.append(_grass_key(xf, Color(b[o + 12], b[o + 13], b[o + 14], b[o + 15])))
	out.sort()
	return out


func _grass_key(xf: Transform3D, c: Color) -> String:
	return "%.3f %.3f %.3f %.4f %.4f %.4f %.3f %.3f %.3f" % [xf.origin.x, xf.origin.y, xf.origin.z,
		xf.basis.x.x, xf.basis.x.z, xf.basis.y.y, c.r, c.g, c.b]


## Wood in your pack and all your chests.
func _wood_everywhere(main) -> int:
	var n: int = main.player.count("wood")
	for b in main.buildings.values():
		if b.kind == "chest":
			n += int(b.items.get("wood", 0))
	return n


func _vault_gold_total(main) -> int:
	var n := 0
	for b in main.buildings.values():
		if b.kind == "vault":
			n += int(b.items.get("gold", 0))
	return n


## A way to put a 3-tile wall between a settler and the cottage at `home`: the
## wall two tiles out, the settler four tiles out, and room to walk round.
## {"wall": [cells], "stand": cell}, or {} if no side of the cottage has room.
func _wall_between(world, home: Vector2i) -> Dictionary:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var side := Vector2i(d.y, d.x)  # along the wall
		var wall := [home + d * 2 - side, home + d * 2, home + d * 2 + side]
		var ok := true
		for c in wall:
			ok = ok and world.can_build(c)
		# Open ground for the settler, and a way round at least one end of the wall.
		for c in [home + d * 3, home + d * 4, home + d, home + d * 3 + side * 2, home + d * 2 + side * 2, home + d + side * 2,
				home + d + side]:
			ok = ok and world.is_walkable(world.cell_center(c))
		if ok:
			return {"wall": wall, "stand": home + d * 4}
	return {}


## `n` free tiles in an east-west row, searching around `start`.
func _free_row(world, start: Vector2i, n: int) -> Array:
	for r in range(0, 14):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var line := []
				for k in n:
					var c := start + Vector2i(dx + k, dz)
					if not world.can_build(c):
						break
					line.append(c)
				if line.size() == n:
					return line
	return []


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
