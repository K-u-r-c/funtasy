class_name WallSuite
extends RefCounted
## #98 summoned walls fall after one hit (scenario "walls" solo, "walls_lan" on a LAN pair): every
## breakable kind (stakes, thorns, briar, bone spears) is brought down by one hit of every class's
## primary attack (swings and shots), drawn with its art (no placeholder spikes); cover (the
## sarcophagus lid, the ingots) and flames stand; a monster's hit never breaks a wall; the
## Rotwood Treant's real Stake Line falls to one hit; on LAN the client's swing brings a wall down
## on the host and the client sees it gone.

var da: Node
var g: Node
var p: Player

const BREAKABLE := ["stakes", "thorns", "briar", "bone_spears"]
const STANDING := ["lid", "ingot", "fire_wall"]


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _primaries() -> Array:
	var out: Array = []
	for c in ["warrior", "ranger", "mage", "priest"]:
		out.append(str(GameData.classes[c].primary_attack))
	return out


## An open floor cell near the hero with plain floor 3 cells to its right; the hero stands there.
func _spot() -> Vector2:
	var d: Node = g.dungeon
	var best := p.global_position
	var best_d := INF
	for y in d.size.y:
		for x in d.size.x:
			var ok := true
			for k in range(-1, 5):
				for dy in [-1, 0, 1]:
					ok = ok and d.cell_at(Vector2i(x + k, y + dy)) == DungeonGenerator.CELL_FLOOR
			var c: Vector2 = d.cell_center(Vector2i(x, y))
			if ok and not d.is_safe(c) and c.distance_to(p.global_position) < best_d:
				best = c
				best_d = c.distance_to(p.global_position)
	for pr in d.props_in_radius(best, 160.0):
		var key: Variant = d.props.find_key(pr)
		if key != null:
			d.remove_prop_quietly(str(key))
	return best


## Host: raise a wall of `kind` on the cell `cells` tiles right of the hero; its id.
func _wall(kind: String, cells: int, blocks: String) -> int:
	var id: int = Combat.instance.new_id()
	var c: Vector2i = g.dungeon.cell_of(p.global_position) + Vector2i(cells, 0)
	g.dungeon.add_obstacle.rpc(id, kind, [c], 30.0, blocks)
	return id


