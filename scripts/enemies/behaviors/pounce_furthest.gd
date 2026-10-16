extends MonsterBehavior
## Crypt Ghoul: every `every` s it leaps from the shadows onto the player furthest from it
## (within `range`), with a short stun on landing. params: every (9), range (280)

var _left := 3.0


func on_think(game: Node) -> bool:
	_left -= float(GameData.bal("ai.think_interval"))
	if _left > 0.0 or not enemy.can_act() or not enemy.casting.is_empty():
		return false
	var best: Actor = null
	var best_d := 60.0
	for pl in game.players_root.get_children():
		if not enemy._valid_target(pl):
			continue
		var d: float = pl.global_position.distance_to(enemy.global_position)
		if d > best_d and d <= float(p("range", 280.0)) and Combat.instance.has_los(enemy.global_position, pl.global_position):
			best_d = d
			best = pl
	if best == null:
		return false
	_left = float(p("every", 9.0))
	enemy.target = best
	Combat.instance.try_use_skill(enemy, "ghoul_pounce", best.global_position)
	return true


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	# A spot ~150 px away the ghoul can see (pillars and walls block the pounce).
	var spot: Vector2 = suite.g.nearest_floor(enemy.global_position + Vector2(150, 0))
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		var cand: Vector2 = suite.g.nearest_floor(enemy.global_position + dir * 150.0)
		if cand.distance_to(enemy.global_position) > 80.0 and Combat.instance.has_los(enemy.global_position, cand):
			spot = cand
			break
	suite.p.host_teleport(spot)
	await suite.da._wait(0.1)


func test_check(_suite: RefCounted) -> String:
	var uses: Dictionary = Combat.instance.get_meta("uses", {})
	return "" if uses.has("%s:ghoul_pounce" % enemy.name) else "no pounce"
