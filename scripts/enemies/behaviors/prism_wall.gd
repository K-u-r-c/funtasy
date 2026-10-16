extends MonsterBehavior
## Astral Warden: every `every` s raises an arcane prism that reflects every hero projectile for
## `duration` s (a status with the reflect_projectiles flag). params: every (10), duration (4), status

var _left := 2.0
var raised := 0


func on_think(_g: Node) -> bool:
	_left -= float(GameData.bal("ai.think_interval"))
	if _left > 0.0 or enemy.target == null:
		return false
	_left = float(p("every", 10.0))
	Combat.instance.apply_status(Combat.instance.make_ctx(enemy, {"id": "prism", "school": "spell"}), enemy, str(p("status", "prism_ward")), float(p("duration", 4.0)), 0.0)
	Combat.instance.fx.ring.rpc(enemy.global_position, 26.0, "#a080ff", "")
	raised += 1
	return false


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	enemy.add_threat(suite.p, 10.0)


func test_check(_suite: RefCounted) -> String:
	return "" if raised > 0 and enemy.status.has_flag("reflect_projectiles") else "no prism"
