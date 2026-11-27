## Builds the village buildings (GRAPHICS_VILLAGE_BUILDINGS.md) from
## Quaternius' Medieval Village MegaKit and Fantasy Props MegaKit (both CC0,
## models/CREDITS.md): two cottages (plastered, and stone), the workbench,
## the smokehouse and the barracks.
##
## Each building is the kits' modular pieces placed together and merged into
## one mesh, scaled to its tile. Every surface of every building uses one
## material (shaders/village.gdshader) over one texture array
## (models/village/village_textures.png: the kits' ten colour maps, 256² each),
## the layer in UV2.x: one draw call per building, plus one for the glow of
## its windows (an inner box, seen through the window openings).
##
## SRC: a folder with models/ (the kits' .gltf + .bin) and textures/ (their
## BaseColor maps, any format Image loads).
##   SRC=... godot --headless --path last-light/game --script res://tools/build_village_models.gd
## Run once to write the texture strip, then `godot --import`, then again.
extends SceneTree

const OUT := "res://models/village/"
const SIZE := 256  # each texture layer
## Texture layers, in order: the source map's name and the kit materials using it.
const LAYERS := [["T_WoodTrim_BaseColor", ["MI_WoodTrim", "MI_WoodTrim_Wear"]],
	["T_Plaster_BaseColor", ["MI_Plaster"]], ["T_RockTrim_BaseColor", ["MI_RockTrim"]],
	["T_Brick_BaseColor", ["MI_Brick"]], ["T_UnevenBrick_BaseColor", ["MI_UnevenBrick"]],
	["T_RoundTiles_BaseColor", ["MI_RoundTiles"]], ["T_Trim_Furniture_BaseColor", ["MI_Trim_Furniture"]],
	["T_Trim_Metal_BaseColor", ["MI_Trim_Metal"]], ["T_Trim_Props_BaseColor", ["MI_Trim_Props_Vertex", "MI_Trim_Props"]],
	["T_Trim_Cloth_BaseColor", ["MI_Trim_Cloth", "MI_Banner"]]]
const WOOD := 0
const UNEVEN := 4
const ROCK := 2
## Kit metres to game metres, matching the KayKit cottage they replace
## (about 2 m across and 2.4 m tall): buildings reach a little past their tile,
## as before.
const COTTAGE_SCALE := 0.35
const BARRACKS_SCALE := 0.33
const SMOKEHOUSE_SCALE := 0.28
const WORKBENCH_SCALE := 0.65
## The barracks' banners, dyed the legion's red.
const BANNER_RED := Color(0.72, 0.16, 0.12)

var _src := ""
var _pieces := {}  # name -> Array of [arrays, layer]
## The building being made: merged arrays (main surface) and the glow box.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _col := PackedColorArray()
var _idx := PackedInt32Array()
var _glow := []  # [Vector3 centre, Vector3 size] boxes


func _initialize() -> void:
	_src = OS.get_environment("SRC")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not FileAccess.file_exists(ProjectSettings.globalize_path(OUT + "village_textures.png")) or OS.get_environment("REPAINT") == "1":
		_write_strip()
		print("(texture strip written: run --import, then this tool again)")
		quit()
		return
	var material := _material()
	var built := {
		"cottage_plaster": _cottage(false), "cottage_stone": _cottage(true), "smokehouse": _smokehouse(),
		"barracks": _barracks(), "workbench": _workbench(),
	}
	for name: String in built:
		var mesh: ArrayMesh = built[name]
		mesh.surface_set_material(0, material)
		var err := ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
		var tris := 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(s) / 3
		print("%s: %d surfaces, %d triangles, aabb %s, %s" % [name, mesh.get_surface_count(), tris, mesh.get_aabb(), error_string(err)])
	quit()


# ---------- Textures ----------

## The ten colour maps, downsized, stacked into one image (imported as a
## Texture2DArray of 10 layers).
func _write_strip() -> void:
	var strip := Image.create(SIZE, SIZE * LAYERS.size(), false, Image.FORMAT_RGB8)
	for i in LAYERS.size():
		var base := _src.path_join("textures").path_join(str(LAYERS[i][0]))
		var img: Image = null
		for ext in [".png", ".webp", ".jpg"]:
			if FileAccess.file_exists(base + ext):
				img = Image.load_from_file(base + ext)
				break
		assert(img != null, "missing texture " + base)
		img.convert(Image.FORMAT_RGB8)
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i(0, i * SIZE))
	strip.save_png(ProjectSettings.globalize_path(OUT + "village_textures.png"))
	var imp := FileAccess.open(ProjectSettings.globalize_path(OUT + "village_textures.png.import"), FileAccess.WRITE)
	imp.store_string("[remap]\n\nimporter=\"2d_array_texture\"\ntype=\"CompressedTexture2DArray\"\n\n[params]\n\n" +
		"compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n" +
		"compress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n" % LAYERS.size())
	imp.close()


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/village.gdshader")
	m.set_shader_parameter("textures", load(OUT + "village_textures.png"))
	ResourceSaver.save(m, OUT + "village.tres")
	return load(OUT + "village.tres")


