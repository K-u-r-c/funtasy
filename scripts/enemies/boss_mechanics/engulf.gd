extends BossMechanic
## Murk Amalgam P1 - Engulf: swallows its current target (the tank) for at most `duration` s.
## The victim is held inside the boss (Player.held_by: pinned to it on every peer, no collision,
## the Engulfed status icon and a green, lifted look), takes acid damage every second, and the
## whole party sees a "Burst it down" bar (Boss.burst_bar). Allies must deal `burst` damage (scaled
## by the boss's HP multiplier) to tear the victim free; otherwise it is spat out for `fail` of
## max HP. The victim is always released when the time is up, it falls, the phase ends or the boss
## dies (#12). params: every, duration (4), burst (300), dot (dict), fail (0.45)

var victim: Player = null
var _left := -1.0
var _tick := 0.0
var _taken := 0.0
var _need := 0.0
var freed := false
var grabs := 0
var longest := 0.0
var _held_t := 0.0


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
	_left = minf(float(p("duration", 4.0)), 4.0)
	_held_t = 0.0
	_tick = 1.0
	_taken = 0.0
	_need = float(p("burst", 300.0)) * maxf(boss.hp_mult, 0.2)
	grabs += 1
	Combat.instance.apply_status(ctx(), victim, "engulfed", _left + 0.2, 0.0)
	victim.held_by = boss.get_path()
	boss.burst_bar = Vector2(0.0, _left)
	Combat.instance.fx.sound.rpc("engulf", boss.global_position)
	game().broadcast_message.rpc("The Amalgam engulfs %s! Burst it down!", "#7fd94a", [victim.display_name])


func physics(delta: float) -> void:
	super.physics(delta)
	if victim == null:
		return
	if not is_instance_valid(victim) or not victim.is_alive():
		_release(false)
		return
	_left -= delta
	_held_t += delta
	_tick -= delta
	boss.burst_bar = Vector2(clampf(_taken / maxf(_need, 1.0), 0.0, 1.0), maxf(_left, 0.0))
	if _tick <= 0.0:
		_tick = 1.0
		var c := ctx()
		Combat.instance.deal_damage(c, victim, Combat.instance.value_of_spec(p("dot", {"base": 2, "coef": 0.5}), c), {"damage_type": "nature", "dot": true})
	if _left <= 0.0 and victim:
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
	longest = maxf(longest, _held_t)
	if victim and is_instance_valid(victim):
		victim.status.remove("engulfed")
		victim.held_by = NodePath()
		victim.host_teleport(game().nearest_floor(boss.global_position + Vector2(0, 50)))
		if burst:
			freed = true
			game().broadcast_message.rpc("%s is torn free!", "#c0ff90", [victim.display_name])
	victim = null
	_left = -1.0
	if is_instance_valid(boss):
		boss.burst_bar = Vector2.ZERO


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
