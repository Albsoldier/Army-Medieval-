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
const VIEW := 3  # terrain chunks drawn around the player in each direction
const PROP_VIEW := 2  # trees, rocks and bushes are drawn a little closer in
const GRASS_RADIUS := 34  # tiles of grass around the player
const CHUNKS := SIZE / CHUNK
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
const PROP_TYPES := ["tree", "stump", "rock", "iron_rock", "rubble", "bush", "bush_empty", "gold_rock"]
## Saved prop changes may also be "cleared": the ground under a building.
const CHANGE_TYPES := ["tree", "stump", "rock", "iron_rock", "rubble", "bush", "bush_empty", "cleared", "gold_rock"]
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
const UNEXPLORED := Color(0.80, 0.73, 0.58)  # blank parchment
## The map is drawn like an old chart: muted, with shaded hills.
const MAP_COLORS := [
	Color("3d5c68"),  # deep water
	Color("5c8390"),  # shallow water
	Color("d6c497"),  # sand
	Color("a9aa6a"),  # grass
	Color("75814d"),  # forest
	Color("9c9383"),  # rock
]
## What the props are drawn as. Trees come in two kinds.
const DRAW_TYPES := ["tree_pine", "tree_oak", "stump", "rock", "iron_rock", "rubble", "bush", "bush_empty", "gold_rock"]
## Rocks you can't walk through, and props you can hit for materials.
const SOLID_PROPS := ["tree", "rock", "iron_rock", "gold_rock"]
const HARVESTABLE := ["tree", "rock", "iron_rock", "gold_rock", "bush"]
## Small islands out at sea, reached by galley. Each has a treasure hoard.
const ISLET_COUNT := 5
const ISLET_NAMES := ["Gull Rock", "Ember Isle", "The Black Teeth", "Saint Brine", "Hollow Key", "Far Holm"]
const POI_COUNTS := {"lighthouse": 2, "shipwreck": 4, "ruins": 6, "cave": 4, "shrine": 4, "camp": 6}
var _poi_cells: Dictionary = {}  # cells kept clear around places to discover
var _poi_centers: Dictionary = {}  # Vector2i cell -> poi id (these tiles can't be walked through)
var _map_dirty := false
var _map_timer := 0.0

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _grass: MultiMeshInstance3D
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
var _terrain_mat: ShaderMaterial
var islets: Array = []  # [{"cell": Vector2i, "r": float, "name": String}]
var _islets_on := false
var season := "spring"  # spring, summer, autumn or winter (main.gd sets it)
var _ice_mat: StandardMaterial3D
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

	# Small bumps and dips that make the ground look natural up close.
	_detail = FastNoiseLite.new()
	_detail.seed = p_seed + 1231
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.16
	_detail.fractal_octaves = 2

	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = preload("res://shaders/terrain.gdshader")

	_islets_on = false
	_find_spawn()
	_place_pois()
	# The islets came after the main island, so they must not move anything on it:
	# they're only placed in open sea, and the caches are rebuilt with them included.
	_place_islets()
	_islets_on = true
	_data.clear()
	_corners.clear()
	_base_props.clear()
	_place_hoards()
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.78, 0.86, 0.92)
	_ice_mat.roughness = 0.2
	_ice_mat.metallic_specular = 0.8
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
	_bed.position = Vector3(_water.position.x, -3.05, _water.position.z)

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
	if not is_land(cell) and not is_ice(cell):
		return false
	if structures.has(cell):
		var built: String = structures[cell]
		return (built in ["gate", "oil_gate"] and not wolf) or built in ["dock", "spike_trap", "field"]
	if _poi_centers.has(cell):
		return false
	return not prop_type(cell) in SOLID_PROPS


## In winter, lakes and shallow sea freeze over and can be walked on.
func is_ice(cell: Vector2i) -> bool:
	return season == "winter" and terrain_at(cell) == WATER


## Whether a boat can be at `pos`. Rafts keep to shallow water; a galley can
## cross the deep sea. Ice stops both.
func is_sailable(pos: Vector2, deep_ok: bool) -> bool:
	var cell := cell_of(pos)
	if cell.x < 4 or cell.y < 4 or cell.x >= SIZE - 4 or cell.y >= SIZE - 4:
		return false
	var t := terrain_at(cell)
	if t == DEEP:
		return deep_ok
	return t == WATER and season != "winter"


