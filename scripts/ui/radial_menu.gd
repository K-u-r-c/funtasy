extends Control
## Radial quick-item picker shown while Q/E is held. Point with the mouse, the right stick (or
## the left stick); releasing the key assigns the highlighted consumable to that slot.

var player: Player
var slot := "q"
var _options: Array = []  ## consumable ids
var _selected := -1
var _sel_anim := 0.0  ## eased angle of the highlight wedge
var _pop := 0.0
var _icons: Dictionary = {}  ## consumable id -> Texture2D (loaded before drawing)
const RADIUS := 84.0
const INNER := 34.0
const OUTER := 116.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options = player.inv.consumable_types()
	_options.append("")  # "clear slot"
	_selected = _options.find(player.inv.quick.get(slot, ""))
	for id in _options:
		if not str(id).is_empty():
			_icons[id] = GameData.texture(str(GameData.consumables[id].icon))
	_sel_anim = float(maxi(_selected, 0))
	var tw := create_tween()
	tw.tween_method(func(v: float): _pop = v, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("ui_open", 0.03)


func selected_id() -> String:
	if _selected < 0 or _selected >= _options.size():
		return player.inv.quick.get(slot, "")
	var id: String = _options[_selected]
	return id if not id.is_empty() else "__clear__"


func _process(delta: float) -> void:
	var dir := InputSettings.stick_aim()
	if dir == Vector2.ZERO:
		var m := InputSettings.move_vector()
		if InputSettings.using_gamepad and m.length() > 0.5:
			dir = m
	if dir == Vector2.ZERO and not InputSettings.using_gamepad:
		var d := get_local_mouse_position() - size / 2.0
		if d.length() > 20.0:
			dir = d
	if dir != Vector2.ZERO and not _options.is_empty():
		var a := fposmod(dir.angle() + PI / 2.0 + PI / _options.size(), TAU)
		var next := int(a / TAU * _options.size()) % _options.size()
		if next != _selected:
			_selected = next
			AudioManager.play_sfx("ui_move", 0.0)
	if _selected >= 0:
		var n := float(_options.size())
		var diff := fposmod(float(_selected) - _sel_anim + n / 2.0, n) - n / 2.0
		_sel_anim = fposmod(_sel_anim + diff * clampf(delta * 18.0, 0.0, 1.0), n)
	queue_redraw()


func _draw() -> void:
	var c := (size / 2.0).round()
	var k := clampf(_pop, 0.0, 1.2)
	var n := _options.size()
	var font := UITheme.font()
	draw_circle(c, (OUTER + 6.0) * k, Color(0.02, 0.03, 0.05, 0.55))
	_ring(c, OUTER * k, INNER * k, UITheme.GLASS)
	draw_circle(c, INNER * k, UITheme.GLASS_DEEP)
	draw_arc(c, OUTER * k, 0, TAU, 64, UITheme.GOLD_DIM, 1.0)
	draw_arc(c, INNER * k, 0, TAU, 40, UITheme.EDGE, 1.0)
	if n == 0 or k < 0.3:
		return
	var seg := TAU / n
	# Highlight wedge (eased) + pointer
	if _selected >= 0:
		var a0 := -PI / 2.0 + seg * _sel_anim - seg / 2.0
		_wedge(c, INNER * k + 1.0, OUTER * k - 1.0, a0, a0 + seg, Color(UITheme.CYAN, 0.13))
		draw_arc(c, OUTER * k - 2.0, a0 + 0.02, a0 + seg - 0.02, 16, UITheme.CYAN, 2.0)
		var mid := a0 + seg / 2.0
		var tip := c + Vector2.from_angle(mid) * (OUTER * k + 7.0)
		var side := Vector2.from_angle(mid + PI / 2.0) * 4.0
		var back := c + Vector2.from_angle(mid) * (OUTER * k + 1.0)
		draw_colored_polygon(PackedVector2Array([tip.round(), (back + side).round(), (back - side).round()]), UITheme.CYAN)
	if n > 1:
		for i in n:
			var a := -PI / 2.0 + seg * i - seg / 2.0
			draw_line((c + Vector2.from_angle(a) * INNER * k).round(), (c + Vector2.from_angle(a) * OUTER * k).round(), Color(UITheme.EDGE, 0.8), 1.0)
	for i in n:
		var a := -PI / 2.0 + seg * i
		var p := (c + Vector2.from_angle(a) * RADIUS * k).round()
		var sel := i == _selected
		var box := Rect2(p - Vector2(20, 20), Vector2(40, 40))
		draw_style_box(UITheme.cached_glass(Color("16203af2") if sel else Color("070a10f2"), UITheme.GOLD if sel else UITheme.EDGE, 1, 0, UITheme.CYAN if sel else Color(0, 0, 0, 0)), box)
		var id: String = _options[i]
		if id.is_empty():
			_text_center(font, p + Vector2(0, 4), "none", UITheme.FONT_SMALL, UITheme.TEXT_DIM)
			continue
		var def: Dictionary = GameData.consumables[id]
		var tex: Texture2D = _icons.get(id)
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(16, 16) + Vector2(0, -1 if sel else 0), Vector2(32, 32)), false)
		var cnt := "%d" % player.inv.count_of(id)
		var cw := font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
		var cp := box.end - Vector2(cw + 3, 3)
		draw_string_outline(font, cp, cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
		draw_string(font, cp, cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, Color.WHITE)
	# Center: slot + selection
	_text_center(font, c + Vector2(0, 0), "Slot", UITheme.FONT_SMALL, UITheme.TEXT_DIM)
	_text_center(font, c + Vector2(0, 14), slot.to_upper(), UITheme.FONT_BODY, UITheme.CYAN)
	var label := "Clear"
	if _selected >= 0 and _selected < n and not str(_options[_selected]).is_empty():
		label = str(GameData.consumables[_options[_selected]].name)
	_text_center(font, c + Vector2(0, OUTER * k + 26.0), label, UITheme.FONT_BODY, UITheme.GOLD)


func _ring(c: Vector2, outer: float, inner: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(TAU * i / steps) * outer)
	for i in range(steps, -1, -1):
		pts.append(c + Vector2.from_angle(TAU * i / steps) * inner)
	draw_colored_polygon(pts, col)


func _wedge(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * r1)
	for i in range(steps, -1, -1):
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * r0)
	draw_colored_polygon(pts, col)


func _text_center(font: Font, pos: Vector2, t: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(roundf(pos.x - w / 2.0), roundf(pos.y))
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
