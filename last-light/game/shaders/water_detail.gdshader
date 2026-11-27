// Water, phase 5B.1 (GRAPHICS_PHASE_5B1_WATER_SURFACE.md): the same sheet of
// water as water.gdshader (the same swell, moving the same way, at the same
// level), drawn more naturally:
//  - Its colour comes from how deep the water is under each point, read from
//    the scene's depth: clear and green-turquoise over the shallows, where the
//    seabed and shore show through, deepening to a dark blue-green offshore.
//  - It fades out at the waterline instead of ending in a hard line, with a
//    faint, broken lap of light water along the shore and around anything
//    standing in it.
//  - Small wind ripples (textures/water/ripples_normal.png, made in
//    tools/build_water_textures.gd) drift across it in two directions over
//    the old broad swell, fading with distance.
//  - Softer highlights (roughness about 0.1-0.16 rather than 0.06) and a
//    muted sky sheen at low angles, rather than glare.
// No reflections are rendered: the sky sheen is a colour, as before.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.19);
uniform vec3 mid_water : source_color = vec3(0.05, 0.22, 0.28);
uniform vec3 shallow : source_color = vec3(0.11, 0.35, 0.34);
uniform vec3 sky_tint : source_color = vec3(0.42, 0.55, 0.63);
uniform vec3 lap : source_color = vec3(0.70, 0.76, 0.72);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float ripple_strength = 0.55;
uniform float clarity = 0.75;        // metres of water before it is mostly opaque

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The swell, exactly as before.
	VERTEX.y += sin(world_pos.x * 0.21 + TIME * 0.9) * 0.05 + sin(world_pos.z * 0.17 + TIME * 0.7) * 0.05;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);

	// How deep the water is here: the scene behind this point, in world space.
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	behind.xyz /= behind.w;
	vec3 behind_world = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - behind_world.y, 0.0);
	// Along the line of sight too, so that steep views into deep water stay deep.
	float through = max(length(behind.xyz) - length(VERTEX), 0.0);
	float shade_depth = mix(depth, through, 0.3);

	// The old broad swell, softened, with the ripples over it.
	vec3 n = vec3(
		sin(p.x * 0.8 + t * 1.2) * 0.04 + sin(p.y * 1.9 - t * 0.8) * 0.025,
		1.0,
		cos(p.y * 0.7 + t * 1.0) * 0.04 + cos(p.x * 2.1 + t * 0.6) * 0.025);
	vec2 r1 = texture(ripples, p / 5.5 + vec2(t * 0.021, t * 0.013)).rg * 2.0 - 1.0;
	vec2 r2 = texture(ripples, vec2(p.x * 0.6 - p.y * 0.8, p.x * 0.8 + p.y * 0.6) / 13.0 - vec2(t * 0.011, -t * 0.017)).rg * 2.0 - 1.0;
	float near = 1.0 - smoothstep(35.0, 140.0, dist);
	vec2 r = (r1 * 0.6 + r2 * 0.4) * ripple_strength * mix(0.25, 1.0, near);
	n.x += r.x;
	n.z -= r.y;
	n = normalize(n);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	// Colour by depth, with a slow drift between greener and bluer water.
	float drift = vnoise(p * 0.018 + 5.0);
	vec3 shallow_c = mix(shallow, shallow * vec3(0.9, 1.0, 1.1), drift);
	vec3 col = mix(shallow_c, mid_water, smoothstep(0.0, 1.4, shade_depth));
	col = mix(col, deep, smoothstep(1.0, 4.0, shade_depth));

	// A muted sky sheen at low angles.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	col = mix(col, sky_tint, clamp(fresnel, 0.0, 1.0) * 0.32);

	// A faint, broken lap of light water along the waterline.
	float edge = 1.0 - smoothstep(0.0, 0.12, depth);
	float broken = smoothstep(0.35, 0.75, vnoise(p * 1.7 + vec2(t * 0.25, -t * 0.18)) + r.x * 0.4);
	float lap_w = edge * broken * 0.35 * smoothstep(0.004, 0.03, depth);
	col = mix(col, lap, lap_w);

	ALBEDO = col;
	// Clear in the shallows (the seabed shows), fading in at the waterline.
	float opacity = 1.0 - exp(-shade_depth / clarity);
	ALPHA = clamp(mix(0.18, 0.94, opacity) + fresnel * 0.3 + lap_w * 0.5, 0.0, 0.96) * smoothstep(0.0, 0.06, depth);
	ROUGHNESS = mix(0.1, 0.16, near * clamp(length(r) * 2.0, 0.0, 1.0));
	SPECULAR = 0.5;
}
