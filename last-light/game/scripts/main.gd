## Last Light: game loop, rules and the link between the island and the server.
extends Node3D

const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Campfire = preload("res://scripts/campfire.gd")
const Wolf = preload("res://scripts/wolf.gd")
const Trace = preload("res://scripts/trace.gd")
const Hud = preload("res://scripts/hud.gd")
const Api = preload("res://scripts/api.gd")

const DAY_LENGTH := 240.0  # seconds of real time per in-game day
const INTERACT_RADIUS := 26.0
const ITEM_NAMES := {
	"wood": "wood", "stone": "stone", "berries": "berries",
	"raw_meat": "raw meat", "cooked_meat": "cooked meat",
}
const RECIPES := {
	"campfire": {"wood": 5, "stone": 3},
	"torch": {"wood": 2},
	"spear": {"wood": 3, "stone": 2},
}
const NAME_A := ["Ashen", "Hollow", "Weeping", "Silent", "Drowned", "Ember", "Pale", "Thorn", "Grey", "Lantern", "Salt", "Gloam"]
const NAME_B := ["Isle", "Reach", "Shoal", "Haven", "Rock", "Atoll", "Key", "Holm", "Skerry", "Strand"]

var world: World
var player: Player
var hud: Hud
var api: Api
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var entities: Node3D
var zoom := 1.0

var seed_value := 0
var island_name := ""
var day := 1
var clock := DAY_LENGTH * 0.05
var started := false
var alive := true
var run_id := ""
var last_damage := "unknown causes"
var action_cooldown := 0.0
var attack_cooldown := 0.0
var wolf_spawn_timer := 6.0
var howled_tonight := false
var campfires: Array = []
var wolves: Array = []
var traces: Array = []
var rng := RandomNumberGenerator.new()
var _auth_retried := false


func _ready() -> void:
	_setup_input()
	rng.randomize()
	seed_value = seed_override() if seed_override() > 0 else today_seed()
	island_name = make_island_name(seed_value)

	world = World.new()
	add_child(world)
	world.generate(seed_value)

	entities = Node3D.new()
	add_child(entities)

	player = Player.new()
	player.world = world
	player.pos = world.cell_center(world.spawn_cell)
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 160.0
	add_child(camera)
	camera.make_current()
	_setup_environment()
	_update_camera(1.0)

	hud = Hud.new()
	add_child(hud)
	api = Api.new()
	add_child(api)

	hud.set_island(island_name, seed_value)
	_update_lighting()
	_refresh_hud()

	if api.player_name == "":
		hud.open_dialog("Last Light",
			"You wake on the cold sand of %s. Others have washed up here before you, and some never left.\n\nWhat should the island remember you as?" % island_name,
			PackedStringArray(["Begin"]), _on_name_chosen, "Your name", 20, false)
	else:
		_begin_run()


# ---------- Setup ----------

static func today_seed() -> int:
	var d := Time.get_datetime_dict_from_system(true)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## Run with `-- --seed=20261119` to explore a specific island.
static func seed_override() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return arg.trim_prefix("--seed=").to_int()
	return 0


