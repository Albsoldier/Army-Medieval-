## Builds the realistic swords and axes (phase 4E.1, GRAPHICS_PHASE_4E1_SWORDS.md)
## into models/weapons/: original geometry and textures, made here (no
## third-party assets):
##   - weapons_colour.png and weapons_orm.png: one shared 256 x 256 atlas in
##     columns: bright steel, iron, rusty iron, gold, bronze, wood, weathered
##     wood / leather wrap, red leather / dark steel fittings. Brushing,
##     scratches, honed edges, pitting, rust, grain and wraps are painted from
##     noise; roughness (G) and metal (B) vary with them.
##   - weapons.tres: one StandardMaterial3D for every weapon.
##   - gladius.res (the iron sword), spatha.res (steel), gilded_sword.res,
##     axe.res (the player's) and raider_axe.res: one surface each.
## Each weapon keeps the old one's frame: the grip at the origin (the hand),
## the blade or haft along +y, sword flats facing +-z, axe blades towards +z.
## Run it twice, importing in between (the second run points the material at
## the imported textures; REPAINT=1 paints the atlas again):
##   godot --headless --path last-light/game --script res://tools/build_weapon_models.gd
##   godot --headless --path last-light/game --import   (then run the tool again)
extends SceneTree

const OUT := "res://models/weapons/"
const SIZE := 256
const COL := 32  # each material's column in the atlas
## Columns (x) and their part of the height (v range).
const REGIONS := {
	"steel": [0, 0.0, 1.0], "iron": [1, 0.0, 1.0], "rust": [2, 0.0, 1.0], "gold": [3, 0.0, 1.0],
	"bronze": [4, 0.0, 1.0], "wood": [5, 0.0, 1.0], "darkwood": [6, 0.0, 0.5], "leather": [6, 0.5, 1.0],
	"redleather": [7, 0.0, 0.5], "darksteel": [7, 0.5, 1.0],
}

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _st: SurfaceTool
var _group := 1
var _atlas := "weapons"  # which atlas _uv maps into: "weapons" or "shields"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_rng.seed = 4101
	_noise.seed = 4101
	_noise.frequency = 1.0
	# TARGETS: what to build: swords (the swords and axes, 4E.1; the default),
	# spears and shields (4E.2). Building spears or shields leaves the swords'
	# files alone.
	var targets := OS.get_environment("TARGETS").split(",", false)
	if targets.is_empty():
		targets = PackedStringArray(["swords"])
	var painted := false
	if "swords" in targets and (OS.get_environment("REPAINT") == "1"
			or not FileAccess.file_exists(ProjectSettings.globalize_path(OUT + "weapons_colour.png"))):
		_paint_atlas()
		painted = true
	if ("spears" in targets or "shields" in targets) and (OS.get_environment("REPAINT_SHIELDS") == "1"
			or not FileAccess.file_exists(ProjectSettings.globalize_path(OUT + "shields_colour.png"))):
		_paint_shields()
		painted = true
	if painted:
		print("(atlas painted: run --import, then this tool again)")
		quit()
		return
	var built := {}  # name -> [mesh, material]
	if "swords" in targets:
		var mat := _material()
		for item in [["gladius", _gladius()], ["spatha", _spatha()], ["gilded_sword", _gilded_sword()],
				["axe", _axe(false)], ["raider_axe", _axe(true)]]:
			built[item[0]] = [item[1], mat]
	if "spears" in targets:
		var weapons: Material = load(OUT + "weapons.tres")  # the swords' material, shared
		var shields := _shield_material()
		for kind in SPEARS:
			built[kind] = [_spear(kind), shields if kind == "spear_flint" else weapons]
	if "shields" in targets:
		var shields := _shield_material()
		built["scutum"] = [_scutum(false), shields]
		built["scutum_centurion"] = [_scutum(true), shields]
		built["shield_raider"] = [_round_shield(false), shields]
		built["shield_chief"] = [_round_shield(true), shields]
	for name in built:
		var mesh: ArrayMesh = built[name][0]
		mesh.surface_set_material(0, built[name][1])
		var err := ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
		var aabb := mesh.get_aabb()
		print("%s: %d triangles, %d vertices, %s .. %s, %s" % [name, mesh.surface_get_array_index_len(0) / 3,
			mesh.surface_get_array_len(0), aabb.position, aabb.end, error_string(err)])
	quit()


# ---------- The atlas ----------

func _paint_atlas() -> void:
	var colour := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var orm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var scratches := _scratch_map()
	for region in REGIONS:
		var r: Array = REGIONS[region]
		var y0 := int(float(r[1]) * SIZE)
		var y1 := int(float(r[2]) * SIZE)
		for y in range(y0, y1):
			for x in range(int(r[0]) * COL, (int(r[0]) + 1) * COL):
				var u := (x - int(r[0]) * COL + 0.5) / COL  # across the part (edge to edge)
				var v := (y - y0 + 0.5) / float(y1 - y0)  # along it
				var px: Array = _texel(region, u, v, float(scratches.get(Vector2i(x, y), 0.0)))
				colour.set_pixel(x, y, px[0])
				orm.set_pixel(x, y, Color(1.0, px[1], px[2]))
	colour.save_png(ProjectSettings.globalize_path(OUT + "weapons_colour.png"))
	orm.save_png(ProjectSettings.globalize_path(OUT + "weapons_orm.png"))


## Fine scratches: short random strokes, mostly along the length.
func _scratch_map() -> Dictionary:
	var out := {}
	for k in 380:
		var x := _rng.randf() * SIZE
		var y := _rng.randf() * SIZE
		var a := _rng.randf_range(-0.5, 0.5) + (PI / 2 if _rng.randf() < 0.75 else 0.0)
		var length := _rng.randf_range(3.0, 11.0)
		var strength := _rng.randf_range(0.25, 0.7)
		for s in int(length):
			var p := Vector2i(int(x + cos(a) * s), int(y + sin(a) * s))
			if p.x >= 0 and p.x < SIZE and p.y >= 0 and p.y < SIZE and p.x / COL == int(x) / COL:
				out[p] = strength
	return out


