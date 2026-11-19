## Last Light: game loop, rules and the link between the island and the server.
extends Node3D

const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Campfire = preload("res://scripts/campfire.gd")
const Wolf = preload("res://scripts/wolf.gd")
const Trace = preload("res://scripts/trace.gd")
const Hud = preload("res://scripts/hud.gd")
const Api = preload("res://scripts/api.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Structure = preload("res://scripts/structure.gd")
const Soldier = preload("res://scripts/soldier.gd")

const RECRUIT_COST := {"wood": 3, "stone": 2, "berries": 5}
const BUILD_RANGE := 8  # tiles from the player
const MAX_TORCH_POSTS := 24  # lights are expensive in the browser renderer

const ISLAND_ID := 1  # the permanent island, as the server knows it
const WORLD_SEED := 20261119  # the island's shape never changes
const SAVE_INTERVAL := 6.0  # seconds between autosaves
const CLOUD_INTERVAL := 15.0  # seconds between uploads of the save to the server

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
var life_start_day := 1  # the day this survivor woke up
var home := Vector2.INF  # the last campfire you built: where you wake after dying
var _resumed := false
var _save_timer := 0.0
var _read_ids: Dictionary = {}  # notes and graves already read
var _auth_retried := false
var _js_save_callback: Variant = null
var _last_save: Dictionary = {}
var _cloud_timer := 0.0
var _cloud_dirty := false
var _cloud_busy := false
var _login_name := ""
var _new_username := ""
var buildings: Dictionary = {}  # Vector2i cell -> Structure node
var soldiers: Array = []
var army_mode := "follow"
var build_mode := false
var build_index := 0
var _ghost: Node3D
var _ghost_key := ""


func _ready() -> void:
	_setup_input()
	rng.randomize()
	seed_value = ISLAND_ID
	var world_seed := seed_override() if seed_override() > 0 else WORLD_SEED
	island_name = make_island_name(world_seed)

	world = World.new()
	add_child(world)
	world.generate(world_seed)

	entities = Node3D.new()
	add_child(entities)

	player = Player.new()
	player.world = world
	player.pos = world.cell_center(world.spawn_cell)
	_resumed = _apply_save(SaveGame.read())
	add_child(player)
	world.update_view(player.pos, true)

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

	hud.set_island(island_name, "a permanent island")
	_hook_page_unload()
	_update_lighting()
	_refresh_hud()

	if api.player_name == "":
		_show_welcome()
	else:
		_begin_run()


func _show_welcome() -> void:
	var buttons := PackedStringArray(["Begin"])
	if api.is_online():
		buttons.append("I have an account")
	hud.open_dialog("Last Light",
		"You wake on the cold sand of %s. Others have washed up here before you, and some never left.\n\nWhat should the island remember you as?" % island_name,
		buttons, _on_name_chosen, "Your name", 20, false)


# ---------- Setup ----------

## Run with `-- --seed=12345` to explore a different island shape (offline only makes sense).
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
	_bind("menu", [KEY_ESCAPE])
	_bind("build", [KEY_B])
	_bind("demolish", [KEY_X])
	_bind("army", [KEY_T])
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


func _on_name_chosen(choice: int, text: String) -> void:
	if choice == 1:
		_start_login(true)
		return
	api.set_player_name(text if text != "" else "Wanderer")
	_begin_run()


func _begin_run() -> void:
	started = true
	if _resumed:
		hud.toast("Welcome back. Day %d on %s." % [day, island_name])
	else:
		hud.toast("Day %d on %s. Gather wood and stone before nightfall." % [day, island_name])
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
	if run_id == "":
		api.start_run(seed_value, _on_run_started)
	api.fetch_account(_on_account_checked)
	api.fetch_save(_on_cloud_checked)
	api.fetch_traces(seed_value, _on_traces_loaded)


func _on_run_started(ok: bool, data: Variant) -> void:
	if ok:
		run_id = str(data.get("run_id", ""))
		save_game()
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
		if _nearest(campfires, pos, 20.0) != null:
			return  # one of your own fires, already loaded from your save
		var fire: Campfire = Campfire.new()
		fire.fuel = 0.0
		fire.owner_name = str(d.get("player_name", "someone"))
		fire.world = world
		fire.pos = pos
		entities.add_child(fire)
		campfires.append(fire)
	elif kind == "grave" or kind == "note" or kind == "stash" or kind == "bag":
		var t: Trace = Trace.new()
		t.world = world
		t.setup(d)
		t.was_read = _read_ids.has(t.trace_id())
		entities.add_child(t)
		traces.append(t)


# ---------- Main loop ----------

func _process(delta: float) -> void:
	world.update_view(player.pos)
	player.tick_visuals(delta)
	if started and alive:
		_save_timer += delta
		if _save_timer >= SAVE_INTERVAL:
			save_game()
	_cloud_timer += delta
	if _cloud_dirty and _cloud_timer >= CLOUD_INTERVAL:
		_upload_save()
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
		_tick_army(delta)
		_update_hint()
		_update_build_preview()
		if player.health <= 0.0:
			_die()
	_update_camera(delta)
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.1, 0.55, 2.5)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.1, 0.55, 2.5)
	if not started or not alive or hud.is_modal():
		return
	if build_mode and _build_input(event):
		return
	if event.is_action_pressed("build"):
		_set_build_mode(true)
	elif event.is_action_pressed("army"):
		_toggle_army_mode()
	elif event.is_action_pressed("interact", true):
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
	elif event.is_action_pressed("menu"):
		_open_menu()


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
		save_game(false, true)
	if not was_night and is_night():
		hud.toast("Night falls. Stay close to a fire.")
	_update_lighting()


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# No fog: in the Compatibility renderer even light fog washed out the whole scene.
	env.fog_enabled = false
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
	sun.light_color = _sky_blend(Color(1.0, 0.96, 0.88), Color(1.0, 0.72, 0.5), Color(0.55, 0.65, 1.0), n)
	sun.light_energy = lerpf(1.0, 0.1, n)

	var sky := _sky_blend(Color(0.58, 0.77, 0.94), Color(0.93, 0.56, 0.38), Color(0.02, 0.03, 0.07), n)
	env.background_color = sky
	env.ambient_light_color = _sky_blend(Color(0.62, 0.68, 0.8), Color(0.55, 0.47, 0.5), Color(0.05, 0.06, 0.12), n)
	env.ambient_light_energy = lerpf(0.55, 1.0, n)


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

	if near_fire or has_torch or n < 0.5 or _nearest(_torch_posts(), player.pos, Structure.TORCH_RADIUS) != null:
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


