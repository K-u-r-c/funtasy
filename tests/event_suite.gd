class_name EventSuite
extends RefCounted
## #72 Special rooms and events (scenario "events" solo, "events_lan" host + client): the floor
## picks 1-3 different events from floor 2 (none on floor 1), the generator puts them in normal,
## reachable rooms (never the start, boss, merchant or forge chamber; the arena only where every
## way in is a door it can shut; the vault a sealed leaf with its lever elsewhere); each event's
## whole flow works with its warnings shown before the danger (Telegraph leads); the HUD tracker,
## the map markers and the save keep up.

var da: Node
var g: Node
var p: Player
var fe: FloorEvents


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	p.iframe_left = 9999.0
	await da._wait(1.0)
	if da.only.has("probe"):
		await BalanceSuite.new(da).run_events()
		return
	picks()
	placement()
	GameState.set_meta("force_events", "arena,vault,shrine,cursed_chest,prisoner")
	GameState.set_meta("test_mimic", true)
	GameState.set_meta("test_prisoner", "ally")
	g.start_floor(4)
	await da._wait(2.0)
	p = da._local()
	p.iframe_left = 9999.0
	fe = g.events
	live_layout()
	await shrine()
	await cursed_chest()
	await prisoner()
	await vault()
	await arena()
	tracker_and_map()
	saved()
	# The other outcomes on a fresh floor: a plain cursed chest, a prisoner who rewards.
	GameState.set_meta("force_events", "cursed_chest,prisoner")
	GameState.set_meta("test_mimic", false)
	GameState.set_meta("test_prisoner", "reward")
	g.start_floor(5)
	await da._wait(2.0)
	p = da._local()
	p.iframe_left = 9999.0
	fe = g.events
	await plain_chest()
	await prisoner_reward()
	# Floor-long bargains end with the floor.
	GameState.set_meta("force_events", "none")
	g.start_floor(6)
	await da._wait(1.5)
	p = da._local()
	da.check(not p.status.effects.any(func(s): return str(s.id).begins_with("shrine_")), "the shrine's bargain and curse end with the floor")
	for k in ["force_events", "test_mimic", "test_prisoner"]:
		GameState.remove_meta(k)
	await BalanceSuite.new(da).run_events()


## Floor 1 never, then 1-3 different events (over 400 floors on floor 2-12), the same for the same
## seed, every event appearing; the prisoner only from its min_depth.
func picks() -> void:
	var forced := str(GameState.get_meta("force_events", ""))
	GameState.remove_meta("force_events")
	var bad := ""
	var seen := {}
	var counts := {1: 0, 2: 0, 3: 0}
	for i in 400:
		var sd := 333 + i * 7919
		var d := 2 + i % 11
		var evs: Array = g.pick_events(sd, d)
		if evs != g.pick_events(sd, d):
			bad = "seed %d not stable" % sd
		if evs.size() < 1 or evs.size() > 3:
			bad = "seed %d: %d events" % [sd, evs.size()]
		var uniq := {}
		for e in evs:
			uniq[e] = true
			seen[e] = int(seen.get(e, 0)) + 1
			if d < int(FloorEvents.def(str(e)).get("min_depth", 1)):
				bad = "%s on floor %d" % [e, d]
		if uniq.size() != evs.size():
			bad = "seed %d repeats %s" % [sd, evs]
		counts[evs.size()] = int(counts.get(evs.size(), 0)) + 1
	var none1 := true
	for i in 50:
		none1 = none1 and g.pick_events(9 + i * 31, 1).is_empty()
	if not forced.is_empty():
		GameState.set_meta("force_events", forced)
	da.check(bad.is_empty() and none1 and seen.size() == 5, "1-3 different events a floor from floor 2, none on floor 1, seeded, all five appear (%s, counts %s)%s" % [seen, counts, "" if bad.is_empty() else ": " + bad])


