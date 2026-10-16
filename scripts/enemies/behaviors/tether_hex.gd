extends MonsterBehavior
## Cursed Scribe: every `every` s binds the two nearest heroes with an astral tether; while it
## holds (`duration` s) both lose Intellect and Strength (a stacking status every 2 s).
## params: every (14), duration (8), status (anguish)

var _left := 3.0
var _hold := -1.0
var _tick := 0.0
var bound: Array = []
var _tid := -1


func on_think(g: Node) -> bool:
	_left -= float(GameData.bal("ai.think_interval"))
	if _left > 0.0 or _hold > 0.0 or enemy.target == null:
		return false
	var pool: Array = g.players_root.get_children().filter(func(pl): return pl.is_targetable() and pl.global_position.distance_to(enemy.global_position) < 360.0)
	if pool.is_empty():
		return false
	pool.sort_custom(func(a, b): return a.global_position.distance_to(enemy.global_position) < b.global_position.distance_to(enemy.global_position))
	bound = pool.slice(0, 2)
	if bound.size() == 2:
		_tid = Combat.instance.new_id()
		Combat.instance.fx.tether.rpc(_tid, bound[0].get_path(), bound[1].get_path(), "#c03060")
	_left = float(p("every", 14.0))
	_hold = float(p("duration", 8.0))
	_tick = 0.0
	enemy.play_action.rpc("cast", enemy.facing)
	return true


func on_physics(delta: float) -> void:
	if _hold <= 0.0:
		return
	_hold -= delta
	if _hold <= 0.0 and _tid >= 0:
		Combat.instance.fx.tether_end.rpc(_tid)
		_tid = -1
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 2.0
	var ctx := Combat.instance.make_ctx(enemy, {"id": "anguish", "school": "spell"})
	for pl in bound:
		if is_instance_valid(pl) and pl.is_targetable():
			Combat.instance.apply_status(ctx, pl, str(p("status", "anguish")), float(p("duration", 8.0)) + 4.0, 0.0)
			Combat.instance.fx.beam.rpc(enemy.global_position, pl.global_position, "#c03060", 0.3, "")


func on_death() -> bool:
	if _tid >= 0:
		Combat.instance.fx.tether_end.rpc(_tid)
		_tid = -1
	return false


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	enemy.add_threat(suite.p, 10.0)


func test_check(suite: RefCounted) -> String:
	return "" if suite.p.status.has(str(p("status", "anguish"))) or Array(suite.p.get_meta("test_seen_status", [])).has(str(p("status", "anguish"))) or bound.has(suite.p) else "nobody bound"
