extends FloorMechanic
## Kurgan - Blood-Cursed Earth (GDD 1.5): every slain monster leaves a pool of accursed blood for
## `duration` s. Monsters standing in it regenerate `regen` of their max health per second; heroes
## take `burn` of their weapon power per second as physical damage. params: duration (20),
## radius (36), regen (0.03), burn (0.05)

var pools: Array = []  ## [{pos, left}]
var _tick := 0.0
var burns := 0


func on_enemy_killed(e: Node) -> void:
	pools.append({"pos": e.global_position, "left": float(p("duration", 20.0))})
	Combat.instance.add_zone({"type": "zone", "radius": float(p("radius", 36.0)), "duration": float(p("duration", 20.0)), "tick": 99.0,
		"color": "#7a0a10", "light_only": true}, Combat.instance.env_ctx(0.0), e.global_position)


func physics(delta: float) -> void:
	for pl in pools.duplicate():
		pl.left -= delta
		if pl.left <= 0.0:
			pools.erase(pl)
	_tick -= delta
	if _tick > 0.0 or pools.is_empty():
		return
	_tick = 1.0
	var r := float(p("radius", 36.0))
	for pool in pools:
		for a in Combat.instance.all_actors():
			if not (a is Actor) or not a.is_targetable() or a.global_position.distance_to(pool.pos) > r:
				continue
			if a.team == Actor.Team.MONSTERS:
				Combat.instance.heal(Combat.instance.env_ctx(0.0), a, a.health.max_hp * float(p("regen", 0.03)))
			elif a is Player:
				var power: float = a.stats.power_for("melee")
				if Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, maxf(1.0, power * float(p("burn", 0.05))), {"dot": true}) > 0.0:
					burns += 1


func test_trigger(suite: RefCounted) -> void:
	var e: Enemy = suite.g.spawn_monster("training_dummy", suite.g.nearest_floor(suite.p.global_position + Vector2(10, 0)), false)
	await suite.da._wait(0.2)
	Combat.instance.deal_damage(Combat.instance.test_ctx(suite.p, {"id": "t", "school": "spell"}), e, e.health.hp + 99.0, {"damage_type": "true"})
	suite.p.iframe_left = 0.0


func test_check(suite: RefCounted) -> String:
	suite.p.iframe_left = 0.0
	return "" if not pools.is_empty() and burns > 0 else "no blood pool burn"
