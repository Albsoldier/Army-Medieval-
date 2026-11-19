## The island: terrain generated from the daily seed, plus harvestable props
## (trees, rocks, berry bushes). Everything is deterministic for a seed, so
## every player on the same day gets the same island.
##
## Game logic works on a flat grid in "pixels" (TILE pixels per tile), which is
## also what the server stores. In 3D, one tile is one metre: see to_3d().
extends Node3D

const TILE := 16
const SIZE := 160
const NO_CELL := Vector2i(-1, -1)
const WATER_LEVEL := 0.0

enum { DEEP, WATER, SAND, GRASS, FOREST, ROCK }

const TERRAIN_COLORS := [
	Color("1d3b5c"),  # deep water (seabed)
	Color("3d6f7a"),  # shallow water (seabed)
	Color("d9c48a"),  # sand
	Color("6f9e48"),  # grass
	Color("4c7a36"),  # forest floor
	Color("8a8577"),  # rock
]

## Each prop type is drawn with one or more parts. A part is a mesh with an
## offset, scale and colour, instanced for every prop of that type.
const PROP_TYPES := ["tree", "stump", "rock", "bush", "bush_empty"]

var seed_value := 0
var terrain := PackedByteArray()
var elevation := PackedFloat32Array()
var corner_heights := PackedFloat32Array()  # (SIZE + 1) * (SIZE + 1)
## Vector2i cell -> {"type": String, "hp": int, "regrow_day": int}
var props: Dictionary = {}
var spawn_cell := Vector2i.ZERO

var _layers: Dictionary = {}  # prop type -> Array of [MultiMeshInstance3D, part definition]


