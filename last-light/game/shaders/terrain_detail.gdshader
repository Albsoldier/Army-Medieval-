// Terrain, phase 5A (GRAPHICS_PHASE_5A_TERRAIN.md): the original terrain shader's
// colours (terrain.gdshader: the palette, its broad variation, dry patches,
// bare earth, slopes turning to rock, the seasons, snow and the wet shore), with
// real ground textures laid into them.
//
// `ground` is a texture array of five CC0 ground textures (grass, forest floor,
// dirt, sand, rock; tools/build_terrain_textures.gd), each normalised to 0.5
// grey: they add surface detail and small hue shifts to the palette colour
// rather than replacing it. Against tiling: each is sampled at two scales, one
// rotated, mixed by noise. Transitions between ground types are broken up by
// fine noise and by the textures themselves (stones show through sand first,
// grass gives way to earth in its own bare patches), so the 1 m tile grid
// under the blend weights no longer shows. Normal maps (`ground_normal`) bend
// the light for close-up relief, in world space (the terrain mesh has no
// tangents). Detail fades a little with distance, against shimmer.
//
// Vertex colour carries the blend weights, as before: r = sand, g = forest
// floor, b = rock (grass is what's left).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 grass_a : source_color = vec3(0.30, 0.37, 0.19);
uniform vec3 grass_b : source_color = vec3(0.40, 0.44, 0.23);
uniform vec3 dry_grass : source_color = vec3(0.53, 0.49, 0.31);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.24);
uniform vec3 forest_a : source_color = vec3(0.22, 0.27, 0.14);
uniform vec3 forest_b : source_color = vec3(0.33, 0.29, 0.18);
uniform vec3 sand_a : source_color = vec3(0.66, 0.59, 0.45);
uniform vec3 sand_b : source_color = vec3(0.56, 0.50, 0.38);
uniform vec3 rock_a : source_color = vec3(0.45, 0.43, 0.40);
uniform vec3 rock_b : source_color = vec3(0.58, 0.56, 0.51);
uniform float snow = 0.0;    // winter
uniform float autumn = 0.0;
uniform float summer = 0.0;

uniform sampler2DArray ground : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap, repeat_enable;
uniform float tile = 3.5;           // metres per texture repeat (the near scale)
uniform float detail = 0.9;         // how much of the textures' detail shows
uniform float relief = 0.7;         // normal map strength

varying vec3 world_pos;
varying vec3 world_normal;