## [colour, roughness, metal] of one texel; u across, v along.
func _texel(region: String, u: float, v: float, scratch: float) -> Array:
	var along := _noise.get_noise_2d(u * 2.0, v * 40.0)  # slow along the length
	var brushed := _noise.get_noise_2d(u * 70.0 + 300.0, v * 3.0)  # fine streaks along it
	var blotch := _noise.get_noise_2d(u * 1.5 + 900.0, v * 5.0)  # broad wear and dirt
	var edge := minf(u, 1.0 - u)  # 0 at either edge
	match region:
		"steel", "iron", "rust", "darksteel":
			var base: Color = {"steel": Color(0.64, 0.66, 0.69), "iron": Color(0.44, 0.45, 0.47),
				"rust": Color(0.33, 0.32, 0.32), "darksteel": Color(0.27, 0.28, 0.30)}[region]
			var rough: float = {"steel": 0.3, "iron": 0.45, "rust": 0.6, "darksteel": 0.42}[region]
			var metal := 1.0
			var c := base * (1.0 + 0.07 * brushed + 0.05 * along)
			# Honed edges: a bright, smoother band; just inside it, darker from wear.
			if region != "darksteel" and edge < 0.13:
				c = c.lerp(Color(0.78, 0.8, 0.82), 0.55 if region != "rust" else 0.35)
				rough -= 0.1
			elif region != "darksteel" and edge < 0.2:
				c *= 0.88
			# Pitting and dirt; rust in patches on the raiders' axes.
			if region in ["iron", "rust"]:
				c *= 1.0 - 0.14 * smoothstep(0.15, 0.6, blotch)
				rough += 0.1 * smoothstep(0.15, 0.6, blotch)
			if region == "rust" and blotch < -0.15 and edge >= 0.13:
				c = c.lerp(Color(0.43, 0.25, 0.14), clampf((-0.15 - blotch) * 3.0, 0.0, 0.85))
				rough = 0.85
				metal = 0.35
			# Scratches: bright and a little rougher.
			c = c.lerp(Color(0.82, 0.83, 0.85), scratch * 0.22)
			rough += scratch * 0.06 + 0.04 * brushed
			return [Color(c.r, c.g, c.b), clampf(rough, 0.12, 1.0), metal]
		"gold", "bronze":
			var base: Color = Color(0.86, 0.65, 0.29) if region == "gold" else Color(0.6, 0.41, 0.22)
			var c := base * (1.0 + 0.05 * brushed)
			c *= 1.0 - 0.16 * smoothstep(0.1, 0.6, blotch)  # grime in the recesses
			if region == "bronze" and blotch < -0.35:  # a little patina
				c = c.lerp(Color(0.33, 0.45, 0.36), 0.25)
			c = c.lerp(Color(1.0, 0.88, 0.62), scratch * 0.12)
			return [Color(c.r, c.g, c.b), clampf(0.34 + 0.08 * blotch + scratch * 0.05, 0.2, 0.7), 1.0]
		"wood", "darkwood":
			var warp := _noise.get_noise_2d(u * 1.2 + 50.0, v * 2.5) * 1.6
			var grain := 0.5 + 0.5 * sin((u * 9.0 + warp) * TAU)
			var light := Color(0.46, 0.31, 0.18) if region == "wood" else Color(0.3, 0.22, 0.15)
			var dark := Color(0.29, 0.18, 0.1) if region == "wood" else Color(0.18, 0.13, 0.09)
			var c := dark.lerp(light, pow(grain, 1.6)) * (1.0 + 0.04 * along)
			if region == "darkwood":
				c *= 1.0 - 0.12 * smoothstep(0.1, 0.6, blotch)  # weathered, handled
			return [Color(c.r, c.g, c.b), clampf(0.68 + 0.1 * grain * 0.5 + (0.1 if region == "darkwood" else 0.0), 0.4, 0.95), 0.0]
		"leather", "redleather":
			# A strap wound round the grip: diagonal bands with dark grooves.
			var band := fposmod(u + v * 10.0, 1.0)
			var base := Color(0.34, 0.21, 0.12) if region == "leather" else Color(0.46, 0.11, 0.09)
			var c := base * (1.0 + 0.06 * blotch + 0.03 * brushed)
			if band < 0.12:
				c *= 0.45
			else:
				c *= 0.9 + 0.2 * sin(band * PI)  # each turn rounded
			return [Color(c.r, c.g, c.b), clampf(0.72 + 0.08 * blotch, 0.5, 0.95), 0.0]
	return [Color.MAGENTA, 1.0, 0.0]


## The one material: the atlas's colour, roughness (G) and metal (B).
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Weapons_Atlas"
	m.albedo_texture = load(OUT + "weapons_colour.png")
	m.roughness_texture = load(OUT + "weapons_orm.png")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic_texture = load(OUT + "weapons_orm.png")
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	m.roughness = 1.0
	m.metallic_specular = 0.5
	ResourceSaver.save(m, OUT + "weapons.tres")
	return load(OUT + "weapons.tres")


## A UV in a region: u across (0..1), v along (0..1).
func _uv(region: String, u: float, v: float) -> Vector2:
	if _atlas == "shields":
		var rect: Rect2i = SHIELD_REGIONS[region]
		return Vector2((rect.position.x + 1.0 + clampf(u, 0.0, 1.0) * (rect.size.x - 2.0)) / SHIELD_SIZE,
			(rect.position.y + 1.0 + clampf(v, 0.0, 1.0) * (rect.size.y - 2.0)) / SHIELD_SIZE)
	var r: Array = REGIONS[region]
	var x := (int(r[0]) * COL + 1.0 + clampf(u, 0.0, 1.0) * (COL - 2.0)) / SIZE
	var y := lerpf(float(r[1]), float(r[2]), clampf(v, 0.002, 0.998))
	return Vector2(x, y)


# ---------- Building blocks ----------

func _begin() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_group = 1


func _end() -> ArrayMesh:
	_st.index()
	_st.generate_normals()
	return _st.commit()


## One triangle, turned to face `outward` (Godot's front faces are clockwise:
## its generated normal is (c - a) x (b - a)). smooth: the smoothing group.
func _tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, outward: Vector3, smooth: int) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	_st.set_smooth_group(smooth)
	for p in [[a, ua], [b, ub], [c, uc]]:
		_st.set_uv(p[1])
		_st.add_vertex(p[0])


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		outward: Vector3, smooth: int) -> void:
	_tri(a, b, c, ua, ub, uc, outward, smooth)
	_tri(a, c, d, ua, uc, ud, outward, smooth)