## Fires and torch posts: wolves keep away from both.
func _lights() -> Array:
	var lights := campfires.duplicate()
	for b in buildings.values():
		if b.kind == "torch_post":
			lights.append(b)
	return lights


func _tick_wolves(delta: float) -> void:
	var night := is_night()
	if night:
		wolf_spawn_timer -= delta
		if wolf_spawn_timer <= 0.0:
			wolf_spawn_timer = rng.randf_range(9.0, 16.0)
			# Bigger armies draw bigger packs.
			if wolves.size() < mini(1 + day, 6) + soldiers.size() / 10:
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
	var lights := _lights()
	for wolf in wolves.duplicate():
		# Each wolf goes for whoever is closest: you or one of your soldiers.
		var target_pos := player.pos
		var victim: Soldier = null
		var best: float = wolf.pos.distance_to(player.pos)
		for soldier in soldiers:
			if not soldier.dead:
				var d: float = wolf.pos.distance_to(soldier.pos)
				if d < best:
					best = d
					target_pos = soldier.pos
					victim = soldier
		if wolf.tick(delta, target_pos, lights, night):
			if victim == null:
				_hurt(Wolf.BITE_DAMAGE, "wolves")
			elif victim.hurt(Wolf.BITE_DAMAGE):
				_on_soldier_fallen(victim)
		# A wolf pressed against your walls gnaws through them.
		if night and buildings.has(wolf.blocked_cell):
			var b: Structure = buildings[wolf.blocked_cell]
			var rate := 4.0 if b.kind == "stone_wall" else 12.0
			if b.damage(rate * delta):
				hud.toast("Wolves broke through your %s!" % b.display_name().to_lower())
				_remove_structure(b.cell)
		if not night and wolf.pos.distance_to(player.pos) > 450.0:
			wolves.erase(wolf)
			wolf.queue_free()


func _kill_wolf(wolf: Wolf, by_army: bool) -> void:
	wolves.erase(wolf)
	var fall_time: float = wolf.die()
	get_tree().create_timer(fall_time + 1.0).timeout.connect(wolf.queue_free)
	player.add_item("raw_meat", 2)
	hud.toast("Your soldiers bring down a wolf. +2 raw meat" if by_army else "The wolf falls. +2 raw meat")


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
	var building := _nearest(buildings.values(), pos, 24.0)
	if building != null:
		_use_building(building)
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
			_read_ids[t.trace_id()] = true
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
				_read_ids[t.trace_id()] = true
				player.sanity = minf(player.sanity + 5.0, 100.0)
				body += "\n\nYou pay your respects. (+5 sanity)"
			hud.open_dialog("A grave", body, PackedStringArray(["Close"]), Callable())
		"bag":
			var items := t.items()
			for item in items:
				if item == "spear":
					player.has_spear = true
				elif ITEM_NAMES.has(item):
					player.add_item(item, clampi(int(items[item]), 0, 999))
			hud.toast("You recover your belongings: %s." % _items_text(items))
			_remove_trace(t)
			save_game()
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
				_kill_wolf(wolf, false)


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
			hud.toast("You build a campfire. If you fall, you'll wake here.")
			home = pos
			save_game()
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
	var building := _nearest(buildings.values(), pos, 24.0)
	if build_mode:
		return  # the build bar uses the hint line
	if trace != null:
		var t: Trace = trace
		hint = {"note": "E: read the note", "grave": "E: read the grave", "stash": "E: open the stash",
			"bag": "E: pick up your belongings"}.get(t.kind, "")
	elif fire != null:
		var f: Campfire = fire
		if not f.is_lit():
			hint = "E: relight fire (2 wood)"
		elif player.count("raw_meat") > 0:
			hint = "E: cook meat"
		elif player.count("wood") > 0:
			hint = "E: add wood to the fire"
	elif building != null:
		hint = _building_hint(building)
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
	if not soldiers.is_empty() or _count("barracks") > 0:
		inv += "\nArmy %d / %d  ·  %s (T)" % [soldiers.size(), _army_capacity(),
			"following" if army_mode == "follow" else "guarding"]
	hud.update_stats([player.health, player.hunger, player.warmth, player.sanity], day, time_label(), inv)


