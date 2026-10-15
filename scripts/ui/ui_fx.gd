class_name UIFx
extends RefCounted
## Shared UI motion: spring pop-ins for windows, small flashes. Only short, whole-window
## scale tweens are used; buttons never scale (that shimmers on nearest-filtered pixel art).


## Spring pop-in (TRANS_BACK) + fade. `window` must already be in the tree.
static func pop_in(window: Control, sound := true) -> void:
	var dur := float(GameData.bal("ui.window_pop_time", 0.25))
	window.modulate.a = 0.0
	window.scale = Vector2(0.9, 0.9)
	var set_pivot := func(): window.pivot_offset = (window.size / 2.0).round()
	set_pivot.call()
	window.resized.connect(set_pivot)
	var tw := window.create_tween().set_parallel(true)
	tw.tween_property(window, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(window, "modulate:a", 1.0, dur * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if sound:
		AudioManager.play_sfx("ui_open", 0.03)


## Brief brightness flash (e.g. a slot that just changed).
static func flash(c: CanvasItem, strength := 0.8) -> void:
	var tw := c.create_tween()
	tw.tween_property(c, "self_modulate", Color(1 + strength, 1 + strength, 1 + strength), 0.05)
	tw.tween_property(c, "self_modulate", Color.WHITE, 0.18)


## Horizontal shake for refused actions (e.g. can't equip).
static func deny(c: Control) -> void:
	AudioManager.play_sfx("ui_error", 0.0)
	var tw := c.create_tween()
	for i in 4:
		tw.tween_property(c, "position:x", c.position.x + (2.0 if i % 2 == 0 else -2.0), 0.03)
	tw.tween_property(c, "position:x", c.position.x, 0.03)
