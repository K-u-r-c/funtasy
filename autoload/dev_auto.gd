extends Node
## Dev-only automated test driver. Does nothing unless the game is launched with user args:
##   godot --path . -- --auto=host --players=2 --class=warrior --scenario=full --quit=120
##   godot --path . -- --auto=join --class=mage --quit=120
##   godot --path . -- --auto=solo --class=priest --scenario=gamepad --quit=40
##   godot --path . -- --scenario=rebind | --scenario=rebind_check   (no session)
##   godot --path . -- --auto=steamhost --quit=20                     (Steam lobby smoke test)
## Results are printed as "[test] PASS ..." / "[test] FAIL ..." lines (see tools/run_tests.sh).

var mode := ""
var scenario := ""
var class_id := "warrior"
var gender := ""  ## --gender=male|female (empty = default)
var char_name := ""
var wanted_players := 2
var quit_after := 0.0
var shot := ""
var shot_at := 0.0
var biome := ""  ## --biome=<floor type id> (monster suite, tours)
var tour := ""  ## --tour=<name>[:arg] (screenshot tours)
var only: Array = []  ## --only=a,b: limit a suite to these ids (debugging one legendary)
var window_size := Vector2i.ZERO  ## --window=WxH: resize the window (layout checks per aspect)
var fails := 0
var passes := 0

var _fight := false
var _finishing := false
var _skill_cycle := 0.0
var _seen_visible := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var v := a.get_slice("=", 1)
		if a.begins_with("--auto="):
			mode = v
		elif a.begins_with("--scenario="):
			scenario = v
		elif a.begins_with("--class="):
			class_id = v
		elif a.begins_with("--gender="):
			gender = v
		elif a.begins_with("--name="):
			char_name = v
		elif a.begins_with("--players="):
			wanted_players = int(v)
		elif a.begins_with("--quit="):
			quit_after = float(v)
		elif a.begins_with("--shot="):
			shot = v
		elif a.begins_with("--shot-at="):
			shot_at = float(v)
		elif a.begins_with("--biome="):
			biome = v
			GameState.set_meta("force_biome", v)
		elif a.begins_with("--only="):
			only = Array(v.split(","))
		elif a.begins_with("--tour="):
			tour = v
		elif a.begins_with("--boss="):
			GameState.set_meta("force_boss", v)
		elif a.begins_with("--window="):
			window_size = Vector2i(int(v.get_slice("x", 0)), int(v.get_slice("x", 1)))
	if window_size != Vector2i.ZERO:
		_apply_window_size.call_deferred()
	if mode.is_empty() and scenario.is_empty():
		set_process(false)
		return
	if char_name.is_empty():
		char_name = "Test%s" % mode.capitalize()
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(_finish.bind("timeout"))
	if not shot.is_empty() and not scenario in ["shots", "lobby_shot", "hero_shots", "monster_shots", "tour"]:
		get_tree().create_timer(shot_at).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(shot)
			log_line("screenshot saved to %s" % shot))
	_run.call_deferred()


func _apply_window_size() -> void:
	await get_tree().process_frame
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.size = window_size
	# Tiling Wayland compositors (Hyprland) ignore the requested size: float this process's own
	# window and size it there (test runs only, nothing persistent).
	if OS.has_environment("HYPRLAND_INSTANCE_SIGNATURE"):
		var pid := "pid:%d" % OS.get_process_id()
		OS.execute("hyprctl", ["dispatch", "setfloating", pid])
		OS.execute("hyprctl", ["dispatch", "resizewindowpixel", "exact %d %d,%s" % [window_size.x, window_size.y, pid]])
		OS.execute("hyprctl", ["dispatch", "movewindowpixel", "exact 0 0,%s" % pid])
		for i in 10:
			await get_tree().process_frame
	await get_tree().process_frame
	log_line("window %s -> viewport %s" % [w.size, get_viewport().get_visible_rect().size])


func log_line(msg: String) -> void:
	var id := multiplayer.get_unique_id() if multiplayer and multiplayer.multiplayer_peer else 0
	print("[auto:%s id=%d] %s" % [mode if not mode.is_empty() else scenario, id, msg])


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("[test] PASS %s" % what)
	else:
		fails += 1
		print("[test] FAIL %s" % what)


func _finish(reason: String) -> void:
	if _finishing:
		return
	_finishing = true
	print("[test] SUMMARY %s: %d passed, %d failed (%s)" % [mode if not mode.is_empty() else scenario, passes, fails, reason])
	SceneManager.quit_game(1 if fails > 0 else 0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return cond.call()


# =========================================================================================
# Session flow
# =========================================================================================


func _run() -> void:
	await _wait(0.5)
	match scenario:
		"gamepad_menu":
			await _gamepad_menu_flow()
			return
		"shots":
			await _shots_flow()
			return
		"hero_shots":
			await _hero_shots_flow()
			return
		"preview_grid":
			await _preview_grid_flow()
			return
		"monster_shots":
			await _monster_shots_flow()
			return
		"lobby_shot":
			# Lobby with a saved game selected (visual check), e.g. --shot=/tmp/lobby.png
			NetworkManager.host_solo()
			await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 6.0)
			var games := SaveSystem.list_games()
			if not games.is_empty():
				get_tree().current_scene._game_opt.select(1)
				get_tree().current_scene._on_game_selected(1)
			await _wait(0.8)
			await _snap(shot.get_base_dir(), shot.get_file().get_basename())
			_finish("lobby shot")
			return
		"rebind":
			_rebind_test()
			return
		"rebind_check":
			_rebind_check()
			return
		"art_check":
			_art_check()
			_finish("art check")
			return
		"hero_art":
			await HeroArtSuite.new(self).run()
			_finish("hero art")
			return
	match mode:
		"solo":
			NetworkManager.host_solo()
		"host":
			NetworkManager.host_enet()
		"join":
			NetworkManager.join_enet("127.0.0.1")
		"steamhost":
			await _steam_host_test()
			return
		_:
			return
	var in_lobby := await _wait_until(func(): return get_tree().current_scene and get_tree().current_scene.name == "Lobby", 15.0)
	check(in_lobby, "%s reached the lobby" % mode)
	await _wait(0.5)
	GameState.select_character(char_name, class_id, gender)
	log_line("selected %s (%s)" % [char_name, class_id])
	if multiplayer.is_server():
		var all := await _wait_until(func(): return GameState.roster.size() >= (1 if mode == "solo" else wanted_players), 25.0)
		check(all, "host sees %d players in the roster" % GameState.roster.size())
		if mode != "solo" and scenario == "full":
			GameState.set_setting("friendly_fire", true)
			GameState.set_setting("friendly_fire", false)
		NetworkManager.start_run()
	if not multiplayer.is_server():
		NetworkManager.session_closed.connect(_on_client_session_closed, CONNECT_ONE_SHOT)
	var in_game := await _wait_until(func(): return _game() != null and _game().depth >= 1 and _local() != null, 25.0)
	check(in_game, "%s entered floor 1 with a spawned player" % mode)
	if not in_game:
		_finish("no game")
		return
	if multiplayer.is_server():
		match scenario:
			"full":
				await _full_scenario()
			"gamepad":
				await _gamepad_scenario()
			"wipe":
				await _wipe_scenario()
			"classes":
				await _classes_scenario()
			"skills":
				await SkillSuite.new(self).run_class(class_id)
			"primitives":
				await SkillSuite.new(self).run_primitives()
			"monsters":
				await MonsterSuite.new(self).run(biome)
			"bosses":
				await BossSuite.new(self).run(biome)
			"legendaries":
				await LegendarySuite.new(self).run_legendaries(class_id)
			"progression":
				BalanceSuite.new(self).run_progression()
			"balance":
				await BalanceSuite.new(self).run_fresh()
				await BalanceSuite.new(self).run()
			"biomes":
				await BiomeSuite.new(self).run(biome)
			"economy":
				await EconomySuite.new(self).run()
			"economy_lan":
				await EconomySuite.new(self).run_lan()
			"skills_lan":
				await SkillSuite.new(self).run_lan()
			"anim_lan":
				await AnimSuite.new(self).run_lan()
			"lore":
				await LoreSuite.new(self).run()
			"tour":
				await ShotTour.new(self, shot if not shot.is_empty() else OS.get_user_data_dir().path_join("tour")).run(tour)
			"idle":
				await _wait(9999.0)
			"boss":
				await _boss_scenario()
			"tank":
				await _tank_scenario()
			"continue":
				await _continue_scenario()
			"continue_lan":
				await _continue_lan_scenario()
			"darkness":
				await _darkness_scenario()
			"ui_layout":
				await _ui_layout_scenario()
			"host_leave":
				await _wait(8.0)
				log_line("host ends the session from the pause menu")
				var hud: Node = get_tree().get_first_node_in_group("hud")
				hud.open_overlay(hud.PauseMenu.new())
				await _wait(0.3)
				hud._overlay._leave()
				var at_menu := await _wait_until(func(): return get_tree().current_scene and get_tree().current_scene.name == "MainMenu", 5.0)
				check(at_menu, "host is back in the main menu")
				await _wait(3.0)
			"client_leave":
				await _wait(8.0)
				NetworkManager.to_clients("DevAuto", "client_cmd", ["leave", null])
				await _wait(4.0)
				check(_game().players_root.get_child_count() == 1, "host removed the leaving player")
				check(_game().enemies_root.get_child_count() > 0, "run continues for the host")
				await _wait(2.0)
			_:
				await _wait(3.0)
		_finish("scenario done")


func _on_client_session_closed() -> void:
	if _finishing:
		return
	var ok := await _wait_until(func(): return get_tree().current_scene and get_tree().current_scene.name == "MainMenu", 5.0)
	check(ok, "client returned to the main menu when the session closed")
	await _wait(2.0)
	_finish("session closed")


func _process(delta: float) -> void:
	if not _fight:
		return
	var p := _local()
	var g := _game()
	if p == null or g == null:
		return
	var best: Node2D = null
	var best_d := INF
	for e in g.enemies_root.get_children():
		if e.visible:
			_seen_visible += 1
		var d: float = e.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best:
		p.auto_aim = best.global_position
	if scenario == "classes" and multiplayer.is_server():
		p.resource.value = p.resource.max_value  # test only: every skill must get a turn
	_skill_cycle += delta
	var actions := ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]
	var idx := int(_skill_cycle / 0.7) % actions.size()
	for i in actions.size():
		if i == idx or actions[i] == "attack":
			Input.action_press(actions[i])
		else:
			Input.action_release(actions[i])


func _game() -> Node:
	return get_tree().get_first_node_in_group("game")


func _local() -> Player:
	var g := _game()
	return g.local_player if g and is_instance_valid(g.local_player) else null


func _other_player() -> Player:
	for p in _game().players_root.get_children():
		if p.peer_id != 1:
			return p
	return null


func _nearest_enemy(pos: Vector2, boss: bool = false) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in _game().enemies_root.get_children():
		if e.is_boss != boss or not e.is_alive():
			continue
		var d: float = e.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# =========================================================================================
# Client-side commands sent by the host test driver
# =========================================================================================


## Host -> client (via SessionRpc): run a test step on the client and report.
func client_cmd(cmd: String, arg: Variant) -> void:
	var p := _local()
	match cmd:
		"fight":
			_fight = bool(arg)
			if not _fight:
				for a in ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]:
					Input.action_release(a)
				if p:
					p.auto_aim = Vector2.INF
				check(_seen_visible > 0, "client saw enemies through its own field of view")
		"pickup":
			# Point at the item, as a player would with the mouse.
			var items: Array = _game().items_root.get_children()
			items.sort_custom(func(x, y): return x.global_position.distance_to(p.global_position) < y.global_position.distance_to(p.global_position))
			if not items.is_empty():
				p.auto_aim = items[0].global_position
				await get_tree().physics_frame
				await get_tree().physics_frame
			var target: Dictionary = _game().find_interactable(p)
			for gi in _game().items_root.get_children():
				log_line("item %s at %.0f px" % [gi.item.get("name"), gi.global_position.distance_to(p.global_position)])
			log_line("interact target: %s" % target.get("text", "none"))
			check(target.get("kind", "") == "item", "client finds the dropped item as interact target")
			if not target.is_empty():
				p.request_interact.rpc_id(1, target.node.get_path())
		"equip_uid":
			for i in p.inv.backpack.size():
				if p.inv.backpack[i].get("uid") == arg:
					p.request_equip.rpc_id(1, i)
		"use_q":
			p.request_use_quick.rpc_id(1, "q")
		"check_door":
			var door: Node = _game().dungeon.get_node_or_null(NodePath("../Entities/" + str(arg[0])))
			check(door != null and door.is_open == bool(arg[1]), "client sees door %s open=%s" % [arg[0], arg[1]])
		"use_slots":
			for slot in arg:
				var aim_at: Vector2 = p.global_position + p.facing * 60.0
				var near := _nearest_enemy(p.global_position)
				if near:
					aim_at = near.global_position
				p.request_skill.rpc_id(1, int(slot), aim_at)
				await _wait(1.2)
				p.request_skill_release.rpc_id(1, int(slot), aim_at)
				await _wait(0.4)
		"check_boss_arena":
			await _wait(0.3)
			var bn: Node = _game().enemies_root.get_node_or_null(str(arg[0]))
			check(bn != null and Rect2(arg[1]).has_point(bn.global_position), "client sees the boss back in its arena")
		"check_grab":
			var hud_g: Node = get_tree().get_first_node_in_group("hud")
			var bg: Node = _game().enemies_root.get_node_or_null(str(arg))
			check(not p.held_by.is_empty() and p.status.shown.any(func(x): return str(x[0]) == "engulfed"), "client: held by the boss with the Engulfed status icon")
			check(bg != null and p.global_position.distance_to(bg.global_position) < 16.0, "client: carried inside the boss (%.0f px)" % (p.global_position.distance_to(bg.global_position) if bg else -1.0))
			check(hud_g._burst_bar.visible and str(hud_g._burst_label.text).contains("Burst it down"), "client: the Burst it down bar shows (%s)" % hud_g._burst_label.text)
		"check_released":
			await _wait(0.3)
			check(p.held_by.is_empty() and not get_tree().get_first_node_in_group("hud")._burst_bar.visible, "client: released, the bar is gone")
		"check_windup":
			var lp: Node = _game().enemies_root.get_node_or_null(str(arg))
			check(int(Combat.instance.fx.get_meta("windup_markers", 0)) > 0 and lp != null and lp.has_meta("cast_end"),
					"client sees the leap's cast bar and landing marker")
		"check_prop_gone":
			check(not _game().dungeon.props.has(str(arg)), "client sees floor 2 prop %s destroyed" % arg)
		"check_chest_open":
			var ch: Node = _game().dungeon.props.get(str(arg))
			check(ch != null and ch.opened, "client sees the floor 2 chest opened")
		"check_portal":
			check(_game().portal != null, "client sees the exit portal")
		"check_depth":
			check(_game().depth == int(arg), "client is on floor %d" % int(arg))
		"check_inventory_has":
			var found := false
			for it in p.inv.backpack:
				if it.get("uid") == arg:
					found = true
			for s in p.inv.equipment:
				if p.inv.equipment[s].get("uid") == arg:
					found = true
			check(found, "client inventory snapshot contains traded item")
		"claim_mine":
			var members: Array = GameState.game_info.get("members", [])
			for i in members.size():
				if members[i].name == char_name:
					GameState.claim_slot(i)
		"check_genders":
			var host_p: Player = null
			for q in _game().players_root.get_children():
				if q != p:
					host_p = q
			check(p.gender == str(arg[1]) and host_p != null and host_p.gender == str(arg[0])
					and p.sprite._layer_keys.get("body", "") == CharacterSprite.body_key(str(arg[1])),
					"client sees its %s hero and the host's %s hero" % [p.gender, host_p.gender if host_p else "?"])
		"try_new_hero":
			GameState.choose_new_character("Intruder", "mage")
		"take_torch":
			var ts: Array = _game().dungeon.torches.values()
			ts.sort_custom(func(x, y): return x.global_position.distance_to(p.global_position) < y.global_position.distance_to(p.global_position))
			p.auto_aim = ts[0].global_position
			await get_tree().physics_frame
			await get_tree().physics_frame
			var tgt: Dictionary = _game().find_interactable(p)
			check(tgt.get("kind", "") == "torch", "client finds a wall torch to take (%s)" % tgt.get("text", "none"))
			if not tgt.is_empty():
				p.request_interact.rpc_id(1, tgt.node.get_path())
		"check_torch":
			var wt: Node = _game().dungeon.torches.get(str(arg[0]))
			check(wt != null and wt.state == int(arg[1]) and (p.torch_sync > 0) == bool(arg[2]),
				"client sees torch %s state %d, carrying=%s" % [arg[0], wt.state if wt else -1, p.torch_sync > 0])
		"pick_again":
			GameState.choose_new_character(char_name, class_id, gender)
		"check_life":
			check(p.life_state == int(arg), "client sees its own life state %d (got %d)" % [int(arg), p.life_state])
		"check_lobby":
			check(get_tree().current_scene.name == "Lobby", "client returned to the lobby after the wipe")
		"done":
			_finish.call_deferred("host finished")
		_ when cmd.begins_with("eco_"):
			await EconomySuite.new(self).client_cmd(cmd, arg)
		_ when cmd.begins_with("sk_"):
			await SkillSuite.new(self).client_cmd(cmd, arg)
		_ when cmd.begins_with("an_"):
			await AnimSuite.new(self).client_cmd(cmd, arg)
		"leave":
			log_line("client leaves to the main menu mid-run")
			NetworkManager.leave_to_menu()
			var ok := await _wait_until(func(): return get_tree().current_scene and get_tree().current_scene.name == "MainMenu", 5.0)
			check(ok, "client is back in the main menu after leaving")
			await _wait(2.0)
			_finish.call_deferred("left")


