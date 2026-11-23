## Weapons and armour, by material. Better materials make better gear:
## wood and flint early on, iron once you have a forge, steel later,
## and gilded steel (gold from the islets) at the end.
## Each list is ordered from worst to best; a tier is an index into it.
extends RefCounted

const SPEAR := [
	{"name": "Wooden spear", "damage": 2, "cost": {"wood": 4}, "station": "hand", "tip": Color("8a6440"), "shaft": Color("a07548")},
	{"name": "Flint spear", "damage": 3, "cost": {"wood": 3, "stone": 2}, "station": "hand", "tip": Color("6f6c66"), "shaft": Color("caa472")},
	{"name": "Iron spear", "damage": 5, "cost": {"iron": 3, "wood": 2}, "station": "forge", "tip": Color("9ea2a8"), "shaft": Color("caa472")},
	{"name": "Steel spear", "damage": 8, "cost": {"steel": 3, "wood": 2}, "station": "forge", "tip": Color("d4dae2"), "shaft": Color("7a5636")},
	{"name": "Gilded spear", "damage": 12, "cost": {"steel": 3, "gold": 2}, "station": "forge", "tip": Color("e8c25a"), "shaft": Color("5a3d22")},
]
const SWORD := [
	{"name": "Iron sword", "damage": 6, "cost": {"iron": 4, "hide": 1}, "station": "forge", "blade": Color("9ea2a8"), "hilt": Color("5a3d22")},
	{"name": "Steel sword", "damage": 10, "cost": {"steel": 4, "hide": 1}, "station": "forge", "blade": Color("d4dae2"), "hilt": Color("3d2a18")},
	{"name": "Gilded sword", "damage": 15, "cost": {"steel": 3, "gold": 3}, "station": "forge", "blade": Color("e6d28a"), "hilt": Color("e0b43c")},
]
## reduce: the share of every bite the armour stops. warmth: how much it slows the cold.
const ARMOUR := [
	{"name": "Hide armour", "reduce": 0.2, "warmth": 0.2, "cost": {"hide": 4, "wood": 1}, "station": "workbench", "color": Color("6e4f33"), "trim": Color("4d3420")},
	{"name": "Iron armour", "reduce": 0.45, "warmth": 0.0, "cost": {"iron": 5, "hide": 3}, "station": "forge", "color": Color("7d8186"), "trim": Color("5d6166")},
	{"name": "Steel armour", "reduce": 0.6, "warmth": 0.0, "cost": {"steel": 5, "hide": 3}, "station": "forge", "color": Color("c4cad2"), "trim": Color("8a9098")},
	{"name": "Gilded armour", "reduce": 0.75, "warmth": 0.1, "cost": {"steel": 4, "gold": 4, "hide": 2}, "station": "forge", "color": Color("d9bd6a"), "trim": Color("f0cf5a")},
]
const SPEAR_REACH := 34.0
const SWORD_REACH := 27.0
const SPEAR_COOLDOWN := 0.45
const SWORD_COOLDOWN := 0.3  # swords are quicker


static func list_for(kind: String) -> Array:
	match kind:
		"spear":
			return SPEAR
		"sword":
			return SWORD
	return ARMOUR


static func info(kind: String, tier: int) -> Dictionary:
	var l := list_for(kind)
	return l[clampi(tier, 0, l.size() - 1)] if tier >= 0 else {}


static func tier_name(kind: String, tier: int) -> String:
	return str(info(kind, tier).get("name", ""))


## The stat line shown next to a piece of gear.
static func stat_text(kind: String, tier: int) -> String:
	var g := info(kind, tier)
	if g.is_empty():
		return ""
	if kind == "armour":
		return "stops %d%% of bites" % int(round(float(g["reduce"]) * 100.0))
	return "%d damage" % int(g["damage"])


## Recipes made at a station ("hand" means from the inventory), as
## {"id": "gear:<kind>:<tier>", "name", "cost", "about", "kind", "tier"}.
static func recipes_for(station: String) -> Array:
	var out := []
	for kind in ["spear", "sword", "armour"]:
		var l := list_for(kind)
		for t in l.size():
			if str(l[t]["station"]) == station:
				out.append({"id": "gear:%s:%d" % [kind, t], "name": str(l[t]["name"]), "cost": l[t]["cost"],
					"about": stat_text(kind, t), "kind": kind, "tier": t})
	return out
