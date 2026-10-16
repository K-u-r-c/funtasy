extends MonsterBehavior
## Abyssal Leech: latches onto its target (rides along, no dash), draining `fury` Fury / `mana`
## Mana per second. A melee hit from another hero knocks it off (stunned). params: fury (10),
## mana (15), status (leeched), range (26)

var victim: Player = null
var _tick := 0.0
var knocked := false


func on_think(_game: Node) -> bool:
	if victim:
		return false  # keeps biting its host while it drains (target_override)
	var t: Actor = enemy.target
	if is_instance_valid(t) and t is Player and t.is_targetable() and t.global_position.distance_to(enemy.global_position) <= float(p("range", 26.0)) and enemy.can_act():
		victim = t
		set_state("latched")
		Combat.instance.apply_status(Combat.instance.make_ctx(enemy, {"id": "latch", "school": "melee"}), victim, str(p("status", "leeched")), -1.0, 0.0)
		Combat.instance.fx.sound.rpc("hit", enemy.global_position)
		return true
	return false


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if victim else Vector2.INF


func target_override() -> Actor:
	return victim if victim and is_instance_valid(victim) else null


func on_physics(delta: float) -> void:
	if victim == null:
		return
	if not is_instance_valid(victim) or not victim.is_targetable() or not enemy.can_act():
		_release()
		return
	enemy.global_position = victim.global_position + Vector2(6, -2)
	if not victim.status.has(str(p("status", "leeched"))):
		victim.status.apply(str(p("status", "leeched")), -1.0, 0.0, Combat.instance.make_ctx(enemy, {"id": "latch", "school": "melee"}))
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		var drain := float(p("fury", 10)) if victim.resource.kind == "fury" else float(p("mana", 15))
		victim.resource.gain(-drain)


func on_damaged(attacker: Actor, _amount: float) -> void:
	if victim and attacker is Player and attacker != victim and enemy.last_attack_ctx.get("school", "") == "melee":
		knocked = true
		_release()
		Combat.instance.apply_status(Combat.instance.make_ctx(attacker, {"id": "knock_off", "school": "melee"}), enemy, "stun", 1.5, 0.0)
		Combat.instance.fx.number.rpc(enemy.global_position, "Knocked off", "info")


func on_death() -> bool:
	_release()
	return false


func _release() -> void:
	if victim and is_instance_valid(victim):
		victim.status.remove(str(p("status", "leeched")))
	victim = null
	set_state("")


func test_trigger(suite: RefCounted) -> void:
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(14, 0)))
	enemy.add_threat(suite.p, 50.0)


func test_check(suite: RefCounted) -> String:
	if victim == null:
		return "not latched"
	return "" if victim == suite.p else "latched onto someone else"
