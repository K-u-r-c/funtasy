extends Control
## Minimap around the camera focus: discovered cells only, no enemies (fog-of-war rule).
## Also used scaled-up by the full map overlay.

var cell_px := 2.0
var full_map := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var game := get_tree().get_first_node_in_group("game")
	if game == null or game.dungeon.size == Vector2i.ZERO:
		return
	var d: Dungeon = game.dungeon
	var focus_cell: Vector2 = Vector2(d.cell_of(game.camera.global_position))
	var px := cell_px
	var origin := size / 2.0 - focus_cell * px
	var first := Vector2i.ZERO
	var last := d.size
	if full_map:
		px = minf(size.x / d.size.x, size.y / d.size.y)
		origin = (size - Vector2(d.size) * px) / 2.0
	else:
		first = Vector2i(focus_cell - size / (2.0 * px)).clamp(Vector2i.ZERO, d.size)
		last = Vector2i(focus_cell + size / (2.0 * px) + Vector2.ONE).clamp(Vector2i.ZERO, d.size)
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			var c := Vector2i(x, y)
			if not d.is_discovered(c):
				continue
			var v := d.cell_at(c)
			var col := Color(0.42, 0.38, 0.36) if v == DungeonGenerator.CELL_FLOOR else (Color(0.85, 0.3, 0.05) if v == DungeonGenerator.CELL_LAVA else Color(0.16, 0.14, 0.16))
			draw_rect(Rect2(origin + Vector2(c) * px, Vector2(px, px)), col)
	for door in d.doors:
		var dc: Vector2i = door.cells[0]
		if d.is_discovered(dc):
			draw_rect(Rect2(origin + Vector2(dc) * px, Vector2(px, px) * 1.5), Color(0.75, 0.5, 0.25) if not door.is_open else Color(0.4, 0.3, 0.2))
	if game.portal:
		draw_circle(origin + Vector2(d.cell_of(game.portal.global_position)) * px, px * 2.5, Color(0.7, 0.4, 1.0))
	for p in game.players_root.get_children():
		var pc := Vector2(p.global_position) / d.tile
		var col2 := Color.from_string(str(p.class_def.get("color", "#ffffff")), Color.WHITE)
		draw_circle(origin + pc * px, maxf(2.0, px * 1.2), col2 if p.life_state == Player.Life.ALIVE else Color(0.5, 0.5, 0.5))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.32, 0.25), false, 1.0)
