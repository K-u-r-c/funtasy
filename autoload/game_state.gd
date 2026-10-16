extends Node
## Session state shared by menus, lobby and the run:
## - which game the party plays: a new one, or a saved game the host continues
##   (`game_info`, replicated). Saves belong to games, not to characters: a saved game has a
##   fixed party size and its own heroes, and a party wipe ends (deletes) it;
## - the lobby roster (peer id -> name/class/gender/level/slot), replicated by the host;
## - the host's game settings (data/game_settings.json), replicated to every client;
## - host-only: the authoritative character of every peer and the saved-game record.

signal roster_changed
signal settings_changed
signal game_changed

var roster: Dictionary = {}  ## peer id -> {name, class_id, gender, level, slot}
var settings: Dictionary = {}  ## game setting id -> value
## Replicated: {mode: "new"|"continue", id, party_size, depth, members: [{name, class_id, gender, level}]}
var game_info: Dictionary = {}
var local_choice: Dictionary = {}  ## this peer's pick: {name, class_id, gender} (new) or {slot} (continue)
var last_hero: Dictionary = {}  ## last name/class this peer typed, to pre-fill the lobby

# Host only
var characters: Dictionary = {}  ## peer id -> character dict
var game: Dictionary = {}  ## the saved-game record being played (see SaveSystem)
var current_depth := 1


func _ready() -> void:
	reset_settings()
	_set_new_game_info()
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.connected_as_client.connect(_on_connected_as_client)
	NetworkManager.session_closed.connect(_on_session_closed)


## Starting kit of a new hero: 2 = the simple start (primary attack + one basic skill). Saves
## without "kit" are older heroes, whose old tier-0 starter skills stay free (Player.legacy_kit).
const KIT_VERSION := 2


static func new_character(char_name: String, class_id: String, gender: String = "") -> Dictionary:
	return {
		"name": char_name, "class_id": class_id, "gender": CharacterSprite.valid_gender(gender), "level": 1, "xp": 0,
		"talents": {}, "equipment": {}, "backpack": [],
		"backpack_capacity": int(GameData.bal("inventory.start_capacity", 12)),
		"quick": {"q": "", "e": ""},
		"allocated": {}, "run_mods": [], "gold": 0, "bonus_stat_points": 0, "bonus_talent_points": 0, "loadout": [],
		"kit": KIT_VERSION,
	}


func is_continuing() -> bool:
	return game_info.get("mode", "new") == "continue"


# =========================================================================================
# Host: choosing the game
# =========================================================================================


func select_new_game() -> void:
	if not multiplayer.is_server():
		return
	game = {}
	_set_new_game_info()
	_reset_choices()


func select_saved_game(id: String) -> bool:
	if not multiplayer.is_server():
		return false
	var g := SaveSystem.load_game(id)
	if g.is_empty():
		return false
	game = g
	var members: Array = []
	for m in g.members:
		members.append({"name": m.name, "class_id": m.class_id, "gender": CharacterSprite.valid_gender(str(m.get("gender", ""))), "level": int(m.level)})
	game_info = {"mode": "continue", "id": g.id, "party_size": int(g.party_size), "depth": int(g.get("depth", 1)), "members": members}
	_reset_choices()
	return true


## Host: can the run start with the players currently connected?
func start_problem() -> String:
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	for id in ids:
		if not roster.has(id):
			return "Waiting for every player to pick a hero."
	if is_continuing() and ids.size() != int(game_info.party_size):
		return "This saved game needs exactly %d player%s (%d connected)." % [int(game_info.party_size), "" if int(game_info.party_size) == 1 else "s", ids.size()]
	return ""


## Host, when the run starts: creates the saved game for a new party.
func begin_game() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = roster.keys()
	ids.sort()
	if not is_continuing():
		game = {"id": SaveSystem.new_game_id(), "created_at": int(Time.get_unix_time_from_system()),
			"party_size": ids.size(), "depth": 1, "members": []}
		for i in ids.size():
			roster[ids[i]].slot = i
			game.members.append(characters[ids[i]])
	current_depth = int(game.get("depth", 1))


func start_depth() -> int:
	return maxi(1, int(game.get("depth", 1)))


## Host: writes the current state of every hero (and the floor reached) to the saved game.
func save_game() -> void:
	if not multiplayer.is_server() or game.is_empty():
		return
	for peer in characters:
		var slot := int(roster.get(peer, {}).get("slot", -1))
		if slot >= 0 and slot < game.members.size():
			game.members[slot] = characters[peer].duplicate(true)
	game.depth = current_depth
	SaveSystem.save_game(game)


## Host: the party was wiped, this game is over for good.
func end_game() -> void:
	if not multiplayer.is_server() or game.is_empty():
		return
	SaveSystem.delete_game(str(game.id))
	game = {}
	_set_new_game_info()
	_reset_choices()


