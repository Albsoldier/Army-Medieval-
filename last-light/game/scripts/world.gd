## The island: one large, permanent island generated from a fixed seed.
##
## The island is too big to build in one go (SIZE x SIZE tiles), so it is split
## into CHUNK x CHUNK chunks. Terrain data is generated on demand, and 3D meshes
## and props are only built for the chunks around the player.
##
## Trees, rocks and bushes come from the seed. Only the props a player has
## changed are stored, in `prop_changes`, which the save file keeps.
##
## Game logic works on a flat grid in "pixels" (TILE pixels per tile), which is
## also what the server stores. In 3D, one tile is one metre: see to_3d().
extends Node3D

const TILE := 16
const SIZE := 1024  # tiles per side: about a kilometre
const CHUNK := 32
const VIEW := 2  # chunks drawn around the player in each direction
const BUILDS_PER_FRAME := 2
const NO_CELL := Vector2i(-1, -1)
const WATER_LEVEL := 0.0

enum { DEEP, WATER, SAND, GRASS, FOREST, ROCK }

const TERRAIN_COLORS := [
	Color("1d3b5c"),  # deep water (seabed)
	Color("3d6f7a"),  # shallow water (seabed)
	Color("c7ae74"),  # sand (a little darker, so beaches don't wash out at midday)
	Color("6f9e48"),  # grass
	Color("4c7a36"),  # forest floor
	Color("8a8577"),  # rock
]

## Prop types that are drawn. "rubble" is what's left of a broken rock.
const PROP_TYPES := ["tree", "stump", "rock", "iron_rock", "rubble", "bush", "bush_empty"]
## Saved prop changes may also be "cleared": the ground under a building.
const CHANGE_TYPES := ["tree", "stump", "rock", "iron_rock", "rubble", "bush", "bush_empty", "cleared"]
## Props you can build over (they are cleared for good).
const BUILD_OVER := ["", "stump", "rubble", "bush_empty", "cleared"]
## Days before something you used grows back.
const REGROW_DAYS := {"stump": 5, "rubble": 6, "bush_empty": 2}

var seed_value := 0
var spawn_cell := Vector2i.ZERO
## Vector2i cell -> {"type": String, "hp": int, "regrow_day": int}. Saved.
var prop_changes: Dictionary = {}
## Vector2i cell -> structure type, for everything the player built. The 3D
## nodes and their hit points live in main.gd.
var structures: Dictionary = {}
## Places to discover: Array of {"id", "type", "cell", "name", "seed"}. Fixed by the seed.
var pois: Array = []
## The explored map: one pixel per MAP_SCALE tiles, dark until explored.
var map_image: Image
var map_texture: ImageTexture
var explored: Dictionary = {}  # Vector2i chunk -> true

const MAP_SCALE := 4  # tiles per map pixel
const UNEXPLORED := Color(0.07, 0.09, 0.12)
const POI_COUNTS := {"lighthouse": 2, "shipwreck": 4, "ruins": 6, "cave": 4, "shrine": 4, "camp": 6}
var _poi_cells: Dictionary = {}  # cells kept clear around places to discover
var _poi_centers: Dictionary = {}  # Vector2i cell -> poi id (these tiles can't be walked through)
var _map_dirty := false
var _map_timer := 0.0

var _noise: FastNoiseLite
var _continent: FastNoiseLite
var _moisture: FastNoiseLite
var _data: Dictionary = {}  # chunk -> {"t": PackedByteArray, "e": PackedFloat32Array}
var _corners: Dictionary = {}  # chunk -> PackedFloat32Array of (CHUNK + 1)^2 corner heights
var _base_props: Dictionary = {}  # chunk -> {Vector2i cell: String type}
var _meshes: Dictionary = {}  # chunk -> MeshInstance3D
var _build_queue: Array = []
var _view_chunk := Vector2i(-999, -999)
var _props_dirty := true
var _layers: Dictionary = {}  # prop type -> Array of [MultiMeshInstance3D, part definition]
var _terrain_mat: StandardMaterial3D
var _water: MeshInstance3D
var _bed: MeshInstance3D


