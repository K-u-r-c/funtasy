class_name FloorState
extends RefCounted
## #55: the floor a saved game was left on. The floor itself is rebuilt from the run seed (same
## layout on every peer); this snapshot is the difference on top of it, captured by the host
## into the saved game (GameState.save_game) and laid back over the rebuilt floor when the game
## is continued (Game.start_floor). Short-lived state (threat, statuses, corpses, timed zones and
## obstacles, boss mechanic props, floor mechanic timers) is not kept: see docs/DECISIONS.md #55.

const MAP_COMPRESSION := FileAccess.COMPRESSION_DEFLATE


static func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]


static func vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


## Host: the snapshot of the running floor. `prev` is the snapshot saved before (the heroes and
## maps of players who left the session stay as they were).
static func capture(g: Node, prev: Dictionary) -> Dictionary:
	var same: bool = int(prev.get("depth", -1)) == g.depth and int(prev.get("seed", 0)) == int(g.layout.get("seed", 0))
	var snap := {"depth": g.depth, "seed": int(g.layout.get("seed", 0)), "time": snappedf(g.floor_time, 0.1)}
	var enemies: Array = []
	for e in g.enemies_root.get_children():
		if not (e is Enemy) or e.is_queued_for_deletion() or not e.is_alive() or e.team != Actor.Team.MONSTERS:
			continue
		if e.has_meta("summoned") or e.lifetime > 0.0:
			continue
		enemies.append({"def": e.def_id, "pos": _v(e.global_position), "hp": snappedf(e.health.hp, 0.1),
			"boss": e.is_boss, "elite": e.elite, "key": e.key_carrier})
	snap.enemies = enemies
	snap.boss_alive = g.boss_alive
	var items: Array = []
	for gi in g.items_root.get_children():
		if not gi.is_queued_for_deletion():
			items.append({"item": gi.item, "pos": _v(gi.global_position)})
	snap.items = items
	# Props: the layout's props that are gone, the ones opened (chests, levers, shrines), and
	# the elite altars that appeared on the floor.
	var d: Dungeon = g.dungeon
	var destroyed: Array = []
	var opened: Array = []
	var altars: Array = []
	for n in d.layout_prop_names():
		if not d.props.has(n):
			destroyed.append(n)
	for n in d.props:
		var pr: Node = d.props[n]
		if not is_instance_valid(pr) or pr.is_queued_for_deletion():
			continue
		if pr.type == "elite_altar":
			altars.append({"name": n, "type": pr.type, "pos": _v(pr.global_position), "opened": pr.opened})
		elif pr.opened:
			opened.append(n)
	snap.destroyed = destroyed
	snap.opened = opened
	snap.altars = altars
	var doors: Array = []
	for door in d.doors:
		doors.append([door.is_open, door.sealed, door.floodgate])
	snap.doors = doors
	var torches := {}
	for tid in d.torches:
		torches[tid] = int(d.torches[tid].state)
	snap.torches = torches
	var grates: Array = []
	for gid in d.grate_by_id:
		if not d.grate_by_id[gid]._sprite.visible:
			grates.append(gid)
	snap.grates_down = grates
	snap.cells = d.changed_cells()
	snap.keys = g.party_keys
	snap.key_chest = g.key_chest
	var m: Merchants = g.merchants
	var signed := {}
	for peer in m._signed:
		var slot := _slot_of(int(peer))
		if slot >= 0:
			signed[str(slot)] = m._signed[peer]
	snap.merchant = {"stock": m.stock, "contracts": m.contracts, "shop_open": m.shop_open, "signed": signed}
	# Heroes and their maps, by save slot.
	var heroes: Dictionary = prev.get("heroes", {}).duplicate(true) if same else {}
	var maps: Dictionary = prev.get("maps", {}).duplicate(true) if same else {}
	for p in g.players_root.get_children():
		if p.is_queued_for_deletion():
			continue
		var slot := _slot_of(p.peer_id)
		if slot < 0:
			continue
		# A hero still waiting for its saved state (restore_hero) keeps it.
		var pending: Dictionary = p.get_meta("pending_restore", {})
		heroes[str(slot)] = {"pos": _v(p.global_position), "hp": snappedf(p.health.hp, 0.1),
			"res": snappedf(p.resource.value, 0.1), "life": int(p.life_state)} if pending.is_empty() else pending
		var bytes: PackedByteArray = d.discovered if p.peer_id == 1 else g.reported_maps.get(p.peer_id, PackedByteArray())
		if not bytes.is_empty():
			maps[str(slot)] = Marshalls.raw_to_base64(bytes.compress(MAP_COMPRESSION))
	snap.heroes = heroes
	snap.maps = maps
	snap.map_size = d.discovered.size()
	return snap


static func _slot_of(peer: int) -> int:
	return int(GameState.roster.get(peer, {}).get("slot", -1))


static func _peer_of(slot: int) -> int:
	for peer in GameState.roster:
		if int(GameState.roster[peer].get("slot", -1)) == slot:
			return int(peer)
	return 0


static func map_bytes(snap: Dictionary, slot: int) -> PackedByteArray:
	var b64 := str(snap.get("maps", {}).get(str(slot), ""))
	if b64.is_empty():
		return PackedByteArray()
	return Marshalls.base64_to_raw(b64).decompress(int(snap.get("map_size", 0)), MAP_COMPRESSION)


