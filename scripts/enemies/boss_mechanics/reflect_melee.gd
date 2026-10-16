extends BossMechanic
## Ignis P2 - White Heat: the boss burns hot (a status: +50% haste) and every melee hit on it
## sears the attacker for `reflect` of the blow as fire damage. params: status, reflect (0.3)

var seared := 0


func _ready() -> void:
	Combat.instance.apply_status(ctx(), boss, str(p("status", "white_heat")), -1.0, 0.0)


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	var att: Variant = data.get("attacker")
	if data.get("melee", false) and is_instance_valid(att) and att is Actor and att != boss:
		var c := ctx()
		Combat.instance.deal_damage.call_deferred(c, att, maxf(1.0, amount * float(p("reflect", 0.3))), {"damage_type": "fire", "redirected": true})
		seared += 1
	return amount


func stop() -> void:
	if is_instance_valid(boss):
		boss.status.remove(str(p("status", "white_heat")))


func test_trigger(suite: RefCounted) -> void:
	var c := Combat.instance.make_ctx(suite.p, {"id": "t", "school": "melee"})
	Combat.instance.deal_damage(c, boss, 5.0, {})


func test_check(_suite: RefCounted) -> String:
	return "" if seared > 0 and boss.status.has(str(p("status", "white_heat"))) else "no white heat reflect"
