extends CanvasLayer
## Fade-to-black scene transitions.

const FADE_TIME := 0.25

var message: String = ""  ## One-shot text the next scene can show (e.g. "Host disconnected").
var _fade: ColorRect
var _busy := false
var _queued: Array = []  ## [path, message] requested while a transition was running


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func change_scene(path: String, msg: String = "") -> void:
	if _busy:
		_queued = [path, msg]
		return
	_busy = true
	message = msg
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	t = create_tween()
	t.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	await t.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	if not _queued.is_empty():
		var next := _queued
		_queued = []
		change_scene(next[0], next[1])


func take_message() -> String:
	var m := message
	message = ""
	return m