# ---------- Building ----------

func _count(kind: String) -> int:
	var n := 0
	for b in buildings.values():
		if b.kind == kind:
			n += 1
	return n


func _torch_posts() -> Array:
	var posts := []
	for b in buildings.values():
		if b.kind == "torch_post":
			posts.append(b)
	return posts


func _add_structure(kind: String, cell: Vector2i, hp: float = -1.0, items: Dictionary = {}) -> Structure:
	var b: Structure = Structure.new()
	b.setup(world, kind, cell)
	if hp > 0.0:
		b.hp = minf(hp, Structure.max_hp(kind))
	b.items = items
	entities.add_child(b)
	buildings[cell] = b
	world.add_structure(cell, kind)
	return b


func _remove_structure(cell: Vector2i) -> void:
	if buildings.has(cell):
		buildings[cell].queue_free()
		buildings.erase(cell)
	world.remove_structure(cell)


func _set_build_mode(on: bool) -> void:
	build_mode = on
	if not on and _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_key = ""
	if on:
		hud.toast("Build mode: aim with the mouse, click or E to build, X to demolish, B to finish.")


## Handles keys and clicks in build mode. Returns true if the event was used.
func _build_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var n: int = key.physical_keycode - KEY_1
		if n >= 0 and n < Structure.ORDER.size():
			build_index = n
			return true
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_try_build(Structure.ORDER[build_index], _build_target())
		return true
	if event.is_action_pressed("interact"):
		_try_build(Structure.ORDER[build_index], _build_target())
		return true
	if event.is_action_pressed("demolish"):
		_demolish(_build_target())
		return true
	if event.is_action_pressed("build") or event.is_action_pressed("menu"):
		_set_build_mode(false)
		return true
	return false


## The tile under the mouse, if it's close enough; otherwise the tile in front of you.
func _build_target() -> Vector2i:
	var here := world.cell_of(player.pos)
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) > 0.001:
		var t := (player.position.y - origin.y) / dir.y
		if t > 0.0:
			var hit := origin + dir * t
			var cell := world.cell_of(Vector2(hit.x, hit.z) * World.TILE)
			if cell != here and maxi(absi(cell.x - here.x), absi(cell.y - here.y)) <= BUILD_RANGE:
				return cell
	return world.cell_of(player.pos + player.facing * World.TILE * 1.2)


func _build_problem(kind: String, cell: Vector2i) -> String:
	if cell == world.cell_of(player.pos):
		return "You're standing there."
	if not world.can_build(cell):
		return "You can't build there."
	if kind == "torch_post" and _count("torch_post") >= MAX_TORCH_POSTS:
		return "You have the most torch posts allowed (%d)." % MAX_TORCH_POSTS
	if not player.can_afford(Structure.info(kind)["cost"]):
		return "Needs %s." % _items_text(Structure.info(kind)["cost"])
	return ""


func _try_build(kind: String, cell: Vector2i) -> bool:
	var problem := _build_problem(kind, cell)
	if problem != "":
		hud.toast(problem)
		return false
	player.pay(Structure.info(kind)["cost"])
	_add_structure(kind, cell)
	if kind == "tent":
		home = world.cell_center(cell)
		hud.toast("Tent pitched. You'll wake here if you fall.")
	_save_timer = SAVE_INTERVAL - 1.0  # save within a second
	return true


func _demolish(cell: Vector2i) -> void:
	if not buildings.has(cell):
		hud.toast("There's nothing you built there.")
		return
	var b: Structure = buildings[cell]
	var cost: Dictionary = Structure.info(b.kind)["cost"]
	for item in cost:
		player.add_item(item, int(cost[item]) / 2)
	for item in b.items:
		player.add_item(item, int(b.items[item]))
	hud.toast("You take down the %s and get some materials back." % b.display_name().to_lower())
	_remove_structure(cell)
	_save_timer = SAVE_INTERVAL - 1.0


func _update_build_preview() -> void:
	if not build_mode:
		return
	var kind: String = Structure.ORDER[build_index]
	var cell := _build_target()
	var problem := _build_problem(kind, cell)
	var key := "%s:%s" % [kind, problem == ""]
	if key != _ghost_key:
		if _ghost:
			_ghost.queue_free()
		var g: Structure = Structure.new()
		g.setup(world, kind, cell)
		add_child(g)
		g.make_ghost(problem == "")
		_ghost = g
		_ghost_key = key
	_ghost.position = world.to_3d(world.cell_center(cell))
	var names := PackedStringArray()
	for i in Structure.ORDER.size():
		var n: String = Structure.info(Structure.ORDER[i])["name"]
		names.append(("[%d %s]" if i == build_index else "%d %s") % [i + 1, n])
	var info: Dictionary = Structure.info(kind)
	hud.set_hint("%s\n%s: %s. %s  %s" % [
		"  ".join(names), info["name"], _items_text(info["cost"]), info["about"],
		problem if problem != "" else "Click or E to build · X demolish · B done"])


