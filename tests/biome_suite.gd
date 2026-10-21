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
			leaf_rules(str(id), 150 if not biome.is_empty() else 100)
			depth_growth(str(id))
			party_counts(str(id))
	if biome.is_empty():
		plan_checks()
		await mixed_live_floor()
	await check_live_floor()


## #70: the run's biome order, mixed floors and boss picks over many run seeds (pure functions of
## the run seed and depth, so every peer and a continued game agree).
func plan_checks() -> void:
	var forced: Variant = GameState.get_meta("force_biome", "")
	GameState.set_meta("force_biome", "")
	var fixed := FloorPlan.fixed_order()
	var n := fixed.size()
	var bad_fixed := 0
	var repeats := []
	var holes := []
	var mixed := 0
	var mixed_slots := 0
	var early_mix := 0
	var self_mix := 0
	var boss_repeat := []
	var seeds := 24
	for s in seeds:
		var rs := 1000 + s * 7717
		var seq: Array = []
		for d in range(1, 56):
			seq.append(FloorPlan.biome_at(rs, d))
		for d in range(1, 6):
			if seq[d - 1] != fixed[d - 1]:
				bad_fixed += 1
		for d in range(2, 56):
			if seq[d - 1] == seq[d - 2]:
				repeats.append("seed %d floor %d %s" % [rs, d, seq[d - 1]])
		for c in range(5, 55, n):
			var cyc := {}
			for k in n:
				cyc[seq[c + k]] = true
			if cyc.size() != n:
				holes.append("seed %d floors %d-%d" % [rs, c + 1, c + n])
		for d in range(1, 56):
			var m := FloorPlan.mix_at(rs, d)
			if d < int(GameData.bal("biomes.mixed_from_floor")):
				early_mix += 0 if m.is_empty() else 1
				continue
			mixed_slots += 1
			if not m.is_empty():
				mixed += 1
				self_mix += 1 if m == seq[d - 1] else 0
		var bosses := FloorPlan.bosses_to(rs, 40)
		var last := {}
		for d in range(1, 41):
			var b: String = seq[d - 1]
			if last.has(b) and last[b] == bosses[d - 1] and GameData.floor_types[b].bosses.size() > 1:
				boss_repeat.append("seed %d floor %d" % [rs, d])
			last[b] = bosses[d - 1]
	da.check(bad_fixed == 0, "floors 1-5 keep the fixed order (%s) for every run seed" % ", ".join(fixed))
	da.check(repeats.is_empty(), "floors 1-55 over %d run seeds never repeat a biome back to back%s" % [seeds, "" if repeats.is_empty() else ": %s" % [repeats.slice(0, 4)]])
	da.check(holes.is_empty(), "every cycle of five from floor 6 holds all five biomes%s" % ("" if holes.is_empty() else ": %s" % [holes.slice(0, 4)]))
	var share := float(mixed) / maxf(mixed_slots, 1)
	var want := float(GameData.bal("biomes.mixed_share"))
	da.check(early_mix == 0 and self_mix == 0 and absf(share - want) < 0.06,
			"mixed floors only from floor 6, never by their own biome, at the data share (%.2f, data %.2f)" % [share, want])
	da.check(boss_repeat.is_empty(), "a boss never repeats the one met last time in its biome%s" % ("" if boss_repeat.is_empty() else ": %s" % [boss_repeat.slice(0, 4)]))
	# A mixed floor's spawns bring monsters of both biomes, at about the data share.
	var own := 0
	var inv := 0
	var hazards := 0
	for s in 12:
		var fd := FloorPlan.floor_def("crypt", "sewers", 555 + s)
		hazards += 1 if fd.get("mix_hazard", false) else 0
		var lay: Dictionary = DungeonGenerator.new().generate(555 + s, fd, 1.0, 8)
		var inv_ids: Array = GameData.floor_types.sewers.monsters.map(func(m): return str(m.id))
		for grp in lay.spawns:
			for m in grp.monsters:
				if inv_ids.has(str(m.id)):
					inv += 1
				else:
					own += 1
	var ms := float(inv) / maxf(own + inv, 1)
	da.check(own > 0 and inv > 0 and absf(ms - float(GameData.bal("biomes.monster_share"))) < 0.12,
			"a mixed floor spawns monsters of both biomes (%d own, %d invaders: %.2f, data %.2f)" % [own, inv, ms, float(GameData.bal("biomes.monster_share"))])
	var fdk := FloorPlan.floor_def("archives", "kurgan", 9)
	da.check(FloorPlan.title(fdk).contains(Loc.t("overrun from the Blighted Kurgan")) and FloorPlan.title(fdk).begins_with(Loc.t("The Shrouded Archives")),
			"a mixed floor's title names its invader ('%s')" % FloorPlan.title(fdk))
	GameState.set_meta("force_biome", forced)