# =========================================================================================
# Scenarios (host)
# =========================================================================================


func _full_scenario() -> void:
	var g := _game()
	var host_p := _local()
	await _wait_until(func(): return _other_player() != null, 10.0)
	var client_p: Player = _other_player()
	check(client_p != null, "client player spawned on the host")
	if client_p == null:
		return
	await _wait(1.5)
	check(g.enemies_root.get_child_count() > 3, "monsters spawned (%d)" % g.enemies_root.get_child_count())
	check(get_tree().get_first_node_in_group("boss") != null, "boss spawned")
	check(g.dungeon.doors.size() > 0, "floor has doors (%d)" % g.dungeon.doors.size())
	check(g.dungeon.props.size() > 0, "floor has props (%d)" % g.dungeon.props.size())

	# --- 1. Combat: client fights a monster with attack + skills 1-5 -----------------------
	var target := _nearest_enemy(client_p.global_position)
	var spot: Vector2 = g.nearest_floor(target.global_position + Vector2(-50, 0))
	for off in [Vector2(-50, 0), Vector2(50, 0), Vector2(0, 50), Vector2(0, -50), Vector2(-35, 35), Vector2(35, -35)]:
		var cand: Vector2 = g.nearest_floor(target.global_position + off)
		if Combat.instance.has_los(cand, target.global_position):
			spot = cand
			break
	client_p.host_teleport(spot)
	host_p.host_teleport(g.nearest_floor(spot + Vector2(-30, 0)))
	# The fight checks skill use and kill credit, not survival: a pack must not wipe the party
	# (that ends the run and the rest of the scenario). Downed / revive are tested later.
	host_p.iframe_left = 12.0
	client_p.iframe_left = 12.0
	var xp_before := client_p.xp + client_p.level * 100000
	# Kill credit is what is checked, not the pack's toughness (wights, footmen that reassemble).
	for e in g.enemies_root.get_children():
		if e is Enemy and not e.is_boss and e.global_position.distance_to(target.global_position) < 260.0:
			e.health.hp = e.health.max_hp * 0.15
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", true])
	await _wait(9.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", false])
	# The fight's input cycle can miss a slot's window (a charge-up skill, a busy moment): the
	# client then asks for every bar skill it hasn't used yet, still through the host.
	var used := Combat.instance.get_meta("uses", {}) as Dictionary
	var missing: Array = []
	for i in client_p.skills.size():
		if not str(client_p.skills[i]).is_empty() and not used.has("%s:%s" % [client_p.name, client_p.skills[i]]):
			missing.append(i)
	if not missing.is_empty():
		client_p.resource.value = client_p.resource.max_value
		NetworkManager.to_clients("DevAuto", "client_cmd", ["use_slots", missing])
		await _wait(1.6 * missing.size() + 0.5)
	used = Combat.instance.get_meta("uses", {}) as Dictionary
	var client_uses := 0
	for k in used:
		if str(k).begins_with(client_p.name + ":"):
			client_uses += 1
	var client_bar := client_p.skills.filter(func(x): return not str(x).is_empty()).size()
	check(client_uses >= client_bar, "client used %d different skills through host validation (%d on the bar)" % [client_uses, client_bar])
	check(client_p.cooldowns.size() > 0 or client_uses > 0, "host tracks client cooldowns")
	check(not is_instance_valid(target) or target.health.hp < target.health.max_hp, "client damaged the monster (host authority)")
	if client_p.xp + client_p.level * 100000 <= xp_before and not (is_instance_valid(target) and target.is_alive() and target.is_targetable()):
		# The host's cleave can finish the target before the client touches it (or it is out of
		# reach underground): any XP monster that can be hit will do.
		target = null
		for e in g.enemies_root.get_children():
			if e is Enemy and not e.is_boss and e.is_alive() and e.is_targetable() and int(e.def.get("xp", 0)) > 0:
				if target == null or e.global_position.distance_to(client_p.global_position) < target.global_position.distance_to(client_p.global_position):
					target = e
	if client_p.xp + client_p.level * 100000 <= xp_before and is_instance_valid(target) and target.is_alive():
		# The pack outlasted the 9 s fight (reassembling footmen, burrowed crawlers): the client
		# lands the killing blow so kill credit is still what gets checked.
		var kctx := Combat.instance.make_ctx(client_p, GameData.skill(str(client_p.skills[0])))
		Combat.instance.deal_damage(kctx, target, target.health.hp + target.health.absorb + 999.0, {"damage_type": "true", "area": true})
		await _wait(0.5)
	check(client_p.xp + client_p.level * 100000 > xp_before, "client earned XP for kills")
	log_line("client resource %s %.1f/%.1f" % [client_p.resource.kind, client_p.resource.value, client_p.resource.max_value])
	# Isolate the remaining checks from the monsters that are still chasing the party.
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	await _wait(0.3)
	for pl in [host_p, client_p]:
		_reset_player(pl)

	# --- 2. Threat / aggro hysteresis on a real monster --------------------------------------
	var m: Enemy = g.spawn_monster("ghoul", g.nearest_floor(host_p.global_position + Vector2(60, 0)), false)
	await _wait(0.3)
	m.threat.clear()
	m.add_threat(host_p, 100.0)
	m.add_threat(client_p, 60.0)
	var t1: Node = m.threat.update(0.1, m._valid_target)
	var ratio: float = m.threat._switch_ratio(client_p)
	m.add_threat(client_p, 100.0 * ratio - 60.0 - 5.0)  # just below the threshold: no switch
	var t2: Node = m.threat.update(0.1, m._valid_target)
	m.add_threat(client_p, 10.0)  # just above: switches
	var t3: Node = m.threat.update(0.1, m._valid_target)
	check(t1 == host_p and t2 == host_p and t3 == client_p, "threat table keeps target until challenger exceeds %d%%" % roundi(ratio * 100.0))
	m.taunted_by(host_p, 3.0)
	check(m.threat.update(0.1, m._valid_target) == host_p, "taunt forces the target")
	m.queue_free()

	# --- 2b. Monster abilities (melee, ranged, caster heal/curse/bolt) ------------------------
	host_p.iframe_left = 30.0
	client_p.iframe_left = 30.0
	var pack: Array = []
	for mid in ["ghoul", "skeleton_archer", "cultist", "cultist"]:
		pack.append(g.spawn_monster(mid, g.nearest_floor(host_p.global_position + Vector2(randf_range(-90, 90), randf_range(-60, 60))), false))
	await _wait(0.3)
	for e in pack:
		e.add_threat(host_p, 5.0)
	pack[0].health.hp = pack[0].health.max_hp * 0.3  # something for the cultists to heal
	await _wait(12.0)
	var m_uses := Combat.instance.get_meta("uses", {}) as Dictionary
	for sid in ["ghoul_claw", "skeleton_arrow", "cultist_bolt", "cultist_curse", "cultist_mend"]:
		var seen := false
		for k in m_uses:
			if str(k).ends_with(":" + sid):
				seen = true
		check(seen, "monster AI used %s" % sid)
	for e in pack:
		if is_instance_valid(e):
			e.queue_free()
	host_p.iframe_left = 0.0
	client_p.iframe_left = 0.0
	_reset_player(host_p)
	await _wait(0.3)

	# --- 2b'. A monster leap winds up with a cast bar and a landing marker the client sees too (#2)
	client_p.iframe_left = 30.0
	var leaper: Enemy = g.spawn_monster("ghoul", g.nearest_floor(client_p.global_position + Vector2(140, 0)), false)
	await _wait(0.3)
	leaper.behaviors = []
	leaper.add_threat(client_p, 50.0)
	leaper._aggro_since -= 5.0
	var leap_err := Combat.instance.try_use_skill(leaper, "ghoul_pounce", client_p.global_position)
	check(leap_err.is_empty() and float(leaper.casting.get("left", 0.0)) >= 0.8, "host: the ghoul winds up its pounce (%s)" % leap_err)
	await _wait(0.3)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_windup", str(leaper.name)])
	await _wait(1.5)
	if is_instance_valid(leaper):
		leaper.queue_free()
	client_p.iframe_left = 0.0
	_reset_player(client_p)
	await _wait(0.3)

	# --- 2c. Hazards + friendly fire -----------------------------------------------------------
	await _hazard_checks(g, host_p, client_p)

	_reset_player(host_p)
	host_p.iframe_left = 30.0
	await _interaction_choice_checks(g, host_p)
	# --- 3. Doors -----------------------------------------------------------------------------
	# A plain door the host can reach, with nobody standing in its doorway (an open door
	# never closes on someone).
	var door: Node = g.dungeon.doors[0]
	var reach := float(GameData.bal("world.interact_range")) + 20.0
	for dr in g.dungeon.doors:
		if dr.floodgate or dr.monster_proof:
			continue
		var stand: Vector2 = g.nearest_floor(dr.interact_pos() + Vector2(0, 40))
		var blocked := Combat.instance.all_actors().any(func(a): return dr.world_rect.grow(4).has_point(a.global_position))
		if stand.distance_to(dr.interact_pos()) <= reach and not blocked:
			door = dr
			break
	host_p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 40)))
	await _wait(0.4)
	# A monster that wandered into the doorway meanwhile would keep it open: move it off.
	for e in g.enemies_root.get_children():
		if door.world_rect.grow(24).has_point(e.global_position):
			e.host_teleport(g.layout.start)
	var was_open: bool = door.is_open
	g.host_interact(host_p, door)
	await _wait(0.4)
	if door.is_open == was_open:
		print("[auto:host] door %s not toggled: hero %.0f px from it, open %s" % [door.name, host_p.global_position.distance_to(door.interact_pos()), was_open])
	check(door.is_open != was_open, "host toggled a door")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_door", [door.name, door.is_open]])
	await _wait(0.5)

	# --- 4. Items: drop -> pick up -> equip (trade), appearance, off-class penalty ------------
	var rng := RandomNumberGenerator.new()
	var weapon_base: String = {"warrior": "sword", "ranger": "bow", "mage": "arcane_wand", "priest": "holy_staff"}[client_p.class_id]
	var item := ItemGenerator.generate_equipment(weapon_base, 1, 3, rng)
	check(host_p.host_give_item(item).is_empty(), "host player received a rare %s" % weapon_base)
	var drop_at: Vector2 = host_p.global_position
	host_p.request_drop.rpc_id(1, true, str(host_p.inv.backpack.size() - 1))
	await _wait(0.5)
	check(g.items_root.get_child_count() > 0, "item dropped on the ground")
	client_p.host_teleport(drop_at + host_p.facing * 18.0)
	await _wait(0.8)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["pickup", null])
	await _wait(1.0)
	var has := false
	for it in client_p.inv.backpack:
		if it.get("uid") == item.uid:
			has = true
	check(has, "client picked up the item dropped by the host (trade)")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_inventory_has", item.uid])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["equip_uid", item.uid])
	await _wait(0.8)
	check(client_p.inv.equipment.get("main_hand", {}).get("uid") == item.uid, "client equipped the traded weapon")
	check(client_p.appearance.has("weapon"), "weapon appearance layer replicated (%s)" % str(client_p.appearance.get("weapon", ["none"])[0]))
	check(not bool(client_p.stats.final.get("offclass", true)), "own-class weapon has no penalty")
	var off_base := "bow" if client_p.class_id != "ranger" else "sword"
	var off_item := ItemGenerator.generate_equipment(off_base, 1, 1, rng)
	client_p.host_give_item(off_item)
	await _wait(0.3)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["equip_uid", off_item.uid])
	await _wait(0.8)
	var dm := float(client_p.stats.final.get("damage_mult", 1.0))
	check(bool(client_p.stats.final.get("offclass", false)) and absf(dm - 0.2) < 0.05, "off-class weapon: damage x%.2f and cooldown x%.1f" % [dm, client_p.stats.final.get("cooldown_mult", 1.0)])
	var cd_off: float = client_p.stats.cooldown_for(GameData.skill(client_p.skills[1]))
	check(cd_off > float(GameData.skill(client_p.skills[1]).cooldown) * 1.2, "off-class weapon lengthens cooldowns (%.1fs)" % cd_off)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["equip_uid", item.uid])
	await _wait(0.5)

	# --- 5. Consumables on Q ------------------------------------------------------------------
	var potion := ItemGenerator.generate_consumable("potion_health", 2, rng)
	var potions_before := client_p.inv.count_of("potion_health")
	client_p.host_give_item(potion)
	await _wait(0.3)
	check(client_p.inv.quick.get("q", "") == "potion_health" or client_p.inv.quick.get("e", "") == "potion_health", "potion auto-assigned to a quick slot")
	client_p.inv.quick["q"] = "potion_health"
	# Nothing else may touch the client's health while the potion is checked (DoTs from the
	# hazard steps, a stray monster).
	client_p.status.clear_all()
	client_p.iframe_left = 3.0
	client_p.health.hp = client_p.health.max_hp * 0.3
	NetworkManager.to_clients("DevAuto", "client_cmd", ["use_q", null])
	await _wait(0.6)
	check(client_p.inv.count_of("potion_health") == potions_before + 1 and client_p.health.fraction() > 0.5, "Q potion consumed and healed (left %d, hp %.0f%%)" % [client_p.inv.count_of("potion_health"), client_p.health.fraction() * 100.0])

	# --- 6. Downed -> revive ------------------------------------------------------------------
	# The host is only a helper from here on; keep it standing so a stray hit can't turn the
	# client's (intentional) death into a party wipe.
	_reset_player(host_p)
	host_p.iframe_left = 60.0
	var near_host: Vector2 = host_p.global_position
	for off in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
		var cand: Vector2 = host_p.global_position + off
		if g.dungeon.cell_at(g.dungeon.cell_of(cand)) == DungeonGenerator.CELL_FLOOR and Combat.instance.has_los(host_p.global_position, cand):
			near_host = cand
			break
	client_p.host_teleport(near_host)
	await _wait(0.4)
	client_p.iframe_left = 0.0
	Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), client_p, 99999.0)
	await _wait(0.3)
	check(client_p.life_state == Player.Life.DOWNED, "lethal damage downs the player")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_life", Player.Life.DOWNED])
	host_p.request_revive.rpc_id(1, client_p.peer_id, true)
	await _wait(float(GameData.bal("player.revive_channel")) + 0.6)
	check(client_p.life_state == Player.Life.ALIVE, "teammate revived the downed player")

	# --- 7. Downed -> ghost after the timer ---------------------------------------------------
	client_p.iframe_left = 0.0
	Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), client_p, 99999.0)
	await _wait(float(GameData.bal("player.downed_time")) + 0.8)
	check(client_p.life_state == Player.Life.GHOST, "unrevived player becomes a ghost")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_life", Player.Life.GHOST])
	check(not g._wiped, "one ghost with a living teammate is not a wipe")

	# --- 8. Boss -> portal -> floor 2 ---------------------------------------------------------
	var boss: Enemy = _nearest_enemy(host_p.global_position, true)
	check(boss != null, "boss found")
	var host_xp := host_p.xp + host_p.level * 100000
	host_p.host_teleport(g.nearest_floor(boss.global_position + Vector2(0, 120)))
	await _wait(0.5)
	# Let the boss fight for real (host player immune) through both phases.
	host_p.iframe_left = 60.0
	boss.add_threat(host_p, 10.0)
	await _wait(1.0)
	check(g.boss_engaged, "boss engaged (boss music + HUD bar)")
	await _wait(14.0)
	host_p.iframe_left = 60.0
	boss.health.absorb = 0.0
	boss.health.hp = boss.health.max_hp * maxf(float(boss.def.phases[boss.def.phases.size() - 2].hp_above) - 0.05, 0.05)
	await _wait(12.0)
	check(boss.phase == boss.def.phases.size() - 1, "%s entered its last phase" % boss.display_name)
	var boss_uses: Array = []
	for k in (Combat.instance.get_meta("uses", {}) as Dictionary):
		if str(k).begins_with(boss.name + ":"):
			boss_uses.append(str(k).get_slice(":", 1))
	var boss_abilities: Array = []
	for ph in boss.def.phases:
		for sid in ph.abilities:
			if not boss_abilities.has(sid):
				boss_abilities.append(sid)
	for sid in boss_abilities:
		check(boss_uses.has(sid), "boss used %s" % sid)
	host_p.iframe_left = 0.0
	_reset_player(host_p)
	var ctx := Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0]))
	ctx.crit_chance = 0.0
	ctx.school = "spell"  # reaches a flying boss too
	var guard := 0
	while is_instance_valid(boss) and boss.is_alive() and guard < 400:
		guard += 1
		boss.stats.final.dodge = 0.0
		Combat.instance.deal_damage(ctx, boss, boss.health.max_hp * 0.08)
		await get_tree().physics_frame
	check(not is_instance_valid(boss) or not boss.is_alive(), "boss defeated")
	await _wait(1.0)
	check(g.portal != null, "exit portal opened on the host")
	check(g.items_root.get_child_count() >= 3, "boss dropped bonus loot (%d items on the ground)" % g.items_root.get_child_count())
	check(host_p.xp + host_p.level * 100000 > host_xp, "host earned boss XP")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_portal", null])
	for e in g.enemies_root.get_children():
		e.queue_free()  # the boss's summons would otherwise keep fighting the waiting players
	host_p.iframe_left = 60.0
	# Standing in the portal does nothing; every living player has to interact with it.
	for pl in g.players_root.get_children():
		pl.host_teleport(g.portal.global_position + Vector2(randf_range(-12, 12), 6))
	await _wait(2.5)
	check(g.depth == 1, "walking into the portal doesn't descend")
	host_p.host_teleport(g.portal.global_position + Vector2(0, 30))
	await _wait(0.4)
	host_p.auto_aim = g.portal.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pt: Dictionary = g.find_interactable(host_p)
	check(pt.get("kind", "") == "portal", "the portal is an interaction (%s)" % pt.get("text", "none"))
	host_p.auto_aim = Vector2.INF
	_descend_all(g)
	# Extra presses during the countdown (an impatient player) must not carry over to floor 2.
	g.host_interact(host_p, g.portal)
	g.host_interact(host_p, g.portal)
	await _wait(3.0)
	check(g.depth == 2, "party descended to floor 2")
	check(g.portal_ready.is_empty(), "portal readiness reset on the new floor")
	await _wait(1.0)
	check(client_p.life_state == Player.Life.ALIVE, "ghost revived on the next floor")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_depth", 2])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_life", Player.Life.ALIVE])
	var saved := SaveSystem.load_game(str(GameState.game.get("id", "")))
	var slot := int(GameState.roster[client_p.peer_id].slot)
	check(not saved.is_empty() and int(saved.depth) == 2 and int(saved.party_size) == 2 \
		and int(saved.members[slot].level) == client_p.level, "host saved the game: floor 2, 2 players, client hero level %d" % client_p.level)
	check(g.enemies_root.get_child_count() > 3, "floor 2 populated with monsters")
	await _wait(1.0)
	await _floor2_props_check(g, host_p)
	await _wait(1.0)
	# The next floor's portal asks again: nobody descends until they interact with it.
	g._boss_defeated.rpc(g.nearest_floor(host_p.global_position + Vector2(0, 40)))
	await _wait(2.5)
	check(g.depth == 2 and g.portal != null and g.portal_ready.is_empty(), "a new portal waits for the players to opt in again")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


