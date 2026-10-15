class_name AnimButton
extends Button
## Menu button: glass style from UITheme, a gold marker that slides in on hover/focus, a 1 px
## press offset (theme "pressed" style) with a click sound, and a fade-in intro. It never
## scales, so the pixel font stays crisp.

var _hot := 0.0  ## 0..1 marker animation
var _tween: Tween


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(240, 30)
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(_set_hot.bind(true))
	focus_entered.connect(_on_focus)
	mouse_exited.connect(func(): _set_hot(has_focus()))
	focus_exited.connect(func(): _set_hot(is_hovered()))
	button_down.connect(func(): AudioManager.play_sfx("ui_press", 0.05))
	pressed.connect(func(): AudioManager.play_sfx("ui_accept", 0.03))


func play_intro(delay: float) -> void:
	modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_focus() -> void:
	AudioManager.play_sfx("ui_move", 0.0)
	_set_hot(true)


func _set_hot(hot: bool) -> void:
	if disabled:
		hot = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float): _hot = v; queue_redraw(), _hot, 1.0 if hot else 0.0, 0.14) \
			.set_trans(Tween.TRANS_BACK if hot else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if _hot <= 0.01:
		return
	# Marker: a 2 px gold bar that grows from the middle of the left edge, and a faint cyan
	# underline that sweeps in from the left.
	var h := roundf((size.y - 8.0) * clampf(_hot, 0.0, 1.2))
	var y := roundf((size.y - h) / 2.0)
	var off := 1.0 if button_pressed else 0.0
	draw_rect(Rect2(3, y + off, 2, h), UITheme.GOLD)
	draw_rect(Rect2(6, y + off + 1, 1, maxf(h - 2.0, 0.0)), Color(UITheme.GOLD, 0.35))
	var w := roundf((size.x - 8.0) * clampf(_hot, 0.0, 1.0))
	draw_rect(Rect2(4, size.y - 3, w, 1), Color(UITheme.CYAN, 0.45))
