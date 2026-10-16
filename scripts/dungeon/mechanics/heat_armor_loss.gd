extends FloorMechanic
## Foundry - Abyssal Heat (GDD 1.3, D35): a hero fighting in an overheated room loses armor every
## `every` s (a stacking status, up to `max` stacks); 5 s out of combat cools them down.
## params: every (10), status (heat_exhaustion), max (10), cool (5)

var _left: Dictionary = {}  ## Player -> seconds to the next stack
var _calm: Dictionary = {}  ## Player -> seconds out of combat


func physics(delta: float) -> void:
	var env := Combat.instance.env_ctx(0.0)
	for pl in game.players_root.get_children():
		if not pl.is_targetable():
			continue
		if _in_combat(pl):
			_calm[pl] = 0.0
			_left[pl] = float(_left.get(pl, float(p("every", 10.0)))) - delta
			if float(_left[pl]) <= 0.0:
				_left[pl] = float(p("every", 10.0))
				pl.status.apply(str(p("status", "heat_exhaustion")), -1.0, 0.0, env)
		else:
			_calm[pl] = float(_calm.get(pl, 0.0)) + delta
			if float(_calm[pl]) >= float(p("cool", 5.0)):
				pl.status.remove(str(p("status", "heat_exhaustion")))
				_left[pl] = float(p("every", 10.0))


## A monster that has the hero on its threat table and is close counts as a fight.
func _in_combat(pl: Node) -> bool:
	for e in game.enemies_root.get_children():
		if e is Enemy and e.is_alive() and e.aggro and e.global_position.distance_to(pl.global_position) < 360.0:
			return true
	return false


func test_trigger(suite: RefCounted) -> void:
	var e: Enemy = suite.g.spawn_monster("training_dummy", suite.g.nearest_floor(suite.p.global_position + Vector2(60, 0)), false)
	if e:
		e.add_threat(suite.p, 50.0)
		e.aggro = true
	_left[suite.p] = 0.05


func test_check(suite: RefCounted) -> String:
	return "" if suite.p.status.has(str(p("status", "heat_exhaustion"))) else "no heat stack"