func _hazard_checks(g: Node, host_p: Player, client_p: Player) -> void:
	# Everything here runs in the start room: it has no props, monsters or hazards of its own.
	var c: Vector2 = g.layout.start
	_reset_player(host_p)
	_reset_player(client_p)
	# Explosive barrel destroyed by a player: monsters always hurt, allies only with friendly fire.
	for ff in [false, true]:
		GameState.set_setting("friendly_fire", ff)
		var spot := c + Vector2(0, 40)
		g.dungeon._add_prop("TestBarrel%s" % ff, "barrel_explosive", spot)
		var ghoul: Enemy = g.spawn_monster("ghoul", spot + Vector2(30, 0), false)
		host_p.host_teleport(c + Vector2(0, -90))
		client_p.host_teleport(spot + Vector2(-30, 0))
		await _wait(0.8)
		ghoul.set_physics_process(false)
		ghoul.stats.final.dodge = 0.0
		_reset_player(client_p)
		client_p.iframe_left = 0.0
		var hp_c := client_p.health.hp
		var hp_g := ghoul.health.hp
		g.dungeon.props["TestBarrel%s" % ff].take_damage(999.0, Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0])))
		await _wait(0.4)
		# The weaker floor-1 ghoul (#8) may die to the blast: that hurt it too.
		check(not is_instance_valid(ghoul) or ghoul.health.hp < hp_g or not ghoul.is_alive(), "player-triggered barrel explosion hurts monsters (FF %s)" % ff)
		check(client_p.health.hp < hp_c, "an explosive barrel hurts players in range too (FF %s)" % ff)
		if is_instance_valid(ghoul):
			ghoul.queue_free()
		await _wait(0.2)
	# A player's projectile vs an ally.
	host_p.host_teleport(c + Vector2(-70, -40))
	client_p.host_teleport(c + Vector2(70, -40))
	await _wait(0.8)
	var proj_skill := {"id": "test_bolt", "school": "spell", "effects": [{"type": "projectile", "sprite": "magic", "speed": 600, "range": 300, "radius": 8, "damage": {"base": 10, "coef": 0.0}}]}
	var pctx := Combat.instance.make_ctx(host_p, proj_skill)
	pctx.crit_chance = 0.0
	for ff2 in [true, false]:
		GameState.set_setting("friendly_fire", ff2)
		_reset_player(client_p)
		client_p.iframe_left = 0.0
		var before := client_p.health.hp
		Combat.instance.run_effect(proj_skill.effects[0], pctx, host_p.global_position, client_p.global_position)
		await _wait(0.6)
		if ff2:
			check(client_p.health.hp < before, "friendly fire ON: projectile hits an ally")
		else:
			check(client_p.health.hp == before, "friendly fire OFF: projectile passes allies")
	# Lava and spikes hurt players.
	if not g.layout.lava_pools.is_empty():
		var pool: Rect2i = g.layout.lava_pools[0]
		_reset_player(client_p)
		client_p.iframe_left = 0.0
		client_p.host_teleport(g.dungeon.cell_center(pool.get_center()))
		await _wait(1.3)
		check(client_p.health.hp < client_p.health.max_hp, "standing in lava hurts")
	else:
		log_line("no lava on this floor, lava check skipped")
	if not g.dungeon.spikes.is_empty():
		_reset_player(client_p)
		client_p.iframe_left = 0.0
		client_p.host_teleport(g.dungeon.spikes[0].position)
		await _wait(3.2)
		check(client_p.health.hp < client_p.health.max_hp, "raised spikes hurt")
	client_p.host_teleport(c + Vector2(40, 60))
	_reset_player(client_p)
	# A destructible prop between the viewer (host) and a monster hides it; breaking it reveals it.
	host_p.host_teleport(c + Vector2(-100, 0))
	await _wait(0.5)
	var watcher: Enemy = g.spawn_monster("skeleton_archer", c + Vector2(60, 0), false)
	watcher.set_physics_process(false)  # frozen at once: a strafing archer could step out of the crate's shadow
	await _wait(0.7)
	check(watcher.visible, "monster in plain sight is visible")
	g.dungeon._add_prop("TestCrate", "crate", c + Vector2(-20, 6))
	await _wait(0.4)
	check(not watcher.visible, "destructible prop blocks line of sight")
	g.dungeon.props["TestCrate"].take_damage(999.0, Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0])))
	await _wait(0.4)
	check(watcher.visible, "destroying the prop reveals the monster")
	watcher.queue_free()
	_reset_player(host_p)
	_reset_player(client_p)
	await _wait(0.2)


## Regression: after descending, props must still break and chests must open only once
## (the previous floor's nodes used to keep their names and the new ones got renamed).
func _floor2_props_check(g: Node, host_p: Player) -> void:
	var renamed := 0
	for id in g.dungeon.props:
		if str(g.dungeon.props[id].name) != str(id):
			renamed += 1
	check(renamed == 0, "floor 2 prop nodes keep their ids (%d renamed)" % renamed)
	var target: Node = null
	var chest: Node = null
	for id in g.dungeon.props:
		var pr: Node = g.dungeon.props[id]
		if target == null and pr.destructible() and not pr.def.has("explode"):
			target = pr
		if chest == null and pr.interactable() and pr.type == "chest":
			chest = pr
	if target:
		var tid: String = target.prop_id
		target.take_damage(9999.0, Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0])))
		await _wait(0.5)
		check(not g.dungeon.props.has(tid), "floor 2 prop %s destroyed on the host" % tid)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_prop_gone", tid])
	if chest:
		host_p.host_teleport(g.nearest_floor(chest.global_position + Vector2(0, 20)))
		await _wait(0.6)
		# Only drops next to the chest count: monsters dying elsewhere drop loot too.
		var near_chest := func() -> int:
			return g.items_root.get_children().filter(func(it: Node): return it.global_position.distance_to(chest.global_position) < 100.0).size()
		var before: int = near_chest.call()
		g.host_interact(host_p, chest)
		await _wait(0.4)
		var after_first: int = near_chest.call()
		g.host_interact(host_p, chest)
		await _wait(0.4)
		var after_second: int = near_chest.call()
		check(chest.opened and after_first > before and after_second == after_first,
			"floor 2 chest opens once (no bottomless chest; opened %s, items %d -> %d -> %d, %.0f px away)" % [chest.opened, before, after_first, after_second,
			host_p.global_position.distance_to(chest.global_position)])
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_chest_open", chest.prop_id])
	else:
		log_line("no chest on floor 2, chest check skipped")
	await _wait(0.5)


## Every living player interacts with the portal (that's how the party descends).
func _descend_all(g: Node) -> void:
	for pl in g.players_root.get_children():
		if pl.life_state == Player.Life.ALIVE:
			pl.host_teleport(g.portal.global_position + Vector2(randf_range(-10, 10), 4))
			g.host_interact(pl, g.portal)


## Picking an interaction: the mouse points at it; on a gamepad the character faces it.
func _interaction_choice_checks(g: Node, host_p: Player) -> void:
	var spot: Vector2 = g.layout.start
	host_p.host_teleport(spot)
	var rng := RandomNumberGenerator.new()
	g.loot.drop_item(ItemGenerator.generate_consumable("potion_health", 1, rng), spot + Vector2(-26, 0))
	g.loot.drop_item(ItemGenerator.generate_consumable("potion_mana", 1, rng), spot + Vector2(26, 0))
	await _wait(0.6)
	var left: Node = null
	var right: Node = null
	for it in g.items_root.get_children():
		if it.global_position.distance_to(spot + Vector2(-26, 0)) < 4.0:
			left = it
		elif it.global_position.distance_to(spot + Vector2(26, 0)) < 4.0:
			right = it
	for side in [[left, "left"], [right, "right"]]:
		host_p.auto_aim = side[0].global_position + Vector2(0, -6)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(g.find_interactable(host_p).get("node") == side[0], "mouse: the item under the cursor (%s) is chosen" % side[1])
	host_p.auto_aim = Vector2.INF
	InputSettings.using_gamepad = true
	for side in [[left, Vector2.LEFT, "left"], [right, Vector2.RIGHT, "right"]]:
		host_p.facing = side[1]
		check(g.find_interactable(host_p).get("node") == side[0], "gamepad: the item the character faces (%s) is chosen" % side[2])
	InputSettings.using_gamepad = false
	left.queue_free()
	right.queue_free()
	await _wait(0.2)


func _reset_player(p: Player) -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.health.hp = p.health.max_hp
	p.status.clear_all()


## Both players kill the boss with their real skills (kept alive with i-frames so the test
## doesn't depend on balance), then walk into the portal.
func _boss_scenario() -> void:
	var g := _game()
	var host_p := _local()
	await _wait_until(func(): return g.players_root.get_child_count() >= GameState.roster.size(), 10.0)
	await _wait(1.0)
	var boss: Enemy = _nearest_enemy(host_p.global_position, true)
	var spot: Vector2 = g.nearest_floor(boss.global_position + Vector2(0, 100))
	for p in g.players_root.get_children():
		p.host_teleport(spot + Vector2(randf_range(-30, 30), 0))
	await _wait(0.6)
	await _boss_guard_and_grab_checks(g, boss)
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", true])
	_fight = true
	var t := 0.0
	var start_hp := boss.health.hp
	while is_instance_valid(boss) and boss.is_alive() and t < 240.0:
		for p in g.players_root.get_children():
			p.iframe_left = 2.0
			if p.life_state != Player.Life.ALIVE:
				p.revive(1.0)
			if p.global_position.distance_to(boss.global_position) > 260.0 and not p.status.has("tome_prison"):
				p.host_teleport(g.nearest_floor(boss.global_position + Vector2(0, 90)))
		await _wait(1.0)
		t += 1.0
		if int(t) % 30 == 0 and is_instance_valid(boss):
			print("[auto:host] boss %s at %d s: HP %d / %d, phase %d" % [boss.def_id, t, boss.health.hp, boss.health.max_hp, boss.phase])
	_fight = false
	for a in ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]:
		Input.action_release(a)
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", false])
	var dead := not is_instance_valid(boss) or not boss.is_alive()
	check(dead, "players killed the boss with their skills in %d s (boss HP %d at start)" % [t, start_hp])
	if not dead:
		return
	await _wait(1.0)
	check(g.portal != null, "portal opened")
	_descend_all(g)
	var down := await _wait_until(func(): return g.depth == 2, 8.0)
	check(down, "party reached floor 2 through the portal")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_depth", 2])
		await _wait(0.5)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