# ---------- Pieces ----------

## A kit piece's surfaces, each with its texture layer (loaded once).
func _piece(name: String) -> Array:
	if not _pieces.has(name):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(_src.path_join("models").path_join(name + ".gltf"), state)
		assert(err == OK, "missing piece " + name)
		var scene := doc.generate_scene(state)
		var out := []
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat_name: String = mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
				var layer := -1
				for i in LAYERS.size():
					if mat_name in LAYERS[i][1]:
						layer = i
				assert(layer >= 0, "%s: unknown material %s" % [name, mat_name])
				out.append([mesh.surface_get_arrays(s), layer])
		scene.free()
		_pieces[name] = out
	return _pieces[name]


func _begin() -> void:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_uv = PackedVector2Array()
	_uv2 = PackedVector2Array()
	_col = PackedColorArray()
	_idx = PackedInt32Array()
	_glow = []


## Adds a piece at a transform; `tint` dyes the given layer (banners).
func _add(name: String, xf: Transform3D, tint_layer := -1, tint := Color.WHITE) -> void:
	for surf: Array in _piece(name):
		var a: Array = surf[0]
		var layer: int = surf[1]
		var base := _v.size()
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var c := tint if layer == tint_layer else Color.WHITE
		for i in pv.size():
			_v.append(xf * pv[i])
			_n.append((xf.basis * pn[i]).normalized())
			_uv.append(pu[i])
			_uv2.append(Vector2(layer, 0))
			_col.append(c)
		var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in pi:
			_idx.append(base + i)


## A box (outward faces) on a texture layer, its UVs spanning `uv_rect`
## on every face (a chimney, a door).
func _box(centre: Vector3, size: Vector3, layer: int, uv_rect: Rect2, skip_bottom := true) -> void:
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD]]
	for f in faces:
		var normal: Vector3 = f[0]
		if skip_bottom and normal == Vector3.DOWN:
			continue
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var c: Vector3 = centre + normal * h.abs().dot(normal.abs())
		var su := h.abs().dot(u.abs())
		var sw := h.abs().dot(w.abs())
		var base := _v.size()
		for k in 4:
			var du := -1.0 if k == 0 or k == 3 else 1.0
			var dw := -1.0 if k < 2 else 1.0
			_v.append(c + u * du * su + w * dw * sw)
			_n.append(normal)
			_uv.append(uv_rect.position + Vector2((du + 1.0) * 0.5, 1.0 - (dw + 1.0) * 0.5) * uv_rect.size)
			_uv2.append(Vector2(layer, 0))
			_col.append(Color.WHITE)
		# Godot's front faces are clockwise seen from outside.
		for t in [0, 2, 1, 0, 3, 2]:
			_idx.append(base + t)


## A storey of walls round a square of `side` wall pieces each way (2 m
## each), centred, at height y. `walls`: front, right, back, left lists.
func _storey(walls: Array, y: float, side := 2) -> void:
	var half := side  # metres from the centre to a wall's outer face
	for s in 4:
		var list: Array = walls[s]
		var turn := Basis(Vector3.UP, -PI * 0.5 * s)  # front (+z), right (+x), back, left
		for i in side:
			var along := -side + 1.0 + i * 2.0
			var at := turn * Vector3(along, y, half)
			_add(str(list[i % list.size()]), Transform3D(turn, at))


## A plank door filling a doorway, a little inside the wall's face.
func _door(x: float, half: float, round_top: bool) -> void:
	# Dark planks: the wood trim's second band.
	_box(Vector3(x, 1.05, half - 0.12), Vector3(1.0, 2.1 if not round_top else 2.3, 0.04), WOOD, Rect2(0.02, 0.33, 0.45, 0.25), false)


## Ends the building: the merged surface, the window-glow box, scaled and LODs.
func _finish(scale: float) -> ArrayMesh:
	var xf := Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO)
	for i in _v.size():
		_v[i] = xf * _v[i]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_INDEX] = _idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "Village", Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	if not _glow.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for g: Array in _glow:
			var mesh := BoxMesh.new()
			mesh.size = (g[1] as Vector3) * scale
			st.append_from(mesh, 0, Transform3D(Basis(), (g[0] as Vector3) * scale))
		var glow_mat := StandardMaterial3D.new()
		glow_mat.resource_name = "WindowGlow"
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, glow_mat, "WindowGlow")
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


# ---------- Buildings ----------

