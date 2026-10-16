extends BossMechanic
## Isolde P1 - Brood Nursery: every `every` s blood ticks hatch around her; they scurry to the
## heroes, latch onto ankles and burst after 3 s (their kamikaze fuse). params: every, count (4), monster

var hatched := 0


func trigger() -> void:
	var g := game()
	for i in int(p("count", 4)):
		var e: Enemy = g.spawn_monster(str(p("monster", "blood_tick")), g.nearest_floor(boss.global_position + Vector2.from_angle(TAU * i / float(p("count", 4))) * 40.0), false)
		if e:
			hatched += 1
			for pl in living_players():
				e.add_threat(pl, 5.0)
	Combat.instance.fx.sound.rpc("swarm", boss.global_position)


func test_check(_suite: RefCounted) -> String:
	return "" if hatched > 0 else "no ticks"
