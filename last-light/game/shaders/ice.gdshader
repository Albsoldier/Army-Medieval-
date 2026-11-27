// Winter ice, phase 5B.1 (GRAPHICS_PHASE_5B1_WATER_SURFACE.md). Drawn on the
// sheet world.gd's _build_ice_smooth makes: the ground cuts it off along the
// shoreline, and COLOR.a fades towards open deep water, where this shader cuts
// a ragged edge (alpha scissor, so the ice stays solid and writes depth: the
// water around it then sees it as a shore and fades against it).
// The look: pale, slightly blue ice with clearer, darker patches, drifts of
// powder snow, faint cracks and a soft sheen. It is only the look: where you
// can walk on the ice is still the frozen tiles.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 ice_pale : source_color = vec3(0.57, 0.64, 0.68);
uniform vec3 ice_clear : source_color = vec3(0.29, 0.39, 0.45);
uniform vec3 snow_col : source_color = vec3(0.86, 0.89, 0.93);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

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
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);

	// A ragged edge where the ice gives way to open water.
	float ragged = fbm(p * 0.9 + 3.0);
	ALPHA = COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = clamp(0.5 + (ragged - 0.5) * 0.6, 0.05, 0.95);

	// Clearer, darker ice in patches, powder snow in drifts, and the thin ice at the edge darker.
	float clear_w = smoothstep(0.45, 0.7, fbm(p * 0.12 + 17.0));
	vec3 col = mix(ice_pale, ice_clear, clear_w * 0.8);
	col = mix(col, ice_clear * 0.8, (1.0 - smoothstep(0.5, 0.95, COLOR.a)) * 0.6);
	float drift = smoothstep(0.5, 0.75, fbm(p * 0.22 + vec2(5.0, 9.0)) + (vnoise(p * 3.1) - 0.5) * 0.15);
	col = mix(col, snow_col, drift * 0.75);

	// Faint cracks, fading with distance.
	float crack_n = vnoise(p * 0.7 + 41.0) + (vnoise(p * 4.0) - 0.5) * 0.08;
	float crack = 1.0 - smoothstep(0.0, 0.012, abs(crack_n - 0.5));
	crack *= smoothstep(0.55, 0.7, vnoise(p * 0.15 + 3.0));   // only here and there
	crack *= (1.0 - drift) * (1.0 - smoothstep(15.0, 45.0, dist));
	col = mix(col, col * vec3(0.8, 0.85, 0.9), crack);

	// Gentle unevenness from the ripple map, very much flattened.
	vec2 r = texture(ripples, p / 7.0).rg * 2.0 - 1.0;
	vec3 n = normalize(vec3(r.x * 0.12, 1.0, -r.y * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ALBEDO = col;
	ROUGHNESS = mix(0.22, 0.85, drift);
	SPECULAR = 0.45;
}
