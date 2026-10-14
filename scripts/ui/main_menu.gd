extends Control
## Title screen: start a solo/LAN/Steam session or open the options. Every session (solo too)
## continues in the lobby, where players pick their character.

const SETTINGS_MENU := preload("res://scripts/ui/settings_menu.gd")

var _pages: Dictionary = {}
var _current: VBoxContainer
var _status: Label
var _lobby_list: VBoxContainer
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _switching := false
var _overlay: Control


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	var title := UITheme.title("FUNTASY", 64)
	title.position = Vector2(80, 60)
	add_child(title)
	var tagline := UITheme.label("A dark fantasy co-op dungeon crawler", UITheme.TEXT_DIM, 18)
	tagline.position = Vector2(86, 140)
	add_child(tagline)

	_status = UITheme.label("", UITheme.DANGER)
	_status.position = Vector2(80, 490)
	add_child(_status)

	var hint := UITheme.label("", UITheme.TEXT_DIM, 12)
	hint.text = "v0.1 MVP  -  Steam: %s" % ("ready" if NetworkManager.steam_ready else NetworkManager.steam_status)
	hint.position = Vector2(80, 515)
	add_child(hint)

	_build_main_page()
	_build_play_page()
	_build_browser_page()
	_build_lan_page()

	NetworkManager.session_ready.connect(_on_session_ready)
	NetworkManager.session_failed.connect(_set_status)
	NetworkManager.lobby_list_received.connect(_populate_lobbies)

	var msg := SceneManager.take_message()
	_show_page("main", true)
	if not msg.is_empty():
		_set_status(msg)
	AudioManager.play_music("menu")


func _unhandled_input(ev: InputEvent) -> void:
	if _overlay != null:
		return
	if ev.is_action_pressed("ui_cancel") and _current != _pages["main"]:
		get_viewport().set_input_as_handled()
		_show_page("play" if _current in [_pages["lan"], _pages["browser"]] else "main")


# --- Page construction -----------------------------------------------------------------------


func _new_page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.position = Vector2(80, 200)
	page.add_theme_constant_override("separation", 8)
	page.visible = false
	add_child(page)
	_pages[page_name] = page
	return page


func _btn(page: VBoxContainer, text: String, action: Callable, disabled := false) -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(action)
	page.add_child(b)
	return b


func _build_main_page() -> void:
	var p := _new_page("main")
	_btn(p, "Play", _show_page.bind("play"))
	_btn(p, "Options", open_settings)
	_btn(p, "Quit", _quit)


func _build_play_page() -> void:
	var p := _new_page("play")
	var steam_ok := NetworkManager.steam_ready
	_btn(p, "Solo", NetworkManager.host_solo)
	_btn(p, "Host LAN game", _on_host_lan)
	_btn(p, "Join LAN game", _show_page.bind("lan"))
	_btn(p, "Host Steam lobby", _on_host_steam, not steam_ok)
	_btn(p, "Join Steam lobby", _show_page.bind("browser"), not steam_ok)
	_btn(p, "Back", _show_page.bind("main"))


func _build_browser_page() -> void:
	var p := _new_page("browser")
	p.add_child(UITheme.label("Steam lobbies (test app 480)", UITheme.ACCENT))
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	p.add_child(_lobby_list)
	_btn(p, "Refresh", NetworkManager.request_steam_lobbies)
	_btn(p, "Back", _show_page.bind("play"))


func _build_lan_page() -> void:
	var p := _new_page("lan")
	p.add_child(UITheme.label("Host address", UITheme.ACCENT))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(240, 32)
	p.add_child(_ip_edit)
	p.add_child(UITheme.label("Port", UITheme.ACCENT))
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(240, 32)
	p.add_child(_port_edit)
	_btn(p, "Connect", _on_join_lan)
	_btn(p, "Back", _show_page.bind("play"))


# --- Page switching --------------------------------------------------------------------------


func _show_page(page_name: String, instant := false) -> void:
	if _switching:
		return
	_switching = true
	_set_status("")
	if _current and not instant:
		var out := create_tween()
		out.tween_property(_current, "modulate:a", 0.0, 0.08)
		await out.finished
	if _current:
		_current.hide()
	_current = _pages[page_name]
	_current.modulate.a = 1.0
	_current.show()
	var delay := 0.0
	var first: Control = null
	for c in _current.get_children():
		if c is AnimButton:
			c.play_intro(delay)
			delay += 0.04
		if first == null and c is Control and c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and c.disabled):
			first = c
	if first:
		first.grab_focus()
	if page_name == "browser":
		_clear_lobbies()
		NetworkManager.request_steam_lobbies()
		# Fresh lobbies can take a moment to show up in Steam's list; ask once more.
		get_tree().create_timer(2.5).timeout.connect(func():
			if _current == _pages["browser"]:
				NetworkManager.request_steam_lobbies())
	_switching = false


func _set_status(text: String) -> void:
	_status.text = text


# --- Actions ---------------------------------------------------------------------------------


func open_settings() -> void:
	_overlay = SETTINGS_MENU.new()
	add_child(_overlay)
	_overlay.closed.connect(func():
		_overlay = null
		for c in _current.get_children():
			if c is AnimButton and not c.disabled:
				c.grab_focus()
				break)


func _quit() -> void:
	SceneManager.quit_game()


func _on_host_steam() -> void:
	_set_status("Creating Steam lobby...")
	NetworkManager.host_steam()


func _on_host_lan() -> void:
	_set_status("Hosting on port %d..." % NetworkManager.DEFAULT_PORT)
	NetworkManager.host_enet()


func _on_join_lan() -> void:
	_set_status("Connecting...")
	NetworkManager.join_enet(_ip_edit.text.strip_edges(), int(_port_edit.text))


func _clear_lobbies() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()


func _populate_lobbies(lobbies: Array) -> void:
	if _lobby_list == null:
		return
	_clear_lobbies()
	if lobbies.is_empty():
		_lobby_list.add_child(UITheme.label("No lobbies found", UITheme.TEXT_DIM))
		return
	for l in lobbies:
		var b := AnimButton.new()
		b.text = "%s  (%d/%d)" % [l.name, l.count, l.max]
		b.pressed.connect(func():
			_set_status("Joining lobby...")
			NetworkManager.join_steam(l.id))
		_lobby_list.add_child(b)
		b.play_intro(0.0)


func _on_session_ready() -> void:
	SceneManager.change_scene(NetworkManager.LOBBY_SCENE)