## Over many layouts in every biome: events only in normal rooms reachable from the start (the
## vault in its own sealed leaf), the arena where every opening is a door and never a leaf's
## anchor, and the special chambers untouched.
func placement() -> void:
	var bad := ""
	var placed := {}
	var asked := {}
	for fid in ["crypt", "sewers", "foundry", "archives", "kurgan"]:
		var fd: Dictionary = GameData.floor_types[fid]
		for i in 24:
			var sd := 7711 + i * 104729
			var depth := 2 + i % 9
			var evs: Array = g.pick_events(sd, depth)
			if i % 4 == 0:
				evs = ["arena", "vault", "shrine"]
			for e in evs:
				asked[e] = int(asked.get(e, 0)) + 1
			var lay: Dictionary = DungeonGenerator.new().generate(sd, fd, 1.0, depth, "", i % 3 == 0, evs)
			var why := _placement_problem(lay, evs)
			for e in lay.events:
				placed[e.id] = int(placed.get(e.id, 0)) + 1
			if not why.is_empty():
				bad = "%s seed %d %s: %s" % [fid, sd, evs, why]
				break
		if not bad.is_empty():
			break
	var missing := []
	for e in asked:
		if int(placed.get(e, 0)) < int(asked[e]) * 0.9:
			missing.append("%s %d/%d" % [e, placed.get(e, 0), asked[e]])
	da.check(bad.is_empty() and missing.is_empty(), "120 layouts: every event in a reachable normal room (the vault a sealed leaf), the arena sealable, no special chamber used (placed %s of %s)%s" % [placed, asked, "" if bad.is_empty() else ": " + bad])
	da.check(missing.is_empty(), "at least 90%% of the events asked for find a room (%s)" % [missing])


func _placement_problem(lay: Dictionary, evs: Array) -> String:
	var adj: Array = DungeonGenerator.room_graph(lay.cells, lay.size, lay.rooms)
	var hops: Dictionary = DungeonGenerator.room_hops(adj, 0)
	var ids := {}
	for e in lay.events:
		ids[e.id] = true
		if not evs.has(e.id):
			return "%s placed but not asked for" % e.id
		var room: Dictionary = lay.rooms[int(e.room)]
		if e.id == "vault":
			if room.role != "vault":
				return "the vault is in a %s room" % room.role
			var lr: Dictionary = lay.rooms[int(e.lever_room)]
			if lr.role != "normal" or not hops.has(int(e.lever_room)):
				return "the vault lever in a %s room" % lr.role
			var doors: Array = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(Rect2i(room.rect).grow(1)))
			if doors.size() != 1 or str(doors[0].kind) != "vault" or not doors[0].monster_proof:
				return "vault doors %s" % [doors.map(func(d): return d.kind)]
			if DungeonGenerator.room_openings(lay.cells, lay.size, room.rect) != 1:
				return "the vault is not a dead end"
			continue
		if room.role != "normal":
			return "%s in a %s room" % [e.id, room.role]
		if not hops.has(int(e.room)):
			return "%s unreachable" % e.id
		if e.id == "arena":
			var r: Rect2i = room.rect
			var dn: int = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(r.grow(1))).size()
			if room.get("leaf_anchor", false) or DungeonGenerator.room_openings(lay.cells, lay.size, r) != dn or e.doors.size() != dn:
				return "the arena can't be sealed (%d doors)" % dn
			for grp in lay.spawns:
				if int(grp.room) == int(e.room) and not grp.monsters.is_empty():
					return "monsters already in the arena"
		else:
			var c: Vector2i = Vector2i(Vector2(e.pos) / 32.0)
			if not DungeonGenerator.walkable(lay.cells[c.y * lay.size.x + c.x]):
				return "%s on a %d cell" % [e.id, lay.cells[c.y * lay.size.x + c.x]]
	return ""


func live_layout() -> void:
	da.check(fe.entries.size() == 5, "the test floor has all five events (%s)" % [fe.entries.keys()])
	for k in ["Event_shrine", "Event_cursed_chest", "Event_prisoner", "Event_vault_lever", "Event_arena_chest"]:
		if not g.dungeon.props.has(k):
			da.check(false, "the floor has %s" % k)
	da.check(not g.dungeon.props["Event_arena_chest"].visible and not g.dungeon.props["Event_arena_chest"].interactable(), "the arena's chest waits hidden")
	var guards: Array = g.enemies_root.get_children().filter(func(e): return e.get("guard"))
	da.check(guards.size() == 1 and guards[0].is_elite(), "one elite guard carries the cell key")


