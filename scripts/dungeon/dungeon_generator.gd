class_name DungeonGenerator
extends RefCounted
## Pure, deterministic floor layout generation. Every peer runs this with the seed the host
## sends, so the map itself never has to be replicated. Only the host uses the enemy spawns.
##
## Layout keys: size, cells (PackedByteArray, see CELL_*), rooms [{rect, role}], doors
## [{cells, vertical, rect}], props [{type, pos}], chests [pos], spikes [{cell, phase}],
## torches [{cell}], lava_pools [Rect2i], spawns [{room, monsters: [{id, pos}]}],
## plates [{cell}], pendulums [{pos, axis, span, phase}],
## start (Vector2), boss_pos (Vector2), boss_room (int), portal_pos (Vector2).
##
## A floor type's "generator" block picks the architecture profile, e.g. the Crypt's
## labyrinth_vaults: {"winding": true, "extra_edges": 4, "pillared_hall_chance": 0.4}.

const CELL_WALL := 0
const CELL_FLOOR := 1
const CELL_LAVA := 2

var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var tile := 32
var cells := PackedByteArray()
var gen: Dictionary = {}  ## the floor type's architecture profile


## `depth` makes deeper floors darker (fewer lit rooms), so every peer must pass the same value.
func generate(seed_value: int, floor_def: Dictionary, count_mult: float = 1.0, depth: int = 1) -> Dictionary:
	rng.seed = seed_value
	tile = int(GameData.bal("world.tile_size"))
	var grid: Array = floor_def.grid
	w = int(grid[0])
	h = int(grid[1])
	cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(CELL_WALL)
	var layout := {"size": Vector2i(w, h)}
	gen = floor_def.get("generator", {})
	var rooms := _place_rooms(floor_def)
	_connect_rooms(rooms)
	_pick_merchant_room(rooms)
	var doors := _find_doors(rooms)
	layout.rooms = rooms
	layout.doors = doors
	var door_zone := {}
	for d in doors:
		for c in d.cells:
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					door_zone[c + Vector2i(dx, dy)] = true
	layout.lava_pools = _place_lava(rooms, floor_def, door_zone)
	var used := door_zone.duplicate()
	layout.props = _place_props(rooms, floor_def, used)
	layout.props.append_array(_place_lore_props(rooms, floor_def, used))
	layout.chests = _place_chests(rooms, floor_def, used)
	layout.spikes = _place_spikes(rooms, floor_def, used)
	layout.plates = _place_plates(rooms, floor_def, used)
	layout.pendulums = _place_pendulums(rooms, floor_def, used)
	layout.torches = _place_torches(rooms, floor_def, depth)
	layout.spawns = _place_spawns(rooms, floor_def, used, count_mult)
	var boss_room: Dictionary = rooms[1]
	var start_room: Dictionary = rooms[0]
	layout.boss_room = 1
	layout.merchant = _merchant_layout(rooms, used)
	layout.start = _cell_center(start_room.rect.get_center())
	layout.boss_pos = _cell_center(boss_room.rect.get_center() - Vector2i(0, 2))
	layout.portal_pos = _cell_center(boss_room.rect.get_center() + Vector2i(0, 2))
	layout.cells = cells
	return layout


func _idx(c: Vector2i) -> int:
	return c.y * w + c.x


func get_cell(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return CELL_WALL
	return cells[_idx(c)]


func _set_cell(c: Vector2i, v: int) -> void:
	if c.x <= 0 or c.y <= 0 or c.x >= w - 1 or c.y >= h - 1:
		return
	cells[_idx(c)] = v


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c * tile) + Vector2(tile, tile) * 0.5


# --- Rooms + corridors ------------------------------------------------------------------------


