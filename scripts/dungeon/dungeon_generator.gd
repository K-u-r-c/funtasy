class_name DungeonGenerator
extends RefCounted
## Pure, deterministic floor layout generation. Every peer runs this with the seed the host
## sends, so the map itself never has to be replicated. Only the host uses the enemy spawns.
##
## Layout keys: size, cells (PackedByteArray, see CELL_*), rooms [{rect, role}], doors
## [{cells, vertical, rect}], props [{type, pos}], chests [pos], spikes [{cell, phase}],
## torches [{cell}], lava_pools [Rect2i], spawns [{room, monsters: [{id, pos}]}],
## plates [{cell}],
## start (Vector2), boss_pos (Vector2), boss_room (int), portal_pos (Vector2).
##
## A floor type's "generator" block picks the architecture profile, e.g. the Crypt's
## labyrinth_vaults: {"winding": true, "extra_edges": 4, "pillared_hall_chance": 0.4}.

const CELL_WALL := 0
const CELL_FLOOR := 1
const CELL_LAVA := 2
const CELL_WATER := 3  ## shallow sewage: walkable, slows (Sewers)
const CELL_SLUDGE := 4  ## deep sludge: walkable, slows + Blighted Taint (Sewers)
const CELL_CANAL := 5  ## toxic canal: blocks movement, not sight or projectiles
const CELL_BRIDGE := 6  ## catwalk over a canal: walkable
const CELL_GRATE := 7  ## iron grate over molten rock: walkable until it collapses (Foundry)


## Can heroes and monsters stand on this cell kind?
static func walkable(v: int) -> bool:
	return v == CELL_FLOOR or v == CELL_LAVA or v == CELL_WATER or v == CELL_SLUDGE or v == CELL_BRIDGE or v == CELL_GRATE

const LEAF_ATTEMPTS := 16
const BRUSH := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]  ## corridors are 2 cells wide
const SIDES4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var tile := 32
var cells := PackedByteArray()
var gen: Dictionary = {}  ## the floor type's architecture profile
var _depth := 1


## `depth` makes deeper floors darker (fewer lit rooms), so every peer must pass the same value.
## `merchant` is the floor's one merchant (Game.pick_merchant); "" = the seeded pick.
func generate(seed_value: int, floor_def: Dictionary, count_mult: float = 1.0, depth: int = 1, merchant: String = "") -> Dictionary:
	rng.seed = seed_value
	_depth = depth
	tile = int(GameData.bal("world.tile_size"))
	var grid: Array = floor_def.grid
	w = int(grid[0])
	h = int(grid[1])
	cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(CELL_WALL)
	var layout := {"size": Vector2i(w, h)}
	gen = floor_def.get("generator", {})
	# #23 / #30 / #31: the merchant and boss chambers are sealed leaves of the room graph. An
	# attempt that can't attach them (rare) is redrawn from a derived seed, the same on every peer.
	var rooms: Array = []
	for attempt in LEAF_ATTEMPTS:
		if attempt > 0:
			rng.seed = seed_value + attempt * 104729
			cells.fill(CELL_WALL)
		rooms = _place_rooms(floor_def)
		_mark_merchant_room(rooms)
		_connect_rooms(rooms)
		if _attach_leaves(rooms):
			break
		if attempt == LEAF_ATTEMPTS - 1:
			push_error("DungeonGenerator: seed %d has no layout with sealed boss / merchant rooms" % seed_value)
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
	_place_pools(rooms, door_zone)
	_place_canals(rooms, door_zone)
	_place_platforms(rooms, doors, door_zone)
	_round_rooms(rooms, doors, door_zone)
	_cave_rooms(rooms, door_zone)
	var used := door_zone.duplicate()
	layout.props = _place_props(rooms, floor_def, used)
	layout.props.append_array(_place_lore_props(rooms, floor_def, used))
	layout.chests = _place_chests(rooms, floor_def, used)
	layout.spikes = _place_spikes(rooms, floor_def, used)
	layout.plates = _place_plates(rooms, floor_def, used)
	layout.spouts = _place_spouts(rooms, floor_def)
	layout.grates = _place_grates(rooms, floor_def, used)
	layout.props.append_array(_place_shelf_rows(rooms, used))
	layout.anomalies = _place_anomalies(rooms)
	layout.rifts = _scatter(rooms, used, floor_def.get("void_rifts", [0, 0]))
	layout.runes = _scatter(rooms, used, floor_def.get("silence_runes", [0, 0]))
	layout.snares = _scatter(rooms, used, floor_def.get("root_snares", [0, 0]))
	for d in doors:
		if str(d.kind).is_empty() and not d.get("floodgate", false) and rng.randf() < float(gen.get("bookshelf_door_chance", 0.0)):
			d.style = "bookshelf"
	var arena := _side_arena(rooms)
	if arena.size != Vector2i.ZERO:
		layout.side_arena = arena
	layout.props.append_array(_place_floodgates(doors, rooms, used))
	layout.torches = _place_torches(rooms, floor_def, depth)
	layout.spawns = _place_spawns(rooms, floor_def, used, count_mult)
	var boss_room: Dictionary = rooms[1]
	var start_room: Dictionary = rooms[0]
	layout.boss_room = 1
	layout.merchant = _merchant_layout(rooms, used, merchant if not merchant.is_empty() else pick_merchant(seed_value))
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
	# One extra room for the merchant (#6), so the fighting rooms keep their count.
	var target := rng.randi_range(int(spec.count[0]), int(spec.count[1])) + 1
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


