## Builds the phase 5A terrain textures (GRAPHICS_PHASE_5A_TERRAIN.md) from five
## Poly Haven ground textures (CC0, models/CREDITS.md): grass, forest floor,
## dirt, sand and rock. Writes, in textures/terrain/:
##   ground_albedo.png  the five colour maps, 512² each, stacked: a 5-layer
##                      texture array. Each is normalised to an average of 0.5
##                      grey, so it carries only surface detail (grain, blades,
##                      pebbles, moss, cracks) and its own small hue shifts; the
##                      terrain shader multiplies it into the game's own palette
##                      colours, which keep the art direction and the seasons.
##   ground_normal.png  their normal maps (OpenGL), 256² each, the same way.
##
##   SRC=<folder of <name>_diff.jpg and <name>_nor.jpg> \
##   godot --headless --path last-light/game --script res://tools/build_terrain_textures.gd
## Then `godot --import`.
extends SceneTree

const OUT := "res://textures/terrain/"
## Layer order (the shader relies on it): grass, forest floor, dirt, sand, rock.
const LAYERS := ["rocky_terrain_02", "forest_leaves_02", "dirt", "coast_sand_01", "aerial_rocks_02"]
## Per layer: how much of the photo's contrast is kept (grass, forest, dirt, sand, rock).
const CONTRAST := [1.0, 0.95, 0.9, 0.85, 0.6]
## How much of each photo's own colour variation (beyond brightness) is kept.
const HUE_KEPT := 0.5
const ALBEDO_SIZE := 512
const NORMAL_SIZE := 256


func _initialize() -> void:
	var src := OS.get_environment("SRC")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var albedo := Image.create(ALBEDO_SIZE, ALBEDO_SIZE * LAYERS.size(), false, Image.FORMAT_RGB8)
	var normal := Image.create(NORMAL_SIZE, NORMAL_SIZE * LAYERS.size(), false, Image.FORMAT_RGB8)
	for i in LAYERS.size():
		var img := Image.load_from_file(src.path_join(LAYERS[i] + "_diff.jpg"))
		img.convert(Image.FORMAT_RGB8)
		img.resize(ALBEDO_SIZE, ALBEDO_SIZE, Image.INTERPOLATE_LANCZOS)
		var mean := Color(0, 0, 0)
		for y in ALBEDO_SIZE:
			for x in ALBEDO_SIZE:
				var c := img.get_pixel(x, y)
				mean += Color(c.r, c.g, c.b, 0)
		var n := float(ALBEDO_SIZE * ALBEDO_SIZE)
		mean = Color(mean.r / n, mean.g / n, mean.b / n)
		# Normalised by brightness (not per channel, which would blow up a
		# texture's weakest channel), keeping only part of its own hue, with
		# the contrast set per layer (the rock photo is the harshest).
		var mean_lum := (mean.r + mean.g + mean.b) / 3.0
		var contrast: float = CONTRAST[i]
		for y in ALBEDO_SIZE:
			for x in ALBEDO_SIZE:
				var c := img.get_pixel(x, y)
				var lum := (c.r + c.g + c.b) / 3.0
				var out := Color()
				for k in 3:
					var ch: float = [c.r, c.g, c.b][k]
					var tint: float = [mean.r, mean.g, mean.b][k] / mean_lum  # the texture's average hue, removed
					var v := lerpf(lum, ch / tint, HUE_KEPT) / mean_lum * 0.5
					out[k] = clampf(0.5 + (v - 0.5) * contrast, 0.0, 1.0)
				img.set_pixel(x, y, out)
		albedo.blit_rect(img, Rect2i(0, 0, ALBEDO_SIZE, ALBEDO_SIZE), Vector2i(0, i * ALBEDO_SIZE))
		var nor := Image.load_from_file(src.path_join(LAYERS[i] + "_nor.jpg"))
		nor.convert(Image.FORMAT_RGB8)
		nor.resize(NORMAL_SIZE, NORMAL_SIZE, Image.INTERPOLATE_LANCZOS)
		normal.blit_rect(nor, Rect2i(0, 0, NORMAL_SIZE, NORMAL_SIZE), Vector2i(0, i * NORMAL_SIZE))
		print("%s: mean colour %s" % [LAYERS[i], mean])
	for item in [["ground_albedo", albedo], ["ground_normal", normal]]:
		var path: String = OUT + str(item[0]) + ".png"
		(item[1] as Image).save_png(ProjectSettings.globalize_path(path))
		var imp := FileAccess.open(ProjectSettings.globalize_path(path + ".import"), FileAccess.WRITE)
		imp.store_string("[remap]\n\nimporter=\"2d_array_texture\"\ntype=\"CompressedTexture2DArray\"\n\n[params]\n\n" +
			"compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n" +
			"compress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n" % LAYERS.size())
		imp.close()
	print("written: run --import")
	quit()
