class_name Dungeon
extends Node2D
## Builds a floor from a DungeonGenerator layout on every peer: tile layers (floor + y-sorted
## walls with collision and light occluders), doors, props, chests, spikes, torches and lava
## lights. Doors and props get deterministic names so the host can address them by RPC.
## Also offers the host-side queries used by AI and combat (paths, doors, props, hazards).

const DOOR_SCRIPT := preload("res://scripts/dungeon/door.gd")
const PROP_SCRIPT := preload("res://scripts/dungeon/prop.gd")
const SPIKES_SCRIPT := preload("res://scripts/dungeon/spikes.gd")
const TORCH_SCRIPT := preload("res://scripts/dungeon/torch.gd")

var layout: Dictionary = {}
var floor_def: Dictionary = {}
var tile := 32
var size := Vector2i.ZERO
var cells := PackedByteArray()
var astar := AStarGrid2D.new()
var doors: Array = []
var props: Dictionary = {}  ## name -> Prop
var debris: Array = []  ## destroyed props (still in the tree as rubble until the floor ends)
var spikes: Array = []
var lights: Array = []  ## torch / lava lights, culled by distance in Visibility
var discovered := PackedByteArray()  ## local fog-of-war memory (per peer)

var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var entities: Node2D  ## y-sorted parent shared with actors (set by Game)


func build(new_layout: Dictionary, def: Dictionary, entity_root: Node2D) -> void:
	clear()
	layout = new_layout
	floor_def = def
	entities = entity_root
	tile = int(GameData.bal("world.tile_size"))
	size = layout.size
	cells = layout.cells
	discovered = PackedByteArray()
	discovered.resize(size.x * size.y)
	_build_tiles()
	_build_astar()
	var n := 0
	for d in layout.doors:
		var door: Node2D = DOOR_SCRIPT.new()
		door.name = "Door_%d" % n
		door.setup(d, tile)
		entities.add_child(door)
		doors.append(door)
		for c in d.cells:
			astar.set_point_weight_scale(c, 3.0)
		n += 1
	n = 0
	for p in layout.props:
		_add_prop("Prop_%d" % n, str(p.type), p.pos)
		n += 1
	n = 0
	for cpos in layout.chests:
		_add_prop("Chest_%d" % n, "chest", cpos)
		n += 1
	for s in layout.spikes:
		var sp: Node2D = SPIKES_SCRIPT.new()
		sp.setup(s.cell, tile, float(s.phase))
		add_child(sp)
		spikes.append(sp)
	for t in layout.torches:
		var torch: Node2D = TORCH_SCRIPT.new()
		torch.position = Vector2(t.cell * tile) + Vector2(tile / 2.0, tile - 6.0)
		torch.color = Color.from_string(str(floor_def.get("torch_color", "#ff9944")), Color.ORANGE)
		entities.add_child(torch)
		lights.append(torch.light)
	for pool in layout.lava_pools:
		var l := PointLight2D.new()
		l.texture = GameData.texture("fx.light")
		l.color = Color.from_string(str(floor_def.get("lava_color", "#ff5511")), Color.ORANGE_RED)
		l.energy = 1.1
		l.texture_scale = maxf(pool.size.x, pool.size.y) * tile / 90.0
		l.position = Vector2(pool.position * tile) + Vector2(pool.size * tile) / 2.0
		add_child(l)
		lights.append(l)


## Removes the previous floor. Nodes are detached from the tree immediately (not just queued):
## the next floor reuses the same deterministic names (Door_0, Prop_0, ...), and a name that is
## still taken would get auto-renamed, breaking the RPCs that address doors and props.
func clear() -> void:
	for d in doors:
		_discard(d)
	doors.clear()
	for p in props.values():
		_discard(p)
	props.clear()
	for p in debris:
		_discard(p)
	debris.clear()
	for s in spikes:
		_discard(s)
	spikes.clear()
	for l in lights:
		if is_instance_valid(l):
			var torch: Node = l.get_parent()
			_discard(torch if torch != self else l)
	lights.clear()
	_discard(floor_layer)
	floor_layer = null
	_discard(wall_layer)
	wall_layer = null