## Prim's MST over the centres of the ordinary rooms (start + normal) plus a few extra edges for
## loops. The boss and merchant rooms are left out and every corridor keeps clear of their walls,
## so _attach_leaves can give each exactly one entrance.
func _connect_rooms(rooms: Array) -> void:
	var core: Array = _core_rooms(rooms)
	var reserved: Array = []
	for i in rooms.size():
		if not core.has(i):
			reserved.append(Rect2i(rooms[i].rect).grow(1))
	var in_tree := {core[0]: true}
	var edges: Array = []
	while in_tree.size() < core.size():
		var best := INF
		var pair := Vector2i(-1, -1)
		for a in in_tree:
			for b in core:
				if in_tree.has(b):
					continue
				var d := Vector2(rooms[a].rect.get_center() - rooms[b].rect.get_center()).length()
				if d < best:
					best = d
					pair = Vector2i(a, b)
		in_tree[pair.y] = true
		edges.append(pair)
	for k in int(gen.get("extra_edges", 2)):
		var a2: int = core[rng.randi_range(0, core.size() - 1)]
		var b2: int = core[rng.randi_range(0, core.size() - 1)]
		if a2 != b2:
			edges.append(Vector2i(a2, b2))
	var clear := func(c: Vector2i) -> bool:
		if c.x <= 0 or c.y <= 0 or c.x >= w - 1 or c.y >= h - 1:
			return false
		for r in reserved:
			if r.has_point(c):
				return false
		return true
	for e in edges:
		_carve_path(_corridor_path(rooms[e.x].rect.get_center(), rooms[e.y].rect.get_center(), clear))


## Indices of the ordinary rooms: the start room first, then the normal rooms.
func _core_rooms(rooms: Array) -> Array:
	var out: Array = []
	for i in rooms.size():
		if rooms[i].role == "start" or rooms[i].role == "normal":
			out.append(i)
	return out


## Brush origins of a corridor from a to b whose every cell passes `clear`: the profile's L shape
## (or winding detour) first, the other corner next, a grid search last. [] if nothing fits.
func _corridor_path(a: Vector2i, b: Vector2i, clear: Callable) -> Array:
	var tries: Array = []
	if gen.get("winding", false) and Vector2(b - a).length() > 10.0:
		# Labyrinth: a detour through a jittered midpoint gives the corridor extra bends.
		var mid := (a + b) / 2
		var side := Vector2(b - a).orthogonal().normalized() * rng.randf_range(-6.0, 6.0)
		mid = Vector2i(clampi(mid.x + int(side.x), 3, w - 5), clampi(mid.y + int(side.y), 3, h - 5))
		var flip := rng.randf() < 0.5
		var p1 := _l_cells(a, mid, flip)
		p1.append_array(_l_cells(mid, b, not flip))
		tries.append(p1)
	var first := rng.randf() < 0.5
	tries.append(_l_cells(a, b, first))
	tries.append(_l_cells(a, b, not first))
	for t in tries:
		if _path_clear(t, clear):
			return t
	return _grid_path(a, b, clear)


func _path_clear(path: Array, clear: Callable) -> bool:
	for p in path:
		for o in BRUSH:
			if not clear.call(p + o):
				return false
	return true


