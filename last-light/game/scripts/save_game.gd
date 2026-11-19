## Reads and writes the save file. On the web, user:// is stored in the
## browser (IndexedDB), so a save survives reloads but stays on that browser.
extends RefCounted

const PATH := "user://save.json"
const VERSION := 1


static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}


static func write(data: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


static func erase() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
