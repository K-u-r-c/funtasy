class_name Dungeon
extends TileMapLayer
## Procedural dungeon: random non-overlapping rooms joined by L-shaped corridors.
## Generation only uses a seeded RandomNumberGenerator, so every peer builds the identical
## map from the same seed and no tiles ever need to be synchronized.

const TILE := 16
const GRID_W := 64
const GRID_H := 44
const MIN_ROOMS := 6
const FLOOR_A := Vector2i(0, 0)
const FLOOR_B := Vector2i(1, 0)
const WALL := Vector2i(2, 0)

var rooms: Array[Rect2i] = []
var start_room: Rect2i
var exit_room: Rect2i

var _floor: Dictionary = {}


func _ready() -> void:
	tile_set = _make_tileset()


func world_size() -> Vector2:
	return Vector2(GRID_W, GRID_H) * TILE


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


func room_center(room: Rect2i) -> Vector2:
	return cell_center(room.get_center())


func random_point_in(room: Rect2i, rng: RandomNumberGenerator) -> Vector2:
	var cell := Vector2i(
		rng.randi_range(room.position.x + 1, room.end.x - 2),
		rng.randi_range(room.position.y + 1, room.end.y - 2)
	)
	return cell_center(cell)


func generate(map_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	_floor.clear()
	rooms.clear()

	var attempts := 0
	while (rooms.size() < MIN_ROOMS or attempts < 40) and attempts < 400:
		attempts += 1
		var w := rng.randi_range(6, 11)
		var h := rng.randi_range(5, 8)
		var room := Rect2i(
			rng.randi_range(2, GRID_W - w - 3), rng.randi_range(2, GRID_H - h - 3), w, h
		)
		var overlaps := false
		for other in rooms:
			if other.grow(2).intersects(room):
				overlaps = true
				break
		if overlaps:
			continue
		_carve_room(room)
		if not rooms.is_empty():
			_carve_corridor(rooms.back().get_center(), room.get_center(), rng)
		rooms.append(room)

	start_room = rooms[0]
	exit_room = rooms[0]
	var best := -1.0
	for r in rooms:
		var d := Vector2(r.get_center() - start_room.get_center()).length()
		if d > best:
			best = d
			exit_room = r
	_paint()


func _carve_room(room: Rect2i) -> void:
	for x in range(room.position.x, room.end.x):
		for y in range(room.position.y, room.end.y):
			_floor[Vector2i(x, y)] = true


func _carve_corridor(from: Vector2i, to: Vector2i, rng: RandomNumberGenerator) -> void:
	var horizontal_first := rng.randf() < 0.5
	var corner := Vector2i(to.x, from.y) if horizontal_first else Vector2i(from.x, to.y)
	_carve_line(from, corner)
	_carve_line(corner, to)


## Corridors are 2 tiles wide so players fit through comfortably.
func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		_floor[p] = true
		_floor[p + Vector2i(1, 1)] = true
		_floor[p + Vector2i(1, 0)] = true
		_floor[p + Vector2i(0, 1)] = true
		if p == b:
			break
		p += step


func _paint() -> void:
	clear()
	for x in GRID_W:
		for y in GRID_H:
			var c := Vector2i(x, y)
			if _floor.has(c):
				set_cell(c, 0, FLOOR_A if (x + y) % 2 == 0 else FLOOR_B)
			else:
				set_cell(c, 0, WALL)


func _make_tileset() -> TileSet:
	var img := Image.create(TILE * 3, TILE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE, TILE), Color(0.22, 0.2, 0.26))
	img.fill_rect(Rect2i(TILE, 0, TILE, TILE), Color(0.25, 0.23, 0.29))
	img.fill_rect(Rect2i(TILE * 2, 0, TILE, TILE), Color(0.07, 0.06, 0.09))
	img.fill_rect(Rect2i(TILE * 2, 0, TILE, 2), Color(0.38, 0.33, 0.44))  # lit wall top edge
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	for c in [FLOOR_A, FLOOR_B, WALL]:
		src.create_tile(c)
	var half := TILE / 2.0
	var data := src.get_tile_data(WALL, 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	]))
	return ts
