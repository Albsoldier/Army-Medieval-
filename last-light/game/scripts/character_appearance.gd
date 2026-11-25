## How a character drawn with shaders/character_atlas.gdshader looks: hood up
## or down, skin tone, outfit, backpack and worn armour (phase 4C,
## GRAPHICS_PLAYER_REFINEMENT.md). Everything is set with instance uniforms on
## the character's MeshInstance3D, so characters that look different still
## share one mesh and one material. Used by the player; written so the
## soldiers can use it later.
extends RefCounted

## The skin texture's average colour (sRGB), measured over the kit's skin
## textures: the "medium" tone, as the kit made it.
const SKIN_REFERENCE := Color8(167, 116, 81)
## Skin colours (sRGB) for each tone, as albedo. Skin is multiplied by
## tone / reference (in linear light), so the texture's own shading, pores
## and blush stay; nothing is painted over. The steps are closer than real
## albedo would be: the game's filmic tone mapping crushes dark albedo, so
## these were chosen from renders (GRAPHICS_PLAYER_REFINEMENT.md) to read as
## evenly spaced tones by day, with the darkest still showing the face.
const SKIN_TONES := {
	"light": Color8(184, 132, 94),
	"medium": Color8(167, 116, 81),
	"tan": Color8(156, 106, 71),
	"dark": Color8(147, 98, 65),
	"deep": Color8(131, 85, 56),
}
const OUTFITS := ["ranger", "earth"]  # earth: the kit's beige and brown dye of the same clothes
const DEFAULT := {"hood": true, "skin": "medium", "outfit": "ranger", "backpack": true}


## Sets everything but the armour. look: as DEFAULT; missing keys keep the default.
static func apply(mi: GeometryInstance3D, look: Dictionary) -> void:
	mi.set_instance_shader_parameter("hood_up", 1.0 if look.get("hood", true) else 0.0)
	mi.set_instance_shader_parameter("backpack_on", 1.0 if look.get("backpack", true) else 0.0)
	mi.set_instance_shader_parameter("outfit", float(maxi(OUTFITS.find(str(look.get("outfit", "ranger"))), 0)))
	mi.set_instance_shader_parameter("skin_gain", skin_gain(str(look.get("skin", "medium"))))


## Worn armour: off, or on in the colours (sRGB) and finish of what it's made of.
static func set_armour(mi: GeometryInstance3D, on: bool, color := Color.GRAY, trim := Color.DIM_GRAY, metal := 0.75) -> void:
	mi.set_instance_shader_parameter("armour_on", 1.0 if on else 0.0)
	if on:
		mi.set_instance_shader_parameter("armour_color", color)
		mi.set_instance_shader_parameter("armour_trim", trim)
		mi.set_instance_shader_parameter("armour_metal", metal)


## The multiplier (linear light) that turns the reference skin into `tone`.
static func skin_gain(tone: String) -> Vector3:
	var to: Color = SKIN_TONES.get(tone, SKIN_REFERENCE)
	var a := to.srgb_to_linear()
	var b := SKIN_REFERENCE.srgb_to_linear()
	return Vector3(a.r / b.r, a.g / b.g, a.b / b.b)


## A look from URL-style options (?hood=down&skin=dark&outfit=earth&backpack=0);
## unknown values are ignored.
static func from_options(options: Dictionary) -> Dictionary:
	var look := DEFAULT.duplicate()
	if options.has("hood"):
		look["hood"] = str(options["hood"]) not in ["down", "0", "off"]
	if SKIN_TONES.has(str(options.get("skin", ""))):
		look["skin"] = str(options["skin"])
	if str(options.get("outfit", "")) in OUTFITS:
		look["outfit"] = str(options["outfit"])
	if options.has("backpack"):
		look["backpack"] = str(options["backpack"]) not in ["0", "off"]
	return look