func _building_hint(b: Structure) -> String:
	var damaged: bool = b.hp < Structure.max_hp(b.kind) - 1.0
	match b.kind:
		"chest":
			return "E: open the chest"
		"tent":
			return "E: sleep until morning" if is_night() else "E: rest at your tent"
		"barracks":
			return "E: recruit soldiers (%d / %d)" % [soldiers.size(), _army_capacity()]
	if damaged:
		return "E: repair the %s (%d%%)" % [b.display_name().to_lower(), int(100.0 * b.hp / Structure.max_hp(b.kind))]
	return ""


func _use_building(b: Structure) -> void:
	match b.kind:
		"chest":
			_open_chest(b)
			return
		"tent":
			home = b.pos
			if is_night():
				hud.open_dialog("Sleep until morning?",
					"You crawl into your tent. Your soldiers keep watch.",
					PackedStringArray(["Sleep", "Stay up"]), _on_sleep_choice)
			else:
				hud.toast("Your tent. You'll wake here if you fall. Come back at night to sleep.")
			return
		"barracks":
			_open_barracks()
			return
	var max_hp := Structure.max_hp(b.kind)
	if b.hp >= max_hp - 1.0:
		hud.toast("The %s is in good shape." % b.display_name().to_lower())
		return
	var material := "stone" if b.kind == "stone_wall" else "wood"
	if player.count(material) < 1:
		hud.toast("Repairs need 1 %s." % material)
		return
	player.add_item(material, -1)
	b.repair(max_hp * 0.4)
	hud.toast("You patch up the %s." % b.display_name().to_lower())


func _on_sleep_choice(choice: int, _text: String) -> void:
	if choice != 0:
		return
	clock = DAY_LENGTH - 0.01  # dawn arrives on the next frame
	player.warmth = 100.0
	player.sanity = minf(player.sanity + 20.0, 100.0)
	player.hunger = maxf(player.hunger - 15.0, 0.0)
	for wolf in wolves:
		wolf.queue_free()
	wolves.clear()
	hud.toast("You sleep through the night.")


func _open_chest(b: Structure) -> void:
	var stored: String = _items_text(b.items) if not b.items.is_empty() else "nothing"
	hud.open_dialog("Storage chest", "In the chest: %s." % stored,
		PackedStringArray(["Store everything", "Take everything", "Close"]), _on_chest_choice.bind(b))


func _on_chest_choice(choice: int, _text: String, b: Structure) -> void:
	if not is_instance_valid(b):
		return
	if choice == 0:
		_chest_store(b)
		hud.toast("You put everything in the chest.")
	elif choice == 1:
		_chest_take(b)
		hud.toast("You take everything from the chest.")
	_save_timer = SAVE_INTERVAL - 1.0


func _chest_store(b: Structure) -> void:
	for item in player.inventory:
		var n := player.count(item)
		if n > 0:
			b.items[item] = int(b.items.get(item, 0)) + n
			player.inventory[item] = 0


func _chest_take(b: Structure) -> void:
	for item in b.items:
		if ITEM_NAMES.has(item):
			player.add_item(item, int(b.items[item]))
	b.items = {}


# ---------- Army ----------

func _army_capacity() -> int:
	return mini(Soldier.MAX_ARMY, Soldier.PER_BARRACKS * _count("barracks"))


func _open_barracks() -> void:
	hud.open_dialog("Barracks",
		"Your army: %d of %d (each barracks houses %d, up to %d in all).\n\nRecruit a soldier for %s." % [
			soldiers.size(), _army_capacity(), Soldier.PER_BARRACKS, Soldier.MAX_ARMY, _items_text(RECRUIT_COST)],
		PackedStringArray(["Recruit 1", "Recruit 5", "Recruit 10", "Close"]), _on_barracks_choice)


func _on_barracks_choice(choice: int, _text: String) -> void:
	var wanted: int = [1, 5, 10, 0][clampi(choice, 0, 3)] if choice >= 0 else 0
	if wanted > 0:
		var got := _recruit(wanted)
		if got > 0:
			hud.toast("%d soldier%s joined your army." % [got, "" if got == 1 else "s"])


## Recruits up to `n` soldiers. Returns how many joined.
func _recruit(n: int) -> int:
	var barracks: Structure = _nearest(buildings.values().filter(func(b): return b.kind == "barracks"), player.pos, 99999.0)
	if barracks == null:
		hud.toast("Build a barracks first.")
		return 0
	var joined := 0
	for i in n:
		if soldiers.size() >= _army_capacity():
			hud.toast("No room: build another barracks (each houses %d)." % Soldier.PER_BARRACKS)
			break
		if not player.can_afford(RECRUIT_COST):
			hud.toast("Each soldier needs %s." % _items_text(RECRUIT_COST))
			break
		player.pay(RECRUIT_COST)
		var spot := world.random_walkable_near(barracks.pos, 16.0, 40.0, rng)
		_spawn_soldier(spot if spot != Vector2.INF else player.pos, Soldier.MAX_HP, army_mode, player.pos)
		joined += 1
	if joined > 0:
		_save_timer = SAVE_INTERVAL - 1.0
	return joined


