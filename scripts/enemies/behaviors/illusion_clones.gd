extends MonsterBehavior
## Void Weaver: when it notices a hero it conjures `count` mirror phantoms that cast shadowy
## missiles too; only the true weaver casts a ground shadow. params: count (3), monster (id)

var made := 0


func on_think(g: Node) -> bool:
	if made > 0 or not enemy.aggro or enemy.target == null:
		return false
	for i in int(p("count", 3)):
		var pos: Vector2 = g.nearest_floor(enemy.global_position + Vector2.from_angle(TAU * i / float(p("count", 3))) * 50.0)
		var e: Enemy = g.spawn_monster(str(p("monster", "void_phantom")), pos, false)
		if e:
			made += 1
			e.add_threat(enemy.target, 10.0)
	Combat.instance.fx.ring.rpc(enemy.global_position, 60.0, "#6040a0", "")
	return false


func test_trigger(suite: RefCounted) -> void:
	enemy.add_threat(suite.p, 10.0)
	enemy.aggro = true


func test_check(_suite: RefCounted) -> String:
	return "" if made == int(p("count", 3)) else "made %d phantoms" % made
