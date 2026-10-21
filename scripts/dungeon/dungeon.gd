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
const BACK_LINE := 4.0  ## #79: px behind a wall face's top where lights behind the wall stop
const PLATE_SCRIPT := preload("res://scripts/dungeon/pressure_plate.gd")
const SPOUT_SCRIPT := preload("res://scripts/dungeon/wall_spout.gd")
const GRATE_SCRIPT := preload("res://scripts/dungeon/grate.gd")

var layout: Dictionary = {}
var floor_def: Dictionary = {}
var tile := 32
var size := Vector2i.ZERO
var cells := PackedByteArray()
var astar := AStarGrid2D.new()
var doors: Array = []
var props: Dictionary = {}  ## name -> Prop
var torches: Dictionary = {}  ## torch id -> wall torch
var debris: Array = []  ## destroyed props (still in the tree as rubble until the floor ends)
var spikes: Array = []
var plates: Array = []  ## pressure plates (Crypt)
var plate_by_id: Dictionary = {}
var spouts: Array = []  ## wall spouts: acid (Sewers), flame jets (Foundry)
var grates: Array = []  ## collapsing grates (Foundry)
var grate_by_id: Dictionary = {}
var pulse_props: Array = []  ## props that pulse damage around them (boiling cauldrons)
var anomalies: Array = []  ## Archives: world rects where skill costs fluctuate
var proximity_props: Array = []  ## host: props that go off when a hero comes close (gas pockets)
var lights: Array = []  ## torch / lava lights, culled by distance in Visibility
var obstacles: Dictionary = {}  ## dynamic terrain id -> {node, cells}
var safe_rect := Rect2i()  ## the merchant room (cells): monsters never path into it or target anyone inside
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
	for d0 in layout.doors:
		var d: Dictionary = d0
		if not str(d.get("kind", "")).is_empty():
			# The sealed chambers' doors (#23 / #31): the boss door, or the floor merchant's own.
			d = d0.duplicate()
			d.type = str(layout.get("merchant", {}).get("npc", "")) if d.kind == "merchant" else "boss"
			d.biome = str(def.get("id", ""))
		var door: Node2D = DOOR_SCRIPT.new()
		door.name = "Door_%d" % n
		door.setup(d, tile)
		entities.add_child(door)
		doors.append(door)
		if door.light:
			lights.append(door.light)
		for c in d.cells:
			astar.set_point_weight_scale(c, 3.0)
		n += 1
	n = 0
	for p in layout.props:
		_add_prop("Prop_%d" % n, str(p.type), p.pos)
		if p.has("gate"):
			props["Prop_%d" % n].set_meta("gate", int(p.gate))
		n += 1
	# The floor's merchant (the same name on every peer).
	var m: Dictionary = layout.get("merchant", {})
	safe_rect = Rect2i()
	if not m.is_empty():
		safe_rect = layout.rooms[int(m.room)].rect
		for x in range(safe_rect.position.x, safe_rect.end.x):
			for y in range(safe_rect.position.y, safe_rect.end.y):
				astar.set_point_solid(Vector2i(x, y), true)
		_add_prop("Merchant", str(m.npc), m.pos)
	n = 0
	for cpos in layout.chests:
		_add_prop("Chest_%d" % n, "chest", cpos)
		n += 1
	for s in layout.spikes:
		var sp: Node2D = SPIKES_SCRIPT.new()
		sp.setup(s.cell, tile, float(s.phase))
		add_child(sp)
		spikes.append(sp)
	n = 0
	for pd in layout.get("plates", []):
		var plate: Node2D = PLATE_SCRIPT.new()
		plate.setup(pd.cell, tile, "Plate_%d" % n)
		add_child(plate)
		plates.append(plate)
		plate_by_id[plate.plate_id] = plate
		n += 1
	for sp2 in layout.get("spouts", []):
		var spout: Node2D = SPOUT_SCRIPT.new()
		spout.setup(sp2.cell, sp2.dir, tile, float(sp2.phase), str(sp2.get("kind", "acid")))
		entities.add_child(spout)
		spouts.append(spout)
	anomalies.clear()
	for ar in layout.get("anomalies", []):
		anomalies.append(Rect2(Vector2(ar.position * tile), Vector2(ar.size * tile)))
	n = 0
	for gr in layout.get("grates", []):
		var grate: Node2D = GRATE_SCRIPT.new()
		grate.setup(gr.cell, tile, "Grate_%d" % n)
		add_child(grate)
		grates.append(grate)
		grate_by_id[grate.grate_id] = grate
		n += 1
	n = 0
	for t in layout.torches:
		var torch: Node2D = TORCH_SCRIPT.new()
		torch.name = "Torch_%d" % n
		torch.torch_id = torch.name
		torch.cell = t.cell
		# Sorted just in front of the wall cell (its y-sort origin is the cell's bottom edge),
		# otherwise the wall tile is drawn over the torch; the sprite itself sits up on the wall.
		torch.position = Vector2(t.cell * tile) + Vector2(tile / 2.0, tile + 2.0)
		torch.color = Color.from_string(str(floor_def.get("torch_color", "#ff9944")), Color.ORANGE)
		entities.add_child(torch)
		torches[torch.torch_id] = torch
		lights.append(torch.light)
		n += 1
	for pool in layout.lava_pools:
		var l := PointLight2D.new()
		LightLayers.setup_light(l)
		l.texture = GameData.texture("fx.light")
		l.color = Color.from_string(str(floor_def.get("lava_color", "#ff5511")), Color.ORANGE_RED)
		l.energy = 1.1
		LightLayers.register(l, float(GameData.bal("lighting.lava_light_per_cell")) * maxf(pool.size.x, pool.size.y))
		l.position = Vector2(pool.position * tile) + Vector2(pool.size * tile) / 2.0
		add_child(l)
		lights.append(l)
		l.add_child(_heat_shimmer(Vector2(pool.size * tile) / 2.0))