## A blade swept along +y from `base` for `length`. half_width(t) and
## half_thick(t) shape it (t: 0 at the guard, 1 at the point); profile(t)
## gives its cross-section, edge to edge, as (x in -1..1, z in 0..1) for the
## upper face (the lower face is its mirror). Every face of the section is its
## own smoothing group, so edges, bevels, ridges and fullers stay crisp.
func _blade(base: float, length: float, half_width: Callable, half_thick: Callable, profile: Callable,
		stations: int, region: String) -> void:
	var ts := []
	for k in stations + 1:
		ts.append(pow(float(k) / stations, 0.85))  # closer together towards the point
	for side in [1.0, -1.0]:
		var count: int = (profile.call(0.0) as Array).size()
		for j in count - 1:
			var group := _group
			_group += 1
			for k in stations:
				var corners := []
				var uvs := []
				for kk in [k, k + 1]:
					var t: float = ts[kk]
					var prof: Array = profile.call(t)
					for jj in [j, j + 1]:
						var p: Vector2 = prof[jj]
						corners.append(Vector3(p.x * half_width.call(t), base + t * length, side * p.y * half_thick.call(t)))
						uvs.append(_uv(region, (p.x + 1.0) * 0.5, t))
				var mid: Vector3 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
				var out := Vector3(mid.x * 0.3, 0.0, side)
				_quad(corners[0], corners[1], corners[3], corners[2], uvs[0], uvs[1], uvs[3], uvs[2], out, group)


## A surface of revolution round the y axis: rings of (y, radius), scaled
## (sx, sz) into an oval; caps where a ring at either end is not a point.
## u runs round, v along; smooth: one smoothing group (or a new one per band).
func _lathe(rings: Array, segs: int, region: String, sx := 1.0, sz := 1.0, smooth := true, turn := 0.0,
		v_scale := 1.0, xf := Transform3D.IDENTITY) -> void:
	var group := _group
	_group += 1
	for i in rings.size() - 1:
		var g := group if smooth else _group + i
		for s in segs:
			var a0 := TAU * s / segs + turn
			var a1 := TAU * (s + 1) / segs + turn
			var p := []
			var uv := []
			for ring in [rings[i], rings[i + 1]]:
				for a in [a0, a1]:
					p.append(Vector3(cos(a) * float(ring[1]) * sx, float(ring[0]), sin(a) * float(ring[1]) * sz))
			for ri in [i, i + 1]:
				for su in [s, s + 1]:
					uv.append(_uv(region, float(su) / segs, float(ri) / (rings.size() - 1) * v_scale))
			var mid: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
			var out := Vector3(mid.x, (float(rings[i][1]) - float(rings[i + 1][1])) * 0.5, mid.z)
			_quad(xf * p[0], xf * p[1], xf * p[3], xf * p[2], uv[0], uv[1], uv[3], uv[2], xf.basis * out, g)
	if not smooth:
		_group += rings.size()
	for end in [0, rings.size() - 1]:
		var ring: Array = rings[end]
		if float(ring[1]) < 0.0005:
			continue
		var cap := _group
		_group += 1
		var centre := Vector3(0, float(ring[0]), 0)
		var up := Vector3(0, -1.0 if end == 0 else 1.0, 0)
		for s in segs:
			var a0 := TAU * s / segs + turn
			var a1 := TAU * (s + 1) / segs + turn
			var p0 := Vector3(cos(a0) * float(ring[1]) * sx, float(ring[0]), sin(a0) * float(ring[1]) * sz)
			var p1 := Vector3(cos(a1) * float(ring[1]) * sx, float(ring[0]), sin(a1) * float(ring[1]) * sz)
			_tri(xf * centre, xf * p0, xf * p1, _uv(region, 0.5, 0.5), _uv(region, 0.5 + 0.4 * cos(a0), 0.5 + 0.1 * sin(a0)),
				_uv(region, 0.5 + 0.4 * cos(a1), 0.5 + 0.1 * sin(a1)), xf.basis * up, cap)


## A box (crisp faces) from `lo` to `hi`, its x and z sizes scaled by taper at
## the top (for guards that narrow or flare).
func _box(lo: Vector3, hi: Vector3, region: String, top_scale := Vector2.ONE) -> void:
	var c := (lo + hi) * 0.5
	var corner := func(ix: int, iy: int, iz: int) -> Vector3:
		var p := Vector3(lo.x if ix == 0 else hi.x, lo.y if iy == 0 else hi.y, lo.z if iz == 0 else hi.z)
		if iy == 1:
			p.x = c.x + (p.x - c.x) * top_scale.x
			p.z = c.z + (p.z - c.z) * top_scale.y
		return p
	var faces := [
		[Vector3.RIGHT, [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]]],
		[Vector3.LEFT, [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]]],
		[Vector3.UP, [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]]],
		[Vector3.DOWN, [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]],
		[Vector3.BACK, [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]],
		[Vector3.FORWARD, [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]]],
	]
	for f in faces:
		var q := []
		for idx in f[1]:
			q.append(corner.call(idx[0], idx[1], idx[2]))
		var uv := [_uv(region, 0.1, 0.1), _uv(region, 0.9, 0.1), _uv(region, 0.9, 0.9), _uv(region, 0.1, 0.9)]
		_quad(q[0], q[1], q[2], q[3], uv[0], uv[1], uv[2], uv[3], f[0], _group)
		_group += 1


## A flat outline in the (z, y) plane, thick in x: half_thick(z) thins it
## towards the edge (an axe head). Both faces and the rim; u runs from the
## back (0.5) to the edge (1.0), so the edge falls in the honed band.
func _plate(outline: PackedVector2Array, half_thick: Callable, region: String, z_edge: float) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var uv_of := func(p: Vector2) -> Vector2:
		return _uv(region, 0.5 + 0.5 * clampf(p.x / z_edge, 0.0, 1.0), (p.y - lo.y) / (hi.y - lo.y))
	for side in [1.0, -1.0]:
		var group := _group
		_group += 1
		for t in range(0, tris.size(), 3):
			var p := []
			var uv := []
			for k in 3:
				var q: Vector2 = outline[tris[t + k]]
				p.append(Vector3(side * float(half_thick.call(q.x)), q.y, q.x))
				uv.append(uv_of.call(q))
			_tri(p[0], p[1], p[2], uv[0], uv[1], uv[2], Vector3(side, 0, 0), group)
	var rim := _group
	_group += 1
	var centre := (lo + hi) * 0.5
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var mid := (a + b) * 0.5
		var out := Vector3(0, mid.y - centre.y, mid.x - centre.x)
		var ta: float = half_thick.call(a.x)
		var tb: float = half_thick.call(b.x)
		_quad(Vector3(ta, a.y, a.x), Vector3(tb, b.y, b.x), Vector3(-tb, b.y, b.x), Vector3(-ta, a.y, a.x),
			uv_of.call(a), uv_of.call(b), uv_of.call(b), uv_of.call(a), out, rim)


# ---------- The weapons ----------

## A diamond section: edge, bevel, central ridge, bevel, edge.
func _diamond(_t: float) -> Array:
	return [Vector2(-1, 0), Vector2(-0.72, 0.42), Vector2(0, 1), Vector2(0.72, 0.42), Vector2(1, 0)]


