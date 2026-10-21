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
var _version: Label


const SHINE := preload("res://assets/shaders/title_shine.gdshader")

var _pages_box: VBoxContainer
static var _splash_shown := false  ## The boot splash plays once per launch, not on every return.


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	# Everything sits in containers inside a safe-area margin, pinned to the left edge; the
	# backdrop fills the rest of any aspect ratio.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := int(GameData.bal("ui.safe_margin", 10))
	safe.add_theme_constant_override("margin_left", m + 40)
	safe.add_theme_constant_override("margin_right", m + 40)
	safe.add_theme_constant_override("margin_top", m + 24)
	safe.add_theme_constant_override("margin_bottom", m + 8)
	add_child(safe)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	safe.add_child(col)

	var title := UITheme.title("FUNTASY", UITheme.FONT_LOGO)
	var mat := ShaderMaterial.new()
	mat.shader = SHINE
	title.material = mat
	col.add_child(title)
	col.add_child(_spacer())

	var panel := GlassWindow.new(false)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(panel)
	_pages_box = VBoxContainer.new()
	panel.add_child(_pages_box)
	col.add_child(_spacer())

	_status = UITheme.label("", UITheme.DANGER)
	col.add_child(_status)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	col.add_child(foot)
	_version = UITheme.label("v%s" % str(ProjectSettings.get_setting("application/config/version", "0.2.2")), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	_version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_version)
	foot.add_child(PromptBar.new([["ui_accept", Loc.t("Select")], ["ui_cancel", Loc.t("Back")]]))

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
	# Automated test runs (user args) and headless instances go straight to the menu.
	if not _splash_shown and OS.get_cmdline_user_args().is_empty() and DisplayServer.get_name() != "headless":
		_splash_shown = true
		add_child(SplashScreen.new())


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


func _unhandled_input(ev: InputEvent) -> void:
	if _overlay != null:
		return
	if ev.is_action_pressed("ui_cancel") and _current != _pages["main"]:
		get_viewport().set_input_as_handled()
		AudioManager.play_sfx("ui_back", 0.03)
		_show_page("play" if _current in [_pages["lan"], _pages["browser"]] else "main")


# --- Page construction -----------------------------------------------------------------------


func _new_page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.visible = false
	_pages_box.add_child(page)
	_pages[page_name] = page
	return page


func _btn(page: VBoxContainer, text: String, action: Callable, disabled := false, icon_key := "") -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	b.disabled = disabled
	if not icon_key.is_empty():
		b.icon = UITheme.icon_tex(icon_key)
		b.add_theme_constant_override("icon_max_width", 16)
	b.pressed.connect(action)
	page.add_child(b)
	return b


func _build_main_page() -> void:
	var p := _new_page("main")
	_btn(p, Loc.t("Play"), _show_page.bind("play"), false, "menu_play")
	_btn(p, Loc.t("Options"), open_settings, false, "menu_options")
	_btn(p, Loc.t("Quit"), _quit, false, "menu_quit")


func _build_play_page() -> void:
	var p := _new_page("play")
	var steam_ok := NetworkManager.steam_ready
	_btn(p, Loc.t("Solo"), NetworkManager.host_solo, false, "nav_character")
	_btn(p, Loc.t("Host LAN game"), _on_host_lan, false, "menu_host")
	_btn(p, Loc.t("Join LAN game"), _show_page.bind("lan"), false, "menu_join")
	_btn(p, Loc.t("Host Steam lobby"), _on_host_steam, not steam_ok, "ui_crown")
	_btn(p, Loc.t("Join Steam lobby"), _show_page.bind("browser"), not steam_ok, "ui_party")
	_btn(p, Loc.t("Back"), _show_page.bind("main"), false, "menu_back")


func _build_browser_page() -> void:
	var p := _new_page("browser")
	p.add_child(UITheme.label(Loc.t("Steam lobbies (test app 480)"), UITheme.ACCENT, UITheme.FONT_SMALL))
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	p.add_child(_lobby_list)
	_btn(p, Loc.t("Refresh"), NetworkManager.request_steam_lobbies, false, "act_reset")
	_btn(p, Loc.t("Back"), _show_page.bind("play"), false, "menu_back")


func _build_lan_page() -> void:
	var p := _new_page("lan")
	p.add_child(UITheme.label(Loc.t("Host address"), UITheme.ACCENT, UITheme.FONT_SMALL))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(240, 32)
	p.add_child(_ip_edit)
	p.add_child(UITheme.label(Loc.t("Port"), UITheme.ACCENT, UITheme.FONT_SMALL))
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(240, 32)
	p.add_child(_port_edit)
	_btn(p, Loc.t("Connect"), _on_join_lan, false, "menu_join")
	_btn(p, Loc.t("Back"), _show_page.bind("play"), false, "menu_back")


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
	var locale := TranslationServer.get_locale()
	_overlay.closed.connect(func():
		_overlay = null
		if TranslationServer.get_locale() != locale:
			# A new language: the menu is built again with the new texts.
			SceneManager.change_scene(NetworkManager.MENU_SCENE)
			return
		for c in _current.get_children():
			if c is AnimButton and not c.disabled:
				c.grab_focus()
				break)


func _quit() -> void:
	SceneManager.quit_game()


func _on_host_steam() -> void:
	_set_status(Loc.t("Creating Steam lobby..."))
	NetworkManager.host_steam()


func _on_host_lan() -> void:
	_set_status(Loc.f("Hosting on port %d...", [NetworkManager.DEFAULT_PORT]))
	NetworkManager.host_enet()


func _on_join_lan() -> void:
	_set_status(Loc.t("Connecting..."))
	NetworkManager.join_enet(_ip_edit.text.strip_edges(), int(_port_edit.text))


func _clear_lobbies() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()


func _populate_lobbies(lobbies: Array) -> void:
	if _lobby_list == null:
		return
	_clear_lobbies()
	if lobbies.is_empty():
		_lobby_list.add_child(UITheme.label(Loc.t("No lobbies found"), UITheme.TEXT_DIM))
		return
	for l in lobbies:
		var b := AnimButton.new()
		b.text = "%s  (%d/%d)" % [l.name, l.count, l.max]
		b.pressed.connect(func():
			_set_status(Loc.t("Joining lobby..."))
			NetworkManager.join_steam(l.id))
		_lobby_list.add_child(b)
		b.play_intro(0.0)


func _on_session_ready() -> void:
	SceneManager.change_scene(NetworkManager.LOBBY_SCENE)
