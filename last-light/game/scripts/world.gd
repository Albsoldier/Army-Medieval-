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
const PROP_CHUNK_DEFAULT := 32  # tiles (metres) per side of a prop chunk; see GRAPHICS_PROP_CHUNKS.md
const PROP_BUILDS_PER_FRAME := 1
const GRASS_FLOATS := 16  # MultiMesh data per grass clump: a 3x4 transform and a colour
const GRASS_ROWS_PER_FRAME := 6  # rows of grass worked out ahead of time each frame  # prop chunks built per frame as you travel (they appear far out, in the fog)
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
var _grass_cache: Dictionary = {}  # chunk -> rows of ready-made grass data (see _grass_rows)
var _grass_dirty := true  # the grass around the player needs gathering again
var _grass_partial: Dictionary = {}  # chunk -> rows worked out so far, ahead of time
var _continent: FastNoiseLite
var _moisture: FastNoiseLite
var _data: Dictionary = {}  # chunk -> {"t": PackedByteArray, "e": PackedFloat32Array}
var _corners: Dictionary = {}  # chunk -> PackedFloat32Array of (CHUNK + 1)^2 corner heights
var _base_props: Dictionary = {}  # chunk -> {Vector2i cell: String type}
var _meshes: Dictionary = {}  # chunk -> MeshInstance3D
var _build_queue: Array = []
var _view_chunk := Vector2i(-999, -999)
var _last_prop_center := Vector2i(-999, -999)
var _props_dirty := true  # every built prop chunk needs rebuilding (season, loaded save)
## Props are drawn per chunk, so the camera and shadow passes can cull each one:
## chunk -> {"node": Node3D, "props": int}. See GRAPHICS_PROP_CHUNKS.md.
var _prop_chunks: Dictionary = {}
var prop_chunk := PROP_CHUNK_DEFAULT  # prop chunk size in tiles; set before the first update_view
## One MultiMesh per prop type per chunk (each type's parts merged into one mesh),
## rather than one per part. Set before the first update_view.
var prop_grouping := true
var _merged_props: Dictionary = {}  # kind -> ArrayMesh: every part of the type, rigid and leaf surfaces
## Environment prototype (phase 4A): these prop types are drawn with textured
## models from Quaternius's Stylized Nature MegaKit (models/nature, CC0) instead
## of their procedural parts. Same places, sizes, seasons and collision; only
## the mesh changes. Picked bushes use the bush model with its flowers hidden.
## Set before generate(); ?nature=0 turns it off. See GRAPHICS_ENVIRONMENT_PROTOTYPE.md.
const NATURE_MODELS := {"tree_pine": "pine", "tree_oak": "oak", "rock": "rock", "bush": "bush", "bush_empty": "bush"}
## Which texture each of their surfaces uses (by the model's material name).
const NATURE_TEXTURES := {"Bark_NormalTree": "bark", "Leaves_Pine": "pine_needles",
	"Leaves_NormalTree": "leaves", "Flowers": "flowers", "Rocks": "rock"}
