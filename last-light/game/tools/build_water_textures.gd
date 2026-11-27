## Builds the phase 5B.1 water ripple normal map (GRAPHICS_PHASE_5B1_WATER_SURFACE.md):
## textures/water/ripples_normal.png, 256², tileable, made here from seamless
## noise (original work, no third-party asset). Small wind ripples, a little
## stretched along one direction, which the water shader scrolls twice in
## different directions and scales.
##   godot --headless --path last-light/game --script res://tools/build_water_textures.gd
## Then `godot --import`.
extends SceneTree

const OUT := "res://textures/water/ripples_normal.png"
const SIZE := 256


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	# Two layers of seamless noise: broad wavelets and fine ripples.
	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var layers := []
	for spec in [[3, 0.012, 1.0, 11], [4, 0.035, 0.45, 23]]:
		var n := FastNoiseLite.new()
		n.seed = spec[3]
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_octaves = spec[0]
		n.frequency = spec[1]
		layers.append([n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true), spec[2]])
	for y in SIZE:
		for x in SIZE:
			var h := 0.0
			for l in layers:
				# Stretched along x: ripples run across the wind, not as round blobs.
				var img: Image = l[0]
				h += img.get_pixel(x, (y * 2) % SIZE).r * float(l[1])
			h /= 1.45
			height.set_pixel(x, y, Color(h, h, h))
	height.bump_map_to_normal_map(6.0)
	height.convert(Image.FORMAT_RGB8)
	height.save_png(ProjectSettings.globalize_path(OUT))
	var imp := FileAccess.open(ProjectSettings.globalize_path(OUT + ".import"), FileAccess.WRITE)
	imp.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n" +
		"compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n" +
		"compress/normal_map=1\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n" +
		"roughness/mode=0\nroughness/src_normal=\"\"\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\n" +
		"process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n" +
		"process/size_limit=0\ndetect_3d/compress_to=0\n")
	imp.close()
	print("written ", OUT, ": run --import")
	quit()