func _spawn_soldier(pos: Vector2, hp: float, mode: String, guard_point: Vector2) -> Soldier:
	var s: Soldier = Soldier.new()
	s.world = world
	s.pos = pos
	s.hp = clampf(hp, 1.0, Soldier.MAX_HP)
	s.mode = "guard" if mode == "guard" else "follow"
	s.guard_point = guard_point
	s.slot = soldiers.size()
	entities.add_child(s)
	soldiers.append(s)
	return s


func _toggle_army_mode() -> void:
	if soldiers.is_empty():
		hud.toast("You have no soldiers yet. Build a barracks (B, then 7) and recruit some.")
		return
	army_mode = "guard" if army_mode == "follow" else "follow"
	for s in soldiers:
		s.mode = army_mode
		s.guard_point = player.pos
	hud.toast("Your army guards this spot." if army_mode == "guard" else "Your army follows you.")
	_save_timer = SAVE_INTERVAL - 1.0


func _tick_army(delta: float) -> void:
	for s in soldiers:
		var killed: Wolf = s.tick(delta, player.pos, player.facing, wolves)
		if killed != null and wolves.has(killed):
			_kill_wolf(killed, true)
		s.set_shown(s.pos.distance_to(player.pos) < Soldier.DRAW_DISTANCE)


func _on_soldier_fallen(s: Soldier) -> void:
	soldiers.erase(s)
	for i in soldiers.size():
		soldiers[i].slot = i
	get_tree().create_timer(3.0).timeout.connect(s.queue_free)
	hud.toast("One of your soldiers has fallen.")


func _export_structures() -> Array:
	var out := []
	for b in buildings.values():
		out.append([b.cell.x, b.cell.y, b.kind, snappedf(b.hp, 0.1), b.items])
	return out


func _export_soldiers() -> Array:
	var out := []
	for s in soldiers:
		out.append([snappedf(s.pos.x, 0.1), snappedf(s.pos.y, 0.1), snappedf(s.hp, 0.1), s.mode,
			snappedf(s.guard_point.x, 0.1), snappedf(s.guard_point.y, 0.1)])
	return out


# ---------- Death ----------

func _die() -> void:
	alive = false
	player.die()
	hud.set_hint("")
	var days := day - life_start_day
	api.record_local_best(seed_value, days)
	# Save straight away: the survivor wakes at their last campfire, and what
	# they carried waits in a bag where they fell. Reloading now loses nothing.
	save_game(true, true)
	hud.open_dialog("You died on day %d" % day,
		"Taken by %s. This survivor lived %d full day%s.\n\nYour belongings wait in a bag where you fell, and you'll wake at your last campfire. Your grave stays on the island for everyone to find. Leave an epitaph:" % [last_damage, days, "" if days == 1 else "s"],
		PackedStringArray(["Rest"]), _on_epitaph, "Here lies…", 100, false)


func _on_epitaph(_choice: int, text: String) -> void:
	var days := day - life_start_day
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
		lines.append("No one else is listed yet." if api.is_online() else "Offline: no leaderboard without the island server.")
	lines.append("")
	lines.append("Your longest life here: %d day%s." % [api.local_best(seed_value), "" if api.local_best(seed_value) == 1 else "s"])
	hud.open_dialog("Longest survivors on %s" % island_name, "\n".join(lines), PackedStringArray(["Wake again"]), _restart, "", 0, false)


func _restart(_choice: int, _text: String) -> void:
	get_tree().reload_current_scene()


# ---------- Cloud saves and accounts ----------

## True if a save is a real game for this island (not empty or a "start over" marker).
func _save_fits(save: Variant) -> bool:
	return typeof(save) == TYPE_DICTIONARY and save.has("player") and not save.get("reset", false) \
		and int(save.get("version", 0)) == SaveGame.VERSION and int(save.get("world_seed", 0)) == world.seed_value


func _upload_save(force: bool = false, done: Callable = Callable()) -> void:
	if not api.can_post() or _last_save.is_empty() or (_cloud_busy and not force):
		if done.is_valid():
			done.call(false)
		return
	_cloud_busy = true
	_cloud_dirty = false
	_cloud_timer = 0.0
	api.upload_save(float(_last_save.get("saved_at", 0.0)), _last_save, _on_uploaded.bind(done))


func _on_uploaded(ok: bool, data: Variant, done: Callable) -> void:
	_cloud_busy = false
	if not ok:
		if str(data.get("error", "")) == "newer_save_exists":
			# This survivor was played more recently in another browser.
			api.fetch_save(_on_cloud_checked)
		else:
			_cloud_dirty = true  # try again later
	if done.is_valid():
		done.call(ok)


