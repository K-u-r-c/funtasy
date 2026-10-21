class_name Badge
extends Control
## The shared badge of the floor systems (#70-#74): a small dark glass tile with a coloured rim,
## the PixelLab icon inside and a slow glow in the rim colour. It pops in when shown and, on hover
## (or keyboard / gamepad focus where it is focusable), shows its card: icon, name and lines of
## what it does. The same colours mean the same thing everywhere (UITheme.BADGE_*):
## a biome / invasion ember, a floor modifier its own colour, warnings red.

var icon_key := ""
var title := ""
var lines: Array = []  ## [[text, colour], ...] shown under the title on the card
var rim := Color("e8b74a")
var px := 26
var _t := 0.0
var _pop := 0.0


func _init(icon: String = "", name_: String = "", card_lines: Array = [], colour: Color = Color("e8b74a"), size_px: int = 26) -> void:
	icon_key = icon
	title = name_
	lines = card_lines
	rim = colour
	px = size_px
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# A non-empty tooltip text turns on the custom card below.
	tooltip_text = title


func _ready() -> void:
	pop()


## The pop-in: a quick swell with a flash of the rim.
func pop() -> void:
	_pop = 1.0
	pivot_offset = Vector2(px, px) / 2.0
	scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(_pop - delta * 1.5, 0.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(px, px))
	var glow := 0.22 + 0.12 * sin(_t * 2.4) + 0.5 * _pop
	draw_rect(r.grow(2), Color(rim, glow * 0.45))
	draw_style_box(UITheme.cached_glass(Color("070a12f0"), rim.darkened(0.25), 1, 0), r)
	var tex := UITheme.icon_tex(icon_key)
	if tex:
		draw_texture_rect(tex, r.grow(-2), false)
	if has_focus():
		draw_rect(r.grow(3), UITheme.GOLD, false, 1.0)


func _make_custom_tooltip(_for_text: String) -> Object:
	return card(icon_key, title, lines, rim)


## The badge card (also used by the floor banner and the choice cards' headers).
static func card(icon: String, name_: String, card_lines: Array, colour: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.glass(Color("080b12f5"), colour.darkened(0.2), 1, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(UITheme.icon(icon, 32))
	var t := UITheme.label(name_, colour.lightened(0.25), UITheme.FONT_BODY)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	for ln in card_lines:
		var l := UITheme.label(str(ln[0]), ln[1] if ln.size() > 1 else UITheme.TEXT, UITheme.FONT_SMALL)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(240, 0)
		v.add_child(l)
	return p