## A fullered section (a groove down the middle), easing to a diamond towards
## the point where the fuller runs out.
func _fullered(t: float) -> Array:
	var f := clampf((t - 0.62) / 0.2, 0.0, 1.0)  # 0: full fuller, 1: plain
	var flat := 0.82
	var groove := lerpf(0.42, 0.95, f)
	return [Vector2(-1, 0), Vector2(-0.8, 0.5), Vector2(-0.34, flat), Vector2(-0.18, lerpf(groove, flat, f)),
		Vector2(0, lerpf(groove * 0.92, 1.0, f)), Vector2(0.18, lerpf(groove, flat, f)), Vector2(0.34, flat),
		Vector2(0.8, 0.5), Vector2(1, 0)]


## The iron sword: a Roman gladius (Mainz pattern). A waisted, double-edged
## iron blade with a diamond section and a long point; a wooden handguard
## faced with bronze, a ribbed wooden grip, an oval wooden pommel with a
## bronze peen. About 0.74 m.
func _gladius() -> ArrayMesh:
	_begin()
	_blade(0.13, 0.52,
		func(t): return lerpf(0.027, 0.0, smoothstep(0.76, 1.0, t)) * (1.0 - 0.13 * sin(clampf(t / 0.76, 0.0, 1.0) * PI) + 0.04 * smoothstep(0.55, 0.76, t)),
		func(t): return lerpf(0.0048, 0.0018, t),
		_diamond, 16, "iron")
	_lathe([[0.1, 0.03], [0.112, 0.042], [0.124, 0.04], [0.13, 0.028]], 12, "wood", 1.0, 0.68)  # handguard
	_lathe([[0.122, 0.036], [0.13, 0.034], [0.132, 0.02]], 12, "bronze", 1.0, 0.62)  # its bronze facing
	var grip := []
	for k in 13:
		var y := lerpf(-0.045, 0.1, k / 12.0)
		grip.append([y, 0.0145 + 0.0022 * cos(k / 12.0 * TAU * 4.0)])  # four finger ridges
	_lathe(grip, 8, "wood", 1.0, 0.85)
	_lathe([[-0.045, 0.012], [-0.05, 0.026], [-0.065, 0.031], [-0.08, 0.026], [-0.088, 0.012]], 12, "wood", 1.0, 0.75)  # pommel
	_lathe([[-0.087, 0.008], [-0.095, 0.004], [-0.097, 0.0]], 6, "bronze")  # the peen of the tang
	return _end()


## The steel sword: a spatha, the longer sword of the later legions and
## cavalry. A slender fullered steel blade, a short iron guard, a leather-wound
## grip, a dark steel pommel. About 0.95 m.
func _spatha() -> ArrayMesh:
	_begin()
	_blade(0.125, 0.74,
		func(t): return lerpf(0.0235, 0.0195, t) * (1.0 - smoothstep(0.9, 1.0, t)) + 0.0003,
		func(t): return lerpf(0.0042, 0.0022, t),
		_fullered, 20, "steel")
	_box(Vector3(-0.055, 0.1, -0.013), Vector3(0.055, 0.125, 0.013), "darksteel", Vector2(0.92, 0.9))  # guard
	_lathe([[-0.045, 0.014], [0.0, 0.0155], [0.05, 0.0155], [0.1, 0.0145]], 8, "leather", 1.0, 0.85, true, 0.0, 1.0)
	_lathe([[-0.045, 0.016], [-0.05, 0.026], [-0.065, 0.028], [-0.078, 0.02], [-0.082, 0.008]], 10, "darksteel", 1.0, 0.6)  # wheel pommel
	return _end()


## The gilded sword: a fine fullered steel blade with gilded fittings: a
## flaring cross-guard, a red leather grip bound with gold wire, a faceted
## gold pommel. About 0.92 m.
func _gilded_sword() -> ArrayMesh:
	_begin()
	_blade(0.13, 0.7,
		func(t): return lerpf(0.026, 0.019, t) * (1.0 - smoothstep(0.82, 1.0, t)) + 0.0003,
		func(t): return lerpf(0.0044, 0.002, t),
		_fullered, 20, "steel")
	_box(Vector3(-0.012, 0.1, -0.015), Vector3(0.012, 0.132, 0.015), "gold")  # guard: the block
	for side in [-1.0, 1.0]:
		# Each arm flares and lifts towards its tip.
		_box(Vector3(side * 0.012 if side > 0 else -0.085, 0.108, -0.01), Vector3(0.085 if side > 0 else -0.012, 0.124, 0.01),
			"gold", Vector2(1.0, 1.0))
		_box(Vector3(side * 0.07 - 0.012, 0.104, -0.013), Vector3(side * 0.07 + 0.012, 0.13, 0.013), "gold")
	_lathe([[-0.045, 0.014], [0.0, 0.0155], [0.05, 0.0155], [0.1, 0.0145]], 8, "redleather", 1.0, 0.85)
	for y in [-0.04, 0.03, 0.095]:
		_lathe([[y - 0.004, 0.0165], [y + 0.004, 0.0165]], 8, "gold", 1.0, 0.86)  # gold wire bands
	_lathe([[-0.045, 0.015], [-0.052, 0.026], [-0.068, 0.03], [-0.082, 0.022], [-0.09, 0.0]], 6, "gold", 1.0, 0.8, false)  # faceted pommel
	return _end()


## The player's axe: a bearded felling axe on an ash haft. The raiders' axe:
## the same family, smaller and rough, with rust, on a dark, handled haft.
func _axe(raider: bool) -> ArrayMesh:
	_begin()
	var head_y := 0.6 if raider else 0.62
	var bottom := -0.12 if raider else -0.125
	var top := 0.68 if raider else 0.725
	var r := 0.015 if raider else 0.017
	_lathe([[bottom, r * 1.12], [bottom + 0.06, r], [top - 0.1, r * 0.95], [top, r]], 8, "darkwood" if raider else "wood", 1.0, 0.82)
	var s := 0.82 if raider else 1.0  # the raider's head is smaller
	var outline := PackedVector2Array()
	for p in [Vector2(-0.028, 0.036), Vector2(0.035, 0.034), Vector2(0.12, 0.06), Vector2(0.2, 0.085),
			Vector2(0.235, 0.05), Vector2(0.245, -0.01), Vector2(0.235, -0.07), Vector2(0.2, -0.12),
			Vector2(0.165, -0.11), Vector2(0.12, -0.06), Vector2(0.05, -0.034), Vector2(-0.028, -0.036)]:
		outline.append(Vector2(p.x * s, head_y + p.y * s))
	var z_edge := 0.245 * s
	_plate(outline, func(z): return lerpf(0.017, 0.0016, smoothstep(0.02, z_edge, z)) * (0.9 if raider else 1.0),
		"rust" if raider else "iron", z_edge)
	# The eye round the haft, and a wedge driven into its top.
	_lathe([[head_y - 0.04 * s, 0.024], [head_y + 0.04 * s, 0.024]], 8, "rust" if raider else "darksteel", 0.95, 1.05, false)
	_box(Vector3(-0.004, head_y + 0.04 * s, -0.012), Vector3(0.004, head_y + 0.048 * s, 0.012), "darksteel")
	return _end()


