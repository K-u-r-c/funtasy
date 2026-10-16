extends BossMechanic
## Vespera P1 - Vermin Swarm: plague flies blind every player and snuff their carried torches.
## params: every, blind (3)


func trigger() -> void:
	var c := ctx()
	for pl in living_players():
		Combat.instance.apply_status(c, pl, "blind", float(p("blind", 3.0)), 0.0)
		pl.torch_left = 0.0
		pl.torch_sync = 0
		Combat.instance.fx.ring.rpc(pl.global_position, 24.0, "#404020", "")
	Combat.instance.fx.sound.rpc("swarm", boss.global_position)
	game().broadcast_message.rpc("A vermin swarm darkens the air!", "#808040")


func test_check(suite: RefCounted) -> String:
	return "" if suite.p.status.has("blind") or Array(suite.p.get_meta("test_seen_status", [])).has("blind") else "no blind"