static func make_island_name(s: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return "%s %s" % [NAME_A[r.randi() % NAME_A.size()], NAME_B[r.randi() % NAME_B.size()]]


func _setup_input() -> void:
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("interact", [KEY_E])
	_bind("attack", [KEY_SPACE])
	_bind("eat", [KEY_F])
	_bind("craft_campfire", [KEY_1])
	_bind("craft_torch", [KEY_2])
	_bind("craft_spear", [KEY_3])
	_bind("write_note", [KEY_N])
	_bind("leave_stash", [KEY_G])
	_bind("help", [KEY_H])
	if InputMap.action_get_events("attack").size() < 2:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", click)


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return  # already set up (the scene was reloaded)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _on_name_chosen(_choice: int, text: String) -> void:
	api.set_player_name(text if text != "" else "Wanderer")
	_begin_run()


func _begin_run() -> void:
	started = true
	hud.toast("Day 1 on %s. Gather wood and stone before nightfall." % island_name)
	var best := api.local_best(seed_value)
	if best >= 0:
		hud.toast("Your best on this island: %d day%s." % [best, "" if best == 1 else "s"])
	if not api.is_online():
		hud.set_connection("Offline: no island server configured.")
		return
	hud.set_connection("Reaching the island server…")
	api.ensure_registered(_on_registered)


func _on_registered(ok: bool) -> void:
	if not ok:
		hud.set_connection("Offline: couldn't reach the island server.")
		return
	hud.set_connection("Online as %s" % api.player_name)
	api.start_run(seed_value, _on_run_started)
	api.fetch_traces(seed_value, _on_traces_loaded)


func _on_run_started(ok: bool, data: Variant) -> void:
	if ok:
		run_id = str(data.get("run_id", ""))
	elif int(data.get("status", 0)) == 401 and not _auth_retried:
		# The server no longer knows our token; sign up again once.
		_auth_retried = true
		api.ensure_registered(_on_reregistered)
	else:
		hud.set_connection("Online, but this run won't be recorded (%s)." % str(data.get("error", "error")))


func _on_reregistered(ok: bool) -> void:
	if ok:
		api.start_run(seed_value, _on_run_started)


func _on_traces_loaded(ok: bool, data: Variant) -> void:
	if not ok:
		return
	var list: Variant = data.get("traces", [])
	if typeof(list) != TYPE_ARRAY:
		return
	var count := 0
	for d in list:
		if typeof(d) == TYPE_DICTIONARY:
			_spawn_trace(d)
			count += 1
	if count > 0:
		hud.toast("Others have been here. You spot signs of %d visitor%s." % [count, "" if count == 1 else "s"])


func _spawn_trace(d: Dictionary) -> void:
	var kind := str(d.get("kind", ""))
	var pos := Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	if kind == "camp":
		var fire: Campfire = Campfire.new()
		fire.fuel = 0.0
		fire.owner_name = str(d.get("player_name", "someone"))
		fire.world = world
		fire.pos = pos
		entities.add_child(fire)
		campfires.append(fire)
	elif kind == "grave" or kind == "note" or kind == "stash":
		var t: Trace = Trace.new()
		t.world = world
		t.setup(d)
		entities.add_child(t)
		traces.append(t)


# ---------- Main loop ----------

func _process(delta: float) -> void:
	player.tick_visuals(delta)
	if started and alive and not hud.is_modal():
		_advance_clock(delta)
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		player.move(dir, delta)
		action_cooldown = maxf(action_cooldown - delta, 0.0)
		attack_cooldown = maxf(attack_cooldown - delta, 0.0)
		for fire in campfires:
			fire.tick(delta)
		_tick_survival(delta)
		_tick_wolves(delta)
		_update_hint()
		if player.health <= 0.0:
			_die()
	_update_camera(delta)
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.1, 0.55, 1.8)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.1, 0.55, 1.8)
	if not started or not alive or hud.is_modal():
		return
	if event.is_action_pressed("interact", true):
		_interact()
	elif event.is_action_pressed("attack", true):
		_attack()
	elif event.is_action_pressed("eat"):
		_eat()
	elif event.is_action_pressed("craft_campfire"):
		_craft("campfire")
	elif event.is_action_pressed("craft_torch"):
		_craft("torch")
	elif event.is_action_pressed("craft_spear"):
		_craft("spear")
	elif event.is_action_pressed("write_note"):
		_write_note()
	elif event.is_action_pressed("leave_stash"):
		_leave_stash()
	elif event.is_action_pressed("help"):
		hud.toggle_help()


# ---------- Time of day ----------

