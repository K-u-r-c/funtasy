class_name ResumeSuite
extends RefCounted
## #55 Continuing a saved game resumes the floor (scenario "resume" solo, "resume_lan" on a LAN
## pair): on floor 1 the heroes kill two monsters, open a chest, break a prop, open a door, drop
## an item, lose some HP and walk to far rooms; then the host leaves through the pause menu (the
## real path) and continues the game from the lobby (the client rejoins and claims its hero).
## The floor must come back as it was left: the same layout, the same living monsters where
## they stood, the chest open, the prop broken, the door open, the item in its place, every hero
## where it stood with its HP, and every player's discovered map. #60: the heroes wear armour and a
## legendary, and the lobby preview of the continued game (host and client) shows exactly the
## layers each hero shows in the world.

const POS_TOL := 8.0
const ENEMY_TOL := 24.0

var da: Node
var g: Node
var p: Player
var _before: Dictionary  ## the world as the save is written (the frame of the quit)


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _kill(e: Actor) -> void:
	Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), e, e.health.hp + 50.0, {"damage_type": "true"})


## Looks compare by value (the world's variant keys are StringNames, the save's Strings).
static func same_look(a: Dictionary, b: Dictionary) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))


static func discovered_count(d: Dungeon) -> int:
	return d.discovered.count(1)


## Everything the check compares, read from the world as it stands.
func record() -> Dictionary:
	var enemies: Array = []
	for e in g.enemies_root.get_children():
		if e is Enemy and e.is_alive() and e.team == Actor.Team.MONSTERS and not e.has_meta("summoned"):
			enemies.append([e.def_id, e.global_position, e.is_boss])
	var heroes := {}
	var looks := {}
	for pl in g.players_root.get_children():
		heroes[pl.display_name] = [pl.global_position, pl.health.hp]
		looks[pl.display_name] = pl.appearance.duplicate(true)
	var items: Array = []
	for gi in g.items_root.get_children():
		items.append([str(gi.item.get("uid", "")), gi.global_position])
	var rooms: Array = g.layout.rooms.map(func(r): return str(r.rect))
	return {"looks": looks, "size": g.layout.size, "rooms": rooms, "enemies": enemies, "heroes": heroes, "items": items,
		"props": g.dungeon.props.keys(), "opened": g.dungeon.props.keys().filter(func(n): return g.dungeon.props[n].opened),
		"doors": g.dungeon.doors.map(func(dr): return dr.is_open), "map": discovered_count(g.dungeon), "depth": g.depth}


## The two records match: returns "" or what differs.
static func diff(a: Dictionary, b: Dictionary) -> String:
	if a.size != b.size or a.rooms != b.rooms or a.depth != b.depth:
		return "layout %s / %s rooms, depth %d -> %s / %s rooms, depth %d" % [a.size, a.rooms.size(), a.depth, b.size, b.rooms.size(), b.depth]
	if a.enemies.size() != b.enemies.size():
		return "%d living monsters -> %d" % [a.enemies.size(), b.enemies.size()]
	var left: Array = b.enemies.duplicate()
	for e in a.enemies:
		var hit := -1
		for i in left.size():
			# The boss waits at home after a reload; everything else stands where it stood.
			if left[i][0] == e[0] and (e[2] or left[i][1].distance_to(e[1]) <= ENEMY_TOL):
				hit = i
				break
		if hit < 0:
			return "monster %s at %s is missing" % [e[0], e[1]]
		left.remove_at(hit)
	return ""


func check_same(before: Dictionary, after: Dictionary, chest: String, broken: String, door: int, uid: String) -> void:
	var why := diff(before, after)
	da.check(why.is_empty(), "the same floor with the same living monsters where they stood%s" % ("" if why.is_empty() else ": " + why))
	da.check(after.opened.has(chest), "the opened chest %s is still open" % chest)
	da.check(not after.props.has(broken), "the broken prop %s is still broken" % broken)
	da.check(door < 0 or after.doors[door], "the opened door %d is still open" % door)
	var item_ok := false
	for it in after.items:
		item_ok = item_ok or (it[0] == uid and it[1].distance_to(_item_pos(before, uid)) <= POS_TOL)
	da.check(item_ok, "the dropped item lies where it was dropped")
	for hero in before.heroes:
		var h0: Array = before.heroes[hero]
		var h1: Array = after.heroes.get(hero, [Vector2.INF, -1.0])
		da.check(h1[0].distance_to(h0[0]) <= POS_TOL and absf(float(h1[1]) - float(h0[1])) <= 1.0,
				"%s is back where it stood (%.0f px off) with its HP (%.0f -> %.0f)" % [hero, h1[0].distance_to(h0[0]), h0[1], h1[1]])
	da.check(after.map == before.map and before.map > 0, "the host's discovered map comes back (%d cells -> %d)" % [before.map, after.map])