## Which islet a cell is on, or -1.
func islet_at(cell: Vector2i) -> int:
	for i in islets.size():
		var c: Vector2i = islets[i]["cell"]
		if Vector2(cell - c).length() < float(islets[i]["r"]) * 1.3:
			return i
	return -1


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
	var y := height_at(pos)
	if season == "winter" and y < 0.05 and terrain_at(cell_of(pos)) == WATER:
		y = 0.05  # standing on the ice
	return Vector3(pos.x / TILE, y, pos.y / TILE)


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
			if not kind in HARVESTABLE:
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
		"gold_rock":
			gained = {"gold": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				prop["type"] = "rubble"
		"bush":
			if season == "winter":
				return {}  # nothing grows in winter
			gained = {"berries": 5 if season == "autumn" else 3}
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
	if _islets_on:
		for islet in islets:
			var c: Vector2i = islet["cell"]
			var r: float = islet["r"]
			var dist := Vector2(x - c.x, z - c.y).length()
			if dist < r * 1.3:
				e = maxf(e, 0.06 + 0.95 * (1.0 - (dist / r) * (dist / r)) + (detail - 0.5) * 0.25)
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
		return -3.0
	var ck := Vector2i(x / CHUNK, z / CHUNK)
	var data: Dictionary = _chunk_data(ck)
	var i := (z - ck.y * CHUNK) * CHUNK + (x - ck.x * CHUNK)
	return _height_for(data["t"][i], data["e"][i])


## Ground height in metres for a terrain type and elevation: rolling hills,
## with rocky peaks rising well above them.
static func _height_for(t: int, e: float) -> float:
	if t == DEEP:
		return -3.0
	if t == WATER:
		return -1.0
	if t == SAND:
		return 0.1 + (e - 0.26) * 1.5
	if t == ROCK:
		return minf(2.2 + (e - 0.9) * 14.0, 7.5)
	return 0.3 + (e - 0.32) * 3.4


## Heights live on tile corners, averaged from the four tiles around each
## corner, plus a little noise so the land isn't perfectly smooth.
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
			var h := (_tile_height(x - 1, z - 1) + _tile_height(x, z - 1)
				+ _tile_height(x - 1, z) + _tile_height(x, z)) / 4.0
			h += _detail.get_noise_2d(x, z) * 0.28 * clampf(h * 2.0, 0.0, 1.0)
			corners[cz * w + cx] = h
	_corners[ck] = corners
	return corners


## The height of any tile corner on the island, across chunk borders.
func _corner_height(gx: int, gz: int) -> float:
	gx = clampi(gx, 0, SIZE)
	gz = clampi(gz, 0, SIZE)
	var ck := Vector2i(mini(gx / CHUNK, CHUNKS - 1), mini(gz / CHUNK, CHUNKS - 1))
	var corners := _chunk_corners(ck)
	return corners[(gz - ck.y * CHUNK) * (CHUNK + 1) + (gx - ck.x * CHUNK)]


## How much sand, forest floor and rock meet at a corner, for the terrain shader.
func _corner_blend(gx: int, gz: int) -> Color:
	var c := Color(0, 0, 0, 1)
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var t := terrain_at(Vector2i(gx, gz) + o)
		if t == SAND or t == WATER or t == DEEP:
			c.r += 0.25
		elif t == FOREST:
			c.g += 0.25
		elif t == ROCK:
			c.b += 0.25
	return c


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
			var on_islet := not islets.is_empty() and islet_at(cell) >= 0
			if on_islet and (types[lz * CHUNK + lx] == ROCK or types[lz * CHUNK + lx] == GRASS):
				# The islets hold the island's richest ore: gold, and plenty of iron.
				if roll < 0.045:
					props[cell] = "gold_rock"
					continue
				if roll < 0.09:
					props[cell] = "iron_rock"
					continue
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
	# One smooth surface per chunk: shared corners, smooth normals, and blend
	# weights for the terrain shader. Open sea is left to the seabed plane.
	var corners := _chunk_corners(ck)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [ck.x, ck.y]
	add_child(mi)
	_meshes[ck] = mi
	var any_land := false
	for h in corners:
		if h > -2.7:
			any_land = true
			break
	if not any_land:
		return
	var w := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	for cz in w:
		for cx in w:
			var gx := ck.x * CHUNK + cx
			var gz := ck.y * CHUNK + cz
			var i := cz * w + cx
			verts[i] = Vector3(gx, corners[i], gz)
			var hl := _corner_height(gx - 1, gz)
			var hr := _corner_height(gx + 1, gz)
			var hd := _corner_height(gx, gz - 1)
			var hu := _corner_height(gx, gz + 1)
			normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
			colors[i] = _corner_blend(gx, gz)
	var indices := PackedInt32Array()
	indices.resize(CHUNK * CHUNK * 6)
	var k := 0
	for z in CHUNK:
		for x in CHUNK:
			var a := z * w + x
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + w + 1
			indices[k + 3] = a
			indices[k + 4] = a + w + 1
			indices[k + 5] = a + w
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.material_override = _terrain_mat
	_build_ice(ck, mi)


## A sheet of ice over the shallow water in a chunk, shown in winter.
func _build_ice(ck: Vector2i, parent: Node3D) -> void:
	var verts := PackedVector3Array()
	for lz in CHUNK:
		for lx in CHUNK:
			var x := ck.x * CHUNK + lx
			var z := ck.y * CHUNK + lz
			if terrain_at(Vector2i(x, z)) != WATER:
				continue
			var y := 0.04
			verts.append_array(PackedVector3Array([Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1),
				Vector3(x, y, z), Vector3(x + 1, y, z + 1), Vector3(x, y, z + 1)]))
	if verts.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ice := MeshInstance3D.new()
	ice.name = "Ice"
	ice.mesh = mesh
	ice.material_override = _ice_mat
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ice.visible = season == "winter"
	parent.add_child(ice)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(640, 640)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

	# Dark seabed under the open sea.
	var bed_plane := PlaneMesh.new()
	bed_plane.size = Vector2(640, 640)
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color("1b3540")
	bed_mat.roughness = 1.0
	_bed = MeshInstance3D.new()
	_bed.mesh = bed_plane
	_bed.material_override = bed_mat
	add_child(_bed)


