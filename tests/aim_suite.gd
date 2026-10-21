class_name AimSuite
extends RefCounted
## #83 aiming at the cursor (scenario "aim" solo, "aim_lan" on a LAN pair). Shots and beams are
## drawn at chest height (CombatFx.HEIGHT), so a mouse aim takes the ground point under the
## cursor: every hero shot / beam then flies through the cursor in all 8 directions and at every
## distance; each class's primary attack hits a training dummy whose body is under the cursor
## (the shot passed 16 px over its feet before); areas land on the cursor itself; the stick and
## the harness's ground aim are unchanged; a client's shot keeps the direction it aimed although
## the host's copy of the hero trails it (_lag_aim), and the client's primary hits the dummy under
## its cursor through the real input path.

var da: Node
var g: Node
var p: Player

const BODY := Vector2(0, -18)  ## where a player points at a 64 px hero or monster: its middle
const DIRS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1), Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)]


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Hero skills whose shot or beam flies from the hero toward the aim (not lobbed).
static func flying_skills() -> Array:
	var out: Array = []
	for sid in GameData.skills:
		if not str(sid).split("_")[0] in ["warrior", "ranger", "mage", "priest"]:
			continue
		var shape := SkillShape.of(GameData.skills[sid])
		if str(shape.kind) in ["projectile", "line"] and not shape.get("lob", false):
			out.append(sid)
	return out


func _primaries() -> Array:
	var out: Array = []
	for c in ["warrior", "ranger", "mage", "priest"]:
		out.append(str(GameData.classes[c].primary_attack))
	return out


## The open floor nearest the hero with plain stone `dist` px around it in all 8 directions (no
## walls, water or secure rooms in the way); props there are cleared (host).
func _open_spot(dist: float) -> Vector2:
	var d: Node = g.dungeon
	var best := p.global_position
	var best_d := INF
	for y in d.size.y:
		for x in d.size.x:
			var c: Vector2 = d.cell_center(Vector2i(x, y))
			if d.cell_at(Vector2i(x, y)) != DungeonGenerator.CELL_FLOOR or d.is_safe(c) or c.distance_to(p.global_position) >= best_d:
				continue
			var open := true
			for dir in DIRS:
				var t := 0.0
				while open and t <= dist + 24.0:
					open = d.cell_at(d.cell_of(c + Vector2(dir).normalized() * t)) == DungeonGenerator.CELL_FLOOR
					t += 8.0
				if not open:
					break
			if open:
				best = c
				best_d = c.distance_to(p.global_position)
	# Barrels and tables stop shots: clear them around the spot (host).
	if da.multiplayer.is_server():
		for pr in d.props_in_radius(best, dist + 40.0):
			var key: Variant = d.props.find_key(pr)
			if key != null:
				d.remove_prop_quietly(str(key))
	return best


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.auto_aim = Vector2.INF
	# Geometry: every flying hero skill, 8 directions, 3 distances: the drawn path (chest height)
	# passes through the cursor.
	var bad: Array = []
	var n := 0
	for sid in flying_skills():
		p.skills[1] = sid
		for d in DIRS:
			for dist in [40.0, 120.0, 260.0]:
				var cursor: Vector2 = p.global_position + Vector2(d).normalized() * dist
				p.auto_cursor = cursor
				p._update_aim(Vector2.ZERO)
				var aim := p._cast_aim(1)
				var a: Vector2 = p.global_position + CombatFx.HEIGHT
				var dir := (aim - p.global_position).normalized()
				var off := absf(dir.orthogonal().dot(cursor - a))
				var ahead := dir.dot(cursor - a) > 0.0
				n += 1
				if off > 0.5 or not ahead:
					bad.append("%s %s %.0f: %.1f px" % [sid, d, dist, off])
	da.check(n > 100 and bad.is_empty(), "%d flying-skill aims: every shot's drawn path passes through the cursor (%s)" % [n, bad.slice(0, 5)])
	# Areas land on the cursor itself; the stick / harness ground aim is untouched.
	var area := ""
	for sid in GameData.skills:
		if str(sid).begins_with("mage_") and str(SkillShape.of(GameData.skills[sid]).kind) == "area":
			area = sid
			break
	p.skills[1] = area
	p.auto_cursor = p.global_position + Vector2(100, 30)
	p._update_aim(Vector2.ZERO)
	da.check(not area.is_empty() and p._cast_aim(1).is_equal_approx(p.auto_cursor), "an area skill (%s) lands on the cursor itself" % area)
	p.skills[1] = "mage_bolt"
	p.auto_cursor = Vector2.INF
	p.auto_aim = p.global_position + Vector2(100, 30)
	p._update_aim(Vector2.ZERO)
	da.check(not p.mouse_aim and p._cast_aim(1).is_equal_approx(p.auto_aim), "a ground aim (stick / harness) is used as it is")
	p.auto_aim = Vector2.INF
	# The host keeps a client's aimed direction when its copy of the hero trails the client.
	var from := p.global_position + Vector2(-12, 5)
	var aim2 := p.global_position + Vector2(150, -40)
	var lag := p._lag_aim(p.skills[1], aim2, from)
	da.check((lag - p.global_position).normalized().is_equal_approx((aim2 - from).normalized()), "a client's shot keeps the direction it aimed from where it stood")
	da.check(p._lag_aim(area, aim2, from).is_equal_approx(aim2), "an area keeps its point")
	da.check(p._lag_aim(p.skills[1], aim2, p.global_position + Vector2(400, 0)).is_equal_approx(aim2), "a gap too big for lag is ignored")
	# End to end: each class's primary hits a dummy whose body is under the cursor, in 8 directions.
	var spot := _open_spot(110.0)
	p.host_teleport(spot)
	await da._wait(0.5)
	for sid in _primaries():
		var reach := 30.0 if str(SkillShape.of(GameData.skill(sid)).kind) in ["melee", "cone"] else 110.0
		var hits := await shoot_ring(sid, reach)
		da.check(hits >= DIRS.size() - 1, "%s hits the dummy under the cursor in %d of %d directions" % [sid, hits, DIRS.size()])
	p.auto_cursor = Vector2.INF
	da.log_line("aim: done")