# ========== Phase 4E.2: spears and shields (GRAPHICS_PHASE_4E2_SPEARS_SHIELDS.md) ==========

## The spears: each keeps the old spear's frame (the hand at the origin, the
## shaft along +y, from y = bottom to the head's tip) and length.
##   spear_pilum: the legionaries' pilum (a long iron shank with a small
##     pyramidal point, joined to the shaft by an iron collar);
##   spear_officer: the centurion's hasta (a leaf-bladed steel head on a
##     bronze socket, bronze bands and butt);
##   spear_lance: the cavalry's long lance (a narrow steel head, a leather grip);
##   spear_wooden / _flint / _iron / _steel / _gilded: the player's five tiers.
const SPEARS := {
	"spear_pilum": {"bottom": -0.5, "top": 0.84, "r": 0.016, "shaft": "wood"},
	"spear_officer": {"bottom": -0.5, "top": 1.06, "r": 0.016, "shaft": "darkwood"},
	"spear_lance": {"bottom": -0.68, "top": 1.5, "r": 0.017, "shaft": "darkwood"},
	"spear_wooden": {"bottom": -0.5, "top": 1.06, "r": 0.017, "shaft": "wood"},
	"spear_flint": {"bottom": -0.5, "top": 1.08, "r": 0.017, "shaft": "shaft"},
	"spear_iron": {"bottom": -0.5, "top": 1.08, "r": 0.016, "shaft": "wood"},
	"spear_steel": {"bottom": -0.5, "top": 1.06, "r": 0.016, "shaft": "darkwood"},
	"spear_gilded": {"bottom": -0.5, "top": 1.06, "r": 0.016, "shaft": "darkwood"},
}
const SHIELD_SIZE := 512
## The shields' atlas: painted faces, plank backs, metals, flint, a shaft, leather.
const SHIELD_REGIONS := {
	"face_legion": Rect2i(0, 0, 192, 320), "face_centurion": Rect2i(192, 0, 192, 320),
	"face_raider": Rect2i(384, 0, 128, 128), "face_chief": Rect2i(384, 128, 128, 128),
	"sleather": Rect2i(384, 256, 128, 64),
	"planks": Rect2i(0, 320, 128, 192), "siron": Rect2i(128, 320, 32, 192), "sbronze": Rect2i(160, 320, 32, 192),
	"sgold": Rect2i(192, 320, 32, 192), "srust": Rect2i(224, 320, 32, 192), "flint": Rect2i(256, 320, 32, 192),
	"shaft": Rect2i(288, 320, 32, 192), "rawhide": Rect2i(320, 320, 32, 192), "binding": Rect2i(352, 320, 32, 192),
}
## The painted faces: field colour, design colour, design is gilt (metallic).
const FACES := {
	"face_legion": [Color(0.55, 0.1, 0.08), Color(0.86, 0.66, 0.2), false],
	"face_centurion": [Color(0.42, 0.06, 0.06), Color(0.9, 0.7, 0.3), true],
	"face_raider": [Color(0.4, 0.27, 0.16), Color(0.2, 0.14, 0.09), false],
	"face_chief": [Color(0.48, 0.12, 0.11), Color(0.07, 0.06, 0.06), false],
}


# ---------- The shields' atlas ----------

func _paint_shields() -> void:
	var colour := Image.create(SHIELD_SIZE, SHIELD_SIZE, false, Image.FORMAT_RGBA8)
	var orm := Image.create(SHIELD_SIZE, SHIELD_SIZE, false, Image.FORMAT_RGBA8)
	colour.fill(Color(0.3, 0.22, 0.15))
	orm.fill(Color(1.0, 0.8, 0.0))
	var scratches := {}
	for k in 500:
		var x := _rng.randf() * SHIELD_SIZE
		var y := _rng.randf() * SHIELD_SIZE
		var a := _rng.randf() * TAU
		for t in int(_rng.randf_range(3.0, 10.0)):
			scratches[Vector2i(int(x + cos(a) * t), int(y + sin(a) * t))] = _rng.randf_range(0.3, 0.8)
	for region in SHIELD_REGIONS:
		var rect: Rect2i = SHIELD_REGIONS[region]
		for y: float in range(rect.position.y, rect.end.y):
			for x: float in range(rect.position.x, rect.end.x):
				var u := (x - rect.position.x + 0.5) / rect.size.x
				var v := (y - rect.position.y + 0.5) / rect.size.y
				var px: Array = _shield_texel(region, u, v, float(scratches.get(Vector2i(x, y), 0.0)))
				colour.set_pixel(x, y, px[0])
				orm.set_pixel(x, y, Color(1.0, px[1], px[2]))
	colour.save_png(ProjectSettings.globalize_path(OUT + "shields_colour.png"))
	orm.save_png(ProjectSettings.globalize_path(OUT + "shields_orm.png"))


