extends MonsterBehavior
## A status the monster always carries (the Iron Punisher's crowd-control immunity).
## params: status (id)


func _ready() -> void:
	enemy.status.apply(str(p("status", "cc_immune")), -1.0, 0.0, Combat.instance.env_ctx(0.0))


func on_physics(_delta: float) -> void:
	if not enemy.status.has(str(p("status", "cc_immune"))):
		enemy.status.apply(str(p("status", "cc_immune")), -1.0, 0.0, Combat.instance.env_ctx(0.0))


func test_check(_suite: RefCounted) -> String:
	return "" if enemy.status.has(str(p("status", "cc_immune"))) else "status missing"
