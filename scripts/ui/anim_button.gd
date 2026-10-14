class_name AnimButton
extends Button
## Menu button with hover/focus grow, press squash and a slide-in intro.

const NORMAL := Color(0.16, 0.18, 0.28)
const HOVER := Color(0.28, 0.34, 0.58)
const PRESSED := Color(0.45, 0.55, 0.85)
const DISABLED := Color(0.12, 0.12, 0.16)

var _tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(200, 28)
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 14)
	add_theme_stylebox_override("normal", _box(NORMAL))
	add_theme_stylebox_override("hover", _box(HOVER))
	add_theme_stylebox_override("focus", _box(HOVER, Color(1, 0.85, 0.3)))
	add_theme_stylebox_override("pressed", _box(PRESSED))
	add_theme_stylebox_override("disabled", _box(DISABLED))
	add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.5))
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(_set_hot.bind(true))
	focus_entered.connect(_set_hot.bind(true))
	mouse_exited.connect(_set_hot.bind(false))
	focus_exited.connect(_set_hot.bind(false))
	button_down.connect(_squash)


func play_intro(delay: float) -> void:
	modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay)
	t.tween_property(self, "scale", Vector2.ONE, 0.3).from(Vector2(0.7, 0.7)) \
		.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_hot(hot: bool) -> void:
	if disabled:
		return
	_retween()
	_tween.tween_property(self, "scale", Vector2.ONE * (1.08 if hot else 1.0), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _squash() -> void:
	_retween()
	_tween.tween_property(self, "scale", Vector2(0.94, 0.9), 0.06)
	_tween.tween_property(self, "scale", Vector2.ONE * 1.08, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _retween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()


func _box(color: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if border.a > 0.0:
		sb.set_border_width_all(2)
		sb.border_color = border
	return sb
