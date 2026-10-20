extends Node
## Video, audio and language preferences, stored in the [video], [audio] and [game] sections of
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
## Interface language (#32): [locale, name shown in its own language].
const LANGUAGES := [["en", "English"], ["pl", "Polski"]]
var language := "en"
## #56: the window is out of focus (alt-tab, minimised, another workspace). The compositor then
## throttles or stops the window's frames and V-Sync would stall the main loop with them; the host
## simulates for the whole party, so it keeps running at full rate behind a frame cap instead.
var in_background := false


func _ready() -> void:
	_ensure_buses()
	load_settings()
	# --lang=<locale> overrides the saved language (screenshot tours, tests).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			language = a.get_slice("=", 1)
	apply_language()
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
	_apply_frame_pacing()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			in_background = true
			_apply_frame_pacing()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			in_background = false
			_apply_frame_pacing()


func _apply_frame_pacing() -> void:
	var sync := vsync and not in_background
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if sync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(GameData.bal("performance.background_fps", 60)) if in_background else 0


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
	SaveSystem.write_section("game", {"language": language})


func load_settings() -> void:
	var v := SaveSystem.read_section("video")
	window_mode = clampi(int(v.get("window_mode", window_mode)), 0, 2)
	var size: Variant = v.get("window_size", window_size)
	window_size = size if size is Vector2i else window_size
	if DisplayServer.get_name() != "headless" and not available_sizes().has(window_size):
		window_size = available_sizes().back()
	vsync = bool(v.get("vsync", vsync))
	screen_shake = bool(v.get("screen_shake", screen_shake))
	var gsec := SaveSystem.read_section("game")
	language = str(gsec.get("language", language))
	var a := SaveSystem.read_section("audio")
	for bus in BUSES:
		volumes[bus] = float(a.get(bus, volumes[bus]))


## Switches every translated text to `language` (texts built afterwards; open screens rebuild
## on EventBus.locale_changed).
func apply_language() -> void:
	if not LANGUAGES.any(func(l): return l[0] == language):
		language = "en"
	TranslationServer.set_locale(language)


func set_language(locale: String) -> void:
	if locale == language:
		return
	language = locale
	apply_language()
	save_settings()
	EventBus.locale_changed.emit()


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
