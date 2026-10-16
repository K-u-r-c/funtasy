extends MonsterBehavior
## Heretic Flesh-Stitcher: every `every` s injects the nearby ally monsters of `creature` type
## (or any, without it) with a serum status. params: every (8), radius (220), status, duration,
## creature, skill (for the cast animation / cooldown record)

var _left := 2.0
var buffed := 0


func on_think(g: Node) -> bool:
	_left -= float(GameData.bal("ai.think_interval"))
	if _left > 0.0 or not enemy.can_act():
		return false
	var pool: Array = []
	for e in g.enemies_root.get_children():
		if e == enemy or not (e is Enemy) or not e.is_alive() or e.team != enemy.team:
			continue
		if p("creature", "") != "" and e.creature_type() != str(p("creature", "")) and not e.status.has(str(p("status", "foul_serum"))):
			continue
		if e.global_position.distance_to(enemy.global_position) <= float(p("radius", 220.0)) and not e.status.has(str(p("status", "foul_serum"))):
			pool.append(e)
	if pool.is_empty():
		_left = 1.0
		return false
	_left = float(p("every", 8.0))
	var ctx := Combat.instance.make_ctx(enemy, {"id": str(p("skill", "stitcher_serum")), "school": "spell"})
	for e2 in pool:
		Combat.instance.apply_status(ctx, e2, str(p("status", "foul_serum")), float(p("duration", 12.0)), 0.0)
		Combat.instance.fx.ring.rpc(e2.global_position, 20.0, "#90ff60", "")
		buffed += 1
	enemy.play_action.rpc("cast", enemy.facing)
	Combat.instance.fx.sound.rpc("buff", enemy.global_position)
	return true


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	suite.g.spawn_monster("plague_ratman", suite.g.nearest_floor(enemy.global_position + Vector2(40, 0)), false)
	await suite.da._wait(0.2)


func test_check(_suite: RefCounted) -> String:
	return "" if buffed > 0 else "nobody buffed"
