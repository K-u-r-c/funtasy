extends MonsterBehavior
## Plague Ratman: once below `threshold` health it backflips away from its target and hurls a
## blinding flask (once). params: threshold (0.3), distance (130), skill (ratman_flask)

var _done := false


func on_think(_game: Node) -> bool:
	if _done or enemy.health.fraction() > float(p("threshold", 0.3)) or not enemy.can_act():
		return false
	var t: Actor = enemy.target
	if t == null or not is_instance_valid(t):
		return false
	_done = true
	var away := (enemy.global_position - t.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	var dest: Vector2 = game().nearest_floor(enemy.global_position + away * float(p("distance", 130.0)))
	enemy.host_dash(dest, 0.35)
	enemy.play_action.rpc("dash", away)
	Combat.instance.fx.sound.rpc("dash", enemy.global_position)
	enemy.cooldowns.erase(str(p("skill", "ratman_flask")))
	enemy.get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(enemy) and enemy.is_alive() and is_instance_valid(t):
			Combat.instance.try_use_skill(enemy, str(p("skill", "ratman_flask")), t.global_position))
	return true


func test_trigger(_suite: RefCounted) -> void:
	enemy.health.hp = enemy.health.max_hp * 0.2


func test_check(_suite: RefCounted) -> String:
	var uses: Dictionary = Combat.instance.get_meta("uses", {})
	return "" if _done and uses.has("%s:%s" % [enemy.name, p("skill", "ratman_flask")]) else "no retreat"