## A 4 x 4 m cottage: two wall pieces a side, 3 m walls, a tiled roof with
## timbered gables, a stone chimney. Plastered and timbered, or of fieldstone.
func _cottage(stone: bool) -> ArrayMesh:
	_begin()
	var p := "Wall_UnevenBrick_" if stone else "Wall_Plaster_"
	var front := [p + "Door_Round", p + "Window_Wide_Round"]
	var right := [p + "Window_Thin_Round", p + "Straight"] if not stone else [p + "Window_Wide_Flat", p + "Straight"]
	var back := [p + "Straight", p + "Window_Wide_Round"] if not stone else [p + "Straight", p + "Window_Thin_Round"]
	var left := [p + "Straight", p + "Window_Thin_Round"]
	_storey([front, right, back, left], 0.0)
	_door(-1.0, 2.0, true)
	_roof(3.0, false)
	_chimney(Vector3(1.15, 0, -0.9), 6.3)
	_glow.append([Vector3(0, 1.45, 0), Vector3(3.5, 2.8, 3.5)])
	return _finish(COTTAGE_SCALE)


## The 4 x 4 tiled roof and its two gable ends, at the top of the walls.
func _roof(y: float, plain_gables: bool) -> void:
	_add("Roof_RoundTiles_4x4", Transform3D(Basis(), Vector3(0, y, 0)))
	for z: float in [2.0, -2.0]:
		_add("Roof_Front_Brick4", Transform3D(Basis(Vector3.UP, 0.0 if z > 0.0 else PI), Vector3(0, y, z)))


## A fieldstone chimney rising through the roof, capped with dressed stone.
func _chimney(at: Vector3, top: float) -> void:
	var w := 0.62
	var bottom := 3.6
	_box(Vector3(at.x, (bottom + top) * 0.5, at.z), Vector3(w, top - bottom, w), UNEVEN, Rect2(0.0, 0.0, 0.35, 0.9))
	_box(Vector3(at.x, top + 0.06, at.z), Vector3(w + 0.12, 0.12, w + 0.12), ROCK, Rect2(0.0, 0.33, 0.5, 0.25))


## The smokehouse: a small, windowless fieldstone house with a big chimney
## (the old smoke rises from it: structure.gd).
func _smokehouse() -> ArrayMesh:
	_begin()
	var w := "Wall_UnevenBrick_"
	_storey([[w + "Door_Flat", w + "Straight"], [w + "Straight"], [w + "Straight"], [w + "Straight"]], 0.0)
	_door(-1.0, 2.0, false)
	_roof(3.0, true)
	_chimney(Vector3(1.0, 0, -0.6), 6.8)
	return _finish(SMOKEHOUSE_SCALE)


## The barracks: two storeys (a fieldstone ground floor, a plastered and
## timbered upper floor) under the tiled roof, the legion's red banners
## on the front, a bench by the door.
func _barracks() -> ArrayMesh:
	_begin()
	var s := "Wall_UnevenBrick_"
	var p := "Wall_Plaster_"
	_storey([[s + "Door_Round", s + "Window_Wide_Flat"], [s + "Window_Wide_Flat", s + "Straight"],
		[s + "Straight", s + "Window_Wide_Flat"], [s + "Straight", s + "Window_Wide_Flat"]], 0.0)
	_storey([[p + "Window_Wide_Round", p + "Window_Wide_Round"], [p + "Window_Thin_Round", p + "Window_Thin_Round"],
		[p + "Window_Wide_Round", p + "Window_Wide_Round"], [p + "Window_Thin_Round", p + "Window_Thin_Round"]], 3.0)
	_door(-1.0, 2.0, true)
	_roof(6.0, false)
	_chimney(Vector3(-1.1, 0, -1.0), 9.2)
	# The legion's red: a banner hung flat on the front between the upper
	# windows, and one on an iron arm out from each side wall.
	_add("Banner_1_Cloth", Transform3D(Basis().scaled(Vector3.ONE * 0.75), Vector3(0, 5.85, 2.12)), 9, BANNER_RED)
	for side: float in [1.0, -1.0]:
		var out := Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
		_add("Banner_2", Transform3D(out.scaled(Vector3.ONE * 0.7), Vector3(side * 2.02, 4.7, 0.6)), 9, BANNER_RED)
	_add("Bench", Transform3D(Basis().scaled(Vector3.ONE * 0.8), Vector3(1.0, 0, 2.55)))
	_glow.append([Vector3(0, 2.95, 0), Vector3(3.5, 5.8, 3.5)])
	return _finish(BARRACKS_SCALE)


## The workbench: the carpenter's bench with its drawer box, a grindstone
## beside it.
func _workbench() -> ArrayMesh:
	_begin()
	_add("Workbench", Transform3D(Basis(), Vector3(-0.15, 0, -0.1)))
	_add("Workbench_Drawers", Transform3D(Basis(), Vector3(-0.15, 0, -0.1)))
	_add("Whetstone", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 0.75), Vector3(1.05, 0, 0.35)))
	return _finish(WORKBENCH_SCALE)