## [colour, roughness, metal] of one texel of the shields' atlas.
func _shield_texel(region: String, u: float, v: float, scratch: float) -> Array:
	var broad := _noise.get_noise_2d(u * 3.0 + 700.0, v * 3.0)
	var fine := _noise.get_noise_2d(u * 40.0, v * 40.0)
	if FACES.has(region):
		return _face_texel(region, u, v, scratch, broad, fine)
	match region:
		"planks":
			# The back: glued planks, grain along them, dark seams.
			var plank := fposmod(u * 5.0, 1.0)
			var warp := _noise.get_noise_2d(u * 1.5 + 30.0, v * 3.0) * 1.4
			var grain := 0.5 + 0.5 * sin((u * 22.0 + warp) * TAU)
			var c := Color(0.27, 0.18, 0.11).lerp(Color(0.42, 0.3, 0.19), pow(grain, 1.5))
			c *= 1.0 - 0.1 * smoothstep(0.1, 0.6, broad)
			if plank < 0.04 or plank > 0.97:
				c *= 0.55
			return [Color(c.r, c.g, c.b), 0.8, 0.0]
		"siron", "sbronze", "sgold", "srust":
			var base: Color = {"siron": Color(0.42, 0.43, 0.45), "sbronze": Color(0.6, 0.42, 0.22),
				"sgold": Color(0.86, 0.66, 0.3), "srust": Color(0.33, 0.31, 0.3)}[region]
			var c := base * (1.0 + 0.05 * _noise.get_noise_2d(u * 60.0, v * 4.0))
			c *= 1.0 - 0.15 * smoothstep(0.1, 0.6, broad)
			var rough: float = {"siron": 0.45, "sbronze": 0.38, "sgold": 0.32, "srust": 0.62}[region]
			var metal := 1.0
			if region == "srust" and broad < -0.1:
				c = c.lerp(Color(0.42, 0.24, 0.13), 0.7)
				rough = 0.85
				metal = 0.35
			c = c.lerp(Color(0.85, 0.85, 0.85) if region != "sgold" else Color(1.0, 0.9, 0.65), scratch * 0.2)
			return [Color(c.r, c.g, c.b), rough, metal]
		"flint":
			# Knapped flint: grey-brown, shell-like facets, a paler cortex at the edges.
			var cell := _noise.get_noise_2d(u * 9.0 + 400.0, v * 5.0)
			var c := Color(0.36, 0.33, 0.3).lerp(Color(0.5, 0.47, 0.42), 0.5 + 0.5 * cell)
			if minf(u, 1.0 - u) < 0.1:
				c = c.lerp(Color(0.66, 0.62, 0.55), 0.6)
			return [Color(c.r, c.g, c.b), 0.38 + 0.15 * absf(cell), 0.0]
		"shaft":
			var warp := _noise.get_noise_2d(u * 1.2 + 80.0, v * 2.5) * 1.6
			var grain := 0.5 + 0.5 * sin((u * 9.0 + warp) * TAU)
			var c := Color(0.32, 0.21, 0.12).lerp(Color(0.5, 0.36, 0.22), pow(grain, 1.6))
			return [Color(c.r, c.g, c.b), 0.7, 0.0]
		"rawhide", "binding", "sleather":
			var base: Color = {"rawhide": Color(0.55, 0.44, 0.3), "binding": Color(0.35, 0.24, 0.15),
				"sleather": Color(0.3, 0.19, 0.11)}[region]
			var band := fposmod(u + v * (10.0 if region == "binding" else 3.0), 1.0)
			var c := base * (1.0 + 0.08 * broad + 0.04 * fine)
			if region == "binding" and band < 0.14:
				c *= 0.5
			return [Color(c.r, c.g, c.b), 0.75, 0.0]
	return [Color.MAGENTA, 1.0, 0.0]


## A painted face. u, v: 0..1 across and down the face (round faces: the disc
## inscribed in the square). Paint over wood, chipped at the edges, scratched,
## dirtier towards the bottom; the design per face.
func _face_texel(region: String, u: float, v: float, scratch: float, broad: float, fine: float) -> Array:
	var face: Array = FACES[region]
	var field: Color = face[0]
	var ink: Color = face[1]
	var gilt: bool = face[2]
	var c := field * (1.0 + 0.06 * broad + 0.03 * fine)
	var rough := 0.62
	var metal := 0.0
	var design := 0.0  # 0..1: how much of the design colour
	var p := Vector2(u, v)
	match region:
		"face_legion", "face_centurion":
			var aspect := 0.62  # the scutum's width / height
			var q := Vector2((u - 0.5) * aspect, v - 0.5)  # in the face's own proportions
			# A border band inset from the edge (two for the centurion).
			var edge := minf(minf(u, 1.0 - u) * aspect, minf(v, 1.0 - v))
			design = maxf(design, _band(edge, 0.035, 0.012))
			if region == "face_centurion":
				design = maxf(design, _band(edge, 0.06, 0.006))
			# Wings above and below the boss: feathers fanning out sideways.
			for side: float in [-1.0, 1.0]:
				var root := Vector2(0.0, side * 0.13)
				for f: int in 5:
					var ang := deg_to_rad(8.0 + f * 9.0) * side
					for lr: float in [-1.0, 1.0]:
						var d := Vector2(lr * cos(ang), -sin(ang) * side * -1.0)
						var rel := q - root
						var along := rel.dot(d)
						var across := absf(rel.dot(Vector2(-d.y, d.x)))
						var length := 0.15 - f * 0.012
						if along > 0.02 and along < length:
							design = maxf(design, 1.0 - smoothstep(0.006, 0.011, across + along * 0.03))
			# Thunderbolts from the boss to the corners (the legion's mark).
			if region == "face_legion":
				for dx: float in [-1.0, 1.0]:
					for dy: float in [-1.0, 1.0]:
						var dir := Vector2(dx * 0.18, dy * 0.34).normalized()
						var rel := q
						var along := rel.dot(dir)
						if along > 0.1 and along < 0.36:
							var zig := absf(fposmod(along * 14.0, 2.0) - 1.0) * 2.0 - 1.0
							var off := rel.dot(Vector2(-dir.y, dir.x)) - zig * 0.018
							design = maxf(design, 1.0 - smoothstep(0.006, 0.01, absf(off)))
			# The centurion's laurel wreath round the boss.
			if region == "face_centurion":
				var r := q.length()
				var ang := atan2(q.y, q.x)
				var leaf := fposmod(ang / TAU * 22.0, 1.0)
				if absf(r - 0.115) < 0.02:
					design = maxf(design, 1.0 - smoothstep(0.25, 0.45, absf(leaf - 0.5)) * 1.0 * smoothstep(0.008, 0.02, absf(r - 0.115)) - 0.0)
		"face_raider":
			# Planks, painted in quarters: dark and bare.
			var q := p - Vector2(0.5, 0.5)
			var quarter := (1 if q.x > 0.0 else 0) + (1 if q.y > 0.0 else 0)
			if quarter % 2 == 0:
				design = 0.9
			var plank := fposmod(u * 6.0, 1.0)
			if plank < 0.04:
				c *= 0.6
		"face_chief":
			# A black ring and cross on red.
			var q := p - Vector2(0.5, 0.5)
			var r := q.length()
			design = maxf(design, _band(absf(r - 0.3), 0.0, 0.035))
			design = maxf(design, (1.0 - smoothstep(0.03, 0.045, minf(absf(q.x), absf(q.y)))) * (1.0 if r < 0.3 else 0.0))
	c = c.lerp(ink * (1.0 + 0.05 * broad), clampf(design, 0.0, 1.0))
	if gilt and design > 0.5:
		metal = 0.75
		rough = 0.35
	# Wear: paint chipped to the wood near the rim, scratches, grime low down.
	var rim := minf(minf(u, 1.0 - u), minf(v, 1.0 - v)) if region in ["face_legion", "face_centurion"] \
		else maxf(0.0, 0.5 - (p - Vector2(0.5, 0.5)).length())
	var chip := smoothstep(0.0, 0.05, rim) + 0.6 * (fine + 0.2)
	if chip < 0.35:
		c = c.lerp(Color(0.34, 0.24, 0.15), 0.75)
		metal = 0.0
		rough = 0.8
	c = c.lerp(Color(0.62, 0.55, 0.45), scratch * 0.3)
	c *= 1.0 - 0.18 * smoothstep(0.65, 1.0, v) * (0.5 + 0.5 * broad)
	return [Color(c.r, c.g, c.b), rough, metal]