## #12: the arena guard puts a boss that left its arena back in the middle; the Amalgam's grab
## holds a hero visibly (status, pinned to the boss, "Burst it down" bar on every screen) for at
## most 4 s and lets go when it ends or the boss dies.
func _boss_guard_and_grab_checks(g: Node, boss: Enemy) -> void:
	var r: Rect2i = g.layout.rooms[int(g.layout.boss_room)].rect
	var t := float(g.dungeon.tile)
	var arena := Rect2(Vector2(r.position) * t, Vector2(r.size) * t).grow(t)
	var back_before: int = boss.arena_returns
	boss.host_teleport(g.layout.start)
	await _wait(0.8)
	check(arena.has_point(boss.global_position) and boss.arena_returns > back_before, "a boss outside its arena is put back in the middle (%s)" % boss.def_id)
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_boss_arena", [boss.name, arena]])
		await _wait(0.6)
	var eng: BossMechanic = null
	for m in boss.mechanics:
		if str(m.get_script().resource_path).ends_with("engulf.gd"):
			eng = m
	var victim := _other_player()
	if eng == null or victim == null:
		return
	victim.iframe_left = 30.0
	boss.target = victim
	eng.trigger()
	check(eng.victim == victim and victim.held_by == boss.get_path() and boss.burst_bar.y > 0.0 and victim.status.has("engulfed"),
			"the Amalgam grabs the client: held, Engulfed, a Burst it down bar")
	await _wait(0.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_grab", str(boss.name)])
	var held := 0.0
	var stayed := true
	while eng.victim != null and held < 6.0:
		stayed = stayed and arena.has_point(boss.global_position)
		await _wait(0.1)
		held += 0.1
	check(stayed, "the boss stays in its arena during the grab")
	check(eng.victim == null and victim.held_by.is_empty() and eng.longest <= 4.05 and boss.burst_bar == Vector2.ZERO,
			"the grab lets go after at most 4 s (%.2f s)" % eng.longest)
	check(arena.has_point(boss.global_position), "the boss is still in its arena after the grab")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_released", null])
	await _wait(0.4)
	# The boss dying (its mechanics stop) releases a held hero at once.
	boss.target = victim
	eng.trigger()
	await _wait(0.3)
	eng.stop()
	check(victim.held_by.is_empty() and not victim.status.has("engulfed"), "a held hero is released when the boss dies")
	if not victim.is_alive():
		victim.revive(1.0)
	await _wait(0.3)


## Real aggro check: the host (tank class) and a damage dealer both fight a monster pack with
## their normal rotations; the pack should stay on the tank and not flip-flop.
func _tank_scenario() -> void:
	var g := _game()
	var tank := _local()
	await _wait_until(func(): return _other_player() != null, 10.0)
	var dps := _other_player()
	var c: Vector2 = g.layout.start
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	await _wait(0.3)
	tank.host_teleport(c + Vector2(0, 0))
	dps.host_teleport(c + Vector2(-120, 30))
	await _wait(0.6)
	var pack: Array = []
	for i in 4:
		# Skeletal footmen: no behaviour that picks its own target (a ghoul's pounce would).
		pack.append(g.spawn_monster("skeletal_footman", c + Vector2(110, -40 + i * 26), false))
	await _wait(0.3)
	for e in pack:
		e.hp_mult *= 25.0  # test only: long enough fight to measure aggro
		e.recompute_stats()
		e.health.hp = e.health.max_hp
	_fight = true
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", true])
	var on_tank := 0
	var samples := 0
	var switches := 0
	var rapid := 0  # target changed and changed back within 2 s = erratic
	var last: Dictionary = {}
	var last_switch: Dictionary = {}
	var t := 0.0
	while t < 25.0:
		for p in [tank, dps]:
			p.iframe_left = 2.0
			if p.life_state != Player.Life.ALIVE:
				p.revive(1.0)
		await _wait(0.5)
		t += 0.5
		if t < 2.0:
			continue  # let the tank open the fight
		for e in pack:
			if not is_instance_valid(e) or not e.is_alive() or e.target == null:
				continue
			if e.target != tank and e.target != dps:
				continue  # decoys (the Mage's Blink image) pull aggro on purpose for a moment
			samples += 1
			if e.target == tank:
				on_tank += 1
			if last.has(e) and last[e] != e.target:
				switches += 1
				# A taunt pulling the monster back is the tank doing its job, not a flip-flop.
				var taunted: bool = e.threat._taunt_left > 0.0 and e.target == e.threat._taunt_by
				if last_switch.has(e) and t - float(last_switch[e]) < 2.0 and not taunted:
					rapid += 1
					log_line("rapid switch %s at %.1f s -> %s; threat tank %.0f dps %.0f, taunt %.1f s, state '%s'" % [e.name, t,
						e.target.name, e.threat.value_of(tank), e.threat.value_of(dps), e.threat._taunt_left, e.behavior_state])
				last_switch[e] = t
			last[e] = e.target
		var alive := 0
		for e in pack:
			if is_instance_valid(e) and e.is_alive():
				alive += 1
		if alive == 0:
			break
		pass
	_fight = false
	for a in ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]:
		Input.action_release(a)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", false])
	var share := float(on_tank) / maxf(samples, 1.0)
	var per_min := switches / maxf(t, 1.0) * 60.0
	log_line("tank share %.0f%% of %d samples, %d switches (%.1f per monster-minute), %d rapid" % [share * 100.0, samples, switches, per_min / maxf(pack.size(), 1.0), rapid])
	check(samples > 20 and share >= 0.7, "%s holds aggro against a %s (%.0f%% of samples)" % [tank.class_id, dps.class_id, share * 100.0])
	check(rapid == 0, "monsters don't flip-flop between targets (%d switches, none back-and-forth within 2 s)" % switches)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


## Solo: play, level up and reach floor 2, leave; then continue the saved game and check the
## hero and floor came back, and that a saved game refuses a different party size.
func _continue_scenario() -> void:
	var g := _game()
	var p := _local()
	await _wait(1.0)
	p.add_xp(Player.xp_to_next(1) + 5)
	g.start_floor(2)
	await _wait(1.0)
	var id := str(GameState.game.id)
	var lvl := p.level
	check(lvl >= 2 and int(SaveSystem.load_game(id).depth) == 2, "saved game records floor 2 and level %d" % lvl)
	var want_gender := CharacterSprite.valid_gender(gender)
	check(p.gender == want_gender and str(SaveSystem.load_game(id).members[0].get("gender", "")) == want_gender,
			"hero gender %s is used in the world and saved" % want_gender)
	NetworkManager.leave_to_menu()
	await _wait_until(func(): return get_tree().current_scene.name == "MainMenu", 6.0)
	await _wait(0.5)
	NetworkManager.host_solo()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 6.0)
	await _wait(0.5)
	# A save from before genders existed loads with the default body.
	var legacy := SaveSystem.load_game(id)
	legacy.id = "legacy_gender_test"
	for m in legacy.members:
		m.erase("gender")
	SaveSystem.save_game(legacy)
	check(GameState.select_saved_game("legacy_gender_test") and str(GameState.game_info.members[0].gender) == CharacterSprite.valid_gender(""),
			"an old save without a gender loads with the default body")
	GameState.claim_slot(0)
	await _wait(0.2)
	check(str(GameState.roster.get(1, {}).get("gender", "")) == CharacterSprite.valid_gender(""), "old save hero claimed with the default gender")
	SaveSystem.delete_game("legacy_gender_test")
	check(GameState.select_saved_game(id), "host selects the saved game in the lobby")
	GameState.choose_new_character("Intruder", "mage")
	await _wait(0.2)
	check(not GameState.roster.has(1), "a new hero can't join a saved game")
	GameState.claim_slot(0)
	await _wait(0.2)
	check(GameState.start_problem().is_empty() and int(GameState.roster[1].level) == lvl, "hero from the saved game claimed (level %d)" % lvl)
	NetworkManager.start_run()
	var ok := await _wait_until(func(): return _game() != null and _game().depth >= 1 and _local() != null, 15.0)
	await _wait(1.0)
	check(ok and _game().depth == 2 and _local().level == lvl, "continued on floor 2 with the same hero (floor %s, level %s)" % [_game().depth if _game() else -1, _local().level if _local() else -1])
	check(ok and _local().gender == want_gender and _local().sprite._layer_keys.get("body", "") == CharacterSprite.body_key(want_gender),
			"continued hero keeps gender %s and its body art" % want_gender)
	# A 1-player save can't be continued by 2 players (checked through the start rule).
	GameState.game_info.party_size = 2
	check(not GameState.start_problem().is_empty(), "a saved game requires its party size")
	GameState.game_info.party_size = 1


## LAN: two players save on floor 2, go back to the lobby, the host picks the saved game, the
## client claims its own hero over the network, and both continue on floor 2.
func _continue_lan_scenario() -> void:
	var g := _game()
	await _wait_until(func(): return _other_player() != null, 10.0)
	var client_p := _other_player()
	check(client_p.gender == "female" and _local().gender == CharacterSprite.valid_gender(gender),
			"host sees the client's female hero and its own %s hero" % _local().gender)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_genders", [_local().gender, "female"]])
	await _wait(0.5)
	# The host's HUD party frame shows the client's hero with the female body art.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var frame_ok := false
	for f in hud._party_box.get_children():
		if f.visible and f.p == client_p:
			var layers: Array = f._portrait._layers
			var tex: Variant = layers[0][0] if not layers.is_empty() else null
			var atlas_path: String = tex.atlas.resource_path if tex is AtlasTexture else ""
			frame_ok = atlas_path.begins_with(str(GameData.asset_entry(CharacterSprite.body_key("female")).path))
	check(frame_ok, "host party frame shows the client's hero with the female body")
	client_p.add_xp(Player.xp_to_next(1) + Player.xp_to_next(2) + 5)
	var client_level := client_p.level
	g.start_floor(2)
	await _wait(1.0)
	var id := str(GameState.game.id)
	NetworkManager.return_to_lobby()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 8.0)
	await _wait(0.8)
	check(GameState.select_saved_game(id), "host selects the 2-player saved game")
	await _wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["try_new_hero", null])
	await _wait(0.5)
	check(GameState.roster.size() == 0, "the client can't bring a new hero into the saved game")
	GameState.claim_slot(0 if GameState.game_info.members[0].name == char_name else 1)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["claim_mine", null])
	var ready := await _wait_until(func(): return GameState.start_problem().is_empty(), 6.0)
	var cid := multiplayer.get_peers()[0]
	check(ready and GameState.roster.has(cid) and int(GameState.roster[cid].level) == client_level, "client claimed its own hero over the network (level %d)" % client_level)
	NetworkManager.start_run()
	var ok := await _wait_until(func(): return _game() != null and _game().players_root.get_child_count() == 2 and _game().depth == 2, 15.0)
	check(ok, "both players continue on floor 2")
	if ok:
		await _wait(1.0)
		check(_other_player().level == client_level, "client hero kept its level in the continued game")
		check(_other_player().gender == "female", "client hero kept its gender in the continued game")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


## LAN: wall torches can be taken (then burn out) and broken; monsters are only visible when lit;
## deeper floors have fewer lit rooms.
func _darkness_scenario() -> void:
	var g := _game()
	var host_p := _local()
	await _wait_until(func(): return _other_player() != null, 10.0)
	var client_p := _other_player()
	await _wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	host_p.iframe_left = 999.0
	client_p.iframe_left = 999.0
	# 1. The start room is always lit.
	var start_room: Rect2i = g.layout.rooms[0].rect
	var start_torches: Array = []
	for t in g.dungeon.torches.values():
		var tc: Vector2i = g.dungeon.cell_of(t.global_position - Vector2(0, 8))  # the wall cell it hangs on
		if tc.x >= start_room.position.x and tc.x < start_room.end.x and tc.y == start_room.position.y - 1:
			start_torches.append(t)
	check(start_torches.size() >= 1, "start room has wall torches (%d)" % start_torches.size())
	# A second torch for the projectile check: the start room's, or the nearest one elsewhere.
	if start_torches.size() < 2:
		var rest: Array = g.dungeon.torches.values().filter(func(t): return not start_torches.has(t))
		rest.sort_custom(func(a, b): return a.global_position.distance_to(host_p.global_position) < b.global_position.distance_to(host_p.global_position))
		if not rest.is_empty():
			start_torches.append(rest[0])
	# 2. The client takes one.
	var torch: Node = start_torches[0]
	client_p.host_teleport(torch.interact_pos() + Vector2(0, 18))
	await _wait(0.8)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["take_torch", null])
	await _wait(0.8)
	check(torch.state == torch.State.TAKEN and client_p.torch_sync == int(GameData.bal("lighting.carried_torch_duration")), "client took the torch (%d s of light)" % client_p.torch_sync)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_torch", [torch.torch_id, torch.State.TAKEN, true]])
	await _wait(0.3)
	# 3. It burns out.
	client_p.torch_left = 1.5
	await _wait(2.2)
	check(client_p.torch_sync == 0, "the carried torch burns out")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_torch", [torch.torch_id, torch.State.TAKEN, false]])
	# 4. A projectile at another torch breaks it.
	var other: Node = start_torches[1]
	host_p.host_teleport(g.nearest_floor(other.global_position + Vector2(0, 90)))
	await _wait(0.6)
	var bolt := {"id": "test_bolt", "school": "spell", "effects": [{"type": "projectile", "sprite": "magic", "speed": 700, "range": 300, "radius": 6, "damage": {"base": 5, "coef": 0.0}}]}
	Combat.instance.run_effect(bolt.effects[0], Combat.instance.make_ctx(host_p, bolt), host_p.global_position, other.global_position)
	await _wait(0.8)
	check(other.state == other.State.BROKEN, "a projectile breaks a wall torch")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_torch", [other.torch_id, other.State.BROKEN, false]])
	# 5. Monsters in the dark are invisible until something lights them.
	var spots := _dark_pair(g)
	check(not spots.is_empty(), "found a dark spot with line of sight")
	if not spots.is_empty():
		host_p.host_teleport(spots[0])
		var m: Enemy = g.spawn_monster("ghoul", spots[1], false)
		await get_tree().physics_frame
		m.set_physics_process(false)
		m.position = spots[1]
		m.net_pos = spots[1]
		await _wait(0.6)
		check(not m.visible, "a monster in line of sight but in the dark is hidden")
		Combat.instance.fx.ring.rpc(m.global_position, 70.0, "#ff7722", "")
		await _wait(0.15)
		if not m.visible:
			var q2 := PhysicsRayQueryParameters2D.create(host_p.global_position + Vector2(0, -6), m.global_position + Vector2(0, -6), Combat.LOS_MASK)
			var hit := get_viewport().world_2d.direct_space_state.intersect_ray(q2)
			log_line("flash missed: host %s monster %s (%.0f px), ray hit %s" % [host_p.global_position, m.global_position,
				host_p.global_position.distance_to(m.global_position), hit.get("collider", "nothing")])
		check(m.visible, "a spell's flash reveals it")
		await _wait(1.0)
		check(not m.visible, "it is hidden again when the flash fades")
		host_p.host_take_torch()
		await _wait(0.5)
		check(m.visible, "a carried torch reveals it")
		host_p.torch_left = 0.0
		host_p.torch_sync = 0
		m.queue_free()
	# 6. Deeper floors are darker.
	var lit := {}
	for d in [1, 8]:
		var lay := DungeonGenerator.new().generate(12345, g.floor_def, 1.0, d)
		lit[d] = lay.torches.size()
	check(lit[8] < lit[1], "deeper floors have fewer torches (floor 1: %d, floor 8: %d)" % [lit[1], lit[8]])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


## Two floor points ~150 px apart with line of sight, neither lit by any light.
func _dark_pair(g: Node) -> Array:
	var d: Dungeon = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 7):
			var a := d.cell_center(Vector2i(x, y))
			var b := d.cell_center(Vector2i(x + 5, y))
			if d.cell_at(Vector2i(x, y)) != DungeonGenerator.CELL_FLOOR or d.cell_at(Vector2i(x + 5, y)) != DungeonGenerator.CELL_FLOOR:
				continue
			if a.distance_to(g.layout.start) < 500.0:
				continue
			var dark := true
			for l in get_tree().get_nodes_in_group(LightLayers.GROUP):
				if l == g.visibility.vision_light:
					continue
				var rad := float(l.get_meta("radius", 0.0)) + 40.0
				if l.global_position.distance_to(a) < rad or l.global_position.distance_to(b) < rad:
					dark = false
					break
			# A door on the line can be closed later (by a monster) and block the reveal checks.
			for door in d.doors:
				if Geometry2D.get_closest_point_to_segment(door.global_position, a, b).distance_to(door.global_position) < 40.0:
					dark = false
					break
			# The same physics ray Visibility uses (props block it, the grid check doesn't see them).
			var q := PhysicsRayQueryParameters2D.create(a + Vector2(0, -6), b + Vector2(0, -6), Combat.LOS_MASK)
			if dark and Combat.instance.has_los(a, b) and get_viewport().world_2d.direct_space_state.intersect_ray(q).is_empty():
				return [a, b]
	return []


