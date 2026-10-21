extends CorruptBehavior
## Corrupted - Warding: every `every` s it chants over the most hurt monster within `range`: a
## blue ring on that ally warns, then a ward of `absorb` x its health shields it.

var _left := 3.0
var shielded := 0


func on_physics(delta: float) -> void:
	if not enemy.aggro or not enemy.is_alive():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = float(p("every", 9.0))
	var ally := _ally()
	if ally == null:
		return
	warn_at(ally.global_position, 28.0, "Ward", ally.get_path())
	enemy.play_action.rpc("cast", (ally.global_position - enemy.global_position).normalized())
	act_after(func():
		if is_instance_valid(ally) and ally.is_alive():
			ally.health.absorb = maxf(ally.health.absorb, ally.health.max_hp * float(p("absorb", 0.35)))
			ally.health.absorb_time = 12.0
			Combat.instance.fx.actor_fx.rpc(ally.get_path(), "buff")
			shielded += 1)


func _ally() -> Node:
	var best: Node = null
	var worst := 2.0
	for e in game().enemies_root.get_children():
		if e == enemy or not is_instance_valid(e) or not e.is_alive() or e.team != enemy.team or e.is_boss:
			continue
		if e.global_position.distance_to(enemy.global_position) > float(p("range", 200)):
			continue
		var f: float = e.health.fraction()
		if f < worst:
			worst = f
			best = e
	return best


func test_trigger(suite: RefCounted) -> void:
	enemy.aggro = true
	_left = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if shielded > 0 else "no ally shielded"
