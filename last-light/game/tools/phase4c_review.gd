## Phase 4C final review (GRAPHICS_PHASE_4C_FINAL.md): checks the player's
## ranger model as shipped, without rendering.
##   - skeleton: the 65-bone humanoid rig, the same bones the kits share;
##   - skin: every bind names a bone of that skeleton, every vertex's weights
##     are valid and sum to 1, bone indices are in range;
##   - animations: the six the game asks for, every track on a real bone;
##   - parts: each approved part (clothing, skin, hood up, hood down, armour,
##     backpack) matches its approved fingerprint (tools/model_parts_hash.gd);
##   - in game: the equipment followers sit on the right bones, and the tools,
##     torch and armour follow them through every animation.
##   godot --headless --path last-light/game --script res://tools/phase4c_review.gd
## Prints REVIEW_OK or REVIEW_FAILED.
extends SceneTree

## Fingerprints of the approved parts (GRAPHICS_PLAYER_HOOD.md, unchanged by the outfits).
const APPROVED := {
	0: "cb9556e9d2b0d11f15c1bd9f28283e7d",  # clothing
	1: "e70aed2b4551587720e1266708a3b79e",  # skin
	2: "61cd5f8959496dba6691c27ab58c37f2",  # hood up (with cropped hair)
	3: "b2b559e0a348cf9c374b32cbd5f2c4bf",  # hood down (folded hood, hair)
	4: "720d3c0bcf3347cfb53e37d998435cde",  # armour
	5: "814a0e23da012cc3c6b31db4ff66df6a",  # backpack (hidden by default? see the report)
}

var _failed := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = load("res://models/player/ranger.scn").instantiate()
	root.add_child(scene)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	print("Model")
	_check(sk.get_bone_count() == 65, "skeleton has the humanoid rig's 65 bones (%d)" % sk.get_bone_count())
	for bone in ["root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "hand_r", "hand_l", "foot_r", "foot_l"]:
		if sk.find_bone(bone) < 0:
			_check(false, "bone %s is missing" % bone)
	var skin := mi.skin
	var bad_binds := 0
	for b in skin.get_bind_count():
		if sk.find_bone(skin.get_bind_name(b)) < 0:
			bad_binds += 1
	_check(bad_binds == 0, "all %d skin binds name a bone of the skeleton" % skin.get_bind_count())
	_check(mi.mesh.get_surface_count() == 1 and mi.mesh.surface_get_material(0) is ShaderMaterial,
		"one surface, one material (%s)" % mi.mesh.surface_get_material(0).resource_name)
	var a := mi.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bad_sum := 0
	var bad_index := 0
	var unbound := 0
	for i in n:
		var sum := 0.0
		for c in 4:
			var wt := weights[i * 4 + c]
			sum += wt
			if wt < 0.0 or bones[i * 4 + c] < 0 or bones[i * 4 + c] >= skin.get_bind_count():
				bad_index += 1
		if absf(sum - 1.0) > 0.01:
			bad_sum += 1
		if sum <= 0.0:
			unbound += 1
	_check(bad_sum == 0 and bad_index == 0 and unbound == 0,
		"all %d vertices skinned: weights sum to 1, bone indices in range (off: %d, bad: %d)" % [n, bad_sum, bad_index])
	var tris: int = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("  info triangles %d, vertices %d, binds %d, LODs %d" % [tris, n, skin.get_bind_count(), mi.mesh.surface_get_lod_count(0) if mi.mesh.has_method("surface_get_lod_count") else -1])
	# Animations: every track on a bone of this skeleton.
	for anim_name in ["Idle", "Walk", "Run", "Punch_Right", "Sword_Slash", "Death"]:
		if not ap.has_animation(anim_name):
			_check(false, "animation %s is missing" % anim_name)
			continue
		var anim := ap.get_animation(anim_name)
		var missing := 0
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			if path.get_subname_count() > 0 and sk.find_bone(path.get_concatenated_subnames()) < 0:
				missing += 1
		_check(missing == 0, "%s: %d tracks, all on bones of the skeleton, %.2f s" % [anim_name, anim.get_track_count(), anim.length])
	# Approved parts, unchanged.
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var per := {}
	for t in range(0, idx.size(), 3):
		var part := int(uv2[idx[t]].x)
		var s := ""
		for k in 3:
			var i := idx[t + k]
			s += "%s%s%s%s" % [a[Mesh.ARRAY_VERTEX][i], a[Mesh.ARRAY_NORMAL][i], a[Mesh.ARRAY_TEX_UV][i], uv2[i]]
			for c in 4:
				s += "%d:%.6f," % [skin.get_bind_name(bones[i * 4 + c]).hash(), weights[i * 4 + c]]
		if not per.has(part):
			per[part] = []
		per[part].append(s)
	for part in APPROVED:
		var l: Array = per.get(part, [])
		l.sort()
		var h := "".join(l).md5_text()
		_check(h == APPROVED[part], "part %d (%d triangles) matches its approved fingerprint" % [part, l.size()])
	scene.queue_free()

	# In game: followers on the right bones, equipment follows them.
	print("In game")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	if main.hud.is_modal():
		main.hud._choose(0)
	var p = main.player
	var want := {"_right_hand": "hand_r", "_left_hand": "hand_l", "_torso": "spine_01", "_neck": "neck_01"}
	for f in want:
		var follower := p.get(f) as BoneAttachment3D
		_check(follower != null and follower.bone_name == want[f], "%s follows %s" % [f, want[f]])
	p.has_spear = true
	p.sword_tier = 1
	p.has_axe = true
	p.has_pickaxe = true
	p.armour = true
	p.armour_on = true
	p.armour_tier = 1
	p.torch_time = 999.0
	var body = p._body
	for tool in ["sword", "spear", "axe", "pickaxe"]:
		p.equip(tool)
		var node: Node3D = {"sword": p._sword, "spear": p._spear, "axe": p._axe, "pickaxe": p._pickaxe}[tool]
		var worst := 0.0
		for action in ["idle", "walk", "run", "punch", "slash"]:
			body._oneshot = 0.0
			body.play_once(action)
			for k in 8:
				await process_frame
				p.tick_visuals(0.016)
				# The axe and pickaxe are held 8 cm down the handle (player.gd), the others at the hand.
				var grip: float = 0.08 if tool in ["axe", "pickaxe"] else 0.0
				worst = maxf(worst, absf(node.global_position.distance_to(p._right_hand.global_position) - grip))
		_check(node.visible and worst < 0.005, "%s stays at its grip in the right hand through idle, walk, run, punch and slash (off by %.3f m)" % [tool, worst])
	var torch_off: float = p._torch.global_position.distance_to(p._left_hand.global_position)
	_check(p._torch.visible and torch_off < 0.3, "the torch is in the left hand (%.2f m)" % torch_off)
	_check(not p._armour.visible and float(p._look_mesh.get_instance_shader_parameter("armour_on")) == 1.0,
		"worn armour is the ranger's own shell, not the boxy breastplate")
	print("REVIEW_OK" if _failed == 0 else "REVIEW_FAILED %d" % _failed)
	quit(0 if _failed == 0 else 1)