var nature_models := true
## The models' far versions (fewer, larger leaf cards; simpler bark, each with
## its own small vertex buffer) are drawn for chunks further than this from the
## camera: kind -> ArrayMesh. Rocks rely on Godot's automatic mesh LOD alone.
const NATURE_NEAR := 40.0
var _nature_far: Dictionary = {}
## The models don't cast shadows themselves: their leaf cards would need the
## cut-out shader in every shadow pass. Instead each chunk draws the type's old
## procedural mesh into the shadow maps only (same instances, same seasons):
## kind -> ArrayMesh. The shadows stay what they were before the prototype.
var _nature_shadow: Dictionary = {}
var _prop_queue: Array = []  # chunks in view that still need building, nearest first
var _dirty_prop_chunks: Dictionary = {}  # chunk -> true: rebuild (something there changed)
var _props_root: Node3D
## kind -> Array of layer definitions {"parts": [part, ...], "material": Material}.
## Parts that share a mesh and material (a bush's berries) share one layer.
var _prop_defs: Dictionary = {}
var _terrain_mat: ShaderMaterial
## Phase 5A (GRAPHICS_PHASE_5A_TERRAIN.md): the textured terrain shader. Off with
## ?terrain=0 (set before generate()), to compare with the original look. It
## changes only how the ground is drawn: the terrain data, heights and meshes
## are the same either way.
var terrain_detail := true
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
	if terrain_detail and ResourceLoader.exists("res://shaders/terrain_detail.gdshader"):
		_terrain_mat.shader = load("res://shaders/terrain_detail.gdshader")
		_terrain_mat.set_shader_parameter("ground", load("res://textures/terrain/ground_albedo.png"))
		_terrain_mat.set_shader_parameter("ground_normal", load("res://textures/terrain/ground_normal.png"))

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
		_build_queue.clear()
		_queue_prop_chunks()
		for gk in _grass_cache.keys():
			var gfar: Vector2i = (gk - center).abs()
			if maxi(gfar.x, gfar.y) > 4:
				_grass_cache.erase(gk)  # keep only the grass near you
		for gk in _grass_partial.keys():
			var pfar: Vector2i = (gk - center).abs()
			if maxi(pfar.x, pfar.y) > 4:
				_grass_partial.erase(gk)
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

	_update_props(immediate, center != _last_prop_center)
	_last_prop_center = center

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
	_grass_changed(cell)
	if prop_type(cell) != "" and prop_type(cell) != "cleared":
		prop_changes[cell] = {"type": "cleared", "hp": 0, "regrow_day": 0}
		_mark_props_dirty(cell)


func remove_structure(cell: Vector2i) -> void:
	structures.erase(cell)
	_grass_changed(cell)


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
		_mark_props_dirty(cell)
	prop_changes[cell] = prop
	return gained


## Felled trees, broken rocks and picked bushes grow back after a few days.
func regrow(day: int) -> void:
	for cell in prop_changes.keys():
		var regrow_day := int(prop_changes[cell].get("regrow_day", 0))
		if regrow_day > 0 and regrow_day <= day:
			prop_changes.erase(cell)
			_mark_props_dirty(cell)


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
	# Each tile touches four corners: look its height up once, not four times.
	# Tiles run from one before the chunk to one after it (CHUNK + 2 a side).
	var tw := CHUNK + 2
	var tiles := PackedFloat64Array()
	tiles.resize(tw * tw)
	for tz in tw:
		for tx in tw:
			tiles[tz * tw + tx] = _tile_height(ck.x * CHUNK - 1 + tx, ck.y * CHUNK - 1 + tz)
	var corners := PackedFloat32Array()
	corners.resize(w * w)
	for cz in w:
		for cx in w:
			var x := ck.x * CHUNK + cx
			var z := ck.y * CHUNK + cz
			var t := cz * tw + cx  # the tile up and to the left of this corner
			var h := (tiles[t] + tiles[t + 1]
				+ tiles[t + tw] + tiles[t + tw + 1]) / 4.0
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


## The blend weights for the four terrain types around a corner (see _corner_blend).
static func _blend_of(types: Array) -> Color:
	var c := Color(0, 0, 0, 1)
	for t in types:
		if t == SAND or t == WATER or t == DEEP:
			c.r += 0.25
		elif t == FOREST:
			c.g += 0.25
		elif t == ROCK:
			c.b += 0.25
	return c


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
	var arrays := _terrain_arrays(ck, corners)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.material_override = _terrain_mat
	_build_ice(ck, mi)