func _discard(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.queue_free()


# --- Tiles ---------------------------------------------------------------------------------------


func _build_tiles() -> void:
	var tiles_entry := GameData.asset_entry(str(floor_def.tiles))
	var ts := _make_tileset(tiles_entry)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = ts
	floor_layer.z_index = -10
	add_child(floor_layer)
	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = ts
	wall_layer.y_sort_enabled = true
	entities.add_child(wall_layer)
	var floors: Array = tiles_entry.floor
	var faces: Array = tiles_entry.wall_face
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(size) ^ cells.size()
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			var v := cell_at(c)
			if v == DungeonGenerator.CELL_FLOOR:
				var f: Array = floors[rng.randi_range(0, floors.size() - 1)] if rng.randf() < 0.35 else floors[0]
				floor_layer.set_cell(c, 0, Vector2i(int(f[0]), int(f[1])))
			elif v == DungeonGenerator.CELL_LAVA:
				var lv: Array = tiles_entry.lava
				floor_layer.set_cell(c, 0, Vector2i(int(lv[0]), int(lv[1])))
			else:
				if not _near_floor(c):
					continue
				var below := cell_at(c + Vector2i(0, 1))
				if below != DungeonGenerator.CELL_WALL:
					var fc: Array = faces[(x * 7 + y * 3) % faces.size()]
					wall_layer.set_cell(c, 0, Vector2i(int(fc[0]), int(fc[1])))
				else:
					var wt: Array = tiles_entry.wall_top
					wall_layer.set_cell(c, 0, Vector2i(int(wt[0]), int(wt[1])))


func _near_floor(c: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if cell_at(c + Vector2i(dx, dy)) != DungeonGenerator.CELL_WALL:
				return true
	return false


func _make_tileset(entry: Dictionary) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile, tile)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_occlusion_layer()
	var src := TileSetAtlasSource.new()
	src.texture = load(str(entry.path))
	src.texture_region_size = Vector2i(tile, tile)
	ts.add_source(src, 0)
	var half := tile / 2.0
	var full := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var face_top := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, -half + 6), Vector2(-half, -half + 6)])
	var all_tiles: Array = []
	for f in entry.floor:
		all_tiles.append([Vector2i(int(f[0]), int(f[1])), "floor"])
	all_tiles.append([Vector2i(int(entry.wall_top[0]), int(entry.wall_top[1])), "top"])
	for f in entry.wall_face:
		all_tiles.append([Vector2i(int(f[0]), int(f[1])), "face"])
	all_tiles.append([Vector2i(int(entry.lava[0]), int(entry.lava[1])), "lava"])
	for t in all_tiles:
		var coords: Vector2i = t[0]
		if not src.has_tile(coords):
			src.create_tile(coords)
		var data := src.get_tile_data(coords, 0)
		match t[1]:
			"top", "face":
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, full)
				var occ := OccluderPolygon2D.new()
				occ.polygon = full if t[1] == "top" else face_top
				data.set_occluder(0, occ)
				data.y_sort_origin = int(half)
	return ts


# --- AStar + queries ------------------------------------------------------------------------


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(tile, tile)
	astar.offset = Vector2(tile, tile) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in size.y:
		for x in size.x:
			var v := cell_at(Vector2i(x, y))
			if v == DungeonGenerator.CELL_WALL:
				astar.set_point_solid(Vector2i(x, y), true)
			elif v == DungeonGenerator.CELL_LAVA:
				astar.set_point_weight_scale(Vector2i(x, y), 25.0)


func cell_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return DungeonGenerator.CELL_WALL
	return cells[c.y * size.x + c.x]


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / tile), floori(pos.y / tile))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c * tile) + Vector2(tile, tile) / 2.0


func is_lava(pos: Vector2) -> bool:
	return cell_at(cell_of(pos)) == DungeonGenerator.CELL_LAVA


func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size * tile))


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := cell_of(from)
	var b := cell_of(to)
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
		return PackedVector2Array()
	if astar.is_point_solid(b):
		return PackedVector2Array([to])
	var path := astar.get_point_path(a, b, true)
	if path.size() > 0:
		path.remove_at(0)
	if path.is_empty():
		return PackedVector2Array([to])
	path[path.size() - 1] = to
	return path


func closed_door_near(pos: Vector2, next: Vector2) -> Node:
	for d in doors:
		if d.is_open:
			continue
		var r: Rect2 = d.world_rect.grow(14.0)
		if r.has_point(pos) or (r.has_point(next) and pos.distance_to(next) < 48.0):
			return d
	return null


func props_in_radius(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for p in props.values():
		if is_instance_valid(p) and p.destructible() and p.global_position.distance_to(pos) <= r + 10.0:
			out.append(p)
	return out


func _add_prop(prop_name: String, type: String, pos: Vector2) -> void:
	var p: StaticBody2D = PROP_SCRIPT.new()
	p.name = prop_name
	p.prop_id = prop_name
	p.setup(type, pos)
	entities.add_child(p)
	props[prop_name] = p
	if p.blocks_path():
		astar.set_point_solid(cell_of(pos), true)


## Host -> all (reliable, call_local): a prop was destroyed.
@rpc("authority", "call_local", "reliable")
func destroy_prop(prop_name: String) -> void:
	var p: Node = props.get(prop_name)
	if p == null or not is_instance_valid(p):
		return
	props.erase(prop_name)
	debris.append(p)
	astar.set_point_solid(cell_of(p.global_position), false)
	p.break_apart()


## Host -> all (reliable, call_local): a chest was opened.
@rpc("authority", "call_local", "reliable")
func open_chest(prop_name: String) -> void:
	var p: Node = props.get(prop_name)
	if p and is_instance_valid(p):
		p.set_opened()


# --- Fog of war memory (local) ------------------------------------------------------------------


func is_discovered(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return false
	return discovered[c.y * size.x + c.x] == 1


func mark_discovered(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return false
	var i := c.y * size.x + c.x
	if discovered[i] == 1:
		return false
	discovered[i] = 1
	return true


## Cells that block sight for the grid FOV (walls and closed doors).
func blocks_sight(c: Vector2i) -> bool:
	if cell_at(c) == DungeonGenerator.CELL_WALL:
		return true
	for d in doors:
		if not d.is_open and d.cells.has(c):
			return true
	return false