func _place_rooms(fd: Dictionary) -> Array:
	var spec: Dictionary = fd.rooms
	var target := rng.randi_range(int(spec.count[0]), int(spec.count[1]))
	var rooms: Array = []
	var rects: Array = []
	# Boss room first (largest), then the rest; the start room is the one farthest from it.
	var bs: Array = spec.boss_size
	var boss_rect := _try_rect(int(bs[0]), int(bs[1]), rects, 200)
	rects.append(boss_rect)
	var tries := 0
	while rects.size() < target + 1 and tries < 600:
		tries += 1
		var rw := rng.randi_range(int(spec.min_size[0]), int(spec.max_size[0]))
		var rh := rng.randi_range(int(spec.min_size[1]), int(spec.max_size[1]))
		var r := _try_rect(rw, rh, rects, 1)
		if r.size != Vector2i.ZERO:
			rects.append(r)
	var far := 1
	var best := -1.0
	for i in range(1, rects.size()):
		var d := Vector2(rects[i].get_center() - boss_rect.get_center()).length()
		if d > best:
			best = d
			far = i
	rooms.append({"rect": rects[far], "role": "start"})
	rooms.append({"rect": boss_rect, "role": "boss"})
	for i in range(1, rects.size()):
		if i != far:
			rooms.append({"rect": rects[i], "role": "normal"})
	for room in rooms:
		var rr: Rect2i = room.rect
		for x in range(rr.position.x, rr.end.x):
			for y in range(rr.position.y, rr.end.y):
				_set_cell(Vector2i(x, y), CELL_FLOOR)
	return rooms


func _try_rect(rw: int, rh: int, existing: Array, attempts: int) -> Rect2i:
	for i in attempts:
		var r := Rect2i(rng.randi_range(3, w - rw - 4), rng.randi_range(3, h - rh - 4), rw, rh)
		var ok := true
		for o in existing:
			if o.grow(4).intersects(r):
				ok = false
				break
		if ok:
			return r
	return Rect2i()


func _connect_rooms(rooms: Array) -> void:
	# Prim's MST over room centers + a couple of extra edges for loops.
	var n := rooms.size()
	var in_tree := {0: true}
	var edges: Array = []
	while in_tree.size() < n:
		var best := INF
		var pair := Vector2i(-1, -1)
		for a in in_tree:
			for b in n:
				if in_tree.has(b):
					continue
				var d := Vector2(rooms[a].rect.get_center() - rooms[b].rect.get_center()).length()
				if d < best:
					best = d
					pair = Vector2i(a, b)
		in_tree[pair.y] = true
		edges.append(pair)
	for k in int(gen.get("extra_edges", 2)):
		var a2 := rng.randi_range(0, n - 1)
		var b2 := rng.randi_range(0, n - 1)
		if a2 != b2 and not (a2 == 1 or b2 == 1):
			edges.append(Vector2i(a2, b2))
	for e in edges:
		_carve_corridor(rooms[e.x].rect.get_center(), rooms[e.y].rect.get_center())


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	if gen.get("winding", false) and Vector2(b - a).length() > 10.0:
		# Labyrinth: a detour through a jittered midpoint gives the corridor extra bends.
		var mid := (a + b) / 2
		var side := Vector2(b - a).orthogonal().normalized() * rng.randf_range(-6.0, 6.0)
		mid = Vector2i(clampi(mid.x + int(side.x), 3, w - 5), clampi(mid.y + int(side.y), 3, h - 5))
		_carve_l(a, mid)
		_carve_l(mid, b)
		return
	_carve_l(a, b)