## 0 during the day, 1 in the dead of night, in between at dusk and dawn.
func night_amount() -> float:
	var t := clock / DAY_LENGTH
	if t < 0.58:
		return 0.0
	if t < 0.68:
		return (t - 0.58) / 0.10
	if t < 0.92:
		return 1.0
	return 1.0 - (t - 0.92) / 0.08


func is_night() -> bool:
	return night_amount() > 0.6


func time_label() -> String:
	var t := clock / DAY_LENGTH
	if t < 0.25:
		return "Morning"
	if t < 0.5:
		return "Afternoon"
	if t < 0.62:
		return "Evening"
	if t < 0.92:
		return "Night"
	return "Dawn"


func _advance_clock(delta: float) -> void:
	var was_night := is_night()
	clock += delta
	if clock >= DAY_LENGTH:
		clock -= DAY_LENGTH
		day += 1
		howled_tonight = false
		world.regrow(day)
		player.sanity = minf(player.sanity + 10.0, 100.0)
		hud.toast("Dawn of day %d. You made it through the night." % day)
	if not was_night and is_night():
		hud.toast("Night falls. Stay close to a fire.")
	_update_lighting()


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.018
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	_update_lighting()


## Picks a colour for day (n = 0), dusk/dawn (0.5) or night (1).
static func _sky_blend(day_color: Color, dusk_color: Color, night_color: Color, n: float) -> Color:
	if n < 0.5:
		return day_color.lerp(dusk_color, n * 2.0)
	return dusk_color.lerp(night_color, (n - 0.5) * 2.0)


func _update_lighting() -> void:
	var n := night_amount()
	var t := clock / DAY_LENGTH
	# The sun rises in the east, crosses the sky and sets as night falls.
	# At night the same light becomes a dim, bluish moon.
	var day_frac := clampf(t / 0.66, 0.0, 1.0)
	var sun_pitch := -(10.0 + sin(day_frac * PI) * 55.0)
	var sun_yaw := lerpf(-75.0, 75.0, day_frac)
	var moon := Vector3(-50.0, 30.0, 0.0)
	var angles := Vector3(sun_pitch, sun_yaw, 0.0).lerp(moon, clampf((n - 0.5) * 2.0, 0.0, 1.0))
	sun.rotation_degrees = angles
	sun.light_color = _sky_blend(Color(1.0, 0.96, 0.88), Color(1.0, 0.6, 0.35), Color(0.55, 0.65, 1.0), n)
	sun.light_energy = lerpf(1.25, 0.1, n)

	var sky := _sky_blend(Color(0.58, 0.77, 0.94), Color(0.93, 0.56, 0.38), Color(0.02, 0.03, 0.07), n)
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = _sky_blend(Color(0.62, 0.66, 0.75), Color(0.6, 0.45, 0.42), Color(0.05, 0.06, 0.12), n)
	env.ambient_light_energy = 1.0


func _update_camera(delta: float) -> void:
	# Third-person camera behind and above the survivor. Mouse wheel zooms.
	var target := player.position + Vector3(0, 0.7, 0)
	var desired := target + Vector3(0, 9.0, 7.5) * zoom
	var weight := 1.0 if delta >= 1.0 else 1.0 - exp(-delta * 6.0)
	camera.position = camera.position.lerp(desired, weight)
	camera.look_at(target)


# ---------- Survival ----------

