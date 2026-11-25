## Small helpers for building low-poly models out of Godot's primitive meshes.
extends RefCounted


static func material(color: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Adds a mesh to `parent` and returns it. Each part gets its own material.
static func part(parent: Node3D, mesh: Mesh, color: Color, offset: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, emission: float = 0.0, unshaded: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color, emission, unshaded)
	mi.position = offset
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func sphere(radius: float, rings: int = 4, segments: int = 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.rings = rings
	m.radial_segments = segments
	return m


## A cylinder, or a cone when `top` is 0.
static func cylinder(top: float, bottom: float, height: float, segments: int = 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 3
	return m


static func omni(color: Color, light_range: float, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = light_range
	light.light_energy = energy
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	return light


# ---------- Merging parts (fewer draw calls) ----------

static var _shared_vertex_mat: StandardMaterial3D
static var _shared_mats: Dictionary = {}  # "colour|emission|unshaded" -> material


## One material for every merged part: the part colours are in the vertices.
## Renders exactly like material(colour) (vertex colour as sRGB, roughness 0.9).
static func vertex_colour_material() -> StandardMaterial3D:
	if _shared_vertex_mat == null:
		_shared_vertex_mat = StandardMaterial3D.new()
		_shared_vertex_mat.vertex_color_use_as_albedo = true
		_shared_vertex_mat.vertex_color_is_srgb = true
		_shared_vertex_mat.roughness = 0.9
	return _shared_vertex_mat


## material(), but one shared copy per colour and style. Only for parts whose
## material is never changed afterwards.
static func shared_material(color: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(true), emission, unshaded]
	if not _shared_mats.has(key):
		_shared_mats[key] = material(color, emission, unshaded)
	return _shared_mats[key]


## Merges `parts` (MeshInstance3D children of `node`, made by part()) into one
## mesh drawn with one shared material, each part keeping its colour, place
## and turn. Glowing and unshaded parts can't share it: they stay separate, on
## shared materials. Returns the meshes `node` is now drawn with.
static func bake(node: Node3D, parts: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var kept := []
	var merged := 0
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for p in parts:
		var mi := p as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		var plain: bool = mi.get_parent() == node and mi.mesh != null and mat != null \
			and not mat.emission_enabled and mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(mat.roughness, 0.9) and mi.visible
		if not plain:
			if mat != null and mi.mesh != null and not mat.transparency:
				mi.material_override = shared_material(mat.albedo_color, mat.emission_energy_multiplier if mat.emission_enabled else 0.0,
					mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
			kept.append(mi)
			continue
		var arrays: Array = (mi.mesh as PrimitiveMesh).get_mesh_arrays() if mi.mesh is PrimitiveMesh else mi.mesh.surface_get_arrays(0)
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pi: Variant = arrays[Mesh.ARRAY_INDEX]
		var xf := mi.transform
		var nb := xf.basis.inverse().transposed()
		var first := verts.size()
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((nb * pn[i]).normalized())
			colors.append(mat.albedo_color)
		if pi == null:
			for i in pv.size():
				indices.append(first + i)
		else:
			for i in (pi as PackedInt32Array):
				indices.append(first + i)
		shadow = mi.cast_shadow
		merged += 1
		node.remove_child(mi)
		mi.queue_free()
	if merged == 0:
		return kept
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	var baked := MeshInstance3D.new()
	baked.name = "Baked"
	baked.mesh = mesh
	baked.material_override = vertex_colour_material()
	baked.cast_shadow = shadow
	node.add_child(baked)
	kept.push_front(baked)
	return kept


## Every part() made directly under `node` (MeshInstance3D children with a material).
static func parts_of(node: Node3D) -> Array:
	return node.get_children().filter(func(c): return c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D)
