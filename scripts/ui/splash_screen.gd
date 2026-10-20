class_name SplashScreen
extends CanvasLayer
## Boot splash shown once per launch over the title screen: black, the FUNTASY logo fades in,
## a light sweep with a glint runs across it, then everything fades out to reveal the menu.
## Any key/button skips it. Timings: balance.json ui.splash.

signal finished

const SHINE := preload("res://assets/shaders/title_shine.gdshader")

var _bg: ColorRect
var _title: Label
var _glint: Glint
var _mat: ShaderMaterial
var _tween: Tween
var _leaving := false


func _ready() -> void:
	# Above SceneManager (100) so the focus bracket of the menu underneath stays hidden.
	layer = 110
	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_title = UITheme.title("FUNTASY", UITheme.FONT_LOGO)
	_mat = ShaderMaterial.new()
	_mat.shader = SHINE
	_mat.set_shader_parameter("manual", true)
	_mat.set_shader_parameter("progress", 0.0)
	_title.material = _mat
	_title.modulate.a = 0.0
	_bg.add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH

	_glint = Glint.new()
	_glint.modulate.a = 0.0
	_title.add_child(_glint)
	_play.call_deferred()


func _play() -> void:
	await get_tree().process_frame
	_title.pivot_offset = _title.size / 2.0
	# Whole-number end scale keeps the pixel font crisp.
	var big := Vector2.ONE * _t("title_scale", 2.0)
	_title.scale = big * 0.92
	# The glint flares on the upper-right corner of the last letter, where the sweep ends.
	_glint.position = Vector2(_title.size.x - 10.0, 12.0)

	_tween = create_tween()
	_tween.tween_interval(_t("black_hold", 0.4))
	var fade_in := _t("title_fade_in", 1.2)
	_tween.tween_property(_title, "modulate:a", 1.0, fade_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_title, "scale", big, fade_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Shine: one sweep across the letters, the whole logo flares brighter as it passes and a
	# star glint pops at the end.
	var shine := _t("shine_time", 0.9)
	_tween.tween_property(_mat, "shader_parameter/progress", 1.0, shine).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_title, "modulate", Color(1.5, 1.4, 1.2), shine * 0.5).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_title, "modulate", Color.WHITE, shine * 0.5).set_delay(shine * 0.5).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_glint, "modulate:a", 1.0, shine * 0.25).set_delay(shine * 0.6)
	_tween.parallel().tween_property(_glint, "spin", 1.0, shine * 0.9).set_delay(shine * 0.6)
	_tween.parallel().tween_property(_glint, "modulate:a", 0.0, shine * 0.4).set_delay(shine * 1.1)

	_tween.tween_interval(_t("title_hold", 0.9))
	_tween.tween_callback(_leave.bind(_t("fade_out", 0.8)))


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		_leave(_t("skip_fade", 0.25))


func _leave(time: float) -> void:
	if _leaving:
		return
	_leaving = true
	if _tween:
		_tween.kill()
	var t := create_tween()
	t.tween_property(_title, "modulate:a", 0.0, time * 0.5)
	t.tween_property(_bg, "modulate:a", 0.0, time * 0.5)
	await t.finished
	finished.emit()
	queue_free()


func _t(key: String, fallback: float) -> float:
	return float(GameData.bal("ui.splash." + key, fallback))


## Four-point star glint; `spin` 0..1 grows and turns it.
class Glint extends Control:
	var spin := 0.0:
		set(v):
			spin = v
			queue_redraw()

	func _draw() -> void:
		var s := 1.0 + spin * 0.6
		var a := spin * PI * 0.25
		var col := Color(1.0, 0.96, 0.8)
		for i in 4:
			var dir := Vector2.RIGHT.rotated(a + i * PI * 0.5)
			var side := dir.orthogonal() * 1.5 * s
			draw_colored_polygon(PackedVector2Array([dir * 14.0 * s, side, -side]), col)
		draw_circle(Vector2.ZERO, 2.5 * s, Color.WHITE)
