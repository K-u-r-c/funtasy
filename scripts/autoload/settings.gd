extends Node
## Video settings (window mode, resolution, vsync) persisted to user://settings.cfg.
## Also registers the game's input actions so they exist without editing project.godot.

const PATH := "user://settings.cfg"
const BASE_SIZE := Vector2i(640, 360)

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

const MODE_NAMES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]

var window_mode: int = WindowMode.WINDOWED
var scale_factor: int = 2
var vsync: bool = true


func _ready() -> void:
	_register_inputs()
	load_settings()
	apply()


## Integer multiples of the 640x360 base that fit on the current screen.
func available_scales() -> Array[int]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array[int] = []
	for s in range(1, 9):
		if BASE_SIZE * s <= screen:
			out.append(s)
	if out.is_empty():
		out.append(1)
	return out


func resolution_for(scale: int) -> Vector2i:
	return BASE_SIZE * scale


func snapshot() -> Dictionary:
	return {"window_mode": window_mode, "scale_factor": scale_factor, "vsync": vsync}


func restore(snap: Dictionary) -> void:
	window_mode = snap.window_mode
	scale_factor = snap.scale_factor
	vsync = snap.vsync
	apply()


func apply() -> void:
	var window := get_window()
	match window_mode:
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.size = resolution_for(scale_factor)
			_center_window()
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "scale_factor", scale_factor)
	cfg.set_value("video", "vsync", vsync)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	window_mode = clampi(int(cfg.get_value("video", "window_mode", window_mode)), 0, 2)
	scale_factor = int(cfg.get_value("video", "scale_factor", scale_factor))
	if not available_scales().has(scale_factor):
		scale_factor = available_scales().back()
	vsync = bool(cfg.get_value("video", "vsync", vsync))


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen)
	get_window().position = rect.position + (rect.size - get_window().size) / 2


func _register_inputs() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("attack", [KEY_SPACE, KEY_J])
	_add_action("pause", [KEY_ESCAPE])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