func _near(pos: Vector2, dy: float = 30.0) -> void:
	p.host_teleport(g.nearest_floor(pos + Vector2(0, dy)))
	await da._wait(0.4)


## The shrine: kneeling opens two bargains; striking one applies its gift and its price, once.
func shrine() -> void:
	var node: Node = g.dungeon.props["Event_shrine"]
	await _near(node.global_position)
	g.host_interact(p, node)
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Node = hud._overlay
	da.check(panel != null and panel.get("cards") != null and panel.cards.size() == 2, "kneeling at the shrine shows two bargains")
	if panel == null or panel.get("cards") == null or panel.cards.is_empty():
		return
	var id: String = panel.cards.keys()[0]
	var b: Dictionary = {}
	for x in FloorEvents.def("shrine").bargains:
		if str(x.id) == id:
			b = x
	var hp0 := p.health.hp
	panel._choose(id)
	await da._wait(0.9)
	da.check(p.status.has(str(b.buff)), "the bargain's gift (%s) is on the hero" % b.buff)
	match str(b.cost):
		"hp":
			da.check(p.health.hp < hp0 * 0.8, "its price: health now (%d -> %d)" % [hp0, p.health.hp])
		"curse":
			da.check(p.status.has(str(b.curse)), "its price: the curse %s" % b.curse)
		"tougher":
			var room := int(fe.st("shrine").get("tougher", -1))
			var r: Rect2i = g.layout.rooms[room].rect if room >= 0 else Rect2i()
			var em: Array = g.enemies_root.get_children().filter(func(e): return r.has_point(g.dungeon.cell_of(e.global_position)))
			da.check(room >= 0 and not em.is_empty() and em.all(func(e): return e.status.has("shrine_empowered")) and Telegraph.lead_of("shrine_tougher") >= 0.0,
				"its price: the nearest room's monsters are empowered and marked (%d)" % em.size())
	g.host_interact(p, node)
	await da._wait(0.4)
	da.check(hud._overlay == null or hud._overlay.get("cards") == null, "the idol takes its price only once")


## The cursed chest (a mimic here): it breathes now and then; opened, it shudders for its lead
## before the mimic bites; killed, it drops the cursed loot.
func cursed_chest() -> void:
	var node: Node = g.dungeon.props["Event_cursed_chest"]
	await _near(node.global_position, 26.0)
	await da._wait_until(func(): return fe.log.any(func(e): return e[0] == "breath"), 8.0)
	da.check(fe.log.any(func(e): return e[0] == "breath"), "a mimic chest breathes now and then (the tell)")
	var items0: int = g.items_root.get_child_count()
	g.host_interact(p, node)
	await da._wait_until(func(): return str(fe.st("cursed_chest").get("state", "")) == "mimic", 4.0)
	var lead := Telegraph.lead_of("mimic")
	var m: Array = g.enemies_root.get_children().filter(func(e): return e.get_meta("event_mimic", false))
	da.check(m.size() == 1 and lead >= FloorEvents.num("cursed_chest", "wake_warn") - 0.05, "opened, it shudders %.1f s (data %.1f) before the mimic wakes" % [lead, FloorEvents.num("cursed_chest", "wake_warn")])
	if m.is_empty():
		return
	Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), m[0], 999999.0, {"damage_type": "true"})
	await da._wait(0.6)
	da.check(str(fe.st("cursed_chest").get("state", "")) == "dead" and g.items_root.get_child_count() > items0 + 1, "the mimic falls and the cursed treasure spills out")