func generate(p_seed: int) -> void:
	seed_value = p_seed
	terrain.resize(SIZE * SIZE)
	elevation.resize(SIZE * SIZE)
	props.clear()

	var noise := FastNoiseLite.new()
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 4

	var moisture := FastNoiseLite.new()
	moisture.seed = p_seed + 7919
	moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture.frequency = 0.045

	var center := Vector2(SIZE, SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(center) / (SIZE * 0.5)
			var e := noise.get_noise_2d(x, y) * 0.5 + 0.5
			e = e + 0.38 - d * d * 1.2
			var t := GRASS
			if d > 0.96 or e < 0.12:
				t = DEEP
			elif e < 0.26:
				t = WATER
			elif e < 0.32:
				t = SAND
			elif e > 0.9:
				t = ROCK
			elif moisture.get_noise_2d(x, y) > 0.12:
				t = FOREST
			terrain[y * SIZE + x] = t
			elevation[y * SIZE + x] = e

	_compute_heights()
	_find_spawn()
	_place_props()
	_build_terrain()
	_build_water()
	_build_prop_layers()
	refresh_props(PROP_TYPES)


# ---------- Queries used by the game logic ----------

func terrain_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return DEEP
	return terrain[cell.y * SIZE + cell.x]


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


func is_land(cell: Vector2i) -> bool:
	var t := terrain_at(cell)
	return t != DEEP and t != WATER


func is_walkable(pos: Vector2) -> bool:
	var cell := cell_of(pos)
	if not is_land(cell):
		return false
	if props.has(cell):
		var kind: String = props[cell]["type"]
		if kind == "tree" or kind == "rock":
			return false
	return true


func world_size_px() -> int:
	return SIZE * TILE


## Ground height in metres at a game position.
func height_at(pos: Vector2) -> float:
	var fx := clampf(pos.x / TILE, 0.0, SIZE - 0.001)
	var fz := clampf(pos.y / TILE, 0.0, SIZE - 0.001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _corner(ix, iz)
	var h10 := _corner(ix + 1, iz)
	var h01 := _corner(ix, iz + 1)
	var h11 := _corner(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Converts a game position (pixels on the grid) to a point on the 3D ground.
func to_3d(pos: Vector2) -> Vector3:
	return Vector3(pos.x / TILE, height_at(pos), pos.y / TILE)


## Returns the closest harvestable prop within `radius` pixels, or NO_CELL.
func find_prop_near(pos: Vector2, radius: float) -> Vector2i:
	var best := NO_CELL
	var best_dist := radius
	var base := cell_of(pos)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := base + Vector2i(dx, dy)
			if not props.has(cell):
				continue
			var kind: String = props[cell]["type"]
			if kind == "stump" or kind == "bush_empty":
				continue
			var dist := pos.distance_to(cell_center(cell))
			if dist < best_dist:
				best_dist = dist
				best = cell
	return best


func prop_type(cell: Vector2i) -> String:
	if not props.has(cell):
		return ""
	return str(props[cell]["type"])


## Hits a prop once. Returns the items gained, e.g. {"wood": 1}.
func harvest(cell: Vector2i, day: int) -> Dictionary:
	if not props.has(cell):
		return {}
	var prop: Dictionary = props[cell]
	var gained := {}
	match str(prop["type"]):
		"tree":
			gained = {"wood": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				prop["type"] = "stump"
				refresh_props(["tree", "stump"])
		"rock":
			gained = {"stone": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				props.erase(cell)
				refresh_props(["rock"])
		"bush":
			gained = {"berries": 3}
			prop["type"] = "bush_empty"
			prop["regrow_day"] = day + 2
			refresh_props(["bush", "bush_empty"])
	return gained


## Berry bushes come back after a couple of days.
func regrow(day: int) -> void:
	var changed := false
	for cell in props:
		var prop: Dictionary = props[cell]
		if prop["type"] == "bush_empty" and int(prop["regrow_day"]) <= day:
			prop["type"] = "bush"
			changed = true
	if changed:
		refresh_props(["bush", "bush_empty"])


## A random walkable point between min_r and max_r pixels from `origin`,
## or Vector2.INF if none was found.
func random_walkable_near(origin: Vector2, min_r: float, max_r: float, rng: RandomNumberGenerator) -> Vector2:
	for i in 24:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var pos := origin + Vector2.from_angle(angle) * r
		if is_walkable(pos):
			return pos
	return Vector2.INF


func land_tile_count() -> int:
	var count := 0
	for t in terrain:
		if t != DEEP and t != WATER:
			count += 1
	return count


# ---------- Generation ----------

func _tile_height(t: int, e: float) -> float:
	if t == DEEP:
		return -2.4
	if t == WATER:
		return -0.8
	if t == SAND:
		return 0.12 + (e - 0.26) * 1.2
	if t == ROCK:
		return minf(1.1 + (e - 0.9) * 9.0, 4.5)
	return 0.24 + (e - 0.32) * 1.6


## Heights live on tile corners, averaged from the tiles around each corner,
## which gives smooth hills and beaches that slope into the sea.
func _compute_heights() -> void:
	corner_heights.resize((SIZE + 1) * (SIZE + 1))
	for cz in SIZE + 1:
		for cx in SIZE + 1:
			var total := 0.0
			for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var x: int = cx + o.x
				var z: int = cz + o.y
				if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
					total += -2.4
				else:
					total += _tile_height(terrain[z * SIZE + x], elevation[z * SIZE + x])
			corner_heights[cz * (SIZE + 1) + cx] = total / 4.0


func _corner(x: int, z: int) -> float:
	x = clampi(x, 0, SIZE)
	z = clampi(z, 0, SIZE)
	return corner_heights[z * (SIZE + 1) + x]


func _find_spawn() -> void:
	# The grass tile closest to the middle of the island.
	var center := Vector2(SIZE, SIZE) * 0.5
	var best_dist := INF
	spawn_cell = Vector2i(SIZE / 2, SIZE / 2)
	for y in SIZE:
		for x in SIZE:
			if terrain[y * SIZE + x] != GRASS:
				continue
			var dist := Vector2(x, y).distance_squared_to(center)
			if dist < best_dist:
				best_dist = dist
				spawn_cell = Vector2i(x, y)


func _place_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 17
	for y in SIZE:
		for x in SIZE:
			var cell := Vector2i(x, y)
			if cell.distance_to(spawn_cell) < 3.0:
				continue
			var roll := rng.randf()
			var kind := ""
			match terrain[y * SIZE + x]:
				FOREST:
					if roll < 0.32:
						kind = "tree"
					elif roll < 0.35:
						kind = "bush"
				GRASS:
					if roll < 0.035:
						kind = "tree"
					elif roll < 0.06:
						kind = "bush"
					elif roll < 0.07:
						kind = "rock"
				ROCK:
					if roll < 0.22:
						kind = "rock"
				SAND:
					if roll < 0.012:
						kind = "rock"
			if kind != "":
				props[cell] = {"type": kind, "hp": 3, "regrow_day": 0}


# ---------- 3D building ----------

func _build_terrain() -> void:
	# One flat-shaded quad per tile, coloured by terrain, for a low-poly look.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in SIZE:
		for x in SIZE:
			var t := terrain[z * SIZE + x]
			var color: Color = TERRAIN_COLORS[t]
			var h := _hash01(x, z, 1)
			if t == SAND or t == GRASS or t == FOREST or t == ROCK:
				color = color.darkened(h * 0.12)
			if t == SAND and _touches_water(x, z):
				color = color.darkened(0.1)
			st.set_color(color)
			var a := Vector3(x, _corner(x, z), z)
			var b := Vector3(x + 1, _corner(x + 1, z), z)
			var c := Vector3(x + 1, _corner(x + 1, z + 1), z + 1)
			var d := Vector3(x, _corner(x, z + 1), z + 1)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # our colours are sRGB, like everywhere else in Godot
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.name = "Terrain"
	terrain_mesh.mesh = st.commit()
	terrain_mesh.material_override = mat
	add_child(terrain_mesh)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE * 4, SIZE * 4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.42, 0.58, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.material_override = mat
	water.position = Vector3(SIZE * 0.5, WATER_LEVEL, SIZE * 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# Dark seabed far out, so the open sea doesn't look empty.
	var bed := MeshInstance3D.new()
	var bed_plane := PlaneMesh.new()
	bed_plane.size = Vector2(SIZE * 4, SIZE * 4)
	bed.mesh = bed_plane
	bed.material_override = _flat_material(Color("15304d"))
	bed.position = Vector3(SIZE * 0.5, -2.45, SIZE * 0.5)
	add_child(bed)


func _part(mesh: Mesh, color: Color, offset: Vector3, size: Vector3 = Vector3.ONE) -> Dictionary:
	return {"mesh": mesh, "color": color, "offset": offset, "scale": size}


func _prop_parts() -> Dictionary:
	var berry := _sphere(0.075, 3, 6)
	return {
		"tree": [
			_part(_cylinder(0.11, 0.16, 1.0, 6), Color("5a3d22"), Vector3(0, 0.5, 0)),
			_part(_cylinder(0.0, 0.8, 1.3, 7), Color("1f4a27"), Vector3(0, 1.35, 0)),
			_part(_cylinder(0.0, 0.6, 1.1, 7), Color("2c6234"), Vector3(0, 2.0, 0)),
			_part(_cylinder(0.0, 0.38, 0.8, 7), Color("3a7a40"), Vector3(0, 2.55, 0)),
		],
		"stump": [
			_part(_cylinder(0.17, 0.2, 0.28, 7), Color("5a3d22"), Vector3(0, 0.14, 0)),
			_part(_cylinder(0.15, 0.15, 0.02, 7), Color("b08a5a"), Vector3(0, 0.29, 0)),
		],
		"rock": [
			_part(_sphere(0.55, 3, 6), Color("77746c"), Vector3(0, 0.15, 0), Vector3(1.0, 0.75, 0.9)),
			_part(_sphere(0.3, 3, 5), Color("8d8a80"), Vector3(0.35, 0.1, 0.25), Vector3(1.0, 0.8, 1.0)),
		],
		"bush": [
			_part(_sphere(0.42, 3, 7), Color("2e5a2a"), Vector3(0, 0.32, 0), Vector3(1.0, 0.85, 1.0)),
			_part(berry, Color("d6334a"), Vector3(0.28, 0.45, 0.12)),
			_part(berry, Color("d6334a"), Vector3(-0.2, 0.5, 0.22)),
			_part(berry, Color("e0405a"), Vector3(0.05, 0.62, -0.25)),
			_part(berry, Color("c42a40"), Vector3(-0.3, 0.35, -0.12)),
		],
		"bush_empty": [
			_part(_sphere(0.36, 3, 7), Color("4a6a38"), Vector3(0, 0.27, 0), Vector3(1.0, 0.8, 1.0)),
		],
	}


func _build_prop_layers() -> void:
	var parts := _prop_parts()
	for kind in PROP_TYPES:
		var layers := []
		for p in parts[kind]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = p["mesh"]
			var inst := MultiMeshInstance3D.new()
			inst.name = "Props_%s" % kind
			inst.multimesh = mm
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.95
			inst.material_override = mat
			add_child(inst)
			layers.append([inst, p])
		_layers[kind] = layers


## Rebuilds the 3D instances for the given prop types after props change.
func refresh_props(kinds: Array) -> void:
	var cells_by_kind := {}
	for kind in kinds:
		cells_by_kind[kind] = []
	for cell in props:
		var kind: String = props[cell]["type"]
		if cells_by_kind.has(kind):
			cells_by_kind[kind].append(cell)
	for kind in kinds:
		if not _layers.has(kind):
			continue
		var cells: Array = cells_by_kind[kind]
		for layer in _layers[kind]:
			var inst: MultiMeshInstance3D = layer[0]
			var p: Dictionary = layer[1]
			var mm := inst.multimesh
			mm.instance_count = cells.size()
			var base_color: Color = p["color"]
			var offset: Vector3 = p["offset"]
			var part_scale: Vector3 = p["scale"]
			for i in cells.size():
				var cell: Vector2i = cells[i]
				var yaw := _hash01(cell.x, cell.y, 2) * TAU
				var s := 0.8 + _hash01(cell.x, cell.y, 3) * 0.45
				var jitter := Vector3(_hash01(cell.x, cell.y, 4) - 0.5, 0, _hash01(cell.x, cell.y, 5) - 0.5) * 0.35
				var origin := Vector3(cell.x + 0.5, 0, cell.y + 0.5) + jitter
				origin.y = height_at(Vector2(origin.x, origin.z) * TILE) - 0.05
				var turn := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * s)
				var xform := Transform3D(turn * Basis.from_scale(part_scale), origin + turn * offset)
				mm.set_instance_transform(i, xform)
				var shade := (_hash01(cell.x, cell.y, 6) - 0.5) * 0.18
				mm.set_instance_color(i, base_color.lightened(shade) if shade > 0.0 else base_color.darkened(-shade))


func _touches_water(x: int, y: int) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := terrain_at(Vector2i(x, y) + offset)
		if t == WATER or t == DEEP:
			return true
	return false


func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (seed_value * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h ^ (h >> 16)) % 10000) / 10000.0


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _sphere(radius: float, rings: int, segments: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.rings = rings
	m.radial_segments = segments
	return m


func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m