## A 4-connected search over brush origins whose cells pass `clear` (a and b always pass).
func _grid_path(a: Vector2i, b: Vector2i, clear: Callable) -> Array:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for x in w:
		for y in h:
			var p := Vector2i(x, y)
			if p == a or p == b:
				continue
			for o in BRUSH:
				if not clear.call(p + o):
					astar.set_point_solid(p, true)
					break
	var ids := astar.get_id_path(a, b)
	return Array(ids) if not ids.is_empty() else []


## The cells of an L from a to b: along x first (or along y first when `y_first`).
func _l_cells(a: Vector2i, b: Vector2i, y_first: bool) -> Array:
	var corner := Vector2i(a.x, b.y) if y_first else Vector2i(b.x, a.y)
	var out := _line_cells(a, corner)
	out.append_array(_line_cells(corner, b))
	return out


func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var out: Array = []
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		p += step
	return out


func _carve_path(path: Array) -> void:
	for p in path:
		for o in BRUSH:
			if get_cell(p + o) == CELL_WALL:
				_set_cell(p + o, CELL_FLOOR)


## Every floor has one merchant room (#6): the normal room closest to a medium size (seeded like
## everything else). It gets no monsters, hazards or loose props, and monsters never path into it.
func _mark_merchant_room(rooms: Array) -> void:
	var best := INF
	var pick := -1
	for i in range(2, rooms.size()):
		var r: Rect2i = rooms[i].rect
		var score := absf(r.size.x - 11) + absf(r.size.y - 9) + rng.randf() * 2.0
		if r.size.x < 9 or r.size.y < 8:
			score += 100.0
		if score < best:
			best = score
			pick = i
	if pick >= 0 and rooms.size() > 3:
		rooms[pick].role = "merchant"


## #23 / #30 / #31: the merchant room hangs off a shallower room and the boss chamber off the
## room farthest from the start along the room graph, each through one corridor that touches
## nothing else and one 2-cell door in its top or bottom wall. The boss is then strictly the
## farthest room (one more step than the deepest ordinary room) and both are dead ends.
## False when the ordinary rooms aren't all connected or a leaf can't be attached.
func _attach_leaves(rooms: Array) -> bool:
	var core := _core_rooms(rooms)
	var hops := room_hops(room_graph(cells, Vector2i(w, h), rooms), 0)
	var max_h := 0
	for i in core:
		if not hops.has(i):
			return false
		max_h = maxi(max_h, int(hops[i]))
	var mi := -1
	for i in rooms.size():
		if rooms[i].role == "merchant":
			mi = i
	if mi >= 0:
		var mc: Vector2i = rooms[mi].rect.get_center()
		var near: Array = core.filter(func(i): return int(hops[i]) < max_h)
		near.sort_custom(func(a, b): return (rooms[a].rect.get_center() - mc).length_squared() < (rooms[b].rect.get_center() - mc).length_squared())
		if not near.any(func(i): return _carve_leaf(rooms, mi, i)):
			return false
	var dist := _walk_dist(rooms[0].rect.get_center())
	var deep: Array = core.filter(func(i): return int(hops[i]) == max_h)
	var far_cell := func(i: int) -> int:
		return int(dist.get(Rect2i(rooms[i].rect).get_center(), 0))
	deep.sort_custom(func(a, b): return far_cell.call(a) > far_cell.call(b))
	return deep.any(func(i): return _carve_leaf(rooms, 1, i))