static func _item_pos(rec: Dictionary, uid: String) -> Vector2:
	for it in rec.items:
		if it[0] == uid:
			return it[1]
	return Vector2.INF


## Host (#60): a hero puts on a plate set and a legendary helm (the client's through its own
## equip request).
func gear_up(pl: Player) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60
	var items: Array = []
	for b in ["plate_chest", "greaves", "boots", "gloves"]:
		items.append(ItemGenerator.generate_equipment(b, 2, 3, rng))
	items.append(ItemGenerator.make_legendary("crown_blood_chieftain", 2, rng))
	for it in items:
		it.req = 1
		pl.host_give_item(it)
		await da._wait(0.2)
		if pl.is_local():
			pl.request_equip.rpc_id(1, pl.inv.backpack.size() - 1)
		else:
			NetworkManager.to_clients("DevAuto", "client_cmd", ["equip_uid", it.uid])
		await da._wait(0.3)


## Host: changes the floor and walks the heroes away. Returns [chest, broken prop, door, uid].
func change_floor() -> Array:
	for pl in g.players_root.get_children():
		await gear_up(pl)
	da.check(g.players_root.get_children().all(func(q): return q.appearance.has("chest") and q.appearance.has("head")),
			"every hero wears the plate chest and the legendary helm")
	var enemies: Array = g.enemies_root.get_children().filter(func(e): return e is Enemy and not e.is_boss)
	for i in mini(2, enemies.size()):
		_kill(enemies[i])
	await da._wait(0.5)
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
	# Open a chest the real way: walk there and interact.
	var chest := ""
	for n in g.dungeon.props:
		if str(n).begins_with("Chest_") and not g.dungeon.props[n].opened:
			chest = str(n)
			break
	if not chest.is_empty():
		var cp: Node = g.dungeon.props[chest]
		p.host_teleport(g.nearest_floor(cp.interact_pos()))
		await da._wait(0.6)
		g.host_interact(p, cp)
	var broken := ""
	for n in g.dungeon.props:
		var pr: Node = g.dungeon.props[n]
		if pr.destructible() and not pr.def.has("explode") and not pr.def.has("proximity") and str(n).begins_with("Prop_"):
			broken = str(n)
			pr.take_damage(pr.hp + 1.0, Combat.instance.make_ctx(p, {"id": "test", "school": "physical"}))
			break
	var door := -1
	for i in g.dungeon.doors.size():
		var dr: Node = g.dungeon.doors[i]
		if not dr.is_open and not dr.sealed and not dr.floodgate:
			dr.host_set_open(true)
			door = i
			break
	var item := ItemGenerator.generate_equipment("gloves", 2, 2, RandomNumberGenerator.new())
	item.uid = "resume_test_item"
	g.loot.drop_item(item, g.nearest_floor(g.layout.start + Vector2(40, 0)))
	# Spread the heroes over far rooms, hurt.
	var rooms: Array = g.layout.rooms.filter(func(r): return r.role == "normal")
	var i := 0
	for pl in g.players_root.get_children():
		var room: Dictionary = rooms[(rooms.size() - 1 - i) % rooms.size()]
		pl.host_teleport(g.nearest_floor(g.dungeon.cell_center(Rect2i(room.rect).get_center())))
		pl.health.hp = roundf(pl.health.max_hp * (0.6 - 0.1 * i))
		i += 1
	await da._wait(1.0)
	return [chest, broken, door, item.uid]


## Host: the real quit (pause menu, "End session"), then continue the saved game from the lobby.
func quit_and_continue(players: int) -> bool:
	var id := str(GameState.game.id)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.PauseMenu.new())
	await da._wait(0.3)
	# Monsters walk and hit: the world is read in the frame the save is written.
	_before = record()
	hud._overlay._leave()
	var at_menu: bool = await da._wait_until(func(): return da.get_tree().current_scene and da.get_tree().current_scene.name == "MainMenu", 6.0)
	da.check(at_menu, "host left to the main menu through the pause menu")
	var saved := SaveSystem.load_game(id)
	da.check(saved.has("run_seed") and not saved.get("floor", {}).is_empty(), "the saved game holds the run seed and the floor")
	await da._wait(0.5)
	if players > 1:
		NetworkManager.host_enet(da.port)
	else:
		NetworkManager.host_solo()
	await da._wait_until(func(): return da.get_tree().current_scene.name == "Lobby", 8.0)
	await da._wait(0.5)
	da.check(GameState.select_saved_game(id), "host selects the saved game again")
	await da._wait(0.3)
	GameState.claim_slot(0 if GameState.game_info.members[0].name == da.char_name else 1)
	if players > 1:
		await da._wait_until(func(): return da.multiplayer.get_peers().size() >= players - 1, 20.0)
		await da._wait(0.5)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["claim_mine", null])
	var ready: bool = await da._wait_until(func(): return GameState.start_problem().is_empty(), 10.0)
	da.check(ready, "every player claimed their hero")
	await da._wait(0.5)
	var lobby: Node = da.get_tree().current_scene
	var want: Dictionary = _before.looks.get(da.char_name, {})
	da.check(same_look(lobby._preview.look, want) and want.has("chest"),
			"host: the lobby preview shows the saved hero in its own gear (%s), not the class default" % [lobby._preview.look.keys()])
	if players > 1:
		NetworkManager.to_clients("DevAuto", "client_cmd", ["resume_preview", null])
		await da._wait(0.8)
	NetworkManager.start_run()
	# Read the restored world at once, before a monster can land a hit or walk off.
	var ok: bool = await da._wait_until(func(): return _restored(players), 20.0)
	g = da._game()
	p = da._local()
	return ok