func _wipe_scenario() -> void:
	var g := _game()
	await _wait(2.0)
	for p in g.players_root.get_children():
		p.iframe_left = 0.0
		Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), p, 99999.0)
	await _wait(1.0)
	check(g._wiped, "party wipe detected when nobody is standing")
	var host_p := _local()
	var game_id := str(GameState.game.get("id", "x"))
	check(SaveSystem.load_game(game_id).is_empty() and not GameState.is_continuing(), "a wipe ends the game: its save is deleted")
	var back := await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 12.0)
	check(back, "host returned to the lobby after the wipe")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_lobby", null])
	await _wait(1.0)
	check(host_p == null or not is_instance_valid(host_p), "game scene freed")
	# A second run starts cleanly: everyone has to create a new hero.
	check(GameState.roster.is_empty(), "heroes of the wiped game can't be picked again")
	GameState.choose_new_character(char_name, class_id, gender)
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["pick_again", null])
	await _wait_until(func(): return GameState.roster.size() >= (2 if NetworkManager.has_remote_peers() else 1), 10.0)
	NetworkManager.start_run()
	var again := await _wait_until(func(): return _game() != null and _game().depth == 1 and _game().players_root.get_child_count() == GameState.roster.size(), 20.0)
	check(again, "second run started after the wipe with every player spawned")
	if again:
		await _wait(1.0)
		var p2 := _local()
		check(p2 != null and p2.inv.equipment.keys() == ["main_hand"] and int(p2.inv.equipment.main_hand.rarity) == 1 and p2.is_alive(),
				"host starts the new run alive, in underwear with only the class's starting weapon")
		check(not _game()._wiped, "wipe flag reset for the new run")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(0.5)


## Solo: a new hero starts with the primary attack and one basic skill, and uses every skill on
## its bar (switches class by restarting the run is out of scope, so this runs with --class).
func _classes_scenario() -> void:
	var g := _game()
	var p := _local()
	await _wait(1.0)
	_starting_kit_checks(p)
	await _primary_env_checks(g, p)
	# Only skill use is checked here: a lucky monster pack must not wipe the solo hero.
	p.iframe_left = 9999.0
	var target := _nearest_enemy(p.global_position)
	p.host_teleport(g.nearest_floor(target.global_position + Vector2(-60, 0)))
	await _wait(0.5)
	var res_before := p.resource.value
	_fight = true
	await _wait(10.0)
	_fight = false
	for a in ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]:
		Input.action_release(a)
	var used := Combat.instance.get_meta("uses", {}) as Dictionary
	for i in 6:
		var sid: String = p.skills[i]
		if sid.is_empty():
			continue
		check(used.has("%s:%s" % [p.name, sid]), "%s used %s" % [p.class_id, sid])
	log_line("resource %s before=%.1f after=%.1f max=%.1f" % [p.resource.kind, res_before, p.resource.value, p.resource.max_value])
	if p.resource.kind == "fury":
		check(p.resource.max_value == 100.0, "fury pool is 100")
	else:
		check(p.resource.max_value > 0.0, "mana pool exists")
	await _wait(0.5)


## A melee primary (warrior, priest since #9) hits the monster in front, breaks a prop in its
## arc and bursts a closed door open.
func _primary_env_checks(g: Node, p: Player) -> void:
	var sid := str(p.class_def.primary_attack)
	var sk := GameData.skill(sid)
	if not Array(sk.effects).any(func(e): return str(e.type) == "melee"):
		return
	var c: Vector2 = g.layout.start
	for e in g.enemies_root.get_children():
		if e.global_position.distance_to(c) < 260.0:
			e.queue_free()
	p.iframe_left = 9999.0
	p.host_teleport(c)
	await _wait(0.3)
	var mon: Enemy = g.spawn_monster("ghoul", g.nearest_floor(c + Vector2(30, 0)), false)
	g.dungeon._add_prop("TestPrimaryCrate", "crate", c + Vector2(26, 16))
	await _wait(0.3)
	mon.set_physics_process(false)
	mon.behaviors = []
	var hp0 := mon.health.hp
	var crate: Node = g.dungeon.props["TestPrimaryCrate"]
	for i in 8:
		p.cooldowns.erase(sid)
		Combat.instance.try_use_skill(p, sid, c + Vector2(40, 8), {"primary": true})
		await _wait(0.25)
	check(not is_instance_valid(mon) or mon.health.hp < hp0 or not mon.is_alive(), "%s: the primary attack (%s) damages a monster" % [p.class_id, sk.name])
	check(not is_instance_valid(crate) or not crate.destructible(), "%s: the primary attack breaks a crate" % p.class_id)
	if is_instance_valid(mon):
		mon.queue_free()
	var door: Node = null
	for d in g.dungeon.doors:
		if not d.vertical and not d.floodgate:
			door = d
			break
	if door == null:
		return
	door.host_set_open(false)
	await _wait(0.2)
	var stand: Vector2 = g.nearest_floor(Vector2(door.world_rect.get_center().x, door.world_rect.end.y + 16.0))
	p.host_teleport(stand)
	await _wait(0.2)
	p.cooldowns.erase(sid)
	Combat.instance.try_use_skill(p, sid, door.world_rect.get_center(), {"primary": true})
	await _wait(0.4)
	check(door.is_open, "%s: the primary attack bursts a closed door open (%s)" % [p.class_id, door.name])
	p.host_teleport(c)
	await _wait(0.2)


## Simple start (#1): primary + the one basic skill, four empty slots, only those two unlocked;
## a hero saved before the simple start keeps the old starters and its full bar.
func _starting_kit_checks(p: Player) -> void:
	var cdef: Dictionary = GameData.classes[p.class_id]
	var on_bar := p.skills.filter(func(x): return not str(x).is_empty())
	check(p.skills.size() == 6 and str(p.skills[0]) == str(cdef.primary_attack) and on_bar.size() == 2
			and str(p.skills[1]) == str(cdef.skills[0]), "new %s starts with the primary + one skill: %s" % [p.class_id, p.skills])
	check(p.unlocked_skills().size() == 2, "only the primary and the basic skill are known (%s)" % [p.unlocked_skills()])
	check(int(p.to_character().get("kit", 0)) == GameState.KIT_VERSION, "a new hero is saved with the simple-start kit")
	# Starting weapon (#10): the class's Common weapon in the main hand, drawn on the sprite.
	var sw: Dictionary = cdef.get("starting_weapon", {})
	var wpn: Dictionary = p.inv.equipment.get("main_hand", {})
	var ok_w: bool = not sw.is_empty() and str(wpn.get("base", "")) == str(sw.base) and int(wpn.get("rarity", 0)) == 1 \
			and Array(GameData.item_bases[str(sw.base)].get("classes", [])).has(p.class_id) and p.inv.equipment.size() == 1
	check(ok_w, "new %s starts with %s (%s) equipped" % [p.class_id, sw.get("name", "?"), wpn.get("name", "nothing")])
	check(p.appearance.has("weapon") and str(p.appearance.weapon[0]) == str(GameData.item_bases[str(sw.base)].appearance),
			"the starting weapon is drawn on the sprite (%s)" % [p.appearance.get("weapon", "none")])
	var old_lo: Array = [cdef.primary_attack]
	for nd in p.talent_tree().get("nodes", []):
		if nd.get("legacy_starter", false) or (nd.get("starter", false) and str(nd.skill) != str(cdef.primary_attack)):
			old_lo.append(str(nd.skill))
	old_lo = old_lo.slice(0, 6)
	var saved := p.to_character()
	saved.erase("kit")
	saved.loadout = old_lo
	var had_ch := GameState.characters.has(p.peer_id)
	var keep_ch: Dictionary = GameState.characters.get(p.peer_id, {})
	GameState.characters[p.peer_id] = saved
	p._host_init()
	check(p.legacy_kit and p.skills == old_lo and p.talent_points == 0, "an old save keeps its full loadout for free (%s)" % [p.skills])
	check(not p.to_character().has("kit"), "an old save stays an old save")
	if had_ch:
		GameState.characters[p.peer_id] = keep_ch
	else:
		GameState.characters.erase(p.peer_id)
	p._host_init()
	check(not p.legacy_kit and p.skills == p.default_loadout(), "back to the new hero")


func _gamepad_scenario() -> void:
	var p := _local()
	await _wait(1.0)
	var start := p.global_position
	_joy_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(0.8)
	_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	check(InputSettings.using_gamepad, "gamepad input switches the active device")
	check(p.global_position.distance_to(start) > 20.0, "left stick moves the player (%.0f px)" % p.global_position.distance_to(start))
	_joy_axis(JOY_AXIS_RIGHT_X, -1.0)
	await _wait(0.2)
	check(p.facing.x < -0.5, "right stick aims")
	_joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _wait(0.4)
	_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(p.local_cd.has(0) or p.cooldowns.has(p.skills[0]), "RT fires the primary attack")
	p.resource.value = p.resource.max_value
	_joy_button(JOY_BUTTON_A, true)
	await _wait(0.3)
	_joy_button(JOY_BUTTON_A, false)
	check(p.cooldowns.has(p.skills[1]) or Combat.instance.get_meta("uses", {}).has("%s:%s" % [p.name, p.skills[1]]), "A triggers skill 1")
	var before_cd := p._dodge_cd
	_joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _wait(0.1)
	_joy_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(p._dodge_cd > before_cd, "LT dodges")
	var hud := get_tree().get_first_node_in_group("hud")
	_joy_button(JOY_BUTTON_BACK, true)
	await _wait(0.2)
	_joy_button(JOY_BUTTON_BACK, false)
	check(hud.has_overlay(), "View opens the inventory")
	var focused := get_viewport().gui_get_focus_owner()
	check(focused != null, "inventory has gamepad focus (%s)" % (focused.get_class() if focused else "none"))
	_joy_button(JOY_BUTTON_DPAD_RIGHT, true)
	await _wait(0.1)
	_joy_button(JOY_BUTTON_DPAD_RIGHT, false)
	await _wait(0.1)
	check(get_viewport().gui_get_focus_owner() != focused, "D-pad moves focus in the inventory")
	_joy_button(JOY_BUTTON_B, true)
	await _wait(0.2)
	_joy_button(JOY_BUTTON_B, false)
	await _wait(0.2)
	check(not hud.has_overlay(), "B closes the inventory")
	# Radial menu: hold LB with a potion in the backpack, pick with the stick, release.
	p.host_give_item(ItemGenerator.generate_consumable("potion_mana", 1, RandomNumberGenerator.new()))
	p.host_give_item(ItemGenerator.generate_consumable("potion_health", 1, RandomNumberGenerator.new()))
	await _wait(0.3)
	_joy_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await _wait(InputSettings.hold_threshold + 0.2)
	check(hud._radial != null, "holding LB opens the radial menu")
	_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(0.2)
	_joy_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _wait(0.4)
	check(hud._radial == null and not str(p.inv.quick.get("q", "")).is_empty(), "radial selection assigned Q = %s" % p.inv.quick.get("q", ""))
	_joy_button(JOY_BUTTON_START, true)
	await _wait(0.2)
	_joy_button(JOY_BUTTON_START, false)
	check(hud.has_overlay(), "Menu button opens the pause menu")
	_joy_button(JOY_BUTTON_B, true)
	await _wait(0.2)
	_joy_button(JOY_BUTTON_B, false)
	await _wait(0.2)
	check(not hud.has_overlay(), "B closes the pause menu")