## The terrain mesh data for one chunk: one smooth surface with shared corners,
## smooth normals, and blend weights for the terrain shader.
func _terrain_arrays(ck: Vector2i, corners: PackedFloat32Array) -> Array:
	var w := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	# Corner heights with a one-corner border from the neighbouring chunks (for
	# the normals), and the terrain under every corner (for the blend weights),
	# each looked up once rather than four times per vertex.
	var ew := w + 2
	var near := PackedFloat32Array()
	near.resize(ew * ew)
	for ez in ew:
		for ex in ew:
			var cx := ex - 1
			var cz := ez - 1
			if cx >= 0 and cz >= 0 and cx < w and cz < w:
				near[ez * ew + ex] = corners[cz * w + cx]
			else:
				near[ez * ew + ex] = _corner_height(ck.x * CHUNK + cx, ck.y * CHUNK + cz)
	var tw := CHUNK + 2
	var kinds := PackedByteArray()
	kinds.resize(tw * tw)
	for tz in tw:
		for tx in tw:
			kinds[tz * tw + tx] = terrain_at(Vector2i(ck.x * CHUNK - 1 + tx, ck.y * CHUNK - 1 + tz))
	for cz in w:
		for cx in w:
			var gx := ck.x * CHUNK + cx
			var gz := ck.y * CHUNK + cz
			var i := cz * w + cx
			verts[i] = Vector3(gx, corners[i], gz)
			var e := (cz + 1) * ew + (cx + 1)
			normals[i] = Vector3(near[e - 1] - near[e + 1], 2.0, near[e - ew] - near[e + ew]).normalized()
			var t := cz * tw + cx  # the tile up and to the left of this corner
			colors[i] = _blend_of([kinds[t], kinds[t + 1], kinds[t + tw], kinds[t + tw + 1]])
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
	return arrays


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


## Sets up how each prop type is drawn: its layers and their shared materials,
## and the grass. The props themselves are built per chunk (_build_prop_chunk).
func _build_prop_layers() -> void:
	if _props_root:
		_props_root.queue_free()
	_prop_chunks.clear()
	_prop_queue.clear()
	_dirty_prop_chunks.clear()
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_prop_defs.clear()
	var parts := _prop_parts()
	var foliage_shader := preload("res://shaders/foliage.gdshader")
	var bark := StandardMaterial3D.new()  # one material for everything that doesn't sway
	bark.vertex_color_use_as_albedo = true
	bark.vertex_color_is_srgb = true
	bark.roughness = 0.95
	var leaves_by_sway := {}
	for kind in DRAW_TYPES:
		var layers := []
		var by_key := {}
		for p in parts[kind]:
			var sway := float(p["sway"])
			var key := "%d:%s" % [(p["mesh"] as Mesh).get_instance_id(), sway]
			if by_key.has(key):
				by_key[key]["parts"].append(p)  # same mesh, same material: one layer
				continue
			var mat: Material = bark
			if sway > 0.0:
				if not leaves_by_sway.has(sway):
					var leaves := ShaderMaterial.new()
					leaves.shader = foliage_shader
					leaves.set_shader_parameter("sway", sway)
					leaves_by_sway[sway] = leaves
				mat = leaves_by_sway[sway]
			var layer := {"parts": [p], "material": mat, "mesh": p["mesh"], "sway": sway}
			by_key[key] = layer
			layers.append(layer)
		_prop_defs[kind] = layers
	_merged_props.clear()
	var rigid_mat := ShaderMaterial.new()
	rigid_mat.shader = preload("res://shaders/prop_rigid.gdshader")
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = preload("res://shaders/prop_leaves.gdshader")
	for kind in DRAW_TYPES:
		_merged_props[kind] = _merge_parts(kind, parts[kind], rigid_mat, leaf_mat)
	if nature_models:
		_use_nature_models()
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


## Swaps the merged meshes of NATURE_MODELS' prop types for the textured
## models. Each model has the same two kinds of surface as a merged prop (rigid
## and leaves), so a chunk still draws one MultiMesh per type, and the textures
## and materials are shared by every model that uses them.
func _use_nature_models() -> void:
	var rigid := preload("res://shaders/prop_tex_rigid.gdshader")
	var leaves := preload("res://shaders/prop_tex_leaves.gdshader")
	var materials := {}
	var meshes := {}
	_nature_far.clear()
	_nature_shadow.clear()
	for kind in NATURE_MODELS:
		var file: String = NATURE_MODELS[kind]
		if kind != "rock":  # rocks are solid: they cast their own shadow
			_nature_shadow[kind] = _merged_props[kind]  # the procedural mesh, before it's swapped
		for variant in [file, file + "_far"]:
			if meshes.has(variant) or not ResourceLoader.exists("res://models/nature/%s.glb" % variant):
				continue
			var scene := load("res://models/nature/%s.glb" % variant) as PackedScene
			var root := scene.instantiate()
			var mesh := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh as ArrayMesh
			root.free()
			for s in mesh.get_surface_count():
				var mat_name := mesh.surface_get_material(s).resource_name
				var tex: String = NATURE_TEXTURES[mat_name]
				if not materials.has(tex):
					var mat := ShaderMaterial.new()
					mat.resource_name = mat_name  # the imported mesh is cached: found by the same name next time
					mat.shader = rigid if tex in ["bark", "rock"] else leaves
					mat.set_shader_parameter("albedo", load("res://models/nature/%s.png" % tex))
					materials[tex] = mat
				mesh.surface_set_material(s, materials[tex])
			meshes[variant] = mesh
		_merged_props[kind] = meshes[file]
		if meshes.has(file + "_far"):
			_nature_far[kind] = meshes[file + "_far"]


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


