extends BossMechanic
## Malazar P1 - Rune of Damnation: paints `count` demonic runes on the arena floor (armed traps);
## stepping on one sets off an arcane detonation. They fade after `lifetime` s.
## params: every (18), count (7), lifetime (14), damage (dict)

var painted := 0


func trigger() -> void:
	var room := boss_room().grow(-40.0)
	var c := ctx()
	c.damage_type = "arcane"
	for i in int(p("count", 7)):
		var at: Vector2 = game().nearest_floor(Vector2(randf_range(room.position.x, room.end.x), randf_range(room.position.y, room.end.y)))
		Combat.instance.add_zone({"type": "trap", "trigger_radius": 18, "duration": float(p("lifetime", 14.0)), "arm_time": 1.0, "color": "#a040ff",
			"effects": [{"type": "aoe", "at": "self", "radius": 56, "damage": p("damage", {"base": 8, "coef": 1.4}), "damage_type": "arcane", "color": "#a040ff", "fx": "explosion"}]}, c, at)
		painted += 1
	game().broadcast_message.rpc("Runes of Damnation burn into the floor - watch your step!", "#a040ff")


func test_check(_suite: RefCounted) -> String:
	return "" if painted > 0 else "no runes"