## The prisoner: locked without the key; the guard drops it; the key frees the prisoner, who
## fights for the heroes.
func prisoner() -> void:
	var cage: Node = g.dungeon.props["Event_prisoner"]
	da.check(cage.get_node_or_null("PrisonerNpc") != null, "the captive stands in the cage")
	await _near(cage.global_position, 34.0)
	g.host_interact(p, cage)
	await da._wait(0.3)
	da.check(str(fe.st("prisoner").get("state", "")) == "locked", "without the key the cage stays locked")
	var guard: Array = g.enemies_root.get_children().filter(func(e): return e.get("guard"))
	if guard.is_empty():
		da.check(false, "the guard is on the floor")
		return
	# Some monsters get up again (bone piles, shells): strike until it stays down.
	for k in 6:
		if not is_instance_valid(guard[0]) or guard[0].health.hp <= 0.0:
			break
		guard[0].behaviors.clear()
		Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), guard[0], 999999.0, {"damage_type": "true"})
		await da._wait(0.4)
	await da._wait_until(func(): return g.items_root.get_children().any(func(it): return str(it.item.get("kind", "")) == "cell_key"), 3.0)
	var key: Array = g.items_root.get_children().filter(func(it): return str(it.item.get("kind", "")) == "cell_key")
	da.check(key.size() == 1, "the guard drops the cell key")
	if key.is_empty():
		return
	p.host_teleport(key[0].global_position)
	await da._wait(0.5)
	g.loot.try_pickup(p, key[0])
	await da._wait(0.3)
	da.check(fe.st("prisoner").get("key", false), "the party holds the cell key")
	await _near(cage.global_position, 34.0)
	g.host_interact(p, cage)
	await da._wait(0.8)
	var allies: Array = g.enemies_root.get_children().filter(func(e): return e.get_meta("event_ally", false))
	da.check(str(fe.st("prisoner").get("state", "")) == "freed" and allies.size() == 1 and allies[0].team == Actor.Team.PLAYERS and not allies[0].look.is_empty(),
		"freed, %s fights beside the heroes (hero look, heroes' side)" % fe.prisoner_def().get("name", ""))
	if allies.size() == 1:
		await companion(allies[0], p)


## #99 (host): the freed prisoner follows `hero` (who freed it) through the floor, fights the
## monsters near it, is a target for them, catches up when left far behind and never blocks a hero.
func companion(ally: Enemy, hero: Player) -> void:
	var comp: MonsterBehavior = null
	for b in ally.behaviors:
		if str(b.params.get("id", "")) == "companion":
			comp = b
	da.check(comp != null and ally.collision_layer == 0 and int(ally.get_meta("leader_peer", 0)) == hero.peer_id,
			"the prisoner follows its rescuer and has no body a hero could bump into")
	if comp == null:
		return
	for e in g.enemies_root.get_children():
		if e != ally:
			e.queue_free()
	hero.iframe_left = 9999.0
	# The hero walks off to somewhere about 6-12 tiles away (a path, maybe through a door).
	var start: Vector2 = ally.global_position
	var dest := _walk_target(start, 150.0, 520.0)
	hero.host_teleport(dest)
	await da._wait_until(func(): return ally.global_position.distance_to(hero.global_position) < 110.0, 9.0)
	var d := ally.global_position.distance_to(hero.global_position)
	da.check(d < 130.0 and comp.teleports == 0 and start.distance_to(dest) >= 100.0, "it walks after the hero across the floor (%.0f px away, the hero went %.0f px)" % [d, start.distance_to(dest)])
	# A monster near the hero: the prisoner fights it.
	# Far enough that a ranged prisoner needn't back off first; time for a busy test machine.
	var mat: Vector2 = g.nearest_floor(hero.global_position + Vector2(110, 0))
	for k in 16:
		var c: Vector2 = g.nearest_floor(hero.global_position + Vector2.from_angle(TAU * k / 16.0) * 110.0)
		if Combat.instance.has_los(hero.global_position, c) and Combat.instance.has_los(ally.global_position, c) and not g.dungeon.is_safe(c):
			mat = c
			break
	var m: Enemy = g.spawn_monster("ghoul", mat, false)
	await da._wait(0.2)
	m.set_physics_process(false)  # it stands still, so only the prisoner deals the damage
	var hp0: float = m.health.hp
	await da._wait_until(func(): return not is_instance_valid(m) or m.health.hp < hp0, 14.0)
	da.check(not is_instance_valid(m) or m.health.hp < hp0, "the prisoner attacks a monster near its hero (%s)" % ally.def_id)
	if is_instance_valid(m):
		m.queue_free()
	# A monster next to the prisoner targets it.
	var m2: Enemy = g.spawn_monster("ghoul", g.nearest_floor(ally.global_position + Vector2(-50, 0)), false)
	await da._wait(0.3)
	m2.health.max_hp = 999999.0  # the prisoner fights back: the ghoul must live through the check
	m2.health.hp = 999999.0
	m2.add_threat(ally, 50.0)
	await da._wait(0.6)
	da.check(m2.target == ally, "monsters can make the prisoner their target")
	m2.queue_free()
	await da._wait(0.3)
	# Left far behind: it steps out beside the hero.
	var far := _walk_target(hero.global_position, 700.0, 1600.0)
	hero.host_teleport(far)
	await da._wait(1.5)
	da.check(comp.teleports > 0 and ally.global_position.distance_to(hero.global_position) < 120.0,
			"left far behind, it catches up beside the hero (%.0f px)" % ally.global_position.distance_to(hero.global_position))


