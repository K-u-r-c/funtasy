class_name DungeonGenerator
extends RefCounted
## Pure, deterministic floor layout generation. Every peer runs this with the seed the host
## sends, so the map itself never has to be replicated. Only the host uses the enemy spawns.
##
## Layout keys: size, cells (PackedByteArray, see CELL_*), rooms [{rect, role}], doors
## [{cells, vertical, rect}], props [{type, pos}], chests [pos], spikes [{cell, phase}],
## torches [{cell}], lava_pools [Rect2i], spawns [{room, monsters: [{id, pos}]}],
## start (Vector2), boss_pos (Vector2), boss_room (int), portal_pos (Vector2).

const CELL_WALL := 0
const CELL_FLOOR := 1
const CELL_LAVA := 2

var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var tile := 32
var cells := PackedByteArray()


func generate(seed_value: int, floor_def: Dictionary, count_mult: float = 1.0) -> Dictionary:
	rng.seed = seed_value
	tile = int(GameData.bal("world.tile_size"))
	var grid: Array = floor_def.grid
	w = int(grid[0])
	h = int(grid[1])
	cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(CELL_WALL)
	var layout := {"size": Vector2i(w, h)}
	var rooms := _place_rooms(floor_def)
	_connect_rooms(rooms)
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
	layout.chests = _place_chests(rooms, floor_def, used)
	layout.spikes = _place_spikes(rooms, floor_def, used)
	layout.torches = _place_torches(rooms)
	layout.spawns = _place_spawns(rooms, floor_def, used, count_mult)
	var boss_room: Dictionary = rooms[1]
	var start_room: Dictionary = rooms[0]
	layout.boss_room = 1
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
	for k in 2:
		var a2 := rng.randi_range(0, n - 1)
		var b2 := rng.randi_range(0, n - 1)
		if a2 != b2 and not (a2 == 1 or b2 == 1):
			edges.append(Vector2i(a2, b2))
	for e in edges:
		_carve_corridor(rooms[e.x].rect.get_center(), rooms[e.y].rect.get_center())


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
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
						doors.append({"cells": run.duplicate(), "vertical": bool(side[3]), "rect": rect})
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
		if room.role == "start":
			continue
		var n := rng.randi_range(int(fd.props_per_room[0]), int(fd.props_per_room[1]))
		for i in n:
			var c2 := _free_cell(r, 1, used, true)
			if c2.x < 0:
				continue
			used[c2] = true
			var t: String = types[ItemGenerator._weighted_index(ws, rng)]
			var jitter := Vector2(rng.randf_range(-5, 5), rng.randf_range(-4, 4))
			out.append({"type": t, "pos": _cell_center(c2) + jitter})
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


func _place_torches(rooms: Array) -> Array:
	var out: Array = []
	for room in rooms:
		var r: Rect2i = room.rect
		var count := 4 if room.role == "boss" else rng.randi_range(1, 3)
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