## #70: a live mixed floor: invaders among its monsters, its title in the banner and the HUD.
func mixed_live_floor() -> void:
	GameState.set_meta("force_mix", "kurgan")
	g.start_floor(g.depth + 1)
	await da._wait(1.5)
	var inv_ids: Array = GameData.floor_types.kurgan.monsters.map(func(m): return str(m.id))
	var seen_inv := 0
	for e in g.enemies_root.get_children():
		if not e.is_boss and inv_ids.has(str(e.def_id)):
			seen_inv += 1
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(str(g.floor_def.get("mix", "")) == "kurgan" and seen_inv > 0 and hud._mix_label.visible and not hud._mix_label.text.is_empty(),
			"a live mixed floor (%s by kurgan): %d invading monsters, the HUD says '%s'" % [g.floor_type_for(g.depth), seen_inv, hud._mix_label.text])
	GameState.set_meta("force_mix", "")
	g.start_floor(g.depth + 1)
	await da._wait(1.0)
	da.check(not hud._mix_label.visible, "an ordinary floor shows no invader line")


## #68: a party of four meets about x1.5 the monsters per room of a lone hero (the count
## multiplier Game.start_floor passes the generator; HP and damage scale per player).
func party_counts(fid: String) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var per := float(GameData.bal("scaling.count_per_extra_player"))
	var avg := {}
	for n in [1, 4]:
		var total := 0
		var rooms := 0
		for i in 8:
			var lay: Dictionary = DungeonGenerator.new().generate(777 + i * 7919, fd, 1.0 + per * (n - 1), 3)
			for grp in lay.spawns:
				total += grp.monsters.size()
				rooms += 1
		avg[n] = float(total) / maxf(rooms, 1.0)
	var ratio: float = avg[4] / maxf(avg[1], 0.01)
	da.check(ratio > 1.3 and ratio < 1.7, "%s: 4 heroes meet %.1f monsters per room, a lone hero %.1f (x%.2f, data x%.2f)" % [fid, avg[4], avg[1], ratio, 1.0 + per * 3.0])


## #58: deeper floors are a little bigger. Over several seeds per depth: the room count and the
## grid grow with depth, never past dungeon.size_max_mult, and every layout keeps the #23 / #30
## leaf rules (connected, sealed boss and merchant rooms).
func depth_growth(fid: String) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var cap := float(GameData.bal("dungeon.size_max_mult"))
	var base_rooms := (int(fd.rooms.count[0]) + int(fd.rooms.count[1])) / 2.0 + 3.0  # + start, boss, merchant
	var bad := ""
	var avg := {}
	for d in [1, 5, 10, 20, 40]:
		var total := 0
		for i in 6:
			var seed_value: int = 4242 + i * 7919 + int(d) * 31
			var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, d)
			var why := _leaf_problem(lay)
			if not why.is_empty() and bad.is_empty():
				bad = "depth %d seed %d: %s" % [d, seed_value, why]
			var area_mult := float(lay.size.x * lay.size.y) / float(int(fd.grid[0]) * int(fd.grid[1]))
			if area_mult > cap * 1.05 and bad.is_empty():
				bad = "depth %d grid %s is %.2fx floor 1" % [d, lay.size, area_mult]
			total += lay.rooms.filter(func(r): return r.role != "prison").size()
		avg[d] = total / 6.0
	var grows: bool = avg[5] >= avg[1] and avg[10] > avg[1] and avg[20] > avg[10] and avg[40] >= avg[20]
	var capped: bool = avg[40] <= base_rooms * cap + 1.0 and is_equal_approx(DungeonGenerator.size_mult(40), cap)
	da.check(grows and capped and bad.is_empty(), "%s: floors grow a little with depth, up to %.1fx (average rooms at depth 1/5/10/20/40: %s)%s"
			% [fid, cap, ", ".join([avg[1], avg[5], avg[10], avg[20], avg[40]].map(func(v): return "%.1f" % v)), "" if bad.is_empty() else ": " + bad])


