class_name InputGlyph
extends Control
## On-screen button prompt for an input action, drawn as pixel art: gamepad face buttons as
## colored discs (A/B/X/Y), shoulders/triggers as pills, keys as key caps, mouse buttons as a
## small mouse. Follows the last used device and the player's rebinding live.

const FACE_COLORS := {
	"A": Color("5fcf6b"), "B": Color("f25050"), "X": Color("4aa3ff"), "Y": Color("f5be42"),
}
const H := 16.0

@export var action := "":
	set(v):
		action = v
		_refresh()
## Forces a binding code ("key:F", "button:a"); empty = look up `action` for the active device.
var code := "":
	set(v):
		code = v
		_refresh()

var _code := ""
var _text := ""


func _init(p_action: String = "") -> void:
	action = p_action
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	EventBus.input_device_changed.connect(func(_g): _refresh())
	EventBus.bindings_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_code = code if not code.is_empty() else InputSettings.glyph_code(action)
	_text = InputSettings.glyph_text(_code) if not _code.is_empty() else "?"
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var kind := _code.get_slice(":", 0)
	if kind == "button" and FACE_COLORS.has(_text):
		return Vector2(H, H)
	if kind == "mouse":
		return Vector2(11, H)
	if _code.begins_with("button:dpad_"):
		return Vector2(H, H)
	var f := UITheme.font()
	var w := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	return Vector2(maxf(H, ceilf(w) + 6.0), H)


## Single letters use the full 16 px size (at 12 px some letters, like Q, read ambiguously).
func _font_size() -> int:
	return UITheme.FONT_BODY if _text.length() == 1 else UITheme.FONT_SMALL


func _draw() -> void:
	var kind := _code.get_slice(":", 0)
	var r := Rect2(Vector2.ZERO, get_minimum_size())
	r.position.y = roundf((size.y - r.size.y) / 2.0)
	if kind == "button" and FACE_COLORS.has(_text):
		_disc(r, FACE_COLORS[_text])
	elif kind == "mouse":
		_mouse(r, _code.get_slice(":", 1))
	elif _code.begins_with("button:dpad_"):
		_dpad(r, _code.trim_prefix("button:dpad_"))
	elif kind == "button" or kind == "axis":
		_pill(r)
	else:
		_keycap(r)


func _disc(r: Rect2, c: Color) -> void:
	var center := r.get_center()
	draw_circle(center + Vector2(0, 1), H / 2.0, Color(0, 0, 0, 0.6))
	draw_circle(center, H / 2.0, c.darkened(0.55))
	draw_circle(center, H / 2.0 - 1.0, c)
	draw_rect(Rect2(center.x - 2, r.position.y + 2, 4, 1), c.lightened(0.45))
	_label(r, Color("0b0e14"), Vector2(0, 0))


func _pill(r: Rect2) -> void:
	var sb := UITheme.cached_glass(Color("2a3247"), Color("8e93a6"), 1, 0)
	draw_style_box(sb, r)
	_label(r, UITheme.TEXT, Vector2.ZERO)


func _keycap(r: Rect2) -> void:
	var face := Rect2(r.position, r.size - Vector2(0, 2))
	draw_style_box(UITheme.cached_glass(Color("3a3f52"), Color("12151e"), 1, 0), Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 1)))
	draw_style_box(UITheme.cached_glass(Color("d9d4c6"), Color("12151e"), 1, 0), face)
	_label(face, Color("141824"), Vector2(0, 0))


## D-pad cross with the pressed arm lit.
func _dpad(r: Rect2, which: String) -> void:
	var o := r.position + Vector2(1, 1)
	var dark := Color("12151e")
	draw_rect(Rect2(o + Vector2(4, 0), Vector2(6, 14)), dark)
	draw_rect(Rect2(o + Vector2(0, 4), Vector2(14, 6)), dark)
	var face := Color("8e93a6")
	draw_rect(Rect2(o + Vector2(5, 1), Vector2(4, 12)), face)
	draw_rect(Rect2(o + Vector2(1, 5), Vector2(12, 4)), face)
	var arm := {"up": Rect2(5, 1, 4, 5), "down": Rect2(5, 8, 4, 5), "left": Rect2(1, 5, 5, 4), "right": Rect2(8, 5, 5, 4)}
	if arm.has(which):
		var a: Rect2 = arm[which]
		draw_rect(Rect2(o + a.position, a.size), UITheme.GOLD)


func _mouse(r: Rect2, which: String) -> void:
	var body := Rect2(r.position + Vector2(0, 2), Vector2(11, 13))
	draw_style_box(UITheme.cached_glass(Color("d9d4c6"), Color("12151e"), 1, 0), body)
	draw_rect(Rect2(body.position.x + 5, body.position.y + 1, 1, 5), Color("12151e"))
	var hl := Color(UITheme.GOLD)
	match which:
		"left":
			draw_rect(Rect2(body.position.x + 1, body.position.y + 1, 4, 5), hl)
		"right":
			draw_rect(Rect2(body.position.x + 6, body.position.y + 1, 4, 5), hl)
		_:
			draw_rect(Rect2(body.position.x + 4, body.position.y + 2, 3, 3), hl)


func _label(r: Rect2, c: Color, nudge: Vector2) -> void:
	var f := UITheme.font()
	var fs := _font_size()
	var w := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Capitals of the pixel font are ~0.7 em tall: put the baseline so they sit centered.
	var base := Vector2(roundf(r.get_center().x - w / 2.0), roundf(r.get_center().y + fs * 0.35)) + nudge
	draw_string(f, base, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
