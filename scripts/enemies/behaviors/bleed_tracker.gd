extends MonsterBehavior
## Bloodhound of the Barrow: ignores threat for any bleeding hero in range and runs twice as fast
## at heroes below `low` health. params: range (360), low (0.4), status (frenzied_hunt)

var tracked: Actor = null


func target_override() -> Actor:
	var g := game()
	if g == null:
		return null
	var best: Actor = null
	var best_d := float(p("range", 360.0))
	for pl in g.players_root.get_children():
		if pl.is_targetable() and pl.status.has("bleed"):
			var d: float = pl.global_position.distance_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = pl
	tracked = best
	return best


func on_think(_g: Node) -> bool:
	var t: Actor = enemy.target
	var hunting := t != null and is_instance_valid(t) and t.health.fraction() < float(p("low", 0.4))
	if hunting and not enemy.status.has(str(p("status", "frenzied_hunt"))):
		enemy.status.apply(str(p("status", "frenzied_hunt")), -1.0, 0.0, Combat.instance.env_ctx(0.0))
	elif not hunting:
		enemy.status.remove(str(p("status", "frenzied_hunt")))
	return false


func test_trigger(suite: RefCounted) -> void:
	Combat.instance.apply_status(Combat.instance.make_ctx(enemy, {"id": "t", "school": "melee"}), suite.p, "bleed", 6.0, 1.0)
	suite.p.set_meta("test_keep_status", "bleed")


func test_check(suite: RefCounted) -> String:
	if not suite.p.status.has("bleed"):
		Combat.instance.apply_status(Combat.instance.make_ctx(enemy, {"id": "t", "school": "melee"}), suite.p, "bleed", 6.0, 1.0)
	return "" if tracked == suite.p else "not tracking the bleeding hero"
