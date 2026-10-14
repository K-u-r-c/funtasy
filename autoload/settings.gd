extends Node
## Video and audio preferences, stored in the [video] and [audio] sections of
## user://settings.cfg. Input bindings live in InputSettings.

const BASE_SIZE := Vector2i(960, 540)

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

const MODE_NAMES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const WINDOW_SIZES := [
	Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const BUSES := ["Master", "Music", "SFX"]

var window_mode: int = WindowMode.WINDOWED
var window_size: Vector2i = Vector2i(1920, 1080)
var vsync: bool = true
var screen_shake: bool = true
var volumes: Dictionary = {"Master": 0.8, "Music": 0.7, "SFX": 0.8}


func _ready() -> void:
	_ensure_buses()
	load_settings()
	if DisplayServer.get_name() != "headless":
		apply()
	apply_audio()


func available_sizes() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array[Vector2i] = []
	for s in WINDOW_SIZES:
		if s.x <= screen.x and s.y <= screen.y:
			out.append(s)
	if out.is_empty():
		out.append(WINDOW_SIZES[0])
	return out


func snapshot() -> Dictionary:
	return {"window_mode": window_mode, "window_size": window_size, "vsync": vsync}


func restore(snap: Dictionary) -> void:
	window_mode = snap.window_mode
	window_size = snap.window_size
	vsync = snap.vsync
	apply()


func apply() -> void:
	var window := get_window()
	match window_mode:
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.size = window_size
			_center_window()
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


func apply_audio() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		var v: float = clampf(float(volumes.get(bus, 1.0)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func save_settings() -> void:
	SaveSystem.write_section("video", {
		"window_mode": window_mode, "window_size": window_size, "vsync": vsync,
		"screen_shake": screen_shake,
	})
	SaveSystem.write_section("audio", volumes)


func load_settings() -> void:
	var v := SaveSystem.read_section("video")
	window_mode = clampi(int(v.get("window_mode", window_mode)), 0, 2)
	var size: Variant = v.get("window_size", window_size)
	window_size = size if size is Vector2i else window_size
	if DisplayServer.get_name() != "headless" and not available_sizes().has(window_size):
		window_size = available_sizes().back()
	vsync = bool(v.get("vsync", vsync))
	screen_shake = bool(v.get("screen_shake", screen_shake))
	var a := SaveSystem.read_section("audio")
	for bus in BUSES:
		volumes[bus] = float(a.get(bus, volumes[bus]))


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen)
	get_window().position = rect.position + (rect.size - get_window().size) / 2


func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