## A floor spot between `lo` and `hi` px from `from` that a path reaches (in plain sight when one
## is: no door or prop to wait at on the way).
func _walk_target(from: Vector2, lo: float, hi: float) -> Vector2:
	var best := from
	for k in 300:
		var c0: Vector2 = g.nearest_floor(from + Vector2.from_angle(TAU * k / 37.0) * lerpf(lo, hi, float(k % 7) / 6.0))
		var d0 := c0.distance_to(from)
		if d0 >= lo and d0 <= hi and not g.dungeon.is_safe(c0) and Combat.instance.has_los(from, c0) and g.dungeon.props_in_radius((from + c0) / 2.0, d0 / 2.0).is_empty():
			return c0
	for r in g.layout.rooms:
		var c: Vector2 = g.nearest_floor(Vector2(Rect2i(r.rect).get_center()) * float(g.dungeon.tile))
		var dd := c.distance_to(from)
		if dd >= lo and dd <= hi and not g.dungeon.is_safe(c) and g.dungeon.find_path(from, c).size() > 1:
			return c
		# Never a secure room (monsters leave heroes alone there) and never past the catch-up range.
		if dd <= hi and not g.dungeon.is_safe(c) and absf(dd - (lo + hi) / 2.0) < absf(best.distance_to(from) - (lo + hi) / 2.0):
			best = c
	return best


## The vault: sealed; its lever shows on the map once seen; pulled, the vault opens and its chests
## give the vault loot.
func vault() -> void:
	var door: Node = g.dungeon.leaf_door("vault")
	da.check(door != null and door.sealed and door.monster_proof, "the vault door is sealed")
	if door == null:
		return
	await _near(door.interact_pos(), 40.0)
	g.host_interact(p, door)
	await da._wait(0.2)
	da.check(door.sealed and not door.is_open, "the sealed vault door doesn't open by hand")
	var lever: Node = g.dungeon.props["Event_vault_lever"]
	await _near(lever.global_position, 30.0)
	await da._wait_until(func(): return fe.lever_seen, 3.0)
	var mk: Array = g.dungeon.map_markers().filter(func(m): return m.get("id", "") == "vault" and m.has("link"))
	da.check(fe.lever_seen and not mk.is_empty(), "once the lever is seen the map links it to the vault")
	g.host_interact(p, lever)
	await da._wait(0.6)
	da.check(not door.sealed and door.is_open and fe.st("vault").get("open", false), "pulling the lever opens the vault")
	var chest: Node = g.dungeon.props["Event_vault_chest_0"]
	await _near(chest.global_position, 26.0)
	var n0: int = g.items_root.get_child_count()
	g.host_interact(p, chest)
	await da._wait(0.6)
	da.check(g.items_root.get_child_count() > n0, "a vault chest gives its loot")


## Kills the current wave for good (burrowers and bone piles get no second life).
func _kill_wave() -> void:
	for n in fe._wave_names.duplicate():
		var e: Node = g.enemies_root.get_node_or_null(NodePath(n))
		if e and is_instance_valid(e):
			kill(e)


func kill(e: Node) -> void:
	e.behaviors.clear()
	e.behavior_state = ""
	Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), e, 999999.0, {"damage_type": "true"})
	if is_instance_valid(e) and e.health.hp > 0.0:
		e.health.hp = 0.0
		e.on_death()


