// Leaves, needles and bushes: colour from the instance, and a soft sway in the wind.
shader_type spatial;
render_mode cull_disabled;

uniform float sway = 0.05;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world.x * 0.35 + world.z * 0.27;
	vec3 wind = vec3(sin(TIME * 1.3 + phase), 0.0, cos(TIME * 1.1 + phase * 1.3)) * sway;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
}

void fragment() {
	// A touch of light through the leaves at grazing angles.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * (0.92 + rim * 0.25);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