func generate(p_seed: int) -> void:
	seed_value = p_seed
	_data.clear()
	_corners.clear()
	_base_props.clear()
	prop_changes.clear()

	_noise = FastNoiseLite.new()
	_noise.seed = p_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.03
	_noise.fractal_octaves = 4

	# Large shapes: bays, lakes, headlands and mountain ranges.
	_continent = FastNoiseLite.new()
	_continent.seed = p_seed + 4049
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = 0.004
	_continent.fractal_octaves = 3

	_moisture = FastNoiseLite.new()
	_moisture.seed = p_seed + 7919
	_moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture.frequency = 0.02

	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.vertex_color_is_srgb = true
	_terrain_mat.roughness = 1.0
	_terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_find_spawn()
	_place_pois()
	map_image = Image.create(SIZE / MAP_SCALE, SIZE / MAP_SCALE, false, Image.FORMAT_RGBA8)
	map_image.fill(UNEXPLORED)
	map_texture = ImageTexture.create_from_image(map_image)
	explored.clear()
	_build_water()
	_build_prop_layers()


## Builds the terrain and props around `pos`. Call every frame; it spreads the
## work over several frames. `immediate` builds everything at once.
func update_view(pos: Vector2, immediate: bool = false) -> void:
	var center := _chunk_of_cell(cell_of(pos))
	var ground := to_3d(pos)
	_water.position = Vector3(snappedf(ground.x, 8.0), WATER_LEVEL, snappedf(ground.z, 8.0))
	_bed.position = Vector3(_water.position.x, -2.45, _water.position.z)

	if center != _view_chunk:
		_view_chunk = center
		_props_dirty = true
		_build_queue.clear()
		var wanted := {}
		for dz in range(-VIEW, VIEW + 1):
			for dx in range(-VIEW, VIEW + 1):
				var ck := center + Vector2i(dx, dz)
				if _chunk_in_bounds(ck):
					wanted[ck] = true
					if not _meshes.has(ck):
						_build_queue.append(ck)
		_build_queue.sort_custom(_nearer_to_view)  # nearest chunks first
		for ck in _meshes.keys():
			var far: Vector2i = (ck - center).abs()
			if maxi(far.x, far.y) > VIEW + 1:
				_meshes[ck].queue_free()
				_meshes.erase(ck)

	var budget := _build_queue.size() if immediate else BUILDS_PER_FRAME
	while budget > 0 and not _build_queue.is_empty():
		var ck: Vector2i = _build_queue.pop_front()
		if not _meshes.has(ck):
			_build_chunk_mesh(ck)
		budget -= 1

	if _props_dirty:
		_props_dirty = false
		_refresh_props()

	# Reveal the map around the player.
	for dz in range(-VIEW, VIEW + 1):
		for dx in range(-VIEW, VIEW + 1):
			var ck := center + Vector2i(dx, dz)
			if _chunk_in_bounds(ck) and not explored.has(ck):
				explored[ck] = true
				_paint_chunk(ck, true)
	_map_timer += get_process_delta_time()
	if _map_dirty and (_map_timer > 0.5 or immediate):
		_map_dirty = false
		_map_timer = 0.0
		map_texture.update(map_image)


func _nearer_to_view(a: Vector2i, b: Vector2i) -> bool:
	return (a - _view_chunk).length_squared() < (b - _view_chunk).length_squared()


# ---------- Queries used by the game logic ----------

func terrain_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return DEEP
	var ck := _chunk_of_cell(cell)
	var data: Dictionary = _chunk_data(ck)
	var t: PackedByteArray = data["t"]
	return t[(cell.y - ck.y * CHUNK) * CHUNK + (cell.x - ck.x * CHUNK)]


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


func is_land(cell: Vector2i) -> bool:
	var t := terrain_at(cell)
	return t != DEEP and t != WATER


