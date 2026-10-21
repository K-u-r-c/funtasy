class_name DropSuite
extends RefCounted
## #75 Loot falls out of monsters (scenario "drops" solo, "drops_lan" host + client): a monster's
## drop starts at the monster and lands where the loot rules place it (never in a wall or a
## doorway); nothing can be picked up mid-flight (prompt and host); after landing it can. A floor
## whose monsters drop no named legendary gets one from its boss (with its beam); a floor that
## already had one can still roll more from the boss. The guarantee flag is saved with the floor.

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Kills a fresh `id` monster at `at` (boss when `boss`) and returns the ground items it threw.
func kill_for_loot(id: String, at: Vector2, boss: bool = false) -> Array:
	var before: Array = g.items_root.get_children()
	var m: Enemy = g.spawn_monster(id, at, boss)
	await da._wait(0.3)
	m.set_physics_process(false)
	var p: Player = da._local()
	var ctx := Combat.instance.make_ctx(p, {"id": "test_kill", "school": "physical"})
	da.set_meta("dr_died_at", m.global_position)
	Combat.instance.deal_damage(ctx, m, m.health.hp + 99999.0, {"damage_type": "true"})
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	return g.items_root.get_children().filter(func(it): return not before.has(it))


func run() -> void:
	g = da._game()
	var p: Player = da._local()
	p.iframe_left = 9999.0
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(60, 0))
	p.host_teleport(spot + Vector2(-50, 0))
	await da._wait(0.4)
	# 1. A monster's drop flies out of it and lands by the loot rules.
	GameState.set_meta("test_force_drop", true)
	var items := await kill_for_loot("ghoul", spot)
	GameState.set_meta("test_force_drop", false)
	da.check(not items.is_empty(), "the ghoul dropped something (%d items)" % items.size())
	var rise := Vector2(0, -float(GameData.bal("loot.flight.from_height")))
	spot = da.get_meta("dr_died_at", spot)
	var bad := []
	for it in items:
		if it.from == Vector2.INF or it.from.distance_to(spot + rise) > 2.0:
			bad.append("%s from %s" % [it.name, it.from])
		var c: Vector2i = g.dungeon.cell_of(it.global_position)
		if not DungeonGenerator.walkable(g.dungeon.cell_at(c)) or g.in_doorway(it.global_position):
			bad.append("%s lands in a wall or doorway" % it.name)
		if it.global_position.distance_to(spot) > float(GameData.bal("loot.drop_scatter")) + 2.0:
			bad.append("%s lands %.0f px away" % [it.name, it.global_position.distance_to(spot)])
	da.check(bad.is_empty(), "every item starts at the monster and lands where the loot rules put it%s" % ("" if bad.is_empty() else ": %s" % [bad]))
	var flying: Array = items.filter(func(it): return not it.is_landed())
	da.check(flying.size() == items.size(), "right after the kill every item is still in the air")
	if not items.is_empty():
		var it0: Node = items[0]
		p.host_teleport(it0.global_position + Vector2(-6, 0))
		p.aim_pos = it0.global_position
		await da.get_tree().process_frame
		var offered: Dictionary = g.find_interactable(p, 0)
		da.check(offered.get("node") == null or not items.has(offered.get("node")), "a flying item isn't offered")
		var count: int = g.items_root.get_child_count()
		g.host_interact(p, it0)
		await da.get_tree().process_frame
		da.check(is_instance_valid(it0) and not it0.is_queued_for_deletion() and g.items_root.get_child_count() == count, "the host refuses to hand over an item still in the air")
		await da._wait(1.3)
		da.check(items.all(func(it): return not is_instance_valid(it) or it.is_landed()), "every item has landed")
		g.host_interact(p, it0)
		await da._wait(0.2)
		da.check(not is_instance_valid(it0) or it0.is_queued_for_deletion(), "once it has landed it is picked up")
	for it in g.items_root.get_children():
		it.queue_free()
	# 2. No named legendary from the floor's enemies: the boss brings one, with its beam.
	GameState.set_meta("test_no_legendary", true)
	g.legendary_from_enemies = false
	var boss_id: String = g.boss_id
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var drops := await kill_for_loot(boss_id, spot, true)
	var named: Array = drops.filter(func(it): return not str(it.item.get("legendary", "")).is_empty())
	da.check(named.size() == 1 and g.legendary_from_enemies, "a floor whose monsters dropped no legendary gets one from its boss (%d)" % named.size())
	await da._wait(1.6)
	da.check(not named.is_empty() and named[0].is_landed() and named[0].beam_up(), "the legendary lands under its beam of light")
	var snap: Dictionary = FloorState.capture(g, {})
	da.check(bool(snap.get("legendary_from_enemies", false)), "the guarantee is saved with the floor")
	for it in g.items_root.get_children():
		it.queue_free()
	# 3. A floor that already had one still rolls more by chance.
	GameState.set_meta("test_no_legendary", false)
	GameState.set_meta("test_force_legendary", true)
	g.legendary_from_enemies = true
	if is_instance_valid(g.portal):
		g.portal.queue_free()
		g.portal = null
	var drops2 := await kill_for_loot(boss_id, spot + Vector2(20, 0), true)
	var named2: Array = drops2.filter(func(it): return not str(it.item.get("legendary", "")).is_empty())
	da.check(named2.size() >= 1, "a floor that already had a legendary can still roll more (%d)" % named2.size())
	GameState.set_meta("test_force_legendary", false)
	await da._wait(1.0)


## LAN: the client sees the same flight and can't take an item mid-air; after landing it can.
func run_lan() -> void:
	g = da._game()
	var p: Player = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	var c: Player = da._other_player()
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(60, 0))
	p.iframe_left = 9999.0
	c.iframe_left = 9999.0
	p.host_teleport(spot + Vector2(-60, 0))
	c.host_teleport(spot + Vector2(0, 8))
	await da._wait(0.8)
	GameState.set_meta("test_force_drop", true)
	var items := await kill_for_loot("ghoul", spot)
	GameState.set_meta("test_force_drop", false)
	da.check(not items.is_empty(), "host: the ghoul dropped something")
	if items.is_empty():
		return
	var it: Node = items[0]
	NetworkManager.to_clients("DevAuto", "client_cmd", ["dr_flight", [str(it.name), it.from, it.global_position]])
	await da._wait(0.25)
	da.check(is_instance_valid(it) and not it.is_queued_for_deletion(), "host: the client's grab mid-air was refused")
	await da._wait(1.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["dr_take", str(it.name)])
	await da._wait(1.0)
	da.check(not is_instance_valid(it) or it.is_queued_for_deletion(), "host: once landed the client picked it up")
	await da._wait(0.5)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var p: Player = da._local()
	match cmd:
		"dr_flight":
			var it: Node = g.items_root.get_node_or_null(str(arg[0]))
			da.check(it != null and it.from.distance_to(arg[1]) < 1.0 and it.global_position.distance_to(arg[2]) < 1.0,
				"client: the drop flies from the monster to the same spot as on the host")
			if it:
				da.check(not it.is_landed(), "client: the item is still in the air")
				p.aim_pos = it.global_position
				var offered: Dictionary = g.find_interactable(p, 0)
				da.check(offered.get("node") != it, "client: a flying item isn't offered")
				p.request_interact.rpc_id(1, it.get_path())
		"dr_take":
			var it2: Node = g.items_root.get_node_or_null(str(arg))
			da.check(it2 != null and it2.is_landed(), "client: the item has landed")
			if it2:
				p.request_interact.rpc_id(1, it2.get_path())
