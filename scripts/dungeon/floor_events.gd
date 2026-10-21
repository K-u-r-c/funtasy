class_name FloorEvents
extends Node
## #72 Special rooms and events (data/floor_events.json), one node in Game. The generator places
## them (layout.events); this node runs them, host-authoritative, and shows them on every peer:
## - Arena: a hero steps inside -> the doors flash and seal after `seal_warn` (Telegraph
##   "arena_seal") -> waves, each announced by rifts `spawn_warn` before it ("arena_wave_<n>"),
##   a wave counter and countdown on the HUD -> the reward chest rises and the bars lift. With no
##   living hero inside for `fail_time` the trial lapses: the bars lift and it can be tried again.
## - Vault: a sealed leaf; its lever stands in another room; once the lever is seen the map links
##   it to the vault door. Pulling it opens the vault (its chests hold the vault loot).
## - Shrine: a hero kneels -> two bargains on choice cards (a floor-long buff and its price: health
##   now, a floor-long curse, or the nearest room's monsters grow stronger, marked at once).
## - Cursed chest: maybe a mimic (seeded). A mimic breathes now and then (the subtle tell); opened,
##   it shudders and creaks for `wake_warn` (Telegraph "mimic") before it bites.
## - Prisoner: a caged adventurer; a guard elite carries the cell key; freed, they fight beside the
##   heroes for the floor or reward their rescuer (seeded).
##
## RPCs (on this node, the same path on every peer): request_bargain(id): owner -> host,
## reliable. _sync(state), _open_shrine(offers), _arena_alarm(kind, data), _mimic_wake(),
## _notice(text, args): host -> peers, reliable.

signal changed

var game: Node
var state: Dictionary = {}  ## every peer (replicated): event id -> its state
var entries: Dictionary = {}  ## every peer: event id -> layout entry
var seen: Dictionary = {}  ## local: event ids this peer has found (the tracker and the map)
var lever_seen := false  ## local: the vault's lever has been in sight (its link shows)
var log: Array = []  ## every peer: [kind, ...] of what happened (tests)
var _rng := RandomNumberGenerator.new()
var _wave_names: Array = []  ## host: the current arena wave's monsters
var _outside := 0.0  ## host: how long no living hero has been inside the running arena
var _tell_t := 0.0
var _chest_shown := false  ## every peer: the arena's chest has risen


static func def(id: String) -> Dictionary:
	return GameData.floor_events.get("events", {}).get(id, {})


static func num(id: String, key: String, fallback: float = 0.0) -> float:
	return float(def(id).get(key, fallback))


# =========================================================================================
# Every peer
# =========================================================================================


## After Dungeon.build on every peer: the floor's events (the host then rolls their state).
func setup_floor(layout: Dictionary) -> void:
	entries.clear()
	state.clear()
	seen.clear()
	lever_seen = false
	_chest_shown = false
	log.clear()
	_wave_names.clear()
	for e in layout.get("events", []):
		entries[str(e.id)] = e
	if multiplayer.is_server():
		_host_roll(int(layout.get("seed", 0)))


## Inside the arena's room (#71 hunters never step out there).
func in_arena(pos: Vector2) -> bool:
	return entries.has("arena") and room_of("arena").grow(1).has_point(game.dungeon.cell_of(pos))


func has_event(id: String) -> bool:
	return entries.has(id)


func st(id: String) -> Dictionary:
	return state.get(id, {})


## The room rect (cells) of an event, or an empty rect.
func room_of(id: String) -> Rect2i:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty() or not game.layout.has("rooms"):
		return Rect2i()
	return game.layout.rooms[int(e.room)].rect


func _process(delta: float) -> void:
	if game == null or game.dungeon == null or entries.is_empty():
		return
	_update_seen()
	_update_visuals(delta)
	if multiplayer.is_server():
		_host_tick(delta)


