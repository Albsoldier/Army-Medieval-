// Leaf, needle and flower cards of the textured nature models (models/nature,
// phase 4A). The same look as prop_leaves.gdshader (wind sway, seasonal tint,
// light through the leaves), with the card's shape cut out of its texture.
// Cut-out (alpha scissor), not blending: no sorting, and the cards write depth
// and cast shadows like solid geometry.
// Per vertex: UV = texture coordinates; UV2 = (1 for leaves or -1 for flowers,
// sway in metres). Per instance: as props.gdshaderinc (winter hides leaves on
// oaks and flowers on bushes; picked bushes hide their flowers).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/props.gdshaderinc"

uniform sampler2D albedo : filter_linear_mipmap;
uniform float alpha_cut = 0.35;

varying vec4 tint;
varying vec4 custom;
varying float part;

void vertex() {
	part = UV2.x;
	if (prop_hidden(part, INSTANCE_CUSTOM)) {
		VERTEX = vec3(0.0);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world.x * 0.35 + world.z * 0.27;
	vec3 wind = vec3(sin(TIME * 1.3 + phase), 0.0, cos(TIME * 1.1 + phase * 1.3)) * UV2.y;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
	tint = COLOR;
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 t = texture(albedo, UV);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = prop_color(t.rgb, part, tint, custom) * (0.92 + rim * 0.25);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