## Whether a creature can stand at `pos`. Gates let people through but not wolves.
func is_walkable(pos: Vector2, wolf: bool = false) -> bool:
	var cell := cell_of(pos)
	if not is_land(cell):
		return false
	if structures.has(cell):
		return structures[cell] == "gate" and not wolf
	if _poi_centers.has(cell):
		return false
	var kind := prop_type(cell)
	return kind != "tree" and kind != "rock" and kind != "iron_rock"


func can_build(cell: Vector2i) -> bool:
	return is_land(cell) and not structures.has(cell) and not _poi_cells.has(cell) and prop_type(cell) in BUILD_OVER


func add_structure(cell: Vector2i, kind: String) -> void:
	structures[cell] = kind
	if prop_type(cell) != "" and prop_type(cell) != "cleared":
		prop_changes[cell] = {"type": "cleared", "hp": 0, "regrow_day": 0}
		_props_dirty = true


func remove_structure(cell: Vector2i) -> void:
	structures.erase(cell)


func world_size_px() -> int:
	return SIZE * TILE


## Ground height in metres at a game position.
func height_at(pos: Vector2) -> float:
	var fx := clampf(pos.x / TILE, 0.0, SIZE - 0.001)
	var fz := clampf(pos.y / TILE, 0.0, SIZE - 0.001)
	var ix := floori(fx)
	var iz := floori(fz)
	var ck := _chunk_of_cell(Vector2i(ix, iz))
	var corners := _chunk_corners(ck)
	var lx := ix - ck.x * CHUNK
	var lz := iz - ck.y * CHUNK
	var w := CHUNK + 1
	var tx := fx - ix
	var tz := fz - iz
	var h00 := corners[lz * w + lx]
	var h10 := corners[lz * w + lx + 1]
	var h01 := corners[(lz + 1) * w + lx]
	var h11 := corners[(lz + 1) * w + lx + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Converts a game position (pixels on the grid) to a point on the 3D ground.
func to_3d(pos: Vector2) -> Vector3:
	return Vector3(pos.x / TILE, height_at(pos), pos.y / TILE)


## The prop on a cell as {"type", "hp", "regrow_day"}, or {} if there is none.
func get_prop(cell: Vector2i) -> Dictionary:
	if prop_changes.has(cell):
		return prop_changes[cell]
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return {}
	var base: Dictionary = _chunk_props(_chunk_of_cell(cell))
	if not base.has(cell):
		return {}
	return {"type": base[cell], "hp": 3, "regrow_day": 0}


func prop_type(cell: Vector2i) -> String:
	return str(get_prop(cell).get("type", ""))


## Returns the closest harvestable prop within `radius` pixels, or NO_CELL.
func find_prop_near(pos: Vector2, radius: float) -> Vector2i:
	var best := NO_CELL
	var best_dist := radius
	var base := cell_of(pos)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := base + Vector2i(dx, dy)
			var kind := prop_type(cell)
			if kind != "tree" and kind != "rock" and kind != "iron_rock" and kind != "bush":
				continue
			var dist := pos.distance_to(cell_center(cell))
			if dist < best_dist:
				best_dist = dist
				best = cell
	return best


## Hits a prop once. Returns the items gained, e.g. {"wood": 1}.
func harvest(cell: Vector2i, day: int) -> Dictionary:
	var prop := get_prop(cell).duplicate()
	if prop.is_empty():
		return {}
	var gained := {}
	match str(prop["type"]):
		"tree":
			gained = {"wood": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				prop["type"] = "stump"
		"rock":
			gained = {"stone": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				prop["type"] = "rubble"
		"iron_rock":
			gained = {"ore": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				prop["type"] = "rubble"
		"bush":
			gained = {"berries": 3}
			prop["type"] = "bush_empty"
		_:
			return {}
	if REGROW_DAYS.has(prop["type"]):
		prop["regrow_day"] = day + int(REGROW_DAYS[prop["type"]])
		_props_dirty = true
	prop_changes[cell] = prop
	return gained


## Felled trees, broken rocks and picked bushes grow back after a few days.
func regrow(day: int) -> void:
	for cell in prop_changes.keys():
		var regrow_day := int(prop_changes[cell].get("regrow_day", 0))
		if regrow_day > 0 and regrow_day <= day:
			prop_changes.erase(cell)
			_props_dirty = true


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


## Number of seed props in the chunks generated so far (used by tests).
func loaded_prop_count() -> int:
	var count := 0
	for ck in _base_props:
		count += _base_props[ck].size()
	return count


# ---------- Saving ----------

func export_changes() -> Dictionary:
	var out := {}
	for cell in prop_changes:
		var p: Dictionary = prop_changes[cell]
		out["%d,%d" % [cell.x, cell.y]] = [p["type"], int(p["hp"]), int(p["regrow_day"])]
	return out


func import_changes(data: Dictionary) -> void:
	prop_changes.clear()
	for key in data:
		var parts := str(key).split(",")
		var v: Variant = data[key]
		if parts.size() != 2 or typeof(v) != TYPE_ARRAY or v.size() < 3:
			continue
		var kind := str(v[0])
		if not kind in CHANGE_TYPES:
			continue
		prop_changes[Vector2i(parts[0].to_int(), parts[1].to_int())] = {
			"type": kind, "hp": int(v[1]), "regrow_day": int(v[2]),
		}
	_props_dirty = true


# ---------- Generation ----------

func _chunk_of_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))


func _chunk_in_bounds(ck: Vector2i) -> bool:
	return ck.x >= 0 and ck.y >= 0 and ck.x * CHUNK < SIZE and ck.y * CHUNK < SIZE


## Terrain type and elevation for one tile, straight from the noise.
func _sample(x: int, z: int) -> Array:
	var half := SIZE * 0.5
	var d := Vector2(x - half, z - half).length() / half
	var big := _continent.get_noise_2d(x, z) * 0.5 + 0.5
	var detail := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	var e := big * 0.55 + detail * 0.45 + 0.3 - d * d * 1.25
	var t := GRASS
	if d > 0.97 or e < 0.12:
		t = DEEP
	elif e < 0.26:
		t = WATER
	elif e < 0.32:
		t = SAND
	elif e > 0.9:
		t = ROCK
	elif _moisture.get_noise_2d(x, z) > 0.05:
		t = FOREST
	return [t, e]


func _chunk_data(ck: Vector2i) -> Dictionary:
	if _data.has(ck):
		return _data[ck]
	var t := PackedByteArray()
	t.resize(CHUNK * CHUNK)
	var e := PackedFloat32Array()
	e.resize(CHUNK * CHUNK)
	for lz in CHUNK:
		for lx in CHUNK:
			var s := _sample(ck.x * CHUNK + lx, ck.y * CHUNK + lz)
			t[lz * CHUNK + lx] = s[0]
			e[lz * CHUNK + lx] = s[1]
	var data := {"t": t, "e": e}
	_data[ck] = data
	return data


func _tile_height(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
		return -2.4
	var ck := Vector2i(x / CHUNK, z / CHUNK)
	var data: Dictionary = _chunk_data(ck)
	var i := (z - ck.y * CHUNK) * CHUNK + (x - ck.x * CHUNK)
	var t: int = data["t"][i]
	var e: float = data["e"][i]
	if t == DEEP:
		return -2.4
	if t == WATER:
		return -0.8
	if t == SAND:
		return 0.12 + (e - 0.26) * 1.2
	if t == ROCK:
		return minf(1.1 + (e - 0.9) * 9.0, 4.5)
	return 0.24 + (e - 0.32) * 1.6


## Heights live on tile corners, averaged from the four tiles around each
## corner, which gives smooth hills and beaches that slope into the sea.
func _chunk_corners(ck: Vector2i) -> PackedFloat32Array:
	if _corners.has(ck):
		return _corners[ck]
	var w := CHUNK + 1
	var corners := PackedFloat32Array()
	corners.resize(w * w)
	for cz in w:
		for cx in w:
			var x := ck.x * CHUNK + cx
			var z := ck.y * CHUNK + cz
			corners[cz * w + cx] = (_tile_height(x - 1, z - 1) + _tile_height(x, z - 1)
				+ _tile_height(x - 1, z) + _tile_height(x, z)) / 4.0
	_corners[ck] = corners
	return corners


func _chunk_props(ck: Vector2i) -> Dictionary:
	if _base_props.has(ck):
		return _base_props[ck]
	var props := {}
	var data: Dictionary = _chunk_data(ck)
	var types: PackedByteArray = data["t"]
	for lz in CHUNK:
		for lx in CHUNK:
			var cell := Vector2i(ck.x * CHUNK + lx, ck.y * CHUNK + lz)
			if cell.distance_to(spawn_cell) < 3.0 or _poi_cells.has(cell):
				continue
			var roll := _hash01(cell.x, cell.y, 7)
			var kind := ""
			match types[lz * CHUNK + lx]:
				FOREST:
					if roll < 0.3:
						kind = "tree"
					elif roll < 0.33:
						kind = "bush"
				GRASS:
					if roll < 0.03:
						kind = "tree"
					elif roll < 0.055:
						kind = "bush"
					elif roll < 0.065:
						kind = "rock"
					elif roll < 0.067:
						kind = "iron_rock"
				ROCK:
					if roll < 0.035:
						kind = "iron_rock"
					elif roll < 0.2:
						kind = "rock"
				SAND:
					if roll < 0.012:
						kind = "rock"
			if kind != "":
				props[cell] = kind
	_base_props[ck] = props
	return props


func _find_spawn() -> void:
	# The grass tile closest to the middle of the island.
	var center := Vector2i(SIZE / 2, SIZE / 2)
	spawn_cell = center
	for r in range(0, 200):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cell := center + Vector2i(dx, dz)
				if terrain_at(cell) == GRASS:
					spawn_cell = cell
					return


# ---------- 3D building ----------

func _build_chunk_mesh(ck: Vector2i) -> void:
	# One flat-shaded quad per tile, coloured by terrain, for a low-poly look.
	var data: Dictionary = _chunk_data(ck)
	var types: PackedByteArray = data["t"]
	var corners := _chunk_corners(ck)
	var w := CHUNK + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lz in CHUNK:
		for lx in CHUNK:
			var x := ck.x * CHUNK + lx
			var z := ck.y * CHUNK + lz
			var t := types[lz * CHUNK + lx]
			if t == DEEP and corners[lz * w + lx] < -2.3 and corners[(lz + 1) * w + lx + 1] < -2.3:
				continue  # open sea: the seabed plane covers it
			var color: Color = TERRAIN_COLORS[t]
			if t == SAND or t == GRASS or t == FOREST or t == ROCK:
				color = color.darkened(_hash01(x, z, 1) * 0.12)
			st.set_color(color)
			var a := Vector3(x, corners[lz * w + lx], z)
			var b := Vector3(x + 1, corners[lz * w + lx + 1], z)
			var c := Vector3(x + 1, corners[(lz + 1) * w + lx + 1], z + 1)
			var d := Vector3(x, corners[(lz + 1) * w + lx], z + 1)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [ck.x, ck.y]
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = _terrain_mat
	add_child(mi)
	_meshes[ck] = mi


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.42, 0.58, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

	# Dark seabed under the open sea.
	var bed_plane := PlaneMesh.new()
	bed_plane.size = Vector2(400, 400)
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color("15304d")
	bed_mat.roughness = 1.0
	_bed = MeshInstance3D.new()
	_bed.mesh = bed_plane
	_bed.material_override = bed_mat
	add_child(_bed)


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
		"iron_rock": [
			_part(_sphere(0.55, 3, 6), Color("6e625a"), Vector3(0, 0.15, 0), Vector3(1.0, 0.8, 0.9)),
			_part(_sphere(0.16, 2, 5), Color("b0582a"), Vector3(0.3, 0.42, 0.2)),
			_part(_sphere(0.13, 2, 5), Color("c4652e"), Vector3(-0.28, 0.38, -0.1)),
			_part(_sphere(0.11, 2, 5), Color("a14d24"), Vector3(0.05, 0.52, -0.3)),
		],
		"rubble": [
			_part(_sphere(0.14, 2, 5), Color("77746c"), Vector3(0.15, 0.04, 0.05)),
			_part(_sphere(0.1, 2, 5), Color("8d8a80"), Vector3(-0.15, 0.03, -0.1)),
			_part(_sphere(0.08, 2, 5), Color("6c6a63"), Vector3(0.0, 0.03, 0.2)),
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
	for kind in _layers:
		for layer in _layers[kind]:
			layer[0].queue_free()
	_layers.clear()
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


## Rebuilds the 3D props for the chunks around the player.
func _refresh_props() -> void:
	var cells_by_kind := {}
	for kind in PROP_TYPES:
		cells_by_kind[kind] = []
	for dz in range(-VIEW, VIEW + 1):
		for dx in range(-VIEW, VIEW + 1):
			var ck := _view_chunk + Vector2i(dx, dz)
			if not _chunk_in_bounds(ck):
				continue
			for cell in _chunk_props(ck):
				var kind := prop_type(cell)
				if cells_by_kind.has(kind):
					cells_by_kind[kind].append(cell)

	for kind in PROP_TYPES:
		var cells: Array = cells_by_kind[kind]
		# Work out each prop's place, turn and size once, then use it for every part.
		var origins := []
		var turns := []
		for cell in cells:
			var jitter := Vector3(_hash01(cell.x, cell.y, 4) - 0.5, 0, _hash01(cell.x, cell.y, 5) - 0.5) * 0.35
			var origin := Vector3(cell.x + 0.5, 0, cell.y + 0.5) + jitter
			origin.y = height_at(Vector2(origin.x, origin.z) * TILE) - 0.05
			var s := 0.8 + _hash01(cell.x, cell.y, 3) * 0.45
			origins.append(origin)
			turns.append(Basis(Vector3.UP, _hash01(cell.x, cell.y, 2) * TAU) * Basis.from_scale(Vector3.ONE * s))
		for layer in _layers[kind]:
			var inst: MultiMeshInstance3D = layer[0]
			var p: Dictionary = layer[1]
			var mm := inst.multimesh
			mm.instance_count = cells.size()
			var base_color: Color = p["color"]
			var offset: Vector3 = p["offset"]
			var part_scale := Basis.from_scale(p["scale"])
			for i in cells.size():
				var cell: Vector2i = cells[i]
				var turn: Basis = turns[i]
				var origin: Vector3 = origins[i]
				mm.set_instance_transform(i, Transform3D(turn * part_scale, origin + turn * offset))
				var shade := (_hash01(cell.x, cell.y, 6) - 0.5) * 0.18
				mm.set_instance_color(i, base_color.lightened(shade) if shade > 0.0 else base_color.darkened(-shade))


func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (seed_value * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h ^ (h >> 16)) % 10000) / 10000.0


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


# ---------- Map ----------

## Paints one chunk onto the map. `loaded` uses the chunk's generated data;
## otherwise (restoring a save) it samples the noise directly, which is cheaper.
func _paint_chunk(ck: Vector2i, loaded: bool) -> void:
	var per := CHUNK / MAP_SCALE
	var types: PackedByteArray = _chunk_data(ck)["t"] if loaded else PackedByteArray()
	for py in per:
		for px in per:
			var lx := px * MAP_SCALE + MAP_SCALE / 2
			var lz := py * MAP_SCALE + MAP_SCALE / 2
			var t: int
			if loaded:
				t = types[lz * CHUNK + lx]
			else:
				t = int(_sample(ck.x * CHUNK + lx, ck.y * CHUNK + lz)[0])
			var color: Color = TERRAIN_COLORS[t]
			if t == DEEP or t == WATER:
				color = color.lightened(0.12)
			map_image.set_pixel(ck.x * per + px, ck.y * per + py, color)
	_map_dirty = true


## Explored chunks as a compact hex string (one bit per chunk), for the save file.
func export_explored() -> String:
	var per_side := SIZE / CHUNK
	var bytes := PackedByteArray()
	bytes.resize(per_side * per_side / 8)
	for ck in explored:
		var i: int = ck.y * per_side + ck.x
		bytes[i / 8] |= 1 << (i % 8)
	return bytes.hex_encode()


func import_explored(hex: String) -> void:
	var per_side := SIZE / CHUNK
	var bytes := hex.hex_decode()
	if bytes.size() != per_side * per_side / 8:
		return
	for i in per_side * per_side:
		if bytes[i / 8] & (1 << (i % 8)):
			var ck := Vector2i(i % per_side, i / per_side)
			if not explored.has(ck):
				explored[ck] = true
				_paint_chunk(ck, _data.has(ck))
	map_texture.update(map_image)


# ---------- Places to discover ----------

const POI_NAMES := {
	"lighthouse": ["Gull Point Lighthouse", "The Last Lighthouse", "Cormorant Light"],
	"shipwreck": ["Wreck of the Margarethe", "Wreck of the Grey Heron", "Wreck of the Kestrel", "Wreck of the Salt Maiden", "Wreck of the Undine"],
	"ruins": ["The Old Watchtower", "Fallen Chapel", "Keeper's Hall", "The Broken Granary", "Mossgate Ruins", "The Signal Post", "Stone Barrows"],
	"cave": ["Wolf's Mouth", "Echo Cave", "The Hollow Deep", "Lantern Cave", "Drip Cavern"],
	"shrine": ["Shrine of the Tide", "Moss Shrine", "Shrine of Embers", "The Quiet Stones", "Shrine of the Lost"],
	"camp": ["Mara's Camp", "The Surveyors' Camp", "Tomas's Hideout", "A Fisher's Shelter", "The Last Watch", "Ivo's Camp", "The Deserters' Fire"],
}


func _place_pois() -> void:
	pois.clear()
	_poi_cells.clear()
	_poi_centers.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	var half := SIZE / 2
	var placed: Array = []
	for kind in ["lighthouse", "shipwreck", "cave", "ruins", "shrine", "camp"]:
		var names: Array = POI_NAMES[kind].duplicate()
		var want: int = POI_COUNTS[kind]
		var tries := 0
		var made := 0
		while made < want and tries < 3000:
			tries += 1
			var r := sqrt(rng.randf()) * half * 0.9
			var a := rng.randf() * TAU
			var cell := Vector2i(half + int(cos(a) * r), half + int(sin(a) * r))
			# The first abandoned camp sits near the start, so new players find one early.
			if kind == "camp" and made == 0 and tries < 400:
				cell = spawn_cell + Vector2i(int(cos(a) * rng.randf_range(14, 24)), int(sin(a) * rng.randf_range(14, 24)))
			elif cell.distance_to(spawn_cell) < 30.0:
				continue
			if not _poi_site_ok(kind, cell):
				continue
			var too_close := false
			for other in placed:
				if cell.distance_to(other) < 45.0:
					too_close = true
					break
			if too_close:
				continue
			placed.append(cell)
			var poi_name: String = names[made % names.size()]
			pois.append({"id": "%s-%d" % [kind, made], "type": kind, "cell": cell, "name": poi_name,
				"seed": rng.randi()})
			var radius := 3 if kind == "lighthouse" or kind == "shipwreck" or kind == "cave" else 2
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					_poi_cells[cell + Vector2i(dx, dz)] = true
			_poi_centers[cell] = pois[-1]["id"]
			made += 1


func _poi_site_ok(kind: String, cell: Vector2i) -> bool:
	var t := int(_sample(cell.x, cell.y)[0])
	var near_water := false
	for o in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		var tn := int(_sample(cell.x + o.x, cell.y + o.y)[0])
		if tn == WATER or tn == DEEP:
			near_water = true
	match kind:
		"lighthouse":
			return (t == SAND or t == GRASS or t == ROCK) and near_water
		"shipwreck":
			return t == SAND and near_water
		"cave":
			return t == ROCK and not near_water
		_:
			return (t == GRASS or t == FOREST) and not near_water
