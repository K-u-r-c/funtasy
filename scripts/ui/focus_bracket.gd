class_name FocusBracket
extends Control
## Animated selection bracket that glides to whatever control has keyboard/gamepad focus:
## four gold corner brackets that breathe outwards plus a faint cyan outline. Hidden while the
## mouse is the active device (hover styles do that job). Lives on a top canvas layer.

const CORNER := 5.0
const SPEED := 22.0

var _rect := Rect2()
var _alpha := 0.0
var _time := 0.0
var _last_target: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_time += delta
	var target := get_viewport().gui_get_focus_owner()
	var show := target != null and target.is_visible_in_tree() and not target.is_queued_for_deletion() \
			and InputSettings.focus_nav_active() and not target.has_meta("no_focus_bracket")
	if show:
		var xf := target.get_global_transform_with_canvas()
		var r := Rect2(xf * Vector2.ZERO, xf.basis_xform(target.size))
		if target != _last_target and _alpha < 0.05:
			_rect = r  # appear in place instead of flying in from the last spot
		_last_target = target
		var t := clampf(SPEED * delta, 0.0, 1.0)
		_rect = Rect2(_rect.position.lerp(r.position, t), _rect.size.lerp(r.size, t))
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * 8.0)
	if _alpha <= 0.0:
		_last_target = null
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var grow := 2.0 + roundf(0.5 + 0.5 * sin(_time * 5.0))
	var r := Rect2(_rect.position.round(), _rect.size.round()).grow(grow)
	var gold := Color(UITheme.GOLD, _alpha)
	var cyan := Color(UITheme.CYAN, 0.35 * _alpha)
	draw_rect(r.grow(-1), cyan, false, 1.0)
	var l := CORNER
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x - 2.0
	var y1 := r.end.y - 2.0
	for c: Vector2 in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]:
		var hx := c.x if c.x == x0 else c.x - l + 2.0
		var vy := c.y if c.y == y0 else c.y - l + 2.0
		draw_rect(Rect2(hx + 1, c.y + 1, l, 2), Color(0, 0, 0, 0.5 * _alpha))
		draw_rect(Rect2(hx, c.y, l, 2), gold)
		draw_rect(Rect2(c.x, vy, 2, l), gold)
