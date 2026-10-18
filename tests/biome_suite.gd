class_name BiomeSuite
extends RefCounted
## Headless biome checks (scenario "biomes", solo host). For every floor type (or --biome=<id>):
## generated layouts over several seeds are connected and carry the biome's hazards, the boss
## pick covers the whole boss list, and the floor's monsters / props come from the biome's data.
## On the live floor (the run's first floor type) the hazards hurt and every floor mechanic runs
## its own test_trigger / test_check.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run(biome: String = "") -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var ids: Array = GameData.floor_types.keys()
	ids.sort()
	for id in ids:
		if biome.is_empty() or id == biome:
			check_layouts(str(id))
			leaf_rules(str(id))
	await check_live_floor()


## #23 / #30 / #31 over many seeds, read from the carved grid (not the generator's intentions):
## the boss chamber is the room farthest from the start along the room graph and a dead end with
## one opening, its one door is the boss door on a top / bottom wall; the merchant room likewise
## has one opening and one merchant door; nothing else leaks into either.
func leaf_rules(fid: String, seeds: int = 150) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var bad := ""
	var t0 := Time.get_ticks_msec()
	for i in seeds:
		var seed_value := 31337 + i * 7919
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1 + i % 8)
		var why := _leaf_problem(lay)
		if not why.is_empty():
			bad = "seed %d: %s" % [seed_value, why]
			break
	da.check(bad.is_empty(), "%s: over %d seeds the boss chamber is the graph-farthest dead end with one boss door and the merchant room has one merchant door (%d ms)%s" % [fid, seeds, Time.get_ticks_msec() - t0, "" if bad.is_empty() else ": " + bad])


func _leaf_problem(lay: Dictionary) -> String:
	var adj: Array = DungeonGenerator.room_graph(lay.cells, lay.size, lay.rooms)
	var hops: Dictionary = DungeonGenerator.room_hops(adj, 0)
	var boss := int(lay.boss_room)
	for i in lay.rooms.size():
		if lay.rooms[i].role != "prison" and not hops.has(i):
			return "room %d (%s) unreachable" % [i, lay.rooms[i].role]
	for i in lay.rooms.size():
		if i != boss and lay.rooms[i].role != "prison" and int(hops[i]) >= int(hops[boss]):
			return "room %d (%s) is %d steps away, the boss %d" % [i, lay.rooms[i].role, hops[i], hops[boss]]
	for pair in [[boss, "boss"], [int(lay.merchant.get("room", -1)), "merchant"]]:
		var ri: int = pair[0]
		if ri < 0:
			return "no %s room" % pair[1]
		var rect: Rect2i = lay.rooms[ri].rect
		var openings := DungeonGenerator.room_openings(lay.cells, lay.size, rect)
		if openings != 1 or adj[ri].size() != 1:
			return "%s room has %d openings, %d neighbours" % [pair[1], openings, adj[ri].size()]
		var doors: Array = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(rect.grow(1)))
		if doors.size() != 1 or str(doors[0].kind) != pair[1] or doors[0].vertical:
			return "%s room doors: %s" % [pair[1], doors.map(func(d): return [d.kind, d.vertical])]
		# Sealed: with its door shut nothing reaches the room.
		var shut := {}
		for c in doors[0].cells:
			shut[c] = true
		var reach := _flood(lay, lay.start, shut)
		if reach.has(rect.get_center()):
			return "%s room reachable past its door" % pair[1]
	return ""