## Merges every part of a prop type into one mesh: a surface for the rigid
## parts and one for the leaves. Each vertex carries its part's colour and sway
## (see props.gdshaderinc), so one MultiMesh instance draws the whole prop.
func _merge_parts(kind: String, kind_parts: Array, rigid_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var groups := {"rigid": [], "leaf": []}
	for p in kind_parts:
		groups["leaf" if float(p["sway"]) > 0.0 else "rigid"].append(p)
	var mesh := ArrayMesh.new()
	for group in ["rigid", "leaf"]:
		if groups[group].is_empty():
			continue
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for p in groups[group]:
			var arrays: Array = (p["mesh"] as PrimitiveMesh).get_mesh_arrays()
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var scale: Vector3 = p["scale"]
			var offset: Vector3 = p["offset"]
			var base: Color = p["color"]
			var sway := float(p["sway"])
			var part := sway if sway > 0.0 else (-1.0 if kind == "bush" else 0.0)  # a bush's rigid parts are its berries
			var first := verts.size()
			for i in pv.size():
				verts.append(pv[i] * scale + offset)
				normals.append((pn[i] / scale).normalized())
				uvs.append(Vector2(base.r, base.g))
				uv2s.append(Vector2(base.b, part))
				colors.append(Color.WHITE)
			for i in pi:
				indices.append(first + i)
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TEX_UV] = uvs
		out[Mesh.ARRAY_TEX_UV2] = uv2s
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		mesh.surface_set_material(mesh.get_surface_count() - 1, leaf_mat if group == "leaf" else rigid_mat)
	return mesh


## A merged prop's per-instance colouring this season: [leaf tint (rgb, amount),
## (shade, frost on rocks and stumps, hide leaves, hide berries)]. The same
## rules as _season_color, worked out once per prop instead of once per part.
func _prop_instance_params(kind: String, cell: Vector2i) -> Array:
	var tint := Color(0, 0, 0, 0)
	var frost := 0.0
	var hide_leaves := 0.0
	var hide_berries := 0.0
	match season:
		"summer":
			tint = Color("6f7d34")
			tint.a = 0.15
		"autumn":
			if kind == "tree_oak":
				var turn := _hash01(cell.x, cell.y, 71)
				tint = Color("b4561e") if turn < 0.4 else (Color("c98a24") if turn < 0.75 else Color("8e3a1c"))
				tint.a = 0.75
			elif kind == "bush":
				tint = Color("7a5a2a")
				tint.a = 0.45
		"winter":
			if kind == "tree_oak":
				hide_leaves = 1.0
			else:
				tint = Color(0.9, 0.93, 0.96, 0.55)
			if kind == "bush":
				hide_berries = 1.0
			if kind in ["rock", "iron_rock", "gold_rock", "stump"]:
				frost = 0.3
	if kind == "bush_empty" and nature_models:
		hide_berries = 1.0  # a picked bush is the bush model without its flowers
	var shade := (_hash01(cell.x, cell.y, 6) - 0.5) * 0.22
	return [tint, Color(shade, frost, hide_leaves, hide_berries)]


## A change to the prop on `cell` (felled, picked, regrown, built over):
## only its chunk is rebuilt.
func _mark_props_dirty(cell: Vector2i) -> void:
	var ck := _prop_chunk_of_cell(cell)
	if _prop_chunks.has(ck):
		_dirty_prop_chunks[ck] = true


