extends Control
## Minimap around the camera focus: discovered cells only, no enemies (fog-of-war rule).
## Also used scaled-up by the full map overlay.

const FLOOR := Color("3a4560")
const WALL := Color("151a27")
const LAVA := Color("d9561a")
const WATER := Color("2f5a4a")
const CANAL := Color("1a3a14")

var cell_px := 2.0
var full_map := false
var _t := 0.0
var _icons: Dictionary = {}  ## marker icons, loaded in _ready (a texture first loaded inside _draw draws white)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for key in ["ui.map_archibald", "ui.map_malphas", "ui.map_boss", "ui.map_lock"]:
		_icons[key] = GameData.texture(key)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size.round())
	draw_style_box(UITheme.cached_glass(Color("05070bd8"), UITheme.EDGE, 1, 0), r)
	var game := get_tree().get_first_node_in_group("game")
	if game == null or game.dungeon.size == Vector2i.ZERO:
		return
	var d: Dungeon = game.dungeon
	var focus_cell: Vector2 = Vector2(d.cell_of(game.camera.global_position))
	var px := cell_px
	var origin := (size / 2.0 - focus_cell * px).round()
	var first := Vector2i.ZERO
	var last := d.size
	if full_map:
		px = maxf(1.0, floorf(minf((size.x - 8.0) / d.size.x, (size.y - 8.0) / d.size.y)))
		origin = ((size - Vector2(d.size) * px) / 2.0).round()
	else:
		first = Vector2i(focus_cell - size / (2.0 * px)).clamp(Vector2i.ZERO, d.size)
		last = Vector2i(focus_cell + size / (2.0 * px) + Vector2.ONE).clamp(Vector2i.ZERO, d.size)
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			var c := Vector2i(x, y)
			if not d.is_discovered(c):
				continue
			var v := d.cell_at(c)
			var col := FLOOR if v == DungeonGenerator.CELL_FLOOR else (LAVA if v == DungeonGenerator.CELL_LAVA else WALL)
			if v == DungeonGenerator.CELL_WATER or v == DungeonGenerator.CELL_SLUDGE or v == DungeonGenerator.CELL_CANAL:
				col = WATER if v != DungeonGenerator.CELL_CANAL else CANAL
			elif v == DungeonGenerator.CELL_BRIDGE:
				col = FLOOR
			draw_rect(Rect2(origin + Vector2(c) * px, Vector2(px, px)), col)
	for door in d.doors:
		var dc: Vector2i = door.cells[0]
		if d.is_discovered(dc):
			draw_rect(Rect2(origin + Vector2(dc) * px, Vector2(px, px) * 1.5), Color(0.75, 0.5, 0.25) if not door.is_open else Color(0.4, 0.3, 0.2))
	# Discovered merchant and boss chambers (#28): the merchant's sign, a lock while sealed.
	var icon_px := 16.0 if full_map else 12.0
	for mk in d.map_markers():
		var tex := _icon("ui.map_boss" if mk.kind == "boss" else "ui.map_" + str(mk.npc))
		if tex == null:
			continue
		var mc := (origin + (Vector2(mk.cell) + Vector2(0.5, 0.5)) * px).round()
		var ir := Rect2(mc - Vector2(icon_px, icon_px) / 2.0, Vector2(icon_px, icon_px)).abs()
		if mk.kind == "boss":
			draw_circle(mc, icon_px * 0.6 + sin(_t * 3.0), Color(0.8, 0.1, 0.05, 0.35))
		draw_texture_rect(tex, ir, false)
		if mk.locked:
			draw_texture_rect(_icon("ui.map_lock"), Rect2(ir.end - Vector2(7, 7), Vector2(8, 8)), false)
	if game.portal:
		var pp := origin + Vector2(d.cell_of(game.portal.global_position)) * px
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(pp, px * 2.5 + pulse * 1.5, Color(0.7, 0.4, 1.0, 0.35))
		draw_circle(pp, px * 2.0, Color(0.7, 0.4, 1.0))
	# #71 / #72 pings: a threat about to appear (a hunter's rift...), pulsing until it passes.
	for ping in game.map_pings:
		if float(ping.until) < float(game.floor_time):
			continue
		var gp := (origin + Vector2(ping.pos) / d.tile * px).round()
		var k := 0.5 + 0.5 * sin(_t * 8.0)
		draw_circle(gp, px * 3.0 + 3.0 * k, Color(ping.color, 0.3))
		draw_arc(gp, px * 3.0 + 6.0 * k, 0.0, TAU, 20, Color(ping.color, 0.9), 1.5)
		draw_circle(gp, maxf(px, 2.0), ping.color)
	for p in game.players_root.get_children():
		var pc := (origin + Vector2(p.global_position) / d.tile * px).round()
		var col2 := Color.from_string(str(p.class_def.get("color", "#ffffff")), Color.WHITE)
		if p.life_state != Player.Life.ALIVE:
			col2 = Color(0.5, 0.5, 0.5)
		if p.is_local():
			# Facing arrow for the local player.
			var f: Vector2 = p.facing if p.facing != Vector2.ZERO else Vector2.DOWN
			var s := maxf(4.0, px * 2.0)
			var tip := pc + f.normalized() * s
			var side := f.normalized().orthogonal() * s * 0.6
			var back := pc - f.normalized() * s * 0.5
			draw_colored_polygon(PackedVector2Array([tip.round(), (back + side).round(), (back - side).round()]), Color.BLACK)
			draw_colored_polygon(PackedVector2Array([(tip - f.normalized()).round(), (back + side * 0.6).round(), (back - side * 0.6).round()]), UITheme.CYAN)
		else:
			draw_rect(Rect2(pc - Vector2(2, 2), Vector2(4, 4)), Color.BLACK)
			draw_rect(Rect2(pc - Vector2(1, 1), Vector2(3, 3)), col2)
	if not full_map:
		# Compass mark
		var f2 := UITheme.font()
		draw_string_outline(f2, Vector2(roundf(size.x / 2.0) - 3, 11), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
		draw_string(f2, Vector2(roundf(size.x / 2.0) - 3, 11), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, UITheme.GOLD)
	draw_style_box(UITheme.cached_glass(Color(0, 0, 0, 0), UITheme.EDGE, 1, 0, UITheme.GOLD_DIM), r)


func _icon(key: String) -> Texture2D:
	return _icons.get(key)