## 1 inside a band of `width` round `at`, softly.
func _band(d: float, at: float, width: float) -> float:
	return 1.0 - smoothstep(width * 0.7, width, absf(d - at))


func _shield_material() -> StandardMaterial3D:
	if ResourceLoader.exists(OUT + "shields.tres") and OS.get_environment("REMAKE_SHIELD_MATERIAL") != "1":
		return load(OUT + "shields.tres")
	var m := StandardMaterial3D.new()
	m.resource_name = "Shields_Atlas"
	m.albedo_texture = load(OUT + "shields_colour.png")
	m.roughness_texture = load(OUT + "shields_orm.png")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic_texture = load(OUT + "shields_orm.png")
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	m.roughness = 1.0
	m.metallic_specular = 0.5
	ResourceSaver.save(m, OUT + "shields.tres")
	return load(OUT + "shields.tres")


# ---------- Spears ----------

## A leaf blade: widest a third of the way up, tapering to the point.
func _leaf(width: float, widest := 0.3) -> Callable:
	return func(t: float) -> float:
		if t < widest:
			return lerpf(width * 0.45, width, sin(t / widest * PI * 0.5))
		return width * cos((t - widest) / (1.0 - widest) * PI * 0.5) + 0.0004


func _spear(kind: String) -> ArrayMesh:
	_begin()
	var cfg: Dictionary = SPEARS[kind]
	var bottom: float = cfg["bottom"]
	var top: float = cfg["top"]
	var r: float = cfg["r"]
	_atlas = "shields" if kind == "spear_flint" else "weapons"
	var wood: String = cfg["shaft"]
	match kind:
		"spear_pilum":
			# Shaft, thicker towards the collar; an iron butt-spike.
			_lathe([[bottom, r * 0.9], [bottom + 0.1, r], [top - 0.05, r * 1.15], [top, r * 1.2]], 8, wood, 1.0, 1.0)
			_lathe([[bottom - 0.05, 0.002], [bottom - 0.02, r * 0.85], [bottom + 0.04, r * 1.0]], 8, "darksteel")
			_box(Vector3(-0.022, top - 0.005, -0.022), Vector3(0.022, top + 0.055, 0.022), "darksteel", Vector2(0.75, 0.75))  # collar
			_lathe([[top + 0.05, 0.0075], [top + 0.25, 0.0062], [top + 0.4, 0.0058]], 6, "iron")  # the long iron shank
			_blade(top + 0.4, 0.075, func(t): return lerpf(0.011, 0.0, t) + 0.0003, func(t): return lerpf(0.011, 0.0, t) + 0.0003,
				_diamond, 6, "iron")  # small pyramidal point
		"spear_officer", "spear_iron", "spear_steel", "spear_gilded", "spear_lance":
			var metal: String = {"spear_officer": "steel", "spear_iron": "iron", "spear_steel": "steel",
				"spear_gilded": "steel", "spear_lance": "steel"}[kind]
			var socket: String = {"spear_officer": "bronze", "spear_iron": "iron", "spear_steel": "darksteel",
				"spear_gilded": "gold", "spear_lance": "darksteel"}[kind]
			_lathe([[bottom, r * 0.95], [bottom + 0.1, r], [top, r * 0.92]], 8, wood, 1.0, 1.0)
			_lathe([[bottom - 0.035, 0.004], [bottom - 0.01, r * 1.05], [bottom + 0.05, r * 1.1]], 8, socket)  # butt cap
			_lathe([[top - 0.09, r * 1.12], [top, r * 1.1], [top + 0.035, r * 0.7]], 8, socket)  # socket
			var length: float = {"spear_officer": 0.21, "spear_iron": 0.2, "spear_steel": 0.24, "spear_gilded": 0.23,
				"spear_lance": 0.2}[kind]
			var width: float = {"spear_officer": 0.03, "spear_iron": 0.028, "spear_steel": 0.022, "spear_gilded": 0.027,
				"spear_lance": 0.017}[kind]
			_blade(top + 0.03, length, _leaf(width, 0.28 if kind != "spear_lance" else 0.2),
				func(t): return lerpf(0.005, 0.0015, t), _diamond, 12, metal)
			if kind in ["spear_officer", "spear_gilded"]:
				var band: String = "bronze" if kind == "spear_officer" else "gold"
				for y: float in [top - 0.2, top - 0.15, bottom + 0.15]:
					_lathe([[y, r * 1.12], [y + 0.012, r * 1.12]], 8, band, 1.0, 1.0, false)
			if kind == "spear_lance":
				_lathe([[-0.12, r * 1.16], [0.14, r * 1.16]], 8, "leather")  # the grip, where the hand holds it
		"spear_wooden":
			# One length of wood, its point shaped and hardened in the fire (charred).
			_lathe([[bottom, r * 0.95], [bottom + 0.1, r], [top - 0.04, r * 0.95]], 8, "wood")
			_lathe([[top - 0.04, r * 0.95], [top + 0.06, r * 0.75], [top + 0.18, r * 0.3], [top + 0.24, 0.0005]], 8, "darkwood")
		"spear_flint":
			_lathe([[bottom, r * 0.95], [bottom + 0.1, r], [top, r * 0.9]], 8, "shaft")
			# A knapped flint head, thick, bound on with sinew.
			_blade(top - 0.02, 0.17, _leaf(0.027, 0.32), func(t): return lerpf(0.0085, 0.003, t), _diamond, 8, "flint")
			_lathe([[top - 0.07, r * 1.12], [top + 0.02, r * 1.25], [top + 0.035, r * 0.9]], 8, "binding")
	_atlas = "weapons"
	return _end()


# ---------- Shields ----------

