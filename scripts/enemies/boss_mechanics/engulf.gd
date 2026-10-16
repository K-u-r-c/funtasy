extends BossMechanic
## Murk Amalgam P1 - Engulf: swallows its current target (the tank). The victim is hidden and
## takes acid damage every second; allies must deal `burst` damage (scaled by the boss's HP
## multiplier) within `duration` s to force it out, or the victim is spat out for `fail` of max HP.
## params: every, duration (8), burst (500), dot (dict), fail (0.45)

var victim: Player = null
var _left := -1.0
var _tick := 0.0
var _taken := 0.0
var _need := 0.0
var freed := false


func trigger() -> void:
	if victim:
		return
	var t: Actor = boss.target
	if not (t is Player) or not t.is_targetable():
		var pool := living_players()
		if pool.is_empty():
			return
		t = pool[0]
	victim = t
	_left = float(p("duration", 8.0))
	_taken = 0.0
	_need = float(p("burst", 500.0)) * maxf(boss.hp_mult, 0.2)
	Combat.instance.apply_status(ctx(), victim, "engulfed", _left + 0.5, 0.0)
	victim.host_teleport(boss.global_position)
	Combat.instance.fx.sound.rpc("engulf", boss.global_position)
	game().broadcast_message.rpc("The Amalgam engulfs %s! Burst it down (%d damage)!" % [victim.display_name, int(_need)], "#7fd94a")


func physics(delta: float) -> void:
	super.physics(delta)
	if victim == null:
		return
	if not is_instance_valid(victim):
		victim = null
		return
	victim.host_teleport(boss.global_position)
	_left -= delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		var c := ctx()
		victim.status.remove("engulfed")
		Combat.instance.deal_damage(c, victim, Combat.instance.value_of_spec(p("dot", {"base": 2, "coef": 0.5}), c), {"damage_type": "nature", "dot": true})
		if is_instance_valid(victim) and victim.is_alive():
			Combat.instance.apply_status(c, victim, "engulfed", _left + 0.5, 0.0)
	if _left <= 0.0:
		var v := victim
		_release(false)
		if is_instance_valid(v) and v.is_targetable():
			Combat.instance.deal_damage(ctx(), v, v.health.max_hp * float(p("fail", 0.45)), {"damage_type": "true"})


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	if victim and data.get("attacker") is Player and data.attacker != victim:
		_taken += amount
		if _taken >= _need:
			_release(true)
	return amount


func _release(burst: bool) -> void:
	if victim and is_instance_valid(victim):
		victim.status.remove("engulfed")
		victim.host_teleport(game().nearest_floor(boss.global_position + Vector2(0, 50)))
		if burst:
			freed = true
			game().broadcast_message.rpc("%s is torn free!" % victim.display_name, "#c0ff90")
	victim = null
	_left = -1.0


func stop() -> void:
	if victim:
		_release(true)


func test_check(_suite: RefCounted) -> String:
	if victim:
		# The party bursts the boss.
		_taken = _need
		_release(true)
		return "bursting"
	return "" if freed else "nobody engulfed"
