extends Node
## Dev-only test driver. Does nothing unless launched with user args, e.g.
##   godot --path . -- --auto=host --players=2 --quit=15
##   godot --path . -- --auto=join --quit=15
##   godot --path . -- --auto=solo --quit=10
## It hosts/joins, starts the run, walks right, attacks, and logs what this peer sees.

var _mode := ""
var _quit_after := 0.0
var _walk := true
var _shot := ""
var _shot_at := 3.0
var _open := ""
var _scenario := false
var _hold: PackedStringArray = []
var _ui_settings := ""
var _steamapi := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var wanted := 2
	for a in args:
		if a.begins_with("--auto="):
			_mode = a.get_slice("=", 1)
		elif a.begins_with("--quit="):
			_quit_after = float(a.get_slice("=", 1))
		elif a.begins_with("--players="):
			wanted = int(a.get_slice("=", 1))
		elif a.begins_with("--shot="):
			_shot = a.get_slice("=", 1)
		elif a.begins_with("--shot-at="):
			_shot_at = float(a.get_slice("=", 1))
		elif a.begins_with("--open="):
			_open = a.get_slice("=", 1)
		elif a.begins_with("--setres="):
			Settings.scale_factor = int(a.get_slice("=", 1))
			Settings.apply()
			Settings.save_settings()
		elif a.begins_with("--setmode="):
			Settings.window_mode = int(a.get_slice("=", 1))
			Settings.apply()
			Settings.save_settings()
		elif a == "--printwin":
			await get_tree().create_timer(1.0).timeout
			print("[settings] mode=%d scale=%d vsync=%s window=%s winmode=%d scales=%s" % [Settings.window_mode, Settings.scale_factor, Settings.vsync, get_window().size, get_window().mode, Settings.available_scales()])
		elif a == "--scenario":
			_scenario = true
		elif a.begins_with("--hold="):
			_hold = a.get_slice("=", 1).split(",")
		elif a.begins_with("--ui-settings="):
			_ui_settings = a.get_slice("=", 1)
		elif a == "--steamapi":
			_steamapi = true
		elif a == "--idle":
			_walk = false
	if _steamapi:
		_check_steam_api()
		get_tree().quit()
		return
	if not _ui_settings.is_empty():
		_test_settings_ui()
		return
	if _mode.is_empty():
		if _open.is_empty():
			return
		_mode = "none"
	_run(wanted)