func check_layouts(fid: String) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var monsters := {}
	for m in fd.monsters:
		monsters[str(m.id)] = true
	var allowed_props := {"pillar": true, "bookshelf": true, "rusty_lever": true, str(fd.get("secret_container", "secret_sarcophagus")): true}
	for k in fd.get("prop_weights", {}):
		allowed_props[k] = true
	var plates := 0
	var pendulums := 0
	var spouts := 0
	var arenas := 0
	var anomalies := 0
	var rifts := 0
	var snares := 0
	var caves := 0
	var kinds := {}
	var gates := 0
	var gate_bad := ""
	var tiers_seen := {}
	var bad := ""
	for i in 6:
		var seed_value := 1000 + i * 7919
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1 + i)
		var reach := _flood(lay, lay.start)
		for room in lay.rooms:
			if room.role == "prison":
				if reach.has(Vector2i(room.rect.get_center())):
					bad = "the Tome Prison arena is reachable (seed %d)" % seed_value
				continue
			if not reach.has(Vector2i(room.rect.get_center())):
				bad = "room %s unreachable (seed %d)" % [room.role, seed_value]
		for grp in lay.spawns:
			for m in grp.monsters:
				if not monsters.has(str(m.id)):
					bad = "foreign monster %s" % m.id
				var tier := int(GameData.monsters[str(m.id)].get("tier", 1))
				tiers_seen[tier] = true
				if tier > DungeonGenerator.tier_allowed(1 + i):
					bad = "tier %d %s on depth %d" % [tier, m.id, 1 + i]
		for pr in lay.props:
			if not allowed_props.has(str(pr.type)):
				bad = "foreign prop %s" % pr.type
		if lay.get("merchant", {}).is_empty():
			bad = "no merchant chamber (seed %d)" % seed_value
		plates += lay.get("plates", []).size()
		pendulums += lay.get("pendulums", []).size() + lay.props.filter(func(pr): return str(pr.type).contains("pendulum")).size()
		spouts += lay.get("spouts", []).size()
		arenas += 1 if lay.has("side_arena") else 0
		anomalies += lay.get("anomalies", []).size()
		rifts += lay.get("rifts", []).size() + lay.get("runes", []).size()
		snares += lay.get("snares", []).size()
		caves += lay.rooms.filter(func(rm): return rm.get("cave", false)).size()
		var cells: PackedByteArray = lay.cells
		for v in cells:
			kinds[v] = true
		for di in lay.doors.size():
			if lay.doors[di].get("floodgate", false):
				gates += 1
				var levers: Array = lay.props.filter(func(pr): return int(pr.get("gate", -1)) == di)
				if levers.size() != 2:
					gate_bad = "floodgate %d has %d levers" % [di, levers.size()]
	da.check(bad.is_empty(), "%s layouts are connected and use the biome's monsters and props of the depth's tiers%s" % [fid, "" if bad.is_empty() else ": " + bad])
	da.check(tiers_seen.has(1) and tiers_seen.has(2) and tiers_seen.has(3), "%s: depths 1-6 bring in tiers 1, 2 and 3 (%s)" % [fid, tiers_seen.keys()])
	var basic := true
	for d0 in [1, 2]:
		var lay0: Dictionary = DungeonGenerator.new().generate(77 + d0, fd, 1.0, d0)
		for grp0 in lay0.spawns:
			for m0 in grp0.monsters:
				basic = basic and int(GameData.monsters[str(m0.id)].get("tier", 1)) == 1
	da.check(basic, "%s on depths 1-2 spawns only tier 1 monsters" % fid)
	if fd.has("plates_per_room"):
		da.check(plates > 0, "%s layouts have pressure plates (%d over 6 floors)" % [fid, plates])
	da.check(pendulums == 0 and not fd.has("pendulums"), "%s layouts have no pendulum traps (#5)" % fid)
	var gen: Dictionary = fd.get("generator", {})
	if gen.has("water_room_chance"):
		da.check(kinds.has(DungeonGenerator.CELL_WATER) and kinds.has(DungeonGenerator.CELL_SLUDGE), "%s layouts have sewage pools and deep sludge" % fid)
	if gen.has("canal_room_chance"):
		da.check(kinds.has(DungeonGenerator.CELL_CANAL) and kinds.has(DungeonGenerator.CELL_BRIDGE), "%s layouts have toxic canals with catwalks" % fid)
	if gen.has("floodgate_chance"):
		da.check(gates > 0 and gate_bad.is_empty(), "%s floodgates each have two levers (%d gates%s)" % [fid, gates, "" if gate_bad.is_empty() else ", " + gate_bad])
	if fd.has("acid_spouts") or fd.has("wall_spouts"):
		da.check(spouts > 0, "%s layouts have wall spouts (%d over 6 floors)" % [fid, spouts])
	if gen.has("platform_room_chance"):
		da.check(kinds.has(DungeonGenerator.CELL_LAVA) and kinds.has(DungeonGenerator.CELL_BRIDGE), "%s layouts have molten lakes with bridges" % fid)
	if gen.has("side_arena"):
		da.check(arenas > 0, "%s floors carve a sealed Tome Prison arena (%d of 6)" % [fid, arenas])
	if gen.has("anomaly_room_chance"):
		da.check(anomalies > 0, "%s layouts have spatial anomaly rooms (%d)" % [fid, anomalies])
	if fd.has("void_rifts"):
		da.check(rifts > 0, "%s layouts have void rifts and silence runes (%d)" % [fid, rifts])
	if gen.has("cave_room_chance"):
		da.check(caves > 0, "%s layouts carve organic caverns (%d rooms)" % [fid, caves])
	if fd.has("root_snares"):
		da.check(snares > 0, "%s layouts hide root snares (%d)" % [fid, snares])
	if gen.has("grates_per_room"):
		da.check(kinds.has(DungeonGenerator.CELL_GRATE), "%s layouts have collapsing grates" % fid)
	var picked := {}
	for s in 60:
		picked[g.pick_boss(fd, s * 31 + 7)] = true
	var pool: Array = fd.get("bosses", [fd.get("boss", "")])
	da.check(picked.size() == pool.size(), "%s boss pick covers %s" % [fid, ", ".join(pool)])


