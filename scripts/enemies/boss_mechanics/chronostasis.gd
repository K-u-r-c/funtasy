extends BossMechanic
## Memory Devourer P1 - Chronostasis Field: zones where movement, attack speed and projectile speed
## drop by 70% (a status while inside). params: every (12), count (2), radius (80), duration (8)

var made := 0


func trigger() -> void:
	var c := ctx()
	var pool := living_players()
	for i in int(p("count", 2)):
		var at: Vector2 = pool[i % pool.size()].global_position if not pool.is_empty() else boss.global_position
		Combat.instance.add_zone({"type": "zone", "radius": float(p("radius", 80)), "duration": float(p("duration", 8.0)), "tick": 0.25,
			"status_inside": "chronostasis", "color": "#80c0ff"}, c, at)
		made += 1
	game().broadcast_message.rpc("Time slows to a crawl!", "#80c0ff")


func test_check(suite: RefCounted) -> String:
	return "" if made > 0 and (suite.p.status.has("chronostasis") or Array(suite.p.get_meta("test_seen_status", [])).has("chronostasis")) else "no chronostasis"