func _prop_chunk_of_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / prop_chunk), floori(float(cell.y) / prop_chunk))


## The tiles a prop chunk covers.
func _prop_chunk_rect(pck: Vector2i) -> Rect2i:
	return Rect2i(pck * prop_chunk, Vector2i(prop_chunk, prop_chunk))


## The area whose props are drawn: the same PROP_VIEW terrain chunks around the
## player as always, plus `extra` more terrain chunks each way.
func _prop_window(extra: int) -> Rect2i:
	var r := PROP_VIEW + extra
	return Rect2i((_view_chunk - Vector2i(r, r)) * CHUNK, Vector2i(2 * r + 1, 2 * r + 1) * CHUNK)


## The prop chunks that overlap `area` (and the island).
func _prop_chunks_over(area: Rect2i) -> Array:
	area = area.intersection(Rect2i(0, 0, SIZE, SIZE))
	var out := []
	if area.size.x <= 0 or area.size.y <= 0:
		return out
	var a := _prop_chunk_of_cell(area.position)
	var b := _prop_chunk_of_cell(area.end - Vector2i.ONE)
	for z in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			out.append(Vector2i(x, z))
	return out


## The props in one prop chunk, gathered from the terrain chunks under it.
func _prop_chunk_cells(pck: Vector2i) -> Array:
	var rect := _prop_chunk_rect(pck)
	var a := _chunk_of_cell(rect.position)
	var b := _chunk_of_cell(rect.end - Vector2i.ONE)
	var out := []
	for z in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var ck := Vector2i(x, z)
			if not _chunk_in_bounds(ck):
				continue
			for cell in _chunk_props(ck):
				if rect.has_point(cell):
					out.append(cell)
	return out


func _nearer_prop_chunk(a: Vector2i, b: Vector2i) -> bool:
	var centre := Vector2(_view_chunk * CHUNK) + Vector2(CHUNK, CHUNK) * 0.5
	var half := Vector2(prop_chunk, prop_chunk) * 0.5
	return (Vector2(a * prop_chunk) + half).distance_squared_to(centre) < (Vector2(b * prop_chunk) + half).distance_squared_to(centre)


## The prop chunks that are drawn: those overlapping the view window.
func _prop_view_chunks() -> Array:
	return _prop_chunks_over(_prop_window(0))


## On entering a new chunk: queue the chunks that came into view (nearest
## first), hide the ones that left it, and free those well out of it. Chunks
## one ring beyond the view are kept (hidden), so walking back and forth over
## a boundary rebuilds nothing, and the drawn area is the same as before.
func _queue_prop_chunks() -> void:
	_prop_queue.clear()
	for ck in _prop_view_chunks():
		if not _prop_chunks.has(ck):
			_prop_queue.append(ck)
	_prop_queue.sort_custom(_nearer_prop_chunk)
	var shown := _prop_window(0)
	var kept := _prop_window(1)
	for ck in _prop_chunks.keys():
		var rect := _prop_chunk_rect(ck)
		if not rect.intersects(kept):
			(_prop_chunks[ck]["node"] as Node3D).queue_free()
			_prop_chunks.erase(ck)
			_dirty_prop_chunks.erase(ck)
		else:
			(_prop_chunks[ck]["node"] as Node3D).visible = rect.intersects(shown)


## Builds queued chunks (one per frame, or all of them when `immediate`)
## and rebuilds changed ones. Grass follows the player, and is gathered again
## only when you move to a new chunk, the season turns, or a building changes.
func _update_props(immediate: bool, moved: bool) -> void:
	if _props_dirty:
		_props_dirty = false
		for ck in _prop_chunks:
			_dirty_prop_chunks[ck] = true
	for ck in _dirty_prop_chunks.keys():
		_build_prop_chunk(ck)
	_dirty_prop_chunks.clear()
	var budget := _prop_queue.size() if immediate else PROP_BUILDS_PER_FRAME
	while budget > 0 and not _prop_queue.is_empty():
		var ck: Vector2i = _prop_queue.pop_front()
		if not _prop_chunks.has(ck):
			_build_prop_chunk(ck)
		budget -= 1
	if moved or _grass_dirty:
		_refresh_grass()
	elif not immediate:
		_grass_prepare()


