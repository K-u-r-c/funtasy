extends BossMechanic
## Vespera P1 - Vermin Swarm: plague flies blind every player (their carried torches keep
## burning, #3). params: every, blind (3)


func trigger() -> void:
	var c := ctx()
	for pl in living_players():
		Combat.instance.apply_status(c, pl, "blind", float(p("blind", 3.0)), 0.0)
		Combat.instance.fx.ring.rpc(pl.global_position, 24.0, "#404020", "")
	Combat.instance.fx.sound.rpc("swarm", boss.global_position)
	game().broadcast_message.rpc("A vermin swarm darkens the air!", "#808040")


var _torch_before := 0.0


func test_trigger(suite: RefCounted) -> void:
	suite.p.torch_left = 60.0
	_torch_before = suite.p.torch_left
	trigger()


func test_check(suite: RefCounted) -> String:
	if suite.p.torch_left <= 0.0 or suite.p.torch_left < _torch_before - 30.0:
		return "the swarm took the hero's torch"
	return "" if suite.p.status.has("blind") or Array(suite.p.get_meta("test_seen_status", [])).has("blind") else "no blind"