## Carves the one corridor of leaf room `li` to room `xi`: a straight stub out of the middle of
## the leaf's top or bottom wall, then an L (or a grid search) to xi's centre that stays a cell
## away from every other floor cell (it only opens into xi itself).
func _carve_leaf(rooms: Array, li: int, xi: int) -> bool:
	var leaf: Rect2i = rooms[li].rect
	var target: Rect2i = rooms[xi].rect
	var lring := leaf.grow(1)
	# Only the target's own floor may be touched: merging with a corridor at its doorway would
	# join the leaf to that corridor's other room too.
	var free_zone := target
	var near := {}
	for x in w:
		for y in h:
			var c := Vector2i(x, y)
			if cells[_idx(c)] != CELL_WALL and not free_zone.has_point(c):
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						near[c + Vector2i(dx, dy)] = true
	var clear := func(c: Vector2i) -> bool:
		if c.x <= 1 or c.y <= 1 or c.x >= w - 2 or c.y >= h - 2:
			return false
		return free_zone.has_point(c) or (not near.has(c) and not lring.has_point(c))
	var x0 := leaf.get_center().x - 1
	var sides := [1, -1] if target.get_center().y > leaf.get_center().y else [-1, 1]
	for side in sides:
		var wall_y := leaf.end.y if side > 0 else leaf.position.y - 1
		var out_y := leaf.end.y + 2 if side > 0 else leaf.position.y - 4
		# The stub's own cells: through the wall (2 wide) and two rows beyond the ring.
		var stub: Array = _line_cells(Vector2i(x0, wall_y if side > 0 else wall_y - 1), Vector2i(x0, out_y))
		var stub_ok := true
		for p in stub:
			for o in BRUSH:
				var c: Vector2i = p + o
				if c.x <= 1 or c.y <= 1 or c.x >= w - 2 or c.y >= h - 2 or (near.has(c) and not leaf.has_point(c) and not lring.has_point(c)):
					stub_ok = false
		if not stub_ok:
			continue
		var s := Vector2i(x0, out_y)
		var path := []
		for y_first in [false, true]:
			var t := _l_cells(s, target.get_center(), y_first)
			if _path_clear(t.slice(1), clear):
				path = t
				break
		if path.is_empty():
			path = _grid_path(s, target.get_center(), clear)
		if path.is_empty():
			continue
		_carve_path(stub)
		_carve_path(path)
		rooms[xi].leaf_anchor = true  # its walls stay square (a reading room would cut the way in)
		return true
	return false