## (Re)builds one chunk's props: one small MultiMesh per layer of each prop
## type found there, so Godot can cull the chunk as a whole.
func _build_prop_chunk(ck: Vector2i) -> void:
	if _prop_chunks.has(ck):
		(_prop_chunks[ck]["node"] as Node3D).queue_free()
	var node := Node3D.new()
	node.name = "Props_%d_%d" % [ck.x, ck.y]
	_props_root.add_child(node)
	var cells_by_kind := {}
	var total := 0
	var tris := 0  # triangles in this chunk, for checking the renderer's culling
	var bounds := AABB()  # every prop's footprint and height, for measuring what's in view
	var has_bounds := false
	for cell in _prop_chunk_cells(ck):
		var kind := prop_type(cell)
		if kind == "tree":
			kind = _tree_kind(cell)
		if _prop_defs.has(kind):
			if not cells_by_kind.has(kind):
				cells_by_kind[kind] = []
			cells_by_kind[kind].append(cell)
			total += 1
	for kind in cells_by_kind:
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
			var box := AABB(origin - Vector3(2.0, 0.5, 2.0), Vector3(4.0, 7.0, 4.0))  # the tallest pine, scaled up
			bounds = box if not has_bounds else bounds.merge(box)
			has_bounds = true
		if prop_grouping:
			var gm := MultiMesh.new()
			gm.transform_format = MultiMesh.TRANSFORM_3D
			gm.use_colors = true
			gm.use_custom_data = true
			gm.mesh = _merged_props[kind]
			gm.instance_count = cells.size()
			for n in cells.size():
				var params := _prop_instance_params(kind, cells[n])
				gm.set_instance_transform(n, Transform3D(turns[n], origins[n]))
				gm.set_instance_color(n, params[0])
				gm.set_instance_custom_data(n, params[1])
			tris += cells.size() * _mesh_triangles(gm.mesh)
			var ginst := MultiMeshInstance3D.new()
			ginst.name = kind
			ginst.multimesh = gm
			ginst.extra_cull_margin = 0.5  # leaves sway a little outside their resting bounds
			node.add_child(ginst)
			if _nature_shadow.has(kind):
				ginst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(_prop_copy(kind + "_shadow", _nature_shadow[kind], gm, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY))
			if _nature_far.has(kind):
				# The same props drawn with the far model once the chunk is
				# NATURE_NEAR from the camera; only one of the two is ever drawn.
				ginst.visibility_range_end = NATURE_NEAR
				var finst := _prop_copy(kind + "_far", _nature_far[kind], gm, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				finst.visibility_range_begin = NATURE_NEAR
				node.add_child(finst)
			continue
		for layer in _prop_defs[kind]:
			var layer_parts: Array = layer["parts"]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = layer["mesh"]
			mm.instance_count = cells.size() * layer_parts.size()
			var i := 0
			for p in layer_parts:
				var base_color: Color = p["color"]
				var offset: Vector3 = p["offset"]
				var part_scale := Basis.from_scale(p["scale"])
				for n in cells.size():
					var cell: Vector2i = cells[n]
					var turn: Basis = turns[n]
					var origin: Vector3 = origins[n]
					var shade := (_hash01(cell.x, cell.y, 6) - 0.5) * 0.22
					var c := _season_color(kind, p, base_color, cell)
					if c.a <= 0.0:
						mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), origin))
						mm.set_instance_color(i, base_color)
					else:
						mm.set_instance_transform(i, Transform3D(turn * part_scale, origin + turn * offset))
						mm.set_instance_color(i, c.lightened(shade) if shade > 0.0 else c.darkened(-shade))
					i += 1
			tris += mm.instance_count * _mesh_triangles(mm.mesh)
			var inst := MultiMeshInstance3D.new()
			inst.name = kind
			inst.multimesh = mm
			inst.material_override = layer["material"]
			if float(layer["sway"]) > 0.0:
				inst.extra_cull_margin = 0.5  # leaves sway a little outside their resting bounds
			node.add_child(inst)
	node.visible = _prop_chunk_rect(ck).intersects(_prop_window(0))
	_prop_chunks[ck] = {"node": node, "props": total, "tris": tris, "bounds": bounds if has_bounds else null}


