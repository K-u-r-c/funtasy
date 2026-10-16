extends BossMechanic
## Krazik P1 - Bell of Heresy: the bell tolls and a phantom copy of every hero (their look,
## tinted) attacks the party for `lifetime` s. params: every, monster (phantom_copy), lifetime (12)

var made := 0


func trigger() -> void:
	var g := game()
	Combat.instance.fx.sound.rpc("bell", boss.global_position)
	g.broadcast_message.rpc("The Bell of Heresy tolls - your companions turn on you!", "#80ff80")
	for pl in living_players():
		var pos: Vector2 = g.nearest_floor(pl.global_position + Vector2.from_angle(randf() * TAU) * 60.0)
		var e: Enemy = g.spawn_monster(str(p("monster", "phantom_copy")), pos, false, {"copy_peer": pl.peer_id, "lifetime": float(p("lifetime", 12.0))})
		if e:
			made += 1
			for other in living_players():
				if other != pl:
					e.add_threat(other, 20.0)
			e.add_threat(pl, 5.0)


func test_check(_suite: RefCounted) -> String:
	return "" if made > 0 else "no phantoms"
