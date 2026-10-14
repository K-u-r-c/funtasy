extends Node
## Session management: solo (offline peer), LAN (ENet) and Steam (GodotSteam lobbies +
## SteamMultiplayerPeer, app id 480 = Spacewar test app).
## The host is always peer 1 and owns the game; solo is just a host with no clients.

signal players_changed
signal session_ready
signal session_failed(reason: String)
signal lobby_list_received(lobbies: Array)
signal peer_loaded(id: int)

const APP_ID := 480  # Spacewar, Steam's public test app
const GAME_TAG := "funtasy"  # app 480 is shared with everyone, so lobbies are tagged and filtered
const MAX_PLAYERS := 4
const DEFAULT_PORT := 7777
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"

# Steam constants (values from the Steamworks SDK / GodotSteam docs).
const STEAM_RESULT_OK := 1
const STEAM_LOBBY_TYPE_PUBLIC := 2
const STEAM_LOBBY_COMPARISON_EQUAL := 0
const STEAM_DISTANCE_WORLDWIDE := 3
const STEAM_ENTER_SUCCESS := 1

enum Backend { NONE, SOLO, ENET, STEAM }

var backend: int = Backend.NONE
var steam: Object = null
var steam_ready := false
var steam_status := "GodotSteam extension not loaded"
var lobby_id: int = 0
var players: Dictionary = {}  ## peer id -> display name
var in_run := false
var loaded_peers: Dictionary = {}

var _joining_lobby := false


func _ready() -> void:
	_init_steam()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.steamInitEx(APP_ID, true)
	steam_ready = int(result.get("status", -1)) == 0
	steam_status = str(result.get("verbal", "unknown"))
	if not steam_ready:
		push_warning("Steam init failed: %s" % steam_status)
		return
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_joined.connect(_on_steam_lobby_joined)
	steam.lobby_match_list.connect(_on_steam_lobby_match_list)


func local_name() -> String:
	if steam_ready:
		return str(steam.getPersonaName())
	var user := OS.get_environment("USER")
	return user if not user.is_empty() else "Player"


func is_host() -> bool:
	return multiplayer.is_server()


# --- Starting / joining sessions -------------------------------------------------------


func host_solo() -> void:
	_reset()
	backend = Backend.SOLO
	players = {1: local_name()}
	session_ready.emit()


func host_enet(port: int = DEFAULT_PORT) -> void:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		session_failed.emit("Could not host on port %d (error %d)" % [port, err])
		return
	backend = Backend.ENET
	multiplayer.multiplayer_peer = peer
	players = {1: local_name()}
	session_ready.emit()


func join_enet(address: String, port: int = DEFAULT_PORT) -> void:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		session_failed.emit("Could not connect to %s:%d (error %d)" % [address, port, err])
		return
	backend = Backend.ENET
	multiplayer.multiplayer_peer = peer


func host_steam() -> void:
	if not steam_ready:
		session_failed.emit("Steam unavailable: %s" % steam_status)
		return
	_reset()
	backend = Backend.STEAM
	steam.createLobby(STEAM_LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


func request_steam_lobbies() -> void:
	if not steam_ready:
		session_failed.emit("Steam unavailable: %s" % steam_status)
		return
	steam.addRequestLobbyListStringFilter("game", GAME_TAG, STEAM_LOBBY_COMPARISON_EQUAL)
	steam.addRequestLobbyListDistanceFilter(STEAM_DISTANCE_WORLDWIDE)
	steam.requestLobbyList()


func join_steam(target_lobby: int) -> void:
	if not steam_ready:
		session_failed.emit("Steam unavailable: %s" % steam_status)
		return
	_reset()
	backend = Backend.STEAM
	_joining_lobby = true
	steam.joinLobby(target_lobby)


## Closes the current session and returns to a clean offline state.
func leave() -> void:
	if lobby_id != 0 and steam_ready:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	_joining_lobby = false
	var peer := multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	loaded_peers.clear()
	in_run = false
	backend = Backend.NONE


func leave_to_menu(message: String = "") -> void:
	leave()
	SceneManager.change_scene(MENU_SCENE, message)


## Closes Steam lobby / sockets cleanly; call before quitting.
func shutdown() -> void:
	leave()


# --- Run lifecycle -----------------------------------------------------------------------


func start_run() -> void:
	if not multiplayer.is_server():
		return
	if backend == Backend.STEAM and lobby_id != 0:
		steam.setLobbyJoinable(lobby_id, false)
	if backend == Backend.SOLO:
		_begin_run()
	else:
		_begin_run.rpc()


@rpc("authority", "call_local", "reliable")
func _begin_run() -> void:
	in_run = true
	loaded_peers.clear()
	SceneManager.change_scene(GAME_SCENE)


## The game scene calls this once it is loaded so the host knows when to spawn players.
func notify_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(1)
	else:
		_report_loaded.rpc_id(1)


@rpc("any_peer", "reliable")
func _report_loaded() -> void:
	_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	loaded_peers[id] = true
	peer_loaded.emit(id)


func all_loaded() -> bool:
	for id in players:
		if not loaded_peers.has(id):
			return false
	return true


# --- Player roster -----------------------------------------------------------------------


@rpc("any_peer", "reliable")
func _register_name(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	players[multiplayer.get_remote_sender_id()] = display_name.substr(0, 24)
	_broadcast_players()


func _broadcast_players() -> void:
	_sync_players.rpc(players)


@rpc("authority", "call_local", "reliable")
func _sync_players(roster: Dictionary) -> void:
	players = roster
	players_changed.emit()


# --- Multiplayer callbacks ---------------------------------------------------------------


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if in_run or players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	_broadcast_players()


func _on_connected_to_server() -> void:
	_register_name.rpc_id(1, local_name())
	session_ready.emit()


func _on_connection_failed() -> void:
	leave()
	session_failed.emit("Connection failed")


func _on_server_disconnected() -> void:
	leave_to_menu("Host disconnected")


# --- Steam callbacks ---------------------------------------------------------------------


func _on_steam_lobby_created(result: int, new_lobby: int) -> void:
	if result != STEAM_RESULT_OK:
		session_failed.emit("Steam lobby creation failed (result %d)" % result)
		backend = Backend.NONE
		return
	lobby_id = new_lobby
	steam.setLobbyData(new_lobby, "game", GAME_TAG)
	steam.setLobbyData(new_lobby, "name", "%s's game" % local_name())
	steam.setLobbyJoinable(new_lobby, true)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.create_host(0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer
	players = {1: local_name()}
	session_ready.emit()


func _on_steam_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if not _joining_lobby:
		return  # also fires for the lobby we created ourselves
	_joining_lobby = false
	if response != STEAM_ENTER_SUCCESS:
		session_failed.emit("Could not join Steam lobby (response %d)" % response)
		backend = Backend.NONE
		return
	lobby_id = joined_lobby
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(steam.getLobbyOwner(joined_lobby), 0)
	if err != OK:
		session_failed.emit("Could not connect to lobby host (error %d)" % err)
		return
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	var out: Array = []
	for l in lobbies:
		out.append({
			"id": l,
			"name": str(steam.getLobbyData(l, "name")),
			"count": int(steam.getNumLobbyMembers(l)),
			"max": int(steam.getLobbyMemberLimit(l)),
		})
	lobby_list_received.emit(out)


func _reset() -> void:
	leave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()
