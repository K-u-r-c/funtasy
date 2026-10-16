extends MonsterBehavior
## Bloated Drowner: drifts toward its target; within `trigger` px it swells for `fuse` s and
## detonates (its skill: a toxic burst and a poison pool), dying in the blast.
## params: trigger (50), fuse (0.6), skill (drowner_burst)

var _fuse := -1.0
var blown := false


func on_think(_game: Node) -> bool:
	if _fuse >= 0.0:
		return true
	var t: Actor = enemy.target
	if t and is_instance_valid(t) and t.global_position.distance_to(enemy.global_position) <= float(p("trigger", 50.0)):
		_fuse = float(p("fuse", 0.6))
		set_state("swelling")
		Combat.instance.fx.telegraph.rpc(enemy.global_position, 80.0, "#7a9a3a", _fuse)
		return true
	return false


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if _fuse >= 0.0 else Vector2.INF


func on_physics(delta: float) -> void:
	if _fuse < 0.0 or blown:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_explode()


## Killed before it reached anyone: it still bursts.
func on_death() -> bool:
	if not blown:
		_explode()
	return false


func _explode() -> void:
	blown = true
	var ctx := Combat.instance.make_ctx(enemy, GameData.skill(str(p("skill", "drowner_burst"))))
	for eff in GameData.skill(str(p("skill", "drowner_burst"))).effects:
		Combat.instance.run_effect(eff, ctx, enemy.global_position, enemy.global_position)
	if enemy.is_alive():
		enemy.health.take(enemy.health.hp + enemy.health.absorb + 1.0)


func test_trigger(suite: RefCounted) -> void:
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(30, 0)))
	enemy.add_threat(suite.p, 50.0)


func test_check(_suite: RefCounted) -> String:
	return "" if blown else "did not detonate"
