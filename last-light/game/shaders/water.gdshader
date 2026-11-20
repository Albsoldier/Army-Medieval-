// Sea and lakes: gentle swell, moving ripples and a reflective sheen at low angles.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

uniform vec3 deep : source_color = vec3(0.04, 0.14, 0.21);
uniform vec3 shallow : source_color = vec3(0.11, 0.28, 0.33);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.68, 0.78);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.21 + TIME * 0.9) * 0.05 + sin(world_pos.z * 0.17 + TIME * 0.7) * 0.05;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	vec3 n = vec3(
		sin(p.x * 0.8 + t * 1.2) * 0.06 + sin(p.y * 1.9 - t * 0.8) * 0.04 + sin((p.x + p.y) * 3.1 + t * 1.7) * 0.02,
		1.0,
		cos(p.y * 0.7 + t * 1.0) * 0.06 + cos(p.x * 2.1 + t * 0.6) * 0.04 + cos((p.x - p.y) * 2.7 - t * 1.4) * 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(mix(shallow, deep, 0.6), sky_tint, fresnel * 0.6);
	ALPHA = mix(0.76, 0.95, fresnel);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
}
