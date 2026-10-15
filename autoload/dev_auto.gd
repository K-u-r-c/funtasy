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
var char_name := ""
var wanted_players := 2
var quit_after := 0.0
var shot := ""
var shot_at := 0.0
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
	if mode.is_empty() and scenario.is_empty():
		set_process(false)
		return
	if char_name.is_empty():
		char_name = "Test%s" % mode.capitalize()
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(_finish.bind("timeout"))
	if not shot.is_empty() and scenario != "shots":
		get_tree().create_timer(shot_at).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(shot)
			log_line("screenshot saved to %s" % shot))
	_run.call_deferred()


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
		"rebind":
			_rebind_test()
			return
		"rebind_check":
			_rebind_check()
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
	GameState.select_character(char_name, class_id)
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
			"idle":
				await _wait(9999.0)
			"boss":
				await _boss_scenario()
			"tank":
				await _tank_scenario()
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
		"check_saved":
			var saved := SaveSystem.load_character(GameState.local_character.name, GameState.local_character.class_id)
			check(not saved.is_empty() and int(saved.get("level", 0)) == int(arg), "client save file has level %d (got %s)" % [int(arg), saved.get("level", "none")])
		"check_life":
			check(p.life_state == int(arg), "client sees its own life state %d (got %d)" % [int(arg), p.life_state])
		"check_lobby":
			check(get_tree().current_scene.name == "Lobby", "client returned to the lobby after the wipe")
		"done":
			_finish.call_deferred("host finished")
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
	var xp_before := client_p.xp + client_p.level * 100000
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", true])
	await _wait(9.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fight", false])
	var used := Combat.instance.get_meta("uses", {}) as Dictionary
	var client_uses := 0
	for k in used:
		if str(k).begins_with(client_p.name + ":"):
			client_uses += 1
	check(client_uses >= 4, "client used %d different skills through host validation" % client_uses)
	check(client_p.cooldowns.size() > 0 or client_uses > 0, "host tracks client cooldowns")
	check(not is_instance_valid(target) or target.health.hp < target.health.max_hp, "client damaged the monster (host authority)")
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
	_reset_player(host_p)
	await _wait(0.3)

	# --- 2c. Hazards + friendly fire -----------------------------------------------------------
	await _hazard_checks(g, host_p, client_p)

	_reset_player(host_p)
	host_p.iframe_left = 30.0
	# --- 3. Doors -----------------------------------------------------------------------------
	var door: Node = g.dungeon.doors[0]
	host_p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 40)))
	await _wait(0.4)
	var was_open: bool = door.is_open
	g.host_interact(host_p, door)
	await _wait(0.4)
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
	client_p.health.hp = client_p.health.max_hp * 0.3
	NetworkManager.to_clients("DevAuto", "client_cmd", ["use_q", null])
	await _wait(0.6)
	check(client_p.inv.count_of("potion_health") == potions_before + 1 and client_p.health.fraction() > 0.5, "Q potion consumed and healed (left %d, hp %.0f%%)" % [client_p.inv.count_of("potion_health"), client_p.health.fraction() * 100.0])

	# --- 6. Downed -> revive ------------------------------------------------------------------
	# The host is only a helper from here on; keep it standing so a stray hit can't turn the
	# client's (intentional) death into a party wipe.
	_reset_player(host_p)
	host_p.iframe_left = 60.0
	client_p.host_teleport(g.nearest_floor(host_p.global_position + Vector2(20, 0)))
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
	boss.health.hp = boss.health.max_hp * 0.45
	await _wait(12.0)
	check(boss.phase == 1 and boss.status.has("enrage"), "boss entered phase 2 (enraged)")
	var boss_uses: Array = []
	for k in (Combat.instance.get_meta("uses", {}) as Dictionary):
		if str(k).begins_with(boss.name + ":"):
			boss_uses.append(str(k).get_slice(":", 1))
	for sid in ["bone_lord_cleave", "bone_lord_nova", "bone_lord_summon", "bone_lord_slam"]:
		check(boss_uses.has(sid), "boss used %s" % sid)
	host_p.iframe_left = 0.0
	_reset_player(host_p)
	var ctx := Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0]))
	ctx.crit_chance = 0.0
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
	host_p.host_teleport(g.portal.global_position)
	await _wait(3.0)
	check(g.depth == 2, "party descended to floor 2")
	await _wait(1.0)
	check(client_p.life_state == Player.Life.ALIVE, "ghost revived on the next floor")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_depth", 2])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_life", Player.Life.ALIVE])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["check_saved", client_p.level])
	check(g.enemies_root.get_child_count() > 3, "floor 2 populated with monsters")
	await _wait(1.0)
	await _floor2_props_check(g, host_p)
	await _wait(1.0)
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
		check(ghoul.health.hp < hp_g, "player-triggered barrel explosion hurts monsters (FF %s)" % ff)
		if ff:
			check(client_p.health.hp < hp_c, "friendly fire ON: explosion hurts an ally")
		else:
			check(client_p.health.hp == hp_c, "friendly fire OFF: explosion spares allies")
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
	await _wait(0.5)
	watcher.set_physics_process(false)
	await _wait(0.2)
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
		if chest == null and pr.interactable():
			chest = pr
	if target:
		var tid: String = target.prop_id
		target.take_damage(9999.0, Combat.instance.make_ctx(host_p, GameData.skill(host_p.skills[0])))
		await _wait(0.5)
		check(not g.dungeon.props.has(tid), "floor 2 prop %s destroyed on the host" % tid)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_prop_gone", tid])
	if chest:
		host_p.host_teleport(chest.global_position + Vector2(0, 20))
		await _wait(0.6)
		var before: int = g.items_root.get_child_count()
		g.host_interact(host_p, chest)
		await _wait(0.4)
		var after_first: int = g.items_root.get_child_count()
		g.host_interact(host_p, chest)
		await _wait(0.4)
		check(chest.opened and after_first > before and g.items_root.get_child_count() == after_first, "floor 2 chest opens once (no bottomless chest)")
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_chest_open", chest.prop_id])
	else:
		log_line("no chest on floor 2, chest check skipped")
	await _wait(0.5)


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
			if p.global_position.distance_to(boss.global_position) > 260.0:
				p.host_teleport(g.nearest_floor(boss.global_position + Vector2(0, 90)))
		await _wait(1.0)
		t += 1.0
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
	for p in g.players_root.get_children():
		p.host_teleport(g.portal.global_position + Vector2(randf_range(-10, 10), 0))
	var down := await _wait_until(func(): return g.depth == 2, 8.0)
	check(down, "party reached floor 2 through the portal")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_depth", 2])
		await _wait(0.5)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(1.0)


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
		pack.append(g.spawn_monster("ghoul", c + Vector2(110, -40 + i * 26), false))
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
			samples += 1
			if e.target == tank:
				on_tank += 1
			if last.has(e) and last[e] != e.target:
				switches += 1
				if last_switch.has(e) and t - float(last_switch[e]) < 2.0:
					rapid += 1
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