func _part(mesh: Mesh, color: Color, offset: Vector3, size: Vector3 = Vector3.ONE, sway: float = 0.0) -> Dictionary:
	return {"mesh": mesh, "color": color, "offset": offset, "scale": size, "sway": sway}


func _prop_parts() -> Dictionary:
	var berry := _sphere(0.07, 4, 6)
	var bark := Color("4f3a28")
	return {
		# A tall pine in tiers of needles.
		"tree_pine": [
			_part(_cylinder(0.1, 0.22, 3.4, 8), bark, Vector3(0, 1.7, 0)),
			_part(_cylinder(0.08, 1.55, 2.3, 11), Color("23402a"), Vector3(0, 2.1, 0), Vector3.ONE, 0.03),
			_part(_cylinder(0.06, 1.25, 2.0, 11), Color("2a4a30"), Vector3(0, 3.1, 0), Vector3.ONE, 0.04),
			_part(_cylinder(0.04, 0.95, 1.7, 10), Color("315636"), Vector3(0, 4.0, 0), Vector3.ONE, 0.05),
			_part(_cylinder(0.0, 0.6, 1.5, 9), Color("3a613c"), Vector3(0, 4.9, 0), Vector3.ONE, 0.06),
		],
		# A broad-leaved tree with a rounded, lumpy crown.
		"tree_oak": [
			_part(_cylinder(0.16, 0.3, 2.8, 8), Color("5a4430"), Vector3(0, 1.4, 0)),
			_part(_sphere(1.45, 6, 10), Color("34482a"), Vector3(0, 3.5, 0), Vector3(1.0, 0.85, 1.0), 0.05),
			_part(_sphere(1.1, 6, 10), Color("3e552e"), Vector3(0.95, 3.15, 0.35), Vector3(1.0, 0.85, 1.0), 0.06),
			_part(_sphere(1.05, 6, 10), Color("2f4226"), Vector3(-0.85, 3.25, -0.4), Vector3(1.0, 0.85, 1.0), 0.06),
			_part(_sphere(0.95, 6, 10), Color("4a6133"), Vector3(0.2, 4.2, -0.45), Vector3(1.0, 0.85, 1.0), 0.07),
			_part(_sphere(0.85, 6, 10), Color("3b522c"), Vector3(-0.35, 3.95, 0.75), Vector3(1.0, 0.85, 1.0), 0.07),
		],
		"stump": [
			_part(_cylinder(0.22, 0.3, 0.42, 9), bark, Vector3(0, 0.2, 0)),
			_part(_cylinder(0.2, 0.2, 0.02, 9), Color("b89466"), Vector3(0, 0.42, 0)),
		],
		"rock": [
			_part(_sphere(0.75, 5, 9), Color("7d7a72"), Vector3(0, 0.12, 0), Vector3(1.25, 0.62, 1.0)),
			_part(_sphere(0.42, 5, 8), Color("8f8b82"), Vector3(0.55, 0.12, 0.35), Vector3(1.0, 0.7, 1.1)),
			_part(_sphere(0.3, 4, 7), Color("6c6a64"), Vector3(-0.5, 0.06, -0.35), Vector3(1.1, 0.6, 1.0)),
		],
		"iron_rock": [
			_part(_sphere(0.75, 5, 9), Color("6b6058"), Vector3(0, 0.14, 0), Vector3(1.2, 0.68, 1.0)),
			_part(_sphere(0.17, 4, 6), Color("a4532a"), Vector3(0.38, 0.5, 0.25)),
			_part(_sphere(0.14, 4, 6), Color("b9612e"), Vector3(-0.35, 0.44, -0.12)),
			_part(_sphere(0.12, 4, 6), Color("944822"), Vector3(0.05, 0.6, -0.36)),
		],
		"gold_rock": [
			_part(_sphere(0.72, 5, 9), Color("5f5a55"), Vector3(0, 0.14, 0), Vector3(1.2, 0.7, 1.0)),
			_part(_sphere(0.16, 4, 6), Color("e0b43c"), Vector3(0.36, 0.5, 0.22)),
			_part(_sphere(0.13, 4, 6), Color("f0c850"), Vector3(-0.32, 0.46, -0.1)),
			_part(_sphere(0.11, 4, 6), Color("d4a434"), Vector3(0.05, 0.62, -0.34)),
		],
		"rubble": [
			_part(_sphere(0.16, 4, 6), Color("7d7a72"), Vector3(0.18, 0.04, 0.05)),
			_part(_sphere(0.12, 4, 6), Color("8f8b82"), Vector3(-0.18, 0.03, -0.12)),
			_part(_sphere(0.1, 4, 6), Color("6c6a64"), Vector3(0.0, 0.03, 0.24)),
		],
		"bush": [
			_part(_sphere(0.5, 5, 9), Color("355a2a"), Vector3(0, 0.34, 0), Vector3(1.0, 0.8, 1.0), 0.03),
			_part(_sphere(0.36, 5, 8), Color("3f6630"), Vector3(0.38, 0.28, 0.2), Vector3(1.0, 0.8, 1.0), 0.03),
			_part(_sphere(0.32, 5, 8), Color("2f5126"), Vector3(-0.32, 0.26, -0.22), Vector3(1.0, 0.8, 1.0), 0.03),
			_part(berry, Color("b8263c"), Vector3(0.3, 0.55, 0.15)),
			_part(berry, Color("c42a40"), Vector3(-0.22, 0.6, 0.25)),
			_part(berry, Color("a8233a"), Vector3(0.05, 0.7, -0.28)),
			_part(berry, Color("c42a40"), Vector3(-0.4, 0.42, -0.1)),
		],
		"bush_empty": [
			_part(_sphere(0.45, 5, 9), Color("4c6a3a"), Vector3(0, 0.3, 0), Vector3(1.0, 0.75, 1.0), 0.03),
			_part(_sphere(0.3, 5, 8), Color("557040"), Vector3(0.3, 0.24, 0.2), Vector3(1.0, 0.75, 1.0), 0.03),
		],
	}


