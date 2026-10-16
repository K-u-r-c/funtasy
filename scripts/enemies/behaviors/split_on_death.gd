extends MonsterBehavior
## Acid Slime: splits into `count` smaller monsters (`into`) when it dies.
## params: into (monster id), count (3), radius (22)

var spawned := 0


func on_death() -> bool:
	var g := game()
	if g == null:
		return false
	var n := int(p("count", 3))
	for i in n:
		var pos: Vector2 = g.nearest_floor(enemy.global_position + Vector2.from_angle(TAU * i / n) * float(p("radius", 22.0)))
		var e: Enemy = g.spawn_monster(str(p("into", "acid_slime_small")), pos, false)
		if e:
			spawned += 1
			if enemy.target and is_instance_valid(enemy.target):
				e.add_threat(enemy.target, 5.0)
	Combat.instance.fx.sound.rpc("splash", enemy.global_position)
	return false


func test_trigger(suite: RefCounted) -> void:
	Combat.instance.deal_damage(Combat.instance.make_ctx(suite.p, {"id": "t", "school": "spell"}), enemy, enemy.health.hp + 50.0, {"damage_type": "true"})
	await suite.da._wait(0.3)


func test_check(suite: RefCounted) -> String:
	var n := 0
	for e in suite.g.enemies_root.get_children():
		if is_instance_valid(e) and e.def_id == str(p("into", "acid_slime_small")):
			n += 1
	return "" if n >= int(p("count", 3)) else "split into %d" % n
