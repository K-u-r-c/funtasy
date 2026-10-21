extends CorruptBehavior
## Corrupted - Splitting: when it dies its body heaves (a warning ring over the remains) and then
## tears into `count` lesser copies with `hp_x` of the health.

var split := false


func on_death() -> bool:
	if split:
		return false
	split = true
	var g := game()
	var at := enemy.global_position
	var def_id := enemy.def_id
	var tgt: Actor = enemy.target if enemy.target and is_instance_valid(enemy.target) else null
	warn_at(at, float(p("radius", 30)), "Splitting")
	act_after(func():
		var n := int(p("count", 2))
		for i in n:
			var pos: Vector2 = g.nearest_floor(at + Vector2.from_angle(TAU * i / n) * 18.0)
			var e: Node = g.spawn_monster(def_id, pos, false, {"hp_x": float(p("hp_x", 0.35)), "split_of": true})
			if e and tgt and is_instance_valid(tgt):
				e.add_threat(tgt, 5.0)
		Combat.instance.fx.sound.rpc("slime_split", at))
	return false


func test_trigger(suite: RefCounted) -> void:
	Combat.instance.deal_damage(Combat.instance.test_ctx(suite.p, {"id": "t", "school": "spell"}), enemy, enemy.health.hp + 50.0, {"damage_type": "true"})


func test_check(_suite: RefCounted) -> String:
	return "" if uses > 0 else "did not split"
