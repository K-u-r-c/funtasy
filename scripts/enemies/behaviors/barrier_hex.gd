extends MonsterBehavior
## Barrow Hag: every `every` s hexes a hero with Wither Hex; while it lasts, 5% of the hero's
## maximum health each second is turned into absorb shields on the monsters around the hag.
## params: every (12), duration (6), pct (0.05), radius (220)

var _left := 2.0
var _hexed: Actor = null
var _hold := 0.0
var _tick := 0.0
var shielded := 0


func on_think(_g: Node) -> bool:
	_left -= float(GameData.bal("ai.think_interval"))
	var t: Actor = enemy.target
	if _left > 0.0 or t == null or not is_instance_valid(t) or not enemy.can_act():
		return false
	_left = float(p("every", 12.0))
	_hexed = t
	_hold = float(p("duration", 6.0))
	Combat.instance.apply_status(Combat.instance.make_ctx(enemy, {"id": "wither_hex", "school": "spell"}), t, "wither_hex", _hold, 0.0)
	enemy.play_action.rpc("cast", enemy.facing)
	return true


func on_physics(delta: float) -> void:
	if _hexed == null:
		return
	_hold -= delta
	if _hold <= 0.0 or not is_instance_valid(_hexed) or not _hexed.is_targetable():
		_hexed = null
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var amount: float = _hexed.health.max_hp * float(p("pct", 0.05))
	var ctx := Combat.instance.make_ctx(enemy, {"id": "wither_hex", "school": "spell", "damage_type": "shadow"})
	Combat.instance.deal_damage(ctx, _hexed, amount, {"damage_type": "shadow", "dot": true})
	for e in game().enemies_root.get_children():
		if e is Enemy and e.is_alive() and e.team == enemy.team and e.global_position.distance_to(enemy.global_position) <= float(p("radius", 220.0)):
			e.health.absorb += amount
			e.health.absorb_time = maxf(e.health.absorb_time, 8.0)
			shielded += 1


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	enemy.add_threat(suite.p, 10.0)


func test_check(_suite: RefCounted) -> String:
	return "" if shielded > 0 else "no shields woven"
