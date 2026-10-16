extends MonsterBehavior
## Skeletal Footman: when it would die it collapses into a pile of bones and stands up again
## after `delay` s with `hp` of its health - unless an area attack crushes the pile (or killed it).
## params: delay (4), hp (0.3)

var _left := -1.0


func is_pile() -> bool:
	return _left >= 0.0


func on_death() -> bool:
	if is_pile() or enemy.last_hit_area:
		return false  # crushed by an AoE: it stays dead
	_left = float(p("delay", 4.0))
	enemy.health.hp = 1.0
	enemy.casting = {}
	enemy.channel = {}
	set_state("pile")
	Combat.instance.fx.sound.rpc("bone_collapse", enemy.global_position)
	return true


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	# A pile only breaks under area attacks.
	if is_pile():
		return amount if data.get("area", false) else 0.0
	return amount


func on_think(_game: Node) -> bool:
	return is_pile()


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if is_pile() else Vector2.INF


func on_physics(delta: float) -> void:
	if not is_pile():
		return
	_left -= delta
	if _left <= 0.0:
		_left = -1.0
		enemy.health.hp = enemy.health.max_hp * float(p("hp", 0.3))
		set_state("")
		Combat.instance.fx.sound.rpc("bone_reassemble", enemy.global_position)
		Combat.instance.fx.number.rpc(enemy.global_position, "Reassembles", "info")


func test_trigger(suite: RefCounted) -> void:
	var ctx := Combat.instance.test_ctx(suite.p, GameData.skill(str(suite.p.skills[0])))
	Combat.instance.deal_damage(ctx, enemy, enemy.health.hp + 50.0, {"damage_type": "true"})
	await suite.da._wait(0.3)
	suite.da.check(is_pile() and enemy.behavior_state == "pile", "footman collapses into a bone pile")


func test_check(_suite: RefCounted) -> String:
	if is_pile():
		return "still a pile"
	return "" if enemy.is_alive() and enemy.health.fraction() > 0.25 else "did not reassemble"