## Local: an event is found when any cell of its room (the vault: its door) has been seen; the
## first sight plays its tell sound and a line in the feed.
func _update_seen() -> void:
	var d: Node = game.dungeon
	for id in entries:
		if seen.has(id):
			continue
		var found := false
		if id == "vault":
			var door: Node = d.leaf_door("vault")
			if door:
				for c in door.cells:
					found = found or d.is_discovered(c)
		else:
			var r := room_of(id)
			var pos: Vector2 = entries[id].get("pos", entries[id].get("center", Vector2.ZERO))
			found = game.visibility.is_cell_visible(d.cell_of(pos)) if game.get("visibility") else false
			if not found and r.size != Vector2i.ZERO:
				found = d.is_discovered(d.cell_of(pos))
		if found:
			seen[id] = true
			AudioManager.play_sfx("event_found", 0.0)
			EventBus.hud_message.emit(Loc.f("You found: %s", [Loc.t(str(def(id).get("name", id)))]), Color.from_string(str(def(id).get("color", "#ffffff")), Color.WHITE))
			changed.emit()
	if entries.has("vault") and not lever_seen:
		var lc: Vector2i = d.cell_of(entries.vault.lever)
		if game.visibility.is_cell_visible(lc):
			lever_seen = true
			game.add_map_ping(entries.vault.lever, Color.from_string(str(def("vault").color), Color.GOLD), 15.0)
			EventBus.hud_message.emit(Loc.t("This lever opens the sealed vault - marked on your map"), Color.from_string(str(def("vault").color), Color.GOLD))
			changed.emit()


## Local visuals that follow the state: the arena sigil's phase, a mimic's breath.
func _update_visuals(delta: float) -> void:
	var sig: Node = game.dungeon.get_node_or_null("ArenaSigil")
	if sig:
		sig.phase = {"idle": "idle", "sealing": "sealing", "fight": "fight", "done": "done"}.get(str(st("arena").get("state", "idle")), "idle")
	var cs: Dictionary = st("cursed_chest")
	if cs.get("tell", false) and str(cs.get("state", "")) == "closed":
		_tell_t -= delta
		if _tell_t <= 0.0:
			var span: Array = def("cursed_chest").get("tell_every", [3.0, 6.0])
			_tell_t = randf_range(float(span[0]), float(span[1]))
			var chest: Node = game.dungeon.props.get("Event_cursed_chest")
			if chest and is_instance_valid(chest) and chest.visible:
				_breathe(chest)


## The mimic's tell: the lid lifts a hair and settles, and a drop of red glints at the seam.
func _breathe(chest: Node2D) -> void:
	log.append(["breath"])
	var spr: Sprite2D = chest.get("_sprite")
	if spr == null:
		return
	var tw := chest.create_tween()
	tw.tween_property(spr, "scale", Vector2(1.03, 0.97), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "scale", Vector2(0.99, 1.02), 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "scale", Vector2.ONE, 0.3)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.one_shot = true
	p.amount = 2
	p.lifetime = 0.9
	p.direction = Vector2(0, 1)
	p.spread = 10.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector2(0, 30)
	p.color = Color(0.85, 0.1, 0.15)
	p.position = Vector2(4, -14)
	chest.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# =========================================================================================
# Host
# =========================================================================================


func _host_roll(floor_seed: int) -> void:
	_rng.seed = floor_seed + 4049
	for id in entries:
		match id:
			"arena":
				state.arena = {"state": "idle", "wave": 0, "at": -1.0, "warned": false}
			"vault":
				state.vault = {"open": false}
			"shrine":
				var pool: Array = def("shrine").get("bargains", []).map(func(b): return str(b.id))
				var offers: Array = []
				for i in mini(int(num("shrine", "offers", 2)), pool.size()):
					offers.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
				state.shrine = {"offers": offers, "taken": {}, "tougher": -1}
			"cursed_chest":
				var mimic := _rng.randf() < num("cursed_chest", "mimic_chance", 0.5)
				if GameState.has_meta("test_mimic"):
					mimic = bool(GameState.get_meta("test_mimic"))
				state.cursed_chest = {"state": "closed", "tell": mimic}
			"prisoner":
				var outs: Dictionary = def("prisoner").get("outcomes", {"reward": 1})
				var keys: Array = outs.keys()
				keys.sort()
				var w: Array = keys.map(func(k): return float(outs[k]))
				var who: int = _rng.randi_range(0, def("prisoner").get("prisoners", [{}]).size() - 1)
				var outcome: String = keys[ItemGenerator._weighted_index(w, _rng)]
				if GameState.has_meta("test_prisoner"):
					outcome = str(GameState.get_meta("test_prisoner"))
				state.prisoner = {"state": "locked", "outcome": outcome, "who": who, "key": false}
	_sync.rpc(state)