func _run(wanted: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if _open == "settings":
		get_tree().current_scene._open_settings()
	if _open == "play":
		get_tree().current_scene._show_page("play")
	match _mode:
		"solo":
			Net.host_solo()
		"host":
			Net.host_enet()
			await _wait_players(wanted)
			Net.start_run()
			if _scenario:
				_run_scenario()
		"join":
			Net.join_enet("127.0.0.1")
		"steamhost":
			Net.host_steam()
	_log("mode=%s backend=%d" % [_mode, Net.backend])
	var t := 0.0
	while _quit_after <= 0.0 or t < _quit_after:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		if get_tree().get_first_node_in_group("game") and not _hold.is_empty():
			for a in _hold:
				Input.action_press(a)
		if get_tree().get_first_node_in_group("game") and _walk:
			Input.action_press("move_right" if int(t) % 4 < 2 else "move_down")
			Input.action_press("attack")
		_report()
		if not _shot.is_empty() and t == _shot_at:
			get_viewport().get_texture().get_image().save_png(_shot)
	_log("quit")
	Net.shutdown()
	get_tree().quit()


func _wait_players(n: int) -> void:
	var waited := 0.0
	while Net.players.size() < n and waited < 20.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25


func _report() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		_log("scene=%s players=%s" % [get_tree().current_scene.name, Net.players])
		return
	var parts: PackedStringArray = []
	for p in get_tree().get_nodes_in_group("players"):
		parts.append("%s@(%d,%d) hp=%d" % [p.name, p.global_position.x, p.global_position.y, p.hp])
	var enemy_info := ""
	var enemies := get_tree().get_nodes_in_group("enemies")
	if not enemies.is_empty():
		enemies.sort_custom(func(a, b): return str(a.name) < str(b.name))
		enemy_info = " first_enemy=%s@(%d,%d) hp=%d" % [enemies[0].name, enemies[0].global_position.x, enemies[0].global_position.y, enemies[0].hp]
	_log("floor=%d kills=%d enemies=%d over=%s players=[%s]%s" % [
		game.depth, game.kills, enemies.size(), game.hud._over.visible, ", ".join(parts), enemy_info])


func _log(msg: String) -> void:
	print("[auto:%s id=%d] %s" % [_mode, multiplayer.get_unique_id(), msg])


## Host-only: forces the RPC paths a short manual session would exercise.
func _run_scenario() -> void:
	var game: Node = null
	while game == null or game.players_root.get_child_count() < 2 or game.depth < 1:
		await get_tree().create_timer(0.5).timeout
		game = get_tree().get_first_node_in_group("game")
	await get_tree().create_timer(2.0).timeout
	var client_player: Node = null
	for p in game.players_root.get_children():
		if p.name != "1":
			client_player = p
	# a) combat: park the client's player next to an enemy; client holds move_right + attack.
	var enemy: Node = game.enemies_root.get_child(0)
	_log("SCENARIO combat: teleport client next to %s" % enemy.name)
	client_player.teleport.rpc(enemy.global_position - Vector2(12, 0), false)
	await get_tree().create_timer(4.0).timeout
	# b) descent: everyone onto the stairs.
	_log("SCENARIO descent: teleport all players onto stairs")
	for p in game.players_root.get_children():
		p.teleport.rpc(game.stairs.global_position, false)
	await get_tree().create_timer(3.0).timeout
	# c) wipe: lethal damage to everyone.
	_log("SCENARIO wipe: lethal damage")
	for p in game.players_root.get_children():
		p.take_damage.rpc_id(p.get_multiplayer_authority(), 99)
	await get_tree().create_timer(2.0).timeout


func _test_settings_ui() -> void:
	await get_tree().create_timer(1.0).timeout
	var menu := get_tree().current_scene
	menu._open_settings()
	var ui: Node = menu.get_child(menu.get_child_count() - 1)
	await get_tree().create_timer(0.6).timeout
	var before: Dictionary = Settings.snapshot()
	var file_before := FileAccess.get_file_as_string(Settings.PATH)
	ui._res_opt.select(0)
	ui._mode_opt.select(Settings.WindowMode.WINDOWED)
	ui._vsync.button_pressed = false
	ui._on_apply()
	print("[ui] applied: %s window=%s confirming=%s" % [Settings.snapshot(), get_window().size, ui._confirming])
	if _ui_settings == "keep":
		ui._keep()
		print("[ui] kept: file=%s" % FileAccess.get_file_as_string(Settings.PATH).replace("\n", " "))
	else:
		await get_tree().create_timer(11.0).timeout
		print("[ui] after timeout: snapshot=%s before=%s equal=%s file_unchanged=%s" % [
			Settings.snapshot(), before, Settings.snapshot() == before,
			FileAccess.get_file_as_string(Settings.PATH) == file_before])
	get_tree().quit()


func _check_steam_api() -> void:
	var steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	print("[steamapi] singleton=%s class_exists(SteamMultiplayerPeer)=%s" % [steam != null, ClassDB.class_exists("SteamMultiplayerPeer")])
	if steam:
		for m in ["steamInitEx", "createLobby", "joinLobby", "leaveLobby", "setLobbyData", "getLobbyData", "setLobbyJoinable",
				"addRequestLobbyListStringFilter", "addRequestLobbyListDistanceFilter", "requestLobbyList",
				"getLobbyOwner", "getNumLobbyMembers", "getLobbyMemberLimit", "getPersonaName"]:
			print("[steamapi] method %s: %s" % [m, steam.has_method(m)])
		for sig in ["lobby_created", "lobby_joined", "lobby_match_list"]:
			for d in steam.get_signal_list():
				if d.name == sig:
					print("[steamapi] signal %s args=%s" % [sig, d.args.map(func(a): return a.name)])
	if ClassDB.class_exists("SteamMultiplayerPeer"):
		for m in ["create_host", "create_client", "connect_to_lobby", "host_with_lobby"]:
			print("[steamapi] peer.%s: %s" % [m, ClassDB.class_has_method("SteamMultiplayerPeer", m)])
		var props := ClassDB.class_get_property_list("SteamMultiplayerPeer").map(func(p): return p.name)
		print("[steamapi] peer.server_relay property: %s" % props.has("server_relay"))
