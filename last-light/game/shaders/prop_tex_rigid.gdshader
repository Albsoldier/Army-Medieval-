// Bark and rock of the textured nature models (models/nature, phase 4A).
// The same seasonal colouring as prop_rigid.gdshader (frost, per-prop shade),
// applied to the model's texture instead of a flat part colour.
// Per vertex: UV = texture coordinates; UV2 = (0, baked shading: bark is
// darker where branches meet). Per instance: as props.gdshaderinc.
shader_type spatial;

#include "res://shaders/props.gdshaderinc"

uniform sampler2D albedo : filter_linear_mipmap, repeat_enable;

varying vec4 tint;
varying vec4 custom;
varying float shading;

void vertex() {
	tint = COLOR;
	custom = INSTANCE_CUSTOM;
	shading = UV2.y;
}

void fragment() {
	// Texture colours are used as stored, like every other prop colour in the
	// game (see prop_rigid.gdshader), so the new models sit in the same palette.
	vec3 base = texture(albedo, UV).rgb * shading;
	ALBEDO = prop_color(base, 0.0, tint, custom);
	ROUGHNESS = 0.95;
}
