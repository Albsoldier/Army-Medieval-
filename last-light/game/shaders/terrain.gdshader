// Terrain: one smooth surface that blends grass, forest floor, sand and rock.
// Vertex colour carries the blend weights: r = sand, g = forest floor, b = rock
// (grass is what's left). Steep slopes turn to rock on their own.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 grass_a : source_color = vec3(0.33, 0.42, 0.20);
uniform vec3 grass_b : source_color = vec3(0.47, 0.53, 0.26);
uniform vec3 dry_grass : source_color = vec3(0.60, 0.56, 0.33);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.24);
uniform vec3 forest_a : source_color = vec3(0.22, 0.27, 0.14);
uniform vec3 forest_b : source_color = vec3(0.33, 0.29, 0.18);
uniform vec3 sand_a : source_color = vec3(0.74, 0.66, 0.48);
uniform vec3 sand_b : source_color = vec3(0.62, 0.55, 0.40);
uniform vec3 rock_a : source_color = vec3(0.45, 0.43, 0.40);
uniform vec3 rock_b : source_color = vec3(0.58, 0.56, 0.51);

varying vec3 world_pos;
varying vec3 world_normal;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float broad = fbm(p * 0.035);
	float mid = fbm(p * 0.25);
	float fine = vnoise(p * 2.7);

	// Meadows shift between lush and dry, with patches of bare earth.
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, broad));
	grass = mix(grass, dry_grass, smoothstep(0.62, 0.85, fbm(p * 0.06 + 13.0)) * 0.7);
	grass *= 0.86 + 0.24 * mid + 0.08 * fine;
	grass = mix(grass, dirt, smoothstep(0.66, 0.82, fbm(p * 0.18 + 7.0)) * 0.55);

	vec3 forest = mix(forest_a, forest_b, mid) * (0.9 + 0.15 * fine);
	vec3 sand = mix(sand_a, sand_b, mid * 0.7 + fine * 0.3);
	vec3 rock = mix(rock_a, rock_b, mid) * (0.82 + 0.3 * fine);

	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_w = clamp(COLOR.b + smoothstep(0.28, 0.5, slope + (mid - 0.5) * 0.15), 0.0, 1.0);

	vec3 col = grass;
	col = mix(col, forest, smoothstep(0.1, 0.9, COLOR.g + (mid - 0.5) * 0.3));
	col = mix(col, sand, smoothstep(0.15, 0.85, COLOR.r + (mid - 0.5) * 0.25));
	col = mix(col, rock, rock_w);

	// Darker, wet ground at and below the waterline.
	float wet = smoothstep(0.35, -0.15, world_pos.y);
	col *= mix(1.0, 0.72, wet);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, wet);
	SPECULAR = 0.25;
}
