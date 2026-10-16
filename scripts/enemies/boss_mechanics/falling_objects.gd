extends BossMechanic
## Debris rains from the ceiling (Morvath's sarcophagus lids): a red telegraph under every
## player, then a crushing impact that leaves the object as cover for a while.
## params: every, delay (1.5), radius (40), damage (dict), cover ("lid" obstacle kind), cover_time (8)


func trigger() -> void:
	var c := ctx()
	for pl in living_players():
		var at: Vector2 = pl.global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		var eff := {"type": "delayed", "delay": float(p("delay", 1.5)), "at": "self",
			"telegraph": {"radius": float(p("radius", 40)), "color": "#ff2020"},
			"effects": [{"type": "aoe", "radius": float(p("radius", 40)), "damage": p("damage", {"base": 10, "coef": 1.5}), "color": "#c0b090", "shake": 3}]}
		if p("cover", "") != "":
			eff.effects.append({"type": "terrain", "kind": str(p("cover", "lid")), "shape": "point", "at": "self", "lifetime": float(p("cover_time", 8.0)), "blocks": "all"})
		Combat.instance.run_effect(eff, c, at, at)
	Combat.instance.fx.sound.rpc(str(p("sfx", "lid_fall")), boss.global_position)


func test_check(_suite: RefCounted) -> String:
	return "" if not Combat.instance.delayed.is_empty() or not game().dungeon.obstacles.is_empty() else "nothing fell"