## The arena: stepping in warns, then bars every door; three waves, each warned before it comes;
## won, the bars lift and the chest rises; a lapsed trial lifts the bars too.
func arena() -> void:
	for e in g.enemies_root.get_children():
		if not e.get_meta("event_ally", false):
			e.queue_free()
	var c: Vector2 = fe.entries.arena.center
	# #112: stepping in and out again during the warning calls the sealing off.
	var outside: Vector2 = _outside_arena()
	await _near(c, 30.0)
	await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "sealing", 3.0)
	var n_enemies: int = g.enemies_root.get_child_count()
	p.host_teleport(outside)
	await da._wait(FloorEvents.num("arena", "seal_warn") + 1.5)
	da.check(str(fe.st("arena").get("state", "")) == "idle" and fe._arena_doors().all(func(d): return not d.locked) and fe._wave_names.is_empty()
			and g.enemies_root.get_child_count() <= n_enemies and fe.log.any(func(e): return e[0] == "seal_cancelled"),
		"a hero who leaves during the warning leaves the arena unsealed, with no wave (%s)" % fe.st("arena").get("state"))
	var t_in := Telegraph.now()
	await _near(c, 30.0)
	await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "fight", 8.0)
	da.check(Telegraph.now() - t_in >= FloorEvents.num("arena", "seal_warn") - 0.1, "back inside, the full warning runs again before the doors seal (%.1f s)" % (Telegraph.now() - t_in))
	var doors: Array = fe._arena_doors()
	da.check(Telegraph.lead_of("arena_seal") >= FloorEvents.num("arena", "seal_warn") - 0.05 and doors.all(func(d): return d.locked and not d.is_open),
		"the doors flash %.1f s (data %.1f), then the arena bars all %d doors" % [Telegraph.lead_of("arena_seal"), FloorEvents.num("arena", "seal_warn"), doors.size()])
	var d0: Node = doors[0] if not doors.is_empty() else null
	if d0:
		g.host_interact(p, d0)
		d0.host_set_open(true)
		da.check(not d0.is_open, "a barred door doesn't open for heroes or anyone")
	var waves: int = FloorEvents.def("arena").waves.size()
	var leads: Array = []
	for w in waves:
		await da._wait_until(func(): return int(fe.st("arena").get("wave", 0)) > w, 14.0)
		leads.append(Telegraph.lead_of("arena_wave_%d" % (w + 1)))
		await da._wait(0.3)
		_kill_wave()
		await da._wait(0.5)
	da.check(leads.size() == waves and leads.all(func(l): return l >= FloorEvents.num("arena", "spawn_warn") - 0.05),
		"%d waves, each warned before it comes (leads %s, data %.1f)" % [waves, leads, FloorEvents.num("arena", "spawn_warn")])
	await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "done", 6.0)
	var chest: Node = g.dungeon.props["Event_arena_chest"]
	da.check(str(fe.st("arena").get("state", "")) == "done" and doors.all(func(d): return not d.locked) and chest.visible and chest.interactable(),
		"won: the bars lift and the trial chest rises (%s %s %s %s)" % [fe.st("arena").get("state"), doors.map(func(d): return d.locked), chest.visible, chest.interactable()])
	var n0: int = g.items_root.get_child_count()
	await _near(chest.global_position, 24.0)
	g.host_interact(p, chest)
	await da._wait(0.6)
	da.check(g.items_root.get_child_count() > n0 + 1, "the trial chest pays out")


## A floor point just outside the arena room (#112), near one of its doors.
func _outside_arena() -> Vector2:
	var r: Rect2i = fe.room_of("arena")
	for door in fe._arena_doors():
		var dc: Vector2 = Rect2(door.world_rect).get_center()
		for off in [Vector2(0, 48), Vector2(0, -48), Vector2(48, 0), Vector2(-48, 0)]:
			var q: Vector2 = dc + off
			var cell: Vector2i = g.dungeon.cell_of(q)
			if DungeonGenerator.walkable(g.dungeon.cell_at(cell)) and not r.grow(1).has_point(cell):
				return q
	return g.nearest_floor(g.layout.start)