## At startup (and on conflicts): if the server's save is newer than this
## browser's, switch to it. Otherwise upload this browser's progress.
func _on_cloud_checked(ok: bool, data: Variant) -> void:
	if not ok:
		return
	var cloud: Variant = data.get("save", null)
	var local_at := float(_last_save.get("saved_at", SaveGame.read().get("saved_at", 0.0)))
	if _save_fits(cloud) and float(data.get("saved_at", 0.0)) > local_at + 0.5:
		started = false
		SaveGame.write(cloud)
		hud.open_dialog("Loading your game",
			"Your survivor was played more recently in another browser. Loading that progress from the island server.",
			PackedStringArray(["Continue"]), _reload_after, "", 0, false)
	elif started and alive:
		save_game(false, true)


func _on_account_checked(_ok: bool, _data: Variant) -> void:
	pass  # api.username is now up to date


func _open_account() -> void:
	if not api.is_online():
		hud.toast("Accounts need a connection to the island server.")
		return
	if api.has_account():
		hud.open_dialog("Account",
			"Logged in as %s.\n\nYour game is saved on the island server as you play, so you can continue in any browser or on any device by logging in." % api.username,
			PackedStringArray(["Close", "Log out"]), _on_account_menu_logged_in)
	else:
		hud.open_dialog("Account",
			"Your game is saved in this browser and backed up on the island server.\n\nCreate an account to log in from any browser or device and pick up where you left off.",
			PackedStringArray(["Create account", "Log in", "Close"]), _on_account_menu)


func _on_account_menu(choice: int, _text: String) -> void:
	if choice == 0:
		hud.open_dialog("Create account", "Choose a username: 3 to 20 letters, numbers, - or _.",
			PackedStringArray(["Next", "Cancel"]), _on_new_username, "Username", 20)
	elif choice == 1:
		hud.open_dialog("Log in to another account?",
			"Logging in replaces the game in this browser with that account's game.",
			PackedStringArray(["Log in", "Cancel"]), _on_confirm_switch_login)


func _on_new_username(choice: int, text: String) -> void:
	if choice != 0 or text == "":
		return
	_new_username = text
	hud.open_dialog("Create account", "Choose a password for %s: at least 8 characters." % text,
		PackedStringArray(["Create account", "Cancel"]), _on_new_password, "Password", 100, true, true)


func _on_new_password(choice: int, text: String) -> void:
	if choice != 0 or text == "":
		return
	if text.length() < 8:
		hud.open_dialog("Create account", "That password is too short. Use at least 8 characters.",
			PackedStringArray(["Try again", "Cancel"]), _on_retry_new_password)
		return
	hud.open_dialog("Create account", "Creating your account…", PackedStringArray(), Callable(), "", 0, false)
	api.create_account(_new_username, text, _on_account_created)


func _on_retry_new_password(choice: int, _text: String) -> void:
	if choice == 0:
		_on_new_username(0, _new_username)


func _on_account_created(ok: bool, data: Variant) -> void:
	if ok:
		save_game(false, true)
		hud.open_dialog("Account created",
			"You're logged in as %s. Your game is saved on the island server.\n\nOn another browser or device, choose \"I have an account\" (or Esc → Account → Log in) and use this username and password." % api.username,
			PackedStringArray(["Great"]), Callable())
		return
	var reason: String = {
		"username_taken": "That username is taken. Try another.",
		"bad_username": "Usernames are 3 to 20 letters, numbers, - or _.",
		"bad_password": "Passwords need 8 to 100 characters.",
		"already_has_account": "This survivor already has an account.",
		"network": "Couldn't reach the island server.",
	}.get(str(data.get("error", "")), "Something went wrong (%s)." % str(data.get("error", "error")))
	hud.open_dialog("Couldn't create the account", reason, PackedStringArray(["Try again", "Cancel"]), _on_create_retry)


func _on_create_retry(choice: int, _text: String) -> void:
	if choice == 0:
		_on_account_menu(0, "")


func _on_account_menu_logged_in(choice: int, _text: String) -> void:
	if choice == 1:
		hud.open_dialog("Log out?",
			"Your game stays safe on the island server. This browser forgets it until you log in again.",
			PackedStringArray(["Log out", "Cancel"]), _on_confirm_log_out)


func _on_confirm_log_out(choice: int, _text: String) -> void:
	if choice != 0:
		return
	save_game()
	hud.open_dialog("Logging out", "Saving your game to the island server…", PackedStringArray(), Callable(), "", 0, false)
	_upload_save(true, _on_logout_uploaded)


func _on_logout_uploaded(ok: bool) -> void:
	if not ok:
		hud.open_dialog("Couldn't save to the server",
			"Your latest progress isn't on the island server yet, so logging out now could lose it. Try again in a moment.",
			PackedStringArray(["OK"]), Callable())
		return
	started = false
	api.log_out()
	SaveGame.erase()
	get_tree().reload_current_scene()


func _on_confirm_switch_login(choice: int, _text: String) -> void:
	if choice == 0:
		_start_login(false)


func _start_login(from_welcome: bool) -> void:
	hud.open_dialog("Log in", "Your username:", PackedStringArray(["Next", "Back"]),
		_on_login_name.bind(from_welcome), "Username", 20, not from_welcome)


func _on_login_name(choice: int, text: String, from_welcome: bool) -> void:
	if choice != 0 or text == "":
		if from_welcome:
			_show_welcome()
		return
	_login_name = text
	hud.open_dialog("Log in", "Password for %s:" % text, PackedStringArray(["Log in", "Back"]),
		_on_login_password.bind(from_welcome), "Password", 100, not from_welcome, true)


