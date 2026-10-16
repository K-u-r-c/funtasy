extends BossMechanic
## Malazar P2 - Tome Prison (D32): the party is banished into a monochrome parchment dimension -
## the floor's sealed side arena (`layout.side_arena`, or the boss room itself when a floor has
## none). Malazar is out of reach; giant ink drops fall; the heroes must destroy 4 Authorial Seals.
## When the last seal breaks the party returns and the Archivist is weakened (+50% damage taken).
## If the seals still stand after `max_time` s the prison spits the party out, battered, and the
## Archivist is not weakened. params: seals (4), drop_every (1.4), max_time (40), damage (dict)

var seals: Array = []
var _active := false
var _drop := 0.0
var freed := false
var _time := 0.0


func _ready() -> void:
	_active = true
	var g := game()
	var room := _prison_rect().grow(-48.0)
	if g.layout.has("side_arena"):
		var i := 0
		for pl in living_players():
			pl.host_teleport(g.nearest_floor(room.get_center() + Vector2(-30 + 20 * i, 0)))
			i += 1
	var spots := [room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)]
	for i in int(p("seals", 4)):
		var nm := "Seal_%d" % i
		g.dungeon.spawn_prop.rpc(nm, "authorial_seal", g.nearest_floor(spots[i % spots.size()]))
		seals.append(nm)
	var c := ctx()
	Combat.instance.apply_status(c, boss, "out_of_reach", -1.0, 0.0)
	for pl in living_players():
		Combat.instance.apply_status(c, pl, "tome_prison", -1.0, 0.0)
	g.broadcast_message.rpc("Malazar seals you inside the Tome Prison! Break the 4 Authorial Seals!", "#e0e0e0")


func busy() -> bool:
	return _active


func physics(delta: float) -> void:
	if not _active:
		return
	var g := game()
	var left := 0
	for nm in seals:
		var pr: Node = g.dungeon.props.get(nm)
		if pr and is_instance_valid(pr) and pr.destructible():
			left += 1
	if left == 0:
		_release()
		return
	_time += delta
	if _time >= float(p("max_time", 40.0)):
		_eject()
		return
	_drop -= delta
	if _drop > 0.0:
		return
	_drop = float(p("drop_every", 1.4))
	var c := ctx()
	c.damage_type = "shadow"
	for pl in living_players():
		var at: Vector2 = pl.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		Combat.instance.run_effect({"type": "delayed", "delay": 1.2, "at": "self", "telegraph": {"radius": 30, "color": "#101010"},
			"effects": [{"type": "aoe", "radius": 30, "damage": p("damage", {"base": 6, "coef": 1.0}), "damage_type": "shadow", "color": "#202020"}]}, c, at, at)


func _prison_rect() -> Rect2:
	var g := game()
	if g.layout.has("side_arena"):
		var r: Rect2i = g.layout.side_arena
		return Rect2(Vector2(r.position * g.dungeon.tile), Vector2(r.size * g.dungeon.tile))
	return boss_room()


## The seals held: the prison collapses, the party is thrown back hurt and Malazar keeps his guard.
func _eject() -> void:
	var c := ctx()
	for pl in living_players():
		Combat.instance.deal_damage(c, pl, pl.health.max_hp * 0.3, {"damage_type": "shadow", "area": true})
	_release()
	boss.status.remove("weakened_archivist")
	freed = false
	game().broadcast_message.rpc("The Tome Prison collapses - the seals held!", "#c0c0c0")


func _release() -> void:
	_active = false
	freed = true
	if game().layout.has("side_arena"):
		for pl in game().players_root.get_children():
			if pl.life_state != Player.Life.GHOST:
				pl.host_teleport(game().nearest_floor(boss.global_position + Vector2(randf_range(-60, 60), 80)))
	boss.status.remove("out_of_reach")
	Combat.instance.apply_status(ctx(), boss, "weakened_archivist", -1.0, 0.0)
	for pl in game().players_root.get_children():
		pl.status.remove("tome_prison")
	game().broadcast_message.rpc("Reality returns - the Archivist is weakened!", "#ffffff")


func stop() -> void:
	if _active:
		_release()
	var g := game()
	for nm in seals:
		if g.dungeon.props.has(nm):
			g.dungeon.destroy_prop.rpc(nm)
	seals.clear()


func test_trigger(suite: RefCounted) -> void:
	var g := game()
	for nm in seals:
		var pr: Node = g.dungeon.props.get(nm)
		if pr:
			pr.take_damage(9999.0, Combat.instance.test_ctx(suite.p, {"id": "t", "school": "melee"}))
	await suite.da._wait(0.3)


func test_check(suite: RefCounted) -> String:
	return "" if freed and not suite.p.status.has("tome_prison") and boss.status.has("weakened_archivist") else "still imprisoned"
