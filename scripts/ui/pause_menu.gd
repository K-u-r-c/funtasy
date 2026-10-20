extends UIModal
## In-game menu. The game keeps running underneath (it's online co-op).

const SETTINGS_MENU := preload("res://scripts/ui/settings_menu.gd")

var _box: VBoxContainer
var _options_btn: Button


func _init() -> void:
	max_size = Vector2(360, 520)
	prompts = [["ui_accept", Loc.t("Select")], ["ui_cancel", Loc.t("Resume")]]


func _build() -> void:
	header.add_child(UITheme.icon("menu_resume", 32))
	var t := UITheme.title(Loc.t("Paused"), UITheme.FONT_TITLE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	var sub := UITheme.label(Loc.t("The game keeps running for your party"), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	content.add_child(_box)
	var resume := _add(Loc.t("Resume"), func(): closed.emit(), "menu_resume")
	_options_btn = _add(Loc.t("Options"), _open_settings, "menu_options")
	_add(Loc.t("Leave to main menu") if not multiplayer.is_server() else Loc.t("End session (host)"), _leave, "menu_leave")
	var delay := 0.05
	for b in _box.get_children():
		b.play_intro(delay)
		delay += 0.04
	resume.grab_focus.call_deferred()


func _add(text: String, cb: Callable, icon_key := "") -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	if not icon_key.is_empty():
		b.icon = UITheme.icon_tex(icon_key)
		b.add_theme_constant_override("icon_max_width", 16)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func _open_settings() -> void:
	var s: Control = SETTINGS_MENU.new()
	add_child(s)
	var locale := TranslationServer.get_locale()
	s.closed.connect(func():
		if TranslationServer.get_locale() != locale:
			closed.emit()  # back to the game: the HUD rebuilds in the new language
		else:
			_options_btn.grab_focus())


func _leave() -> void:
	if multiplayer.is_server():
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.host_save()
	NetworkManager.leave_to_menu()