func _carve_l(a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(a, corner)
	_carve_line(corner, b)


func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if get_cell(p + o) == CELL_WALL:
				_set_cell(p + o, CELL_FLOOR)
		if p == b:
			break
		p += step


## Every floor has a secure merchant chamber: the normal room closest to a medium size
## (seeded like everything else). It gets no monsters, hazards or loose props.
func _pick_merchant_room(rooms: Array) -> void:
	var best := -1
	var best_score := INF
	for i in range(2, rooms.size()):
		var r: Rect2i = rooms[i].rect
		var score := absf(r.size.x - 11) + absf(r.size.y - 9) + rng.randf() * 2.0
		if r.size.x >= 9 and r.size.y >= 8 and score < best_score:
			best_score = score
			best = i
	if best < 0 and rooms.size() > 2:
		best = 2
	if best >= 0:
		rooms[best].role = "merchant"


## Places the merchant chamber's pieces: Archibald behind the Gilded Portal (left), Malphas
## behind the Demon Altarpiece (right). Returns {} when the floor has no merchant room.
func _merchant_layout(rooms: Array, used: Dictionary) -> Dictionary:
	for i in rooms.size():
		if rooms[i].role != "merchant":
			continue
		var r: Rect2i = rooms[i].rect
		var c := r.get_center()
		var dx := maxi(2, r.size.x / 2 - 2)
		var out := {"room": i,
			"archibald": _cell_center(c + Vector2i(-dx, -1)), "portal": _cell_center(c + Vector2i(-dx, 1)),
			"malphas": _cell_center(c + Vector2i(dx, -1)), "altar": _cell_center(c + Vector2i(dx, 1))}
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				used[Vector2i(x, y)] = true
		return out
	return {}


## Openings in a room's wall ring 2-3 cells wide become doors.
func _find_doors(rooms: Array) -> Array:
	var doors: Array = []
	var taken := {}
	for room in rooms:
		var r: Rect2i = room.rect
		var sides := [
			[Vector2i(r.position.x, r.position.y - 1), Vector2i(1, 0), r.size.x, false],
			[Vector2i(r.position.x, r.end.y), Vector2i(1, 0), r.size.x, false],
			[Vector2i(r.position.x - 1, r.position.y), Vector2i(0, 1), r.size.y, true],
			[Vector2i(r.end.x, r.position.y), Vector2i(0, 1), r.size.y, true],
		]
		for side in sides:
			var run: Array = []
			for i in int(side[2]) + 1:
				var c: Vector2i = side[0] + side[1] * i
				var open := i < int(side[2]) and get_cell(c) == CELL_FLOOR
				if open:
					run.append(c)
				elif not run.is_empty():
					if run.size() >= 2 and run.size() <= 3 and not taken.has(run[0]):
						for rc in run:
							taken[rc] = true
						var rect := Rect2i(run[0], Vector2i.ONE)
						for rc in run:
							rect = rect.expand(rc).expand(rc + Vector2i.ONE)
						doors.append({"cells": run.duplicate(), "vertical": bool(side[3]), "rect": rect,
							"monster_proof": room.role == "merchant"})
					run.clear()
	return doors


# --- Contents --------------------------------------------------------------------------------


func _interior_cells(r: Rect2i, margin: int) -> Array:
	var out: Array = []
	for x in range(r.position.x + margin, r.end.x - margin):
		for y in range(r.position.y + margin, r.end.y - margin):
			out.append(Vector2i(x, y))
	return out


func _free_cell(r: Rect2i, margin: int, used: Dictionary, prefer_edge: bool) -> Vector2i:
	for i in 40:
		var c := Vector2i(rng.randi_range(r.position.x + margin, r.end.x - 1 - margin), rng.randi_range(r.position.y + margin, r.end.y - 1 - margin))
		if prefer_edge and i < 25:
			match rng.randi_range(0, 3):
				0: c.x = r.position.x + margin
				1: c.x = r.end.x - 1 - margin
				2: c.y = r.position.y + margin
				3: c.y = r.end.y - 1 - margin
		if not used.has(c) and get_cell(c) == CELL_FLOOR:
			return c
	return Vector2i(-1, -1)


func _place_lava(rooms: Array, fd: Dictionary, door_zone: Dictionary) -> Array:
	var pools: Array = []
	for room in rooms:
		if room.role != "normal" or rng.randf() > float(fd.get("lava_room_chance", 0.0)):
			continue
		var r: Rect2i = room.rect
		var pw := rng.randi_range(2, mini(4, r.size.x - 6))
		var ph := rng.randi_range(2, mini(3, r.size.y - 6))
		if pw < 2 or ph < 2:
			continue
		var pos := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 3 - pw), rng.randi_range(r.position.y + 3, r.end.y - 3 - ph))
		var pool := Rect2i(pos, Vector2i(pw, ph))
		var clash := false
		for x in range(pool.position.x - 1, pool.end.x + 1):
			for y in range(pool.position.y - 1, pool.end.y + 1):
				if door_zone.has(Vector2i(x, y)):
					clash = true
		if clash:
			continue
		for x in range(pool.position.x, pool.end.x):
			for y in range(pool.position.y, pool.end.y):
				_set_cell(Vector2i(x, y), CELL_LAVA)
		pools.append(pool)
		for x in range(pool.position.x - 1, pool.end.x + 1):
			for y in range(pool.position.y - 1, pool.end.y + 1):
				door_zone[Vector2i(x, y)] = true
	return pools