## Another MultiMeshInstance3D drawing the same props as `source` (same
## places, sizes and seasonal data) with a different mesh: the nature models'
## far versions and shadow proxies.
func _prop_copy(copy_name: String, mesh: Mesh, source: MultiMesh, shadows: GeometryInstance3D.ShadowCastingSetting) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = source.instance_count
	mm.buffer = source.buffer
	var inst := MultiMeshInstance3D.new()
	inst.name = copy_name
	inst.multimesh = mm
	inst.extra_cull_margin = 0.5  # leaves sway a little outside their resting bounds
	inst.cast_shadow = shadows
	return inst


var _mesh_tris: Dictionary = {}  # mesh instance id -> triangle count


func _mesh_triangles(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if not _mesh_tris.has(id):
		var n := 0
		for i in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(i)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			n += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		_mesh_tris[id] = n
	return _mesh_tris[id]


## Trees, rocks and bushes in the chunks being drawn (not the hidden spare ring).
func drawn_prop_count() -> int:
	var n := 0
	for ck in _prop_chunks:
		if (_prop_chunks[ck]["node"] as Node3D).visible:
			n += int(_prop_chunks[ck]["props"])
	return n


## Prop chunks and props inside `camera`'s view (a chunk counts if any of it is).
## For measuring; the renderer does its own culling.
func props_in_view(camera: Camera3D) -> Dictionary:
	var planes := camera.get_frustum()
	var chunks := 0
	var props := 0
	var tris_in_view := 0
	for ck in _prop_chunks:
		var node: Node3D = _prop_chunks[ck]["node"]
		if not node.visible or _prop_chunks[ck]["bounds"] == null:
			continue
		var box: AABB = _prop_chunks[ck]["bounds"]
		var inside := true
		for plane in planes:
			if _box_outside(plane, box):
				inside = false
				break
		if inside:
			chunks += 1
			props += int(_prop_chunks[ck]["props"])
			tris_in_view += int(_prop_chunks[ck]["tris"])
	var shown := 0
	var tris_drawn := 0
	var nodes := 0
	var props_built := 0
	for ck in _prop_chunks:
		props_built += int(_prop_chunks[ck]["props"])
		if (_prop_chunks[ck]["node"] as Node3D).visible:
			shown += 1
			tris_drawn += int(_prop_chunks[ck]["tris"])
			nodes += (_prop_chunks[ck]["node"] as Node3D).get_child_count()
	return {"chunks_built": _prop_chunks.size(), "chunks_drawn": shown, "chunks_in_view": chunks,
		"props_drawn": drawn_prop_count(), "props_in_view": props, "tris_drawn": tris_drawn, "tris_in_view": tris_in_view,
		"multimeshes": nodes, "chunk_m": prop_chunk, "grouped": prop_grouping, "props_built": props_built}


## Camera3D.get_frustum() planes point outwards: a box is outside a plane when
## even its corner deepest inside lies in front of (outside) it.
static func _box_outside(plane: Plane, box: AABB) -> bool:
	var inner := Vector3(box.position.x if plane.normal.x > 0.0 else box.end.x,
		box.position.y if plane.normal.y > 0.0 else box.end.y,
		box.position.z if plane.normal.z > 0.0 else box.end.z)
	return plane.is_point_over(inner)


## Shows or hides every prop chunk (for the benchmark's diagnostics).
func set_props_visible(on: bool) -> void:
	_props_root.visible = on


## Grass around the player: a circle GRASS_RADIUS tiles across, centred on
## the chunk you're in. Each chunk's grass is worked out once (per season) as
## ready-made MultiMesh data in rows, so following the player only copies rows.
func _refresh_grass() -> void:
	_grass_dirty = false
	if season == "winter":
		_grass.multimesh.instance_count = 0  # under the snow
		return
	var center := _view_chunk * CHUNK + Vector2i(CHUNK / 2, CHUNK / 2)
	var r2 := GRASS_RADIUS * GRASS_RADIUS
	var out := PackedFloat32Array()
	for dz in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
		var z := center.y + dz
		if z < 0 or z >= SIZE:
			continue
		var half := int(sqrt(float(r2 - dz * dz)))
		while (half + 1) * (half + 1) + dz * dz <= r2:
			half += 1
		while half * half + dz * dz > r2:
			half -= 1
		var x0 := maxi(center.x - half, 0)
		var x1 := mini(center.x + half, SIZE - 1)
		for kx in range(x0 / CHUNK, x1 / CHUNK + 1):
			var ck := Vector2i(kx, z / CHUNK)
			var row: Array = _grass_rows(ck)[z - ck.y * CHUNK]
			var xs: PackedInt32Array = row[0]
			if xs.is_empty():
				continue
			var a := xs.bsearch(x0, true)
			var b := xs.bsearch(x1 + 1, true)
			if b > a:
				out.append_array((row[1] as PackedFloat32Array).slice(a * GRASS_FLOATS, b * GRASS_FLOATS))
	var mm := _grass.multimesh
	mm.instance_count = out.size() / GRASS_FLOATS
	if not out.is_empty():
		mm.buffer = out


## One chunk's grass, row by row: [cell x of each clump (ascending), and each
## clump's MultiMesh data: a 3x4 transform then a colour, GRASS_FLOATS floats].
func _grass_rows(ck: Vector2i) -> Array:
	if not _grass_cache.has(ck):
		_grass_work(ck, CHUNK)
	return _grass_cache[ck]


## Works out up to `budget` more rows of a chunk's grass. Returns how many it did.
func _grass_work(ck: Vector2i, budget: int) -> int:
	var rows: Array = _grass_partial.get(ck, [])
	var done := 0
	while rows.size() < CHUNK and done < budget:
		rows.append(_grass_row(ck, rows.size()))
		done += 1
	if rows.size() == CHUNK:
		_grass_partial.erase(ck)
		_grass_cache[ck] = rows
	else:
		_grass_partial[ck] = rows
	return done


## Before you get there: works out the grass of the chunks just beyond the
## patch around you, a few rows a frame, so moving on only copies ready rows.
func _grass_prepare() -> void:
	if season == "winter":
		return
	var budget := GRASS_ROWS_PER_FRAME
	for r in range(0, 4):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var ck := _view_chunk + Vector2i(dx, dz)
				if _grass_cache.has(ck) or not _chunk_in_bounds(ck):
					continue
				budget -= _grass_work(ck, budget)
				if budget <= 0:
					return


## One row of a chunk's grass: [cell x of each clump, and their MultiMesh data].
func _grass_row(ck: Vector2i, lz: int) -> Array:
	var xs := PackedInt32Array()
	var data := PackedFloat32Array()
	for lx in CHUNK:
		var cell := Vector2i(ck.x * CHUNK + lx, ck.y * CHUNK + lz)
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
			var basis := Basis(Vector3.UP, jx * TAU) * Basis.from_scale(Vector3(s, s, s))
			var origin := Vector3(p.x, y - 0.02, p.y)
			var g := _hash01(cell.x, cell.y, 50 + c)
			var tint := Color("50652c").lerp(Color("7a7a42"), g * 0.8) if t == GRASS else Color("3b4c25")
			if season == "autumn":
				tint = tint.lerp(Color("8a6a34"), 0.45)
			elif season == "summer":
				tint = tint.lerp(Color("8a8040"), 0.2)
			xs.append(cell.x)
			data.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, origin.x,
				basis.x.y, basis.y.y, basis.z.y, origin.y,
				basis.x.z, basis.y.z, basis.z.z, origin.z,
				tint.r, tint.g, tint.b, tint.a]))
	return [xs, data]


## Something was built or taken down: that chunk's grass is worked out again.
func _grass_changed(cell: Vector2i) -> void:
	_grass_cache.erase(_chunk_of_cell(cell))
	_grass_partial.erase(_chunk_of_cell(cell))
	_grass_dirty = true


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
	_grass_cache.clear()  # the grass is tinted by season
	_grass_partial.clear()
	_grass_dirty = true


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
