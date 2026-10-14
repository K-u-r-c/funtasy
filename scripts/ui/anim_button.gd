class_name AnimButton
extends Button
## Menu button with hover/focus grow, press squash, a slide-in intro and UI sounds.
## Styling comes from the global UITheme.

var _tween: Tween


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(240, 34)
	focus_mode = Control.FOCUS_ALL
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(_set_hot.bind(true))
	focus_entered.connect(_on_focus)
	mouse_exited.connect(_set_hot.bind(false))
	focus_exited.connect(_set_hot.bind(false))
	button_down.connect(_squash)
	pressed.connect(func(): AudioManager.play_sfx("ui_accept", 0.0))


func play_intro(delay: float) -> void:
	modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay)
	t.tween_property(self, "scale", Vector2.ONE, 0.3).from(Vector2(0.8, 0.8)) \
		.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_focus() -> void:
	AudioManager.play_sfx("ui_move", 0.0)
	_set_hot(true)


func _set_hot(hot: bool) -> void:
	if disabled:
		return
	_retween()
	_tween.tween_property(self, "scale", Vector2.ONE * (1.05 if hot else 1.0), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _squash() -> void:
	_retween()
	_tween.tween_property(self, "scale", Vector2(0.95, 0.9), 0.06)
	_tween.tween_property(self, "scale", Vector2.ONE * 1.05, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _retween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