func check_live_floor() -> void:
	var fid := str(g.floor_def.id)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	da.check(g.floor_mechanics.size() == g.floor_def.get("floor_mechanics", []).size(), "%s floor mechanics are running (%d)" % [fid, g.floor_mechanics.size()])
	if not g.dungeon.plates.is_empty():
		var plate: Node2D = g.dungeon.plates[0]
		_ready_hero()
		p.host_teleport(plate.global_position + Vector2(0, -6))
		var hp := p.health.hp
		await da._wait(1.2)
		da.check(p.health.hp < hp, "a pressure plate raises spikes under the hero (%.0f -> %.0f)" % [hp, p.health.hp])
	if not g.dungeon.spouts.is_empty():
		var sp: Node2D = g.dungeon.spouts[0]
		_ready_hero()
		var hp3 := p.health.hp
		var t3 := 0.0
		while t3 < 6.0 and p.health.hp >= hp3:
			p.host_teleport(sp.spray_rect().get_center())
			await da.get_tree().physics_frame
			t3 += 1.0 / 60.0
		da.check(p.health.hp < hp3, "a wall spout (acid / flame) burns the hero")
	if not g.dungeon.proximity_props.is_empty():
		var pr: Node2D = g.dungeon.proximity_props[0]
		_ready_hero()
		p.iframe_left = 9999.0
		p.host_teleport(pr.global_position + Vector2(0, 20))
		await da._wait(0.6)
		da.check(not g.dungeon.props.values().has(pr), "a gas pocket goes off when a hero comes close")
	if not g.layout.get("rifts", []).is_empty():
		var rift: Vector2 = g.layout.rifts[0]
		_ready_hero()
		# A spot in the rift's pull with nothing between (a wall would hold the hero back).
		var spot: Vector2 = g.nearest_floor(rift + Vector2(70, 0))
		for off in [Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70), Vector2(50, 50), Vector2(-50, 50), Vector2(50, -50), Vector2(-50, -50)]:
			var cand: Vector2 = g.nearest_floor(rift + off)
			if cand.distance_to(rift) > 40.0 and cand.distance_to(rift) < 90.0 and Combat.instance.has_los(cand, rift):
				spot = cand
				break
		p.host_teleport(spot)
		var d0 := p.global_position.distance_to(rift)
		await da._wait(1.2)
		da.check(p.global_position.distance_to(rift) < d0 - 4.0, "a void rift pulls the hero in")
	if not g.layout.get("runes", []).is_empty():
		var rune: Vector2 = g.layout.runes[0]
		_ready_hero()
		p.host_teleport(rune)
		await da._wait(0.4)
		da.check(p.status.has("silence") or p.status.has_flag("silenced"), "a silence rune silences the hero")
	if not g.layout.get("snares", []).is_empty():
		_ready_hero()
		p.host_teleport(g.layout.snares[0])
		await da._wait(0.4)
		da.check(p.status.has("root") or p.status.has("bleed"), "a root snare grabs the hero")
	if not g.dungeon.grates.is_empty():
		var gr: Node2D = g.dungeon.grates[0]
		_ready_hero()
		p.iframe_left = 9999.0
		p.host_teleport(gr.global_position)
		await da._wait(1.2)
		da.check(g.dungeon.cell_at(gr.cell) == DungeonGenerator.CELL_LAVA, "a grate collapses under a hero")
	if not g.dungeon.pulse_props.is_empty():
		var pp: Node2D = g.dungeon.pulse_props[0]
		_ready_hero()
		p.host_teleport(pp.global_position + Vector2(0, 24))
		var hp4 := p.health.hp
		# Up to three pulses: a single splash can be dodged or blocked.
		for i in 3:
			pp.set_meta("pulse_left", 0.05)
			await da._wait(0.5)
			if p.health.hp < hp4:
				break
		if p.health.hp >= hp4:
			print("[test] pulse miss: %s at %s, hero at %s (%.0f px), hp %d" % [pp.def.get("id", "?"), pp.global_position, p.global_position, p.global_position.distance_to(pp.global_position), p.health.hp])
		da.check(p.health.hp < hp4, "a pulsing prop (cauldron, dread totem) hits the hero")
	var gate := -1
	for di in g.dungeon.doors.size():
		if g.dungeon.doors[di].floodgate:
			gate = di
			break
	if gate >= 0:
		var door: Node = g.dungeon.doors[gate]
		_ready_hero()
		p.host_teleport(door.interact_pos() + Vector2(0, 20))
		g.host_interact(p, door)
		await da._wait(0.3)
		var shut: bool = not door.is_open
		var lever: Node = null
		for pr2 in g.dungeon.props.values():
			if int(pr2.get_meta("gate", -1)) == gate:
				lever = pr2
		if lever:
			p.host_teleport(lever.global_position + Vector2(0, 14))
			g.host_interact(p, lever)
		await da._wait(0.4)
		da.check(shut and door.is_open, "a floodgate stays shut until its lever is pulled")
	for fm in g.floor_mechanics:
		_ready_hero()
		p.iframe_left = 9999.0
		# Checks that need the dark start with the hero's carried torch burnt out (only the burn-out
		# time ends it in play, #3).
		p.torch_left = 0.0
		p.torch_sync = 0
		await fm.test_trigger(self)
		var mt := 0.0
		var err := "not checked"
		while mt < float(fm.params.get("test_wait", 4.0)):
			p.health.hp = p.health.max_hp
			err = fm.test_check(self)
			if err.is_empty():
				break
			await da._wait(0.25)
			mt += 0.25
		da.check(err.is_empty(), "%s mechanic %s%s" % [fid, fm.params.get("id", "?"), "" if err.is_empty() else ": " + err])
	_ready_hero()
	p.iframe_left = 9999.0


## A floor position (away from the merchant chamber) that satisfies `pred`.
func find_spot(pred: Callable) -> Vector2:
	var d: Node = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			var c := Vector2i(x, y)
			if d.cell_at(c) != DungeonGenerator.CELL_FLOOR or d.safe_rect.has_point(c):
				continue
			var pos: Vector2 = d.cell_center(c)
			if pred.call(pos):
				return pos
	return p.global_position


func _ready_hero() -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.iframe_left = 0.0
	p.status.clear_all()
	p.stats.final.dodge = 0.0
	p.health.hp = p.health.max_hp


func _flood(lay: Dictionary, from: Vector2, shut: Dictionary = {}) -> Dictionary:
	var tile := int(GameData.bal("world.tile_size"))
	var size: Vector2i = lay.size
	var cells: PackedByteArray = lay.cells
	var start := Vector2i(from / tile)
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y or seen.has(n) or shut.has(n):
				continue
			if cells[n.y * size.x + n.x] == DungeonGenerator.CELL_WALL:
				continue
			seen[n] = true
			queue.append(n)
	return seen
