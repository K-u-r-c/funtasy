extends Node
## Loads every definition from res://data (JSON) once at startup and validates it.
## The rest of the game reads balance numbers and definitions only through here.
##
## Single-file tables: balance, assets, game_settings, input_defaults, rarities, affixes,
## consumables, status_effects, props.
## Directory tables (one JSON object per file, keyed by its "id"): classes, monsters, bosses,
## floor_types, item_bases (data/items/bases/*.json).
## Skills and talents: data/skills/<class>.json and data/talents/<class>.json (arrays / trees).

const DATA_DIR := "res://data/"

var balance: Dictionary = {}
var assets: Dictionary = {}
var game_settings: Array = []
var input_defaults: Dictionary = {}
var rarities: Array = []
var affixes: Dictionary = {}
var consumables: Dictionary = {}
var status_effects: Dictionary = {}
var props: Dictionary = {}
var classes: Dictionary = {}
var skills: Dictionary = {}  ## skill id -> def (all classes + monster skills)
var talents: Dictionary = {}  ## class id -> tree def
var monsters: Dictionary = {}
var bosses: Dictionary = {}
var floor_types: Dictionary = {}
var item_bases: Dictionary = {}

var errors: PackedStringArray = []

const REQUIRED := {
	"classes": ["id", "name", "resource", "skills", "base_stats", "per_level", "primary_attack"],
	"skills": ["id", "name", "cooldown", "effects"],
	"monsters": ["id", "name", "ai", "base_stats", "xp", "sprite"],
	"bosses": ["id", "name", "base_stats", "xp", "sprite", "phases"],
	"floor_types": ["id", "name", "monsters", "boss", "music", "boss_music", "tiles"],
	"item_bases": ["id", "name", "slot", "icon"],
}


func _ready() -> void:
	reload()


func reload() -> void:
	errors.clear()
	balance = _load_json("balance.json", {})
	assets = _load_json("assets.json", {})
	game_settings = _load_json("game_settings.json", [])
	input_defaults = _load_json("input_defaults.json", {})
	rarities = _load_json("items/rarities.json", [])
	affixes = _load_json("items/affixes.json", {})
	consumables = _load_json("items/consumables.json", {})
	status_effects = _load_json("status_effects.json", {})
	props = _load_json("props.json", {})
	classes = _load_dir("classes")
	monsters = _load_dir("monsters")
	bosses = _load_dir("bosses")
	floor_types = _load_dir("floor_types")
	item_bases = _load_dir("items/bases")
	skills.clear()
	talents.clear()
	for file in _list_json("skills"):
		var arr: Variant = _load_json("skills/" + file, [])
		for s in arr:
			skills[s.id] = s
	for file in _list_json("talents"):
		talents[file.get_basename()] = _load_json("talents/" + file, {})
	_validate()
	for e in errors:
		push_error("GameData: " + e)


func bal(path: String, fallback: Variant = null) -> Variant:
	## Dotted lookup into balance.json, e.g. bal("player.move_speed").
	var node: Variant = balance
	for part in path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			if fallback == null:
				push_error("GameData: missing balance key '%s'" % path)
			return fallback
	return node


func asset_path(key: String) -> String:
	## Asset registry lookup (data/assets.json, dotted key). Swapping art = editing that file.
	var node: Variant = assets
	for part in key.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			push_error("GameData: missing asset key '%s'" % key)
			return ""
	return str(node.path) if node is Dictionary and node.has("path") else str(node)


func asset_entry(key: String) -> Dictionary:
	var node: Variant = assets
	for part in key.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			push_error("GameData: missing asset key '%s'" % key)
			return {}
	return node if node is Dictionary else {"path": str(node)}


func texture(key: String) -> Texture2D:
	var path := asset_path(key)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("GameData: texture not found for '%s' (%s)" % [key, path])
		return null
	return load(path)


func skill(id: String) -> Dictionary:
	if not skills.has(id):
		push_error("GameData: unknown skill '%s'" % id)
		return {}
	return skills[id]


func rarity(tier: int) -> Dictionary:
	return rarities[clampi(tier, 1, rarities.size()) - 1]


func game_setting_def(id: String) -> Dictionary:
	for d in game_settings:
		if d.id == id:
			return d
	return {}


# --- Loading -------------------------------------------------------------------------------


func _load_json(rel: String, fallback: Variant) -> Variant:
	var path := DATA_DIR + rel
	if not FileAccess.file_exists(path):
		errors.append("missing file %s" % path)
		return fallback
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	return json.data


func _list_json(rel_dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(DATA_DIR + rel_dir)
	if dir == null:
		errors.append("missing directory %s" % rel_dir)
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func _load_dir(rel_dir: String) -> Dictionary:
	var out := {}
	for f in _list_json(rel_dir):
		var d: Variant = _load_json(rel_dir + "/" + f, {})
		if d is Dictionary and d.has("id"):
			out[d.id] = d
		else:
			errors.append("%s/%s has no id" % [rel_dir, f])
	return out


func _validate() -> void:
	var tables := {
		"classes": classes, "skills": skills, "monsters": monsters, "bosses": bosses,
		"floor_types": floor_types, "item_bases": item_bases,
	}
	for table_name in REQUIRED:
		for id in tables[table_name]:
			var def: Dictionary = tables[table_name][id]
			for key in REQUIRED[table_name]:
				if not def.has(key):
					errors.append("%s '%s' is missing '%s'" % [table_name, id, key])
	for cid in classes:
		for sid in classes[cid].skills:
			if not skills.has(sid):
				errors.append("class '%s' references unknown skill '%s'" % [cid, sid])
		if not talents.has(cid):
			errors.append("class '%s' has no talent tree" % cid)
	for fid in floor_types:
		var ft: Dictionary = floor_types[fid]
		for m in ft.monsters:
			if not monsters.has(m.id):
				errors.append("floor type '%s' references unknown monster '%s'" % [fid, m.id])
		if not bosses.has(ft.boss):
			errors.append("floor type '%s' references unknown boss '%s'" % [fid, ft.boss])
