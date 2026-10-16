extends FloorMechanic
## Sewers - Sewer Rot & Sludge Drag (GDD 1.2): heroes wading through sewage (shallow water or deep
## sludge) are slowed by 25% unless their boots are sludge-proof (`terrain_immune`); deep sludge
## stacks Blighted Taint (-5% healing received, max 10) once a second; 3 s on dry stone cleanses it.
## params: slow (status id), taint (status id), dry_time (3)

var _tick := 0.0
var _dry: Dictionary = {}  ## Player -> seconds on dry stone


func physics(delta: float) -> void:
	_tick -= delta
	var second := _tick <= 0.0
	if second:
		_tick = 1.0
	var env := Combat.instance.env_ctx(0.0)
	for pl in game.players_root.get_children():
		if not pl.is_targetable():
			continue
		var kind: int = game.dungeon.cell_at(game.dungeon.cell_of(pl.global_position))
		var wet := kind == DungeonGenerator.CELL_WATER or kind == DungeonGenerator.CELL_SLUDGE
		if wet and not pl.stats.has_flag("terrain_immune"):
			if not pl.status.has(str(p("slow", "sewage_slow"))):
				pl.status.apply(str(p("slow", "sewage_slow")), -1.0, 0.0, env)
		else:
			pl.status.remove(str(p("slow", "sewage_slow")))
		if kind == DungeonGenerator.CELL_SLUDGE:
			_dry[pl] = 0.0
			if second:
				pl.status.apply(str(p("taint", "blighted_taint")), -1.0, 0.0, env)
		elif not wet:
			_dry[pl] = float(_dry.get(pl, 0.0)) + delta
			if float(_dry[pl]) >= float(p("dry_time", 3.0)) and pl.status.has(str(p("taint", "blighted_taint"))):
				pl.status.remove(str(p("taint", "blighted_taint")))


var _phase := 0


func test_trigger(suite: RefCounted) -> void:
	var sludge: Vector2 = suite.find_spot(func(pos: Vector2) -> bool: return game.dungeon.cell_at(game.dungeon.cell_of(pos)) == DungeonGenerator.CELL_SLUDGE)
	var c: Vector2i = game.dungeon.cell_of(sludge)
	if game.dungeon.cell_at(c) != DungeonGenerator.CELL_SLUDGE:
		# This floor rolled no deep sludge: the test pours some under the hero (host grid only).
		c = game.dungeon.cell_of(suite.p.global_position)
		game.dungeon.cells[c.y * game.dungeon.size.x + c.x] = DungeonGenerator.CELL_SLUDGE
		sludge = game.dungeon.cell_center(c)
	suite.p.host_teleport(sludge)
	_phase = 0


func test_check(suite: RefCounted) -> String:
	var pl: Player = suite.p
	if _phase == 0:
		if not (pl.status.has(str(p("taint", "blighted_taint"))) and pl.status.has(str(p("slow", "sewage_slow")))):
			return "no taint / slow in sludge"
		var dry: Vector2 = suite.find_spot(func(pos: Vector2) -> bool:
			var c: Vector2i = game.dungeon.cell_of(pos)
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					if game.dungeon.cell_at(c + Vector2i(dx, dy)) != DungeonGenerator.CELL_FLOOR:
						return false
			return true)
		pl.host_teleport(dry)
		_phase = 1
		return "drying"
	return "" if not pl.status.has(str(p("taint", "blighted_taint"))) and not pl.status.has(str(p("slow", "sewage_slow"))) else "taint stays on dry stone"
