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
