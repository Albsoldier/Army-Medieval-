## Phase 4E.5 (GRAPHICS_PHASE_4E5_EQUIPMENT_OPTIMIZATION.md): draws the kit
## that soldiers and raiders carry (spears, shields, helmets, axes, bows) with
## one MultiMesh per kind of piece, instead of one mesh instance per soldier
## per piece. A legion of 30 then draws its pila in one call, not 30.
##
## Nothing about the kit itself changes. Each piece is still the node that
## soldier.gd and raider.gd place on the body every frame. Its mesh instance
## stays in the tree, only hidden, and this draws the same mesh with the same
## material and shadow setting at that instance's transform, after the
## soldiers and raiders have moved. A piece is drawn only while its node is
## visible in the tree, so far-away soldiers (set_shown) and the dead are left
## out as before.
##
## Off with ?kitbatch=0 (or --kitbatch=0), to compare.
extends Node3D

static var enabled := true
## The batcher of the running game (main.gd makes it), or null.
static var current: Node3D

## key -> {"mmi": MultiMeshInstance3D, "items": Array of MeshInstance3D, "buffer": PackedFloat32Array}
var _groups := {}


func _ready() -> void:
	current = self
	# After main.gd, the soldiers and the raiders have placed their kit.
	process_priority = 1000


func _exit_tree() -> void:
	if current == self:
		current = null


## Draws a piece's meshes (its direct MeshInstance3D children) in the batches.
## Does nothing when batching is off or there is no running game.
static func adopt(piece: Node3D) -> void:
	if not enabled or current == null or piece == null:
		return
	for child in piece.get_children():
		var mi := child as MeshInstance3D
		if mi and mi.mesh and mi.visible:
			current.call("_add", mi)


func _add(mi: MeshInstance3D) -> void:
	var key := "%d:%d:%d" % [mi.mesh.get_instance_id(),
		mi.material_override.get_instance_id() if mi.material_override else 0, mi.cast_shadow]
	if not _groups.has(key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit%d" % _groups.size()
		mmi.multimesh = mm
		mmi.material_override = mi.material_override
		mmi.cast_shadow = mi.cast_shadow
		add_child(mmi)
		_groups[key] = {"mmi": mmi, "items": [], "buffer": PackedFloat32Array()}
	(_groups[key]["items"] as Array).append(mi)
	mi.visible = false


func _process(_delta: float) -> void:
	for key: String in _groups.keys():
		var group: Dictionary = _groups[key]
		var items: Array = group["items"]
		if items.is_empty():
			# No one carries this piece any more: let its mesh and textures go.
			(group["mmi"] as Node).queue_free()
			_groups.erase(key)
			continue
		var buffer: PackedFloat32Array = group["buffer"]
		var mm: MultiMesh = (group["mmi"] as MultiMeshInstance3D).multimesh
		var n := 0
		var i := 0
		while i < items.size():
			var mi = items[i]
			if not is_instance_valid(mi) or (mi as Node).is_queued_for_deletion() or (mi as Node).get_parent() == null:
				items.remove_at(i)
				continue
			i += 1
			var piece := (mi as Node).get_parent() as Node3D
			if not piece.is_visible_in_tree():
				continue
			if (n + 1) * 12 > buffer.size():
				buffer.resize(maxi(16, items.size() * 2) * 12)
			var t: Transform3D = (mi as MeshInstance3D).global_transform
			var k := n * 12
			buffer[k] = t.basis.x.x
			buffer[k + 1] = t.basis.y.x
			buffer[k + 2] = t.basis.z.x
			buffer[k + 3] = t.origin.x
			buffer[k + 4] = t.basis.x.y
			buffer[k + 5] = t.basis.y.y
			buffer[k + 6] = t.basis.z.y
			buffer[k + 7] = t.origin.y
			buffer[k + 8] = t.basis.x.z
			buffer[k + 9] = t.basis.y.z
			buffer[k + 10] = t.basis.z.z
			buffer[k + 11] = t.origin.z
			n += 1
		var capacity := buffer.size() / 12
		if n > 0:
			# The slots past the last piece repeat it, so the batch's bounds
			# (made from every slot) hold only the pieces being drawn.
			for s in range(n, capacity):
				for c in 12:
					buffer[s * 12 + c] = buffer[(n - 1) * 12 + c]
		if mm.instance_count != capacity:
			mm.instance_count = capacity
		if capacity > 0:
			mm.buffer = buffer
		mm.visible_instance_count = n
		group["buffer"] = buffer
		(group["mmi"] as MultiMeshInstance3D).visible = n > 0