func _tick_survival(delta: float) -> void:
	var near_fire := _near_lit_fire(player.pos)
	var has_torch := player.torch_time > 0.0
	if has_torch:
		player.torch_time = maxf(player.torch_time - delta, 0.0)
		if player.torch_time <= 0.0:
			hud.toast("Your torch gutters out.")
	var n := night_amount()

	player.hunger = maxf(player.hunger - 0.22 * delta, 0.0)

	if near_fire:
		player.warmth = minf(player.warmth + 4.0 * delta, 100.0)
	else:
		var loss := lerpf(-0.6, 1.1, n)  # warm up by day, freeze by night
		if has_torch and loss > 0.0:
			loss *= 0.4
		player.warmth = clampf(player.warmth - loss * delta, 0.0, 100.0)

	if near_fire or has_torch or n < 0.5:
		player.sanity = minf(player.sanity + 0.05 * delta, 100.0)
	else:
		player.sanity = maxf(player.sanity - 0.35 * delta, 0.0)

	if player.hunger <= 0.0:
		_hurt(1.0 * delta, "starvation")
	if player.warmth <= 0.0:
		_hurt(1.5 * delta, "the cold")
	if player.sanity <= 0.0:
		_hurt(0.6 * delta, "madness")
	if player.hunger > 50.0 and player.warmth > 30.0 and player.sanity > 20.0:
		player.health = minf(player.health + 0.4 * delta, 100.0)


func _hurt(amount: float, cause: String) -> void:
	player.health = maxf(player.health - amount, 0.0)
	last_damage = cause
	if amount >= 5.0:
		player.hurt_flash = 0.25
		hud.flash()


func _near_lit_fire(pos: Vector2) -> bool:
	for fire in campfires:
		if fire.is_lit() and pos.distance_to(fire.pos) < fire.radius:
			return true
	return false


func _tick_wolves(delta: float) -> void:
	var night := is_night()
	if night:
		wolf_spawn_timer -= delta
		if wolf_spawn_timer <= 0.0:
			wolf_spawn_timer = rng.randf_range(9.0, 16.0)
			if wolves.size() < mini(1 + day, 6):
				var pos := world.random_walkable_near(player.pos, 300.0, 420.0, rng)
				if pos != Vector2.INF:
					var wolf: Wolf = Wolf.new()
					wolf.world = world
					wolf.pos = pos
					entities.add_child(wolf)
					wolves.append(wolf)
					if not howled_tonight:
						howled_tonight = true
						hud.toast("A howl rolls across the island…")
	for wolf in wolves.duplicate():
		if wolf.tick(delta, player.pos, campfires, night):
			_hurt(Wolf.BITE_DAMAGE, "wolves")
		if not night and wolf.pos.distance_to(player.pos) > 450.0:
			wolves.erase(wolf)
			wolf.queue_free()


# ---------- Actions ----------

