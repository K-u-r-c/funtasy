extends BossMechanic
## Ignis P1 - Anvil of Doom: the boss strikes the forge and white-hot ingots fall from the
## rafters at random spots of the arena (after a telegraph), staying as cover for `cover_time` s.
## params: every, count (4), delay (1.2), cover_time (16), damage (dict)

var dropped := 0


func trigger() -> void:
	var room := boss_room().grow(-48.0)
	var c := ctx()
	boss.play_action.rpc("attack", boss.facing)
	Combat.instance.fx.sound.rpc("stomp", boss.global_position)
	game().broadcast_message.rpc("Anvil of Doom! Ingots fall from the rafters!", "#ff9a3a")
	for i in int(p("count", 4)):
		var at := Vector2(randf_range(room.position.x, room.end.x), randf_range(room.position.y, room.end.y))
		at = game().nearest_floor(at)
		Combat.instance.run_effect({"type": "delayed", "delay": float(p("delay", 1.2)), "at": "self",
			"telegraph": {"radius": 30, "color": "#ff7a2a"},
			"effects": [{"type": "aoe", "radius": 30, "damage": p("damage", {"base": 8, "coef": 1.2}), "damage_type": "fire", "color": "#ffb060", "shake": 3},
				{"type": "terrain", "kind": "ingot", "shape": "point", "at": "self", "lifetime": float(p("cover_time", 16.0)), "blocks": "all"}]}, c, at, at)
		dropped += 1


func test_check(_suite: RefCounted) -> String:
	return "" if dropped > 0 and (not Combat.instance.delayed.is_empty() or not game().dungeon.obstacles.is_empty()) else "no ingots"
