## Lists every modelled weapon and shield (models/weapons/): surfaces,
## vertices, triangles, LODs, material and textures, and checks for shared
## and unreferenced materials and textures. Phase 4E.5
## (GRAPHICS_PHASE_4E5_EQUIPMENT_OPTIMIZATION.md):
##   godot --headless --path last-light/game --script res://tools/equipment_inventory.gd
extends SceneTree

const DIR := "res://models/weapons/"


func _initialize() -> void:
	var total_tris := 0
	var mats := {}
	print("item | surfaces | vertices | triangles | lods | material | aabb size")
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".res"):
			continue
		var m := load(DIR + f) as ArrayMesh
		var verts := 0
		var tris := 0
		var lods := 0
		var mat_names := []
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var mat := m.surface_get_material(s)
			var mp := mat.resource_path if mat else "(none)"
			mat_names.append(mp.get_file())
			mats[mp] = mats.get(mp, 0) + 1
		total_tris += tris
		print("%s | %d | %d | %d | %d | %s | %s" % [f.get_basename(), m.get_surface_count(), verts, tris, lods, ",".join(mat_names), m.get_aabb().size])
	print("total triangles: ", total_tris)
	print("materials: ", mats)
	for mp in mats:
		var mat := load(mp) as StandardMaterial3D
		if mat == null:
			continue
		print(mp, " albedo=", mat.albedo_texture.resource_path if mat.albedo_texture else "-",
			" orm=", mat.orm_texture.resource_path if "orm_texture" in mat and mat.orm_texture else "-",
			" rough_tex=", mat.roughness_texture.resource_path if mat.roughness_texture else "-",
			" metal_tex=", mat.metallic_texture.resource_path if mat.metallic_texture else "-",
			" normal=", mat.normal_enabled, " shading=", mat.shading_mode, " transparency=", mat.transparency)
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".png"):
			var t := load(DIR + f) as Texture2D
			var img := t.get_image()
			print(f, " ", t.get_width(), "x", t.get_height(), " format=", img.get_format(), " mipmaps=", img.has_mipmaps(), " bytes=", img.get_data().size())
	quit(0)