func _build_prop_layers() -> void:
	for kind in _layers:
		for layer in _layers[kind]:
			layer[0].queue_free()
	_layers.clear()
	var parts := _prop_parts()
	var foliage_shader := preload("res://shaders/foliage.gdshader")
	for kind in DRAW_TYPES:
		var layers := []
		for p in parts[kind]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = p["mesh"]
			var inst := MultiMeshInstance3D.new()
			inst.name = "Props_%s" % kind
			inst.multimesh = mm
			if float(p["sway"]) > 0.0:
				var leaves := ShaderMaterial.new()
				leaves.shader = foliage_shader
				leaves.set_shader_parameter("sway", p["sway"])
				inst.material_override = leaves
			else:
				var mat := StandardMaterial3D.new()
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = true
				mat.roughness = 0.95
				inst.material_override = mat
			add_child(inst)
			layers.append([inst, p])
		_layers[kind] = layers
	# Grass clumps around the player.
	_grass = MultiMeshInstance3D.new()
	_grass.name = "Grass"
	var gmm := MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	gmm.use_colors = true
	gmm.mesh = _grass_clump_mesh()
	_grass.multimesh = gmm
	var gmat := ShaderMaterial.new()
	gmat.shader = preload("res://shaders/grass.gdshader")
	_grass.material_override = gmat
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass)


