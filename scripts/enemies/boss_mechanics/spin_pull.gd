extends BossMechanic
## Morvath P2 - Bone Whirlwind: the boss spins for `duration` s, deflecting projectiles, hitting
## everything around it and dragging players inward. params: every, duration (4), radius (110),
## pull (90), damage (dict)

var _left := -1.0
var _tick := 0.0


func trigger() -> void:
	_left = float(p("duration", 4.0))
	Combat.instance.apply_status(ctx(), boss, "bone_whirlwind", _left, 0.0)
	game().broadcast_message.rpc("Bone Whirlwind!", "#e8e0c8")


func busy() -> bool:
	return _left > 0.0


func physics(delta: float) -> void:
	super.physics(delta)
	if _left <= 0.0:
		return
	_left -= delta
	_tick -= delta
	var players := living_players()
	if not players.is_empty():
		var t: Vector2 = players[0].global_position
		boss.velocity = (t - boss.global_position).normalized() * boss.move_speed() * 0.8
		boss.move_and_slide()
	if _tick <= 0.0:
		_tick = 0.4
		var c := ctx()
		Combat.instance.run_effect({"type": "aoe", "at": "self", "radius": float(p("radius", 110)), "damage": p("damage", {"base": 4, "coef": 0.6}), "color": "#e8e0c8"}, c, boss.global_position, boss.global_position)
		Combat.instance.run_effect({"type": "pull", "at": "self", "radius": float(p("radius", 110)) * 1.6, "force": float(p("pull", 90))}, c, boss.global_position, boss.global_position)


func test_check(_suite: RefCounted) -> String:
	return "" if boss.status.has("bone_whirlwind") or _left > 0.0 else "no whirlwind"
