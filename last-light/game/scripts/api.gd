## Talks to the Last Light island server (a Cloudflare Worker backed by Turso).
## If no server URL is configured, the game runs offline and every call
## reports failure, so the game never depends on the network to be playable.
extends Node

const PROFILE_PATH := "user://profile.cfg"

var base_url := ""
var player_name := ""
var player_id := ""
var token := ""


func _ready() -> void:
	base_url = str(ProjectSettings.get_setting("last_light/api/base_url", "")).strip_edges()
	if OS.has_feature("web"):
		# Lets you point a web build at another server: index.html?api=https://...
		var override: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('api') || ''", true)
		if typeof(override) == TYPE_STRING and str(override).begins_with("https://"):
			base_url = str(override)
	base_url = base_url.trim_suffix("/")
	_load_profile()


func is_online() -> bool:
	return base_url != ""


func can_post() -> bool:
	return is_online() and token != ""


func set_player_name(n: String) -> void:
	player_name = n.strip_edges().left(20)
	_save_profile()


func forget_identity() -> void:
	player_id = ""
	token = ""
	_save_profile()


# ---------- Local records (work offline too) ----------

func local_best(seed_value: int) -> int:
	var cfg := _profile()
	return int(cfg.get_value("best", str(seed_value), -1))


func record_local_best(seed_value: int, days: int) -> void:
	var cfg := _profile()
	if days > int(cfg.get_value("best", str(seed_value), -1)):
		cfg.set_value("best", str(seed_value), days)
	if days > int(cfg.get_value("best", "all_time", -1)):
		cfg.set_value("best", "all_time", days)
	cfg.save(PROFILE_PATH)


# ---------- Server calls. Every callback receives (ok: bool, data: Variant). ----------

## Callback receives (ok: bool).
func ensure_registered(callback: Callable) -> void:
	if not is_online():
		callback.call(false)
		return
	if token != "":
		callback.call(true)
		return
	_request(HTTPClient.METHOD_POST, "/api/players", {"name": player_name}, _on_registered.bind(callback))


func start_run(seed_value: int, callback: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/api/runs", {"seed": seed_value}, callback)


func end_run(run_id: String, days: int, pos: Vector2, epitaph: String, cause: String, callback: Callable) -> void:
	var body := {"days": days, "x": int(pos.x), "y": int(pos.y), "text": epitaph, "cause": cause}
	_request(HTTPClient.METHOD_POST, "/api/runs/%s/end" % run_id.uri_encode(), body, callback)


func fetch_traces(seed_value: int, callback: Callable) -> void:
	_request(HTTPClient.METHOD_GET, "/api/islands/%d/traces" % seed_value, null, callback)


func post_trace(seed_value: int, kind: String, pos: Vector2, text: String, items: Dictionary, callback: Callable) -> void:
	var body := {"kind": kind, "x": int(pos.x), "y": int(pos.y), "text": text, "items": items}
	_request(HTTPClient.METHOD_POST, "/api/islands/%d/traces" % seed_value, body, callback)


func take_stash(trace_id: String, callback: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/api/traces/%s/take" % trace_id.uri_encode(), {}, callback)


func fetch_leaderboard(seed_value: int, callback: Callable) -> void:
	_request(HTTPClient.METHOD_GET, "/api/islands/%d/leaderboard" % seed_value, null, callback)


# ---------- Internals ----------

func _on_registered(ok: bool, data: Variant, callback: Callable) -> void:
	if ok and typeof(data) == TYPE_DICTIONARY and data.has("token"):
		player_id = str(data["id"])
		token = str(data["token"])
		_save_profile()
		callback.call(true)
	else:
		callback.call(false)


func _request(method: HTTPClient.Method, path: String, body: Variant, callback: Callable) -> void:
	if not is_online():
		if callback.is_valid():
			callback.call_deferred(false, {"error": "offline"})
		return
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	http.request_completed.connect(_on_completed.bind(http, callback))
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		if callback.is_valid():
			callback.call_deferred(false, {"error": "request_failed"})


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		http: HTTPRequest, callback: Callable) -> void:
	http.queue_free()
	var data: Variant = null
	var text := body.get_string_from_utf8()
	if text != "":
		data = JSON.parse_string(text)
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	if not ok and not data.has("error"):
		data["error"] = "network" if result != HTTPRequest.RESULT_SUCCESS else "http_%d" % code
	data["status"] = code
	if code == 401:
		forget_identity()
	if callback.is_valid():
		callback.call(ok, data)


func _profile() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	return cfg


func _load_profile() -> void:
	var cfg := _profile()
	player_name = str(cfg.get_value("player", "name", ""))
	player_id = str(cfg.get_value("player", "id", ""))
	token = str(cfg.get_value("player", "token", ""))


func _save_profile() -> void:
	var cfg := _profile()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "id", player_id)
	cfg.set_value("player", "token", token)
	cfg.save(PROFILE_PATH)