## Five thin blades leaning out from one root.
func _grass_clump_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for b in 7:
		var a := r.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.18)
		var side := Vector3(cos(a + PI / 2), 0, sin(a + PI / 2)) * r.randf_range(0.025, 0.04)
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.08, 0.25)
		var height := r.randf_range(0.35, 0.6)
		for v in [[root - side, 0.0], [root + side, 0.0], [root + lean + Vector3(0, height, 0), 1.0]]:
			verts.append(v[0])
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.5, v[1]))
			colors.append(Color(1, 1, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Which kind of tree grows on a cell: mostly pines in forests, broad-leaved trees in the open.
func _tree_kind(cell: Vector2i) -> String:
	var pine_share := 0.7 if terrain_at(cell) == FOREST else 0.25
	return "tree_pine" if _hash01(cell.x, cell.y, 9) < pine_share else "tree_oak"


## Rebuilds the 3D props and grass for the chunks around the player.
func _refresh_props() -> void:
	var cells_by_kind := {}
	for kind in DRAW_TYPES:
		cells_by_kind[kind] = []
	for dz in range(-PROP_VIEW, PROP_VIEW + 1):
		for dx in range(-PROP_VIEW, PROP_VIEW + 1):
			var ck := _view_chunk + Vector2i(dx, dz)
			if not _chunk_in_bounds(ck):
				continue
			for cell in _chunk_props(ck):
				var kind := prop_type(cell)
				if kind == "tree":
					kind = _tree_kind(cell)
				if cells_by_kind.has(kind):
					cells_by_kind[kind].append(cell)

	for kind in DRAW_TYPES:
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
				var shade := (_hash01(cell.x, cell.y, 6) - 0.5) * 0.22
				var c := _season_color(kind, p, base_color, cell)
				if c.a <= 0.0:
					mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), origin))
					mm.set_instance_color(i, base_color)
					continue
				mm.set_instance_transform(i, Transform3D(turn * part_scale, origin + turn * offset))
				mm.set_instance_color(i, c.lightened(shade) if shade > 0.0 else c.darkened(-shade))
	_refresh_grass()


func _refresh_grass() -> void:
	if season == "winter":
		_grass.multimesh.instance_count = 0  # under the snow
		return
	var center := _view_chunk * CHUNK + Vector2i(CHUNK / 2, CHUNK / 2)
	var xforms := []
	var tints := []
	for dz in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
		for dx in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
			if dx * dx + dz * dz > GRASS_RADIUS * GRASS_RADIUS:
				continue
			var cell := center + Vector2i(dx, dz)
			var t := terrain_at(cell)
			if t != GRASS and t != FOREST:
				continue
			if structures.has(cell) or _poi_cells.has(cell):
				continue
			var clumps := 3 if t == GRASS else 1
			for c in clumps:
				var jx := _hash01(cell.x, cell.y, 20 + c)
				var jz := _hash01(cell.x, cell.y, 30 + c)
				var p := Vector2(cell.x + jx, cell.y + jz)
				var y := height_at(p * TILE)
				var s := 0.7 + _hash01(cell.x, cell.y, 40 + c) * 0.7
				xforms.append(Transform3D(Basis(Vector3.UP, jx * TAU) * Basis.from_scale(Vector3(s, s, s)), Vector3(p.x, y - 0.02, p.y)))
				var g := _hash01(cell.x, cell.y, 50 + c)
				var tint := Color("50652c").lerp(Color("7a7a42"), g * 0.8) if t == GRASS else Color("3b4c25")
				if season == "autumn":
					tint = tint.lerp(Color("8a6a34"), 0.45)
				elif season == "summer":
					tint = tint.lerp(Color("8a8040"), 0.2)
				tints.append(tint)
	var mm := _grass.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])


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
	for py in per:
		for px in per:
			var x := ck.x * CHUNK + px * MAP_SCALE + MAP_SCALE / 2
			var z := ck.y * CHUNK + py * MAP_SCALE + MAP_SCALE / 2
			var here := _map_sample(x, z, loaded)
			var t: int = here[0]
			var color: Color = MAP_COLORS[t]
			# Shade hills as if lit from the north-west, like a relief map.
			var nw: float = _map_sample(x - MAP_SCALE, z - MAP_SCALE, loaded)[1]
			var se: float = _map_sample(x + MAP_SCALE, z + MAP_SCALE, loaded)[1]
			var shade := clampf((nw - se) * 0.22, -0.22, 0.22)
			if t == DEEP or t == WATER:
				shade = 0.0
			color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
			map_image.set_pixel(ck.x * per + px, ck.y * per + py, color)
	_map_dirty = true