func _place_props(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var weights: Dictionary = fd.prop_weights
	var types: Array = weights.keys()
	var ws: Array = []
	for t in types:
		ws.append(float(weights[t]))
	for room in rooms:
		var r: Rect2i = room.rect
		if room.role == "boss":
			# Symmetric pillars give cover from the boss's projectiles.
			for o in [Vector2i(-4, -3), Vector2i(4, -3), Vector2i(-4, 3), Vector2i(4, 3)]:
				var c: Vector2i = r.get_center() + o
				if r.has_point(c):
					used[c] = true
					out.append({"type": "pillar", "pos": _cell_center(c)})
			continue
		if room.role == "start" or room.role == "merchant":
			continue
		var n := rng.randi_range(int(fd.props_per_room[0]), int(fd.props_per_room[1]))
		if rng.randf() < float(gen.get("pillared_hall_chance", 0.0)) and r.size.x >= 9 and r.size.y >= 8:
			# A geometric hall: a grid of stone pillars, fewer loose props.
			for x in range(r.position.x + 2, r.end.x - 2, 3):
				for y in range(r.position.y + 2, r.end.y - 2, 3):
					var pc := Vector2i(x, y)
					if not used.has(pc) and get_cell(pc) == CELL_FLOOR:
						used[pc] = true
						out.append({"type": str(gen.get("pillar_prop", "pillar")), "pos": _cell_center(pc)})
			n = n / 2
		for i in n:
			var c2 := _free_cell(r, 1, used, true)
			if c2.x < 0:
				continue
			used[c2] = true
			var t: String = types[ItemGenerator._weighted_index(ws, rng)]
			var jitter := Vector2(rng.randf_range(-5, 5), rng.randf_range(-4, 4))
			out.append({"type": t, "pos": _cell_center(c2) + jitter})
	return out


## Bookshelves (books drop when they break) and the biome's secret container (D20).
func _place_lore_props(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var shelves: Array = fd.get("bookshelves_per_room", [0, 1])
	var normals: Array = []
	for i in rooms.size():
		if rooms[i].role != "normal":
			continue
		normals.append(i)
		for k in rng.randi_range(int(shelves[0]), int(shelves[1])):
			var c := _free_cell(rooms[i].rect, 1, used, true)
			if c.x >= 0:
				used[c] = true
				out.append({"type": "bookshelf", "pos": _cell_center(c)})
	var sc: Array = fd.get("secret_containers", [0, 0])
	var kind := str(fd.get("secret_container", "secret_sarcophagus"))
	for k in mini(rng.randi_range(int(sc[0]), int(sc[1])), normals.size()):
		var room: Dictionary = rooms[normals.pop_at(rng.randi_range(0, normals.size() - 1))]
		var c2 := _free_cell(room.rect, 1, used, true)
		if c2.x >= 0:
			used[c2] = true
			out.append({"type": kind, "pos": _cell_center(c2)})
	return out


func _place_chests(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var normals: Array = []
	for i in rooms.size():
		if rooms[i].role == "normal":
			normals.append(i)
	var n := rng.randi_range(int(fd.chests[0]), int(fd.chests[1]))
	for k in mini(n, normals.size()):
		var room: Dictionary = rooms[normals.pop_at(rng.randi_range(0, normals.size() - 1))]
		var c := _free_cell(room.rect, 1, used, true)
		if c.x >= 0:
			used[c] = true
			out.append(_cell_center(c))
	return out


func _place_spikes(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	for room in rooms:
		if room.role != "normal":
			continue
		var n := rng.randi_range(int(fd.spikes_per_room[0]), int(fd.spikes_per_room[1]))
		for i in n:
			var c := _free_cell(room.rect, 2, used, false)
			if c.x >= 0:
				used[c] = true
				out.append({"cell": c, "phase": rng.randf()})
	return out


## Pressure plates (Crypt): hidden-ish floor plates in normal rooms that raise spikes around them.
func _place_plates(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	if not fd.has("plates_per_room"):
		return out
	for room in rooms:
		if room.role != "normal":
			continue
		for i in rng.randi_range(int(fd.plates_per_room[0]), int(fd.plates_per_room[1])):
			var c := _free_cell(room.rect, 2, used, false)
			if c.x < 0:
				continue
			# The spikes rise on the 3x3 cells around the plate: keep them clear of props.
			var clear := true
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if used.has(c + Vector2i(dx, dy)) or get_cell(c + Vector2i(dx, dy)) != CELL_FLOOR:
						clear = false
			if not clear:
				continue
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					used[c + Vector2i(dx, dy)] = true
			out.append({"cell": c})
	return out


## Pendulum scythes (Crypt) across straight 2-wide corridor stretches, away from rooms and doors.
func _place_pendulums(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	if not fd.has("pendulums"):
		return out
	var in_room := func(c: Vector2i) -> bool:
		for room in rooms:
			if room.rect.grow(2).has_point(c):
				return true
		return false
	var cands: Array = []
	for y in range(2, h - 3):
		for x in range(2, w - 3):
			var c := Vector2i(x, y)
			if used.has(c) or in_room.call(c):
				continue
			# Horizontal stretch: rows y and y+1 open, walls above and below, for 5 cells.
			var hor := true
			var ver := true
			for k in range(-2, 3):
				var hc := c + Vector2i(k, 0)
				if not (get_cell(hc) == CELL_FLOOR and get_cell(hc + Vector2i(0, 1)) == CELL_FLOOR
						and get_cell(hc + Vector2i(0, -1)) == CELL_WALL and get_cell(hc + Vector2i(0, 2)) == CELL_WALL):
					hor = false
				var vc := c + Vector2i(0, k)
				if not (get_cell(vc) == CELL_FLOOR and get_cell(vc + Vector2i(1, 0)) == CELL_FLOOR
						and get_cell(vc + Vector2i(-1, 0)) == CELL_WALL and get_cell(vc + Vector2i(2, 0)) == CELL_WALL):
					ver = false
			if hor:
				cands.append({"cell": c, "axis": Vector2.DOWN, "pos": _cell_center(c) + Vector2(0, tile * 0.5)})
			elif ver:
				cands.append({"cell": c, "axis": Vector2.RIGHT, "pos": _cell_center(c) + Vector2(tile * 0.5, 0)})
	var n := rng.randi_range(int(fd.pendulums[0]), int(fd.pendulums[1]))
	while out.size() < n and not cands.is_empty():
		var pick: Dictionary = cands.pop_at(rng.randi_range(0, cands.size() - 1))
		var clash := false
		for o in out:
			if Vector2(o.cell - pick.cell).length() < 8.0:
				clash = true
		if clash:
			continue
		for k in range(-2, 3):
			used[pick.cell + Vector2i(k, 0)] = true
			used[pick.cell + Vector2i(0, k)] = true
		out.append({"cell": pick.cell, "pos": pick.pos, "axis": pick.axis, "span": tile * 0.85, "phase": rng.randf()})
	return out


## The start room and the boss room are always lit; other rooms are lit with a chance that
## shrinks with depth (data: balance.lighting), so darkness spreads on deeper floors.
func _place_torches(rooms: Array, fd: Dictionary, depth: int) -> Array:
	var out: Array = []
	var chance := clampf(float(GameData.bal("lighting.lit_room_chance")) + float(GameData.bal("lighting.lit_room_chance_per_depth")) * (depth - 1),
		float(GameData.bal("lighting.lit_room_chance_min")), 1.0)
	var per_room: Array = fd.get("torches_per_room", [1, 3])
	for room in rooms:
		var r: Rect2i = room.rect
		var roll := rng.randf()
		var count := rng.randi_range(int(per_room[0]), int(per_room[1]))
		match room.role:
			"boss":
				count = 4
			"start", "merchant":
				count = maxi(count, 2)
			_:
				if roll > chance:
					count = 0
		var wall_cells: Array = []
		for x in range(r.position.x + 1, r.end.x - 1):
			var c := Vector2i(x, r.position.y - 1)
			if get_cell(c) == CELL_WALL:
				wall_cells.append(c)
		for i in count:
			if wall_cells.is_empty():
				break
			var c2: Vector2i = wall_cells.pop_at(rng.randi_range(0, wall_cells.size() - 1))
			wall_cells.erase(c2 + Vector2i(1, 0))
			wall_cells.erase(c2 - Vector2i(1, 0))
			out.append({"cell": c2})
	return out


func _place_spawns(rooms: Array, fd: Dictionary, used: Dictionary, count_mult: float) -> Array:
	var out: Array = []
	var ids: Array = []
	var ws: Array = []
	for m in fd.monsters:
		ids.append(m.id)
		ws.append(float(m.weight))
	for i in rooms.size():
		if rooms[i].role != "normal":
			continue
		var n := roundi(rng.randi_range(int(fd.enemies_per_room[0]), int(fd.enemies_per_room[1])) * count_mult)
		var group: Array = []
		for k in n:
			var c := _free_cell(rooms[i].rect, 1, used, false)
			if c.x < 0:
				continue
			group.append({"id": ids[ItemGenerator._weighted_index(ws, rng)], "pos": _cell_center(c)})
		out.append({"room": i, "monsters": group})
	return out