## Owner: one primary attack (`sid`) at the wall `cells` tiles to the right.
func _hit(sid: String, cells: int) -> void:
	p.skills[0] = sid
	p.cooldowns.clear()
	p.local_cd.clear()
	p.impact_pending = {}
	var at: Vector2 = g.dungeon.cell_center(g.dungeon.cell_of(p.global_position) + Vector2i(cells, 0))
	p.request_skill.rpc_id(1, 0, at, 0)
	await da._wait(0.7)


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.host_teleport(_spot())
	await da._wait(0.5)
	var prim: Variant = p.skills[0]
	var bad: Array = []
	var art: Array = []
	for kind in BREAKABLE:
		for sid in _primaries():
			var ranged: bool = str(SkillShape.of(GameData.skill(sid)).kind) == "projectile"
			var cells := 3 if ranged else 1
			var id := _wall(kind, cells, "all" if kind == "briar" else "movement")
			await da._wait(0.2)
			var o: Dictionary = g.dungeon.obstacles.get(id, {})
			if not o.is_empty() and o.node.get_children().filter(func(n): return n is Sprite2D).is_empty():
				art.append(kind)
			await _hit(sid, cells)
			if g.dungeon.obstacles.has(id):
				bad.append("%s by %s" % [kind, sid])
				g.dungeon.remove_obstacle(id)
	da.check(bad.is_empty(), "every breakable wall falls to one hit of every class's primary attack (standing: %s)" % [bad])
	da.check(art.is_empty(), "the walls are drawn with their art, not the placeholder spikes (%s)" % [art])
	# Cover and flames stand; a monster's hit breaks nothing.
	var stood: Array = []
	for kind2 in STANDING:
		var id2 := _wall(kind2, 1, "all" if kind2 != "fire_wall" else "movement")
		await _hit("warrior_strike", 1)
		if g.dungeon.obstacles.has(id2):
			stood.append(kind2)
			g.dungeon.remove_obstacle(id2)
	da.check(stood.size() == STANDING.size(), "cover (lid, ingots) and flames stand after a hit (%s)" % [stood])
	var id3 := _wall("stakes", 1, "movement")
	await da._wait(0.2)
	var mctx := Combat.instance.make_ctx(p, {"id": "t", "school": "melee"})
	mctx.team = Actor.Team.MONSTERS
	var n: int = Combat.instance.break_walls(mctx, p.global_position, 80.0)
	da.check(n == 0 and g.dungeon.obstacles.has(id3), "a monster's hit doesn't break a wall")
	g.dungeon.remove_obstacle(id3)
	# The Rotwood Treant's real Stake Line, then one swing.
	var tr: Enemy = g.spawn_monster("rotwood_treant", g.nearest_floor(p.global_position + Vector2(140, 0)), false)
	await da._wait(0.3)
	var before: int = g.dungeon.obstacles.size()
	var err := ""
	for k in 8:
		tr.cooldowns.clear()
		err = Combat.instance.try_use_skill(tr, "treant_stakes", p.global_position)
		if err.is_empty():
			break
		await da._wait(0.3)
	await da._wait_until(func(): return g.dungeon.obstacles.size() > before, 3.0)
	da.log_line("treant stakes: '%s'" % err)
	var made: Array = g.dungeon.obstacles.keys().filter(func(k): return str(g.dungeon.obstacles[k].kind) == "stakes")
	if is_instance_valid(tr):
		tr.queue_free()
	if made.is_empty():
		da.check(false, "the treant raises its stakes")
	else:
		var sid := int(made[0])
		var cells: Array = g.dungeon.obstacles[sid].cells
		var near: Vector2 = g.dungeon.cell_center(cells[0])
		for c in cells:
			if g.dungeon.cell_center(c).distance_to(p.global_position) < near.distance_to(p.global_position):
				near = g.dungeon.cell_center(c)
		p.host_teleport(g.nearest_floor(near + (p.global_position - near).normalized() * 30.0))
		await da._wait(0.3)
		p.skills[0] = "warrior_strike"
		p.cooldowns.clear()
		p.request_skill.rpc_id(1, 0, near, 0)
		await da._wait(0.7)
		da.check(not g.dungeon.obstacles.has(sid), "the Rotwood Treant's Stake Line (%d cells) falls to one swing" % cells.size())
	p.skills[0] = prim


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	var host_p := p
	p = c
	var spot := _spot()
	p = host_p
	c.host_teleport(spot)
	p.host_teleport(g.nearest_floor(spot + Vector2(0, 120)))
	await da._wait(1.0)
	var id: int = Combat.instance.new_id()
	g.dungeon.add_obstacle.rpc(id, "thorns", [g.dungeon.cell_of(c.global_position) + Vector2i(1, 0)], 30.0, "movement")
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["wl_hit", id])
	await da._wait_until(func(): return not g.dungeon.obstacles.has(id), 4.0)
	da.check(not g.dungeon.obstacles.has(id), "host: the client's swing brought the thorns down")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["wl_gone", id])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"wl_hit":
			da.check(g.dungeon.obstacles.has(int(arg)), "client: the thorns stand on my floor too")
			p.iframe_left = 9999.0
			var at: Vector2 = g.dungeon.cell_center(g.dungeon.cell_of(p.global_position) + Vector2i(1, 0))
			p.auto_aim = at
			await da._wait(0.2)
			p.local_cd.clear()
			p._pending.clear()
			Input.action_press("attack")
			await da._wait(0.4)
			Input.action_release("attack")
			p.auto_aim = Vector2.INF
		"wl_gone":
			da.check(not g.dungeon.obstacles.has(int(arg)), "client: the thorns are gone on my screen too")