## Host: the floor was continued from a save (#55): its events as they were. A trial that was
## running when the game was saved starts over (its monsters were saved as ordinary monsters).
func host_restore(saved: Dictionary) -> void:
	for id in saved:
		if not entries.has(id):
			continue
		state[id] = saved[id].duplicate(true)
	if state.has("arena") and str(state.arena.get("state", "")) in ["sealing", "fight"]:
		state.arena = {"state": "idle", "wave": 0, "at": -1.0, "warned": false}
	var ps := st("prisoner")
	if str(ps.get("state", "")) == "freed" and str(ps.get("outcome", "")) == "ally" and game.dungeon.props.has("Event_prisoner"):
		_spawn_ally(game.dungeon.props["Event_prisoner"].global_position + Vector2(0, 22))
	_sync.rpc(state)
	_apply_restored.rpc()


## Host -> all (reliable, after _sync): props shown as the restored state says (the opened
## chest, an open cage, the risen trial chest, the open vault).
@rpc("authority", "call_local", "reliable")
func _apply_restored() -> void:
	var d: Node = game.dungeon
	if str(st("arena").get("state", "")) == "done" and d.props.has("Event_arena_chest"):
		_chest_shown = true
		d.props["Event_arena_chest"].reveal(false)
	if st("vault").get("open", false):
		var door: Node = d.leaf_door("vault")
		if door and door.sealed:
			door.restore_state(true, false, false)
		if d.props.has("Event_vault_lever"):
			d.props["Event_vault_lever"].set_opened()
	var cstate := str(st("cursed_chest").get("state", ""))
	if cstate in ["mimic", "dead", "opened"] and d.props.has("Event_cursed_chest"):
		if cstate == "opened":
			d.props["Event_cursed_chest"].set_opened()
		else:
			d.props["Event_cursed_chest"].visible = false
			d.props["Event_cursed_chest"].collision_layer = 0
	if str(st("prisoner").get("state", "")) == "freed" and d.props.has("Event_prisoner"):
		d.props["Event_prisoner"].set_opened()


func save_state() -> Dictionary:
	return state.duplicate(true)


func _alive_heroes() -> Array:
	return game.players_root.get_children().filter(func(p): return p.life_state == Player.Life.ALIVE)


func _host_tick(delta: float) -> void:
	if state.has("arena"):
		_arena_tick(delta)


## --- Arena -----------------------------------------------------------------------------------


func _arena_inside(p: Node) -> bool:
	return room_of("arena").grow(-1).has_point(game.dungeon.cell_of(p.global_position))


func _arena_doors() -> Array:
	var out: Array = []
	for i in entries.arena.get("doors", []):
		if int(i) < game.dungeon.doors.size():
			out.append(game.dungeon.doors[int(i)])
	return out


func _arena_tick(delta: float) -> void:
	var a: Dictionary = state.arena
	var t: float = game.floor_time
	match str(a.state):
		"idle":
			if _alive_heroes().any(func(p): return _arena_inside(p)):
				a.state = "sealing"
				a.at = t + num("arena", "seal_warn", 3.0)
				Telegraph.warned("arena_seal")
				_arena_alarm.rpc("seal", {"lead": num("arena", "seal_warn", 3.0)})
				_sync.rpc(state)
		"sealing":
			if t < float(a.at):
				return
			# Never shut a door on someone standing in it: wait until the doorways are clear.
			for door in _arena_doors():
				for actor in game.combat.all_actors():
					if door.world_rect.grow(4).has_point(actor.global_position):
						return
			for door in _arena_doors():
				door.host_set_locked(true)
			Telegraph.fired("arena_seal")
			log.append(["sealed"])
			a.state = "fight"
			a.wave = 0
			# The first wave keeps its full warning too.
			a.at = t + maxf(num("arena", "first_wave", 1.5), num("arena", "spawn_warn", 2.0))
			a.warned = false
			_outside = 0.0
			_sync.rpc(state)
		"fight":
			# The trial lapses when nobody living is inside to fight it.
			if not _alive_heroes().any(func(p): return _arena_inside(p)):
				_outside += delta
				if _outside >= num("arena", "fail_time", 8.0):
					_arena_end(false)
					return
			else:
				_outside = 0.0
			var waves: Array = def("arena").get("waves", [])
			_wave_names = _wave_names.filter(func(n): return game.enemies_root.has_node(NodePath(n)) and game.enemies_root.get_node(NodePath(n)).health.hp > 0.0)
			if float(a.at) < 0.0:
				if _wave_names.is_empty():
					if int(a.wave) >= waves.size():
						_arena_end(true)
					else:
						a.at = t + num("arena", "wave_gap", 6.0)
						a.warned = false
						_sync.rpc(state)
				return
			var spawn_warn := num("arena", "spawn_warn", 2.0)
			if not a.warned and t >= float(a.at) - spawn_warn:
				a.warned = true
				a.spots = _wave_spots(int(waves[int(a.wave)].get("count", 3)) + int(waves[int(a.wave)].get("elites", 0)))
				Telegraph.warned("arena_wave_%d" % (int(a.wave) + 1))
				_arena_alarm.rpc("wave", {"wave": int(a.wave) + 1, "of": waves.size(), "spots": a.spots, "lead": spawn_warn})
				_sync.rpc(state)
			if t >= float(a.at):
				_spawn_wave(waves[int(a.wave)], a.get("spots", []))
				Telegraph.fired("arena_wave_%d" % (int(a.wave) + 1))
				a.wave = int(a.wave) + 1
				a.at = -1.0
				_sync.rpc(state)


