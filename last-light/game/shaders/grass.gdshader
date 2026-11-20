// Grass clumps: dark at the root, lighter at the tip, bending in the wind.
shader_type spatial;
render_mode cull_disabled;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = UV.y * UV.y;  // only the tips move
	float gust = sin(TIME * 1.7 + world.x * 0.4 + world.z * 0.3) * 0.5 + sin(TIME * 3.1 + world.x * 1.3) * 0.2;
	vec3 wind = vec3(gust * 0.12, 0.0, gust * 0.06) * bend;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
}

void fragment() {
	// Light every blade as if it faced the sky, whichever side we see,
	// so the backs of blades don't turn black.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = COLOR.rgb * mix(0.7, 1.12, UV.y);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
