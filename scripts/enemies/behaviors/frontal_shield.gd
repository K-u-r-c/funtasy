extends MonsterBehavior
## Dread Wight: its iron door of a shield absorbs `reduction` of damage from the front (`arc`°).
## params: reduction (0.7), arc (120)


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	var att: Variant = data.get("attacker")
	if not (is_instance_valid(att) and att is Node2D) or data.get("dot", false):
		return amount
	var to: Vector2 = att.global_position - enemy.global_position
	if to.length() > 1.0 and absf(enemy.facing.angle_to(to)) <= deg_to_rad(float(p("arc", 120.0)) / 2.0):
		return amount * (1.0 - float(p("reduction", 0.7)))
	return amount


func test_trigger(suite: RefCounted) -> void:
	enemy.facing = (suite.p.global_position - enemy.global_position).normalized()


func test_check(suite: RefCounted) -> String:
	var front := modify_damage_taken(100.0, {"attacker": suite.p})
	enemy.facing = -(suite.p.global_position - enemy.global_position).normalized()
	var back := modify_damage_taken(100.0, {"attacker": suite.p})
	return "" if front < 40.0 and back > 99.0 else "front %d back %d" % [front, back]