const int GRASS = 0;
const int FOREST = 1;
const int DIRT = 2;
const int SAND = 3;
const int ROCK = 4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// A layer's colour detail (about 0.5 on average), sampled twice against tiling:
// at the near scale, and at a larger, rotated scale, mixed by noise.
vec3 layer(int i, vec2 p, float mixer) {
	vec2 uv1 = p / tile;
	vec2 q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	vec2 uv2 = q / (tile * 2.7) + vec2(0.37, 0.71);
	vec3 a = texture(ground, vec3(uv1, float(i))).rgb;
	vec3 b = texture(ground, vec3(uv2, float(i))).rgb;
	return mix(a, b, mixer);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float broad = fbm(p * 0.035);
	float mid = fbm(p * 0.25);
	float fine = vnoise(p * 2.7);
	float edge = vnoise(p * 1.3) - 0.5;   // breaks up the tile-grid edges of the blend
	float mixer = smoothstep(0.35, 0.65, fbm(p * 0.09 + 31.0));

	// The original palette colours, unchanged.
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, broad));
	grass = mix(grass, dry_grass, smoothstep(0.62, 0.85, fbm(p * 0.06 + 13.0)) * 0.7);
	grass *= 0.88 + 0.2 * mid;
	float bare = smoothstep(0.66, 0.82, fbm(p * 0.18 + 7.0)) * 0.55;
	grass = mix(grass, dry_grass * 1.05, summer * 0.3);
	grass = mix(grass, vec3(0.50, 0.38, 0.20) * (0.9 + 0.2 * mid), autumn * 0.45);
	vec3 forest = mix(forest_a, forest_b, mid);
	forest = mix(forest, vec3(0.38, 0.25, 0.13) * (0.9 + 0.2 * mid), autumn * 0.4);
	vec3 sand = mix(sand_a, sand_b, mid * 0.7);
	vec3 rock = mix(rock_a, rock_b, mid);

	// Texture detail for each ground type.
	vec3 t_grass = layer(GRASS, p, mixer);
	vec3 t_forest = layer(FOREST, p, mixer);
	vec3 t_dirt = layer(DIRT, p, 1.0 - mixer);
	vec3 t_sand = layer(SAND, p, mixer);
	vec3 t_rock = layer(ROCK, p * 0.8, mixer);
	float h_grass = dot(t_grass, vec3(0.33));
	float h_rock = dot(t_rock, vec3(0.33));

	// Bare earth: the original dirt patches, edged by the grass texture's own soil.
	float dirt_w = clamp(bare + (0.5 - h_grass) * 0.35 * step(0.02, bare), 0.0, 0.8);
	vec3 col_grass = mix(grass * t_grass * 2.0, dirt * t_dirt * 2.0, dirt_w);

	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_w = clamp(COLOR.b + smoothstep(0.28, 0.5, slope + (mid - 0.5) * 0.15) + (h_rock - 0.5) * 0.5 * step(0.05, COLOR.b + slope), 0.0, 1.0);
	float forest_w = smoothstep(0.1, 0.9, COLOR.g + (mid - 0.5) * 0.3 + edge * 0.35);
	float sand_w = smoothstep(0.15, 0.85, COLOR.r + (mid - 0.5) * 0.25 + edge * 0.4);

	vec3 col = col_grass;
	col = mix(col, forest * t_forest * 2.0, forest_w);
	col = mix(col, sand * t_sand * 2.0, sand_w);
	col = mix(col, rock * t_rock * 2.0, rock_w);

	// The detail fades a little far from the camera (no shimmer, no visible repeat).
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float keep = detail * mix(1.0, 0.55, smoothstep(25.0, 90.0, dist));
	vec3 plain = mix(mix(mix(grass * (1.0 - dirt_w) + dirt * dirt_w, forest, forest_w), sand, sand_w), rock, rock_w);
	col = mix(plain, col, keep);

	// Winter: snow settles on flat ground above the waterline, over the detail.
	float flat_ground = smoothstep(0.55, 0.85, world_normal.y);
	float snow_w = snow * flat_ground * smoothstep(-0.2, 0.3, world_pos.y) * (0.82 + 0.18 * fine);
	col = mix(col, vec3(0.74, 0.78, 0.85) * (0.9 + 0.12 * mid), snow_w);

	// Darker, wet ground at and below the waterline.
	float wet = smoothstep(0.35, -0.15, world_pos.y);
	col *= mix(1.0, 0.72, wet);

	// Relief from the dominant ground type's normal map, in world space.
	int top = GRASS;
	float best = (1.0 - forest_w) * (1.0 - sand_w) * (1.0 - rock_w);
	if (forest_w * (1.0 - sand_w) * (1.0 - rock_w) > best) { top = FOREST; best = forest_w * (1.0 - sand_w) * (1.0 - rock_w); }
	if (sand_w * (1.0 - rock_w) > best) { top = SAND; best = sand_w * (1.0 - rock_w); }
	if (rock_w > best) { top = ROCK; }
	vec3 nt = texture(ground_normal, vec3(p / tile, float(top))).rgb * 2.0 - 1.0;
	float strength = relief * (1.0 - snow_w) * mix(1.0, 0.0, smoothstep(30.0, 80.0, dist));
	vec3 n_world = normalize(world_normal + vec3(nt.x, 0.0, -nt.y) * strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ALBEDO = col;
	float r_type = mix(mix(mix(0.92, 0.95, forest_w), 0.88, sand_w), 0.82, rock_w);
	ROUGHNESS = mix(r_type + (0.5 - dot(col, vec3(0.33))) * 0.1, 0.55, wet);
	SPECULAR = 0.25;
}