func tracker_and_map() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var tr: EventTracker = hud.event_tracker
	da.check(tr.lines.size() == 5 and tr.lines.has("arena") and str(tr.lines.arena) == Loc.t("The arena is won"), "the HUD tracker has a line for each found event (%s)" % [tr.lines])
	var ids: Array = g.dungeon.map_markers().filter(func(m): return m.kind == "event").map(func(m): return m.id)
	da.check(ids.size() >= 5, "every found event has its map marker (%s)" % [ids])


## #55: the events' state is saved with the floor; a trial running at the save starts over.
func saved() -> void:
	var snap: Dictionary = FloorState.capture(g, {})
	var ev: Dictionary = snap.get("events", {})
	da.check(snap.get("events_list", []).size() == 5 and ev.get("vault", {}).get("open", false) and str(ev.get("arena", {}).get("state", "")) == "done"
		and str(ev.get("prisoner", {}).get("state", "")) == "freed", "the floor's save keeps every event's state")
	var running := ev.duplicate(true)
	running.arena.state = "fight"
	fe.host_restore(running)
	da.check(str(fe.st("arena").get("state", "")) == "idle" and fe.st("vault").get("open", false), "restored: a running trial starts over, the open vault stays open")


func plain_chest() -> void:
	var node: Node = g.dungeon.props["Event_cursed_chest"]
	await _near(node.global_position, 26.0)
	var n0: int = g.items_root.get_child_count()
	g.host_interact(p, node)
	await da._wait(0.6)
	da.check(str(fe.st("cursed_chest").get("state", "")) == "opened" and g.items_root.get_child_count() > n0 + 1 and not fe.log.any(func(e): return e[0] == "breath"),
		"a cursed chest that isn't a mimic never breathes and just opens with its treasure")


func prisoner_reward() -> void:
	fe.state.prisoner.key = true
	var cage: Node = g.dungeon.props["Event_prisoner"]
	await _near(cage.global_position, 34.0)
	var n0: int = g.items_root.get_child_count()
	g.host_interact(p, cage)
	await da._wait(0.8)
	da.check(str(fe.st("prisoner").get("state", "")) == "freed" and g.items_root.get_child_count() > n0 and not g.enemies_root.get_children().any(func(e): return e.get_meta("event_ally", false)),
		"a prisoner who rewards: loot for the rescuer, no ally")


