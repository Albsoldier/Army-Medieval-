// Shared by prop_rigid and prop_leaves: the colour of one part of one prop.
//
// Every part of a prop type is merged into one mesh, so a whole tree is one
// MultiMesh instance. Per vertex:  UV.xy, UV2.x = the part's base colour (sRGB);
//                                  UV2.y = sway (leaves), 0 (rigid), -1 (berries).
// Per instance:  COLOR.rgb = seasonal leaf tint, COLOR.a = how much of it;
//                INSTANCE_CUSTOM = (shade, winter tint on rocks and stumps,
//                                   hide leaves, hide berries).
// This reproduces world.gd's old per-part colours exactly: the season's tint,
// then Color.lightened()/darkened() by the prop's shade.

const vec3 FROST = vec3(0.88, 0.9, 0.94);

vec3 prop_color(vec3 base, float part, vec4 tint, vec4 custom) {
	vec3 c = base;
	if (part > 0.0) {
		c = mix(c, tint.rgb, tint.a);  // leaves take the season's colour
	} else {
		c = mix(c, FROST, custom.y);  // rocks and stumps frost over in winter
	}
	float shade = custom.x;
	return shade > 0.0 ? c + (vec3(1.0) - c) * shade : c * (1.0 + shade);
}

// True if this part is hidden this season (bare oaks, no berries in winter).
bool prop_hidden(float part, vec4 custom) {
	return (part > 0.0 && custom.z > 0.5) || (part < 0.0 && custom.w > 0.5);
}