## HUD and overlay layout across window shapes from 1:1 to 32:9. Works headless: the root
## window size drives the stretched (aspect "expand") viewport. Every pinned HUD block and every
## modal window must stay on screen inside the safe margin, HUD blocks must not overlap, modals
## must be centered and capped in width, and the camera must never show more world than the
## dungeon or the camera.max_view_* caps.
func _ui_layout_scenario() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var g := _game()
	var win := get_window()
	var original := win.size
	var margin := float(GameData.bal("ui.safe_margin"))
	hud.preview_full = true
	for s in [Vector2i(720, 720), Vector2i(960, 540), Vector2i(1280, 960), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(3840, 1080)]:
		win.size = s
		hud._last_message = ""
		hud.show_message("The boss is defeated! A portal opens...", Color.WHITE)
		await _wait(0.3)
		var vp := get_viewport().get_visible_rect()
		var tag := "%dx%d (view %dx%d)" % [s.x, s.y, vp.size.x, vp.size.y]
		var safe := vp.grow(-margin + 0.5)
		var blocks: Array = []
		for c in hud._layer.get_children():
			if c.visible and c.size.x > 1.0 and c.size.y > 1.0:
				blocks.append(c)
		var inside := true
		var overlap := false
		for i in blocks.size():
			var r: Rect2 = blocks[i].get_global_rect()
			if not safe.encloses(r):
				inside = false
				log_line("outside the safe area: %s %s" % [blocks[i].get_class(), r])
			for j in range(i + 1, blocks.size()):
				if r.intersects(blocks[j].get_global_rect()):
					overlap = true
					log_line("HUD overlap: %s %s / %s" % [blocks[i].get_class(), r, blocks[j].get_global_rect()])
		check(blocks.size() == 4 and hud._boss_panel.visible and hud._center_panel.visible and inside, "HUD blocks (%d) inside the safe area at %s" % [blocks.size(), tag])
		check(not overlap, "HUD blocks don't overlap at %s" % tag)
		var corner: Rect2 = hud._layer.get_child(0).get_global_rect()
		check(corner.position.is_equal_approx(Vector2(margin, margin)), "player frame pinned to the top-left safe corner at %s" % tag)
		var seen: Vector2 = g.camera.visible_world_size()
		var bounds: Rect2 = g.camera._bounds
		check(seen.x <= float(GameData.bal("camera.max_view_width")) + 1.0 and seen.y <= float(GameData.bal("camera.max_view_height")) + 1.0
				and seen.x <= bounds.size.x + 1.0 and seen.y <= bounds.size.y + 1.0,
				"camera shows %dx%d world px at %s (no void past the dungeon)" % [seen.x, seen.y, tag])
		for panel_script in [hud.CharacterPanel, hud.InventoryPanel, hud.TalentPanel, hud.MapPanel, hud.PauseMenu,
				hud.SkillBookPanel, hud.CodexPanel, hud.ShopPanel, hud.PactPanel, hud.LoreReader, hud.ConfirmDialog]:
			var panel: Control = panel_script.new()
			if panel_script == hud.LoreReader:
				panel.book_id = "lore_001"
				panel.title_text = "Diary of the Last Gravedigger"
			elif panel_script == hud.ConfirmDialog:
				panel.title_text = "Malphas the Soul Broker"
				panel.body_text = "Crossing the threshold costs a blood tithe."
			hud.open_overlay(panel)
			await _wait(0.4)
			var w: Control = hud._overlay.window
			var wr := w.get_global_rect()
			var cap: Vector2 = hud._overlay.max_size if hud._overlay.max_size != Vector2.ZERO \
					else Vector2(float(GameData.bal("ui.modal_max_width")), float(GameData.bal("ui.modal_max_height")))
			var centered := absf(wr.get_center().x - vp.get_center().x) <= 1.0 and absf(wr.get_center().y - vp.get_center().y) <= 1.0
			var name_ := str(panel_script.resource_path.get_file().get_basename())
			check(vp.encloses(wr) and centered and wr.size.x <= cap.x + 1.0 and wr.size.y <= cap.y + 1.0,
					"%s window %dx%d centered on screen, within its max size at %s" % [name_, wr.size.x, wr.size.y, tag])
			if panel_script != hud.MapPanel and panel_script != hud.CodexPanel or (panel_script == hud.CodexPanel and Codex.count() > 0):
				var f := get_viewport().gui_get_focus_owner()
				check(f != null and hud._overlay.is_ancestor_of(f), "%s has gamepad focus at %s" % [name_, tag])
		hud.close_overlay()
		# Options is a dialog of its own (also opened from the main menu).
		var opts: Control = preload("res://scripts/ui/settings_menu.gd").new()
		hud._root.add_child(opts)
		await _wait(0.4)
		var ow: Rect2 = opts.get_child(1).get_child(0).get_global_rect()
		check(vp.encloses(ow) and absf(ow.get_center().x - vp.get_center().x) <= 1.0,
				"options window %dx%d centered on screen at %s" % [ow.size.x, ow.size.y, tag])
		opts.queue_free()
		await _wait(0.1)
	hud.preview_full = false
	# Game menu tabs: C opens Character, the tab actions cycle through the panels, the panel's
	# own key closes it. Every panel has the same window size and shows its title.
	_action("character")
	await _wait(0.4)
	check(hud._overlay != null and hud._overlay.get_script() == hud.CharacterPanel, "C opens the character panel")
	var order: Array = []
	var sizes: Array = []
	for i in UIModal.MENU_TABS.size():
		order.append(str(hud._overlay.title_text))
		sizes.append(hud._overlay.window.size)
		_action("ui_tab_next")
		await _wait(0.35)
	var expected_order: Array = UIModal.MENU_TABS.map(func(t): return t[1])
	check(order == expected_order and hud._overlay.get_script() == hud.CharacterPanel,
			"tab next cycles %s and wraps around" % [order])
	check(sizes.all(func(z): return z == sizes[0]), "all game menu panels share one window size %s" % [sizes])
	_action("ui_tab_prev")
	await _wait(0.35)
	check(str(hud._overlay.menu_tab) == str(UIModal.MENU_TABS[-1][0]), "tab prev wraps to the last tab")
	_action("inventory")
	await _wait(0.35)
	check(hud._overlay.get_script() == hud.InventoryPanel, "a panel's key switches to it while another panel is open")
	_action("inventory")
	await _wait(0.35)
	check(hud._overlay == null, "the open panel's own key closes it")
	hud.open_overlay(hud.CharacterPanel.new())
	await _wait(0.4)
	var cp: Node = hud._overlay
	var p0 := _local()
	check(cp._skill_rows.size() == p0.skills.size() and cp._skill_rows.all(func(r): return r.get("_desc") == null and not str(r._name.text).is_empty()),
			"character panel lists all %d skills compactly (no inline descriptions)" % p0.skills.size())
	check(cp._stats_grid.get_child_count() >= 30, "character panel shows the stats (%d cells)" % cp._stats_grid.get_child_count())
	hud.close_overlay()
	await _skill_tooltip_checks(hud, win)
	# Gamepad focus graph of the inventory: every slot reachable from the first backpack slot
	# with the d-pad, and no neighbor leads out of the window.
	hud.open_overlay(hud.InventoryPanel.new())
	await _wait(0.5)
	var inv_panel: Node = hud._overlay
	var all_slots: Array = inv_panel._slots.values()
	var res := _focus_graph(inv_panel, inv_panel._slots["b:0"], all_slots)
	check(res.missing.is_empty() and res.leaks == 0, "inventory d-pad graph reaches all %d slots, stays in the window (missing %d, leaks %d)" % [all_slots.size(), res.missing.size(), res.leaks])
	hud.open_overlay(hud.TalentPanel.new())
	await _wait(0.5)
	var tp: Node = hud._overlay
	var nodes: Array = tp._buttons.values().map(func(x): return x[0])
	nodes.append(tp._reset)
	res = _focus_graph(tp, nodes[0], nodes)
	check(res.missing.is_empty() and res.leaks == 0, "talent d-pad graph reaches all %d nodes + reset, stays in the window (missing %d, leaks %d)" % [nodes.size() - 1, res.missing.size(), res.leaks])
	# The Skill Book with every skill of the class unlocked (30 entries).
	var lp := _local()
	var all_t := {}
	for nd in lp.talent_tree().get("nodes", []):
		if nd.get("type", "") == "skill" and not nd.get("starter", false):
			all_t[nd.id] = 1
	var saved_t: Dictionary = lp.talents.duplicate()
	lp.talents = all_t
	hud.open_overlay(hud.SkillBookPanel.new())
	await _wait(0.5)
	var sbp: Node = hud._overlay
	var book_n := lp.unlocked_skills().size()
	check(sbp._skill_buttons.size() == book_n and book_n >= 30, "Skill Book lists all %d unlocked skills (%d)" % [book_n, sbp._skill_buttons.size()])
	var sbw: Rect2 = sbp.window.get_global_rect()
	check(get_viewport().get_visible_rect().encloses(sbw), "the full Skill Book fits on screen")
	var sb_nodes: Array = sbp._slot_buttons + sbp._skill_buttons.values()
	res = _focus_graph(sbp, sb_nodes[0], sb_nodes)
	check(res.missing.is_empty() and res.leaks == 0, "Skill Book d-pad graph reaches the bar and every skill (missing %d, leaks %d)" % [res.missing.size(), res.leaks])
	hud.close_overlay()
	lp.talents = saved_t
	# Mouse drag and drop in the inventory, with real mouse events.
	win.size = Vector2i(1920, 1080)
	await _wait(0.3)
	var p := _local()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var helm := ItemGenerator.generate_equipment("plate_helm", 1, 3, rng)
	helm.req = 1
	p.host_give_item(helm)
	await _wait(0.3)
	hud.open_overlay(hud.InventoryPanel.new())
	await _wait(0.5)
	var panel: Node = hud._overlay
	await _mouse_drag(panel._slots["b:%d" % (p.inv.backpack.size() - 1)], panel._slots["e:head"])
	await _wait(0.4)
	check(str(p.inv.equipment.get("head", {}).get("uid", "")) == str(helm.uid), "mouse drag from the backpack onto the head slot equips the helm")
	var on_ground: int = g.items_root.get_child_count()
	await _mouse_drag(panel._slots["e:head"], null)
	await _wait(0.4)
	check(p.inv.equipment.get("head", {}).is_empty() and g.items_root.get_child_count() == on_ground + 1,
			"dragging an item out of the window drops it on the ground")
	# Gear above the character's level: marked in the backpack, refused with an explanation.
	var heavy := ItemGenerator.generate_equipment("plate_chest", 1, 2, rng)
	heavy.req = p.level + 5
	p.host_give_item(heavy)
	await _wait(0.4)
	var hi := p.inv.backpack.size() - 1
	var hslot: ItemSlot = panel._slots["b:%d" % hi]
	check(hslot.locked, "too-high-level gear is marked in the backpack")
	panel._accept_backpack(hi)
	await _wait(0.4)
	check(p.inv.equipment.get("chest", {}).is_empty() and str(panel._notice.text).contains("requires level %d" % heavy.req),
			"equipping it is refused with a message: %s" % panel._notice.text)
	panel._notice.text = ""
	await _mouse_drag(hslot, panel._slots["e:chest"])
	await _wait(0.4)
	check(p.inv.equipment.get("chest", {}).is_empty() and str(panel._notice.text).contains("requires level"),
			"dragging it onto the chest slot is refused with a message")
	var desc := ItemGenerator.describe(heavy, p.class_id, p.level)
	check(desc.any(func(l): return str(l[0]).contains("you are level %d" % p.level)), "item card says the required and current level")
	hud.close_overlay()
	win.size = original
	await _camera_lean_check()
	await _wait(0.2)


