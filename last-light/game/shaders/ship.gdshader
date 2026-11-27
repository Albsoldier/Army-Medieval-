// The ship (tools/build_ship_model.gd; GRAPHICS_SHIPS.md): hull, rigging and
// sails in one surface and one draw call, each part with its own small,
// tiling colour map. UV2.x is the part: 0 hull, 1 rigging, 2 sails. All three
// maps are sampled and one is kept (no branching on a texture fetch).
// Double-sided, like the original: the far side of a sail or a plank is lit
// from its own side.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D hull_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rigging_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sails_texture : source_color, filter_linear_mipmap, repeat_enable;

varying float part;

void vertex() {
	part = UV2.x;
}

void fragment() {
	vec3 hull = texture(hull_texture, UV).rgb;
	vec3 rigging = texture(rigging_texture, UV).rgb;
	vec3 sails = texture(sails_texture, UV).rgb;
	float is_rigging = step(0.5, part) * (1.0 - step(1.5, part));
	float is_sails = step(1.5, part);
	ALBEDO = mix(mix(hull, rigging, is_rigging), sails, is_sails);
	ROUGHNESS = mix(mix(0.85, 0.8, is_rigging), 0.95, is_sails);
	METALLIC = 0.0;
	// Canvas lets light through: a sail's shaded side isn't black.
	BACKLIGHT = ALBEDO * (0.55 * is_sails + 0.3 * is_rigging);
	SPECULAR = 0.3;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
