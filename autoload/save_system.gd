extends Node
## Local persistence.
## - user://settings.cfg: one ConfigFile shared by video/audio/input settings. Every writer
##   goes through write_section() so saving one section never wipes the others.
## - user://games/<id>.json: one file per saved game (host side; see below).
## Launching with the user arg --profile=<name> moves both under user://profiles/<name>/
## (used by the automated tests so they never touch real saves and settings).

const SAVE_VERSION := 2  ## 2 (#55): run_seed and the floor snapshot (older saves start a new floor)

var base_dir := "user://"
var SETTINGS_PATH := "user://settings.cfg"
var GAME_DIR := "user://games/"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			base_dir = "user://profiles/%s/" % a.get_slice("=", 1).validate_filename()
			DirAccess.make_dir_recursive_absolute(base_dir)
	SETTINGS_PATH = base_dir + "settings.cfg"
	GAME_DIR = base_dir + "games/"


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


# --- Saved games ---------------------------------------------------------------------------
# A saved game belongs to the host who created it: {id, created_at, updated_at, party_size,
# depth, members: [character dict, ...]}. Characters only exist inside their game, so a hero
# can't be carried into another party, and a party wipe deletes the game.


func new_game_id() -> String:
	return "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]


func list_games() -> Array:
	var out: Array = []
	var dir := DirAccess.open(GAME_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			var g := _read_json(GAME_DIR + f)
			if not g.is_empty() and g.has("id") and g.has("members"):
				out.append(g)
	out.sort_custom(func(a, b): return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0)))
	return out


func load_game(id: String) -> Dictionary:
	return _read_json(GAME_DIR + id.validate_filename() + ".json")


func save_game(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GAME_DIR)
	data = data.duplicate(true)
	data["version"] = SAVE_VERSION
	data["updated_at"] = int(Time.get_unix_time_from_system())
	var path: String = GAME_DIR + str(data.id).validate_filename() + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func delete_game(id: String) -> void:
	var path := GAME_DIR + id.validate_filename() + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
