extends BossMechanic
## Memory Devourer P1 - Echoes of Regret (D31): the host keeps a 10 s ring buffer of every hero's
## position and facing; every `every` s a phantom of each hero appears where they stood 10 s ago,
## walks their old path and fires a shadow echo along their old facing once a second.
## params: every (16), delay (10), replay (6), monster (echo_phantom)

var _buf: Dictionary = {}  ## Player -> [[t, pos, facing], ...]
var _t := 0.0
var _rec := 0.0
var _echoes: Array = []  ## [{node, player, start}]
var made := 0


func physics(delta: float) -> void:
	super.physics(delta)
	_t += delta
	_rec -= delta
	if _rec <= 0.0:
		_rec = 0.25
		for pl in living_players():
			var b: Array = _buf.get(pl, [])
			b.append([_t, pl.global_position, pl.facing])
			while b.size() > 0 and _t - float(b[0][0]) > float(p("delay", 10.0)) + float(p("replay", 6.0)) + 1.0:
				b.pop_front()
			_buf[pl] = b
	for ec in _echoes.duplicate():
		if not is_instance_valid(ec.node) or not ec.node.is_alive():
			_echoes.erase(ec)
			continue
		var e: Node = ec.node
		var when: float = _t - float(p("delay", 10.0))
		var rec: Array = _sample(ec.player, when)
		if rec.is_empty():
			continue
		e.host_teleport(rec[1])
		e.facing = rec[2]
		if _t - float(ec.get("shot", -9.0)) >= 1.0:
			ec.shot = _t
			Combat.instance.try_use_skill(e, "echo_bolt", e.global_position + Vector2(rec[2]) * 200.0)


func _sample(pl: Node, when: float) -> Array:
	var b: Array = _buf.get(pl, [])
	for r in b:
		if float(r[0]) >= when:
			return r
	return []


func trigger() -> void:
	var g := game()
	for pl in living_players():
		var rec := _sample(pl, _t - float(p("delay", 10.0)))
		if rec.is_empty():
			rec = [_t, pl.global_position, pl.facing]
		var e: Enemy = g.spawn_monster(str(p("monster", "echo_phantom")), rec[1], false, {"copy_peer": pl.peer_id, "lifetime": float(p("replay", 6.0))})
		if e:
			_echoes.append({"node": e, "player": pl, "shot": -9.0})
			made += 1
	g.broadcast_message.rpc("Echoes of Regret replay your past...", "#a0c0ff")


func stop() -> void:
	for ec in _echoes:
		if is_instance_valid(ec.node):
			ec.node.queue_free()
	_echoes.clear()


func test_check(_suite: RefCounted) -> String:
	return "" if made > 0 else "no echoes"
