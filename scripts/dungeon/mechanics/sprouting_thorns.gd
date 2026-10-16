extends FloorMechanic
## Kurgan - living thorns sprout from disturbed earth during fights: every `every` s a short
## thorn wall rises next to a hero who is in combat, blocking movement and shots for `lifetime` s.
## params: every (8), lifetime (6)

var _left := 3.0
var sprouted := 0


func physics(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = float(p("every", 8.0))
	var fighting: Array = []
	for pl in game.players_root.get_children():
		if not pl.is_targetable():
			continue
		for e in game.enemies_root.get_children():
			if e is Enemy and e.is_alive() and e.aggro and e.global_position.distance_to(pl.global_position) < 300.0:
				fighting.append(pl)
				break
	if fighting.is_empty():
		return
	var pl2: Node = fighting[randi() % fighting.size()]
	var dir := Vector2.from_angle(randf() * TAU)
	var at: Vector2 = pl2.global_position + dir * 56.0
	Combat.instance.run_effect({"type": "terrain", "kind": "thorns", "shape": "line", "at": "self", "length": 96, "across": true,
		"lifetime": float(p("lifetime", 6.0)), "blocks": "all"}, Combat.instance.env_ctx(0.0), at, at + dir)
	sprouted += 1


func test_trigger(suite: RefCounted) -> void:
	var e: Enemy = suite.g.spawn_monster("training_dummy", suite.g.nearest_floor(suite.p.global_position + Vector2(80, 0)), false)
	if e:
		e.add_threat(suite.p, 50.0)
		e.aggro = true
	_left = 0.05


func test_check(_suite: RefCounted) -> String:
	return "" if sprouted > 0 else "no thorns"