## Walking distance in cells from `from` to every reachable cell.
func _walk_dist(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for o in SIDES4:
			var n: Vector2i = c + o
			if not dist.has(n) and walkable(get_cell(n)):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


## The room graph of a carved grid (#30): rooms (not the sealed prison) are nodes, joined when a
## corridor runs from one to the other without entering a third room. adj[i] = {j: true}.
static func room_graph(grid: PackedByteArray, size: Vector2i, rooms: Array) -> Array:
	var owner := {}
	for i in rooms.size():
		if rooms[i].role == "prison":
			continue
		var r: Rect2i = rooms[i].rect
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				owner[Vector2i(x, y)] = i
	var cell := func(c: Vector2i) -> int:
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			return CELL_WALL
		return grid[c.y * size.x + c.x]
	var adj: Array = []
	for i in rooms.size():
		adj.append({})
	for i in rooms.size():
		if rooms[i].role == "prison":
			continue
		var r: Rect2i = rooms[i].rect
		var seen := {}
		var queue: Array = []
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var c := Vector2i(x, y)
				if walkable(cell.call(c)) or cell.call(c) == CELL_CANAL:
					seen[c] = true
					queue.append(c)
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for o in SIDES4:
				var n: Vector2i = c + o
				if seen.has(n) or not walkable(cell.call(n)):
					continue
				seen[n] = true
				var j: int = owner.get(n, -1)
				if j == -1:
					queue.append(n)
				elif j != i:
					adj[i][j] = true
					adj[j][i] = true
	return adj


## Steps along the room graph from room `from` to every room it reaches.
static func room_hops(adj: Array, from: int) -> Dictionary:
	var hops := {from: 0}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		for j in adj[i]:
			if not hops.has(j):
				hops[j] = int(hops[i]) + 1
				queue.append(j)
	return hops


## Walkable openings in the wall ring around `rect` (runs of open ring cells).
static func room_openings(grid: PackedByteArray, size: Vector2i, rect: Rect2i) -> int:
	var ring: Array = []
	var r := rect.grow(1)
	for x in range(r.position.x, r.end.x):
		ring.append(Vector2i(x, r.position.y))
	for y in range(r.position.y + 1, r.end.y):
		ring.append(Vector2i(r.end.x - 1, y))
	for x in range(r.end.x - 2, r.position.x - 1, -1):
		ring.append(Vector2i(x, r.end.y - 1))
	for y in range(r.end.y - 2, r.position.y, -1):
		ring.append(Vector2i(r.position.x, y))
	var open := func(c: Vector2i) -> bool:
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			return false
		return walkable(grid[c.y * size.x + c.x])
	var runs := 0
	for k in ring.size():
		if open.call(ring[k]) and not open.call(ring[k - 1]):
			runs += 1
	if runs == 0 and ring.all(func(c): return open.call(c)):
		runs = 1
	return runs


## The floor's one merchant (#6): a seeded pick weighted by merchants.json "floor_pick", from its
## own random stream so the layout itself doesn't depend on it.
## Monster tiers (#8): the strongest tier that may spawn on `at_depth` (balance.json
## scaling.tier_depths lists the first depth of tiers 1, 2, 3...).
static func tier_allowed(at_depth: int) -> int:
	var firsts: Array = GameData.bal("scaling.tier_depths", [1])
	var t := 1
	for i in firsts.size():
		if at_depth >= int(firsts[i]):
			t = i + 1
	return t


## Can monster `id` spawn in a floor's packs on `at_depth`? (Its data "tier", default 1.)
static func spawnable(id: String, at_depth: int) -> bool:
	return int(GameData.monsters.get(id, {}).get("tier", 1)) <= tier_allowed(at_depth)


static func pick_merchant(seed_value: int) -> String:
	var weights: Dictionary = GameData.merchants.get("floor_pick", {"archibald": 1, "malphas": 1})
	var ids: Array = weights.keys()
	ids.sort()
	var total := 0.0
	for id in ids:
		total += float(weights[id])
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 313
	var roll := r.randf() * total
	for id in ids:
		roll -= float(weights[id])
		if roll < 0.0:
			return str(id)
	return str(ids[-1])


## The merchant stands in the middle of its room: {room, npc, pos}. {} when there is no room.
func _merchant_layout(rooms: Array, used: Dictionary, npc: String) -> Dictionary:
	for i in rooms.size():
		if rooms[i].role != "merchant":
			continue
		var r: Rect2i = rooms[i].rect
		var out := {"room": i, "npc": npc, "pos": _cell_center(r.get_center() + Vector2i(0, -1))}
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
						var kind := str(room.role) if room.role in ["boss", "merchant"] else ""
						doors.append({"cells": run.duplicate(), "vertical": bool(side[3]), "rect": rect,
							"monster_proof": room.role == "merchant", "kind": kind})
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


## Aqueducts (Sewers): irregular pools of shallow sewage in some normal rooms, with a deep sludge
## core now and then. Pools keep clear of doors, so every room stays reachable.
func _place_pools(rooms: Array, door_zone: Dictionary) -> void:
	var chance := float(gen.get("water_room_chance", 0.0))
	if chance <= 0.0:
		return
	for room in rooms:
		if room.role != "normal" or rng.randf() > chance:
			continue
		var r: Rect2i = room.rect
		var pw := rng.randi_range(3, maxi(3, mini(7, r.size.x - 4)))
		var ph := rng.randi_range(2, maxi(2, mini(5, r.size.y - 4)))
		var pos := Vector2i(rng.randi_range(r.position.x + 2, r.end.x - 2 - pw), rng.randi_range(r.position.y + 2, r.end.y - 2 - ph))
		var sludge := rng.randf() < float(gen.get("sludge_chance", 0.0))
		for x in range(pos.x - 1, pos.x + pw + 1):
			for y in range(pos.y - 1, pos.y + ph + 1):
				var c := Vector2i(x, y)
				var edge := x < pos.x or y < pos.y or x >= pos.x + pw or y >= pos.y + ph
				if door_zone.has(c) or get_cell(c) != CELL_FLOOR or not r.has_point(c):
					continue
				if edge and rng.randf() < 0.5:
					continue  # ragged rim
				var core := not edge and x > pos.x and y > pos.y and x < pos.x + pw - 1 and y < pos.y + ph - 1
				_set_cell(c, CELL_SLUDGE if sludge and core else CELL_WATER)


## Toxic canals (Sewers) cut across some rooms, 2 cells wide, with a catwalk bridge across.
## A canal never runs into a door, so both halves keep their doors and the bridge joins them.
func _place_canals(rooms: Array, door_zone: Dictionary) -> void:
	var chance := float(gen.get("canal_room_chance", 0.0))
	if chance <= 0.0:
		return
	for room in rooms:
		if room.role != "normal" or rng.randf() > chance:
			continue
		var r: Rect2i = room.rect
		var horizontal := r.size.x >= r.size.y
		var span := r.size.y if horizontal else r.size.x
		if span < 8:
			continue
		var at := rng.randi_range(3, span - 5)
		var cells_: Array = []
		var ok := true
		for k in 2:
			for i in (r.size.x if horizontal else r.size.y):
				var c := Vector2i(r.position.x + i, r.position.y + at + k) if horizontal else Vector2i(r.position.x + at + k, r.position.y + i)
				if door_zone.has(c) or get_cell(c) == CELL_LAVA:
					ok = false
				cells_.append(c)
			# Both ends must meet solid wall, not an opening.
			var end_a := Vector2i(r.position.x - 1, r.position.y + at + k) if horizontal else Vector2i(r.position.x + at + k, r.position.y - 1)
			var end_b := Vector2i(r.end.x, r.position.y + at + k) if horizontal else Vector2i(r.position.x + at + k, r.end.y)
			if get_cell(end_a) != CELL_WALL or get_cell(end_b) != CELL_WALL:
				ok = false
		if not ok:
			continue
		var length := r.size.x if horizontal else r.size.y
		var b := rng.randi_range(2, length - 4)
		for c in cells_:
			var along: int = (c.x - r.position.x) if horizontal else (c.y - r.position.y)
			_set_cell(c, CELL_BRIDGE if along >= b and along < b + 2 else CELL_CANAL)
			door_zone[c] = true


## Platforms (Foundry): some rooms become a molten lake (walkable, burning lava) with a central
## platform, a platform at every door and railing-less 2-cell metal bridges joining them.
func _place_platforms(rooms: Array, doors: Array, door_zone: Dictionary) -> void:
	var chance := float(gen.get("platform_room_chance", 0.0))
	if chance <= 0.0:
		return
	for room in rooms:
		if room.role != "normal" or rng.randf() > chance:
			continue
		var r: Rect2i = room.rect
		if r.size.x < 10 or r.size.y < 9:
			continue
		var core := Rect2i(r.get_center() - Vector2i(r.size.x / 5, r.size.y / 5), Vector2i(maxi(3, r.size.x * 2 / 5), maxi(3, r.size.y * 2 / 5)))
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var c := Vector2i(x, y)
				if core.has_point(c) or door_zone.has(c) or get_cell(c) != CELL_FLOOR:
					continue
				_set_cell(c, CELL_LAVA)
		# Bridges from each door of this room to the core.
		for d in doors:
			var dc: Vector2i = d.cells[0]
			if not r.grow(1).has_point(dc):
				continue
			var inside: Vector2i = dc.clamp(r.position, r.end - Vector2i.ONE)
			var goal := core.get_center()
			var p := inside
			var step_x := signi(goal.x - p.x)
			var step_y := signi(goal.y - p.y)
			var guard := 0
			while p != goal and guard < 64:
				guard += 1
				for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					if get_cell(p + o) == CELL_LAVA and r.has_point(p + o):
						_set_cell(p + o, CELL_BRIDGE)
				if p.x != goal.x and (d.vertical or p.y == goal.y):
					p.x += step_x
				elif p.y != goal.y:
					p.y += step_y
				else:
					p.x += step_x
		room.platforms = true


## Reading rooms (Archives): some rooms are round - cells outside an ellipse turn to wall, except
## around the doors (a straight 2-cell aisle joins every door to the centre).
func _round_rooms(rooms: Array, doors: Array, door_zone: Dictionary) -> void:
	var chance := float(gen.get("round_room_chance", 0.0))
	if chance <= 0.0:
		return
	for room in rooms:
		if room.role != "normal" or rng.randf() > chance or room.get("leaf_anchor", false):
			continue
		var r: Rect2i = room.rect
		if r.size.x < 11 or r.size.y < 9:
			continue
		var c := Vector2(r.position) + Vector2(r.size) / 2.0
		var rx := r.size.x / 2.0
		var ry := r.size.y / 2.0
		var keep := {}
		for d in doors:
			var dc: Vector2i = d.cells[0]
			if not r.grow(1).has_point(dc):
				continue
			var p := dc.clamp(r.position, r.end - Vector2i.ONE)
			var goal := Vector2i(c)
			var guard := 0
			while p != goal and guard < 64:
				guard += 1
				for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					keep[p + o] = true
				if p.x != goal.x and (d.vertical or p.y == goal.y):
					p.x += signi(goal.x - p.x)
				elif p.y != goal.y:
					p.y += signi(goal.y - p.y)
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var cell := Vector2i(x, y)
				var dx := (x + 0.5 - c.x) / rx
				var dy := (y + 0.5 - c.y) / ry
				if dx * dx + dy * dy > 1.0 and not keep.has(cell) and not door_zone.has(cell) and get_cell(cell) == CELL_FLOOR:
					_set_cell(cell, CELL_WALL)
		room.round = true


## Caverns (Kurgan): the walls of some rooms are eaten into organic shapes - a 2-cell rim is
## randomly walled, smoothed by two cellular-automata passes, and pockets cut off from the room's
## centre are filled in. Door zones and the room's core never change, so every room stays reachable.
func _cave_rooms(rooms: Array, door_zone: Dictionary) -> void:
	var chance := float(gen.get("cave_room_chance", 0.0))
	if chance <= 0.0:
		return
	for room in rooms:
		if room.role != "normal" or rng.randf() > chance:
			continue
		var r: Rect2i = room.rect
		# Corridors that meet the room through a wide opening (not a door) stay open too: the
		# cells where they enter, one step in, and their side neighbours.
		var keep := door_zone.duplicate()
		for x0 in range(r.position.x, r.end.x):
			for y0 in range(r.position.y, r.end.y):
				var e := Vector2i(x0, y0)
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not r.has_point(e + o) and get_cell(e + o) == CELL_FLOOR:
						for dx0 in range(-1, 2):
							for dy0 in range(-1, 2):
								keep[e + Vector2i(dx0, dy0)] = true
								keep[e - o + Vector2i(dx0, dy0)] = true
		var rim := func(c: Vector2i) -> bool:
			return c.x < r.position.x + 2 or c.y < r.position.y + 2 or c.x >= r.end.x - 2 or c.y >= r.end.y - 2
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var c := Vector2i(x, y)
				if rim.call(c) and not keep.has(c) and get_cell(c) == CELL_FLOOR and rng.randf() < 0.45:
					_set_cell(c, CELL_WALL)
		for pass_i in 2:
			var changes := {}
			for x in range(r.position.x, r.end.x):
				for y in range(r.position.y, r.end.y):
					var c2 := Vector2i(x, y)
					if not rim.call(c2) or keep.has(c2):
						continue
					var walls := 0
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							if (dx != 0 or dy != 0) and get_cell(c2 + Vector2i(dx, dy)) == CELL_WALL:
								walls += 1
					if walls >= 5:
						changes[c2] = CELL_WALL
					elif walls <= 2:
						changes[c2] = CELL_FLOOR
			for c3 in changes:
				_set_cell(c3, changes[c3])
		# Fill pockets the centre can't reach.
		var seen := {r.get_center(): true}
		var queue: Array = [r.get_center()]
		while not queue.is_empty():
			var c4: Vector2i = queue.pop_back()
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c4 + o
				if r.has_point(n) and not seen.has(n) and get_cell(n) != CELL_WALL:
					seen[n] = true
					queue.append(n)
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var c5 := Vector2i(x, y)
				if not seen.has(c5) and get_cell(c5) != CELL_WALL and not keep.has(c5):
					_set_cell(c5, CELL_WALL)
		room.cave = true


## Library mazes (Archives): rows of bookshelves (they block sight) with aisles in some rooms.
func _place_shelf_rows(rooms: Array, used: Dictionary) -> Array:
	var out: Array = []
	var chance := float(gen.get("shelf_room_chance", 0.0))
	if chance <= 0.0:
		return out
	for room in rooms:
		if room.role != "normal" or room.get("round", false) or rng.randf() > chance:
			continue
		var r: Rect2i = room.rect
		var gap := rng.randi_range(r.position.x + 2, r.end.x - 4)
		for y in range(r.position.y + 2, r.end.y - 2, 3):
			for x in range(r.position.x + 1, r.end.x - 1):
				var cell := Vector2i(x, y)
				if absi(x - gap) <= 1 or used.has(cell) or get_cell(cell) != CELL_FLOOR:
					continue
				if x % 2 == 0:
					continue  # bookshelf props are one cell wide every other cell
				used[cell] = true
				used[cell + Vector2i(1, 0)] = true
				out.append({"type": "bookshelf", "pos": _cell_center(cell) + Vector2(_tile_half(), 0)})
	return out


func _tile_half() -> float:
	return tile * 0.5


## Spatial anomaly zones (Archives): whole rooms where skill costs fluctuate.
func _place_anomalies(rooms: Array) -> Array:
	var out: Array = []
	var chance := float(gen.get("anomaly_room_chance", 0.0))
	for room in rooms:
		if room.role == "normal" and chance > 0.0 and rng.randf() < chance:
			out.append(room.rect)
	return out


## A handful of free floor spots in normal rooms (void rifts, silence runes).
func _scatter(rooms: Array, used: Dictionary, span: Array) -> Array:
	var out: Array = []
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var normals: Array = rooms.filter(func(rm): return rm.role == "normal")
	var guard := 0
	while out.size() < n and not normals.is_empty() and guard < 200:
		guard += 1
		var room: Dictionary = normals[rng.randi_range(0, normals.size() - 1)]
		var c := _free_cell(room.rect, 2, used, false)
		if c.x >= 0:
			used[c] = true
			out.append(_cell_center(c))
	return out


## Tome Prison (D32): a sealed side arena carved out of solid rock, not connected to anything.
func _side_arena(rooms: Array) -> Rect2i:
	if not gen.has("side_arena"):
		return Rect2i()
	var sz: Array = gen.side_arena
	var rects: Array = rooms.map(func(rm): return rm.rect)
	for i in 300:
		var r := Rect2i(rng.randi_range(3, w - int(sz[0]) - 4), rng.randi_range(3, h - int(sz[1]) - 4), int(sz[0]), int(sz[1]))
		var ok := true
		for x in range(r.position.x - 3, r.end.x + 3):
			for y in range(r.position.y - 3, r.end.y + 3):
				if get_cell(Vector2i(x, y)) != CELL_WALL:
					ok = false
		if ok:
			for x in range(r.position.x, r.end.x):
				for y in range(r.position.y, r.end.y):
					_set_cell(Vector2i(x, y), CELL_FLOOR)
			rooms.append({"rect": r, "role": "prison"})
			return r
	return Rect2i()


## Collapsing grates (Foundry): grates over lava in normal rooms.
func _place_grates(rooms: Array, fd: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	if not gen.has("grates_per_room"):
		return out
	var span: Array = gen.grates_per_room
	for room in rooms:
		if room.role != "normal":
			continue
		for i in rng.randi_range(int(span[0]), int(span[1])):
			var c := _free_cell(room.rect, 2, used, false)
			if c.x < 0:
				continue
			used[c] = true
			_set_cell(c, CELL_GRATE)
			out.append({"cell": c})
	return out


## Wall spouts: acid spouts (Sewers) and flame jets (Foundry) in the north walls of normal rooms,
## spraying down on a timer.
func _place_spouts(rooms: Array, fd: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = fd.get("wall_spouts", {})
	if fd.has("acid_spouts"):
		spec = {"kind": "acid", "count": fd.acid_spouts}
	if spec.is_empty():
		return out
	var cands: Array = []
	for room in rooms:
		if room.role != "normal":
			continue
		var r: Rect2i = room.rect
		for x in range(r.position.x + 1, r.end.x - 1):
			var w := Vector2i(x, r.position.y - 1)
			if get_cell(w) == CELL_WALL and walkable(get_cell(w + Vector2i(0, 1))) and walkable(get_cell(w + Vector2i(0, 2))):
				cands.append(w)
	var n := rng.randi_range(int(spec.count[0]), int(spec.count[1]))
	while out.size() < n and not cands.is_empty():
		var c: Vector2i = cands.pop_at(rng.randi_range(0, cands.size() - 1))
		var clash := false
		for o in out:
			if Vector2(o.cell - c).length() < 4.0:
				clash = true
		if not clash:
			out.append({"cell": c, "dir": Vector2i.DOWN, "phase": rng.randf(), "kind": str(spec.kind)})
	return out


## Floodgates (Sewers): some doors rust shut; a rusty lever beside the door on each side opens it.
func _place_floodgates(doors: Array, rooms: Array, used: Dictionary) -> Array:
	var out: Array = []
	var chance := float(gen.get("floodgate_chance", 0.0))
	if chance <= 0.0:
		return out
	for i in doors.size():
		var d: Dictionary = doors[i]
		if not str(d.kind).is_empty() or rng.randf() > chance:
			continue
		var c0: Vector2i = d.cells[0]
		var across := Vector2i(1, 0) if d.vertical else Vector2i(0, 1)
		var along := Vector2i(0, -1) if d.vertical else Vector2i(-1, 0)
		var levers: Array = []
		for side in [-1, 1]:
			var placed := false
			for k in [0, -1, 1, 2]:
				var lc: Vector2i = c0 + across * side * 3 + along * k
				if get_cell(lc) == CELL_FLOOR and not used.has(lc):
					used[lc] = true
					levers.append({"type": "rusty_lever", "pos": _cell_center(lc), "gate": i})
					placed = true
					break
			if not placed:
				break
		if levers.size() == 2:
			d.floodgate = true
			out.append_array(levers)
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
		if spawnable(str(m.id), _depth):
			ids.append(m.id)
			ws.append(float(m.weight))
	if ids.is_empty():
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
