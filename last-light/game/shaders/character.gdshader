// Characters whose mesh parts and materials were merged into one skinned
// surface (character_model.gd, _merge_meshes). Each vertex carries its old
// material's values, so one draw renders what used to take a dozen:
//   COLOR.rgb = albedo (stored as sRGB), COLOR.a = roughness
//   UV        = (metallic, specular)
//   UV2       = (rim, rim tint)
// Lighting is StandardMaterial3D's defaults (Burley diffuse, Schlick-GGX
// specular, back faces culled), so the result matches the old materials.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec4 params;

void vertex() {
	params = vec4(UV, UV2);
}

void fragment() {
	// Godot hands vertex colours to the shader already converted from sRGB
	// to linear, just as a material's albedo colour is (measured: see
	// GRAPHICS_DRAWCALL_OPTIMIZATION.md), so they're used as they come.
	ALBEDO = COLOR.rgb;
	ROUGHNESS = COLOR.a;
	METALLIC = params.x;
	SPECULAR = params.y;
	RIM = params.z;
	RIM_TINT = params.w;
}
