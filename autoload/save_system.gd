extends Node
## Local persistence.
## - user://settings.cfg: one ConfigFile shared by video/audio/input settings. Every writer
##   goes through write_section() so saving one section never wipes the others.
## - user://characters/<key>.json: one file per character (name + class).
## Launching with the user arg --profile=<name> moves both under user://profiles/<name>/
## (used by the automated tests so they never touch real saves and settings).

const SAVE_VERSION := 1

var base_dir := "user://"
var SETTINGS_PATH := "user://settings.cfg"
var CHAR_DIR := "user://characters/"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			base_dir = "user://profiles/%s/" % a.get_slice("=", 1).validate_filename()
			DirAccess.make_dir_recursive_absolute(base_dir)
	SETTINGS_PATH = base_dir + "settings.cfg"
	CHAR_DIR = base_dir + "characters/"


func read_section(section: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {}
	if cfg.load(SETTINGS_PATH) != OK or not cfg.has_section(section):
		return out
	for key in cfg.get_section_keys(section):
		out[key] = cfg.get_value(section, key)
	return out


func write_section(section: String, values: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # missing file is fine: we start empty
	if cfg.has_section(section):
		cfg.erase_section(section)
	for key in values:
		cfg.set_value(section, key, values[key])
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("SaveSystem: could not save settings (%d)" % err)


# --- Characters ----------------------------------------------------------------------------


static func character_key(char_name: String, class_id: String) -> String:
	var safe := ""
	for c in char_name.to_lower():
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return "%s__%s" % [safe, class_id]


func list_characters() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CHAR_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			var c := _read_json(CHAR_DIR + f)
			if not c.is_empty():
				out.append(c)
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


func load_character(char_name: String, class_id: String) -> Dictionary:
	return _read_json(CHAR_DIR + character_key(char_name, class_id) + ".json")


func save_character(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	data = data.duplicate(true)
	data["version"] = SAVE_VERSION
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var path: String = CHAR_DIR + character_key(data.name, data.class_id) + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func delete_character(char_name: String, class_id: String) -> void:
	var path := CHAR_DIR + character_key(char_name, class_id) + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
