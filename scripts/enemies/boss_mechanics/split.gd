extends BossMechanic
## Murk Amalgam P2: tears into twin entities (data monsters, each immune to a damage family).
## The boss itself hides; when every twin is dead the boss dies. params: twins ([ids])

var twins: Array = []


func _ready() -> void:
	var g := game()
	Combat.instance.apply_status(ctx(), boss, "split_hidden", -1.0, 0.0)
	var ids: Array = p("twins", [])
	for i in ids.size():
		var pos: Vector2 = g.nearest_floor(boss.global_position + Vector2(-60 + 120 * i, 0))
		var e: Enemy = g.spawn_monster(str(ids[i]), pos, false, {"hp_mult": boss.hp_mult, "dmg_mult": boss.dmg_mult})
		if e:
			twins.append(e)
			for pl in living_players():
				e.add_threat(pl, 5.0)
	Combat.instance.fx.ring.rpc(boss.global_position, 90.0, "#7fd94a", "explosion")


func busy() -> bool:
	return true  # the hidden core does nothing


func physics(_delta: float) -> void:
	var alive := 0
	for t in twins:
		if is_instance_valid(t) and t.is_alive():
			alive += 1
	if alive == 0 and boss.is_alive():
		boss.status.remove("split_hidden")
		Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), boss, boss.health.hp + boss.health.absorb + 1.0, {"damage_type": "true"})


func stop() -> void:
	for t in twins:
		if is_instance_valid(t) and t.is_alive():
			t.queue_free()


func test_trigger(_suite: RefCounted) -> void:
	for t in twins:
		if is_instance_valid(t):
			Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), t, t.health.hp + t.health.absorb + 10.0, {"damage_type": "true"})


func test_check(_suite: RefCounted) -> String:
	var dead := not is_instance_valid(boss) or not boss.is_alive()
	return "" if twins.size() == 2 and dead else "the core still lives after its twins fell"
