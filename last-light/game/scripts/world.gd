## The island: terrain generated from the daily seed, plus harvestable props
## (trees, rocks, berry bushes). Everything here is deterministic for a seed,
## so every player on the same day gets the same island.
extends Node2D

const TILE := 16
const SIZE := 160
const NO_CELL := Vector2i(-1, -1)

enum { DEEP, WATER, SAND, GRASS, FOREST, ROCK }

const TERRAIN_COLORS := [
	Color("1d3b5c"),  # deep water
	Color("2f6a8f"),  # shallow water
	Color("d8c58a"),  # sand
	Color("6e9b4a"),  # grass
	Color("4a7a3a"),  # forest floor
	Color("8a8577"),  # rock
]

var seed_value := 0
var terrain := PackedByteArray()
## Vector2i cell -> {"type": String, "hp": int, "regrow_day": int}
var props: Dictionary = {}
var spawn_cell := Vector2i.ZERO


func generate(p_seed: int) -> void:
	seed_value = p_seed
	terrain.resize(SIZE * SIZE)
	props.clear()

	var elevation := FastNoiseLite.new()
	elevation.seed = p_seed
	elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation.frequency = 0.03
	elevation.fractal_octaves = 4

	var moisture := FastNoiseLite.new()
	moisture.seed = p_seed + 7919
	moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture.frequency = 0.045

	var center := Vector2(SIZE, SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(center) / (SIZE * 0.5)
			var e := elevation.get_noise_2d(x, y) * 0.5 + 0.5
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

	_find_spawn()
	_place_props()
	_render_terrain()
	queue_redraw()


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
		"rock":
			gained = {"stone": 1}
			prop["hp"] = int(prop["hp"]) - 1
			if int(prop["hp"]) <= 0:
				props.erase(cell)
		"bush":
			gained = {"berries": 3}
			prop["type"] = "bush_empty"
			prop["regrow_day"] = day + 2
	queue_redraw()
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
		queue_redraw()


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


func _render_terrain() -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var t := terrain[y * SIZE + x]
			var color: Color = TERRAIN_COLORS[t]
			var h := _hash01(x, y)
			if t == DEEP or t == WATER:
				color = color.lightened(h * 0.05)
			else:
				color = color.darkened(h * 0.1)
			# A wet-sand rim where land meets water.
			if t == SAND and _touches_water(x, y):
				color = color.darkened(0.12)
			image.set_pixel(x, y, color)

	var sprite := Sprite2D.new()
	sprite.name = "Terrain"
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.scale = Vector2(TILE, TILE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.show_behind_parent = true
	for child in get_children():
		child.queue_free()
	add_child(sprite)


func _touches_water(x: int, y: int) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := terrain_at(Vector2i(x, y) + offset)
		if t == WATER or t == DEEP:
			return true
	return false


func _hash01(x: int, y: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (seed_value * 83492791)
	return float(absi(h) % 1000) / 1000.0


func _draw() -> void:
	for cell in props:
		var prop: Dictionary = props[cell]
		var c := cell_center(cell)
		match str(prop["type"]):
			"tree":
				draw_circle(c + Vector2(1, 5), 7.0, Color(0, 0, 0, 0.22))
				draw_rect(Rect2(c + Vector2(-1.5, 1), Vector2(3, 6)), Color("5a3d22"))
				draw_circle(c + Vector2(0, -1), 7.5, Color("1f4526"))
				draw_circle(c + Vector2(-2, -3), 5.0, Color("2d6136"))
			"stump":
				draw_circle(c, 3.5, Color("5a3d22"))
				draw_circle(c, 2.0, Color("9c7a4f"))
			"rock":
				var pts := PackedVector2Array([
					c + Vector2(-7, 4), c + Vector2(-5, -4), c + Vector2(1, -7),
					c + Vector2(7, -2), c + Vector2(6, 5),
				])
				draw_colored_polygon(pts, Color("6f6b62"))
				draw_line(c + Vector2(-3, -2), c + Vector2(2, -4), Color("a39e91"), 1.5)
			"bush":
				draw_circle(c, 6.0, Color("2e5a2a"))
				for o in [Vector2(-2, -2), Vector2(3, -1), Vector2(0, 3), Vector2(-3, 2)]:
					draw_circle(c + o, 1.3, Color("d6334a"))
			"bush_empty":
				draw_circle(c, 5.0, Color("3a5a30"))
