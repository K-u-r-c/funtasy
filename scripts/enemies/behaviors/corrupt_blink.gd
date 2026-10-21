extends CorruptBehavior
## Corrupted - Shadowstep: every `every` s, when its target is within `range`, a violet ring marks
## the spot `behind` px behind the target; then it steps out of the shadows there and strikes.

var _left := 3.0


func on_physics(delta: float) -> void:
	if not enemy.aggro or not enemy.is_alive():
		return
	_left -= delta
	if _left > 0.0:
		return
	var t: Actor = enemy.target if enemy.target and is_instance_valid(enemy.target) else null
	if t == null or t.global_position.distance_to(enemy.global_position) > float(p("range", 280)):
		_left = 0.5
		return
	_left = float(p("every", 8.0))
	var dir := (t.global_position - enemy.global_position).normalized()
	var spot: Vector2 = game().nearest_floor(t.global_position + dir * float(p("behind", 38)))
	warn_at(spot, 24.0, "Shadowstep")
	act_after(func():
		if not is_instance_valid(enemy) or not enemy.is_alive():
			return
		Combat.instance.fx.ring.rpc(enemy.global_position, 26.0, str(p("color", "#b07cff")), "shadow")
		enemy.host_teleport(spot)
		Combat.instance.fx.ring.rpc(spot, 26.0, str(p("color", "#b07cff")), "shadow")
		var abil: Array = enemy.def.get("ai", {}).get("abilities", [])
		if not abil.is_empty() and is_instance_valid(t):
			enemy.cooldowns.erase(str(abil[0]))
			Combat.instance.try_use_skill(enemy, str(abil[0]), t.global_position))


func test_trigger(suite: RefCounted) -> void:
	enemy.aggro = true
	enemy.target = suite.p
	_left = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if uses > 0 else "did not blink"
