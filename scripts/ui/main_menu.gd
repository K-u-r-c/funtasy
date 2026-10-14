extends Control

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _pages: Dictionary = {}
var _current: VBoxContainer
var _title: Label
var _status: Label
var _lobby_list: VBoxContainer
var _ip_edit: LineEdit
var _switching := false


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	_title = Label.new()
	_title.text = "FUNTASY"
	_title.position = Vector2(60, 36)
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_title.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.4))
	_title.add_theme_constant_override("outline_size", 8)
	add_child(_title)
	_animate_title()

	var tagline := Label.new()
	tagline.text = "co-op dungeon crawler"
	tagline.position = Vector2(64, 96)
	tagline.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0))
	add_child(tagline)

	_status = Label.new()
	_status.position = Vector2(60, 330)
	_status.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	add_child(_status)

	_build_main_page()
	_build_play_page()
	_build_browser_page()
	_build_lan_page()

	Net.session_ready.connect(_on_session_ready)
	Net.session_failed.connect(_on_session_failed)
	Net.lobby_list_received.connect(_populate_lobbies)

	var msg := SceneManager.take_message()
	if not msg.is_empty():
		_set_status(msg)
	_show_page("main", true)


func _animate_title() -> void:
	_title.pivot_offset = Vector2(140, 28)
	_title.modulate.a = 0.0
	var intro := create_tween().set_parallel(true)
	intro.tween_property(_title, "modulate:a", 1.0, 0.6)
	intro.tween_property(_title, "scale", Vector2.ONE, 0.6).from(Vector2(1.4, 1.4)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bob := create_tween().set_loops()
	bob.tween_property(_title, "position:y", 30.0, 1.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_title, "position:y", 38.0, 1.6).set_trans(Tween.TRANS_SINE)


# --- Page construction -------------------------------------------------------------------


func _new_page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.position = Vector2(60, 125)
	page.add_theme_constant_override("separation", 6)
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
	_btn(p, "Settings", _open_settings)
	_btn(p, "Exit", _quit)


func _build_play_page() -> void:
	var p := _new_page("play")
	var steam_ok := Net.steam_ready
	_btn(p, "Solo", _on_solo)
	_btn(p, "Host (Steam)", _on_host_steam, not steam_ok)
	_btn(p, "Join (Steam)", _on_join_steam_browser, not steam_ok)
	_btn(p, "Host (LAN)", _on_host_lan)
	_btn(p, "Join (LAN)", _show_page.bind("lan"))
	_btn(p, "Back", _show_page.bind("main"))
	if not steam_ok:
		var note := Label.new()
		note.text = "Steam unavailable: %s" % Net.steam_status
		note.add_theme_font_size_override("font_size", 10)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(200, 0)
		note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		p.add_child(note)


func _build_browser_page() -> void:
	var p := _new_page("browser")
	var head := Label.new()
	head.text = "Steam lobbies"
	p.add_child(head)
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	p.add_child(_lobby_list)
	_btn(p, "Refresh", Net.request_steam_lobbies)
	_btn(p, "Back", _show_page.bind("play"))


func _build_lan_page() -> void:
	var p := _new_page("lan")
	var head := Label.new()
	head.text = "Host address"
	p.add_child(head)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(200, 24)
	p.add_child(_ip_edit)
	_btn(p, "Connect", _on_join_lan)
	_btn(p, "Back", _show_page.bind("play"))


# --- Page switching ----------------------------------------------------------------------


func _show_page(page_name: String, instant := false) -> void:
	if _switching:
		return
	_switching = true
	_set_status("")
	if _current and not instant:
		var out := create_tween()
		out.tween_property(_current, "modulate:a", 0.0, 0.1)
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
			delay += 0.05
			if first == null and not c.disabled:
				first = c
	if first:
		first.grab_focus()
	if page_name == "browser":
		_clear_lobbies()
		Net.request_steam_lobbies()
	_switching = false


func _set_status(text: String) -> void:
	_status.text = text


# --- Actions -----------------------------------------------------------------------------


func _open_settings() -> void:
	var s := SETTINGS_SCENE.instantiate()
	add_child(s)
	s.closed.connect(func():
		for c in _current.get_children():
			if c is AnimButton and not c.disabled:
				c.grab_focus()
				break)


func _quit() -> void:
	Net.shutdown()
	get_tree().quit()


func _on_solo() -> void:
	Net.host_solo()


func _on_host_steam() -> void:
	_set_status("Creating Steam lobby...")
	Net.host_steam()


func _on_host_lan() -> void:
	_set_status("Hosting on port %d..." % Net.DEFAULT_PORT)
	Net.host_enet()


func _on_join_lan() -> void:
	_set_status("Connecting...")
	Net.join_enet(_ip_edit.text.strip_edges())


func _on_join_steam_browser() -> void:
	_show_page("browser")


func _clear_lobbies() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()


func _populate_lobbies(lobbies: Array) -> void:
	if _lobby_list == null:
		return
	_clear_lobbies()
	if lobbies.is_empty():
		var none := Label.new()
		none.text = "No lobbies found"
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_lobby_list.add_child(none)
		return
	for l in lobbies:
		var b := AnimButton.new()
		b.text = "%s  (%d/%d)" % [l.name, l.count, l.max]
		b.pressed.connect(func():
			_set_status("Joining lobby...")
			Net.join_steam(l.id))
		_lobby_list.add_child(b)
		b.play_intro(0.0)


func _on_session_ready() -> void:
	if Net.backend == Net.Backend.SOLO:
		Net.start_run()
	else:
		SceneManager.change_scene(Net.LOBBY_SCENE)


func _on_session_failed(reason: String) -> void:
	_set_status(reason)