## Spots for a wave inside the arena (away from the heroes and the walls), seeded.
func _wave_spots(n: int) -> Array:
	var r := room_of("arena")
	var out: Array = []
	for i in n * 6:
		if out.size() >= n:
			break
		var c := Vector2i(_rng.randi_range(r.position.x + 1, r.end.x - 2), _rng.randi_range(r.position.y + 1, r.end.y - 2))
		var pos: Vector2 = game.dungeon.cell_center(c)
		if game.dungeon.cell_at(c) != DungeonGenerator.CELL_FLOOR:
			continue
		if _alive_heroes().any(func(p): return p.global_position.distance_to(pos) < 70.0):
			continue
		if out.any(func(o): return o.distance_to(pos) < 40.0):
			continue
		out.append(pos)
	return out


func _spawn_wave(w: Dictionary, spots: Array) -> void:
	var ids: Array = []
	var ws: Array = []
	for m in game.floor_def.get("monsters", []):
		if DungeonGenerator.spawnable(str(m.id), game.depth) and not GameData.monsters.get(str(m.id), {}).get("role", "") in ["illusion", "boss_part"]:
			ids.append(str(m.id))
			ws.append(float(m.weight))
	if ids.is_empty():
		return
	var n := maxi(game.players_root.get_child_count(), 1)
	var count := roundi(float(w.get("count", 3)) * (1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (n - 1)))
	var elites := int(w.get("elites", 0))
	var mods: Array = GameData.elite_modifiers.keys()
	mods.sort()
	for i in count + elites:
		var pos: Vector2 = spots[i % maxi(spots.size(), 1)] if not spots.is_empty() else entries.arena.center
		pos += Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-8, 8))
		var extra := {}
		if i >= count:
			extra.elite = [mods[_rng.randi_range(0, mods.size() - 1)]]
		var e: Node = game.spawn_monster(ids[ItemGenerator._weighted_index(ws, _rng)], pos, false, extra)
		if e == null:
			continue
		e.set_meta("arena", true)
		_wave_names.append(str(e.name))
		for p in _alive_heroes():
			if _arena_inside(p):
				e.add_threat(p, 5.0)
	log.append(["wave", count + elites])


func _arena_end(won: bool) -> void:
	var a: Dictionary = state.arena
	for door in _arena_doors():
		door.host_set_locked(false)
	_wave_names.clear()
	if won:
		a.state = "done"
		a.at = -1.0
		log.append(["won"])
		game.broadcast_message.rpc("The arena is won - its chest rises", "#f0c040", [])
		_arena_alarm.rpc("won", {})
	else:
		a.state = "idle"
		a.wave = 0
		a.at = -1.0
		log.append(["lapsed"])
		game.broadcast_message.rpc("The arena's trial lapses - the bars lift", "#e0503a", [])
		_arena_alarm.rpc("lapsed", {})
	_sync.rpc(state)


## --- Interactions ------------------------------------------------------------------------------


