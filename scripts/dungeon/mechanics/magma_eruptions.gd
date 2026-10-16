extends FloorMechanic
## Foundry - Magma Geysers (GDD 1.3): every 6-10 s a molten channel near a hero erupts, lobbing
## globs that set the floor on fire for 5 s. params: every ([6, 10]), globs (3), radius (34)

var _left := 4.0
var erupted := 0


func physics(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	var span: Array = p("every", [6, 10])
	_left = randf_range(float(span[0]), float(span[1]))
	var d: Node = game.dungeon
	for pl in game.players_root.get_children():
		if not pl.is_targetable():
			continue
		var src := _lava_near(pl.global_position, 8)
		if src == Vector2.INF:
			continue
		var ctx := Combat.instance.env_ctx(0.0)
		ctx.damage_type = "fire"
		for i in int(p("globs", 3)):
			var at: Vector2 = game.nearest_floor(src.lerp(pl.global_position, randf_range(0.3, 1.0)) + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
			Combat.instance.run_effect({"type": "delayed", "delay": 1.0 + i * 0.25, "at": "self", "telegraph": {"radius": float(p("radius", 34)), "color": "#ff5511"},
				"effects": [{"type": "aoe", "radius": float(p("radius", 34)), "damage": {"base": 8, "coef": 0}, "damage_type": "fire", "color": "#ff7a2a"},
					{"type": "zone", "radius": float(p("radius", 34)) - 4.0, "duration": 5.0, "tick": 1.0, "damage": {"base": 3, "coef": 0}, "damage_type": "fire", "color": "#ff5511"}]},
				ctx, at, at)
		erupted += 1
		break


func _lava_near(pos: Vector2, r: int) -> Vector2:
	var d: Node = game.dungeon
	var c: Vector2i = d.cell_of(pos)
	for k in range(1, r + 1):
		for dx in range(-k, k + 1):
			for dy in range(-k, k + 1):
				if absi(dx) != k and absi(dy) != k:
					continue
				if d.cell_at(c + Vector2i(dx, dy)) == DungeonGenerator.CELL_LAVA:
					return d.cell_center(c + Vector2i(dx, dy))
	return Vector2.INF


func test_trigger(suite: RefCounted) -> void:
	var lava: Vector2 = suite.find_spot(func(pos: Vector2) -> bool: return _lava_near(pos, 4) != Vector2.INF and game.dungeon.cell_at(game.dungeon.cell_of(pos)) == DungeonGenerator.CELL_FLOOR)
	suite.p.host_teleport(lava)
	_left = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if erupted > 0 else "no eruption"