## #81 16: heat shimmering over a lava pool: faint pale wisps rising and fading (additive,
## unshaded), spread over the pool's `half` extents.
func _heat_shimmer(half: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.light")
	p.amount = clampi(int(half.x * half.y / 900.0), 4, 24)
	p.lifetime = 1.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = half * 0.9
	p.direction = Vector2.UP
	p.spread = 8.0
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.5, 0.0))
	ramp.add_point(0.4, Color(1.0, 0.8, 0.6, 0.12))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.9, 0.8, 0.0))
	p.color_ramp = ramp
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	p.material = m
	p.z_index = 3
	return p


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
	for t in torches.values():
		_discard(t)
	torches.clear()
	for s in spikes:
		_discard(s)
	spikes.clear()
	for pl in plates:
		_discard(pl)
	plates.clear()
	plate_by_id.clear()
	for sp in spouts:
		_discard(sp)
	spouts.clear()
	for gr in grates:
		_discard(gr)
	grates.clear()
	grate_by_id.clear()
	pulse_props.clear()
	proximity_props.clear()
	for l in lights:
		if is_instance_valid(l):
			var torch: Node = l.get_parent()
			_discard(torch if torch != self else l)
	lights.clear()
	for id in obstacles.keys():
		_discard(obstacles[id].node)
	obstacles.clear()
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
			elif SPECIAL_TILES.has(v):
				var key: String = SPECIAL_TILES[v]
				var st: Array = tiles_entry.get(key, tiles_entry.floor[0])
				floor_layer.set_cell(c, 0, Vector2i(int(st[0]), int(st[1])))
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


## Cell kinds drawn from a named tile of the biome's atlas ("water", "sludge", ...).
const SPECIAL_TILES := {DungeonGenerator.CELL_WATER: "water", DungeonGenerator.CELL_SLUDGE: "sludge",
	DungeonGenerator.CELL_CANAL: "canal", DungeonGenerator.CELL_BRIDGE: "bridge", DungeonGenerator.CELL_GRATE: "lava"}


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
	# Canals block movement only (layer 128, like movement obstacles): sight and shots pass.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, 128)
	ts.set_physics_layer_collision_mask(1, 0)
	ts.add_occlusion_layer()
	# #79: a second layer for the wall face's back line (one-sided, see below).
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
	for k in ["water", "sludge", "bridge"]:
		if entry.has(k):
			all_tiles.append([Vector2i(int(entry[k][0]), int(entry[k][1])), "floor"])
	if entry.has("canal"):
		all_tiles.append([Vector2i(int(entry.canal[0]), int(entry.canal[1])), "canal"])
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
				if t[1] == "face":
					# #79: a light pressed against the back of a wall (a hero's light at its feet,
					# 8 px off the wall) lit the face's top strip, which shows in the room in front
					# as a glow along the top of its wall. A line 4 px behind the face's top that
					# casts only for lights behind it (north) moves that shadow's start off the
					# wall art; lights in front of the face are on its open side.
					var back := OccluderPolygon2D.new()
					back.closed = false
					back.cull_mode = OccluderPolygon2D.CULL_CLOCKWISE
					back.polygon = PackedVector2Array([Vector2(-half, -half - BACK_LINE), Vector2(half, -half - BACK_LINE)])
					data.set_occluder(1, back)
				data.y_sort_origin = int(half)
			"canal":
				data.add_collision_polygon(1)
				data.set_collision_polygon_points(1, 0, full)
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
			elif v == DungeonGenerator.CELL_CANAL:
				astar.set_point_solid(Vector2i(x, y), true)
			elif v == DungeonGenerator.CELL_WATER or v == DungeonGenerator.CELL_SLUDGE:
				astar.set_point_weight_scale(Vector2i(x, y), 2.0)