# =========================================================================================
# LAN
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	GameState.set_meta("force_events", "arena,shrine,cursed_chest")
	GameState.set_meta("test_mimic", true)
	g.start_floor(3)
	await da._wait(2.5)
	p = da._local()
	fe = g.events
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	c.iframe_left = 9999.0
	p.iframe_left = 9999.0
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_layout", fe.entries.keys()])
	await da._wait(1.0)
	# The client kneels at the shrine and strikes a bargain.
	var sh: Node = g.dungeon.props["Event_shrine"]
	c.host_teleport(g.nearest_floor(sh.global_position + Vector2(0, 30)))
	await da._wait(0.8)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_shrine", null])
	await da._wait_until(func(): return fe.st("shrine").get("taken", {}).has(str(c.peer_id)), 6.0)
	var bid := str(fe.st("shrine").taken.get(str(c.peer_id), ""))
	var buff := ""
	for b in FloorEvents.def("shrine").bargains:
		if str(b.id) == bid:
			buff = str(b.buff)
	da.check(not bid.is_empty() and c.status.has(buff), "host: the client's bargain went through the RPC (%s)" % bid)
	# The client opens the cursed chest: everyone sees it wake.
	var ch: Node = g.dungeon.props["Event_cursed_chest"]
	c.host_teleport(g.nearest_floor(ch.global_position + Vector2(0, 26)))
	await da._wait(0.8)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_chest", ch.get_path()])
	await da._wait_until(func(): return str(fe.st("cursed_chest").get("state", "")) == "mimic", 5.0)
	da.check(str(fe.st("cursed_chest").get("state", "")) == "mimic", "host: the client woke the mimic")
	for e in g.enemies_root.get_children():
		e.queue_free()
	# #112: the client steps in and back out during the warning: the sealing is called off for both.
	c.host_teleport(g.nearest_floor(fe.entries.arena.center + Vector2(0, 20)))
	await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "sealing", 3.0)
	c.host_teleport(_outside_arena())
	await da._wait_until(func(): return fe.log.any(func(e): return e[0] == "seal_cancelled"), 3.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_arena_cancel", null])
	await da._wait(1.0)
	# The arena: the client steps in; both see the seal and the waves.
	c.host_teleport(g.nearest_floor(fe.entries.arena.center + Vector2(0, 20)))
	await da._wait_until(func(): return not fe._wave_names.is_empty(), 12.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_arena", null])
	await da._wait(2.0)
	for k in 3:
		await da._wait_until(func(): return not fe._wave_names.is_empty() or str(fe.st("arena").get("state", "")) == "done", 12.0)
		_kill_wave()
		await da._wait(0.6)
	await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "done", 8.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_won", null])
	await da._wait(2.0)
	# #99: a prisoner freed by the client follows the client's hero; the client sees it beside it.
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var ally: Enemy = fe._spawn_ally(g.nearest_floor(c.global_position + Vector2(0, 30)), c.peer_id)
	await da._wait(0.5)
	var dest := _walk_target(c.global_position, 200.0, 520.0)
	c.host_teleport(dest)
	await da._wait_until(func(): return is_instance_valid(ally) and ally.global_position.distance_to(c.global_position) < 110.0, 9.0)
	da.check(is_instance_valid(ally) and ally.global_position.distance_to(c.global_position) < 130.0, "host: the prisoner follows the client's hero who freed it")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ev_ally", null])
	await da._wait(1.0)
	for k in ["force_events", "test_mimic"]:
		GameState.remove_meta(k)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	fe = g.events
	match cmd:
		"ev_ally":
			var me: Player = da._local()
			var allies: Array = g.enemies_root.get_children().filter(func(e): return e is Enemy and e.team == Actor.Team.PLAYERS)
			var near: bool = not allies.is_empty() and allies[0].global_position.distance_to(me.global_position) < 140.0
			da.check(near and not allies[0].look.is_empty(), "client: the freed prisoner walks beside my hero, in its hero look")
			return
		"ev_layout":
			da.check(fe.entries.keys() == arg and g.dungeon.props.has("Event_shrine"), "client: the same events on my floor (%s)" % [fe.entries.keys()])
		"ev_shrine":
			p.request_interact.rpc_id(1, g.dungeon.props["Event_shrine"].get_path())
			await da._wait_until(func(): return da.get_tree().get_first_node_in_group("hud")._overlay != null, 3.0)
			var panel: Node = da.get_tree().get_first_node_in_group("hud")._overlay
			da.check(panel != null and panel.get("cards") != null and panel.cards.size() == 2, "client: the shrine's cards open for me")
			if panel and panel.get("cards") and not panel.cards.is_empty():
				panel._choose(panel.cards.keys()[0])
		"ev_chest":
			p.request_interact.rpc_id(1, NodePath(arg))
			await da._wait(0.4)
			da.check(fe.log.any(func(e): return e[0] == "wake") and Telegraph.log.has("mimic"), "client: I see the chest shudder before the mimic wakes")
		"ev_arena_cancel":
			da.check(fe.log.any(func(e): return e == ["alarm", "cancel"]) and str(fe.st("arena").get("state", "")) == "idle" and fe._arena_doors().all(func(d): return not d.locked)
					and fe._seal_marks.is_empty(), "client: leaving during the warning called the sealing off (no markers, doors open)")
			return
		"ev_arena":
			da.check(Telegraph.log.has("arena_seal") and fe._arena_doors().all(func(d): return d.locked) and str(fe.st("arena").get("state", "")) == "fight",
				"client: the arena's warning came and its doors are barred")
			da.check(Telegraph.log.has("arena_wave_1"), "client: the first wave was warned")
		"ev_won":
			da.check(str(fe.st("arena").get("state", "")) == "done" and g.dungeon.props["Event_arena_chest"].visible, "client: the arena is won and its chest rose")
