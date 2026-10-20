extends CanvasLayer
## Fade-to-black scene transitions.

const FADE_TIME := 0.25

var message: String = ""  ## One-shot text the next scene can show (e.g. "Host disconnected").
var _fade: ColorRect
var _busy := false
var _queued: Array = []  ## [path, message] requested while a transition was running


func _ready() -> void:
	UITheme.install(get_tree().root)
	get_tree().auto_accept_quit = false
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# One gamepad/keyboard focus bracket for every screen, above all other UI.
	add_child(FocusBracket.new())
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


## The only way the game quits: closes the session, lets the audio server release its streams
## (otherwise they are reported as leaked at exit), then quits.
func quit_game(code: int = 0) -> void:
	# Free the game scene before the peer is reset (see SessionRpc).
	var game := get_tree().get_first_node_in_group("game")
	# #55: closing the window mid-floor keeps the floor in the saved game.
	if game and multiplayer.is_server() and game.has_method("host_save"):
		game.host_save()
	get_tree().multiplayer_poll = false
	if game:
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.queue_free()
		await get_tree().process_frame
	NetworkManager.shutdown()
	AudioManager.close()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
