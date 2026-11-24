// Leaves, needles and bushes, merged per prop type: the same look as
// foliage.gdshader (soft sway in the wind, a touch of light through the leaves),
// with each part's sway and colour coming from the merged mesh.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/props.gdshaderinc"

varying vec3 part_color;

void vertex() {
	float sway = UV2.y;
	if (prop_hidden(sway, INSTANCE_CUSTOM)) {
		VERTEX = vec3(0.0);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world.x * 0.35 + world.z * 0.27;
	vec3 wind = vec3(sin(TIME * 1.3 + phase), 0.0, cos(TIME * 1.1 + phase * 1.3)) * sway;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
	part_color = prop_color(vec3(UV.x, UV.y, UV2.x), sway, COLOR, INSTANCE_CUSTOM);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = part_color * (0.92 + rim * 0.25);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