## Host: does `node` belong to an event (its props and the vault door)?
func handles(node: Node) -> bool:
	if node == null or not node.get("def") is Dictionary:
		return node != null and node.has_method("host_set_open") and str(node.get("kind")) == "vault" and node.sealed
	return str(node.def.get("event", "")) in ["shrine", "cursed_chest", "prisoner", "vault"]


func host_interact(p: Player, node: Node) -> void:
	if node.has_method("host_set_open"):
		_notice.rpc_id(p.peer_id, "Sealed: a lever somewhere on this floor opens the vault")
		game.combat.fx.sound.rpc("ui_error", node.interact_pos())
		return
	match str(node.def.get("event", "")):
		"shrine":
			_shrine(p, node)
		"cursed_chest":
			_open_cursed(p, node)
		"prisoner":
			_free_prisoner(p, node)
		"vault":
			_pull_vault_lever(p, node)


func _pull_vault_lever(p: Player, lever: Node) -> void:
	if st("vault").get("open", false):
		return
	state.vault.open = true
	game.dungeon.open_chest.rpc(lever.prop_id)
	game.combat.fx.sound.rpc("floodgate", lever.global_position)
	var door: Node = game.dungeon.leaf_door("vault")
	if door:
		door.host_unseal()
		game.combat.fx.sound.rpc("vault_open", door.interact_pos())
		_ping.rpc(door.interact_pos(), str(def("vault").color), 15.0)
	log.append(["vault_open"])
	game.broadcast_message.rpc("%s pulls the lever - somewhere a vault grinds open", "#f0c040", [p.display_name])
	_sync.rpc(state)


func _shrine(p: Player, _node: Node) -> void:
	var taken: Dictionary = st("shrine").get("taken", {})
	if taken.has(str(p.peer_id)):
		_notice.rpc_id(p.peer_id, "The idol has already taken its price from you")
		return
	_open_shrine.rpc_id(p.peer_id, st("shrine").get("offers", []))


