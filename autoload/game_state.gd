extends Node
## Session state shared by menus, lobby and the run:
## - the local character (loaded/saved through SaveSystem),
## - the lobby roster (peer id -> name/class/level/ready), replicated by the host,
## - the host's game settings (data/game_settings.json), replicated to every client,
## - host-only: the full character data of every peer (authoritative during a run).

signal roster_changed
signal settings_changed

var local_character: Dictionary = {}
var roster: Dictionary = {}  ## peer id -> {name, class_id, level}
var settings: Dictionary = {}  ## game setting id -> value
var characters: Dictionary = {}  ## host only: peer id -> character dict


func _ready() -> void:
	reset_settings()
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.connected_as_client.connect(_on_connected_as_client)
	NetworkManager.session_closed.connect(_on_session_closed)


# --- Characters ----------------------------------------------------------------------------


static func new_character(char_name: String, class_id: String) -> Dictionary:
	return {
		"name": char_name, "class_id": class_id, "level": 1, "xp": 0,
		"talents": {}, "equipment": {}, "backpack": [],
		"backpack_capacity": int(GameData.bal("inventory.start_capacity", 12)),
		"quick": {"q": "", "e": ""},
	}


## Picks the saved character with this name+class, or creates a fresh one (in underwear).
func select_character(char_name: String, class_id: String) -> void:
	var saved := SaveSystem.load_character(char_name, class_id)
	local_character = saved if not saved.is_empty() else new_character(char_name, class_id)
	local_character.name = char_name
	local_character.class_id = class_id
	if NetworkManager.is_active():
		submit_local_character()


func submit_local_character() -> void:
	if multiplayer.is_server():
		_store_submitted(1, local_character)
	else:
		NetworkManager.to_host("GameState", "_submit_character", [local_character])


func save_local_character() -> void:
	if not local_character.is_empty():
		SaveSystem.save_character(local_character)


## Called by the host whenever an authoritative character changed enough to persist.
func push_character_to_owner(peer_id: int) -> void:
	if not multiplayer.is_server() or not characters.has(peer_id):
		return
	if peer_id == multiplayer.get_unique_id():
		_receive_character(characters[peer_id])
	else:
		NetworkManager.to_peer(peer_id, "GameState", "_receive_character", [characters[peer_id]])


## Client -> host (via SessionRpc). A client announces the character it will play.
func _submit_character(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_store_submitted(multiplayer.get_remote_sender_id(), data)


## Host -> owner (via SessionRpc). Authoritative character snapshot for local saving.
func _receive_character(data: Dictionary) -> void:
	local_character = data.duplicate(true)
	save_local_character()


func _store_submitted(peer_id: int, data: Dictionary) -> void:
	if not GameData.classes.has(str(data.get("class_id", ""))):
		return
	var clean := new_character(str(data.get("name", "Hero")).substr(0, 20), data.class_id)
	for key in clean:
		if data.has(key):
			clean[key] = data[key]
	characters[peer_id] = clean
	roster[peer_id] = {"name": clean.name, "class_id": clean.class_id, "level": int(clean.level)}
	_broadcast_roster()


# --- Roster --------------------------------------------------------------------------------


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


# --- Game settings (host-only edits) -------------------------------------------------------


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


# --- Session callbacks ---------------------------------------------------------------------


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		NetworkManager.to_peer(id, "GameState", "_sync_settings", [settings])
		NetworkManager.to_peer(id, "GameState", "_sync_roster", [roster])


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		roster.erase(id)
		characters.erase(id)
		_broadcast_roster()


func _on_connected_as_client() -> void:
	if not local_character.is_empty():
		submit_local_character()


func _on_session_closed() -> void:
	roster.clear()
	characters.clear()
	reset_settings()
	roster_changed.emit()