## [terrain type, height] for a tile, from loaded chunk data or straight from the noise.
func _map_sample(x: int, z: int, loaded: bool) -> Array:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
		return [DEEP, -3.0]
	if loaded or _data.has(Vector2i(x / CHUNK, z / CHUNK)):
		var t := terrain_at(Vector2i(x, z))
		return [t, _tile_height(x, z)]
	var s := _sample(x, z)
	return [int(s[0]), _height_for(int(s[0]), float(s[1]))]


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


## Small islands in the open sea around the main island. Only placed where the
## sea is deep all around, so the main island never changes.
func _place_islets() -> void:
	islets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 131 + 17
	var half := SIZE * 0.5
	var tries := 0
	while islets.size() < ISLET_COUNT and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.8, 0.9)
		var r := rng.randf_range(12.0, 19.0)
		var c := Vector2i(int(half + cos(a) * d * half), int(half + sin(a) * d * half))
		var clear := true
		for other in islets:
			var oc: Vector2i = other["cell"]
			if Vector2(c - oc).length() < r + float(other["r"]) + 60.0:
				clear = false
				break
		if not clear:
			continue
		# Everything within reach of the islet must be open sea now.
		var reach := int(r * 1.3) + 14
		for dz in range(-reach, reach + 1, 3):
			for dx in range(-reach, reach + 1, 3):
				if dx * dx + dz * dz <= reach * reach and int(_sample(c.x + dx, c.y + dz)[0]) != DEEP:
					clear = false
					break
			if not clear:
				break
		if clear:
			islets.append({"cell": c, "r": r, "name": ISLET_NAMES[islets.size() % ISLET_NAMES.size()]})


## A treasure hoard on every islet: the reason to build a galley.
func _place_hoards() -> void:
	for i in islets.size():
		var c: Vector2i = islets[i]["cell"]
		var spot := NO_CELL
		for r in range(3, 14):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if spot == NO_CELL and maxi(absi(dx), absi(dz)) == r:
						var t := terrain_at(c + Vector2i(dx, dz))
						if t == GRASS or t == FOREST:
							spot = c + Vector2i(dx, dz)
		if spot == NO_CELL:
			continue
		var id := "hoard-%d" % i
		pois.append({"id": id, "type": "hoard", "cell": spot, "name": "Hoard of %s" % islets[i]["name"],
			"seed": int(_hash01(spot.x, spot.y, 61) * 100000.0)})
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				_poi_cells[spot + Vector2i(dx, dz)] = true
		_poi_centers[spot] = id


## Sets the season: terrain colours, snow, autumn leaves and ice.
func set_season(p_season: String) -> void:
	if p_season == season:
		return
	season = p_season
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("snow", 1.0 if season == "winter" else 0.0)
		_terrain_mat.set_shader_parameter("autumn", 1.0 if season == "autumn" else 0.0)
		_terrain_mat.set_shader_parameter("summer", 1.0 if season == "summer" else 0.0)
	for ck in _meshes:
		var ice: Node = _meshes[ck].get_node_or_null("Ice")
		if ice:
			(ice as MeshInstance3D).visible = season == "winter"
	_props_dirty = true


## A prop part's colour this season, or a transparent colour to hide it.
func _season_color(kind: String, p: Dictionary, base: Color, cell: Vector2i) -> Color:
	var leafy := float(p["sway"]) > 0.0
	var berry: bool = kind == "bush" and not leafy
	match season:
		"summer":
			if leafy:
				return base.lerp(Color("6f7d34"), 0.15)
		"autumn":
			if kind == "tree_oak" and leafy:
				var turn := _hash01(cell.x, cell.y, 71)
				var fall := Color("b4561e") if turn < 0.4 else (Color("c98a24") if turn < 0.75 else Color("8e3a1c"))
				return base.lerp(fall, 0.75)
			if kind == "bush" and leafy:
				return base.lerp(Color("7a5a2a"), 0.45)
		"winter":
			if kind == "tree_oak" and leafy:
				return Color(0, 0, 0, 0)  # bare branches
			if berry:
				return Color(0, 0, 0, 0)
			if leafy:
				return base.lerp(Color(0.9, 0.93, 0.96), 0.55)
			if kind in ["rock", "iron_rock", "gold_rock", "stump"]:
				return base.lerp(Color(0.88, 0.9, 0.94), 0.3)
	return base


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