## Owner -> host: the hero strikes bargain `id` ("" = walks away).
@rpc("any_peer", "call_local", "reliable")
func request_bargain(id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p: Player = game.player_by_peer(peer)
	var shrine: Node = game.dungeon.props.get("Event_shrine")
	if p == null or shrine == null or p.life_state != Player.Life.ALIVE or not state.has("shrine"):
		return
	if p.global_position.distance_to(shrine.global_position) > float(GameData.bal("world.interact_range")) + 40.0:
		return
	var sh: Dictionary = state.shrine
	if sh.taken.has(str(peer)) or id.is_empty() or not sh.offers.has(id):
		return
	var b: Dictionary = {}
	for x in def("shrine").get("bargains", []):
		if str(x.id) == id:
			b = x
	if b.is_empty():
		return
	sh.taken[str(peer)] = id
	var ctx: Dictionary = Combat.instance.make_ctx(p, {"id": "shrine", "school": "spell"})
	p.status.apply(str(b.buff), 99999.0, 0.0, ctx)
	match str(b.cost):
		"hp":
			p.health.hp = maxf(p.health.hp * (1.0 - float(b.get("hp_pct", 0.3))), 1.0)
			game.combat.fx.number.rpc(p.global_position, "-%d%%" % roundi(float(b.get("hp_pct", 0.3)) * 100.0), "damage")
		"curse":
			p.status.apply(str(b.curse), 99999.0, 0.0, ctx)
		"tougher":
			_empower_nearest_room(shrine.global_position)
	game.combat.fx.sound.rpc("shrine_bargain", shrine.global_position)
	game.combat.fx.actor_fx.rpc(p.get_path(), "buff")
	log.append(["bargain", id, peer])
	game.broadcast_message.rpc("%s strikes a bargain with the idol: %s", "#a66cff", [p.display_name, str(b.name)])
	_sync.rpc(state)


## The shrine's price: the monsters of the nearest room that still has some grow stronger, and
## the room is marked (a map ping and the monsters' red aura) before anyone walks in.
func _empower_nearest_room(from: Vector2) -> void:
	var best := -1
	var best_d := INF
	var by_room := {}
	for e in game.enemies_root.get_children():
		if e.is_boss or e.health.hp <= 0.0:
			continue
		for i in game.layout.rooms.size():
			if game.layout.rooms[i].role == "normal" and Rect2i(game.layout.rooms[i].rect).has_point(game.dungeon.cell_of(e.global_position)):
				by_room.get_or_add(i, []).append(e)
	for i in by_room:
		var c: Vector2 = game.dungeon.cell_center(Rect2i(game.layout.rooms[i].rect).get_center())
		if i == int(entries.shrine.room):
			continue
		var dd := c.distance_to(from)
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0:
		return
	state.shrine.tougher = best
	var tg: Dictionary = def("shrine").get("tougher", {})
	Telegraph.warned("shrine_tougher")
	for e in by_room[best]:
		e.status.apply("shrine_empowered", 99999.0, 0.0, Combat.instance.make_ctx(e, {"id": "shrine", "school": "spell"}))
	Telegraph.fired("shrine_tougher")
	var rc: Vector2 = game.dungeon.cell_center(Rect2i(game.layout.rooms[best].rect).get_center())
	_ping.rpc(rc, UITheme.WARN.to_html(false), 20.0)
	log.append(["tougher", best, by_room[best].size(), tg])


func _open_cursed(p: Player, chest: Node) -> void:
	var cs: Dictionary = st("cursed_chest")
	if str(cs.get("state", "")) != "closed":
		return
	if cs.get("tell", false):
		cs.state = "waking"
		Telegraph.warned("mimic")
		_mimic_wake.rpc(num("cursed_chest", "wake_warn", 1.3))
		_sync.rpc(state)
		await get_tree().create_timer(num("cursed_chest", "wake_warn", 1.3)).timeout
		if not is_instance_valid(chest) or state.get("cursed_chest", {}) != cs:
			return
		cs.state = "mimic"
		# The mimic is an elite of its own, with the chest's extra weight.
		var mods: Array = GameData.elite_modifiers.keys()
		mods.sort()
		var m: Node = game.spawn_monster(str(def("cursed_chest").get("mimic", "chest_mimic")), chest.global_position, false,
			{"elite": [mods[_rng.randi_range(0, mods.size() - 1)]], "hp_x": num("cursed_chest", "mimic_hp_mult", 2.0), "dmg_x": num("cursed_chest", "mimic_damage_mult", 1.0)})
		if m:
			m.set_meta("event_mimic", true)
			m.add_threat(p, 30.0)
		Telegraph.fired("mimic")
		log.append(["mimic"])
		game.broadcast_message.rpc("The chest was a mimic!", "#c0303a", [])
		_sync.rpc(state)
	else:
		cs.state = "opened"
		game.dungeon.open_chest.rpc(chest.prop_id)
		game.combat.fx.sound.rpc("curse_lift", chest.global_position)
		game.loot.roll_and_drop(str(def("cursed_chest").get("loot", "cursed")), chest.global_position + Vector2(0, 18))
		log.append(["cursed_opened"])
		_sync.rpc(state)


## Host (Game, on a kill): the mimic fell - the cursed chest's treasure spills out.
func host_enemy_killed(e: Node) -> bool:
	if e.get_meta("event_mimic", false) and state.has("cursed_chest"):
		state.cursed_chest.state = "dead"
		game.loot.roll_and_drop(str(def("cursed_chest").get("loot", "cursed")), e.global_position)
		log.append(["mimic_dead"])
		_sync.rpc(state)
		return true
	if e.get("guard") and state.has("prisoner"):
		game.loot.drop_item(cell_key_item(), e.global_position + Vector2(12, 6))
		game.broadcast_message.rpc("The guard drops the cell key", "#6fb4ff", [])
		log.append(["key_dropped"])
	return false


func cell_key_item() -> Dictionary:
	return {"kind": "cell_key", "base": "cell_key", "name": "Cell Key", "icon": "items.cell_key", "rarity": 4,
		"uid": ItemGenerator.new_uid(game.loot.rng)}


## Host (LootManager): a hero picked up the cell key; the party holds it.
func host_cell_key(p: Player) -> void:
	if not state.has("prisoner"):
		return
	state.prisoner.key = true
	game.combat.fx.sound.rpc("key_unlock", p.global_position)
	game.broadcast_message.rpc("%s has the cell key - free the prisoner", "#6fb4ff", [p.display_name])
	_sync.rpc(state)


func prisoner_def() -> Dictionary:
	var list: Array = def("prisoner").get("prisoners", [])
	var i := int(st("prisoner").get("who", 0))
	return list[clampi(i, 0, list.size() - 1)] if not list.is_empty() else {}


func _free_prisoner(p: Player, cage: Node) -> void:
	var ps: Dictionary = st("prisoner")
	if str(ps.get("state", "")) != "locked":
		return
	if not ps.get("key", false):
		_notice.rpc_id(p.peer_id, "Locked: a guard on this floor carries the key (marked with a key)")
		game.combat.fx.sound.rpc("ui_error", cage.global_position)
		return
	ps.state = "freed"
	game.dungeon.open_chest.rpc(cage.prop_id)
	game.combat.fx.sound.rpc("cage_open", cage.global_position)
	var pd := prisoner_def()
	log.append(["freed", str(ps.outcome)])
	if str(ps.outcome) == "ally":
		_spawn_ally(cage.global_position + Vector2(0, 22), p.peer_id)
		game.broadcast_message.rpc("%s is free and fights beside you", "#6fb4ff", [str(pd.get("name", ""))])
	else:
		game.loot.roll_and_drop(str(def("prisoner").get("loot", "prisoner")), cage.global_position + Vector2(0, 24))
		game.broadcast_message.rpc("%s is free and rewards %s", "#6fb4ff", [str(pd.get("name", "")), p.display_name])
	_sync.rpc(state)


## Host: the freed prisoner joins the heroes' side for the rest of the floor, following the hero
## who freed it (#99; `leader` 0: the nearest hero).
func _spawn_ally(at: Vector2, leader: int = 0) -> Node:
	var pd := prisoner_def()
	var ally: Node = game.spawn_monster("%s_%s" % [str(def("prisoner").get("ally", "freed_prisoner")), str(pd.get("class", "warrior"))],
		at, false, {"team": Actor.Team.PLAYERS, "look": prisoner_look(pd, true), "display": str(pd.get("name", ""))})
	if ally:
		ally.set_meta("event_ally", true)
		ally.set_meta("leader_peer", leader)
	return ally


## A prisoner's look: the hero body of its gender, in rags (the underwear), with its class's
## starting weapon once freed.
static func prisoner_look(pd: Dictionary, armed: bool) -> Dictionary:
	var inv := Inventory.new()
	if armed:
		inv.equipment = GameState.starting_equipment(str(pd.get("class", "warrior")))
	return {"gender": CharacterSprite.valid_gender(str(pd.get("gender", "male"))), "appearance": inv.appearance()}


## Host, at the floor's start (Game): the prisoner's guard - an elite near the cage that isn't the
## Gold Key carrier, or the nearest pack's first monster made an elite. Returns the spawn slot.
func pick_guard(host_layout: Dictionary, elites: Dictionary) -> Vector2i:
	if not entries.has("prisoner"):
		return Vector2i(-1, -1)
	var at: Vector2 = entries.prisoner.pos
	var best := Vector2i(-1, -1)
	var best_d := INF
	for k in elites:
		if elites[k].get("key", false):
			continue
		var m: Dictionary = host_layout.spawns[k.x].monsters[k.y]
		var dd: float = Vector2(m.pos).distance_to(at)
		if dd < best_d:
			best_d = dd
			best = k
	if best.x >= 0:
		return best
	for gi in host_layout.spawns.size():
		var g: Dictionary = host_layout.spawns[gi]
		if g.monsters.is_empty():
			continue
		var dd2: float = Vector2(g.monsters[0].pos).distance_to(at)
		if dd2 < best_d:
			best_d = dd2
			best = Vector2i(gi, 0)
	return best


# =========================================================================================
# Host -> peers
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _sync(new_state: Dictionary) -> void:
	state = new_state
	# The chest stays open-jawed until the mimic itself stands there.
	if str(st("cursed_chest").get("state", "")) in ["mimic", "dead"] and game and game.dungeon and game.dungeon.props.has("Event_cursed_chest"):
		var ch: Node2D = game.dungeon.props["Event_cursed_chest"]
		ch.visible = false
		ch.collision_layer = 0
	# The captive appears once its identity is known (the first sync of the floor).
	if state.has("prisoner") and game and game.dungeon and game.dungeon.props.has("Event_prisoner"):
		var cage: Node2D = game.dungeon.props["Event_prisoner"]
		if cage.get_node_or_null("PrisonerNpc") == null and str(state.prisoner.get("state", "")) != "freed":
			var npc := PrisonerNpc.new()
			npc.setup(prisoner_def(), cage)
			cage.add_child(npc)
	# (The host's state is changed in place before it is sent, so compare with a local flag.)
	if not _chest_shown and str(st("arena").get("state", "")) == "done":
		_chest_shown = true
		var chest: Node = game.dungeon.props.get("Event_arena_chest") if game and game.dungeon else null
		if chest:
			chest.reveal(true)
			AudioManager.play_sfx_at("arena_won", chest.global_position)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _open_shrine(offers: Array) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_shrine"):
		hud.open_shrine(offers)


## Host -> all: the arena's dangerous moments, shown before they happen: "seal" (the doors flash
## and a countdown), "wave" (rifts at the spawn spots with the wave number), "won", "lapsed".
@rpc("authority", "call_local", "reliable")
func _arena_alarm(kind: String, data: Dictionary) -> void:
	log.append(["alarm", kind])
	var d: Node = game.dungeon
	match kind:
		"seal":
			if not multiplayer.is_server():
				Telegraph.warned("arena_seal")
			AudioManager.play_sfx("arena_horn", 0.0)
			EventBus.hud_message.emit(Loc.t("The arena stirs - its doors are about to seal!"), UITheme.WARN)
			for door in _arena_doors():
				Telegraph.ground(game.fx_root, door.world_rect.get_center(), maxf(door.world_rect.size.x, door.world_rect.size.y) * 0.75,
					float(data.get("lead", 3.0)), "arena_door", Loc.t("Sealing"), UITheme.WARN, "")
		"wave":
			if not multiplayer.is_server():
				Telegraph.warned("arena_wave_%d" % int(data.get("wave", 1)))
			AudioManager.play_sfx("arena_horn", 0.0)
			EventBus.hud_message.emit(Loc.f("Wave %d of %d", [int(data.get("wave", 1)), int(data.get("of", 3))]), UITheme.WARN)
			for pos in data.get("spots", []):
				Telegraph.ground(game.fx_root, pos, 26.0, float(data.get("lead", 2.0)), "arena_spawn", "", UITheme.WARN, "telegraph")
		"won":
			AudioManager.play_sfx("arena_won", 0.0)
		"lapsed":
			pass
	changed.emit()


## Host -> all: the cursed chest shudders and creaks open over `lead` s - then the mimic bites.
@rpc("authority", "call_local", "reliable")
func _mimic_wake(lead: float) -> void:
	if not multiplayer.is_server():
		Telegraph.warned("mimic")
	log.append(["wake"])
	var chest: Node2D = game.dungeon.props.get("Event_cursed_chest")
	if chest == null:
		return
	AudioManager.play_sfx_at("mimic_wake", chest.global_position)
	Telegraph.ground(game.fx_root, chest.global_position + Vector2(0, -2), 34.0, lead, "mimic_mark", Loc.t("Mimic!"), UITheme.WARN, "", false)
	var spr: Sprite2D = chest.get("_sprite")
	var sheet: Texture2D = GameData.texture("props.cursed_chest_wake")
	if spr == null or sheet == null:
		return
	var n := 7
	var fw := sheet.get_width() / n
	var bottoms := [49, 50, 50, 52, 58, 58, 59]
	var tw := chest.create_tween()
	# Shudder first, then the lid opens frame by frame.
	for k in 6:
		tw.tween_property(spr, "position:x", 2.0 if k % 2 == 0 else -2.0, lead * 0.05)
	tw.tween_property(spr, "position:x", 0.0, lead * 0.05)
	for i in n:
		tw.tween_callback(func():
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * fw, 0, fw, sheet.get_height())
			spr.texture = at
			spr.offset = Vector2(0, 2.0 - float(bottoms[i]) + sheet.get_height() / 2.0))
		tw.tween_interval(lead * 0.6 / n)


## Host -> all: a ping on everyone's map (the opened vault, the room the shrine made stronger).
@rpc("authority", "call_local", "reliable")
func _ping(pos: Vector2, color: String, seconds: float) -> void:
	game.add_map_ping(pos, Color.from_string(color, Color.WHITE), seconds)


@rpc("authority", "call_local", "reliable")
func _notice(text: String, args: Array = []) -> void:
	EventBus.hud_message.emit(Loc.f(text, args), Color(1, 0.85, 0.5))
