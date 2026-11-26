// A character built into one textured, skinned surface by
// tools/build_player_model.gd (phase 4C, GRAPHICS_PLAYER_REFINEMENT.md), with
// its appearance chosen per character by instance uniforms, so that many
// characters can share this one material (and one mesh) and still look
// different: hood up or down, skin tone, outfit, worn armour and backpack.
//
// UV is the texture atlas. UV2.x is the part a vertex belongs to, plus a
// lateral coordinate in its fraction (part + 0.05 + 0.9 * across); UV2.y is a
// height along the part (armour plates). Parts:
//   0 clothing, 1 skin, 2 the hood over the head and cropped hair (hood up
//   only), 3 the hood folded down and hair (hood down only), 4 armour shell,
//   5 backpack.
// A hidden part's vertices are collapsed to one point: its triangles have no
// area and draw nothing, at no cost beyond the vertex itself.
//
// Lighting matches the StandardMaterial3D this replaces, with the finish
// character_model.gd's _enhance() gave it (specular 0.35, roughness x0.85,
// soft rim light; stronger rim on skin).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
// The alternative outfit: the clothing half of the atlas (x < 0.5), recoloured.
uniform sampler2D outfit_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
// Roughness in G, metal in B.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;

instance uniform float hood_up = 1.0;
instance uniform float armour_on = 0.0;
instance uniform float backpack_on = 1.0;
instance uniform float outfit = 0.0;  // 0: the original (green), 1: outfit_tex (beige and brown)
// Multiplies skin albedo (linear). It keeps the texture's own shading, pores
// and blush, unlike painting over it; 1 is the texture as made.
instance uniform vec3 skin_gain = vec3(1.0);
instance uniform vec4 armour_color : source_color = vec4(0.49, 0.505, 0.525, 1.0);
instance uniform vec4 armour_trim : source_color = vec4(0.365, 0.38, 0.4, 1.0);
instance uniform float armour_metal = 0.75;  // 0 for hide

varying float v_skin;
varying float v_armour;
varying vec2 v_plate;  // (across, height) on the armour

void vertex() {
	float part = floor(UV2.x);
	float hide = 0.0;
	if (part == 2.0) {
		hide = 1.0 - hood_up;
	} else if (part == 3.0) {
		hide = hood_up;
	} else if (part == 4.0) {
		hide = 1.0 - armour_on;
	} else if (part == 5.0) {
		hide = 1.0 - backpack_on;
	}
	if (hide > 0.5) {
		VERTEX = vec3(0.0);
	}
	v_skin = part == 1.0 ? 1.0 : 0.0;
	v_armour = part == 4.0 ? 1.0 : 0.0;
	v_plate = vec2((fract(UV2.x) - 0.05) / 0.9, UV2.y);
}

void fragment() {
	// The second outfit (GRAPHICS_PLAYER_OUTFITS.md) replaces the clothing half
	// of the atlas. `outfit` is the same over the whole character, so this
	// branch is uniform: mipmaps stay right, and the original outfit doesn't
	// pay for the second texture. The result is as before: the alternative
	// texture where UV.x < 0.5 (clothing), the atlas elsewhere (skin, hair, eyes).
	vec3 col = texture(albedo_tex, UV).rgb;
	if (outfit > 0.5) {
		vec3 alt = texture(outfit_tex, vec2(UV.x * 2.0, UV.y)).rgb;
		col = mix(col, alt, step(UV.x, 0.5));
	}
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 nrm = texture(normal_tex, UV).rgb;
	float rough = orm.g * 0.85;
	float metal = orm.b;
	// Lighter tones scale highlights up too: those are scaled back as a whole
	// (keeping their hue) rather than clipped per channel, which turns them white.
	vec3 toned = col * skin_gain;
	toned *= min(1.0, 0.75 / max(max(toned.r, toned.g), max(toned.b, 0.001)));
	col = mix(col, toned, v_skin);

	// Armour: horizontal plates (lames) with dark seams, a raised centre
	// ridge, and a trim band at the neck and waist; smooth metal (or hide).
	float a = v_armour;
	float lame = fract(v_plate.y * 5.0);
	float seam = smoothstep(0.0, 0.07, lame) * smoothstep(1.0, 0.9, lame);
	float ridge = 1.0 - smoothstep(0.0, 0.05, abs(v_plate.x - 0.5));
	float trim = 1.0 - smoothstep(0.06, 0.1, min(v_plate.y, 1.0 - v_plate.y));
	vec3 plate = armour_color.rgb * mix(0.55, 1.0, seam) * (1.0 + 0.25 * ridge);
	plate = mix(plate, armour_trim.rgb, trim);
	col = mix(col, plate, a);
	metal = mix(metal, armour_metal, a);
	rough = mix(rough, mix(0.8, 0.32, armour_metal), a);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), a);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.35, 0.45, v_skin);
	NORMAL_MAP = nrm;
	RIM = mix(0.18, 0.32, v_skin) * (1.0 - a * armour_metal);
	RIM_TINT = mix(0.6, 0.85, v_skin);
}
