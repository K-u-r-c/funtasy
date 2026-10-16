extends MonsterBehavior
## Hellfire Cultist (and others): on death it releases a skill's effects at its feet (a searing
## heat shockwave). params: skill (id)

var burst := false


func on_death() -> bool:
	if burst:
		return false
	burst = true
	var sk := GameData.skill(str(p("skill", "")))
	var ctx := Combat.instance.make_ctx(enemy, sk)
	for eff in sk.get("effects", []):
		Combat.instance.run_effect(eff, ctx, enemy.global_position, enemy.global_position)
	return false


func test_trigger(suite: RefCounted) -> void:
	Combat.instance.deal_damage(Combat.instance.make_ctx(suite.p, {"id": "t", "school": "spell"}), enemy, enemy.health.hp + 50.0, {"damage_type": "true"})
	await suite.da._wait(0.2)


func test_check(_suite: RefCounted) -> String:
	return "" if burst else "no death burst"