## Owner: fire `sid` (as the primary, through the input path) at a training dummy whose body is
## under the cursor, in each of the 8 directions at `reach` px; returns how many were hit.
func shoot_ring(sid: String, reach: float) -> int:
	var prim: Variant = p.skills[0]
	p.skills[0] = sid
	var hits := 0
	for d in DIRS:
		var at: Vector2 = p.global_position + Vector2(d).normalized() * reach
		var name := await _spawn_dummy(at)
		var dummy: Actor = g.enemies_root.get_node_or_null(name)
		if dummy == null:
			continue
		var hp0: float = dummy.health.hp
		p.resource.value = p.resource.max_value
		p.local_cd.clear()
		p._pending.clear()
		# The cursor on the dummy's body (its middle, as a player would point).
		p.auto_cursor = dummy.global_position + BODY
		await da.get_tree().physics_frame
		await da.get_tree().physics_frame
		Input.action_press("attack")
		await da._wait(0.25)
		Input.action_release("attack")
		var ok: bool = await da._wait_until(func(): return not is_instance_valid(dummy) or dummy.health.hp < hp0, 1.5)
		if ok:
			hits += 1
		else:
			da.log_line("%s missed toward %s" % [sid, d])
		await _kill_dummy(name)
		await da._wait(0.3)
	p.skills[0] = prim
	return hits


func _spawn_dummy(at: Vector2) -> String:
	if da.multiplayer.is_server():
		var e: Node = g.spawn_monster("training_dummy", at, false)
		await da._wait(0.3)
		return str(e.name)
	return ""


func _kill_dummy(name: String) -> void:
	if da.multiplayer.is_server():
		var e: Node = g.enemies_root.get_node_or_null(name)
		if e:
			e.queue_free()
	await da.get_tree().physics_frame


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	p.iframe_left = 9999.0
	c.iframe_left = 9999.0
	p = c
	var spot := _open_spot(110.0)
	p = da._local()
	c.host_teleport(spot)
	p.host_teleport(g.nearest_floor(spot + Vector2(0, 160)))
	await da._wait(1.5)
	# Dummies around the client, one at a time; the client points its cursor at each body and
	# attacks with its own primary through the input path; the host counts the hits.
	var hits := 0
	for d in DIRS:
		var at: Vector2 = c.global_position + Vector2(d).normalized() * 110.0
		var e: Actor = g.spawn_monster("training_dummy", at, false)
		await da._wait(0.5)
		var hp0: float = e.health.hp
		NetworkManager.to_clients("DevAuto", "client_cmd", ["aim_shoot", e.global_position])
		var ok: bool = await da._wait_until(func(): return not is_instance_valid(e) or e.health.hp < hp0, 3.0)
		if ok:
			hits += 1
		else:
			da.log_line("client missed toward %s (client at %s, dummy at %s)" % [d, c.global_position, e.global_position if is_instance_valid(e) else Vector2.ZERO])
		if is_instance_valid(e):
			e.queue_free()
		await da._wait(0.5)
	da.check(hits >= DIRS.size() - 1, "the client's primary hits the dummy under its cursor in %d of %d directions" % [hits, DIRS.size()])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["aim_stop", null])
	await da._wait(0.5)


func client_cmd(cmd: String, arg: Variant) -> void:
	p = da._local()
	match cmd:
		"aim_shoot":
			p.iframe_left = 9999.0
			p.resource.value = p.resource.max_value
			p.auto_aim = Vector2.INF
			p.auto_cursor = Vector2(arg) + BODY
			await da._wait(0.2)
			p.local_cd.clear()
			p._pending.clear()
			Input.action_press("attack")
			await da._wait(0.3)
			Input.action_release("attack")
			da.log_line("client shot at %s from %s (aim %s, cd %s)" % [arg, p.global_position, p._cast_aim(0), p.local_cd])
		"aim_stop":
			p.auto_cursor = Vector2.INF
			Input.action_release("attack")