func _set_new_game_info() -> void:
	game_info = {"mode": "new", "id": "", "party_size": 0, "depth": 1, "members": []}


func _reset_choices() -> void:
	roster.clear()
	characters.clear()
	NetworkManager.to_all("GameState", "_sync_game", [game_info])
	_broadcast_roster()


## Host -> all (via SessionRpc): the game being set up changed; everyone picks again.
func _sync_game(info: Dictionary) -> void:
	game_info = info
	local_choice = {}
	game_changed.emit()


# =========================================================================================
# Every peer: picking a character
# =========================================================================================


## New game: play a fresh level 1 hero with this name, class and gender.
func choose_new_character(char_name: String, class_id: String, gender: String = "") -> void:
	local_choice = {"name": char_name, "class_id": class_id, "gender": CharacterSprite.valid_gender(gender)}
	last_hero = local_choice.duplicate()
	_submit()


## Saved game: play the hero in this slot.
func claim_slot(slot: int) -> void:
	local_choice = {"slot": slot}
	_submit()


## Kept for the test driver and old callers: same as choose_new_character.
func select_character(char_name: String, class_id: String, gender: String = "") -> void:
	choose_new_character(char_name, class_id, gender)


func _submit() -> void:
	if not NetworkManager.is_active() or local_choice.is_empty():
		return
	if multiplayer.is_server():
		_apply_choice(1, local_choice)
	else:
		NetworkManager.to_host("GameState", "_submit_choice", [local_choice])


## Client -> host (via SessionRpc).
func _submit_choice(choice: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_choice(multiplayer.get_remote_sender_id(), choice)


func _apply_choice(peer: int, choice: Dictionary) -> void:
	if is_continuing():
		var slot := int(choice.get("slot", -1))
		if slot < 0 or slot >= game.get("members", []).size():
			return
		for other in roster:
			if other != peer and int(roster[other].get("slot", -1)) == slot:
				return  # already taken
		var ch: Dictionary = game.members[slot].duplicate(true)
		characters[peer] = ch
		ch.gender = CharacterSprite.valid_gender(str(ch.get("gender", "")))  # saves from before genders
		roster[peer] = {"name": ch.name, "class_id": ch.class_id, "gender": ch.gender, "level": int(ch.level), "slot": slot}
	else:
		var cid := str(choice.get("class_id", ""))
		if not GameData.classes.has(cid):
			return
		var ch2 := new_character(str(choice.get("name", "Hero")).strip_edges().substr(0, 16), cid, str(choice.get("gender", "")))
		if ch2.name.is_empty():
			ch2.name = "Hero"
		characters[peer] = ch2
		roster[peer] = {"name": ch2.name, "class_id": cid, "gender": ch2.gender, "level": 1, "slot": -1}
	_broadcast_roster()


# =========================================================================================
# Roster
# =========================================================================================


func _broadcast_roster() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager.to_all("GameState", "_sync_roster", [roster])


## Host -> all (via SessionRpc).
func _sync_roster(data: Dictionary) -> void:
	roster = data
	roster_changed.emit()


func classes_in_party() -> Array:
	var out: Array = []
	for id in roster:
		if not out.has(roster[id].class_id):
			out.append(roster[id].class_id)
	return out


# =========================================================================================
# Game settings (host-only edits)
# =========================================================================================


func reset_settings() -> void:
	settings.clear()
	for d in GameData.game_settings:
		settings[d.id] = d.default


func setting(id: String) -> Variant:
	return settings.get(id, GameData.game_setting_def(id).get("default"))


func set_setting(id: String, value: Variant) -> void:
	if not multiplayer.is_server():
		return
	settings[id] = value
	NetworkManager.to_all("GameState", "_sync_settings", [settings])


## Host -> all (via SessionRpc).
func _sync_settings(data: Dictionary) -> void:
	settings = data
	settings_changed.emit()
	EventBus.game_settings_changed.emit()


# =========================================================================================
# Session callbacks
# =========================================================================================


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		NetworkManager.to_peer(id, "GameState", "_sync_settings", [settings])
		NetworkManager.to_peer(id, "GameState", "_sync_game", [game_info])
		NetworkManager.to_peer(id, "GameState", "_sync_roster", [roster])


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		# During a run the leaver's hero keeps its slot (saved with the rest of the party).
		if not NetworkManager.in_run:
			roster.erase(id)
			characters.erase(id)
			_broadcast_roster()


func _on_connected_as_client() -> void:
	_submit()


func _on_session_closed() -> void:
	roster.clear()
	characters.clear()
	game = {}
	local_choice = {}
	_set_new_game_info()
	reset_settings()
	roster_changed.emit()
	game_changed.emit()