func _on_login_password(choice: int, text: String, from_welcome: bool) -> void:
	if choice != 0 or text == "":
		if from_welcome:
			_show_welcome()
		return
	hud.open_dialog("Log in", "Checking with the island server…", PackedStringArray(), Callable(), "", 0, false)
	api.log_in(_login_name, text, _on_logged_in.bind(from_welcome))


func _on_logged_in(ok: bool, data: Variant, from_welcome: bool) -> void:
	if not ok:
		var reason: String = {
			"wrong_login": "That username and password don't match.",
			"too_many_attempts": "Too many wrong tries. Wait 15 minutes and try again.",
			"network": "Couldn't reach the island server.",
		}.get(str(data.get("error", "")), "Login failed (%s)." % str(data.get("error", "error")))
		hud.open_dialog("Couldn't log in", reason, PackedStringArray(["Try again", "Back"]),
			_on_login_retry.bind(from_welcome), "", 0, false)
		return
	hud.open_dialog("Log in", "Welcome back, %s. Fetching your game…" % api.player_name,
		PackedStringArray(), Callable(), "", 0, false)
	api.fetch_save(_on_login_save)


func _on_login_retry(choice: int, _text: String, from_welcome: bool) -> void:
	if choice == 0:
		_start_login(from_welcome)
	elif from_welcome:
		_show_welcome()


func _on_login_save(ok: bool, data: Variant) -> void:
	started = false  # don't let an autosave overwrite what we load
	var cloud: Variant = data.get("save", null) if ok else null
	if _save_fits(cloud):
		SaveGame.write(cloud)
	else:
		# The account has no game yet: keep this browser's progress, as a new run.
		var local := SaveGame.read()
		if not local.is_empty():
			local["run_id"] = ""
			SaveGame.write(local)
	get_tree().reload_current_scene()


# ---------- Pause menu ----------

func _open_menu() -> void:
	var life := day - life_start_day
	hud.open_dialog("Paused",
		"%s, day %d.\nThis survivor has lived %d full day%s.\n\nThe game saves by itself every few seconds, at dawn, and when you close or reload the page." % [island_name, day, life, "" if life == 1 else "s"],
		PackedStringArray(["Resume", "Save now", "Account", "Start over"]), _on_menu)


func _on_menu(choice: int, _text: String) -> void:
	if choice == 1:
		save_game(false, true)
		hud.toast("Game saved." if not api.can_post() else "Game saved, here and on the island server.")
	elif choice == 2:
		_open_account()
	elif choice == 3:
		hud.open_dialog("Start over?",
			"This deletes your save on this browser: your survivor, your campfires, your bags and every tree you've cut. Graves, notes and stashes on the island server stay.",
			PackedStringArray(["Delete my save", "Cancel"]), _on_start_over)


func _on_start_over(choice: int, _text: String) -> void:
	if choice != 0:
		return
	started = false  # stops any further autosave
	SaveGame.erase()
	if api.can_post():
		# Replace the copy on the server too, or the next visit would bring it back.
		var blank := {"version": SaveGame.VERSION, "world_seed": world.seed_value, "reset": true,
			"saved_at": Time.get_unix_time_from_system()}
		api.upload_save(blank["saved_at"], blank, _reload_after)
	else:
		get_tree().reload_current_scene()


## Reloads the game. Used both after a dialog button and after a server reply.
func _reload_after(_a: Variant = null, _b: Variant = null) -> void:
	get_tree().reload_current_scene()


# ---------- Saving ----------

## Writes the save file. With `respawn`, saves the state after death instead:
## a fresh survivor at the last campfire and a bag with what was carried.
func save_game(respawn: bool = false, upload: bool = false) -> void:
	if not started:
		return
	_save_timer = 0.0
	var fires := []
	for fire in campfires:
		if fire.owner_name == "":
			fires.append({"pos": [fire.pos.x, fire.pos.y], "fuel": fire.fuel})
	var bags := []
	for t in traces:
		if t.kind == "bag":
			bags.append(t.data)
	var data := {
		"version": SaveGame.VERSION,
		"world_seed": world.seed_value,
		"island": ISLAND_ID,
		"saved_at": Time.get_unix_time_from_system(),
		"day": day,
		"clock": clock,
		"life_start_day": life_start_day,
		"run_id": run_id,
		"home": [home.x, home.y] if home != Vector2.INF else null,
		"props": world.export_changes(),
		"fires": fires,
		"bags": bags,
		"read": _read_ids.keys(),
		"structures": _export_structures(),
		"soldiers": _export_soldiers(),
		"army_mode": army_mode,
		"player": {
			"pos": [player.pos.x, player.pos.y],
			"facing": [player.facing.x, player.facing.y],
			"health": player.health,
			"hunger": player.hunger,
			"warmth": player.warmth,
			"sanity": player.sanity,
			"inventory": player.inventory.duplicate(),
			"spear": player.has_spear,
			"torch": player.torch_time,
		},
	}
	if respawn:
		var items := {}
		for item in player.inventory:
			if int(player.inventory[item]) > 0:
				items[item] = int(player.inventory[item])
		if player.has_spear:
			items["spear"] = 1
		if not items.is_empty():
			bags.append({
				"id": "bag-%d" % Time.get_ticks_usec(), "kind": "bag",
				"x": player.pos.x, "y": player.pos.y, "items": items, "player_name": api.player_name,
			})
		var wake := world.cell_center(world.spawn_cell)
		if home != Vector2.INF:
			for offset in [Vector2(24, 0), Vector2(-24, 0), Vector2(0, 24), Vector2(0, -24)]:
				if world.is_walkable(home + offset):
					wake = home + offset
					break
		data["player"] = {
			"pos": [wake.x, wake.y], "facing": [0.0, 1.0], "health": 100.0, "hunger": 80.0,
			"warmth": 100.0, "sanity": 100.0, "inventory": {}, "spear": false, "torch": 0.0,
		}
		data["run_id"] = ""
		data["life_start_day"] = day
	SaveGame.write(data)
	_last_save = data
	_cloud_dirty = true
	if upload:
		_upload_save(true)