func _action(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = a
	up.pressed = false
	Input.parse_input_event(up)


## Character panel skill tooltips: hover and keyboard focus open them, they stay on screen at
## every aspect ratio, and their numbers are the host's (Combat.skill_numbers) and follow stat
## and talent changes live.
func _skill_tooltip_checks(hud: Node, win: Window) -> void:
	var p0 := _local()
	var before := win.size
	for s in [Vector2i(720, 720), Vector2i(1920, 1080), Vector2i(3840, 1080)]:
		win.size = s
		await _wait(0.2)
		hud.open_overlay(hud.CharacterPanel.new())
		await _wait(0.4)
		var cp: Node = hud._overlay
		var tip: SkillTooltip = cp._tooltip
		check(not tip.visible, "no skill tooltip before hovering at %dx%d" % [s.x, s.y])
		var all_in := true
		for row in cp._skill_rows:
			if str(p0.skills[row.slot]).is_empty():
				continue  # an empty slot has no tooltip
			await _mouse_move(row)
			await _wait(0.1)
			var vp := get_viewport().get_visible_rect()
			if not (tip.visible and tip.slot == row.slot and vp.encloses(tip.get_global_rect())
					and not tip.get_global_rect().intersects(row.get_global_rect().grow(-1.0))):
				all_in = false
				log_line("skill tooltip %d: visible %s rect %s vp %s" % [row.slot, tip.visible, tip.get_global_rect(), vp])
		check(all_in, "hovering each skill shows its tooltip on screen, beside the row, at %dx%d" % [s.x, s.y])
		hud.close_overlay()
	win.size = before
	await _wait(0.2)
	# Keyboard focus: arrow down moves focus to the next skill and opens its tooltip.
	hud.open_overlay(hud.CharacterPanel.new())
	await _wait(0.4)
	var cp2: Node = hud._overlay
	var tip2: SkillTooltip = cp2._tooltip
	_key(KEY_DOWN)
	await _wait(0.2)
	var f := get_viewport().gui_get_focus_owner()
	check(f == cp2._skill_rows[1] and tip2.visible and tip2.slot == 1, "keyboard focus on a skill opens its tooltip")
	# Values: the damage row is what Combat computes for the host, and follows stats and talents.
	var slot := -1
	for i in p0.skills.size():
		if not str(p0.skills[i]).is_empty() and _first_damage(GameData.skill(p0.skills[i])) != {}:
			slot = i
			if i > 0:
				break
	var sk := GameData.skill(p0.skills[slot])
	cp2._show_tip(cp2._skill_rows[slot])
	await _wait(0.1)
	var expect := func() -> int:
		return maxi(1, roundi(Combat.value_of(_first_damage(sk), Combat.skill_numbers(p0.stats, p0.level, sk))))
	var shown := func() -> String:
		for r in SkillInfo.rows(p0, sk):
			if int(r.kind) == SkillInfo.Kind.DAMAGE:
				return str(r.v)
		return ""
	var base_value: int = expect.call()
	check(str(shown.call()).begins_with("%d " % base_value) and _tip_text(tip2).contains("%d (crit" % base_value),
			"%s tooltip shows %d damage (host formula), cooldown %.1fs" % [sk.name, base_value, p0.stats.cooldown_for(sk)])
	check(_tip_text(tip2).contains("%.1fs" % p0.stats.cooldown_for(sk)), "tooltip shows the effective cooldown")
	var power_school := str(sk.get("power_school", sk.get("school")))
	var school_power := "power_" + ("spell" if power_school == "spell" else power_school)
	p0.stats.final[school_power] = float(p0.stats.final.get(school_power, 0.0)) + 100.0
	await _wait(0.1)
	var boosted: int = expect.call()
	check(boosted > base_value and _tip_text(tip2).contains("%d (crit" % boosted), "tooltip updates live with stats (%d -> %d)" % [base_value, boosted])
	p0.recompute_stats()
	# A learned talent that changes this skill shows up in the tooltip.
	var talent := ""
	for node in GameData.talents.get(p0.class_id, {}).get("nodes", []):
		for m in node.get("mods", []):
			var ms: Variant = m.get("skill", "")
			if (ms is Array and ms.has(sk.id)) or (ms is String and ms == sk.id):
				talent = node.id
	if talent != "":
		var saved: Dictionary = p0.talents.duplicate()
		var t := saved.duplicate()
		t[talent] = 1
		p0.talents = t
		await _wait(0.1)
		check(_tip_text(tip2).contains("1/"), "tooltip lists the learned talent %s" % talent)
		p0.talents = saved
		p0.recompute_stats()
	hud.close_overlay()
	await _wait(0.2)


func _first_damage(sk: Dictionary) -> Dictionary:
	for e in sk.get("effects", []):
		if e.has("damage"):
			return e.damage
	return {}


func _tip_text(tip: Control) -> String:
	var parts: Array = []
	var stack: Array = [tip]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and n.is_visible_in_tree():
			parts.append(n.text)
		stack.append_array(n.get_children())
	return " | ".join(parts)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


## Moves the mouse over the centre of `c` (real hover: mouse_entered fires).
func _mouse_move(c: Control) -> void:
	var xf := get_viewport().get_final_transform()
	var at: Vector2 = xf * (c.get_global_transform_with_canvas() * (c.size / 2.0))
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.relative = Vector2(6, 0)
	Input.parse_input_event(m)
	await get_tree().process_frame
	await get_tree().process_frame


## Mouse lean: when the cursor jumps to a screen corner the camera eases toward it (small steps
## per frame, never a jump) and stops within camera.aim_lookahead; back at the centre it returns.
func _camera_lean_check() -> void:
	var g := _game()
	var p := _local()
	if g == null or p == null:
		return
	await _wait(1.0)
	var cam: GameCamera = g.camera
	var reach := float(GameData.bal("camera.aim_lookahead"))
	var vp := get_viewport().get_visible_rect().size
	var xf := get_viewport().get_final_transform()
	var corner: Vector2 = xf * (vp * Vector2(0.97, 0.95))
	var m := InputEventMouseMotion.new()
	m.position = corner
	m.global_position = corner
	m.relative = Vector2(40, 40)
	Input.parse_input_event(m)
	var prev: Vector2 = cam._look
	var max_step := 0.0
	for i in 60:
		await get_tree().process_frame
		max_step = maxf(max_step, cam._look.distance_to(prev))
		prev = cam._look
	var lean := cam._look.length()
	check(max_step <= 3.0 and lean > reach * 0.5 and lean <= reach + 0.5,
			"camera eases toward the cursor (max %.1f px per frame, lean %.0f of %.0f px)" % [max_step, lean, reach])


## Walks the d-pad focus graph from `start`: which of `expected` can't be reached, and how many
## neighbors lead outside `root`.
func _focus_graph(root: Node, start: Control, expected: Array) -> Dictionary:
	var seen := {}
	var queue: Array = [start]
	var leaks := 0
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		if seen.has(c):
			continue
		seen[c] = true
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var n: Control = c.find_valid_focus_neighbor(side)
			if n == null:
				continue
			if not root.is_ancestor_of(n):
				leaks += 1
			elif not seen.has(n):
				queue.append(n)
	return {"missing": expected.filter(func(x): return not seen.has(x)), "leaks": leaks}


## Presses the left mouse button on `from`, drags and releases over `to` (null = the left edge of
## the screen, outside any window).
func _mouse_drag(from: Control, to: Control) -> void:
	var xf := get_viewport().get_final_transform()
	var a: Vector2 = xf * (from.get_global_transform_with_canvas() * (from.size / 2.0))
	var b: Vector2 = xf * (to.get_global_transform_with_canvas() * (to.size / 2.0)) if to else xf * Vector2(12, get_viewport().get_visible_rect().size.y / 2.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = a
	ev.global_position = a
	Input.parse_input_event(ev)
	await get_tree().process_frame
	for i in 9:
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, (i + 1) / 9.0)
		m.global_position = m.position
		m.relative = (b - a) / 9.0
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	Input.parse_input_event(up)
	await get_tree().process_frame


func _snap(dir: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join(name_ + ".png"))
	log_line("shot " + name_)


## Windowed screenshot tour of every screen (visual review), e.g.
##   godot --path . -- --scenario=shots --shot=/tmp/shots --class=warrior
## Worn gear covers the body: for every hero body, animation, direction and frame, the body
## pixels left visible (not hidden by a mask nor drawn over) by a full plate set must be none, and with hood + robe
## no shirt / shorts / hair pixel may show (only hands, feet and the face under the hood).
func _art_check() -> void:
	var BodyRegions := load("res://tools/body_regions.gd")
	var chars: Dictionary = GameData.assets.characters
	for g in CharacterSprite.genders():
		var cfg_path := "res://tools/hero_%s.json" % g
		if not FileAccess.file_exists(cfg_path):
			continue
		var br: RefCounted = BodyRegions.new(JSON.parse_string(FileAccess.get_file_as_string(cfg_path)))
		var body_entry := GameData.asset_entry(CharacterSprite.body_key(g))
		var sets := {"plate": ["head_helm", "chest_armor", "legs_armor", "boots_armor", "gloves_armor"], "cloth": ["head_hood", "chest_robe"]}
		for set_name in sets:
			var worst := 0
			var worst_at := ""
			var frames_checked := 0
			var missing := false
			for anim in chars.anims:
				if anim == "ghost":
					continue
				var body := _img(str(body_entry.path) + anim + ".png")
				var masks: Array = []
				for layer in sets[set_name]:
					var key := CharacterSprite.gear_key(layer, g)
					if key.is_empty():
						missing = true
						continue
					# A body pixel is covered when a hide mask drops it or a gear pixel is drawn over it.
					for path in [str(GameData.asset_entry(key).path) + "hide/" + anim + ".png", str(GameData.asset_entry(key).path) + anim + ".png"]:
						var m := _img(path)
						if m:
							masks.append(m)
				if body == null or masks.is_empty():
					continue
				var cell := int(body_entry.frame_size)
				for fy in body.get_height() / cell:
					for fx in body.get_width() / cell:
						var bad := 0
						var cls: Dictionary = br.class_map(body.get_region(Rect2i(fx * cell, fy * cell, cell, cell)))
						for q in cls:
							var p: Vector2i = q + Vector2i(fx * cell, fy * cell)
							if masks.any(func(m): return m.get_pixelv(p).a > 0.5):
								continue
							if set_name == "plate" or cls[q] in ["shirt", "shorts", "hair"]:
								bad += 1
						if bad > worst:
							worst = bad
							worst_at = "%s dir %d frame %d" % [anim, fy, fx]
						frames_checked += 1
			check(not missing and frames_checked > 0 and worst == 0,
					"%s %s set covers the body in %d frames (worst: %d body pixels showing %s)" % [g, set_name, frames_checked, worst, worst_at])
		_held_check(g, br, body_entry)


## Held items sit in the hand: for every held layer, animation, direction and frame the layer is
## drawn and some pixel of it is within 2 px of the body's detected hand.
func _held_check(g: String, br: RefCounted, body_entry: Dictionary) -> void:
	var cfg: Dictionary = br.cfg
	var cell := int(body_entry.frame_size)
	var worst := 0.0
	var worst_at := ""
	var missing := 0
	var checked := 0
	for anim in cfg.get("held_anims", []):
		var body := _img(str(body_entry.path) + anim + ".png")
		if body == null:
			continue
		var sheets := {}
		var backs := {}
		for layer in cfg.held:
			var key := CharacterSprite.gear_key(layer, g)
			sheets[layer] = _img(str(GameData.asset_entry(key).path) + anim + ".png") if not key.is_empty() else null
			backs[layer] = _img(str(GameData.asset_entry(key).path) + "back/" + anim + ".png") if not key.is_empty() else null
		for fy in body.get_height() / cell:
			for fx in body.get_width() / cell:
				var reg: Dictionary = br.segment(body.get_region(Rect2i(fx * cell, fy * cell, cell, cell)))
				var hands: Array = reg.keys().filter(func(q): return reg[q] == "hands")
				if hands.is_empty():
					hands = reg.keys().filter(func(q): return reg[q] == "arms")
				if hands.is_empty():
					hands = reg.keys().filter(func(q): return reg[q] == "torso")
				for layer in sheets:
					var sh: Image = sheets[layer]
					var pix: Array = []
					# Front and back parts together (#16: the part the body hides is in back/).
					for part in [sh, backs.get(layer)]:
						if part:
							var fr: Image = (part as Image).get_region(Rect2i(fx * cell, fy * cell, cell, cell))
							for y in cell:
								for x in cell:
									if fr.get_pixel(x, y).a >= 0.5:
										pix.append(Vector2i(x, y))
					checked += 1
					if pix.is_empty():
						missing += 1
						if missing == 1:
							worst_at = "first empty: %s %s dir %d frame %d" % [layer, anim, fy, fx]
						continue
					var best := 999.0
					# Worn on the back (quiver): it rests against the body, not in a hand.
					var targets: Array = reg.keys() if str(cfg.held[layer].get("anchor", "")) == "back" else hands
					for q in pix:
						for h in targets:
							best = minf(best, maxf(absf(q.x - h.x), absf(q.y - h.y)))
						if best <= 0.0:
							break
					# Held in the hand the body hides (#16): the item goes behind the body and rests
					# against it (torso / arm) instead of touching a visible hand.
					var bk: Image = backs.get(layer)
					if best > 2.0 and bk and bk.get_region(Rect2i(fx * cell, fy * cell, cell, cell)).get_used_rect().size != Vector2i.ZERO:
						var body_px: Array = reg.keys().filter(func(q2): return reg[q2] in ["torso", "arms"])
						var near := 999.0
						for q in pix:
							for h in body_px:
								near = minf(near, maxf(absf(q.x - h.x), absf(q.y - h.y)))
							if near <= 1.0:
								break
						if near <= 1.0:
							best = near
					if best > worst and missing == 0:
						worst = best
						worst_at = "%s %s dir %d frame %d" % [layer, anim, fy, fx]
	check(checked > 0 and missing == 0 and worst <= 2.0,
			"%s held items drawn in all %d layer frames and in the hand (%d empty, worst %d px, %s)" % [g, checked, missing, worst, worst_at])


func _img(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var img := (load(path) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Character art review: the lobby preview, then the hero in the start room next to a line-up
## of CharacterSprites (bare / full kit, idle / walk / attack, 8 directions) and zoomed crops.
## Lobby preview of every class x gender in all 8 directions, cropped into one grid image
## (#15 review): rows = class x gender (gear on), columns = directions E..NE.
##   godot --path . -- --scenario=preview_grid --shot=/tmp/grid.png
func _preview_grid_flow() -> void:
	NetworkManager.host_solo()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 10.0)
	await _wait(0.8)
	var lobby: Node = get_tree().current_scene
	var pv: HeroPreview = lobby._preview
	var grid: Image = null
	var row := 0
	var classes := ["warrior", "ranger", "mage", "priest"]
	for cid in classes:
		for g in CharacterSprite.genders():
			lobby._select_gender(g)
			lobby._select_class(cid)
			await _wait(0.2)
			for d in 8:
				pv.dir_index = d
				pv.rotate_by(0)
				await get_tree().process_frame
				await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				var sc := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
				var r := Rect2i(Vector2i(pv.get_global_rect().position * sc), Vector2i(pv.get_global_rect().size * sc))
				var crop := img.get_region(r)
				if grid == null:
					grid = Image.create(crop.get_width() * 8, crop.get_height() * classes.size() * CharacterSprite.genders().size(), false, crop.get_format())
				grid.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(d * crop.get_width(), row * crop.get_height()))
			row += 1
	var out := shot if not shot.is_empty() else OS.get_user_data_dir().path_join("preview_grid.png")
	grid.save_png(out)
	log_line("preview grid " + out)
	_finish("preview grid")


func _hero_shots_flow() -> void:
	var dir := shot if not shot.is_empty() else OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	NetworkManager.host_solo()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 10.0)
	await _wait(0.8)
	var lobby: Node = get_tree().current_scene
	lobby._select_gender(gender)
	lobby._select_class(class_id)
	await _wait(0.5)
	await _snap(dir, "h01_lobby_%s_%s" % [gender, class_id])
	lobby._preview.rotate_by(1)
	await _wait(0.3)
	await _snap(dir, "h02_lobby_turned")
	GameState.select_character(char_name, class_id, gender)
	await _wait(0.3)
	NetworkManager.start_run()
	await _wait_until(func(): return _game() != null and _local() != null, 15.0)
	await _wait(1.5)
	var g := _game()
	var p := _local()
	p.iframe_left = 9999.0
	for e in g.enemies_root.get_children():
		e.queue_free()
	var look: Dictionary = preload("res://scripts/ui/lobby.gd").class_look(class_id)
	var rows := [["idle", {}], ["walk", {}], ["idle", look], ["walk", look], ["attack", look], ["cast", look], ["dash", look], ["hit", look]]
	var lineup := Node2D.new()
	g.add_child(lineup)
	lineup.global_position = p.global_position + Vector2(-150, -150)
	lineup.y_sort_enabled = true
	for r in rows.size():
		for d in 8:
			var cs := CharacterSprite.new()
			lineup.add_child(cs)
			cs.position = Vector2(d * 38, r * 56)
			cs.set_layer("body", CharacterSprite.body_key(gender))
			for layer in rows[r][1]:
				var a: Array = rows[r][1][layer]
				cs.set_look_layer(layer, a, gender)
			cs.play(rows[r][0], Vector2.RIGHT.rotated(d * PI / 4.0), true)
	g.camera.global_position = lineup.global_position + Vector2(140, 200)
	await _wait(0.6)
	await _snap(dir, "h03_lineup")
	var img := get_viewport().get_texture().get_image()
	var vp := get_viewport().get_visible_rect()
	var xf := get_viewport().get_canvas_transform()
	var tl: Vector2 = xf * (lineup.global_position + Vector2(-24, -56))
	var br: Vector2 = xf * (lineup.global_position + Vector2(8 * 38, rows.size() * 56))
	var sc := Vector2(img.get_size()) / vp.size
	var crop := img.get_region(Rect2i(Vector2i(tl * sc), Vector2i((br - tl) * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(dir.path_join("h04_lineup_zoom.png"))
	# Scale line-up in the hero's light: the hero next to every monster and the boss.
	lineup.queue_free()
	lineup = Node2D.new()
	g.add_child(lineup)
	lineup.global_position = p.global_position + Vector2(-110, 30)
	var scale_row: Array = [["hero", look], ["monsters.ghoul", {}], ["monsters.skeleton_archer", {}], ["monsters.cultist", {}], ["monsters.bone_lord", {}]]
	for i in scale_row.size():
		var cs := CharacterSprite.new()
		lineup.add_child(cs)
		cs.position = Vector2(i * 44 + (24 if i == 4 else 0), 0)
		if scale_row[i][0] == "hero":
			cs.set_layer("body", CharacterSprite.body_key(gender))
			for layer in scale_row[i][1]:
				var a2: Array = scale_row[i][1][layer]
				cs.set_look_layer(layer, a2, gender)
		else:
			cs.set_layer("body", str(scale_row[i][0]))
		cs.play("idle", Vector2.DOWN, true)
	g.camera.global_position = p.global_position
	await _wait(0.6)
	img = get_viewport().get_texture().get_image()
	xf = get_viewport().get_canvas_transform()
	tl = xf * (lineup.global_position + Vector2(-30, -90))
	br = xf * (lineup.global_position + Vector2(4 * 44 + 70, 12))
	sc = Vector2(img.get_size()) / vp.size
	crop = img.get_region(Rect2i(Vector2i(tl * sc), Vector2i((br - tl) * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(dir.path_join("h04b_scale_zoom.png"))
	# Every held item on this body in 8 directions (attack frame), lit: one row per item.
	lineup.queue_free()
	lineup = Node2D.new()
	g.add_child(lineup)
	lineup.global_position = p.global_position + Vector2(-300, -230)
	var held: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/hero_%s.json" % CharacterSprite.valid_gender(gender))).held.keys()
	var light := Combat.instance.fx._light(Color(1, 0.95, 0.85), 2.2, 9.0)
	light.position = Vector2(300, 230)
	lineup.add_child(light)
	for r in held.size():
		var layer: String = held[r]
		var slot := "offhand" if layer.begins_with("offhand") else "weapon"
		for d in 8:
			var cs := CharacterSprite.new()
			lineup.add_child(cs)
			cs.position = Vector2((r % 2) * 320 + d * 38, (r / 2) * 58 + 50)
			cs.set_layer("body", CharacterSprite.body_key(gender))
			cs.set_layer(slot, CharacterSprite.gear_key(layer, gender))
			cs.play("attack", Vector2.RIGHT.rotated(d * PI / 4.0), true)
	g.camera.global_position = lineup.global_position + Vector2(300, 230)
	await _wait(0.25)
	img = get_viewport().get_texture().get_image()
	xf = get_viewport().get_canvas_transform()
	tl = xf * (lineup.global_position + Vector2(-24, -10))
	br = xf * (lineup.global_position + Vector2(640, 7 * 58 + 60))
	sc = Vector2(img.get_size()) / vp.size
	crop = img.get_region(Rect2i(Vector2i(tl * sc), Vector2i((br - tl) * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.save_png(dir.path_join("h04c_held_items.png"))
	# Downed (naked and in class gear) and ghost in 8 directions, lit.
	lineup.queue_free()
	lineup = Node2D.new()
	g.add_child(lineup)
	lineup.global_position = p.global_position + Vector2(-150, -90)
	light = Combat.instance.fx._light(Color(1, 0.95, 0.85), 2.2, 9.0)
	light.position = Vector2(150, 90)
	lineup.add_child(light)
	var end_rows := [["downed", {}], ["downed", look], ["ghost", {}]]
	for r in end_rows.size():
		for d in 8:
			var cs := CharacterSprite.new()
			lineup.add_child(cs)
			cs.position = Vector2(d * 48, r * 56 + 50)
			cs.set_layer("body", CharacterSprite.body_key(gender))
			for layer in end_rows[r][1]:
				var a3: Array = end_rows[r][1][layer]
				cs.set_look_layer(layer, a3, gender)
			cs.play(end_rows[r][0], Vector2.RIGHT.rotated(d * PI / 4.0), true)
			if end_rows[r][0] == "ghost":
				cs.modulate.a = 0.45  # as Player draws its own ghost
	g.camera.global_position = lineup.global_position + Vector2(150, 90)
	await _wait(0.6)
	img = get_viewport().get_texture().get_image()
	xf = get_viewport().get_canvas_transform()
	tl = xf * (lineup.global_position + Vector2(-26, -10))
	br = xf * (lineup.global_position + Vector2(8 * 48, 3 * 56 + 60))
	sc = Vector2(img.get_size()) / vp.size
	crop = img.get_region(Rect2i(Vector2i(tl * sc), Vector2i((br - tl) * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(dir.path_join("h04d_downed_ghost.png"))
	# The hero in the world, fully equipped, walking and attacking.
	g.camera.global_position = p.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for b in GameData.classes[class_id].get("preview_gear", []):
		var it := ItemGenerator.generate_equipment(b, 1, rng.randi_range(2, 5), rng)
		it.req = 1
		p.host_give_item(it)
		p.request_equip.rpc_id(1, p.inv.backpack.size() - 1)
		await _wait(0.1)
	lineup.queue_free()
	await _wait(0.8)
	await _snap(dir, "h05_hero_equipped")
	p.auto_aim = p.global_position + Vector2(-100, 30)
	p.play_action.rpc("attack", Vector2(-1, 0.3))
	await _wait(0.12)
	await _snap(dir, "h06_hero_attack")
	var hud := get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.CharacterPanel.new())
	await _wait(0.5)
	var cp: Node = hud._overlay
	cp._show_tip(cp._skill_rows[1])
	await _wait(0.3)
	await _snap(dir, "h07_character_tooltip")
	hud.open_overlay(hud.InventoryPanel.new())
	await _wait(0.5)
	await _snap(dir, "h08_inventory")
	hud.close_overlay()
	_finish("hero shots")


## Monsters at the new scale in the game: health bars, names and feet next to the hero.
func _monster_shots_flow() -> void:
	var dir := shot if not shot.is_empty() else OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	NetworkManager.host_solo()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 10.0)
	await _wait(0.5)
	GameState.select_character(char_name, class_id, gender)
	await _wait(0.3)
	NetworkManager.start_run()
	await _wait_until(func(): return _game() != null and _local() != null, 15.0)
	await _wait(1.5)
	var g := _game()
	var p := _local()
	p.iframe_left = 9999.0
	for e in g.enemies_root.get_children():
		e.queue_free()
	await _wait(0.2)
	var spawned: Array = []
	var spots := [[ "ghoul", Vector2(-70, -20), false], ["skeleton_archer", Vector2(-25, -45), false], ["cultist", Vector2(25, -45), false], ["bone_lord", Vector2(80, -10), true]]
	for sp in spots:
		var e: Node = g.spawn_monster(str(sp[0]), g.nearest_floor(p.global_position + sp[1]), bool(sp[2]))
		if e:
			spawned.append(e)
	await _wait(0.6)
	for e in spawned:
		if is_instance_valid(e):
			e.health.hp = e.health.max_hp * 0.6
	# A ground zone (the priest's Consecration) under the pack: it must be drawn below them.
	Combat.instance.run_effect({"type": "zone", "at": "self", "radius": 100, "duration": 6.0, "tick": 1.0,
		"targets": "enemies", "color": "#ffd24d", "damage": {"base": 0, "coef": 0.0}},
		Combat.instance.make_ctx(p, GameData.skill("priest_consecration")), p.global_position + Vector2(0, -30), p.global_position)
	await _wait(0.4)
	await _snap(dir, "m01_monsters")
	var img := get_viewport().get_texture().get_image()
	var vp := get_viewport().get_visible_rect()
	var xf := get_viewport().get_canvas_transform()
	var tl: Vector2 = xf * (p.global_position + Vector2(-140, -150))
	var br: Vector2 = xf * (p.global_position + Vector2(160, 40))
	var sc := Vector2(img.get_size()) / vp.size
	var crop := img.get_region(Rect2i(Vector2i(tl * sc), Vector2i((br - tl) * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.save_png(dir.path_join("m02_monsters_zoom.png"))
	_finish("monster shots")


func _shots_flow() -> void:
	var dir := shot if not shot.is_empty() else OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.2)
	await _snap(dir, "01_main_menu")
	get_tree().current_scene.open_settings()
	await _wait(0.5)
	get_tree().current_scene._overlay._tabs.current_tab = 2
	await _wait(0.3)
	await _snap(dir, "02_options_controls")
	get_tree().current_scene._overlay._close()
	await _wait(0.4)
	NetworkManager.host_solo()
	await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 10.0)
	await _wait(0.8)
	GameState.select_character(char_name, class_id, gender)
	await _wait(0.3)
	await _snap(dir, "03_lobby")
	NetworkManager.start_run()
	await _wait_until(func(): return _game() != null and _local() != null, 15.0)
	await _wait(1.5)
	var g := _game()
	var p := _local()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kit: Array = {"warrior": ["sword", "shield"], "ranger": ["bow"], "mage": ["battle_staff", "trinket"], "priest": ["holy_wand", "shield"]}[class_id]
	for b in kit + ["plate_helm", "plate_chest", "greaves", "boots", "gloves", "ring", "necklace"]:
		var it := ItemGenerator.generate_equipment(b, 1, rng.randi_range(1, 5), rng)
		it.req = 1
		p.host_give_item(it)
		p.request_equip.rpc_id(1, p.inv.backpack.size() - 1)
		await _wait(0.1)
	for b in ["greatsword", "crossbow", "arcane_wand", "robe"]:
		p.host_give_item(ItemGenerator.generate_equipment(b, 2, rng.randi_range(2, 5), rng))
	# Look variety (#20): every rarity of a few armour bases and one legendary per class.
	for i in 5:
		p.host_give_item(ItemGenerator.generate_equipment(["greaves", "boots", "gloves", "plate_helm", "hood"][i], 2, i + 1, rng))
	for lid in ["crown_blood_chieftain", "wyvernscale_jerkin", "robe_seven_cataclysms", "cuirass_radiant_dawn"]:
		p.host_give_item(ItemGenerator.make_legendary(lid, 2, rng))
	var heavy := ItemGenerator.generate_equipment("greataxe", 9, 4, rng)
	heavy.req = 9
	p.host_give_item(heavy)
	var heavy2 := ItemGenerator.generate_equipment("plate_helm", 9, 3, rng)
	heavy2.req = 9
	g.loot.drop_item(heavy2, p.global_position + Vector2(-50, 10))
	p.host_give_item(ItemGenerator.generate_consumable("potion_health", 3, rng))
	p.host_give_item(ItemGenerator.generate_consumable("potion_mana", 2, rng))
	for b in ["sword", "bow", "necklace"]:
		g.loot.drop_item(ItemGenerator.generate_equipment(b, 1, rng.randi_range(2, 5), rng), p.global_position + Vector2(rng.randf_range(-60, 60), rng.randf_range(30, 70)))
	p.level = 4
	p.talent_points = 3
	await _wait(1.0)
	await _snap(dir, "04_game_start_room")
	var hud := get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.InventoryPanel.new())
	await _wait(0.5)
	await _snap(dir, "05_inventory")
	hud.open_overlay(hud.TalentPanel.new())
	await _wait(0.5)
	await _snap(dir, "06_talents")
	hud.open_overlay(hud.CharacterPanel.new())
	await _wait(0.5)
	await _snap(dir, "06b_character")
	hud.close_overlay()
	hud.open_radial("q")
	await _wait(0.3)
	await _snap(dir, "07_radial")
	hud.close_radial()
	# Gamepad look: glyphs switch to pad buttons, the focus bracket follows the focused slot.
	_joy_button(JOY_BUTTON_DPAD_DOWN, true)
	_joy_button(JOY_BUTTON_DPAD_DOWN, false)
	hud.open_overlay(hud.InventoryPanel.new())
	await _wait(0.6)
	await _snap(dir, "07b_inventory_gamepad")
	hud.open_overlay(hud.PauseMenu.new())
	await _wait(0.6)
	await _snap(dir, "07c_pause_gamepad")
	hud.close_overlay()
	await _snap(dir, "07d_hud_gamepad")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(10, 0)
	Input.parse_input_event(mouse)
	# Walk into the nearest monster room and fight a bit.
	var target := _nearest_enemy(p.global_position)
	if target:
		p.host_teleport(g.nearest_floor(target.global_position + Vector2(-90, 20)))
		p.iframe_left = 30.0
		await _wait(1.0)
		_fight = true
		await _wait(2.5)
		await _snap(dir, "08_combat")
		_fight = false
		for a in ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]:
			Input.action_release(a)
	hud.open_overlay(hud.MapPanel.new())
	await _wait(0.4)
	await _snap(dir, "09_map")
	hud.close_overlay()
	var boss := _nearest_enemy(p.global_position, true)
	if boss:
		p.host_teleport(g.nearest_floor(boss.global_position + Vector2(0, 110)))
		p.iframe_left = 30.0
		boss.add_threat(p, 10.0)
		await _wait(3.0)
		p.iframe_left = 30.0
		await _snap(dir, "10_boss")
	# Occluders seen from the south (they must not vanish in their own shadow).
	for e in g.enemies_root.get_children():
		e.queue_free()
	for id in g.dungeon.props:
		var pr: Node = g.dungeon.props[id]
		if pr.type == "table":
			p.host_teleport(g.nearest_floor(pr.global_position + Vector2(0, 70)))
			break
	await _wait(1.2)
	await _snap(dir, "11_table_from_south")
	if not g.dungeon.doors.is_empty():
		var door: Node = g.dungeon.doors[0]
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 80)))
		await _wait(1.2)
		await _snap(dir, "12_door_from_south")
		# Pressed against the door from the south: the player must stay lit and visible.
		var door_bottom: float = door.world_rect.end.y
		p.host_teleport(Vector2(door.world_rect.get_center().x, door_bottom + 9.0))
		await _wait(1.0)
		await _snap(dir, "13_against_door")
	# Darkness: a corridor away from torches, first without, then with a carried torch.
	var dark := _dark_pair(g)
	if not dark.is_empty():
		p.host_teleport(dark[0])
		p.torch_left = 0.0
		p.torch_sync = 0
		await _wait(1.2)
		await _snap(dir, "14_dark_no_torch")
		p.host_take_torch()
		await _wait(1.0)
		await _snap(dir, "15_dark_with_torch")
		var fps_samples: Array = []
		for i in 5:
			await _wait(1.0)
			fps_samples.append(Engine.get_frames_per_second())
		log_line("boss room fps %s (enemies %d)" % [fps_samples, g.enemies_root.get_child_count()])
	_finish("shots taken")


## Main menu -> Solo -> lobby -> confirm -> start, using only gamepad events.
func _gamepad_menu_flow() -> void:
	await _wait(1.0)
	var focus := get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "Play", "main menu focuses Play for the gamepad")
	# Main menu cleanup (#13): no tagline, no Steam status, "v0.1", no Codex button.
	var mm: Node = get_tree().current_scene
	var texts: Array = []
	var stack: Array = [mm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label or n is Button:
			texts.append(str(n.text))
		stack.append_array(n.get_children())
	var main_btns: Array = mm._pages["main"].get_children().map(func(b): return str(b.text))
	check(main_btns == ["Play", "Options", "Quit"], "main menu buttons: %s" % [main_btns])
	check(not texts.any(func(x): return x.contains("dungeon crawler") or x.contains("Steam:") or x.contains("MVP")) and str(mm._version.text) == "v0.1",
			"main menu shows no tagline or Steam status, the version reads %s" % mm._version.text)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() is Button and get_viewport().gui_get_focus_owner().text == "Quit", "the D-pad walks Play -> Options -> Quit")
	await _press(JOY_BUTTON_DPAD_UP)
	await _press(JOY_BUTTON_DPAD_UP)
	# Options -> Controls tab (RB) -> rebind a gamepad slot by pressing a pad button.
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	await _wait(0.4)
	var menu: Node = get_tree().current_scene._overlay
	check(menu != null, "Options opened with the gamepad")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(menu._tabs.current_tab == 2, "RB switches to the Controls tab")
	var slot_btn: Button = menu._bind_buttons["skill_1|pad|1"]
	slot_btn.grab_focus()
	await _press(JOY_BUTTON_A)
	await _wait(0.2)
	await _press(JOY_BUTTON_Y)
	check(Array(InputSettings.bindings["skill_1"]["pad"]).has("button:y") and not Array(InputSettings.bindings["skill_4"]["pad"]).has("button:y"), "pad rebinding through the menu (conflict moved Y from skill 4)")
	InputSettings.reset_to_defaults()
	await _press(JOY_BUTTON_B)
	await _wait(0.3)
	check(get_tree().current_scene._overlay == null, "B closes Options")
	await _wait(0.2)
	get_tree().current_scene._pages["main"].get_child(0).grab_focus()
	await _press(JOY_BUTTON_A)
	await _wait(0.5)
	focus = get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "Solo", "Play page focuses Solo")
	await _press(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner().text == "Host LAN game", "D-pad moves menu focus")
	await _press(JOY_BUTTON_DPAD_UP)
	await _press(JOY_BUTTON_A)
	var in_lobby := await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 10.0)
	check(in_lobby, "gamepad reached the lobby")
	await _wait(0.8)
	var lobby: Node = get_tree().current_scene
	var vis := get_viewport().get_visible_rect()
	check(vis.encloses(lobby._preview.get_global_rect()) and vis.encloses(lobby._start.get_global_rect()),
			"lobby preview and Start button fit on a %dx%d view" % [vis.size.x, vis.size.y])
	var other_g: String = "female" if lobby._selected_gender != "female" else "male"
	var picked := false
	for i in 8:
		if lobby._gender_buttons.values().has(get_viewport().gui_get_focus_owner()):
			break
		await _press(JOY_BUTTON_DPAD_DOWN)
	for i in 3:
		if get_viewport().gui_get_focus_owner() == lobby._gender_buttons.get(other_g):
			await _press(JOY_BUTTON_A)
			picked = true
			break
		await _press(JOY_BUTTON_DPAD_RIGHT if other_g == "female" else JOY_BUTTON_DPAD_LEFT)
	check(picked and lobby._selected_gender == other_g and lobby._preview.gender == other_g,
			"gamepad picks the %s body; the preview follows" % other_g)
	var d0: int = lobby._preview.dir_index
	lobby._preview.rotate_by(1)
	check(lobby._preview.dir_index == wrapi(d0 + 1, 0, 8) and lobby._preview.sprite.dir_index == lobby._preview.dir_index, "lobby preview turns")
	# The arrows (#14): from facing the camera, "<" turns the hero to look left, ">" to look right.
	for side in [-1, 1]:
		lobby._preview.dir_index = 2
		lobby._preview.rotate_by(0)
		lobby._turn_buttons[side].pressed.emit()
		var f: Vector2 = lobby._preview.facing()
		check(signf(f.x) == float(side) and lobby._preview.sprite.dir_index == lobby._preview.dir_index,
				"the %s arrow turns the preview %s (facing %s)" % [lobby._turn_buttons[side].text, "left" if side < 0 else "right", f])
	lobby._preview.dir_index = d0
	lobby._preview.rotate_by(1)
	var reached := false
	for i in 10:
		focus = get_viewport().gui_get_focus_owner()
		if focus == lobby._confirm:
			reached = true
			await _wait(0.2)
			check(get_viewport().get_visible_rect().encloses(focus.get_global_rect()), "the focused confirm button is scrolled into view")
			break
		await _press(JOY_BUTTON_DPAD_DOWN)
	check(reached, "D-pad reaches the confirm button in the lobby")
	await _press(JOY_BUTTON_A)
	await _wait(0.5)
	check(GameState.roster.has(1) and str(GameState.roster[1].get("gender", "")) == other_g, "character confirmed with A (%s)" % other_g)
	var found := false
	for i in 14:
		focus = get_viewport().gui_get_focus_owner()
		if focus == lobby._start:
			found = true
			break
		await _press(JOY_BUTTON_DPAD_DOWN)
	check(found, "D-pad reaches the Start button")
	await _press(JOY_BUTTON_A)
	var in_game := await _wait_until(func(): return _game() != null and _local() != null, 15.0)
	check(in_game, "run started from the lobby with the gamepad")
	check(in_game and _local().gender == other_g, "the hero in the world has the chosen body")
	if in_game:
		await _wait(0.5)
		var hud := get_tree().get_first_node_in_group("hud")
		await _press(JOY_BUTTON_DPAD_LEFT)
		check(hud._overlay != null and hud._overlay.get_script() == hud.TalentPanel, "D-pad Left opens talents")
		for i in 3:
			await _press(JOY_BUTTON_DPAD_LEFT)
		check(hud._overlay != null, "D-pad navigation inside talents doesn't close the panel")
		await _press(JOY_BUTTON_B)
		check(hud._overlay == null, "B closes talents")
	_finish("gamepad menu flow")


func _press(button: int) -> void:
	_joy_button(button, true)
	await _wait(0.08)
	_joy_button(button, false)
	await _wait(0.25)


func _joy_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _joy_button(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


# =========================================================================================
# Rebinding persistence + Steam
# =========================================================================================


func _rebind_test() -> void:
	var removed := InputSettings.bind("skill_1", "kbm", 0, "key:J")
	InputSettings.bind("interact", "pad", 0, "button:y")
	check(removed.is_empty(), "binding J to skill 1 had no conflicts")
	var conflict := InputSettings.bind("skill_2", "kbm", 0, "key:J")
	check(conflict.size() == 1, "binding J again resolves the conflict (%s)" % ", ".join(conflict))
	InputSettings.bind("skill_1", "kbm", 0, "key:J")
	check(_has_key("skill_1", KEY_J), "InputMap updated for skill 1")
	_finish("rebind saved")


func _rebind_check() -> void:
	check(_has_key("skill_1", KEY_J), "rebinding of skill 1 survived a restart")
	var pad_ok := false
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_Y:
			pad_ok = true
	check(pad_ok, "gamepad rebinding of interact survived a restart")
	InputSettings.reset_to_defaults()
	check(_has_key("skill_1", KEY_1) and not _has_key("skill_1", KEY_J), "reset to defaults restores skill 1 = 1")
	_finish("rebind checked")


func _has_key(action: String, key: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == key:
			return true
	return false


func _steam_host_test() -> void:
	check(NetworkManager.steam_ready, "Steam initialized (%s)" % NetworkManager.steam_status)
	if not NetworkManager.steam_ready:
		_finish("no steam")
		return
	NetworkManager.host_steam()
	var ok := await _wait_until(func(): return NetworkManager.lobby_id != 0, 15.0)
	check(ok, "Steam lobby created (id %d)" % NetworkManager.lobby_id)
	# Lambdas capture by value, so results go through a dictionary.
	var box := {"lobbies": []}
	NetworkManager.lobby_list_received.connect(func(l): box.lobbies = l)
	var found := false
	for attempt in 6:
		NetworkManager.request_steam_lobbies()
		await _wait(2.5)
		for l in box.lobbies:
			if l.id == NetworkManager.lobby_id:
				found = true
		log_line("lobby list attempt %d: %d lobbies" % [attempt, box.lobbies.size()])
		if found:
			break
	check(found, "own lobby is listed with the game tag (%d lobbies)" % box.lobbies.size())
	check(multiplayer.multiplayer_peer.get_class() == "SteamMultiplayerPeer", "SteamMultiplayerPeer active as host")
	_finish("steam done")
