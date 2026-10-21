extends CorruptBehavior
## Corrupted - Volatile: when it dies its remains swell and glow - an orange ring warns for `warn`
## s - and then explode, hurting every hero in `radius`.

var burst := false


func on_death() -> bool:
	if burst:
		return false
	burst = true
	var at := enemy.global_position
	var c := ctx()
	warn_at(at, float(p("radius", 64)), "Volatile")
	act_after(func():
		Combat.instance.apply_aoe({"type": "aoe", "radius": float(p("radius", 64)), "damage": p("damage", {"base": 6, "coef": 1.5}),
			"damage_type": "fire", "fx": "explosion", "color": str(p("color", "#ff6a2a")), "shake": 4}, c, at))
	return false


func test_trigger(suite: RefCounted) -> void:
	Combat.instance.deal_damage(Combat.instance.test_ctx(suite.p, {"id": "t", "school": "spell"}), enemy, enemy.health.hp + 50.0, {"damage_type": "true"})


func test_check(_suite: RefCounted) -> String:
	return "" if uses > 0 else "did not explode"