func _wipe_scenario() -> void:
	var g := _game()
	await _wait(2.0)
	for p in g.players_root.get_children():
		p.iframe_left = 0.0
		Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), p, 99999.0)
	await _wait(1.0)
	check(g._wiped, "party wipe detected when nobody is standing")
	var host_p := _local()
	check(GameState.characters[1].equipment.is_empty(), "wipe rules applied (equipment lost)")
	var back := await _wait_until(func(): return get_tree().current_scene.name == "Lobby", 12.0)
	check(back, "host returned to the lobby after the wipe")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["check_lobby", null])
	await _wait(1.0)
	check(host_p == null or not is_instance_valid(host_p), "game scene freed")
	# A second run starts cleanly with the wiped characters.
	await _wait_until(func(): return GameState.roster.size() >= (2 if NetworkManager.has_remote_peers() else 1), 10.0)
	NetworkManager.start_run()
	var again := await _wait_until(func(): return _game() != null and _game().depth == 1 and _game().players_root.get_child_count() == GameState.roster.size(), 20.0)
	check(again, "second run started after the wipe with every player spawned")
	if again:
		await _wait(1.0)
		var p2 := _local()
		check(p2 != null and p2.inv.equipment.is_empty() and p2.is_alive(), "host starts the new run alive, in underwear")
		check(not _game()._wiped, "wipe flag reset for the new run")
	if NetworkManager.has_remote_peers():
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await _wait(0.5)


## Solo: every class uses all 5 skills (switches class by restarting the run is out of scope,
## so this runs with the class given by --class).
func _classes_scenario() -> void:
	var g := _game()
	var p := _local()
	await _wait(1.0)
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
		check(used.has("%s:%s" % [p.name, sid]), "%s used %s" % [p.class_id, sid])
	log_line("resource %s before=%.1f after=%.1f max=%.1f" % [p.resource.kind, res_before, p.resource.value, p.resource.max_value])
	if p.resource.kind == "fury":
		check(p.resource.max_value == 100.0, "fury pool is 100")
	else:
		check(p.resource.max_value > 0.0, "mana pool exists")
	await _wait(0.5)


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


func _snap(dir: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join(name_ + ".png"))
	log_line("shot " + name_)


## Windowed screenshot tour of every screen (visual review), e.g.
##   godot --path . -- --scenario=shots --shot=/tmp/shots --class=warrior
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
	GameState.select_character(char_name, class_id)
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
	hud.close_overlay()
	hud.open_radial("q")
	await _wait(0.3)
	await _snap(dir, "07_radial")
	hud.close_radial()
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
	focus = get_viewport().gui_get_focus_owner()
	check(focus is Button and str(focus.text).begins_with("Play as"), "lobby focuses the confirm button")
	await _press(JOY_BUTTON_A)
	await _wait(0.5)
	check(GameState.roster.has(1), "character confirmed with A")
	var found := false
	for i in 14:
		focus = get_viewport().gui_get_focus_owner()
		if focus is Button and str(focus.text).begins_with("Start run"):
			found = true
			break
		await _press(JOY_BUTTON_DPAD_DOWN)
	check(found, "D-pad reaches the Start button")
	await _press(JOY_BUTTON_A)
	var in_game := await _wait_until(func(): return _game() != null and _local() != null, 15.0)
	check(in_game, "run started from the lobby with the gamepad")
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
	var removed := InputSettings.bind("skill_1", "kbm", 0, "key:K")
	InputSettings.bind("interact", "pad", 0, "button:y")
	check(removed.is_empty(), "binding K to skill 1 had no conflicts")
	var conflict := InputSettings.bind("skill_2", "kbm", 0, "key:K")
	check(conflict.size() == 1, "binding K again resolves the conflict (%s)" % ", ".join(conflict))
	InputSettings.bind("skill_1", "kbm", 0, "key:K")
	check(_has_key("skill_1", KEY_K), "InputMap updated for skill 1")
	_finish("rebind saved")


func _rebind_check() -> void:
	check(_has_key("skill_1", KEY_K), "rebinding of skill 1 survived a restart")
	var pad_ok := false
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_Y:
			pad_ok = true
	check(pad_ok, "gamepad rebinding of interact survived a restart")
	InputSettings.reset_to_defaults()
	check(_has_key("skill_1", KEY_1) and not _has_key("skill_1", KEY_K), "reset to defaults restores skill 1 = 1")
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