## #23 / #30 / #31 over many seeds, read from the carved grid (not the generator's intentions):
## the boss chamber is the room farthest from the start along the room graph and a dead end with
## one opening, its one door is the boss door in its bottom wall; the merchant room likewise
## has one opening and one merchant door; nothing else leaks into either.
func leaf_rules(fid: String, seeds: int = 150) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var bad := ""
	var t0 := Time.get_ticks_msec()
	for i in seeds:
		var seed_value := 31337 + i * 7919
		# Every other floor with the forge (#77), a third sealed leaf.
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1 + i % 8, "", i % 2 == 0)
		var why := _leaf_problem(lay)
		if not why.is_empty():
			bad = "seed %d: %s" % [seed_value, why]
			break
	da.check(bad.is_empty(), "%s: over %d seeds the boss chamber is the graph-farthest dead end with one boss door and the merchant room (and the forge) has one door of its own (%d ms)%s" % [fid, seeds, Time.get_ticks_msec() - t0, "" if bad.is_empty() else ": " + bad])


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
	var leaves := [[boss, "boss"], [int(lay.merchant.get("room", -1)), "merchant"]]
	if not lay.get("forge", {}).is_empty():
		leaves.append([int(lay.forge.room), "forge"])
	for pair in leaves:
		var ri: int = pair[0]
		if ri < 0:
			return "no %s room" % pair[1]
		var rect: Rect2i = lay.rooms[ri].rect
		var openings := DungeonGenerator.room_openings(lay.cells, lay.size, rect)
		if openings != 1 or adj[ri].size() != 1:
			return "%s room has %d openings, %d neighbours" % [pair[1], openings, adj[ri].size()]
		var doors: Array = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(rect.grow(1)))
		if doors.size() != 1 or str(doors[0].kind) != pair[1] or doors[0].vertical or Rect2i(doors[0].rect).position.y != rect.end.y:
			return "%s room doors: %s" % [pair[1], doors.map(func(d): return [d.kind, d.vertical, d.rect])]
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
	# A single depth-6 floor can miss a rare tier-3 monster (one weight-2 type in Sewers): a few
	# more depth-6 seeds settle it.
	for k in 4:
		for grp in DungeonGenerator.new().generate(2000 + k * 7919, fd, 1.0, 6).spawns:
			for m in grp.monsters:
				tiers_seen[int(GameData.monsters[str(m.id)].get("tier", 1))] = true
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
	if fid == "foundry":
		await no_eruptions()


## #62: the Foundry has no magma eruptions any more: a hero standing by a lava channel (away from
## spouts and cauldrons, no monsters) for 30 s takes no damage at all.
func no_eruptions() -> void:
	var d: Node = g.dungeon
	var quiet := func(pos: Vector2) -> bool:
		if d.cell_at(d.cell_of(pos)) != DungeonGenerator.CELL_FLOOR:
			return false
		for sp in d.spouts:
			if sp.global_position.distance_to(pos) < 220.0:
				return false
		for pr in d.pulse_props:
			if is_instance_valid(pr) and pr.global_position.distance_to(pos) < 160.0:
				return false
		var c: Vector2i = d.cell_of(pos)
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				if d.cell_at(c + Vector2i(dx, dy)) == DungeonGenerator.CELL_LAVA:
					return absi(dx) > 1 or absi(dy) > 1
		return false
	var spot := find_spot(quiet)
	var found: bool = quiet.call(spot)
	da.check(found, "foundry: a quiet spot by a lava channel")
	if not found:
		return
	da.check(not g.floor_mechanics.any(func(fm): return str(fm.params.get("id", "")) == "magma_eruptions"), "foundry: no magma eruption mechanic runs")
	for e in g.enemies_root.get_children():
		e.queue_free()
	_ready_hero()
	p.iframe_left = 0.0
	p.host_teleport(spot)
	await da._wait(0.5)
	var hp0 := p.health.hp
	var lowest := hp0
	var t := 0.0
	while t < 30.0:
		await da._wait(0.5)
		t += 0.5
		lowest = minf(lowest, p.health.hp)
	da.check(lowest >= hp0, "foundry: 30 s beside a lava channel and nothing erupts under the hero (HP %.0f -> lowest %.0f)" % [hp0, lowest])
	p.iframe_left = 9999.0


## A floor position (away from the merchant chamber) that satisfies `pred`.
func find_spot(pred: Callable) -> Vector2:
	var d: Node = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			var c := Vector2i(x, y)
			if d.cell_at(c) != DungeonGenerator.CELL_FLOOR or d.in_safe_cell(c):
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