## Host: the hero's saved state for this peer, {} when there is none.
static func hero_of(snap: Dictionary, peer: int) -> Dictionary:
	return snap.get("heroes", {}).get(str(_slot_of(peer)), {})


## Host, inside Game.start_floor of the continued floor: the monsters, the boss, the ground
## items, the Gold Key and the merchant come back as they were.
static func restore_host(g: Node, snap: Dictionary, boss_pos: Vector2) -> void:
	for ed in snap.get("enemies", []):
		var boss := bool(ed.get("boss", false))
		var extra := {}
		if not Array(ed.get("elite", [])).is_empty():
			extra.elite = ed.elite
		if bool(ed.get("key", false)):
			extra.key = true
		# The boss waits at home, out of the fight, as it did before anyone came in.
		var e: Node = g.spawn_monster(str(ed.def), boss_pos if boss else vec(ed.pos), boss, extra)
		if e:
			e.health.hp = clampf(float(ed.hp), 1.0, e.health.max_hp)
	g.boss_alive = bool(snap.get("boss_alive", true))
	for it in snap.get("items", []):
		g.loot.drop_item(it.item, vec(it.pos))
	g.add_party_key(int(snap.get("keys", 0)) - g.party_keys)
	g.key_chest = str(snap.get("key_chest", ""))
	var ms: Dictionary = snap.get("merchant", {})
	var m: Merchants = g.merchants
	if not ms.is_empty():
		# JSON brings numbers back as floats: indices and counts are ints again.
		m.stock = ms.get("stock", m.stock)
		for st in m.stock:
			st.left = int(st.get("left", 1))
			st.price = int(st.get("price", 1))
		m.contracts = Array(ms.get("contracts", m.contracts)).map(func(c): return int(c))
		m.shop_open = bool(ms.get("shop_open", false))
		m._signed.clear()
		for slot in ms.get("signed", {}):
			var peer := _peer_of(int(slot))
			if peer > 0:
				m._signed[peer] = Array(ms.signed[slot]).map(func(c): return int(c))
		m._sync.rpc(m.stock, m.contracts, m.shop_open)
	g.floor_time = float(snap.get("time", 0.0))


## Host, once the hero is in: HP, resource and life state as saved. Its stats (max HP with the
## gear) settle over the first frames, so this waits for them.
static func restore_hero(p: Player, h: Dictionary) -> void:
	if h.is_empty():
		return
	p.set_meta("pending_restore", h)
	for i in 2:
		await p.get_tree().physics_frame
	if not is_instance_valid(p):
		return
	p.remove_meta("pending_restore")
	p.health.hp = clampf(float(h.get("hp", p.health.max_hp)), 1.0, p.health.max_hp)
	p.resource.value = clampf(float(h.get("res", p.resource.value)), 0.0, p.resource.max_value)
	match int(h.get("life", Player.Life.ALIVE)):
		Player.Life.DOWNED:
			# Downed when the game was left: down again, with a fresh count for a revive.
			p.life_state = Player.Life.DOWNED
			p.downed_left = float(GameData.bal("player.downed_time"))
		Player.Life.GHOST:
			p.life_state = Player.Life.GHOST
			p.collision_mask = 1


## The part every peer applies (Game._restore_floor_view): props, doors, torches, grates and
## changed cells, without sounds or animations, and the portal if the boss was beaten.
static func view_of(snap: Dictionary, portal_pos: Vector2, g: Node = null) -> Dictionary:
	var v := {}
	for k in ["destroyed", "opened", "altars", "doors", "torches", "grates_down", "cells"]:
		v[k] = snap.get(k, [] if k != "torches" else {})
	# #63: an altar saved where it blocks the way (a doorway, a corridor) rises on open floor.
	if g:
		var moved: Array = []
		for a in v.altars:
			var a2: Dictionary = a.duplicate()
			a2.pos = _v(g.altar_spot(vec(a.pos)))
			moved.append(a2)
		v.altars = moved
	if not bool(snap.get("boss_alive", true)):
		v.portal = _v(portal_pos)
	return v


static func apply_view(g: Node, v: Dictionary) -> void:
	var d: Dungeon = g.dungeon
	for a in v.get("altars", []):
		d.spawn_prop(str(a.name), str(a.type), vec(a.pos))
		if bool(a.get("opened", false)):
			v.opened.append(str(a.name))
	for n in v.get("destroyed", []):
		d.remove_prop_quietly(str(n))
	for n in v.get("opened", []):
		var pr: Node = d.props.get(str(n))
		if pr and is_instance_valid(pr):
			pr.set_opened(true)
	var doors: Array = v.get("doors", [])
	for i in mini(doors.size(), d.doors.size()):
		d.doors[i].restore_state(bool(doors[i][0]), bool(doors[i][1]), bool(doors[i][2]))
	for tid in v.get("torches", {}):
		var t: Node = d.torches.get(tid)
		if t and is_instance_valid(t) and int(t.state) != int(v.torches[tid]):
			t.state = int(v.torches[tid])
			t._apply_state()
	for gid in v.get("grates_down", []):
		var gr: Node = d.grate_by_id.get(gid)
		if gr:
			gr._sprite.visible = false
	var by_kind := {}
	for c in v.get("cells", []):
		var k := int(c[2])
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(Vector2i(int(c[0]), int(c[1])))
	for k in by_kind:
		d.set_cells(by_kind[k], k)
	g.visibility.rebuild_opaque()
	if v.has("portal"):
		g.place_portal(vec(v.portal))