## The continued game is in: every hero spawned with its saved state applied, monsters spawned.
func _restored(players: int) -> bool:
	var gm: Node = da._game()
	if gm == null or da._local() == null or gm.players_root.get_child_count() != players or gm.enemies_root.get_child_count() == 0:
		return false
	return gm.players_root.get_children().all(func(q): return not q.has_meta("pending_restore"))


func run_solo() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var changed: Array = await change_floor()
	if not await quit_and_continue(1):
		da.check(false, "the saved game continued")
		return
	check_same(_before, record(), changed[0], changed[1], changed[2], changed[3])
	# A save from before #55 (no run seed, no floor) still loads: a new floor at its depth.
	var legacy := SaveSystem.load_game(str(GameState.game.id))
	legacy.id = "legacy_floor_test"
	legacy.erase("floor")
	legacy.erase("run_seed")
	SaveSystem.save_game(legacy)
	NetworkManager.leave_to_menu()
	await da._wait_until(func(): return da.get_tree().current_scene.name == "MainMenu", 6.0)
	await da._wait(0.5)
	NetworkManager.host_solo()
	await da._wait_until(func(): return da.get_tree().current_scene.name == "Lobby", 8.0)
	await da._wait(0.5)
	da.check(GameState.select_saved_game("legacy_floor_test"), "host selects an old save without a floor")
	GameState.claim_slot(0)
	await da._wait(0.3)
	NetworkManager.start_run()
	var ok: bool = await da._wait_until(func(): return _restored(1), 20.0)
	g = da._game()
	da.check(ok and g.depth == int(legacy.depth) and da._local().global_position.distance_to(g.layout.start) < 80.0,
			"the old save starts a new floor %d with the hero in the start room" % int(legacy.depth))
	SaveSystem.delete_game("legacy_floor_test")


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var changed: Array = await change_floor()
	# The client's map reaches the host every few seconds: give it one report.
	await da._wait(float(GameData.bal("save.map_report_interval")) + 1.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["resume_remember", null])
	await da._wait(0.5)
	if not await quit_and_continue(2):
		da.check(false, "the saved game continued with both players")
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
		return
	check_same(_before, record(), changed[0], changed[1], changed[2], changed[3])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["resume_compare", null])
	await da._wait(1.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, _arg: Variant) -> void:
	g = da._game()
	match cmd:
		"resume_remember":
			# Rejoin after the host ends the session, and remember this peer's own view.
			da.set_meta("rejoin", true)
			var me: Player = da._local()
			da.set_meta("rs_before", [me.global_position, discovered_count(g.dungeon), g.dungeon.props.keys(), me.appearance.duplicate(true)])
		"resume_preview":
			var lobby: Node = da.get_tree().current_scene
			var want: Dictionary = da.get_meta("rs_before")[3]
			da.check(lobby.name == "Lobby" and same_look(lobby._preview.look, want) and want.has("chest"),
					"client: the lobby preview shows its saved hero in its own gear (%s)" % [lobby._preview.look.keys() if lobby.name == "Lobby" else []])
		"resume_compare":
			var before: Array = da.get_meta("rs_before")
			var me: Player = da._local()
			da.check(me.global_position.distance_to(before[0]) <= POS_TOL, "client: its hero is back where it stood (%.0f px off)" % me.global_position.distance_to(before[0]))
			da.check(discovered_count(g.dungeon) == before[1] and before[1] > 0, "client: its own discovered map comes back (%d cells -> %d)" % [before[1], discovered_count(g.dungeon)])
			var keys: Array = g.dungeon.props.keys()
			keys.sort()
			var was: Array = before[2]
			was.sort()
			da.check(keys == was, "client: the same props stand (broken ones stay broken)")
