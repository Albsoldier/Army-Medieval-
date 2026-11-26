## Islander: game loop, rules and the link between the island and the server.
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
const Boat = preload("res://scripts/boat.gd")
const Gear = preload("res://scripts/gear.gd")
const Raider = preload("res://scripts/raider.gd")
const Horse = preload("res://scripts/horse.gd")
const Settler = preload("res://scripts/settler.gd")
const PerfOverlay = preload("res://scripts/perf_overlay.gd")
const PerfBench = preload("res://scripts/perf_bench.gd")
const GpuValidation = preload("res://scripts/gpu_validation.gd")
## The sun's shadow setups compared in GRAPHICS_SHADOWS.md: cascades (splits)
## and shadow-map atlas size. All keep the 70 m shadow distance.
const SUN_SHADOWS := {
	"A": {"mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "atlas": 4096, "about": "4 cascades, 4096 atlas"},
	"B": {"mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "atlas": 4096, "about": "2 cascades, 4096 atlas"},
	"C": {"mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "atlas": 2048, "about": "2 cascades, 2048 atlas"},
	"D": {"mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "atlas": 2048, "about": "1 cascade, 2048 atlas"},
}
const SUN_SHADOW_DEFAULT := "C"  # chosen in GRAPHICS_SHADOWS.md
## Jobs for soldiers who aren't needed in the field. They work near the barracks.
const JOBS := {
	"wood": {"name": "Woodcutters", "one": "woodcutter", "gives": {"wood": 3}},
	"stone": {"name": "Quarrymen", "one": "quarryman", "gives": {"stone": 3}},
	"farm": {"name": "Farmers", "one": "farmer", "gives": {}},
}
const WORK_RADIUS := 380.0  # workers find trees, rocks and fields this close to the barracks
const FARMER_TEND := 2.0  # seconds of growth a farmer adds to a field with each stroke (doubles its pace)
const HOUSE_BEDS := 2  # settlers per cottage
const SETTLER_FOOD := 2  # food each settler eats every morning, from your chests
const SETTLER_TAX := 2  # gold each fed settler pays every morning
const SETTLER_FOODS := ["wheat", "bread", "berries", "cooked_meat", "smoked_meat"]
const DEFENCES := ["archer_tower", "spike_trap", "oil_gate"]
const HERDS := 7  # herds of wild horses around the main island
const HERD_SIZE := 3
const MAX_TAME_HORSES := 10
const Art = preload("res://scripts/art.gd")
const CAMP_NAMES := ["the Ashfang camp", "the Blackmoor camp", "the Redhand camp", "the Wolfstone camp",
	"the Ironbrook camp", "the Crowhill camp", "the Saltmarsh camp", "the Gallows Oak camp"]
const PURGE_MIN_GOLD := 50  # gold a vault needs before you can start a purge
const PURGE_STEAL := 3  # gold a raider grabs with each blow at the vault
const PURGE_REACH := 130.0
const PURGE_WAVE_GIVE_UP := 210.0  # seconds before a stuck wave flees  # purge raiders turn on defenders closer than this
const MAIN_CAMPS := 8  # raider camps scattered over the main island
const BASE_SAFE_RADIUS := 320.0  # no camp is manned, and no wolf appears, this close to your buildings
const CAMP_REGROUP_DAYS := 8  # a cleared islet camp is retaken after this many days
const Audio = preload("res://scripts/audio.gd")
const Poi = preload("res://scripts/poi.gd")

## Tools you keep once made, and the player property that records each one.
const TOOLS := {"spear": "has_spear", "iron_spear": "iron_spear", "axe": "has_axe", "pickaxe": "has_pickaxe",
	"armour": "armour", "lantern": "lantern"}
const TOOL_NAMES := {"spear": "spear", "iron_spear": "iron spear", "axe": "axe", "pickaxe": "pickaxe",
	"armour": "iron armour", "lantern": "lantern"}
const DISCOVER_RADIUS := 110.0  # game pixels

const BUILD_RANGE := 8  # tiles from the player
const SEASONS := ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON := 3  # a year is 12 days
const SEASON_NEWS := {
	"spring": "Spring. The ice breaks up and the island turns green again.",
	"summer": "Summer. Warm nights, golden meadows.",
	"autumn": "Autumn. The leaves turn, and bushes are heavy with berries. Stock up before winter.",
	"winter": "Winter. Snow falls, lakes freeze over and nothing grows. The nights are bitter: keep fires burning.",
}
const AXE_WOOD := 20  # wood per hit with an axe in hand (1 by hand)
const PICK_STONE := 20  # stone per hit with a pickaxe in hand
const PICK_ORE := 20  # iron ore or gold per hit with a pickaxe in hand
const UNDO_SECONDS := 60.0  # take a building down this soon after building it: full refund
const MAX_TORCH_POSTS := 24  # lights are expensive in the browser renderer

const ISLAND_ID := 1  # the permanent island, as the server knows it
const WORLD_SEED := 20261119  # the island's shape never changes
const SAVE_INTERVAL := 6.0  # seconds between autosaves
const CLOUD_INTERVAL := 15.0  # seconds between uploads of the save to the server

const DAY_LENGTH := 960.0  # seconds of real time per in-game day (16 minutes)
## Cold and darkness build up at this pace, so a long night costs about as much
## warmth and sanity as the old 4-minute day did. Hunger stays tied to real time.
const NIGHT_PACE := 240.0 / DAY_LENGTH
const INTERACT_RADIUS := 26.0
const ITEM_NAMES := {
	"wood": "wood", "stone": "stone", "berries": "berries",
	"raw_meat": "raw meat", "cooked_meat": "cooked meat", "smoked_meat": "smoked meat",
	"ore": "iron ore", "iron": "iron", "hide": "wolf hide", "salve": "healing salve", "gold": "gold", "steel": "steel",
	"wheat": "wheat", "bread": "bread",
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
var weather: CPUParticles3D
var cam_yaw := 0.0  # radians; hold the right mouse button and drag to turn the camera
var first_person := false  # V switches between the strategy camera and first person
var fp_pitch := -0.15  # first person: looking up (+) or down (-), in radians
const SETTINGS_PATH := "user://settings.cfg"
const EYE_HEIGHT := 1.55  # metres
const MOUSE_LOOK := 0.0028  # radians per pixel of mouse movement
var sky_mat: ProceduralSkyMaterial

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
var boats: Array = []  # Boat nodes, moored where you left them
var sailing: Boat = null  # the boat you're on
var _resume_sailing := -1  # boat to put the player back on after loading
var army_mode := "follow"
## Raider camps: [{"id", "pos", "name", "islet"}], the same on every visit (from the seed).
## Raiders live in them and only ever defend them; they never come for your base.
var herds: Array = []  # [{"id", "pos"}]: where wild horses graze (from the seed)
var horses_taken := {}  # wild horse id -> true once tamed, so it doesn't reappear wild
var tame_horses: Array = []  # Horse nodes that trust you
var riding_horse: Horse = null  # the one you're on
var _wild_horses := {}  # id -> Horse grazing near you now
var _resume_riding := -1
var _horse_open: Horse = null  # the horse whose saddlebags are open
## The purge you started at a vault, or {}: {"vault": Structure, "wave", "waves",
## "stake" (gold at the start), "stolen", "timer", "from" (the side they come from)}.
var purge := {}
var purged_day := 0  # one purge a day
var _vault_open: Structure = null  # the vault whose screen is open
var settlers: Array = []  # Settler nodes living in your cottages
var taxes_last := 0  # gold the village paid at the last dawn
var _defences: Array = []  # towers, traps and oil gates
var _fields: Array = []  # farm fields
var _village_spots: Array = []  # where settlers like to go
var _village_timer := 0.0
var bench_mode := false  # the developer benchmark is running: never save
var dev_look := false  # developers: F8 switches the ranger's hood (?devlook=1)
var sun_shadow_preset := ""  # which SUN_SHADOWS preset is in use
var camps: Array = []
var camps_cleared := {}  # camp id -> the day you cleared it
var camps_found := {}  # camp id -> true once you've seen it
var _camp_guards := {}  # camp id -> raiders guarding it now
var _camp_nodes := {}  # camp id -> the camp's tents
var _wolf_kinds_seen := {}  # tougher wolves are announced the first time
var _station_open := ""  # the crafting station whose panel is open
var formation := "line"  # Z cycles: line, shield wall, wedge
var selected: Array = []  # soldiers picked with a drag box
var _drag_from := Vector2.INF  # where a left-drag started (screen)
var _dragging := false
var _right_from := Vector2.INF  # where a right-click started, to tell a click from a camera turn
var _right_moved := 0.0
var build_mode := false
var build_index := 0
var _ghost: Structure
var audio: Audio
var poi_nodes: Dictionary = {}  # poi id -> Poi node (built when you come near)
var poi_found: Dictionary = {}  # poi id -> true
var poi_looted: Dictionary = {}  # poi id -> true
var shrine_days: Dictionary = {}  # poi id -> the day you last rested there
var _poi_timer := 0.0
var _step_timer := 0.0
var _ghost_key := ""


func _ready() -> void:
	_setup_input()
	audio = Audio.new()
	add_child(audio)
	rng.randomize()
	seed_value = ISLAND_ID
	var world_seed := seed_override() if seed_override() > 0 else WORLD_SEED
	island_name = make_island_name(world_seed)

	world = World.new()
	add_child(world)
	var nature := PerfOverlay.url_value("nature")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nature="):
			nature = arg.trim_prefix("--nature=")
	if nature == "0":
		world.nature_models = false  # developers: the procedural trees, rocks and bushes, for comparing
	var building_models := PerfOverlay.url_value("buildings")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--buildings="):
			building_models = arg.trim_prefix("--buildings=")
	Structure.use_models = building_models != "0"  # developers: ?buildings=0 shows the old buildings, for comparing
	var player_model := PerfOverlay.url_value("player")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			player_model = arg.trim_prefix("--player=")
	Player.use_ranger = player_model != "0"  # developers: ?player=0 shows the old adventurer, for comparing
	# The player's look (the ranger only), for trying the appearance options:
	# ?hood=down&skin=light|medium|tan|dark|deep&outfit=earth&backpack=0. Not saved.
	var look_options := {}
	for key in ["hood", "skin", "outfit", "backpack"]:
		var value: String = PerfOverlay.url_value(key)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--%s=" % key):
				value = arg.trim_prefix("--%s=" % key)
		if value != "":
			look_options[key] = value
	Player.appearance = Player.Appearance.from_options(look_options)
	# Developers: ?devlook=1 (or --devlook=1) lets F8 switch the hood up and
	# down while playing, to compare the two (GRAPHICS_PLAYER_HOOD.md).
	var dev_look_flag := PerfOverlay.url_value("devlook")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--devlook="):
			dev_look_flag = arg.trim_prefix("--devlook=")
	dev_look = dev_look_flag != "" and dev_look_flag != "0"
	world.generate(world_seed)
	var prop_chunk_override := prop_chunk_size_override()
	if prop_chunk_override > 0:
		world.prop_chunk = prop_chunk_override
	var grouping := PerfOverlay.url_value("propgroup")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--propgroup="):
			grouping = arg.trim_prefix("--propgroup=")
	if grouping == "0":
		world.prop_grouping = false  # developers: one MultiMesh per part, for comparing
	_make_camps()
	_make_herds()

	entities = Node3D.new()
	add_child(entities)

	player = Player.new()
	player.world = world
	player.pos = world.cell_center(world.spawn_cell)
	_resumed = _apply_save(SaveGame.read())
	add_child(player)
	world.set_season(season_of(day))
	world.update_view(player.pos, true)

	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 260.0
	add_child(camera)
	camera.make_current()
	_setup_environment()
	_make_weather()
	_update_weather()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("view", "first_person", false)):
		set_first_person(true, false)
	_update_camera(1.0)

	hud = Hud.new()
	add_child(hud)
	api = Api.new()
	add_child(api)

	hud.set_island(island_name, "a permanent island")
	hud.setup_maps(world, _map_markers)
	hud.setup_hotbar(_on_hotbar_slot)
	hud.set_backpack_action(_open_inventory)
	hud.set_crosshair(first_person)
	if _resume_riding >= 0 and _resume_riding < tame_horses.size():
		_mount(tame_horses[_resume_riding])  # you saved in the saddle
	if _resume_sailing >= 0 and _resume_sailing < boats.size():
		_board(boats[_resume_sailing])  # you saved while afloat
	_update_pois(0.0, true)
	_hook_page_unload()
	_update_lighting()
	_refresh_hud()
	# Developer tools, off for players (see perf_overlay.gd).
	if PerfOverlay.enabled():
		var overlay: PerfOverlay = PerfOverlay.new()
		overlay.shown = PerfOverlay.requested()
		add_child(overlay)
	if GpuValidation.requested():
		add_child(GpuValidation.new())  # developers: ?gpuval=1, the real-GPU test of the nature models
	elif PerfBench.requested():
		add_child(PerfBench.new())

	if api.player_name == "":
		_show_welcome()
	else:
		_begin_run()


func _show_welcome() -> void:
	var buttons := PackedStringArray(["Begin"])
	if api.is_online():
		buttons.append("I have an account")
	hud.open_dialog("Islander",
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
	_bind("slot_1", [KEY_1])
	_bind("slot_2", [KEY_2])
	_bind("slot_3", [KEY_3])
	_bind("slot_4", [KEY_4])
	_bind("slot_5", [KEY_5])
	_bind("craft_campfire", [KEY_C])
	_bind("craft_torch", [KEY_R])
	_bind("inventory", [KEY_I, KEY_TAB])
	_bind("view", [KEY_V])
	_bind("sprint", [KEY_SHIFT])
	_bind("formation", [KEY_Z])
	_bind("select_army", [KEY_Y])
	_bind("write_note", [KEY_N])
	_bind("leave_stash", [KEY_G])
	_bind("help", [KEY_H])
	_bind("menu", [KEY_ESCAPE])
	_bind("build", [KEY_B])
	_bind("demolish", [KEY_X])
	_bind("army", [KEY_T])
	_bind("map", [KEY_M])
	_bind("use_salve", [KEY_Q])
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
		_add_campfire(pos, 0.0, str(d.get("player_name", "someone")))
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
	audio.update_mix(night_amount(), delta)
	_update_pois(delta)
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
		# Up on the keyboard always means away from the camera, however it's turned.
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down").rotated(-cam_yaw)
		player.move(dir, delta, Input.is_action_pressed("sprint"))
		if not player.sprinting:
			player.recover_stamina(delta)
		_tick_boat()
		_tick_riding()
		_tick_horses(delta)
		if first_person:
			player.facing = _look_2d()  # you face where you look, even when stepping sideways
		if dir != Vector2.ZERO and sailing == null:
			_step_timer -= delta
			if _step_timer <= 0.0:
				_step_timer = 0.3
				audio.play("step", player.position, -16.0, 0.15)
		action_cooldown = maxf(action_cooldown - delta, 0.0)
		attack_cooldown = maxf(attack_cooldown - delta, 0.0)
		for fire in campfires:
			fire.tick(delta)
		_tick_survival(delta)
		_tick_wolves(delta)
		_tick_army(delta)
		_tick_defences(delta)
		_tick_village(delta)
		_update_hint()
		_update_build_preview()
		if player.health <= 0.0:
			_die()
	_update_camera(delta)
	if weather:
		weather.global_position = camera.global_position + Vector3(0, 9, 0)
	player.place_view_model(camera, delta)
	_update_mouse_mode()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	var dev_key := event as InputEventKey
	if dev_look and dev_key and dev_key.pressed and not dev_key.echo and dev_key.keycode == KEY_F8 \
			and player and player._look_mesh:
		Player.appearance["hood"] = not bool(Player.appearance.get("hood", true))
		Player.Appearance.apply(player._look_mesh, Player.appearance)
		hud.toast("Hood %s (developer view, F8)" % ("up" if Player.appearance["hood"] else "down"))
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventMouseMotion
	if drag and first_person and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or drag.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		cam_yaw = wrapf(cam_yaw - drag.relative.x * MOUSE_LOOK, -PI, PI)
		fp_pitch = clampf(fp_pitch - drag.relative.y * MOUSE_LOOK, -1.35, 1.25)
		return
	if drag and drag.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		cam_yaw = wrapf(cam_yaw - drag.relative.x * 0.006, -PI, PI)
		_right_moved += drag.relative.length()
		return
	var wheel := event as InputEventMouseButton
	# First person: a click first grabs the mouse (browsers only allow that on a click).
	if wheel and wheel.pressed and wheel.button_index == MOUSE_BUTTON_LEFT and first_person \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and started and alive and not hud.is_modal():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if wheel and wheel.pressed and not first_person:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.12, 0.55, 3.2)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.12, 0.55, 3.2)
	if not started or not alive or hud.is_modal():
		return
	if build_mode and _build_input(event):
		return
	if not first_person and not build_mode and _army_input(event):
		return
	if event.is_action_pressed("map"):
		hud.toggle_map()
	elif event.is_action_pressed("use_salve"):
		_use_salve()
	elif event.is_action_pressed("build"):
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
	elif event.is_action_pressed("formation"):
		_cycle_formation()
	elif event.is_action_pressed("select_army"):
		_set_selection(soldiers.duplicate())
		hud.toast("Whole army selected (%d). Right-click the ground to send them." % selected.size() if not selected.is_empty() else "You have no soldiers yet.")
	elif event.is_action_pressed("view"):
		set_first_person(not first_person)
	elif event.is_action_pressed("inventory"):
		_open_inventory()
	elif event.is_action_pressed("demolish"):
		_ask_demolish()
	elif _slot_pressed(event) >= 0:
		_on_hotbar_slot(_slot_pressed(event))
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
	return "%s  ·  %s" % [_time_of_day(), world.season.capitalize()]


func _time_of_day() -> String:
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
		_village_dawn()
		var new_season := season_of(day)
		if new_season != world.season:
			world.set_season(new_season)
			_update_weather()
			hud.toast(SEASON_NEWS[new_season])
			if new_season == "winter":
				_leave_boat_if_frozen()
		save_game(false, true)
	if not was_night and is_night():
		hud.toast("Night falls. Stay close to a fire.")
	_update_lighting()


## The season on a given day: three days each of spring, summer, autumn, winter.
static func season_of(d: int) -> String:
	return SEASONS[((maxi(d, 1) - 1) / DAYS_PER_SEASON) % SEASONS.size()]


## Snowflakes in winter, falling leaves in autumn.
func _update_weather() -> void:
	if weather == null:
		return
	match world.season:
		"winter":
			weather.emitting = true
			weather.amount = 700
			weather.gravity = Vector3(0.4, -2.2, 0.2)
			weather.color = Color(1, 1, 1, 0.9)
			weather.scale_amount_min = 0.6
			weather.scale_amount_max = 1.1
		"autumn":
			weather.emitting = true
			weather.amount = 50
			weather.gravity = Vector3(0.6, -1.0, 0.3)
			weather.color = Color("c8722a")
			weather.scale_amount_min = 1.2
			weather.scale_amount_max = 2.0
		_:
			weather.emitting = false


func _make_weather() -> void:
	weather = CPUParticles3D.new()
	weather.local_coords = false
	weather.lifetime = 8.0
	weather.preprocess = 8.0
	weather.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	weather.emission_box_extents = Vector3(28, 1, 28)
	weather.direction = Vector3(0, -1, 0)
	weather.spread = 15.0
	weather.initial_velocity_min = 0.3
	weather.initial_velocity_max = 0.8
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.material = mat
	weather.mesh = flake
	weather.emitting = false
	add_child(weather)


func _setup_environment() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	# Haze only far away (depth fog), so distant hills fade into the sky
	# without washing out what's near the camera.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 32.0
	env.fog_depth_end = 120.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	add_child(sun)
	apply_sun_shadows(sun_shadow_override())
	_update_lighting()


## Sets the sun's shadow cascades and atlas size from a SUN_SHADOWS preset.
func apply_sun_shadows(preset: String) -> void:
	if not SUN_SHADOWS.has(preset):
		preset = SUN_SHADOW_DEFAULT
	var p: Dictionary = SUN_SHADOWS[preset]
	sun.directional_shadow_mode = p["mode"]
	RenderingServer.directional_shadow_atlas_set_size(int(p["atlas"]), true)
	sun_shadow_preset = preset


## Developers can try another prop chunk size (tiles): ?propchunk=40, or -- --propchunk=40.
static func prop_chunk_size_override() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--propchunk="):
			return clampi(arg.trim_prefix("--propchunk=").to_int(), 8, 128)
	var v := PerfOverlay.url_value("propchunk")
	return clampi(v.to_int(), 8, 128) if v != "" else 0


## Developers can try another preset: index.html?shadows=B, or -- --shadows=B.
static func sun_shadow_override() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shadows="):
			return arg.trim_prefix("--shadows=").to_upper()
	return PerfOverlay.url_value("shadows").to_upper()


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
	var sun_pitch := -(12.0 + sin(day_frac * PI) * 48.0)
	var sun_yaw := lerpf(-75.0, 75.0, day_frac)
	var moon := Vector3(-50.0, 30.0, 0.0)
	var angles := Vector3(sun_pitch, sun_yaw, 0.0).lerp(moon, clampf((n - 0.5) * 2.0, 0.0, 1.0))
	sun.rotation_degrees = angles
	sun.light_color = _sky_blend(Color(1.0, 0.94, 0.82), Color(1.0, 0.68, 0.45), Color(0.55, 0.65, 1.0), n)
	sun.light_energy = lerpf(1.0, 0.1, n)

	var top := _sky_blend(Color(0.32, 0.52, 0.78), Color(0.35, 0.33, 0.52), Color(0.01, 0.02, 0.05), n)
	var horizon := _sky_blend(Color(0.74, 0.8, 0.84), Color(0.95, 0.62, 0.42), Color(0.04, 0.05, 0.1), n)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon.darkened(0.4)
	sky_mat.sun_curve = 0.12
	env.fog_light_color = horizon
	env.ambient_light_color = _sky_blend(Color(0.58, 0.64, 0.74), Color(0.55, 0.47, 0.5), Color(0.05, 0.06, 0.12), n)
	env.ambient_light_energy = lerpf(0.45, 1.0, n)


func _update_camera(delta: float) -> void:
	if first_person:
		var look := _look_2d()
		var forward := Vector3(look.x * cos(fp_pitch), sin(fp_pitch), look.y * cos(fp_pitch))
		camera.position = player.position + Vector3(0, EYE_HEIGHT + player.ride_height() + player.head_bob(), 0) + Vector3(look.x, 0, look.y) * 0.12
		camera.look_at(camera.position + forward)
		return
	# A strategy-game camera: it looks down more steeply the further out you zoom.
	# Mouse wheel zooms, right-drag turns it.
	var target := player.position + Vector3(0, 0.9, 0)
	var t := clampf((zoom - 0.55) / (3.2 - 0.55), 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(30.0, 58.0, t))
	var dist := lerpf(7.0, 34.0, t)
	var offset := Vector3(sin(cam_yaw) * cos(pitch), sin(pitch), cos(cam_yaw) * cos(pitch)) * dist
	var desired := target + offset
	var weight := 1.0 if delta >= 1.0 else 1.0 - exp(-delta * 6.0)
	camera.position = camera.position.lerp(desired, weight)
	camera.look_at(target)


## The direction the camera looks, flat on the ground (game coordinates).
func _look_2d() -> Vector2:
	return Vector2(-sin(cam_yaw), -cos(cam_yaw))


## Switches between the strategy camera and first person.
func set_first_person(on: bool, remember: bool = true) -> void:
	first_person = on
	player.set_first_person(on)
	if on:
		# Look the way you were facing, level with the horizon.
		var f := player.facing if player.facing.length() > 0.1 else Vector2.DOWN
		cam_yaw = atan2(-f.x, -f.y)
		fp_pitch = -0.15
		camera.fov = 72.0
	else:
		camera.fov = 50.0
		_update_camera(1.0)  # jump back behind the player
	if hud:
		hud.set_crosshair(on)
	_update_mouse_mode(on)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("view", "first_person", on)
		cfg.save(SETTINGS_PATH)
		if hud:
			hud.toast("First person: move the mouse to look, V to go back." if on else "Strategy view: right-drag to turn, wheel to zoom.")


## First person grabs the mouse for looking around, and lets go while a menu,
## the map or the inventory is open.
func _update_mouse_mode(grab: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := first_person and started and alive and hud != null and not hud.is_modal()
	if not want and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif want and grab and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
		match world.season:
			"summer":
				loss = lerpf(-0.8, 0.6, n)  # mild nights
			"autumn":
				loss = lerpf(-0.4, 1.3, n)
			"winter":
				loss = lerpf(0.25, 1.8, n)  # cold even by day
		if has_torch and loss > 0.0:
			loss *= 0.4
		if loss > 0.0:
			loss *= 1.0 - player.armour_warmth()
		player.warmth = clampf(player.warmth - loss * NIGHT_PACE * delta, 0.0, 100.0)

	if near_fire or has_torch or player.lantern_lit() or n < 0.5 or _nearest(_torch_posts(), player.pos, Structure.TORCH_RADIUS) != null:
		player.sanity = minf(player.sanity + 0.05 * NIGHT_PACE * delta, 100.0)
	else:
		player.sanity = maxf(player.sanity - 0.35 * NIGHT_PACE * delta, 0.0)

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
		audio.play("hurt", player.position)
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
			if _count_wolves() < mini(1 + day, 6) + soldiers.size() / 10:
				var pos := world.random_walkable_near(player.pos, 300.0, 420.0, rng)
				if pos != Vector2.INF and not _near_base(pos, BASE_SAFE_RADIUS):
					var wolf: Wolf = Wolf.new()
					wolf.world = world
					wolf.pos = pos
					wolf.kind = Wolf.pick_kind(day, world.season == "winter", rng.randf())
					if wolf.kind != "grey" and not _wolf_kinds_seen.has(wolf.kind):
						_wolf_kinds_seen[wolf.kind] = true
						hud.toast({"timber": "A timber wolf is out tonight: bigger and tougher. Iron gear will help.",
							"dire": "A dire wolf prowls the island. Only the best weapons and armour stand up to it."}[wolf.kind])
					entities.add_child(wolf)
					wolves.append(wolf)
					audio.play("wolf_howl", wolf_3d(pos), -4.0)
					if not howled_tonight:
						howled_tonight = true
						hud.toast("A howl rolls across the island…")
	var lights := _lights()
	for wolf in wolves.duplicate():
		if not wolves.has(wolf):
			continue  # gone this frame (a purge ended)
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
		var villager: Settler = null
		for st in settlers:
			if not st.dead and not st.hidden:
				var d2: float = wolf.pos.distance_to(st.pos)
				if d2 < best:
					best = d2
					target_pos = st.pos
					victim = null
					villager = st
		var raider: bool = wolf.is_raider()
		var at_vault := false
		if raider and wolf.purge and not purge.is_empty() and best > PURGE_REACH:
			# Purge raiders go for the vault, turning on you or your soldiers only up close.
			target_pos = (purge["vault"] as Structure).pos
			victim = null
			villager = null
			at_vault = true
		if wolf.tick(delta, target_pos, lights, night):
			if at_vault:
				_purge_steal(wolf)
			elif villager != null:
				audio.play("hit" if raider else "wolf_bite", wolf.position, -2.0)
				if villager.hurt(wolf.bite):
					_on_settler_fallen(villager)
			else:
				audio.play("hit" if raider else "wolf_bite", wolf.position, -2.0)
				if victim == null:
					# Armour stops part of every blow.
					_hurt(wolf.bite * (1.0 - player.armour_reduction()), "raiders" if raider else "wolves")
				elif victim.hurt(wolf.bite):
					_on_soldier_fallen(victim)
		# Only purge raiders break walls: they hack their way to the vault.
		if raider and wolf.purge and buildings.has(wolf.blocked_cell):
			var wall: Structure = buildings[wolf.blocked_cell]
			if wall.kind != "vault" and wall.damage((8.0 if wall.kind == "stone_wall" else 22.0) * delta):
				hud.toast("Raiders broke through your %s!" % wall.display_name().to_lower())
				_remove_structure(wall.cell)
		var far: float = wolf.pos.distance_to(player.pos)
		if not raider and not night and far > 450.0:
			wolves.erase(wolf)
			wolf.queue_free()
	_tick_camps()
	_tick_purge(delta)


func _count_wolves() -> int:
	var n := 0
	for w in wolves:
		if not w.is_raider():
			n += 1
	return n


## Whether anything you've built is within `radius` of `pos`.
func _near_base(pos: Vector2, radius: float) -> bool:
	for b in buildings.values():
		if b.pos.distance_to(pos) < radius:
			return true
	return false


## Raider camps: about eight on the main island, far from where you start,
## and one beside each islet's hoard. Worked out from the island's seed, so
## they're always in the same places.
func _make_camps() -> void:
	camps.clear()
	var fixed := RandomNumberGenerator.new()
	fixed.seed = world.seed_value * 61 + 7
	var half := World.SIZE / 2
	var tries := 0
	var made := 0
	while made < MAIN_CAMPS and tries < 4000:
		tries += 1
		var r := sqrt(fixed.randf()) * half * 0.85
		var a := fixed.randf() * TAU
		var cell := Vector2i(half + int(cos(a) * r), half + int(sin(a) * r))
		if world.terrain_at(cell) != World.GRASS or cell.distance_to(world.spawn_cell) < 150.0:
			continue
		var spot := world.cell_center(cell)
		if not world.is_walkable(spot) or _camp_near_others(spot, 1500.0):
			continue
		var by_place := false
		for data in world.pois:
			if world.cell_center(data["cell"]).distance_to(spot) < 500.0:
				by_place = true
				break
		if by_place:
			continue
		camps.append({"id": "camp-%d" % made, "pos": spot, "name": CAMP_NAMES[made % CAMP_NAMES.size()], "islet": -1})
		made += 1
	for i in world.islets.size():
		var spot := world.cell_center(world.islets[i]["cell"])
		for data in world.pois:
			if data["id"] == "hoard-%d" % i:
				var near_hoard := world.random_walkable_near(world.cell_center(data["cell"]), 30.0, 50.0, fixed)
				spot = near_hoard if near_hoard != Vector2.INF else world.cell_center(data["cell"])
		camps.append({"id": "islet-%d" % i, "pos": spot, "name": "the raider camp on %s" % world.islets[i]["name"], "islet": i})


func _camp_near_others(spot: Vector2, gap: float) -> bool:
	for c in camps:
		if (c["pos"] as Vector2).distance_to(spot) < gap:
			return true
	return false


func _camp(id: String) -> Dictionary:
	for c in camps:
		if c["id"] == id:
			return c
	return {}


## Camps come to life as you approach: tents first, then the guards. Guards
## only defend their camp, and a camp near your buildings stays empty.
func _tick_camps() -> void:
	if not started or not alive:
		return
	for c in camps:
		var id: String = c["id"]
		var at: Vector2 = c["pos"]
		var dist := at.distance_to(player.pos)
		var near := dist < 900.0
		if near and not _camp_nodes.has(id):
			_camp_nodes[id] = _build_camp(at)
		elif not near and dist > 1400.0 and _camp_nodes.has(id):
			_camp_nodes[id].queue_free()
			_camp_nodes.erase(id)
		if dist < 380.0 and not camps_found.has(id):
			camps_found[id] = true
			hud.toast("You spot %s. Its raiders defend it, but they never leave it." % c["name"])
			_save_timer = SAVE_INTERVAL - 1.0
		if near and not _camp_guards.has(id) and _camp_holds(id) and not _near_base(at, BASE_SAFE_RADIUS):
			_spawn_camp_guards(c)
		if _camp_guards.has(id):
			var alive_guards: Array = _camp_guards[id].filter(func(r): return is_instance_valid(r) and not r.dead and wolves.has(r))
			_camp_guards[id] = alive_guards
			if alive_guards.is_empty():
				_camp_guards.erase(id)
				camps_cleared[id] = day
				_camp_cleared(c)
			elif not near:
				# Out of sight: the guards go back to their tents.
				for r in alive_guards:
					wolves.erase(r)
					r.queue_free()
				_camp_guards.erase(id)


## Beating a camp's guards: islet camps free their hoard; main-island camps
## have a war chest.
func _camp_cleared(c: Dictionary) -> void:
	audio.play("discover")
	_save_timer = SAVE_INTERVAL - 1.0
	if int(c["islet"]) >= 0:
		hud.toast("You've cleared %s. Its hoard is yours." % c["name"])
		return
	var chest := {"iron": 4, "steel": 2, "gold": 1, "smoked_meat": 2}
	for item in chest:
		player.add_item(item, int(chest[item]))
	hud.toast("You've cleared %s and take its war chest: %s." % [c["name"], _items_text(chest)])


## Whether raiders hold a camp right now (a cleared one is retaken in time).
func _camp_holds(id: String) -> bool:
	return not camps_cleared.has(id) or day >= int(camps_cleared[id]) + CAMP_REGROUP_DAYS


func _spawn_camp_guards(c: Dictionary) -> void:
	var at: Vector2 = c["pos"]
	var guards := []
	var count := 3 + mini(day / 6, 3)
	for k in count + 1:
		var spot := world.random_walkable_near(at, 8.0, 50.0, rng)
		if spot == Vector2.INF:
			continue
		var r := _spawn_raider("raider_chief" if k == 0 else "raider", spot)
		r.home = at
		r.camp = int(c["islet"])
		guards.append(r)
	_camp_guards[c["id"]] = guards


func _spawn_raider(kind: String, at: Vector2) -> Raider:
	var r: Raider = Raider.new()
	r.world = world
	r.kind = kind
	r.pos = at
	entities.add_child(r)
	wolves.append(r)
	return r


## A few hide tents and a banner, where a camp's raiders live.
func _build_camp(at: Vector2) -> Node3D:
	var camp := Node3D.new()
	entities.add_child(camp)
	camp.position = world.to_3d(at)
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		Art.part(camp, Art.cylinder(0.0, 0.9, 1.5, 6), Color("5e4a36"), Vector3(cos(a) * 2.6, 0.75, sin(a) * 2.6))
	Art.part(camp, Art.cylinder(0.04, 0.04, 2.8, 5), Color("4d3420"), Vector3(0, 1.4, 0))
	Art.part(camp, Art.box(Vector3(0.7, 0.45, 0.03)), Color("7a1f1f"), Vector3(0.36, 2.5, 0))
	Art.part(camp, Art.cylinder(0.5, 0.5, 0.05, 8), Color("2b2522"), Vector3(0, 0.02, 0))  # a cold fire pit
	return camp


func wolf_3d(pos: Vector2) -> Vector3:
	return world.to_3d(pos) + Vector3(0, 0.5, 0)


func _kill_wolf(wolf: Wolf, by_army: bool, by: String = "") -> void:
	wolves.erase(wolf)
	audio.play("hurt" if wolf.is_raider() else "wolf_yelp", wolf.position)
	var loot: Dictionary = wolf.loot()
	for item in loot:
		player.add_item(item, int(loot[item]))
	var fall_time: float = wolf.die()
	get_tree().create_timer(fall_time + 1.0).timeout.connect(wolf.queue_free)
	var who := by if by != "" else ("Your soldiers bring down" if by_army else "You bring down")
	hud.toast("%s the %s. +%s" % [who, wolf.display_name(), _items_text(loot)])


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
	if riding_horse != null:
		_dismount()
		return
	if sailing != null:
		_go_ashore()
		return
	var dock := _nearest(buildings.values().filter(func(b): return b.kind == "dock"), pos, 24.0)
	if dock != null:
		_open_dock(dock)
		return
	var boat := _nearest(boats, pos, 36.0)
	if boat != null:
		_board(boat)
		return
	var trace := _nearest(traces, pos, 22.0)
	if trace != null:
		_use_trace(trace)
		return
	var fire := _nearest(campfires, pos, 26.0)
	if fire != null:
		_use_fire(fire)
		return
	var place := _nearest(poi_nodes.values(), pos, 48.0)
	if place != null:
		_use_poi(place)
		return
	# Your own horse comes first, even with wild ones grazing close by.
	var horse := _nearest(tame_horses, pos, 30.0)
	if horse == null:
		horse = _nearest(_wild_horses.values(), pos, 30.0)
	if horse != null:
		_use_horse(horse)
		return
	var building := _nearest(buildings.values(), pos, 24.0)
	if building != null:
		_use_building(building)
		return
	var cell := world.find_prop_near(pos, INTERACT_RADIUS)
	if cell != World.NO_CELL:
		var kind := world.prop_type(cell)
		if (kind == "iron_rock" or kind == "gold_rock") and not player.holding("pickaxe"):
			var ore := "gold" if kind == "gold_rock" else "iron ore"
			if player.has_pickaxe:
				hud.toast("Take your pickaxe in hand (4) to mine %s." % ore)
			else:
				hud.toast("%s needs a pickaxe. Make one at a workbench." % ore.capitalize())
			return
		if kind == "bush" and world.season == "winter":
			hud.toast("The bush is bare. Nothing grows in winter.")
			return
		player.swing()
		audio.play({"tree": "chop", "bush": "pick"}.get(kind, "mine"), world.to_3d(world.cell_center(cell)))
		var gained := world.harvest(cell, day)
		for item in gained:
			var amount := int(gained[item])
			amount *= _tool_bonus(item)
			player.add_item(item, amount)
			hud.toast("+%d %s" % [amount, ITEM_NAMES[item]])


## How much you gather per hit with the right tool in hand: an axe gives 20 wood,
## a pickaxe 20 stone, iron ore or gold.
func _tool_bonus(item: String) -> int:
	if item == "wood" and player.holding("axe"):
		return AXE_WOOD
	if item == "stone" and player.holding("pickaxe"):
		return PICK_STONE
	if (item == "ore" or item == "gold") and player.holding("pickaxe"):
		return PICK_ORE
	return 1


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
			fire.add_fuel(120.0)
			hud.toast("You feed the fire. It will burn for about %d more seconds." % int(fire.fuel))
		else:
			hud.toast("The fire crackles. Bring wood to keep it going.")
	elif player.count("wood") >= 2:
		player.add_item("wood", -2)
		fire.add_fuel(180.0)
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
				if str(item).begins_with("gear_"):
					_restore_gear(str(item).trim_prefix("gear_"), int(items[item]) - 1)
				elif TOOLS.has(item):
					player.set(TOOLS[item], true)
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
	attack_cooldown = player.attack_cooldown()
	# Tired arms swing slower.
	if player.stamina < Player.SWING_COST:
		attack_cooldown *= 2.0
	player.spend_stamina(Player.SWING_COST)
	player.swing()
	audio.play("swing", player.position, -6.0)
	var damage := player.attack_damage()
	var reach := player.attack_reach()
	for wolf in wolves.duplicate():
		if wolf.pos.distance_to(player.pos) <= reach:
			wolf.hurt(damage, player.pos)
			audio.play("hit", wolf.position)
			if wolf.hp <= 0:
				_kill_wolf(wolf, false)


func _eat() -> void:
	for item in ["smoked_meat", "cooked_meat", "bread", "berries", "raw_meat"]:
		if player.count(item) > 0:
			_eat_item(item)
			return
	hud.toast("You have nothing to eat. Look for berry bushes.")


func _eat_item(item: String) -> void:
	if player.count(item) <= 0:
		return
	audio.play("eat")
	player.add_item(item, -1)
	match item:
		"smoked_meat":
			player.hunger = minf(player.hunger + 45.0, 100.0)
			player.sanity = minf(player.sanity + 5.0, 100.0)
			hud.toast("You eat smoked meat. Rich and satisfying.")
		"cooked_meat":
			player.hunger = minf(player.hunger + 35.0, 100.0)
			player.sanity = minf(player.sanity + 3.0, 100.0)
			hud.toast("You eat cooked meat. Warm and filling.")
		"bread":
			player.hunger = minf(player.hunger + 30.0, 100.0)
			player.sanity = minf(player.sanity + 2.0, 100.0)
			hud.toast("You eat a loaf of fresh bread.")
		"berries":
			player.hunger = minf(player.hunger + 8.0, 100.0)
			hud.toast("You eat a handful of berries.")
		"raw_meat":
			player.hunger = minf(player.hunger + 12.0, 100.0)
			player.sanity = maxf(player.sanity - 8.0, 0.0)
			_hurt(3.0, "bad meat")
			hud.toast("You choke down raw meat. Your stomach turns.")


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
			_add_campfire(pos, 360.0, "")
			audio.play("craft", world.to_3d(pos))
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
			player.torch_time = 180.0
			audio.play("craft")
			hud.toast("You light a torch. It will last a while.")
		"spear":
			_make_gear("spear", 1)  # a flint spear


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
		if str(item).begins_with("gear_"):
			parts.append("a " + Gear.tier_name(str(item).trim_prefix("gear_"), int(items[item]) - 1).to_lower())
			continue
		parts.append("%d %s" % [int(items[item]), ITEM_NAMES.get(item, TOOL_NAMES.get(item, str(item)))])
	return ", ".join(parts)


# ---------- HUD ----------

func _update_hint() -> void:
	var pos := player.pos
	var hint := ""
	var trace := _nearest(traces, pos, 22.0)
	var fire := _nearest(campfires, pos, 26.0)
	var cell := world.find_prop_near(pos, INTERACT_RADIUS)
	var building := _nearest(buildings.values(), pos, 24.0)
	var place := _nearest(poi_nodes.values(), pos, 48.0)
	if build_mode:
		return  # the build bar uses the hint line
	var boat := _nearest(boats, pos, 36.0)
	var horse_near := _nearest(tame_horses, pos, 30.0)
	if horse_near == null:
		horse_near = _nearest(_wild_horses.values(), pos, 30.0)
	if riding_horse != null:
		hint = "On horseback · E: dismount"
	elif sailing != null:
		hint = "Sailing the %s · E: go ashore" % sailing.display_name().to_lower()
	elif horse_near != null:
		var hn: Horse = horse_near
		hint = "E: your horse (ride, saddlebags)" if not hn.wild else "E: offer %d berries to the wild horse (trust %d / %d)" % [Horse.BERRIES_PER_FEED, hn.trust, Horse.FEEDS_TO_TAME]
	elif _nearest(buildings.values().filter(func(b): return b.kind == "dock"), pos, 24.0) != null:
		hint = "E: use the dock (boats)"
	elif boat != null:
		hint = "E: board the %s" % (boat as Boat).display_name().to_lower()
	elif trace != null:
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
	elif place != null:
		var pl: Poi = place
		if pl.kind == "shrine":
			hint = "E: rest at %s" % pl.display_name()
		elif poi_looted.has(pl.poi_id()):
			hint = "E: look around %s" % pl.display_name()
		else:
			hint = "E: search %s" % pl.display_name()
	elif building != null:
		hint = _building_hint(building)
	elif cell != World.NO_CELL:
		hint = {"tree": "E: chop tree", "rock": "E: break rock", "bush": "E: pick berries",
			"iron_rock": "E: mine iron ore" if player.holding("pickaxe") else ("Iron ore: take your pickaxe in hand (4)" if player.has_pickaxe else "Iron ore: you need a pickaxe"),
			"gold_rock": "E: mine gold" if player.holding("pickaxe") else ("Gold: take your pickaxe in hand (4)" if player.has_pickaxe else "Gold: you need a pickaxe")}.get(world.prop_type(cell), "")
		if world.prop_type(cell) == "bush" and world.season == "winter":
			hint = "A bare bush. Nothing grows in winter."
	elif is_night() and not _near_lit_fire(pos) and player.torch_time <= 0.0:
		hint = "It's dark and cold. Build a campfire (C) or light a torch (I)."
	hud.set_hint(hint)


func _refresh_hud() -> void:
	var inv := "Wood %d   Stone %d   Berries %d   Raw meat %d   Cooked %d" % [
		player.count("wood"), player.count("stone"), player.count("berries"),
		player.count("raw_meat"), player.count("cooked_meat"),
	]
	var extras := PackedStringArray()
	for item in ["smoked_meat", "bread", "wheat", "ore", "iron", "steel", "hide", "salve", "gold"]:
		if player.count(item) > 0:
			extras.append("%s %d" % [ITEM_NAMES[item].capitalize(), player.count(item)])
	if not extras.is_empty():
		inv += "\n" + "   ".join(extras)
	var gear := PackedStringArray()
	for kind in ["spear", "sword", "armour"]:
		if _gear_tier(kind) >= 0:
			gear.append(Gear.tier_name(kind, _gear_tier(kind)))
	for tool in ["axe", "pickaxe", "lantern"]:
		if player.get(TOOLS[tool]):
			gear.append(TOOL_NAMES[tool].capitalize())
	if player.torch_time > 0.0:
		gear.append("Torch %ds" % int(player.torch_time))
	if not gear.is_empty():
		inv += "\n" + "  ·  ".join(gear)
	if not soldiers.is_empty() or _count("barracks") > 0:
		inv += "\nArmy %d / %d  ·  %s  ·  %s (Z)" % [soldiers.size(), _army_capacity(),
			"following" if army_mode == "follow" else "guarding", formation]
		var workers := soldiers.filter(func(so): return so.mode == "work").size()
		if workers > 0:
			inv += "  ·  %d at work" % workers
	if not settlers.is_empty() or _count("house") > 0:
		inv += "\nVillage: %d settler%s  ·  %d gold in taxes this morning" % [settlers.size(), "" if settlers.size() == 1 else "s", taxes_last]
	hud.update_hotbar(_hotbar_slots(), HOTBAR.find(player.equipped if player.owns(player.equipped) else "hands"))
	hud.set_hotbar_visible(started)
	hud.update_stats([player.health, player.stamina, player.hunger, player.warmth, player.sanity], day, time_label(), inv,
		[100.0, Player.MAX_STAMINA])


# ---------- Campfires, tools, stations ----------

func _add_campfire(pos: Vector2, fuel: float, owner: String) -> Campfire:
	var fire: Campfire = Campfire.new()
	fire.world = world
	fire.pos = pos
	fire.fuel = fuel
	fire.owner_name = owner
	entities.add_child(fire)
	campfires.append(fire)
	var crackle := audio.make_fire_player()
	crackle.position = Vector3(0, 0.5, 0)
	fire.add_child(crackle)
	fire.sound = crackle
	return fire


func _tools_owned() -> Array:
	var owned := []
	for tool in TOOLS:
		if player.get(TOOLS[tool]):
			owned.append(tool)
	return owned


func _use_salve() -> void:
	if player.count("salve") <= 0:
		hud.toast("You have no healing salve. Make some at a workbench (6 berries).")
		return
	if player.health >= 100.0:
		hud.toast("You're not hurt.")
		return
	player.add_item("salve", -1)
	player.health = minf(player.health + 30.0, 100.0)
	audio.play("eat", Vector3.INF, -4.0)
	hud.toast("You apply the salve. +30 health")


## A crafting station: materials and tools on the left, weapons and armour
## (gear.gd) on the right, each with its cost and what it does.
func _open_station(kind: String) -> void:
	_station_open = kind
	var basics := []
	for r in Structure.RECIPES[kind]:
		var cost: Dictionary = r["cost"]
		var owned: bool = TOOLS.has(r["id"]) and player.get(TOOLS[r["id"]])
		basics.append({"name": str(r["name"]), "detail": "free" if cost.is_empty() else _items_text(cost),
			"button": "Owned" if owned else "Make", "action": "station:%s:%s" % [kind, r["id"]],
			"enabled": not owned and (cost.is_empty() or player.can_afford(cost)), "dim": owned})
	var weapons := []
	var armour := []
	for r in Gear.recipes_for(kind):
		var have: bool = _gear_tier(r["kind"]) >= int(r["tier"])
		var row := {"name": str(r["name"]), "detail": "%s · %s" % [r["about"], _items_text(r["cost"])],
			"button": "Owned" if have else "Make", "action": "make:" + str(r["id"]),
			"enabled": not have and player.can_afford(r["cost"]), "dim": have}
		if r["kind"] == "armour":
			armour.append(row)
		else:
			weapons.append(row)
	var right := []
	if not weapons.is_empty():
		right.append({"title": "Weapons", "rows": weapons})
	if not armour.is_empty():
		right.append({"title": "Armour", "rows": armour})
	var about := {"workbench": "Tools and hide armour.", "forge": "Smelt iron and steel, then forge weapons and armour. Gold comes from the islets.",
		"smokehouse": "Smoked meat is the best food."}
	var columns := [[{"title": "Make", "rows": basics}]]
	if not right.is_empty():
		columns.append(right)
	hud.show_panel(Structure.info(kind)["name"], str(about.get(kind, "")) + "   Esc to close", columns, _on_station_action)


func _on_station_action(action: String) -> void:
	var parts := action.split(":")
	if parts[0] == "make":
		_make_gear(parts[2], int(parts[3]))
		_open_station(_station_open)
		return
	if parts[0] == "station":
		for r in Structure.RECIPES[parts[1]]:
			if r["id"] == parts[2] and _make(r):
				_save_timer = SAVE_INTERVAL - 1.0
		_open_station(parts[1])


## Makes one recipe from a crafting station. Returns true if something was made.
func _make(r: Dictionary) -> bool:
	var id: String = r["id"]
	var cost: Dictionary = r["cost"]
	if id.begins_with("gear:"):
		var parts := id.split(":")
		return _make_gear(parts[1], int(parts[2]))
	if TOOLS.has(id) and player.get(TOOLS[id]):
		hud.toast("You already have a %s." % TOOL_NAMES[id])
		return false
	if id == "smoke":
		var raw := player.count("raw_meat")
		if raw == 0:
			hud.toast("You have no raw meat to smoke. Hunt wolves for meat.")
			return false
		player.add_item("raw_meat", -raw)
		player.add_item("smoked_meat", raw)
		audio.play("craft")
		hud.toast("You smoke %d meat." % raw)
		return true
	if not player.can_afford(cost):
		hud.toast("%s needs %s." % [r["name"], _items_text(cost)])
		return false
	player.pay(cost)
	if TOOLS.has(id):
		player.set(TOOLS[id], true)
		if id == "iron_spear":
			player.has_spear = true
		# A new weapon or tool goes straight into your hand.
		var slot: String = {"iron_spear": "spear", "spear": "spear", "axe": "axe", "pickaxe": "pickaxe"}.get(id, "")
		if slot != "":
			player.equip(slot)
		elif id == "armour":
			player.armour_on = true
		elif id == "lantern":
			player.lantern_on = true
	else:
		player.add_item(id, 1)
	audio.play("craft")
	hud.toast("You make: %s." % str(r["name"]).to_lower())
	return true


## Takes back gear (from a save or a bag), keeping whichever is better.
func _restore_gear(kind: String, tier: int) -> void:
	var top := Gear.list_for(kind).size() - 1
	tier = clampi(tier, -1, top)
	match kind:
		"spear":
			player.spear_tier = maxi(player.spear_tier, tier)
		"sword":
			player.sword_tier = maxi(player.sword_tier, tier)
		"armour":
			player.armour_tier = maxi(player.armour_tier, tier)


func _gear_tier(kind: String) -> int:
	match kind:
		"spear":
			return player.spear_tier
		"sword":
			return player.sword_tier
	return player.armour_tier


## Makes a spear, sword or armour of a tier (gear.gd). It replaces what you
## had, so only a better one can be made. Returns true if it was made.
func _make_gear(kind: String, tier: int) -> bool:
	var g := Gear.info(kind, tier)
	if g.is_empty():
		return false
	if _gear_tier(kind) >= tier:
		hud.toast("You already have %s." % ("a better one" if _gear_tier(kind) > tier else "one"))
		return false
	var cost: Dictionary = g["cost"]
	if not player.can_afford(cost):
		hud.toast("%s needs %s." % [g["name"], _items_text(cost)])
		return false
	player.pay(cost)
	match kind:
		"spear":
			player.spear_tier = tier
			player.equip("spear")
		"sword":
			player.sword_tier = tier
			player.equip("sword")
		_:
			player.armour_tier = tier
			player.armour_on = true
	audio.play("craft")
	if kind == "armour":
		hud.toast("You put on your new %s (%s)." % [str(g["name"]).to_lower(), Gear.stat_text(kind, tier)])
	else:
		hud.toast("You make a %s (%s) and take it in hand." % [str(g["name"]).to_lower(), Gear.stat_text(kind, tier)])
	_save_timer = SAVE_INTERVAL - 1.0
	return true


func _open_settings() -> void:
	hud.open_dialog("Settings", "Sound effects are %s. Music is %s." % [
		"on" if audio.sound_on else "off", "on" if audio.music_on else "off"],
		PackedStringArray(["Sound: " + ("on" if audio.sound_on else "off"), "Music: " + ("on" if audio.music_on else "off"), "Close"]),
		_on_settings_choice)


func _on_settings_choice(choice: int, _text: String) -> void:
	if choice == 0:
		audio.set_sound(not audio.sound_on)
		_open_settings()
	elif choice == 1:
		audio.set_music(not audio.music_on)
		_open_settings()


# ---------- Places to discover ----------

## Builds places as you get near, notices when you find one, and lights the lighthouses.
func _update_pois(delta: float, force: bool = false) -> void:
	_poi_timer -= delta
	var n := night_amount()
	for node in poi_nodes.values():
		node.set_night(n)
	if _poi_timer > 0.0 and not force:
		return
	_poi_timer = 0.5
	for data in world.pois:
		var id: String = data["id"]
		var at: Vector2 = world.cell_center(data["cell"])
		var dist := at.distance_to(player.pos)
		if not poi_nodes.has(id) and dist < 1800.0:
			var place: Poi = Poi.new()
			place.setup(world, data)
			place.discovered = poi_found.has(id)
			place.looted = poi_looted.has(id)
			entities.add_child(place)
			poi_nodes[id] = place
		elif poi_nodes.has(id) and dist > 2600.0:
			poi_nodes[id].queue_free()
			poi_nodes.erase(id)
		if started and alive and not poi_found.has(id) and dist < DISCOVER_RADIUS:
			poi_found[id] = true
			if poi_nodes.has(id):
				poi_nodes[id].discovered = true
			audio.play("discover")
			hud.toast("Discovered: %s" % data["name"])
			_save_timer = SAVE_INTERVAL - 1.0


func _use_poi(place: Poi) -> void:
	var id := place.poi_id()
	if place.kind == "hoard" and not poi_looted.has(id):
		var guard_id := "islet-" + id.trim_prefix("hoard-")
		if _camp_guards.has(guard_id) and not _camp_guards[guard_id].is_empty():
			hud.toast("Raiders guard this hoard. Defeat their camp first (%d left)." % _camp_guards[guard_id].size())
			return
	if place.kind == "shrine":
		if int(shrine_days.get(id, -1)) == day:
			hud.toast("The shrine is quiet. Come back tomorrow.")
			return
		shrine_days[id] = day
		player.sanity = 100.0
		player.health = minf(player.health + 15.0, 100.0)
		audio.play("shrine")
		hud.open_dialog(place.display_name(), place.lore() + "\n\nYour mind clears. (Sanity restored, +15 health. Once a day.)",
			PackedStringArray(["Close"]), Callable())
		_save_timer = SAVE_INTERVAL - 1.0
		return
	if poi_looted.has(id):
		hud.open_dialog(place.display_name(), place.lore() + "\n\nThere's nothing left to take.",
			PackedStringArray(["Close"]), Callable())
		return
	var loot := place.loot()
	hud.open_dialog(place.display_name(), place.lore() + "\n\nYou find: %s." % _items_text(loot),
		PackedStringArray(["Take it"]), _on_poi_loot.bind(place))


func _on_poi_loot(_choice: int, _text: String, place: Poi) -> void:
	if not is_instance_valid(place) or poi_looted.has(place.poi_id()):
		return
	var loot := place.loot()
	for item in loot:
		player.add_item(item, int(loot[item]))
	poi_looted[place.poi_id()] = true
	place.looted = true
	place.refresh()
	audio.play("craft")
	hud.toast("You take: %s." % _items_text(loot))
	_save_timer = SAVE_INTERVAL - 1.0


## Everything the minimap and island map show.
func _map_markers() -> Dictionary:
	var items := []
	for b in buildings.values():
		var kind: String = "wall" if b.kind in Structure.LINES_UP else "building"
		items.append([kind, b.pos])
	for fire in campfires:
		items.append(["fire" if fire.is_lit() else "building", fire.pos])
	for t in traces:
		items.append([t.kind, t.pos])
	for data in world.pois:
		if poi_found.has(data["id"]):
			items.append(["poi_looted" if poi_looted.has(data["id"]) else "poi", world.cell_center(data["cell"]), data["name"]])
	if home != Vector2.INF:
		items.append(["home", home])
	for b in boats:
		items.append(["boat", b.pos])
	for h in tame_horses:
		if h != riding_horse:
			items.append(["horse", h.pos])
	# Raider camps on the islets you've found.
	for c in camps:
		if camps_found.has(c["id"]) and _camp_holds(c["id"]):
			items.append(["raiders", c["pos"]])
	var posts := {}
	for so in soldiers:
		if so.mode != "follow":
			posts[Vector2i(so.guard_point / 8.0)] = so.guard_point
	for p in posts.values():
		items.append(["soldiers", p])
	return {"player": player.pos, "facing": player.facing, "items": items}


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
	if kind in DEFENCES:
		_defences.append(b)
	elif kind == "field":
		_fields.append(b)
	_village_timer = 0.0
	_line_up_around(cell)
	if kind == "torch_post":
		var crackle := audio.make_fire_player()
		crackle.position = Vector3(0, 2.0, 0)
		crackle.volume_db = -12.0
		b.add_child(crackle)
		crackle.play(randf() * 5.0)
	return b


## Re-aligns walls and gates on a tile and its four neighbours.
func _line_up_around(cell: Vector2i) -> void:
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = cell + offset
		if buildings.has(c):
			buildings[c].line_up(world.structures)


func _remove_structure(cell: Vector2i) -> void:
	if buildings.has(cell):
		var b: Structure = buildings[cell]
		_defences.erase(b)
		_fields.erase(b)
		b.queue_free()
		buildings.erase(cell)
	world.remove_structure(cell)
	_village_timer = 0.0
	_line_up_around(cell)


func _set_build_mode(on: bool) -> void:
	build_mode = on
	if not on and _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_key = ""
	if on:
		hud.toast("Build mode: aim with the mouse, click or E to build, X to take down, B to finish.")


## Handles keys and clicks in build mode. Returns true if the event was used.
func _build_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var page: Array = Structure.PAGES[_build_page()]
		if key.physical_keycode == KEY_TAB:
			# Turn the page: walls and workshops, then defences and the village.
			var next: Array = Structure.PAGES[(_build_page() + 1) % Structure.PAGES.size()]
			build_index = Structure.ORDER.find(next[0])
			return true
		var n: int = key.physical_keycode - KEY_1
		if key.physical_keycode == KEY_0:
			n = 9
		elif key.physical_keycode == KEY_MINUS:
			n = 10
		elif key.physical_keycode == KEY_EQUAL:
			n = 11
		if n >= 0 and n < page.size():
			build_index = Structure.ORDER.find(page[n])
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


## Which build-menu page the chosen building is on.
func _build_page() -> int:
	var kind: String = Structure.ORDER[build_index]
	for i in Structure.PAGES.size():
		if kind in Structure.PAGES[i]:
			return i
	return 0


## The tile under the mouse, if it's close enough; otherwise the tile in front of you.
func _build_target() -> Vector2i:
	var here := world.cell_of(player.pos)
	# In first person you aim with the middle of the screen.
	var mouse := get_viewport().get_visible_rect().size / 2.0 if first_person else get_viewport().get_mouse_position()
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
	if kind == "dock" and not _next_to_water(cell):
		return "A dock must be at the water's edge."
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
	var built := _add_structure(kind, cell)
	built.built_ms = Time.get_ticks_msec()
	audio.play("build", world.to_3d(world.cell_center(cell)))
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
	if not purge.is_empty() and purge["vault"] == b:
		hud.toast("Not during the purge! Hold the vault.")
		return
	var refund := _refund(b)
	for item in refund:
		player.add_item(item, int(refund[item]))
	for item in b.items:
		player.add_item(item, int(b.items[item]))
	var back := "" if refund.is_empty() else " You get back %s." % _items_text(refund)
	hud.toast("You take down the %s.%s" % [b.display_name().to_lower(), back])
	audio.play("build", world.to_3d(world.cell_center(cell)), -4.0, 0.2)
	_remove_structure(cell)
	if b.kind == "tent" and home == world.cell_center(cell):
		home = Vector2.INF if campfires.is_empty() else campfires[-1].pos
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
	_ghost.cell = cell
	_ghost.line_up(world.structures)
	var names := PackedStringArray()
	var page: Array = Structure.PAGES[_build_page()]
	for i in page.size():
		var n: String = Structure.info(page[i])["name"]
		var key_name := "0" if i == 9 else ("-" if i == 10 else ("=" if i == 11 else str(i + 1)))
		names.append(("[%s %s]" if page[i] == kind else "%s %s") % [key_name, n])
	names.append("Tab: %s" % ("defences and village" if _build_page() == 0 else "walls and workshops"))
	var info: Dictionary = Structure.info(kind)
	hud.set_hint("%s\n%s: %s. %s  %s" % [
		"  ".join(names), info["name"], _items_text(info["cost"]), info["about"],
		_build_action_text(cell, problem)])


func _build_action_text(cell: Vector2i, problem: String) -> String:
	if buildings.has(cell):
		var b: Structure = buildings[cell]
		var refund := _refund(b)
		return "X: take down this %s (get back %s) · B done" % [b.display_name().to_lower(),
			_items_text(refund) if not refund.is_empty() else "nothing"]
	return problem if problem != "" else "Click or E to build · X take down · B done"


## What you get back for taking down a building: everything if you built it
## in the last minute (a mistake), otherwise half.
func _refund(b: Structure) -> Dictionary:
	var cost: Dictionary = Structure.info(b.kind)["cost"]
	var full: bool = b.built_ms >= 0 and Time.get_ticks_msec() - b.built_ms <= int(UNDO_SECONDS * 1000.0)
	var out := {}
	for item in cost:
		var n: int = int(cost[item]) if full else int(cost[item]) / 2
		if n > 0:
			out[item] = n
	return out


## X outside build mode: take down the building next to you, after asking.
func _ask_demolish() -> void:
	var near := _nearest(buildings.values(), player.pos, 30.0)
	if near == null:
		hud.toast("Stand next to one of your buildings and press X to take it down.")
		return
	var b := near as Structure
	if not purge.is_empty() and purge["vault"] == b:
		hud.toast("Not during the purge! Hold the vault.")
		return
	var refund := _refund(b)
	var stored := "" if b.items.is_empty() else "\n\nEverything stored inside comes back to you too."
	hud.open_dialog("Take down the %s?" % b.display_name().to_lower(),
		"You get back %s.%s" % [_items_text(refund) if not refund.is_empty() else "nothing", stored],
		PackedStringArray(["Take it down", "Keep it"]), _on_demolish_choice.bind(b))


func _on_demolish_choice(choice: int, _text: String, b: Structure) -> void:
	if choice == 0 and is_instance_valid(b) and buildings.get(b.cell) == b:
		_demolish(b.cell)


# ---------- Hotbar and inventory ----------

const HOTBAR := ["hands", "spear", "axe", "pickaxe", "sword"]


func _slot_pressed(event: InputEvent) -> int:
	for i in HOTBAR.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			return i
	return -1


## Picks a hotbar slot. Picking the slot already in hand puts it away.
func _on_hotbar_slot(i: int) -> void:
	var tool: String = HOTBAR[i]
	if not player.owns(tool):
		hud.toast("You don't have a %s yet. %s" % [tool, {
			"spear": "Craft one in the inventory (I).", "sword": "Forge one from iron at a forge.",
			"axe": "Make one at a workbench.", "pickaxe": "Make one at a workbench."}.get(tool, "")])
		return
	_equip(tool if player.equipped != tool else "hands")


func _equip(tool: String) -> void:
	if not player.equip(tool):
		return
	audio.play("ui", Vector3.INF, -8.0)
	if hud.is_inventory_open():
		_open_inventory()


func _hotbar_slots() -> Array:
	return [
		{"label": "Hands", "owned": true},
		{"label": _short(Gear.tier_name("spear", player.spear_tier), "Spear"), "owned": player.has_spear},
		{"label": "Axe", "owned": player.has_axe},
		{"label": "Pickaxe", "owned": player.has_pickaxe},
		{"label": _short(Gear.tier_name("sword", player.sword_tier), "Sword"), "owned": player.sword_tier >= 0},
	]


## "Steel spear" -> "Steel spear"; nothing yet -> the plain name.
static func _short(gear_name: String, fallback: String) -> String:
	return gear_name if gear_name != "" else fallback


func _open_inventory() -> void:
	var supplies := []
	for item in ["wood", "stone", "berries", "raw_meat", "cooked_meat", "smoked_meat", "ore", "iron", "steel", "hide", "salve", "gold"]:
		var n: int = player.count(item)
		var row := {"name": str(ITEM_NAMES[item]).capitalize(), "detail": "× %d" % n, "dim": n == 0}
		if item in ["berries", "raw_meat", "cooked_meat", "smoked_meat"]:
			row.merge({"button": "Eat", "action": "eat:" + item, "enabled": n > 0})
		elif item == "salve":
			row.merge({"button": "Use", "action": "salve", "enabled": n > 0 and player.health < 100.0})
		supplies.append(row)

	var gear := []
	for i in HOTBAR.size():
		var tool: String = HOTBAR[i]
		if tool == "hands" or not player.owns(tool):
			continue
		var held: bool = player.equipped == tool
		var label := tool.capitalize()
		var stat := ""
		if tool == "spear" or tool == "sword":
			var tier: int = player.spear_tier if tool == "spear" else player.sword_tier
			label = Gear.tier_name(tool, tier)
			stat = Gear.stat_text(tool, tier) + " · "
		gear.append({"name": label,
			"detail": stat + ("in hand" if held else "key %d" % (i + 1)),
			"button": "Put away" if held else "Equip", "action": "equip:" + ("hands" if held else tool)})
	if player.armour:
		gear.append({"name": Gear.tier_name("armour", player.armour_tier),
			"detail": "%s · %s" % [Gear.stat_text("armour", player.armour_tier), "worn" if player.armour_on else "packed"],
			"button": "Take off" if player.armour_on else "Wear", "action": "armour"})
	if player.lantern:
		gear.append({"name": "Lantern", "detail": "lit" if player.lantern_on else "shuttered",
			"button": "Shutter" if player.lantern_on else "Light", "action": "lantern"})
	if player.torch_time > 0.0:
		gear.append({"name": "Torch", "detail": "%d s left" % int(player.torch_time)})
	if riding_horse != null:
		gear.append({"name": "Saddlebags", "detail": "%d / %d" % [riding_horse.load_count(), Horse.CAPACITY],
			"button": "Open", "action": "bags"})

	var crafting := []
	for what in ["campfire", "torch"]:
		var cost: Dictionary = RECIPES[what]
		var done: bool = what == "torch" and player.torch_time > 0.0
		crafting.append({"name": what.capitalize() + {"campfire": "  (C)", "torch": "  (R)"}[what],
			"detail": _items_text(cost), "button": "Craft", "action": "craft:" + what,
			"enabled": player.can_afford(cost) and not done, "dim": done})
	for r in Gear.recipes_for("hand"):
		var have: bool = _gear_tier(r["kind"]) >= int(r["tier"])
		crafting.append({"name": r["name"], "detail": _items_text(r["cost"]), "button": "Craft", "action": "make:" + str(r["id"]),
			"enabled": player.can_afford(r["cost"]) and not have, "dim": have})

	hud.show_inventory([
		[{"title": "Supplies", "rows": supplies}],
		[{"title": "Weapons and tools", "rows": gear}, {"title": "Crafting", "rows": crafting}],
	], _on_inventory_action)


func _on_inventory_action(action: String) -> void:
	var parts := action.split(":")
	match parts[0]:
		"eat":
			_eat_item(parts[1])
		"salve":
			_use_salve()
		"equip":
			_equip(parts[1])
		"armour":
			player.armour_on = not player.armour_on
			hud.toast("You put on your armour." if player.armour_on else "You take off your armour.")
		"lantern":
			player.lantern_on = not player.lantern_on
			hud.toast("You light the lantern." if player.lantern_on else "You shutter the lantern.")
		"craft":
			if parts[1] == "campfire":
				hud.close_inventory()  # see where it goes
			_craft(parts[1])
		"make":
			_make_gear(parts[2], int(parts[3]))
		"bags":
			if riding_horse != null:
				_open_horse(riding_horse)
				return
	if hud.is_inventory_open():
		_open_inventory()


func _building_hint(b: Structure) -> String:
	var damaged: bool = b.hp < Structure.max_hp(b.kind) - 1.0
	match b.kind:
		"chest":
			return "E: open the chest"
		"tent":
			return "E: sleep until morning" if is_night() else "E: rest at your tent"
		"barracks":
			return "E: recruit soldiers (%d / %d)" % [soldiers.size(), _army_capacity()]
		"workbench", "forge", "smokehouse":
			return "E: use the %s" % b.display_name().to_lower()
		"vault":
			return "E: treasure vault (%d gold)" % _vault_gold(b)
		"field":
			if b.is_ripe():
				return "E: harvest the wheat"
			return "Wheat: %d%% grown%s" % [int(b.growth * 100.0), " (nothing grows in winter)" if world.season == "winter" else ""]
		"house":
			return "E: your village (%d settlers)" % settlers.size()
	if damaged:
		return "E: repair the %s (%d%%)" % [b.display_name().to_lower(), int(100.0 * b.hp / Structure.max_hp(b.kind))]
	return ""


func _use_building(b: Structure) -> void:
	match b.kind:
		"field":
			if b.is_ripe():
				_harvest_field(b, true)
			else:
				hud.toast("The wheat is %d%% grown. Farmers and settlers make it grow faster." % int(b.growth * 100.0))
			return
		"house":
			_open_village()
			return
		"vault":
			_open_vault(b)
			return
		"dock":
			_open_dock(b)
			return
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
		"workbench", "forge", "smokehouse":
			_open_station(b.kind)
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
	_camp_guards.clear()
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
		var n: int = player.count(item)
		if n > 0:
			b.items[item] = int(b.items.get(item, 0)) + n
			player.inventory[item] = 0


func _chest_take(b: Structure) -> void:
	for item in b.items:
		if ITEM_NAMES.has(item):
			player.add_item(item, int(b.items[item]))
	b.items = {}


# ---------- Treasure vault and the purge ----------

func _vault_gold(b: Structure) -> int:
	return int(b.items.get("gold", 0))


## The vault: put gold in or take it out, and start a purge once it holds enough.
func _open_vault(b: Structure) -> void:
	_vault_open = b
	var gold := _vault_gold(b)
	var running := not purge.is_empty()
	var why := ""
	if running:
		why = "A purge is under way."
	elif gold < PURGE_MIN_GOLD:
		why = "Needs %d gold inside." % PURGE_MIN_GOLD
	elif purged_day == day:
		why = "Once a day. Come back tomorrow."
	var waves := _purge_waves(gold)
	var rows := [
		{"name": "Gold in the vault", "detail": "%d" % gold},
		{"name": "Put in your gold", "detail": "you carry %d" % player.count("gold"), "button": "Deposit",
			"action": "deposit", "enabled": player.count("gold") > 0 and not running},
		{"name": "Take the gold out", "detail": "", "button": "Withdraw", "action": "withdraw", "enabled": gold > 0 and not running},
	]
	var purge_rows := [
		{"name": "Start the purge", "detail": why if why != "" else "%d waves of raiders" % waves, "button": "Start",
			"action": "purge", "enabled": why == ""},
		{"name": "If you hold them off", "detail": "+%d gold, and spoils" % (gold / 2)},
		{"name": "If they reach it", "detail": "they steal gold"},
	]
	hud.show_panel("Treasure vault", "Raiders smash through walls to reach the vault during a purge. More gold brings more waves.   Esc to close",
		[[{"title": "Gold", "rows": rows}], [{"title": "The purge", "rows": purge_rows}]], _on_vault_action)


func _on_vault_action(action: String) -> void:
	var b = _vault_open
	if b == null or not is_instance_valid(b):
		hud.close_inventory()
		return
	match action:
		"deposit":
			b.items["gold"] = _vault_gold(b) + player.count("gold")
			player.inventory["gold"] = 0
			audio.play("craft")
		"withdraw":
			player.add_item("gold", _vault_gold(b))
			b.items.erase("gold")
		"purge":
			hud.close_inventory()
			_start_purge(b)
			return
	_save_timer = SAVE_INTERVAL - 1.0
	_open_vault(b)


## How many waves a purge brings for this much gold.
static func _purge_waves(gold: int) -> int:
	return clampi(3 + (gold - PURGE_MIN_GOLD) / 75, 3, 6)


func _start_purge(b: Structure) -> bool:
	var gold := _vault_gold(b)
	if not purge.is_empty() or gold < PURGE_MIN_GOLD or purged_day == day:
		return false
	purged_day = day
	purge = {"vault": b, "wave": 0, "waves": _purge_waves(gold), "stake": gold, "stolen": 0, "timer": 8.0,
		"from": Vector2.from_angle(rng.randf() * TAU)}
	hud.toast("The purge begins! Raiders are gathering. Defend the vault: %d waves." % purge["waves"])
	audio.play("wolf_howl", world.to_3d(b.pos), 2.0, 0.0)
	_save_timer = SAVE_INTERVAL - 1.0
	return true


func _purge_side(v: Vector2) -> String:
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[int(round(v.angle() / (TAU / 8.0))) % 8]


func _spawn_purge_wave() -> void:
	var b: Structure = purge["vault"]
	purge["wave"] = int(purge["wave"]) + 1
	var wave: int = purge["wave"]
	var last: bool = wave == int(purge["waves"])
	# Each wave comes from a new side, bigger than the last; chiefs lead the final one.
	var from: Vector2 = (purge["from"] as Vector2).rotated(wave * 2.1)
	var muster := world.random_walkable_near(b.pos + from * 470.0, 4.0, 80.0, rng)
	if muster == Vector2.INF:
		muster = world.random_walkable_near(b.pos, 360.0, 520.0, rng)
	var count := mini(3 + wave * 2 + int(purge["stake"]) / 60, 16)
	var chiefs := (1 + int(purge["stake"]) / 120) if last else (1 if wave >= 3 else 0)
	var made := 0
	for k in count:
		var spot := world.random_walkable_near(muster, 4.0, 60.0, rng) if muster != Vector2.INF else Vector2.INF
		if spot == Vector2.INF:
			continue
		var r := _spawn_raider("raider_chief" if k < chiefs else "raider", spot)
		r.purge = true
		made += 1
	hud.toast("Wave %d of %d: %d raiders from the %s!" % [wave, purge["waves"], made, _purge_side(from)])
	audio.play("wolf_howl", world.to_3d(muster if muster != Vector2.INF else b.pos), 1.0, 0.0)


func _purge_raiders() -> Array:
	return wolves.filter(func(w): return w.is_raider() and w.purge)


## Runs the purge: waits, sends waves, and ends it when the last falls or the vault is empty.
func _tick_purge(delta: float) -> void:
	if purge.is_empty():
		hud.set_banner("")
		return
	var vault_ref = purge["vault"]
	if not is_instance_valid(vault_ref) or buildings.get((vault_ref as Structure).cell) != vault_ref:
		_end_purge(false, "The vault is gone. The raiders scatter with what they can carry.")
		return
	var b: Structure = vault_ref
	var left := _purge_raiders().size()
	# Stragglers who can't find a way in give up after a while.
	purge["wave_time"] = float(purge.get("wave_time", 0.0)) + delta
	if left > 0 and float(purge["wave_time"]) > PURGE_WAVE_GIVE_UP:
		for r in _purge_raiders():
			wolves.erase(r)
			r.queue_free()
		hud.toast("The rest of the wave loses heart and flees.")
		left = 0
	if left == 0:
		if int(purge["wave"]) >= int(purge["waves"]):
			_end_purge(true)
			return
		purge["timer"] = float(purge["timer"]) - delta
		if float(purge["timer"]) <= 0.0:
			_spawn_purge_wave()
			purge["wave_time"] = 0.0
			purge["timer"] = 12.0  # a breather before the next wave
	hud.set_banner("PURGE  ·  wave %d of %d  ·  %d raiders  ·  vault %d gold" % [
		maxi(int(purge["wave"]), 1), purge["waves"], left, _vault_gold(b)] if int(purge["wave"]) > 0 or left > 0
		else "PURGE  ·  raiders gather…  %ds  ·  vault %d gold" % [ceili(float(purge["timer"])), _vault_gold(b)])


## A raider at the vault grabs gold. If they empty it, the purge is lost.
func _purge_steal(r) -> void:
	var b: Structure = purge["vault"]
	var take := mini(PURGE_STEAL, _vault_gold(b))
	if take > 0:
		b.items["gold"] = _vault_gold(b) - take
		purge["stolen"] = int(purge["stolen"]) + take
		audio.play("hit", b.position, -4.0)
	if _vault_gold(b) <= 0:
		_end_purge(false, "The raiders emptied the vault and escape with %d gold." % purge["stolen"])


func _end_purge(won: bool, why: String = "") -> void:
	var b = purge.get("vault")
	var waves: int = purge.get("waves", 3)
	for r in _purge_raiders():
		wolves.erase(r)
		r.queue_free()
	if won and is_instance_valid(b):
		var bonus := int(purge["stake"]) / 2
		b.items["gold"] = _vault_gold(b) + bonus
		var spoils := {"iron": 4 * waves, "steel": waves, "hide": 2 * waves}
		for item in spoils:
			player.add_item(item, int(spoils[item]))
		audio.play("discover")
		hud.toast("The purge is over: you held the vault! +%d gold in the vault, and spoils: %s." % [bonus, _items_text(spoils)])
	else:
		hud.toast(why if why != "" else "The purge is over.")
	purge = {}
	hud.set_banner("")
	_save_timer = SAVE_INTERVAL - 1.0


# ---------- Defences ----------

## The nearest living wolf or raider within `radius` of `at`, or null.
func _nearest_enemy(at: Vector2, radius: float) -> Wolf:
	var best: Wolf = null
	var best_d := radius
	for w in wolves:
		if not w.dead:
			var d: float = w.pos.distance_to(at)
			if d < best_d:
				best_d = d
				best = w
	return best


## Archer towers shoot, spike traps stab, and oil gates scald.
func _tick_defences(delta: float) -> void:
	for b in _defences:
		b.cooldown = maxf(b.cooldown - delta, 0.0)
		if b.cooldown > 0.0 or wolves.is_empty():
			continue
		match b.kind:
			"archer_tower":
				var foe := _nearest_enemy(b.pos, Structure.TOWER_RANGE)
				if foe != null:
					b.cooldown = Structure.TOWER_COOLDOWN
					b.shoot(foe.position + Vector3(0, 0.6, 0))
					_defence_hit(foe, Structure.TOWER_DAMAGE, "Your archer tower brings down")
			"spike_trap":
				var foe := _nearest_enemy(b.pos, 11.0)
				if foe != null:
					b.cooldown = Structure.TRAP_COOLDOWN
					audio.play("hit", b.position, -6.0)
					_defence_hit(foe, Structure.TRAP_DAMAGE, "Your spike trap brings down")
			"oil_gate":
				if _nearest_enemy(b.pos, Structure.OIL_RANGE) != null:
					b.cooldown = Structure.OIL_COOLDOWN
					b.pour()
					audio.play("hurt", b.position, -8.0)
					for w in wolves.duplicate():
						if not w.dead and w.pos.distance_to(b.pos) < Structure.OIL_RANGE:
							_defence_hit(w, Structure.OIL_DAMAGE, "Boiling oil brings down")


func _defence_hit(foe: Wolf, amount: int, by: String) -> void:
	foe.hurt(amount, foe.pos - foe.facing)
	if foe.hp <= 0 and wolves.has(foe):
		_kill_wolf(foe, true, by)


# ---------- Soldiers at work ----------

func _count_job(job: String) -> int:
	return soldiers.filter(func(so): return so.mode == "work" and so.job == job).size()


func _idle_soldiers() -> Array:
	return soldiers.filter(func(so): return not so.dead and so.mode != "work" and so.kind != "centurion")


func _barracks_near(at: Vector2) -> Structure:
	return _nearest(buildings.values().filter(func(b): return b.kind == "barracks"), at, 99999.0) as Structure


## Legionaries go to work first, then whoever is nearest the barracks.
func _better_worker(a: Soldier, b: Soldier, at: Vector2) -> bool:
	if (a.kind == "legionary") != (b.kind == "legionary"):
		return a.kind == "legionary"
	return a.pos.distance_to(at) < b.pos.distance_to(at)


## Somewhere to work near `from`: [where to stand, what to work on], or [].
## Each tree, rock or field gets one worker.
func _find_work(job: String, from: Vector2) -> Array:
	var taken := {}
	for so in soldiers:
		if so.mode == "work":
			taken[so.work_at] = true
	if job == "farm":
		var best: Structure = null
		var best_d := WORK_RADIUS * 1.5
		for f in _fields:
			var d: float = f.pos.distance_to(from)
			if d < best_d and not taken.has(f.pos):
				best_d = d
				best = f
		return [best.pos + Vector2(0, 5), best.pos] if best != null else []
	var want := "tree" if job == "wood" else "rock"
	var c0 := world.cell_of(from)
	var r := int(WORK_RADIUS / World.TILE)
	var best_at := Vector2.INF
	var best_stand := Vector2.INF
	var best_r := float(r)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := Vector2(dx, dy).length()
			if dist >= best_r:
				continue
			var c := c0 + Vector2i(dx, dy)
			if world.prop_type(c) != want:
				continue
			var at := world.cell_center(c)
			if taken.has(at):
				continue
			for side in [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]:
				var stand: Vector2 = at + side * 13.0
				if world.is_walkable(stand):
					best_r = dist
					best_at = at
					best_stand = stand
					break
	return [best_stand, best_at] if best_at != Vector2.INF else []


## Puts one more soldier to work at `job` (n > 0), or calls one back (n < 0).
func _set_job(job: String, n: int) -> bool:
	if not JOBS.has(job):
		return false
	if n < 0:
		var workers := soldiers.filter(func(so): return so.mode == "work" and so.job == job)
		if workers.is_empty():
			return false
		var back: Soldier = workers[-1]
		back.mode = army_mode
		back.job = ""
		back.guard_point = player.pos
		_reassign_slots()
		_save_timer = SAVE_INTERVAL - 1.0
		return true
	var barracks := _barracks_near(player.pos)
	if barracks == null:
		hud.toast("Build a barracks first.")
		return false
	var idle := _idle_soldiers()
	if idle.is_empty():
		hud.toast("No idle soldiers. Recruit more, or call some back from other jobs.")
		return false
	# Legionaries first, then whoever is nearest the barracks.
	idle.sort_custom(_better_worker.bind(barracks.pos))
	var site := _find_work(job, barracks.pos)
	if site.is_empty():
		hud.toast({"wood": "No free trees near your barracks.", "stone": "No free rocks near your barracks.",
			"farm": "Every field near your barracks has a farmer. Build more fields (B, then Tab)."}[job])
		return false
	var s: Soldier = idle[0]
	s.mode = "work"
	s.job = job
	s.guard_point = site[0]
	s.work_at = site[1]
	selected.erase(s)
	s.set_selected(false)
	_reassign_slots()
	hud.toast("%s goes to work as a %s." % [s.soldier_name, JOBS[job]["one"]])
	_save_timer = SAVE_INTERVAL - 1.0
	return true


## A stroke of the axe, pick or hoe.
func _work_stroke(s: Soldier) -> void:
	var lost := false
	match s.job:
		"wood", "stone":
			lost = world.prop_type(world.cell_of(s.work_at)) != ("tree" if s.job == "wood" else "rock")
			if not lost:
				_store_produce(JOBS[s.job]["gives"], s.pos)
		"farm":
			var f: Structure = buildings.get(world.cell_of(s.work_at))
			lost = f == null or f.kind != "field"
			if not lost:
				if f.is_ripe():
					_harvest_field(f, false)
				elif world.season != "winter":
					f.set_growth(f.growth + FARMER_TEND / Structure.GROW_TIME)
	if lost:
		# The tree was felled or the field taken up: find another, or come back.
		var site := _find_work(s.job, s.pos)
		if site.is_empty():
			hud.toast("%s has no more work as a %s and rejoins the army." % [s.soldier_name, JOBS[s.job]["one"]])
			s.mode = army_mode
			s.job = ""
			s.guard_point = player.pos
			_reassign_slots()
		else:
			s.guard_point = site[0]
			s.work_at = site[1]


## Puts what workers make into the chest nearest them, or your pack if you have no chest.
func _store_produce(items: Dictionary, near: Vector2) -> void:
	var chest: Structure = _nearest(buildings.values().filter(func(b): return b.kind == "chest"), near, 900.0)
	for item in items:
		if chest != null:
			chest.items[item] = int(chest.items.get(item, 0)) + int(items[item])
		else:
			player.add_item(item, int(items[item]))


# ---------- Farms and the village ----------

func _harvest_field(f: Structure, by_you: bool) -> void:
	if not f.is_ripe():
		return
	f.set_growth(0.0)
	if by_you:
		player.add_item("wheat", Structure.FIELD_YIELD)
		audio.play("pick", f.position, -4.0)
		hud.toast("You harvest %d wheat and sow the field again. Bake bread at a smokehouse." % Structure.FIELD_YIELD)
	else:
		_store_produce({"wheat": Structure.FIELD_YIELD}, f.pos)
	_save_timer = SAVE_INTERVAL - 1.0


## Fields grow; settlers wander, tend the wheat and hide from danger.
func _tick_village(delta: float) -> void:
	var growing := world.season != "winter"
	if growing:
		for f in _fields:
			if not f.is_ripe():
				f.set_growth(f.growth + delta / Structure.GROW_TIME)
	if settlers.is_empty():
		return
	_village_timer -= delta
	if _village_timer <= 0.0:
		_village_timer = 3.0
		_village_spots = []
		for b in buildings.values():
			if b.kind in ["field", "house", "chest", "smokehouse"]:
				_village_spots.append(b.pos)
			if b.kind == "field":
				_village_spots.append(b.pos)  # fields count twice: that's where the work is
	var field_spots := _fields.map(func(f): return f.pos)
	for st in settlers:
		var foe := _nearest_enemy(st.pos, Settler.DANGER)
		st.tick(delta, foe.pos if foe != null else Vector2.INF, _village_spots, field_spots)
		if st.tending:
			var f: Structure = _nearest(_fields, st.pos, 14.0)
			if f != null:
				if f.is_ripe():
					_harvest_field(f, false)
				elif growing:
					f.set_growth(f.growth + delta / Structure.GROW_TIME)  # tended wheat grows twice as fast


## How much food your chests hold that settlers will eat.
func _food_in_store() -> int:
	var n := 0
	for b in buildings.values():
		if b.kind == "chest":
			for item in SETTLER_FOODS:
				n += int(b.items.get(item, 0))
	return n


## Takes up to `n` food from your chests. Returns how much it found.
func _take_food(n: int) -> int:
	var got := 0
	for item in SETTLER_FOODS:
		for b in buildings.values():
			if got >= n:
				return got
			if b.kind == "chest" and int(b.items.get(item, 0)) > 0:
				var take := mini(int(b.items[item]), n - got)
				b.items[item] = int(b.items[item]) - take
				if int(b.items[item]) <= 0:
					b.items.erase(item)
				got += take
	return got


## Each morning settlers eat from your chests and pay their taxes; hungry ones
## leave, and newcomers move into empty beds if there's food to spare.
func _village_dawn() -> void:
	var houses := buildings.values().filter(func(b): return b.kind == "house")
	if houses.is_empty() and settlers.is_empty():
		return
	var fed := 0
	var gone := PackedStringArray()
	for st in settlers.duplicate():
		if _take_food(SETTLER_FOOD) >= SETTLER_FOOD:
			fed += 1
		else:
			gone.append(st.settler_name)
			settlers.erase(st)
			st.queue_free()
	taxes_last = fed * SETTLER_TAX
	var vault: Structure = _nearest(buildings.values().filter(func(b): return b.kind == "vault"), player.pos, 99999.0)
	if taxes_last > 0:
		if vault != null:
			vault.items["gold"] = _vault_gold(vault) + taxes_last
		else:
			player.add_item("gold", taxes_last)
	var arrived := PackedStringArray()
	var beds := houses.size() * HOUSE_BEDS - settlers.size()
	for k in mini(beds, 2):
		if _food_in_store() < SETTLER_FOOD * 2:
			break
		var house: Structure = _emptiest_house(houses)
		var spot := world.random_walkable_near(house.pos, 14.0, 30.0, rng)
		var st := _spawn_settler(_settler_name(), rng.randi() % 6, spot if spot != Vector2.INF else house.pos, house.pos, Settler.MAX_HP)
		arrived.append(st.settler_name)
	var news := PackedStringArray()
	if fed > 0:
		news.append("%d settler%s fed, %d gold in taxes%s." % [fed, "" if fed == 1 else "s", taxes_last, " (in the vault)" if vault != null else ""])
	if not gone.is_empty():
		news.append("%s left: there was no food in your chests." % ", ".join(gone))
	if not arrived.is_empty():
		news.append("%s moved into the village." % ", ".join(arrived))
	elif beds > 0 and _food_in_store() < SETTLER_FOOD * 2:
		news.append("Empty beds wait, but nobody will come until your chests hold food.")
	if not news.is_empty():
		hud.toast("The village: " + " ".join(news))


func _emptiest_house(houses: Array) -> Structure:
	var best: Structure = houses[0]
	var best_n := 999
	for h in houses:
		var n := settlers.filter(func(st): return st.home == h.pos).size()
		if n < best_n:
			best_n = n
			best = h
	return best


func _settler_name() -> String:
	var used := settlers.map(func(st): return st.settler_name)
	var free := Array(Settler.NAMES).filter(func(n): return not n in used)
	if free.is_empty():
		return "%s the Younger" % Settler.NAMES[rng.randi() % Settler.NAMES.size()]
	return free[rng.randi() % free.size()]


func _spawn_settler(settler_name: String, look: int, at: Vector2, home_pos: Vector2, hp: float) -> Settler:
	var st: Settler = Settler.new()
	st.world = world
	st.settler_name = settler_name
	st.look = look
	st.pos = at
	st.home = home_pos
	st.hp = clampf(hp, 1.0, Settler.MAX_HP)
	entities.add_child(st)
	settlers.append(st)
	_village_timer = 0.0
	return st


func _on_settler_fallen(st: Settler) -> void:
	settlers.erase(st)
	get_tree().create_timer(3.0).timeout.connect(st.queue_free)
	hud.toast("%s, one of your settlers, has been killed. Guard the village!" % st.settler_name)


func _export_settlers() -> Array:
	var out := []
	for st in settlers:
		out.append([st.settler_name, st.look, snappedf(st.pos.x, 0.1), snappedf(st.pos.y, 0.1),
			snappedf(st.home.x, 0.1), snappedf(st.home.y, 0.1), snappedf(st.hp, 0.1)])
	return out


## E at a cottage: who lives in the village, and how it's fed.
func _open_village() -> void:
	var houses := _count("house")
	var ripe := _fields.filter(func(f): return f.is_ripe()).size()
	var about := [
		{"name": "Cottages", "detail": "%d  (%d beds)" % [houses, houses * HOUSE_BEDS]},
		{"name": "Settlers", "detail": "%d" % settlers.size()},
		{"name": "Food in your chests", "detail": "%d  (they eat %d a day)" % [_food_in_store(), settlers.size() * SETTLER_FOOD]},
		{"name": "Taxes this morning", "detail": "%d gold" % taxes_last},
		{"name": "Fields", "detail": "%d  (%d ripe)" % [_fields.size(), ripe]},
		{"name": "Farmers", "detail": "%d" % _count_job("farm")},
	]
	var people := []
	for st in settlers:
		people.append({"name": st.settler_name, "detail": "hiding at home" if st.hidden else "%d%% health" % int(100.0 * st.hp / Settler.MAX_HP)})
	if people.is_empty():
		people.append({"name": "Nobody yet", "detail": "they come at dawn", "dim": true})
	hud.show_panel("Village", "Each morning settlers eat %d food from your chests (wheat, bread, berries or meat) and pay %d gold, into your vault if you have one. Wolves and raiders hunt them: they run home when danger comes.   Esc to close" % [SETTLER_FOOD, SETTLER_TAX],
		[[{"title": "Your village", "rows": about}], [{"title": "Settlers", "rows": people}]], _on_village_action)


func _on_village_action(_action: String) -> void:
	pass


# ---------- Horses ----------

## Where wild herds graze: meadows around the island, one near the start so
## you meet horses early. Worked out from the island's seed.
func _make_herds() -> void:
	herds.clear()
	var fixed := RandomNumberGenerator.new()
	fixed.seed = world.seed_value * 29 + 11
	var half := World.SIZE / 2
	var tries := 0
	while herds.size() < HERDS and tries < 4000:
		tries += 1
		var near_start := herds.is_empty() and tries < 1500
		var cell: Vector2i
		if near_start:
			var a := fixed.randf() * TAU
			var d := fixed.randf_range(30.0, 60.0)
			cell = world.spawn_cell + Vector2i(int(cos(a) * d), int(sin(a) * d))
		else:
			var r := sqrt(fixed.randf()) * half * 0.85
			var a2 := fixed.randf() * TAU
			cell = Vector2i(half + int(cos(a2) * r), half + int(sin(a2) * r))
		if world.terrain_at(cell) != World.GRASS:
			continue
		var spot := world.cell_center(cell)
		if not world.is_walkable(spot):
			continue
		var crowded := false
		for h in herds:
			if (h["pos"] as Vector2).distance_to(spot) < 1200.0:
				crowded = true
		for c in camps:
			if (c["pos"] as Vector2).distance_to(spot) < 700.0:
				crowded = true
		if not crowded:
			herds.append({"id": "herd-%d" % herds.size(), "pos": spot})


## Wild horses appear as you come near their meadow; tame ones are always there.
func _tick_horses(delta: float) -> void:
	for h in herds:
		var at: Vector2 = h["pos"]
		var dist := at.distance_to(player.pos)
		for j in HERD_SIZE:
			var id := "%s:%d" % [h["id"], j]
			if dist < 800.0 and not _wild_horses.has(id) and not horses_taken.has(id):
				var spot := world.random_walkable_near(at, 4.0, 50.0, rng)
				if spot != Vector2.INF:
					_wild_horses[id] = _spawn_horse(spot, abs(hash(id)) % Horse.COATS.size(), true, id, at)
			elif dist > 1300.0 and _wild_horses.has(id):
				_wild_horses[id].queue_free()
				_wild_horses.erase(id)
	for horse in _wild_horses.values():
		horse.tick(delta)
	for horse in tame_horses:
		if horse != riding_horse:
			horse.tick(delta)


func _spawn_horse(at: Vector2, coat: int, wild: bool, id: String = "", home_pos: Vector2 = Vector2.ZERO) -> Horse:
	var horse: Horse = Horse.new()
	horse.world = world
	horse.pos = at
	horse.coat = coat
	horse.wild = wild
	horse.herd_id = id
	horse.home = home_pos if wild else at
	horse.facing = Vector2.from_angle(float(abs(hash(id + str(at))) % 628) / 100.0)
	entities.add_child(horse)
	return horse


## E by a horse: feed a wild one (berries win its trust), or ride a tame one.
func _use_horse(horse: Horse) -> void:
	if not horse.wild:
		_open_horse(horse)
		return
	if tame_horses.size() >= MAX_TAME_HORSES:
		hud.toast("You have all the horses you can look after (%d)." % MAX_TAME_HORSES)
		return
	if player.count("berries") < Horse.BERRIES_PER_FEED:
		hud.toast("The horse eyes you warily. Offer it %d berries to win its trust." % Horse.BERRIES_PER_FEED)
		return
	player.add_item("berries", -Horse.BERRIES_PER_FEED)
	audio.play("eat", horse.position, -4.0)
	if horse.feed():
		_wild_horses.erase(horse.herd_id)
		horses_taken[horse.herd_id] = true
		tame_horses.append(horse)
		audio.play("discover")
		hud.toast("The horse trusts you now. Press E by it to ride.")
		_save_timer = SAVE_INTERVAL - 1.0
	else:
		hud.toast("It eats from your hand. (Trust %d / %d)" % [horse.trust, Horse.FEEDS_TO_TAME])


## Your horse: ride it, or move things between your pack and its saddlebags.
func _open_horse(horse: Horse) -> void:
	_horse_open = horse
	var actions := []
	if riding_horse == null:
		actions.append({"name": "Ride", "detail": "almost twice as fast", "button": "Ride", "action": "ride"})
	actions.append({"name": "Store everything", "detail": "", "button": "Store all", "action": "store_all",
		"enabled": horse.room() > 0 and _carried() > 0})
	actions.append({"name": "Take everything", "detail": "", "button": "Take all", "action": "take_all",
		"enabled": not horse.items.is_empty()})
	var pack := []
	for item in player.inventory:
		var n := player.count(item)
		if n > 0:
			pack.append({"name": str(ITEM_NAMES.get(item, item)).capitalize(), "detail": "× %d" % n, "button": "Store",
				"action": "store:" + str(item), "enabled": horse.room() > 0})
	var bags := []
	for item in horse.items:
		bags.append({"name": str(ITEM_NAMES.get(item, item)).capitalize(), "detail": "× %d" % int(horse.items[item]),
			"button": "Take", "action": "take:" + str(item)})
	hud.show_panel("Your horse", "Saddlebags: %d / %d   ·   Esc to close" % [horse.load_count(), Horse.CAPACITY],
		[[{"title": "Horse", "rows": actions}, {"title": "You carry", "rows": pack}],
		[{"title": "Saddlebags", "rows": bags}]], _on_horse_action)


func _on_horse_action(action: String) -> void:
	var horse := _horse_open
	if horse == null or not is_instance_valid(horse):
		hud.close_inventory()
		return
	var parts := action.split(":")
	match parts[0]:
		"ride":
			hud.close_inventory()
			_mount(horse)
			return
		"store_all":
			for item in player.inventory.keys():
				_store_in_horse(horse, item, player.count(item))
		"take_all":
			for item in horse.items.keys():
				_take_from_horse(horse, item, int(horse.items[item]))
		"store":
			_store_in_horse(horse, parts[1], player.count(parts[1]))
		"take":
			_take_from_horse(horse, parts[1], int(horse.items.get(parts[1], 0)))
	audio.play("ui", Vector3.INF, -8.0)
	_save_timer = SAVE_INTERVAL - 1.0
	_open_horse(horse)


## Moves up to `n` of an item into the saddlebags, as far as there's room.
func _store_in_horse(horse: Horse, item: String, n: int) -> int:
	var moved := mini(n, horse.room())
	if moved <= 0:
		return 0
	player.add_item(item, -moved)
	horse.items[item] = int(horse.items.get(item, 0)) + moved
	return moved


func _take_from_horse(horse: Horse, item: String, n: int) -> int:
	var moved := mini(n, int(horse.items.get(item, 0)))
	if moved <= 0:
		return 0
	horse.items[item] = int(horse.items[item]) - moved
	if int(horse.items[item]) <= 0:
		horse.items.erase(item)
	player.add_item(item, moved)
	return moved


func _carried() -> int:
	var n := 0
	for item in player.inventory:
		n += player.count(item)
	return n


func _mount(horse: Horse) -> void:
	if sailing != null or riding_horse != null:
		return
	riding_horse = horse
	horse.visible = false
	player.pos = horse.pos
	player.facing = horse.facing
	player.mount(true, Horse.COATS[horse.coat % Horse.COATS.size()])
	hud.toast("You swing into the saddle. You ride almost twice as fast. E to dismount.")


func _dismount() -> void:
	if riding_horse == null:
		return
	var horse := riding_horse
	riding_horse = null
	player.mount(false)
	horse.pos = player.pos
	horse.facing = player.facing
	horse.visible = true
	# Step off beside the horse.
	for side in [Vector2(14, 0), Vector2(-14, 0), Vector2(0, 14), Vector2(0, -14)]:
		var off: Vector2 = player.facing.orthogonal() * side.x + player.facing * side.y
		if world.is_walkable(player.pos + off):
			player.pos += off
			break
	_save_timer = SAVE_INTERVAL - 1.0


func _export_horses() -> Array:
	var out := []
	for h in tame_horses:
		var at: Vector2 = player.pos if h == riding_horse else h.pos  # the one you ride is where you are
		out.append([snappedf(at.x, 0.1), snappedf(at.y, 0.1), h.coat, h.items.duplicate()])
	return out


func _tick_riding() -> void:
	if riding_horse != null:
		riding_horse.pos = player.pos
		riding_horse.facing = player.facing


# ---------- Boats ----------

func _next_to_water(cell: Vector2i) -> bool:
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var t := world.terrain_at(cell + d)
		if t == World.WATER or t == World.DEEP:
			return true
	return false


func _boat_of(kind: String) -> Boat:
	for b in boats:
		if b.kind == kind:
			return b
	return null


func _open_dock(dock: Structure) -> void:
	var lines := PackedStringArray()
	var actions := []
	var buttons := PackedStringArray()
	for kind in ["raft", "galley"]:
		var info: Dictionary = Boat.info(kind)
		var owned := _boat_of(kind)
		if owned == null:
			lines.append("%s (%s): %s" % [info["name"], _items_text(info["cost"]), info["about"]])
			buttons.append("Build %s" % str(info["name"]).to_lower())
			actions.append("build:" + kind)
		else:
			lines.append("%s: yours.%s" % [info["name"], "" if owned.pos.distance_to(dock.pos) < 60.0 else " Moored far away."])
			buttons.append("Board %s" % str(info["name"]).to_lower())
			actions.append("board:" + kind)
	buttons.append("Close")
	actions.append("")
	hud.open_dialog("Dock", "\n\n".join(lines) + "\n\nA raft keeps to lakes and the shallows. Only a galley crosses the open sea to the islets.",
		buttons, _on_dock_choice.bind(dock, actions))


func _on_dock_choice(choice: int, _text: String, dock: Structure, actions: Array) -> void:
	if choice < 0 or choice >= actions.size() or str(actions[choice]) == "":
		return
	var parts := str(actions[choice]).split(":")
	if parts[0] == "build":
		_build_boat(parts[1], dock)
	else:
		var boat := _boat_of(parts[1])
		if boat:
			boat.pos = _launch_point(dock, boat.can_cross_deep())  # boats come round to the dock when you call them
			_board(boat)


## The water beside a dock, where boats are launched.
func _launch_point(dock: Structure, deep_ok: bool = true) -> Vector2:
	var out := dock.water_direction()
	for dist in [26.0, 34.0, 42.0, 50.0]:
		var p: Vector2 = dock.pos + out * dist
		if world.is_sailable(p, deep_ok):
			return p
	return dock.pos + out * 26.0


func _build_boat(kind: String, dock: Structure) -> Boat:
	var cost: Dictionary = Boat.info(kind)["cost"]
	if _boat_of(kind) != null:
		hud.toast("You already have a %s." % kind)
		return null
	if not player.can_afford(cost):
		hud.toast("A %s needs %s." % [kind, _items_text(cost)])
		return null
	var deep_ok: bool = Boat.info(kind)["deep"]
	var at := _launch_point(dock, deep_ok)
	if not world.is_sailable(at, deep_ok):
		hud.toast("The water by this dock is frozen. Wait for spring." if world.season == "winter" else "There's no open water by this dock.")
		return null
	player.pay(cost)
	var boat := _spawn_boat(kind, at, dock.water_direction())
	audio.play("build", world.to_3d(dock.pos))
	hud.toast("Your %s is ready at the dock. Press E by it to go aboard." % boat.display_name().to_lower())
	_save_timer = SAVE_INTERVAL - 1.0
	return boat


func _spawn_boat(kind: String, at: Vector2, facing: Vector2) -> Boat:
	var boat: Boat = Boat.new()
	boat.world = world
	boat.kind = "galley" if kind == "galley" else "raft"
	boat.pos = at
	boat.facing = facing if facing.length() > 0.1 else Vector2.DOWN
	entities.add_child(boat)
	boats.append(boat)
	return boat


func _board(boat: Boat) -> void:
	if sailing != null:
		return
	if riding_horse != null:
		_dismount()  # the horse waits on the shore
	if not world.is_sailable(boat.pos, boat.can_cross_deep()) and world.is_ice(world.cell_of(boat.pos)):
		hud.toast("Your %s is frozen in the ice until spring." % boat.display_name().to_lower())
		return
	sailing = boat
	boat.crewed = true
	player.on_boat = true
	player.boat_deep = boat.can_cross_deep()
	player.boat_speed = boat.speed_factor()
	player.deck_height = boat.deck_height()
	player.pos = boat.pos
	player.facing = boat.facing
	hud.toast("You push off in the %s. E to go ashore." % boat.display_name().to_lower())


## Steps off the boat onto the nearest land. The boat stays moored there.
func _go_ashore() -> bool:
	if sailing == null:
		return false
	var landing := Vector2.INF
	for r in [18.0, 26.0, 34.0, 42.0, 52.0]:
		for i in 16:
			var p: Vector2 = player.pos + Vector2.from_angle(i * TAU / 16.0) * r
			if world.is_walkable(p):
				landing = p
				break
		if landing != Vector2.INF:
			break
	if landing == Vector2.INF:
		hud.toast("There's no shore close enough. Sail closer to land.")
		return false
	var boat := sailing
	_leave_boat()
	player.pos = landing
	# The legion sails with you on a galley, and comes ashore behind you.
	if boat.kind == "galley":
		var landed := 0
		for so in soldiers:
			if so.mode == "follow" and so.pos.distance_to(landing) > 200.0:
				var spot := world.random_walkable_near(landing, 12.0, 70.0, rng)
				if spot != Vector2.INF:
					so.pos = spot
					landed += 1
		if landed > 0:
			hud.toast("Your legion comes ashore.")
	var isle := world.islet_at(world.cell_of(landing))
	if isle >= 0:
		hud.toast("You land on %s." % world.islets[isle]["name"])
	return true


func _leave_boat() -> void:
	if sailing == null:
		return
	sailing.pos = player.pos
	sailing.facing = player.facing
	sailing.crewed = false
	sailing = null
	player.on_boat = false


func _leave_boat_if_frozen() -> void:
	if sailing != null and world.is_ice(world.cell_of(player.pos)):
		_leave_boat()
		hud.toast("The water freezes around your boat. You climb out onto the ice.")


func _tick_boat() -> void:
	if sailing != null:
		sailing.pos = player.pos
		sailing.facing = player.facing


# ---------- Army ----------

func _army_capacity() -> int:
	return mini(Soldier.MAX_ARMY, Soldier.PER_BARRACKS * _count("barracks"))


func _count_kind(kind: String) -> int:
	var n := 0
	for s in soldiers:
		if s.kind == kind:
			n += 1
	return n


## The barracks: recruit each kind of soldier, and see your veterans.
func _open_barracks() -> void:
	var units := []
	for kind in ["legionary", "archer", "cavalry", "centurion"]:
		var info: Dictionary = Soldier.info(kind)
		var cost: Dictionary = info["cost"]
		var room := soldiers.size() < _army_capacity()
		var allowed: bool = kind != "centurion" or _count_kind("centurion") < _count("barracks")
		units.append({"name": str(info["name"]), "detail": _items_text(cost), "button": "Recruit 1",
			"action": "recruit:%s:1" % kind, "enabled": room and allowed and player.can_afford(cost)})
		if kind != "centurion":
			var five := {}
			for item in cost:
				five[item] = int(cost[item]) * 5
			units.append({"name": "", "detail": "", "button": "Recruit 5", "action": "recruit:%s:5" % kind,
				"enabled": room and player.can_afford(five)})
	var roster := []
	for kind in ["legionary", "archer", "cavalry", "centurion"]:
		roster.append({"name": str(Soldier.info(kind)["name"]) + "s", "detail": "× %d" % _count_kind(kind), "dim": _count_kind(kind) == 0})
	roster.append({"name": "Army", "detail": "%d / %d" % [soldiers.size(), _army_capacity()]})
	var veterans := soldiers.filter(func(so): return so.kills > 0)
	veterans.sort_custom(func(a, b): return a.kills > b.kills)
	var best := []
	for so in veterans.slice(0, 6):
		best.append({"name": so.soldier_name, "detail": "%s · %d kill%s" % [so.rank_name(), so.kills, "" if so.kills == 1 else "s"]})
	var about := []
	for kind in ["legionary", "archer", "cavalry", "centurion"]:
		about.append({"name": str(Soldier.info(kind)["name"]), "detail": str(Soldier.info(kind)["about"]).left(34) + "…"})
	var work := []
	var idle := _idle_soldiers().size()
	for job in JOBS:
		var n := _count_job(job)
		work.append({"name": str(JOBS[job]["name"]), "detail": "× %d" % n, "button": "Add one", "action": "job:%s:1" % job,
			"enabled": idle > 0})
		work.append({"name": "", "detail": "", "button": "Call one back", "action": "job:%s:-1" % job, "enabled": n > 0})
	work.append({"name": "Idle soldiers", "detail": "%d" % idle})
	work.append({"name": "Woodcutters and quarrymen", "detail": "3 a stroke, to a chest"})
	work.append({"name": "Farmers", "detail": "tend and harvest fields"})
	hud.show_panel("Barracks", "Each barracks houses %d soldiers, and one centurion. Kills make veterans: Veteran at 3, Elite at 8, Hero at 15. Workers fill your nearest chest (or your pack); T doesn't call them away.   Esc to close" % Soldier.PER_BARRACKS,
		[[{"title": "Recruit", "rows": units}], [{"title": "Work", "rows": work}],
			[{"title": "Your legion", "rows": roster}, {"title": "Most decorated", "rows": best}]],
		_on_barracks_action)


func _on_barracks_action(action: String) -> void:
	var parts := action.split(":")
	if parts.size() == 3 and parts[0] == "job":
		_set_job(parts[1], parts[2].to_int())
	if parts.size() == 3 and parts[0] == "recruit":
		var got := _recruit(parts[2].to_int(), parts[1])
		if got > 0:
			hud.toast("%d %s%s joined your army." % [got, str(Soldier.info(parts[1])["name"]).to_lower(), "" if got == 1 else "s"])
	if hud.is_inventory_open():
		_open_barracks()


## Recruits up to `n` soldiers of a kind. Returns how many joined.
func _recruit(n: int, kind: String = "legionary") -> int:
	var barracks: Structure = _nearest(buildings.values().filter(func(b): return b.kind == "barracks"), player.pos, 99999.0)
	if barracks == null:
		hud.toast("Build a barracks first.")
		return 0
	var cost: Dictionary = Soldier.info(kind)["cost"]
	var joined := 0
	for i in n:
		if soldiers.size() >= _army_capacity():
			hud.toast("No room: build another barracks (each houses %d)." % Soldier.PER_BARRACKS)
			break
		if kind == "centurion" and _count_kind("centurion") >= _count("barracks"):
			hud.toast("One centurion per barracks.")
			break
		if not player.can_afford(cost):
			hud.toast("Each %s needs %s." % [str(Soldier.info(kind)["name"]).to_lower(), _items_text(cost)])
			break
		player.pay(cost)
		var spot := world.random_walkable_near(barracks.pos, 16.0, 40.0, rng)
		_spawn_soldier(spot if spot != Vector2.INF else player.pos, -1.0, army_mode, player.pos, kind)
		joined += 1
	if joined > 0:
		_reassign_slots()
		_save_timer = SAVE_INTERVAL - 1.0
	return joined


func _spawn_soldier(pos: Vector2, hp: float, mode: String, guard_point: Vector2, kind: String = "legionary",
		soldier_name: String = "", kills: int = 0) -> Soldier:
	var s: Soldier = Soldier.new()
	s.world = world
	s.kind = kind if Soldier.KINDS.has(kind) else "legionary"
	s.soldier_name = soldier_name if soldier_name != "" else Soldier.random_name(rng)
	s.kills = maxi(kills, 0)
	s.pos = pos
	s.hp = s.max_hp() if hp <= 0.0 else clampf(hp, 1.0, s.max_hp())
	s.mode = mode if mode in ["follow", "guard", "hold", "work"] else "follow"
	s.guard_point = guard_point
	s.formation = formation
	s.slot = soldiers.size()
	entities.add_child(s)
	soldiers.append(s)
	return s


## T: the whole army follows you, or (if it was following) guards this spot.
func _toggle_army_mode() -> void:
	if soldiers.is_empty():
		hud.toast("You have no soldiers yet. Build a barracks (B, then 7) and recruit some.")
		return
	var army := soldiers.filter(func(so): return so.mode != "work")  # workers stay at their jobs
	var all_following := army.all(func(so): return so.mode == "follow")
	army_mode = "guard" if all_following else "follow"
	for s in army:
		s.mode = army_mode
		s.guard_point = player.pos
	_set_selection([])
	_reassign_slots()
	hud.toast("Your army guards this spot." if army_mode == "guard" else "Your army follows you.")
	_save_timer = SAVE_INTERVAL - 1.0


## Puts each group in formation order: centurions in front, archers at the back.
func _reassign_slots() -> void:
	var groups := {}  # "follow", "guard", or "hold:x,y" -> soldiers
	for s in soldiers:
		var key: String = s.mode if s.mode != "hold" else "hold:%d,%d" % [int(s.guard_point.x), int(s.guard_point.y)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(s)
	for key in groups:
		var group: Array = groups[key]
		group.sort_custom(func(a, b): return Soldier.KIND_ORDER.find(a.kind) < Soldier.KIND_ORDER.find(b.kind))
		for i in group.size():
			group[i].slot = i
			group[i].group_size = group.size()
			group[i].formation = formation


## Z: line, shield wall, wedge.
func _cycle_formation() -> void:
	formation = Soldier.FORMATIONS[(Soldier.FORMATIONS.find(formation) + 1) % Soldier.FORMATIONS.size()]
	_reassign_slots()
	hud.toast("Formation: %s." % formation)
	_save_timer = SAVE_INTERVAL - 1.0


func _set_selection(list: Array) -> void:
	for s in selected:
		if is_instance_valid(s):
			s.set_selected(false)
	selected = list.filter(func(so): return is_instance_valid(so) and not so.dead)
	# A few soldiers show their names; in a big group only the veterans do.
	for s in selected:
		s.set_selected(true, selected.size() <= 5 or s.kills >= 3)


## Sends the selected soldiers to `target`, where they hold in formation,
## facing the way they marched.
func _order_to(target: Vector2) -> void:
	if selected.is_empty():
		return
	var centre := Vector2.ZERO
	for s in selected:
		centre += s.pos
	centre /= selected.size()
	var ahead := (target - centre).normalized() if target.distance_to(centre) > 8.0 else player.facing
	for s in selected:
		s.mode = "hold"
		s.job = ""
		s.guard_point = target
		s.order_facing = ahead
	_reassign_slots()
	hud.toast("%d soldier%s march%s there. T calls everyone back." % [selected.size(), "" if selected.size() == 1 else "s", "es" if selected.size() == 1 else ""])
	_save_timer = SAVE_INTERVAL - 1.0


func _select_in_rect(rect: Rect2) -> void:
	var picked := []
	for s in soldiers:
		if s.dead or s.pos.distance_to(player.pos) > Soldier.DRAW_DISTANCE:
			continue
		var at: Vector3 = s.global_position + Vector3(0, 1.0, 0)
		if camera.is_position_behind(at):
			continue
		if rect.has_point(camera.unproject_position(at)):
			picked.append(s)
	_set_selection(picked)
	if picked.is_empty():
		return
	hud.toast("%d selected. Right-click the ground to send them · Z formation · Esc to deselect." % picked.size())


## Strategy view: drag a box to select soldiers, right-click to send them,
## Esc to let go. Returns true if the event was used.
func _army_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_from = mb.position
			_dragging = false
			return false  # a plain click still attacks
		var was_dragging := _dragging
		_dragging = false
		hud.set_selection_box(Rect2())
		if was_dragging and _drag_from != Vector2.INF:
			_select_in_rect(Rect2(_drag_from, Vector2.ZERO).expand(mb.position))
			_drag_from = Vector2.INF
			return true
		_drag_from = Vector2.INF
		return false
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_right_from = mb.position
			_right_moved = 0.0
			return false
		var was_click := _right_from != Vector2.INF and _right_moved < 8.0
		_right_from = Vector2.INF
		if was_click and not selected.is_empty():
			var target := _ground_under_mouse()
			if target != Vector2.INF:
				_order_to(target)
				return true
		return false
	var mm := event as InputEventMouseMotion
	if mm and _drag_from != Vector2.INF and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if mm.position.distance_to(_drag_from) > 10.0:
			_dragging = true
		if _dragging:
			hud.set_selection_box(Rect2(_drag_from, Vector2.ZERO).expand(mm.position))
			return true
	if event.is_action_pressed("menu") and not selected.is_empty():
		_set_selection([])
		return true
	return false


## The point on the ground under the mouse, in game pixels, or INF.
func _ground_under_mouse() -> Vector2:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.001:
		return Vector2.INF
	var t := (player.position.y - origin.y) / dir.y
	if t <= 0.0:
		return Vector2.INF
	var hit := origin + dir * t
	return Vector2(hit.x, hit.z) * World.TILE


func _tick_army(delta: float) -> void:
	var centurions := soldiers.filter(func(so): return so.kind == "centurion" and not so.dead)
	for s in soldiers:
		s.inspired = false
		if s.kind != "centurion":
			for c in centurions:
				if c.pos.distance_to(s.pos) < Soldier.INSPIRE_RADIUS:
					s.inspired = true
					break
		var killed: Wolf = s.tick(delta, player.pos, player.facing, wolves)
		if killed != null and wolves.has(killed):
			_kill_wolf(killed, true)
		if s.worked:
			_work_stroke(s)
		if s.ranked_up != "":
			hud.toast("%s is now %s %s! (%d kills)" % [s.soldier_name, "an" if s.ranked_up == "Elite" else "a", s.ranked_up, s.kills])
			audio.play("discover", s.position, -6.0)
		s.set_shown(s.pos.distance_to(player.pos) < Soldier.DRAW_DISTANCE)


func _on_soldier_fallen(s: Soldier) -> void:
	soldiers.erase(s)
	selected.erase(s)
	_reassign_slots()
	get_tree().create_timer(3.0).timeout.connect(s.queue_free)
	if s.kills > 0:
		hud.toast("%s has fallen. %s, %d kill%s." % [s.soldier_name, s.rank_name(), s.kills, "" if s.kills == 1 else "s"])
	else:
		hud.toast("%s has fallen." % s.soldier_name)


func _export_structures() -> Array:
	var out := []
	for b in buildings.values():
		var row := [b.cell.x, b.cell.y, b.kind, snappedf(b.hp, 0.1), b.items]
		if b.kind == "field":
			row.append(snappedf(b.growth, 0.001))
		out.append(row)
	return out


func _export_boats() -> Array:
	var out := []
	for b in boats:
		out.append([b.kind, snappedf(b.pos.x, 0.1), snappedf(b.pos.y, 0.1), snappedf(b.facing.x, 0.01), snappedf(b.facing.y, 0.01)])
	return out


func _export_soldiers() -> Array:
	var out := []
	for s in soldiers:
		out.append([snappedf(s.pos.x, 0.1), snappedf(s.pos.y, 0.1), snappedf(s.hp, 0.1), s.mode,
			snappedf(s.guard_point.x, 0.1), snappedf(s.guard_point.y, 0.1),
			{"k": s.kind, "n": s.soldier_name, "x": s.kills, "f": [snappedf(s.order_facing.x, 0.01), snappedf(s.order_facing.y, 0.01)],
				"j": s.job, "w": [snappedf(s.work_at.x, 0.1), snappedf(s.work_at.y, 0.1)]}])
	return out


# ---------- Death ----------

func _die() -> void:
	_leave_boat()
	if riding_horse != null:
		_dismount()
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
		PackedStringArray(["Resume", "Save now", "Account", "Settings", "Start over"]), _on_menu)


func _on_menu(choice: int, _text: String) -> void:
	if choice == 1:
		save_game(false, true)
		hud.toast("Game saved." if not api.can_post() else "Game saved, here and on the island server.")
	elif choice == 2:
		_open_account()
	elif choice == 3:
		_open_settings()
	elif choice == 4:
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
	if not started or bench_mode:
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
		"map": world.export_explored(),
		"places": {"found": poi_found.keys(), "looted": poi_looted.keys(), "shrine_days": shrine_days},
		"structures": _export_structures(),
		"soldiers": _export_soldiers(),
		"army_mode": army_mode,
		"formation": formation,
		"raids": {"cleared": camps_cleared.duplicate(), "found": camps_found.keys(), "purged_day": purged_day},
		"village": {"settlers": _export_settlers(), "taxes": taxes_last},
		"boats": _export_boats(),
		"horses": {"tame": _export_horses(),
			"riding": tame_horses.find(riding_horse) if riding_horse != null else -1, "taken": horses_taken.keys()},
		"sailing": boats.find(sailing) if sailing != null else -1,
		"player": {
			"pos": [player.pos.x, player.pos.y],
			"facing": [player.facing.x, player.facing.y],
			"health": player.health,
			"hunger": player.hunger,
			"warmth": player.warmth,
			"sanity": player.sanity,
			"inventory": player.inventory.duplicate(),
			"spear": player.has_spear,
			"tools": _tools_owned(),
			"gear": {"spear": player.spear_tier, "sword": player.sword_tier, "armour": player.armour_tier},
			"equipped": player.equipped,
			"armour_on": player.armour_on,
			"lantern_on": player.lantern_on,
			"torch": player.torch_time,
		},
	}
	if respawn:
		var items := {}
		for item in player.inventory:
			if int(player.inventory[item]) > 0:
				items[item] = int(player.inventory[item])
		for tool in _tools_owned():
			if not tool in ["spear", "iron_spear", "armour"]:  # gear goes in by tier, below
				items[tool] = 1
		for kind in ["spear", "sword", "armour"]:
			if _gear_tier(kind) >= 0:
				items["gear_" + kind] = _gear_tier(kind) + 1
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
			"warmth": 100.0, "sanity": 100.0, "inventory": {}, "spear": false, "tools": [], "torch": 0.0,
		}
		data["run_id"] = ""
		data["sailing"] = -1
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
	world.set_season(season_of(day))
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
		for tool in p.get("tools", []):
			if TOOLS.has(str(tool)):
				player.set(TOOLS[str(tool)], true)
		# Newer saves store each piece of gear by tier; that's exact, so it wins
		# over the old yes/no flags above.
		var gear: Variant = p.get("gear", {})
		if typeof(gear) == TYPE_DICTIONARY and not gear.is_empty():
			player.spear_tier = clampi(int(gear.get("spear", -1)), -1, Gear.SPEAR.size() - 1)
			player.sword_tier = clampi(int(gear.get("sword", -1)), -1, Gear.SWORD.size() - 1)
			player.armour_tier = clampi(int(gear.get("armour", -1)), -1, Gear.ARMOUR.size() - 1)
		player.equipped = "hands"
		player.equip(str(p.get("equipped", "hands")))
		player.armour_on = bool(p.get("armour_on", true))
		player.lantern_on = bool(p.get("lantern_on", true))
		player.torch_time = maxf(float(p.get("torch", 0.0)), 0.0)

	var map_hex: Variant = save.get("map", "")
	if typeof(map_hex) == TYPE_STRING and map_hex != "":
		world.import_explored(map_hex)
	var places: Variant = save.get("places", {})
	if typeof(places) == TYPE_DICTIONARY:
		for id in places.get("found", []):
			poi_found[str(id)] = true
		for id in places.get("looted", []):
			poi_looted[str(id)] = true
		var days: Variant = places.get("shrine_days", {})
		if typeof(days) == TYPE_DICTIONARY:
			for id in days:
				shrine_days[str(id)] = int(days[id])
	for id in save.get("read", []):
		_read_ids[str(id)] = true
	for f in save.get("fires", []):
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var pos := _to_vec(f.get("pos", null))
		if pos == Vector2.INF:
			continue
		_add_campfire(pos, clampf(float(f.get("fuel", 0.0)), 0.0, Campfire.MAX_FUEL), "")
	for b in save.get("bags", []):
		if typeof(b) == TYPE_DICTIONARY:
			_spawn_trace(b)
	for st in save.get("structures", []):
		if typeof(st) == TYPE_ARRAY and st.size() >= 4 and Structure.TYPES.has(str(st[2])):
			var cell := Vector2i(int(st[0]), int(st[1]))
			if world.can_build(cell):
				var items: Variant = st[4] if st.size() > 4 else {}
				var built := _add_structure(str(st[2]), cell, float(st[3]), items if typeof(items) == TYPE_DICTIONARY else {})
				if st.size() > 5 and built.kind == "field":
					built.set_growth(float(st[5]))
	army_mode = "guard" if str(save.get("army_mode", "follow")) == "guard" else "follow"
	var raids: Variant = save.get("raids", {})
	if typeof(raids) == TYPE_DICTIONARY:
		var cleared: Variant = raids.get("cleared", {})
		if typeof(cleared) == TYPE_DICTIONARY:
			for k in cleared:
				camps_cleared[str(k)] = int(cleared[k])
		for k in raids.get("found", []):
			camps_found[str(k)] = true
		purged_day = int(raids.get("purged_day", 0))
	var village: Variant = save.get("village", {})
	if typeof(village) == TYPE_DICTIONARY:
		taxes_last = int(village.get("taxes", 0))
		for row in village.get("settlers", []):
			if typeof(row) == TYPE_ARRAY and row.size() >= 7:
				_spawn_settler(str(row[0]), int(row[1]), Vector2(float(row[2]), float(row[3])),
					Vector2(float(row[4]), float(row[5])), float(row[6]))
	formation = str(save.get("formation", "line"))
	if not formation in Soldier.FORMATIONS:
		formation = "line"
	for so in save.get("soldiers", []):
		if typeof(so) == TYPE_ARRAY and so.size() >= 6 and soldiers.size() < Soldier.MAX_ARMY:
			var extra: Dictionary = so[6] if so.size() > 6 and typeof(so[6]) == TYPE_DICTIONARY else {}
			var s := _spawn_soldier(Vector2(float(so[0]), float(so[1])), float(so[2]), str(so[3]),
				Vector2(float(so[4]), float(so[5])), str(extra.get("k", "legionary")), str(extra.get("n", "")), int(extra.get("x", 0)))
			var f := _to_vec(extra.get("f", null))
			if f != Vector2.INF and f.length() > 0.1:
				s.order_facing = f
			var w := _to_vec(extra.get("w", null))
			if s.mode == "work" and JOBS.has(str(extra.get("j", ""))) and w != Vector2.INF:
				s.job = str(extra.get("j", ""))
				s.work_at = w
			elif s.mode == "work":
				s.mode = "follow"
	_reassign_slots()
	for bo in save.get("boats", []):
		if typeof(bo) == TYPE_ARRAY and bo.size() >= 5 and _boat_of(str(bo[0])) == null:
			_spawn_boat(str(bo[0]), Vector2(float(bo[1]), float(bo[2])), Vector2(float(bo[3]), float(bo[4])))
	var hs: Variant = save.get("horses", {})
	if typeof(hs) == TYPE_DICTIONARY:
		for t in hs.get("taken", []):
			horses_taken[str(t)] = true
		for row in hs.get("tame", []):
			if typeof(row) == TYPE_ARRAY and row.size() >= 3 and tame_horses.size() < MAX_TAME_HORSES:
				var tame := _spawn_horse(Vector2(float(row[0]), float(row[1])), int(row[2]), false)
				if row.size() > 3 and typeof(row[3]) == TYPE_DICTIONARY:
					for item in row[3]:
						if ITEM_NAMES.has(str(item)) and int(row[3][item]) > 0:
							tame.items[str(item)] = int(row[3][item])
				tame_horses.append(tame)
		_resume_riding = int(hs.get("riding", -1))
	var aboard := int(save.get("sailing", -1))
	if aboard >= 0 and aboard < boats.size():
		_resume_sailing = aboard
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
