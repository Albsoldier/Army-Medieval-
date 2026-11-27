// The village buildings (tools/build_village_models.gd; GRAPHICS_VILLAGE_BUILDINGS.md):
// every surface of every building on one material. The kits' ten colour maps
// are the layers of one texture array; UV2.x picks the layer, so a building is
// one draw call and the textures still tile (the kits' trims repeat along the
// walls and the roof tiles in both directions). COLOR dyes a piece (the
// barracks' banners).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray textures : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec3 albedo = texture(textures, vec3(UV, floor(UV2.x + 0.5))).rgb;
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.3;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