## The scutum: a tall curved rectangle (part of a cylinder round a vertical
## axis behind it), front painted, back of glued planks, an iron (or gilded)
## edging, a domed boss on a square plate, a grip behind. The same size as the
## old one (0.52 x 0.86 m), centred on the old one's origin, the front to +z.
func _scutum(officer: bool) -> ArrayMesh:
	_begin()
	_atlas = "shields"
	var w := 0.52
	var h := 0.86
	var t := 0.022
	var radius := 0.5
	var face := "face_centurion" if officer else "face_legion"
	var edging := "sgold" if officer else "siron"
	var nx := 12
	var ny := 6
	var curve := func(x: float) -> float: return -radius + sqrt(radius * radius - x * x)  # 0 at the middle
	for side: float in [1.0, -1.0]:
		var group := _group
		_group += 1
		for j in ny:
			for i in nx:
				var corners := []
				var uvs := []
				for jj: int in [j, j + 1]:
					for ii: int in [i, i + 1]:
						var x := lerpf(-w * 0.5, w * 0.5, float(ii) / nx)
						var y := lerpf(h * 0.5, -h * 0.5, float(jj) / ny)
						corners.append(Vector3(x, y, float(curve.call(x)) + side * t * 0.5))
						uvs.append(_uv(face if side > 0.0 else "planks", float(ii) / nx, float(jj) / ny))
				var mid: Vector3 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
				var out := Vector3(mid.x, 0.0, mid.z + radius) * side
				_quad(corners[0], corners[1], corners[3], corners[2], uvs[0], uvs[1], uvs[3], uvs[2], out, group)
	# The edging: a metal strip round the rim, a little proud of both faces.
	var rim := []
	for i in nx + 1:
		rim.append(Vector2(lerpf(-w * 0.5, w * 0.5, float(i) / nx), h * 0.5))
	for j in range(1, ny + 1):
		rim.append(Vector2(w * 0.5, lerpf(h * 0.5, -h * 0.5, float(j) / ny)))
	for i in range(nx - 1, -1, -1):
		rim.append(Vector2(lerpf(-w * 0.5, w * 0.5, float(i) / nx), -h * 0.5))
	for j in range(ny - 1, 0, -1):
		rim.append(Vector2(-w * 0.5, lerpf(h * 0.5, -h * 0.5, float(j) / ny)))
	var edge_group := _group
	_group += 1
	for k in rim.size():
		var a: Vector2 = rim[k]
		var b: Vector2 = rim[(k + 1) % rim.size()]
		var za := float(curve.call(a.x))
		var zb := float(curve.call(b.x))
		var out := Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0).normalized()
		var lip := t * 0.5 + 0.004
		_quad(Vector3(a.x, a.y, za + lip), Vector3(b.x, b.y, zb + lip), Vector3(b.x, b.y, zb - lip), Vector3(a.x, a.y, za - lip),
			_uv(edging, 0.2, float(k) / rim.size()), _uv(edging, 0.2, float(k + 1) / rim.size()),
			_uv(edging, 0.8, float(k + 1) / rim.size()), _uv(edging, 0.8, float(k) / rim.size()), out, edge_group)
	# The boss: a square plate and a dome (lathed along +z), at the front's middle.
	var plate := 0.085
	_box(Vector3(-plate, -plate, t * 0.5 - 0.001), Vector3(plate, plate, t * 0.5 + 0.005), edging if officer else "sbronze")
	var to_front := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, t * 0.5 + 0.004))
	_lathe([[0.0, 0.07], [0.012, 0.066], [0.03, 0.05], [0.045, 0.026], [0.05, 0.0]], 14,
		"sgold" if officer else "siron", 1.0, 1.0, true, 0.0, 1.0, to_front)
	# The grip behind the boss.
	_box(Vector3(-0.08, -0.016, -t * 0.5 - 0.03), Vector3(0.08, 0.016, -t * 0.5 - 0.012), "sleather")
	for x: float in [-0.075, 0.075]:
		_box(Vector3(x - 0.008, -0.016, -t * 0.5 - 0.012), Vector3(x + 0.008, 0.016, -t * 0.5), "siron")
	_atlas = "weapons"
	return _end()


## The raiders' round shield: planks, slightly domed, painted; a rawhide (or,
## for a chief, iron) rim; an iron boss; a grip behind. Radius 0.3 m, as before.
func _round_shield(chief: bool) -> ArrayMesh:
	_begin()
	_atlas = "shields"
	var radius := 0.3
	var t := 0.02
	var dome := 0.025
	var face := "face_chief" if chief else "face_raider"
	var segs := 20
	var rings := 4
	var z_at := func(r: float) -> float: return dome * (1.0 - (r / radius) * (r / radius))
	for side: float in [1.0, -1.0]:
		var group := _group
		_group += 1
		for k in rings:
			for s in segs:
				var pts := []
				var uvs := []
				for kk: int in [k, k + 1]:
					for ss: int in [s, s + 1]:
						var r := radius * float(kk) / rings
						var a := TAU * ss / segs
						var p := Vector3(cos(a) * r, sin(a) * r, float(z_at.call(r)) + side * t * 0.5)
						pts.append(p)
						var region := face if side > 0.0 else "planks"
						uvs.append(_uv(region, 0.5 + p.x / (2.0 * radius) * (1.0 if side > 0.0 else 0.9), 0.5 - p.y / (2.0 * radius)))
				var out := Vector3(0, 0, side)
				if k == 0:
					_tri(pts[0], pts[3], pts[2], uvs[0], uvs[3], uvs[2], out, group)
				else:
					_quad(pts[0], pts[1], pts[3], pts[2], uvs[0], uvs[1], uvs[3], uvs[2], out, group)
	# The rim: rawhide sewn over the edge (iron on a chief's).
	var rim_region := "siron" if chief else "rawhide"
	var rim_group := _group
	_group += 1
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var lip := t * 0.5 + 0.004
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		_quad(p0 + Vector3(0, 0, lip), p1 + Vector3(0, 0, lip), p1 - Vector3(0, 0, lip), p0 - Vector3(0, 0, lip),
			_uv(rim_region, 0.2, float(s) / segs), _uv(rim_region, 0.2, float(s + 1) / segs),
			_uv(rim_region, 0.8, float(s + 1) / segs), _uv(rim_region, 0.8, float(s) / segs), (p0 + p1) * 0.5, rim_group)
	var to_front := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, dome + t * 0.5 - 0.004))
	_lathe([[0.0, 0.08], [0.01, 0.075], [0.035, 0.055], [0.06, 0.02], [0.065, 0.0]], 12,
		"siron" if chief else "srust", 1.0, 1.0, true, 0.0, 1.0, to_front)
	_box(Vector3(-0.07, -0.015, -t * 0.5 - 0.028), Vector3(0.07, 0.015, -t * 0.5 - 0.01), "sleather")
	_atlas = "weapons"
	return _end()