func cell_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return DungeonGenerator.CELL_WALL
	return cells[c.y * size.x + c.x]


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / tile), floori(pos.y / tile))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c * tile) + Vector2(tile, tile) / 2.0


## Inside the merchant room (secure ground).
func is_safe(pos: Vector2) -> bool:
	return safe_rect.size != Vector2i.ZERO and safe_rect.has_point(cell_of(pos))


func in_anomaly(pos: Vector2) -> bool:
	for r in anomalies:
		if r.has_point(pos):
			return true
	return false


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


## Destructible things (props and lit wall torches) around `pos`.
func props_in_radius(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for p in props.values():
		if is_instance_valid(p) and p.destructible() and p.global_position.distance_to(pos) <= r + 10.0:
			out.append(p)
	for t in torches.values():
		if is_instance_valid(t) and t.destructible() and t.global_position.distance_to(pos) <= r + 10.0:
			out.append(t)
	return out


## Host -> all (reliable): a prop that wasn't in the layout appears (elite altars, merchant
## chamber pieces). Its name comes from the host so later RPCs can address it.
@rpc("authority", "call_local", "reliable")
func spawn_prop(prop_name: String, type: String, pos: Vector2) -> void:
	if props.has(prop_name):
		return
	_add_prop(prop_name, type, pos)


## Host -> all (reliable): dynamic terrain appears on these cells for `lifetime` seconds (D30).
## blocks: "all" (movement and projectiles, layer 64), "movement" (layer 128) or "none".
## Every peer removes it on its own when the lifetime ends.
@rpc("authority", "call_local", "reliable")
func add_obstacle(id: int, kind: String, cell_list: Array, lifetime: float, blocks: String) -> void:
	var def: Dictionary = GameData.obstacles.get(kind, {})
	var body := StaticBody2D.new()
	body.name = "Obstacle_%d" % id
	body.collision_layer = 64 if blocks == "all" else (128 if blocks == "movement" else 0)
	body.collision_mask = 0
	var color := Color.from_string(str(def.get("color", "#555555")), Color.GRAY)
	for c in cell_list:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(tile, tile) * 0.9
		cs.shape = rect
		cs.position = cell_center(c)
		body.add_child(cs)
		if def.has("sprite") and GameData.asset_exists(str(def.sprite)):
			var s := Sprite2D.new()
			s.texture = GameData.texture(str(def.sprite))
			s.position = cell_center(c) + Vector2(0, -6)
			body.add_child(s)
		else:
			body.add_child(_obstacle_placeholder(str(def.get("style", "spikes")), color, cell_center(c)))
		if blocks != "none" and astar.is_in_boundsv(c):
			astar.set_point_solid(c, true)
	if def.has("light"):
		var l := PointLight2D.new()
		LightLayers.setup_light(l)
		l.texture = GameData.texture("fx.light")
		l.color = Color.from_string(str(def.light), Color.ORANGE)
		l.energy = 0.9
		LightLayers.register(l, tile * 2.0)
		var center := Vector2.ZERO
		for c2 in cell_list:
			center += cell_center(c2)
		l.position = center / maxf(cell_list.size(), 1)
		body.add_child(l)
	if entities:
		entities.add_child(body)
	obstacles[id] = {"node": body, "cells": cell_list, "blocks": blocks, "kind": kind}
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(remove_obstacle.bind(id))


## Drawn stand-in for obstacle art: "flames" (rising particles over a glowing base), "spikes"
## (jagged dark shards) or "block" (a solid lump).
func _obstacle_placeholder(style: String, color: Color, at: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = at
	var h := tile * 0.45
	var base := Polygon2D.new()
	match style:
		"flames":
			base.polygon = _ellipse(h, h * 0.45, 10)
			base.color = Color(color.r * 1.4, color.g * 1.2, color.b, 0.55)
			n.add_child(base)
			var p := CPUParticles2D.new()
			p.texture = GameData.texture("fx.spark")
			p.amount = 14
			p.lifetime = 0.7
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(h, 3)
			p.direction = Vector2.UP
			p.spread = 12.0
			p.gravity = Vector2(0, -60)
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 45.0
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.6
			p.color = Color(color.r * 1.8, color.g * 1.5, color.b * 1.2)
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = mat
			n.add_child(p)
		"block":
			base.polygon = PackedVector2Array([Vector2(-h, -h * 1.2), Vector2(h, -h * 1.2), Vector2(h, h * 0.6), Vector2(-h, h * 0.6)])
			base.color = Color(color, 0.95)
			n.add_child(base)
		_:
			var pts := PackedVector2Array()
			var spikes := 5
			for i in spikes * 2 + 1:
				var x := lerpf(-h, h, float(i) / (spikes * 2))
				pts.append(Vector2(x, -h * (1.7 if i % 2 == 1 else 0.3) + (i * 37 % 7) - 3.0))
			pts.append(Vector2(h, h * 0.5))
			pts.append(Vector2(-h, h * 0.5))
			base.polygon = pts
			base.color = Color(color, 0.95)
			n.add_child(base)
			var edge := Line2D.new()
			edge.points = pts
			edge.closed = true
			edge.width = 1.0
			edge.default_color = color.lightened(0.35)
			n.add_child(edge)
	return n


static func _ellipse(rx: float, ry: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(Vector2(cos(TAU * i / n) * rx, sin(TAU * i / n) * ry))
	return out


func remove_obstacle(id: int) -> void:
	var o: Dictionary = obstacles.get(id, {})
	obstacles.erase(id)
	if o.is_empty():
		return
	if o.blocks != "none":
		for c in o.cells:
			if astar.is_in_boundsv(c) and DungeonGenerator.walkable(cell_at(c)):
				astar.set_point_solid(c, false)
	_discard(o.node)


## Host -> all (reliable, call_local): a wall torch was taken or broken.
@rpc("authority", "call_local", "reliable")
func set_torch_state(torch_id: String, new_state: int) -> void:
	var t: Node = torches.get(torch_id)
	if t and is_instance_valid(t):
		t.set_state(new_state)


func _add_prop(prop_name: String, type: String, pos: Vector2) -> void:
	var p: StaticBody2D = PROP_SCRIPT.new()
	p.name = prop_name
	p.prop_id = prop_name
	p.setup(type, pos)
	entities.add_child(p)
	props[prop_name] = p
	if p.def.has("proximity"):
		proximity_props.append(p)
	if p.def.has("pulse"):
		pulse_props.append(p)
	if p.blocks_path():
		astar.set_point_solid(cell_of(pos), true)


## Host -> all (reliable, call_local): cells change kind at runtime (a grate collapses into lava,
## boulders smash the arena edge). Updates the grid, the floor tiles and the A* weights.
@rpc("authority", "call_local", "reliable")
func set_cells(cell_list: Array, kind: int) -> void:
	var entry := GameData.asset_entry(str(floor_def.tiles))
	for c in cell_list:
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			continue
		cells[c.y * size.x + c.x] = kind
		var key := "lava" if kind == DungeonGenerator.CELL_LAVA else str(SPECIAL_TILES.get(kind, "floor"))
		var t: Array = entry.get(key, entry.floor[0]) if key != "floor" else entry.floor[0]
		floor_layer.set_cell(c, 0, Vector2i(int(t[0]), int(t[1])))
		astar.set_point_solid(c, not DungeonGenerator.walkable(kind))
		astar.set_point_weight_scale(c, 25.0 if kind == DungeonGenerator.CELL_LAVA else 1.0)


## Host -> all (reliable, call_local): a grate fell in or swung back.
@rpc("authority", "call_local", "reliable")
func grate_state(grate_id: String, up: bool) -> void:
	var gr: Node = grate_by_id.get(grate_id)
	if gr:
		gr.show_state(up)


## Host -> all (unreliable, call_local): a pressure plate clicks under someone's feet.
@rpc("authority", "call_local", "unreliable")
func plate_click(plate_id: String) -> void:
	var pl: Node = plate_by_id.get(plate_id)
	if pl:
		pl.click()


## Host -> all (reliable, call_local): the plate's spikes erupt.
@rpc("authority", "call_local", "reliable")
func show_plate_spikes(plate_id: String) -> void:
	var pl: Node = plate_by_id.get(plate_id)
	if pl:
		pl.show_spikes()


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


## #55: the names of the props the layout put on this floor (the same on every peer).
func layout_prop_names() -> Array:
	var out: Array = []
	for i in layout.props.size():
		out.append("Prop_%d" % i)
	for i in layout.chests.size():
		out.append("Chest_%d" % i)
	if not layout.get("merchant", {}).is_empty():
		out.append("Merchant")
	return out


## #55, every peer: a prop destroyed before the game was saved is rubble again, without a sound.
func remove_prop_quietly(prop_name: String) -> void:
	var p: Node = props.get(prop_name)
	if p == null or not is_instance_valid(p):
		return
	props.erase(prop_name)
	proximity_props.erase(p)
	debris.append(p)
	astar.set_point_solid(cell_of(p.global_position), false)
	p.break_apart(true)


## #55, host: cells whose kind changed since the layout was built, as [x, y, kind].
func changed_cells() -> Array:
	var out: Array = []
	var base: PackedByteArray = layout.cells
	for i in mini(cells.size(), base.size()):
		if cells[i] != base[i]:
			out.append([i % size.x, i / size.x, cells[i]])
	return out


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


## The one door of the boss or merchant chamber (door kind "boss" / "merchant"), or null.
func leaf_door(kind: String) -> Node:
	for d in doors:
		if d.kind == kind:
			return d
	return null


## Map markers this peer has discovered (#28): the merchant room (by merchant, sealed or open) and
## the boss chamber, once its door or any of its cells has been seen.
## [{kind: "merchant" / "boss", npc: "archibald" / "malphas" / "", cell: Vector2i, locked: bool}]
func map_markers() -> Array:
	var out: Array = []
	var rooms: Array = layout.get("rooms", [])
	var m: Dictionary = layout.get("merchant", {})
	for e in [["merchant", int(m.get("room", -1)), str(m.get("npc", ""))], ["boss", int(layout.get("boss_room", -1)), ""]]:
		var ri: int = e[1]
		if ri < 0 or ri >= rooms.size():
			continue
		var rect: Rect2i = rooms[ri].rect
		var door := leaf_door(e[0])
		var seen := false
		if door:
			for c in door.cells:
				seen = seen or is_discovered(c)
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				if seen:
					break
				seen = is_discovered(Vector2i(x, y))
		if seen:
			out.append({"kind": e[0], "npc": e[2], "cell": rect.get_center(), "locked": door != null and door.sealed})
	return out


## #79: can a hero at `from` reach `to` without going through a wall or a closed door? Walks the
## segment in 2 px steps; a step counts only well inside a blocking cell (3 px from its edges), so
## grazing a wall corner doesn't refuse, while any wall (at least one cell thick) always does. The
## target's own cell and the last half cell before it may block (an item lying in a closed doorway,
## a lever on its wall) and are ignored; a whole cell of wall or door never is.
func reach_clear(from: Vector2, to: Vector2) -> bool:
	var end_cell := cell_of(to)
	var n := maxi(ceili(from.distance_to(to) / 2.0), 1)
	var last := Vector2i(-9999, -9999)
	for i in range(n + 1):
		var pt := from.lerp(to, float(i) / n)
		var c := cell_of(pt)
		if c == end_cell or pt.distance_to(to) < tile * 0.5:
			continue
		var local := pt - Vector2(c * tile)
		if local.x < 3.0 or local.y < 3.0 or local.x > tile - 3.0 or local.y > tile - 3.0:
			continue
		if c != last and blocks_sight(c):
			return false
		last = c
	return true


## Cells that block sight for the grid FOV (walls and closed doors).
func blocks_sight(c: Vector2i) -> bool:
	if cell_at(c) == DungeonGenerator.CELL_WALL:
		return true
	for d in doors:
		if not d.is_open and d.cells.has(c):
			return true
	return false
