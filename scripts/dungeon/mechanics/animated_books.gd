extends FloorMechanic
## Archives - Arcane Instability (GDD 1.4): when furniture breaks, the books on bookshelves within
## `radius` px come alive - each shelf either fires a volley of rune bolts at the nearest hero or
## bursts in an arcane explosion. params: radius (120)

var woke := 0


func on_prop_broken(prop: Node) -> void:
	for pr in game.dungeon.props.values():
		if not is_instance_valid(pr) or pr == prop or str(pr.get("type")) != "bookshelf" or not pr.destructible():
			continue
		if pr.global_position.distance_to(prop.global_position) > float(p("radius", 120.0)):
			continue
		woke += 1
		var ctx := Combat.instance.env_ctx(0.0)
		ctx.damage_type = "arcane"
		if randf() < 0.5:
			var t: Node = null
			var best := 320.0
			for pl in game.players_root.get_children():
				if pl.is_targetable() and pl.global_position.distance_to(pr.global_position) < best:
					best = pl.global_position.distance_to(pr.global_position)
					t = pl
			if t:
				for i in 3:
					var dir: Vector2 = (t.global_position - pr.global_position).normalized().rotated(deg_to_rad(-15 + 15 * i))
					Combat.instance.spawn_projectile({"sprite": "magic", "speed": 260, "range": 320, "radius": 6, "light": "#8855ff", "damage": {"base": 5, "coef": 0}},
						ctx, pr.global_position + Vector2(0, -16), dir)
		else:
			Combat.instance.apply_aoe({"type": "aoe", "radius": 60, "damage": {"base": 9, "coef": 0}, "damage_type": "arcane", "color": "#8855ff", "fx": "explosion"}, ctx, pr.global_position)
		Combat.instance.fx.sound.rpc("book_burst", pr.global_position)


func test_trigger(suite: RefCounted) -> void:
	var at: Vector2 = suite.p.global_position + Vector2(60, 0)
	game.dungeon.spawn_prop.rpc("TestShelf", "bookshelf", game.nearest_floor(at))
	game.dungeon.spawn_prop.rpc("TestCrateB", "crate", game.nearest_floor(at + Vector2(0, 40)))
	await suite.da._wait(0.2)
	var crate: Node = game.dungeon.props.get("TestCrateB")
	if crate:
		crate.take_damage(999.0, Combat.instance.test_ctx(suite.p, {"id": "t", "school": "melee"}))


func test_check(_suite: RefCounted) -> String:
	return "" if woke > 0 else "books stayed asleep"