## Restores a save. Returns false (and changes nothing) if there is none.
func _apply_save(save: Dictionary) -> bool:
	if save.is_empty() or int(save.get("version", 0)) != SaveGame.VERSION:
		return false
	if int(save.get("world_seed", 0)) != world.seed_value:
		return false
	day = maxi(int(save.get("day", 1)), 1)
	clock = clampf(float(save.get("clock", clock)), 0.0, DAY_LENGTH - 0.01)
	life_start_day = clampi(int(save.get("life_start_day", day)), 1, day)
	run_id = str(save.get("run_id", ""))
	home = _to_vec(save.get("home", null))
	var changes: Variant = save.get("props", {})
	if typeof(changes) == TYPE_DICTIONARY:
		world.import_changes(changes)

	var p: Variant = save.get("player", {})
	if typeof(p) == TYPE_DICTIONARY:
		var pos := _to_vec(p.get("pos", null))
		if pos != Vector2.INF and world.is_walkable(pos):
			player.pos = pos
		var facing := _to_vec(p.get("facing", null))
		if facing != Vector2.INF and facing.length() > 0.1:
			player.facing = facing.normalized()
		player.health = clampf(float(p.get("health", 100.0)), 1.0, 100.0)
		player.hunger = clampf(float(p.get("hunger", 100.0)), 0.0, 100.0)
		player.warmth = clampf(float(p.get("warmth", 100.0)), 0.0, 100.0)
		player.sanity = clampf(float(p.get("sanity", 100.0)), 0.0, 100.0)
		var inv: Variant = p.get("inventory", {})
		if typeof(inv) == TYPE_DICTIONARY:
			for item in player.inventory.keys():
				player.inventory[item] = maxi(int(inv.get(item, 0)), 0)
		player.has_spear = bool(p.get("spear", false))
		player.torch_time = maxf(float(p.get("torch", 0.0)), 0.0)

	for id in save.get("read", []):
		_read_ids[str(id)] = true
	for f in save.get("fires", []):
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var pos := _to_vec(f.get("pos", null))
		if pos == Vector2.INF:
			continue
		var fire: Campfire = Campfire.new()
		fire.world = world
		fire.pos = pos
		fire.fuel = clampf(float(f.get("fuel", 0.0)), 0.0, Campfire.MAX_FUEL)
		entities.add_child(fire)
		campfires.append(fire)
	for b in save.get("bags", []):
		if typeof(b) == TYPE_DICTIONARY:
			_spawn_trace(b)
	for st in save.get("structures", []):
		if typeof(st) == TYPE_ARRAY and st.size() >= 4 and Structure.TYPES.has(str(st[2])):
			var cell := Vector2i(int(st[0]), int(st[1]))
			if world.can_build(cell):
				var items: Variant = st[4] if st.size() > 4 else {}
				_add_structure(str(st[2]), cell, float(st[3]), items if typeof(items) == TYPE_DICTIONARY else {})
	army_mode = "guard" if str(save.get("army_mode", "follow")) == "guard" else "follow"
	for so in save.get("soldiers", []):
		if typeof(so) == TYPE_ARRAY and so.size() >= 6 and soldiers.size() < Soldier.MAX_ARMY:
			_spawn_soldier(Vector2(float(so[0]), float(so[1])), float(so[2]), str(so[3]),
				Vector2(float(so[4]), float(so[5])))
	return true


static func _to_vec(v: Variant) -> Vector2:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.INF


## On the web, also save when the tab is hidden, closed or reloaded.
func _hook_page_unload() -> void:
	if not OS.has_feature("web"):
		return
	_js_save_callback = JavaScriptBridge.create_callback(_on_page_hidden)
	JavaScriptBridge.get_interface("window").addEventListener("pagehide", _js_save_callback)
	JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _js_save_callback)


func _on_page_hidden(_args: Array) -> void:
	if started and alive:
		save_game(false, true)


func _exit_tree() -> void:
	if _js_save_callback != null:
		JavaScriptBridge.get_interface("window").removeEventListener("pagehide", _js_save_callback)
		JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _js_save_callback)
		_js_save_callback = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and started and alive:
		save_game()
