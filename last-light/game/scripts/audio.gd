## Sound effects, ambience and music. All sounds are synthesized by
## tools/make_sounds.py, so there are no recordings or licences involved.
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const SFX := {
	"chop": preload("res://sounds/chop.ogg"),
	"mine": preload("res://sounds/mine.ogg"),
	"pick": preload("res://sounds/pick.ogg"),
	"step": preload("res://sounds/step.ogg"),
	"eat": preload("res://sounds/eat.ogg"),
	"build": preload("res://sounds/build.ogg"),
	"craft": preload("res://sounds/craft.ogg"),
	"swing": preload("res://sounds/swing.ogg"),
	"hit": preload("res://sounds/hit.ogg"),
	"hurt": preload("res://sounds/hurt.ogg"),
	"wolf_howl": preload("res://sounds/wolf_howl.ogg"),
	"wolf_bite": preload("res://sounds/wolf_bite.ogg"),
	"wolf_yelp": preload("res://sounds/wolf_yelp.ogg"),
	"discover": preload("res://sounds/discover.ogg"),
	"shrine": preload("res://sounds/shrine.ogg"),
	"ui": preload("res://sounds/ui.ogg"),
}
const FIRE_LOOP := preload("res://sounds/fire_loop.ogg")
const DAY_LOOP := preload("res://sounds/day_loop.ogg")
const NIGHT_LOOP := preload("res://sounds/night_loop.ogg")
const MUSIC_DAY := preload("res://sounds/music_day.ogg")
const MUSIC_NIGHT := preload("res://sounds/music_night.ogg")
const SILENT_DB := -60.0

var sound_on := true
var music_on := true

var _flat: Array = []  # AudioStreamPlayer pool for sounds without a place
var _spatial: Array = []  # AudioStreamPlayer3D pool for sounds in the world
var _next_flat := 0
var _next_spatial := 0
var _day_amb: AudioStreamPlayer
var _night_amb: AudioStreamPlayer
var _music_day: AudioStreamPlayer
var _music_night: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_settings()
	# Two buses, so one switch silences every effect (fires included) or the music.
	for bus in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_apply_mute()
	for stream in [FIRE_LOOP, DAY_LOOP, NIGHT_LOOP, MUSIC_DAY, MUSIC_NIGHT]:
		(stream as AudioStreamOggVorbis).loop = true
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)
	for i in 14:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 70.0
		p3.bus = "SFX"
		add_child(p3)
		_spatial.append(p3)
	_day_amb = _loop_player(DAY_LOOP, "SFX")
	_night_amb = _loop_player(NIGHT_LOOP, "SFX")
	_music_day = _loop_player(MUSIC_DAY, "Music")
	_music_night = _loop_player(MUSIC_NIGHT, "Music")


## Plays an effect. With `at`, the sound comes from that point in the world.
func play(sound: String, at: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch_spread: float = 0.08) -> void:
	if not sound_on or not SFX.has(sound):
		return
	var pitch := 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	if at == Vector3.INF:
		var p: AudioStreamPlayer = _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		p.stream = SFX[sound]
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p3: AudioStreamPlayer3D = _spatial[_next_spatial]
		_next_spatial = (_next_spatial + 1) % _spatial.size()
		p3.stream = SFX[sound]
		p3.global_position = at
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.play()


## A looping crackle to attach to a fire or torch post.
func make_fire_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = FIRE_LOOP
	p.unit_size = 4.0
	p.max_distance = 22.0
	p.volume_db = -6.0
	p.bus = "SFX"
	return p


## Fades the day and night ambience and music. night: 0 by day, 1 at night.
func update_mix(night: float, delta: float) -> void:
	var w := minf(delta * 1.5, 1.0)
	_fade(_day_amb, -8.0 - night * 30.0, w)
	_fade(_night_amb, -8.0 - (1.0 - night) * 30.0, w)
	_fade(_music_day, -14.0 - night * 40.0, w)
	_fade(_music_night, -14.0 - (1.0 - night) * 40.0, w)


func set_sound(on: bool) -> void:
	sound_on = on
	_apply_mute()
	_save_settings()


func set_music(on: bool) -> void:
	music_on = on
	_apply_mute()
	_save_settings()


func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not sound_on)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on)


func _fade(p: AudioStreamPlayer, target_db: float, w: float) -> void:
	var target := target_db
	p.volume_db = lerpf(p.volume_db, target, w)
	if p.volume_db <= SILENT_DB + 1.0:
		if p.playing:
			p.stop()
	elif not p.playing:
		p.play()


func _loop_player(stream: AudioStream, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sound_on = bool(cfg.get_value("audio", "sound", true))
		music_on = bool(cfg.get_value("audio", "music", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "sound", sound_on)
	cfg.set_value("audio", "music", music_on)
	cfg.save(SETTINGS_PATH)
