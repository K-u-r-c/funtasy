extends Control
## Radial quick-item picker shown while Q/E is held. Point with the mouse, the right stick (or
## the left stick); releasing the key assigns the highlighted consumable to that slot.

var player: Player
var slot := "q"
var _options: Array = []  ## consumable ids
var _selected := -1
const RADIUS := 90.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options = player.inv.consumable_types()
	_options.append("")  # "clear slot"
	_selected = _options.find(player.inv.quick.get(slot, ""))


func selected_id() -> String:
	if _selected < 0 or _selected >= _options.size():
		return player.inv.quick.get(slot, "")
	var id: String = _options[_selected]
	return id if not id.is_empty() else "__clear__"


func _process(_delta: float) -> void:
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
		_selected = int(a / TAU * _options.size()) % _options.size()
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, RADIUS + 34.0, Color(0, 0, 0, 0.55))
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-60, 6), "Quick slot %s" % slot.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, UITheme.ACCENT)
	for i in _options.size():
		var a := -PI / 2.0 + TAU * i / _options.size()
		var p := c + Vector2.from_angle(a) * RADIUS
		var sel := i == _selected
		draw_circle(p, 26.0 if sel else 22.0, Color(0.35, 0.25, 0.15, 0.95) if sel else Color(0.12, 0.1, 0.12, 0.95))
		if sel:
			draw_arc(p, 26.0, 0, TAU, 24, UITheme.ACCENT, 2.0)
		var id: String = _options[i]
		if id.is_empty():
			draw_string(font, p + Vector2(-20, 5), "none", HORIZONTAL_ALIGNMENT_CENTER, 40, 11, UITheme.TEXT_DIM)
			continue
		var def: Dictionary = GameData.consumables[id]
		var tex := GameData.texture(str(def.icon))
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(16, 16), Vector2(32, 32)), false)
		draw_string(font, p + Vector2(-20, 24), "x%d" % player.inv.count_of(id), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color.WHITE)
		if sel:
			draw_string(font, c + Vector2(-80, RADIUS + 52), str(def.name), HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color.WHITE)
