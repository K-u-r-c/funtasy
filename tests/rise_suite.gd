class_name RiseSuite
extends RefCounted
## #49 rise-again marks (scenario "rise_lan" on a LAN pair): a Skeletal Footman knocked down into
## its bone pile shows the mark with a countdown on host and client until it stands up; a crushed
## pile loses it; a corpse a Cultist is raising shows the mark while the chant runs, on both peers,
## and loses it when the corpse rises or the chant is broken; a monster that stays dead shows none.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func mark_of(n: Node) -> Node:
	return g.rise_mark_of(n)


static func any_marks(game: Node) -> Array:
	var out: Array = []
	for n in game.entities.get_children():
		if str(n.name).begins_with("RiseMark_") and not n.is_queued_for_deletion():
			out.append(str(n.name))
	return out


func _kill(e: Actor, area := false) -> void:
	Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), e, e.health.hp + 50.0, {"damage_type": "true", "area": area})


## Asks the client whether `path` carries a mark; `want` [has, kind, min left, max left].
func _client(path: NodePath, want: Array) -> void:
	NetworkManager.to_clients("DevAuto", "client_cmd", ["rs_mark", [String(path), want]])
	await da._wait(0.4)


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	for e in g.enemies_root.get_children():
		e.queue_free()
	for pl in [p, c]:
		pl.iframe_left = 9999.0
	var start: Vector2 = g.layout.start
	p.host_teleport(start)
	c.host_teleport(g.nearest_floor(start + Vector2(-40, 0)))
	p.host_take_torch()
	await da._wait(0.6)
	# The footman's bone pile.
	var f: Enemy = g.spawn_monster("skeletal_footman", g.nearest_floor(start + Vector2(60, 10)), false)
	await da._wait(0.6)
	var delay := 4.0
	for b in f.def.get("behaviors", []):
		if str(b.get("id", "")) == "reassemble":
			delay = float(b.get("delay", 4.0))
	_kill(f)
	await da._wait(0.3)
	var m := mark_of(f)
	da.check(f.behavior_state == "pile" and m != null and m.kind == "reassemble" and absf(m.left() - (delay - 0.3)) < 0.4,
			"host: the footman's bone pile shows the rise mark counting down (%.1f s of %.1f)" % [m.left() if m else -1.0, delay])
	await _client(f.get_path(), [true, "reassemble", delay - 1.2, delay - 0.3])
	await da._wait(1.5)
	await _client(f.get_path(), [true, "reassemble", delay - 2.7, delay - 1.7])
	await da._wait_until(func(): return f.behavior_state == "", delay + 1.0)
	await da._wait(0.3)
	da.check(f.is_alive() and mark_of(f) == null and g._rise_marks.is_empty(), "host: the mark goes when the footman stands up")
	await _client(f.get_path(), [false])
	# Crushed by an area attack: it stays dead, the mark goes.
	_kill(f)
	await da._wait(0.3)
	da.check(mark_of(f) != null, "host: knocked down again, the mark is back")
	_kill(f, true)
	await da._wait(0.5)
	da.check(not is_instance_valid(f) and g._rise_marks.is_empty(), "host: a pile crushed by an area attack stays dead and loses its mark")
	await _client(NodePath(), [false])
	# The cultist raising a fallen skeleton archer.
	var cu: Enemy = g.spawn_monster("cultist", g.nearest_floor(start + Vector2(90, -20)), false)
	var arch: Enemy = g.spawn_monster("skeleton_archer", g.nearest_floor(start + Vector2(70, 30)), false)
	await da._wait(0.6)
	_kill(arch)
	await da._wait(0.4)
	var res: Variant = null
	for b in cu.behaviors:
		if b.has_method("_stop_chant"):
			res = b
	res._left = 0.0
	var chanting: bool = await da._wait_until(func(): return cu.behavior_state == "chanting", 3.0)
	await da._wait(0.2)
	var corpse: Node = g.corpse_node(int(res._corpse.get("id", -1))) if chanting else null
	da.check(chanting and corpse != null and mark_of(corpse) != null and mark_of(corpse).kind == "raise",
			"host: the corpse a cultist is raising shows the rise mark")
	if corpse:
		await _client(corpse.get_path(), [true, "raise", 0.3, 2.0])
	await da._wait_until(func(): return cu.behavior_state == "", 4.0)
	await da._wait(0.4)
	var raised := 0
	for e in g.enemies_root.get_children():
		raised += 1 if e.has_meta("raised") else 0
	da.check(raised == 1 and any_marks(g).is_empty() and g._rise_marks.is_empty(), "host: the archer rose and no mark is left (%s)" % [any_marks(g)])
	await _client(NodePath(), [false])
	# A broken chant: the cultist is stunned mid-chant.
	var arch2: Enemy = g.spawn_monster("skeleton_archer", g.nearest_floor(start + Vector2(110, 30)), false)
	await da._wait(0.5)
	_kill(arch2)
	await da._wait(0.4)
	res._left = 0.0
	await da._wait_until(func(): return cu.behavior_state == "chanting", 3.0)
	await da._wait(0.3)
	da.check(not any_marks(g).is_empty(), "host: a second chant marks its corpse")
	cu.status.apply("stun", 2.0, 0.0, null)
	await da._wait(0.4)
	da.check(any_marks(g).is_empty() and g._rise_marks.is_empty(), "host: a broken chant takes the mark away")
	await _client(NodePath(), [false])
	# A monster that stays dead.
	var gh: Enemy = g.spawn_monster("ghoul", g.nearest_floor(start + Vector2(60, -30)), false)
	await da._wait(0.5)
	_kill(gh)
	await da._wait(0.6)
	da.check(any_marks(g).is_empty(), "host: a ghoul that stays dead shows no mark")
	await _client(NodePath(), [false])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"rs_mark":
			var path := NodePath(str(arg[0]))
			var want: Array = arg[1]
			if path.is_empty():
				da.check(any_marks(g).is_empty(), "client: no rise mark anywhere (%s)" % [any_marks(g)])
				return
			var m := mark_of(da.get_node_or_null(path))
			if bool(want[0]):
				da.check(m != null and m.kind == str(want[1]) and m.left() >= float(want[2]) and m.left() <= float(want[3]),
						"client: %s shows the %s mark, %.1f s left (want %.1f-%.1f)" % [path.get_name(path.get_name_count() - 1), want[1], m.left() if m else -1.0, want[2], want[3]])
			else:
				da.check(m == null, "client: %s has no mark" % path.get_name(path.get_name_count() - 1))
