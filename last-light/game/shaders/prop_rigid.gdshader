// Trunks, rocks, stumps, rubble and berries: the parts of props that don't
// sway. Matches the StandardMaterial3D they used before (instance colour as
// albedo, roughness 0.95, back faces culled).
shader_type spatial;

#include "res://shaders/props.gdshaderinc"

varying vec3 part_color;

void vertex() {
	float part = UV2.y;
	if (prop_hidden(part, INSTANCE_CUSTOM)) {
		VERTEX = vec3(0.0);
	}
	part_color = prop_color(vec3(UV.x, UV.y, UV2.x), part, COLOR, INSTANCE_CUSTOM);
}

void fragment() {
	// The colour as-is: measured against the old StandardMaterial3D renders,
	// which didn't convert these MultiMesh colours from sRGB either.
	ALBEDO = part_color;
	ROUGHNESS = 0.95;
}
