extends MonsterBehavior
## Ash Imp: when a hero gets within `trigger` px it teleports `distance` px away (every `every`
## s at most). params: trigger (56), distance (140), every (5)

var _cd := 0.0
var blinks := 0


func on_physics(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0 or not enemy.can_act():
		return
	var g := game()
	if g == null:
		return
	for pl in g.players_root.get_children():
		if pl.is_targetable() and pl.global_position.distance_to(enemy.global_position) <= float(p("trigger", 56.0)):
			var away: Vector2 = (enemy.global_position - pl.global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			away = away.rotated(randf_range(-0.6, 0.6))
			var dest: Vector2 = g.nearest_floor(enemy.global_position + away * float(p("distance", 140.0)))
			Combat.instance.fx.ring.rpc(enemy.global_position, 16.0, "#ff7a2a", "")
			enemy.host_teleport(dest)
			Combat.instance.fx.ring.rpc(dest, 16.0, "#ff7a2a", "")
			Combat.instance.fx.sound.rpc("blink", dest)
			_cd = float(p("every", 5.0))
			blinks += 1
			return


func test_trigger(suite: RefCounted) -> void:
	_cd = 0.0
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(20, 0)))


func test_check(_suite: RefCounted) -> String:
	return "" if blinks > 0 else "never blinked"