func _nearest(list: Array, pos: Vector2, radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist := radius
	for node in list:
		var dist := pos.distance_to(node.pos)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func _interact() -> void:
	if action_cooldown > 0.0:
		return
	action_cooldown = 0.3
	var pos := player.pos
	var trace := _nearest(traces, pos, 22.0)
	if trace != null:
		_use_trace(trace)
		return
	var fire := _nearest(campfires, pos, 26.0)
	if fire != null:
		_use_fire(fire)
		return
	var cell := world.find_prop_near(pos, INTERACT_RADIUS)
	if cell != World.NO_CELL:
		player.swing()
		var gained := world.harvest(cell, day)
		for item in gained:
			player.add_item(item, int(gained[item]))
			hud.toast("+%d %s" % [int(gained[item]), ITEM_NAMES[item]])


func _use_fire(fire: Campfire) -> void:
	var whose := " left by %s" % fire.owner_name if fire.owner_name != "" else ""
	if fire.is_lit():
		var raw := player.count("raw_meat")
		if raw > 0:
			player.add_item("raw_meat", -raw)
			player.add_item("cooked_meat", raw)
			hud.toast("You cook %d meat over the flames." % raw)
		elif player.count("wood") > 0:
			player.add_item("wood", -1)
			fire.add_fuel(60.0)
			hud.toast("You feed the fire. It will burn for about %d more seconds." % int(fire.fuel))
		else:
			hud.toast("The fire crackles. Bring wood to keep it going.")
	elif player.count("wood") >= 2:
		player.add_item("wood", -2)
		fire.add_fuel(90.0)
		hud.toast("You relight the cold fire pit%s." % whose)
	else:
		hud.toast("A cold fire pit%s. 2 wood would bring it back to life." % whose)


func _use_trace(t: Trace) -> void:
	match t.kind:
		"note":
			var first := not t.was_read
			t.mark_read()
			var body := "\"%s\"" % t.message()
			if first:
				player.sanity = minf(player.sanity + 15.0, 100.0)
				body += "\n\nKnowing you're not alone steadies you. (+15 sanity)"
			hud.open_dialog("A note from %s" % t.author(), body, PackedStringArray(["Close"]), Callable())
		"grave":
			var body := "Here lies %s.\nSurvived %d day%s on this island." % [t.author(), t.days(), "" if t.days() == 1 else "s"]
			if t.message() != "":
				body += "\n\n\"%s\"" % t.message()
			if not t.was_read:
				t.mark_read()
				player.sanity = minf(player.sanity + 5.0, 100.0)
				body += "\n\nYou pay your respects. (+5 sanity)"
			hud.open_dialog("A grave", body, PackedStringArray(["Close"]), Callable())
		"stash":
			if t.is_own(api.player_id):
				hud.toast("Your own stash. Leave it for someone who needs it.")
				return
			var body := "%s left supplies here:\n%s" % [t.author(), _items_text(t.items())]
			hud.open_dialog("A stash", body, PackedStringArray(["Take it", "Leave it"]), _on_stash_choice.bind(t))


func _on_stash_choice(choice: int, _text: String, t: Trace) -> void:
	if choice != 0 or not is_instance_valid(t):
		return
	api.take_stash(t.trace_id(), _on_stash_taken.bind(t))


func _on_stash_taken(ok: bool, data: Variant, t: Trace) -> void:
	if not is_instance_valid(t):
		return
	if ok:
		var items: Variant = data.get("items", {})
		if typeof(items) == TYPE_DICTIONARY:
			for item in items:
				if ITEM_NAMES.has(item):
					player.add_item(item, clampi(int(items[item]), 0, 50))
			hud.toast("You take the stash: %s. Thank you, %s." % [_items_text(items), t.author()])
		_remove_trace(t)
	elif str(data.get("error", "")) == "already_taken" or int(data.get("status", 0)) == 404:
		hud.toast("Someone got here first. The stash is empty.")
		_remove_trace(t)
	else:
		hud.toast("The stash won't open right now (%s)." % str(data.get("error", "error")))


func _remove_trace(t: Trace) -> void:
	traces.erase(t)
	t.queue_free()


func _attack() -> void:
	if attack_cooldown > 0.0:
		return
	attack_cooldown = 0.45
	player.swing()
	var damage := 2 if player.has_spear else 1
	var reach := 34.0 if player.has_spear else 24.0
	for wolf in wolves.duplicate():
		if wolf.pos.distance_to(player.pos) <= reach:
			wolf.hurt(damage, player.pos)
			if wolf.hp <= 0:
				wolves.erase(wolf)
				wolf.queue_free()
				player.add_item("raw_meat", 2)
				hud.toast("The wolf falls. +2 raw meat")


func _eat() -> void:
	if player.count("cooked_meat") > 0:
		player.add_item("cooked_meat", -1)
		player.hunger = minf(player.hunger + 35.0, 100.0)
		player.sanity = minf(player.sanity + 3.0, 100.0)
		hud.toast("You eat cooked meat. Warm and filling.")
	elif player.count("berries") > 0:
		player.add_item("berries", -1)
		player.hunger = minf(player.hunger + 8.0, 100.0)
		hud.toast("You eat a handful of berries.")
	elif player.count("raw_meat") > 0:
		player.add_item("raw_meat", -1)
		player.hunger = minf(player.hunger + 12.0, 100.0)
		player.sanity = maxf(player.sanity - 8.0, 0.0)
		_hurt(3.0, "bad meat")
		hud.toast("You choke down raw meat. Your stomach turns.")
	else:
		hud.toast("You have nothing to eat. Look for berry bushes.")


func _craft(what: String) -> void:
	var cost: Dictionary = RECIPES[what]
	if not player.can_afford(cost):
		hud.toast("A %s needs %s." % [what, _items_text(cost)])
		return
	match what:
		"campfire":
			if _nearest(campfires, player.pos, 40.0) != null:
				hud.toast("There's already a fire here.")
				return
			var pos := player.pos + player.facing * 14.0
			if not world.is_walkable(pos):
				pos = player.pos
			player.pay(cost)
			var fire: Campfire = Campfire.new()
			fire.world = world
			fire.pos = pos
			entities.add_child(fire)
			campfires.append(fire)
			hud.toast("You build a campfire.")
			if api.can_post():
				api.post_trace(seed_value, "camp", pos, "", {}, Callable())
		"torch":
			if player.torch_time > 0.0:
				hud.toast("You're already carrying a lit torch.")
				return
			player.pay(cost)
			player.torch_time = 90.0
			hud.toast("You light a torch. It will last a while.")
		"spear":
			if player.has_spear:
				hud.toast("You already have a spear.")
				return
			player.pay(cost)
			player.has_spear = true
			hud.toast("You carve a spear. Wolves beware.")


func _write_note() -> void:
	if not api.can_post():
		hud.toast("Notes need a connection to the island server.")
		return
	hud.open_dialog("Leave a note",
		"Write something for whoever finds this spot. Everyone on today's island can read it.",
		PackedStringArray(["Leave note", "Cancel"]), _on_note_written,
		"A warning, a tip, a last word…", 140)


func _on_note_written(choice: int, text: String) -> void:
	if choice != 0 or text == "":
		return
	var pos := player.pos
	api.post_trace(seed_value, "note", pos, text, {}, _on_note_posted.bind(text, pos))


func _on_note_posted(ok: bool, data: Variant, text: String, pos: Vector2) -> void:
	if not ok:
		hud.toast("The note blew away (%s)." % str(data.get("error", "error")))
		return
	_spawn_trace({
		"id": str(data.get("id", "")), "kind": "note", "x": pos.x, "y": pos.y, "text": text,
		"player_name": api.player_name, "player_id": api.player_id,
	})
	var t: Trace = traces.back()
	t.mark_read()
	hud.toast("You leave the note. Someone may find it.")


func _leave_stash() -> void:
	if not api.can_post():
		hud.toast("Stashes need a connection to the island server.")
		return
	var items := {}
	for item in ["wood", "stone", "berries", "cooked_meat"]:
		var half := floori(player.count(item) / 2.0)
		if half > 0:
			items[item] = half
	if items.is_empty():
		hud.toast("You have nothing to spare.")
		return
	hud.open_dialog("Leave a stash?",
		"You'll leave half your supplies here: %s.\nThe first survivor who finds it can take it." % _items_text(items),
		PackedStringArray(["Leave it", "Cancel"]), _on_stash_confirm.bind(items))


func _on_stash_confirm(choice: int, _text: String, items: Dictionary) -> void:
	if choice != 0 or not player.can_afford(items):
		return
	player.pay(items)
	var pos := player.pos
	api.post_trace(seed_value, "stash", pos, "", items, _on_stash_posted.bind(items, pos))


func _on_stash_posted(ok: bool, data: Variant, items: Dictionary, pos: Vector2) -> void:
	if not ok:
		for item in items:
			player.add_item(item, int(items[item]))
		hud.toast("Couldn't leave the stash (%s). Your supplies are back in your pack." % str(data.get("error", "error")))
		return
	_spawn_trace({
		"id": str(data.get("id", "")), "kind": "stash", "x": pos.x, "y": pos.y, "items": items,
		"player_name": api.player_name, "player_id": api.player_id,
	})
	hud.toast("You leave a stash for a stranger: %s." % _items_text(items))


func _items_text(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in items:
		parts.append("%d %s" % [int(items[item]), ITEM_NAMES.get(item, str(item))])
	return ", ".join(parts)


# ---------- HUD ----------

func _update_hint() -> void:
	var pos := player.pos
	var hint := ""
	var trace := _nearest(traces, pos, 22.0)
	var fire := _nearest(campfires, pos, 26.0)
	var cell := world.find_prop_near(pos, INTERACT_RADIUS)
	if trace != null:
		var t: Trace = trace
		hint = {"note": "E: read the note", "grave": "E: read the grave", "stash": "E: open the stash"}.get(t.kind, "")
	elif fire != null:
		var f: Campfire = fire
		if not f.is_lit():
			hint = "E: relight fire (2 wood)"
		elif player.count("raw_meat") > 0:
			hint = "E: cook meat"
		elif player.count("wood") > 0:
			hint = "E: add wood to the fire"
	elif cell != World.NO_CELL:
		hint = {"tree": "E: chop tree", "rock": "E: break rock", "bush": "E: pick berries"}.get(world.prop_type(cell), "")
	elif is_night() and not _near_lit_fire(pos) and player.torch_time <= 0.0:
		hint = "It's dark and cold. Build a campfire (1) or light a torch (2)."
	hud.set_hint(hint)


func _refresh_hud() -> void:
	var inv := "Wood %d   Stone %d   Berries %d   Raw meat %d   Cooked %d" % [
		player.count("wood"), player.count("stone"), player.count("berries"),
		player.count("raw_meat"), player.count("cooked_meat"),
	]
	if player.has_spear:
		inv += "\nSpear"
	if player.torch_time > 0.0:
		inv += ("   " if player.has_spear else "\n") + "Torch %ds" % int(player.torch_time)
	hud.update_stats([player.health, player.hunger, player.warmth, player.sanity], day, time_label(), inv)


# ---------- Death ----------

func _die() -> void:
	alive = false
	hud.set_hint("")
	var days := day - 1
	api.record_local_best(seed_value, days)
	hud.open_dialog("You died on day %d" % day,
		"Taken by %s. You survived %d full day%s.\n\nYour grave will stay on this island for everyone who plays today. Leave an epitaph:" % [last_damage, days, "" if days == 1 else "s"],
		PackedStringArray(["Rest"]), _on_epitaph, "Here lies…", 100, false)


func _on_epitaph(_choice: int, text: String) -> void:
	var days := day - 1
	if api.can_post() and run_id != "":
		api.end_run(run_id, days, player.pos, text, last_damage, _on_run_ended)
	else:
		_show_leaderboard(false, {})


func _on_run_ended(_ok: bool, _data: Variant) -> void:
	api.fetch_leaderboard(seed_value, _show_leaderboard)


func _show_leaderboard(ok: bool, data: Variant) -> void:
	var lines := PackedStringArray()
	var entries: Variant = data.get("entries", []) if ok else []
	if typeof(entries) == TYPE_ARRAY and not entries.is_empty():
		var rank := 1
		for e in entries:
			lines.append("%d.  %s  —  %d day%s" % [rank, str(e.get("name", "?")), int(e.get("days", 0)), "" if int(e.get("days", 0)) == 1 else "s"])
			rank += 1
	else:
		lines.append("No one else is listed yet." if api.is_online() else "Offline: you were alone on this island.")
	lines.append("")
	lines.append("Your best here: %d day%s." % [api.local_best(seed_value), "" if api.local_best(seed_value) == 1 else "s"])
	lines.append("A new island washes up every day at midnight UTC.")
	hud.open_dialog("Longest survivors on %s" % island_name, "\n".join(lines), PackedStringArray(["Wake again"]), _restart, "", 0, false)


func _restart(_choice: int, _text: String) -> void:
	get_tree().reload_current_scene()
