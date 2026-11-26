## Prints a fingerprint of each part of the player model (models/player/ranger.scn):
## its triangle count and an MD5 of every vertex (position, normal, UVs, bone
## names and weights), by the part labels in UV2 (character_atlas.gdshader).
## Run it before and after rebuilding the model to prove which parts changed:
## the hood work (GRAPHICS_PLAYER_HOOD.md) left the approved armour (part 4)
## identical.
##   godot --headless --path last-light/game --script res://tools/model_parts_hash.gd
extends SceneTree
func _initialize():
	var root: Node = load("res://models/player/ranger.scn").instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var a := mi.mesh.surface_get_arrays(0)
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
				s += "%d:%.6f," % [mi.skin.get_bind_name(a[Mesh.ARRAY_BONES][i * 4 + c]).hash(), a[Mesh.ARRAY_WEIGHTS][i * 4 + c]]
		if not per.has(part): per[part] = []
		per[part].append(s)
	var keys := per.keys(); keys.sort()
	for p in keys:
		var l: Array = per[p]; l.sort()
		print("part ", p, " tris ", l.size(), " hash ", "".join(l).md5_text())
	quit()
