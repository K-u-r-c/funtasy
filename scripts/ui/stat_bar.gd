class_name StatBar
extends Control
## Pixel resource bar: bevelled fill, a damage trail that catches up after a short delay
## (amber), a heal lead (pale), a hatched shield overlay, a white flash on damage and centered
## text. Call `set_values()` every frame; tweens only start when the value actually changes.

var fill_color := Color("c23a3a")
var trail_color := Color("f5be42")
var shield_color := Color("6ee3f0")
var show_text := true
var text := ""
var font_size := UITheme.FONT_SMALL
var ticks := 0  ## draw a tick every 1/ticks of the bar (0 = none)

var flash_on_damage := false  ## white flash on big drops (HP / boss bars)
## Changes smaller than this (fraction of the bar) just move the fill: regen, decay and
## per-frame drift never restart the trail or the flash.
var min_step := 0.01

var _value := -1.0  ## shown fill 0..1
var _goal := -1.0  ## latest value set
var _trail := 0.0  ## damage trail (amber) or heal lead (pale), always >= _value
var _healing := false
var _shield := 0.0
var _flash := 0.0
var _trail_tween: Tween
var _fill_tween: Tween
var _flash_tween: Tween


func _init(color: Color = Color("c23a3a"), min_size: Vector2 = Vector2(150, 12)) -> void:
	fill_color = color
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Wraps the bar in the iron gauge frame with skull caps (PixelLab ornament, #29).
func set_ornate() -> void:
	var tex := UITheme.icon_tex("orn_gauge")
	if tex == null:
		return
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = 22
	np.patch_margin_right = 22
	np.patch_margin_top = 8
	np.patch_margin_bottom = 8
	np.draw_center = false
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.offset_left = -12
	np.offset_right = 12
	np.offset_top = -5
	np.offset_bottom = 5
	add_child(np)


## `frac` 0..1, `shield_frac` 0..1 (absorb relative to max), `label` drawn centered.
func set_values(frac: float, shield_frac: float = 0.0, label: String = "") -> void:
	frac = clampf(frac, 0.0, 1.0)
	var changed := label != text or not is_equal_approx(shield_frac, _shield)
	text = label
	_shield = clampf(shield_frac, 0.0, 1.0)
	if _value < 0.0:
		_value = frac
		_trail = frac
		_goal = frac
		changed = true
	elif not is_equal_approx(frac, _goal):
		changed = true
		if absf(frac - _goal) < min_step:
			_goal = frac
			if not _busy(_fill_tween):
				_value = frac
			if not _busy(_trail_tween):
				_trail = maxf(_value, frac) if _healing and _busy(_fill_tween) else _value
		elif frac < _goal:
			_on_drop(frac)
		else:
			_on_rise(frac)
	if changed or _shield > 0.0:
		queue_redraw()


func _busy(t: Tween) -> bool:
	return t != null and t.is_valid() and t.is_running()


func _on_drop(frac: float) -> void:
	_goal = frac
	_healing = false
	if _busy(_fill_tween):
		_fill_tween.kill()
	_trail = maxf(_trail, _value)
	_value = frac
	if _busy(_trail_tween):
		_trail_tween.kill()
	_trail_tween = create_tween()
	_trail_tween.tween_interval(float(GameData.bal("ui.bar_trail_delay", 0.3)))
	_trail_tween.tween_method(func(v: float): _trail = v; queue_redraw(), _trail, frac,
			float(GameData.bal("ui.bar_trail_time", 0.45))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Small drops that happened meanwhile are absorbed: the trail ends on the current value.
	_trail_tween.tween_callback(func(): _trail = _value; queue_redraw())
	if flash_on_damage:
		if _busy(_flash_tween):
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(func(v: float): _flash = v; queue_redraw(), 1.0, 0.0, 0.18)


func _on_rise(frac: float) -> void:
	_goal = frac
	# Heals: the pale lead jumps ahead, the fill glides up to it.
	_healing = true
	_trail = frac
	if _busy(_trail_tween):
		_trail_tween.kill()
	if _busy(_fill_tween):
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_method(func(v: float): _value = v; queue_redraw(), _value, frac, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fill_tween.tween_callback(func(): _value = _goal; _trail = _goal; queue_redraw())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size.round())
	draw_style_box(UITheme.cached_glass(Color("05070bf0"), UITheme.EDGE, 1, 0), r)
	var inner := r.grow(-1)
	var w := inner.size.x
	var v := maxf(_value, 0.0)
	if _trail > v:
		var lead := fill_color.lightened(0.55) if _healing else trail_color
		draw_rect(Rect2(inner.position, Vector2(roundf(w * _trail), inner.size.y)), lead)
	var fw := roundf(w * v)
	if fw > 0.0:
		var fr := Rect2(inner.position, Vector2(fw, inner.size.y))
		draw_rect(fr, fill_color)
		draw_rect(Rect2(fr.position, Vector2(fw, 1)), fill_color.lightened(0.35))
		if inner.size.y > 4.0:
			draw_rect(Rect2(fr.position + Vector2(0, inner.size.y - 1), Vector2(fw, 1)), fill_color.darkened(0.4))
		if _flash > 0.0:
			draw_rect(fr, Color(1, 1, 1, 0.6 * _flash))
	if ticks > 1:
		for i in range(1, ticks):
			var x := roundf(inner.position.x + w * i / ticks)
			draw_rect(Rect2(x, inner.position.y + 1, 1, inner.size.y - 2), Color(0, 0, 0, 0.35))
	if _shield > 0.0:
		var sw := roundf(w * _shield)
		var sx := minf(inner.position.x + fw, inner.end.x - sw)
		var sr := Rect2(sx, inner.position.y, sw, inner.size.y)
		draw_rect(sr, Color(shield_color, 0.35))
		var scroll := int(Time.get_ticks_msec() / 150) % 3
		for x in range(int(sr.position.x) + scroll, int(sr.end.x), 3):
			draw_rect(Rect2(x, sr.position.y + 1, 1, sr.size.y - 1), Color(shield_color, 0.7))
		draw_rect(Rect2(sr.position, Vector2(sw, 1)), Color(1, 1, 1, 0.6))
	if show_text and not text.is_empty():
		var f := UITheme.font()
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var base := Vector2(roundf((r.size.x - tw) / 2.0), roundf(r.size.y / 2.0 + f.get_ascent(font_size) / 2.0 - 2.0))
		draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0, 0, 0, 0.9))
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.TEXT)
