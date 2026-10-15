extends UIModal
## In-game menu. The game keeps running underneath (it's online co-op).

const SETTINGS_MENU := preload("res://scripts/ui/settings_menu.gd")

var _box: VBoxContainer
var _options_btn: Button


func _init() -> void:
	max_size = Vector2(360, 520)
	prompts = [["ui_accept", "Select"], ["ui_cancel", "Resume"]]


func _build() -> void:
	var t := UITheme.title("Paused", UITheme.FONT_TITLE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	var sub := UITheme.label("The game keeps running for your party", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	content.add_child(_box)
	var resume := _add("Resume", func(): closed.emit())
	_options_btn = _add("Options", _open_settings)
	_add("Leave to main menu" if not multiplayer.is_server() else "End session (host)", _leave)
	var delay := 0.05
	for b in _box.get_children():
		b.play_intro(delay)
		delay += 0.04
	resume.grab_focus.call_deferred()


func _add(text: String, cb: Callable) -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func _open_settings() -> void:
	var s: Control = SETTINGS_MENU.new()
	add_child(s)
	s.closed.connect(func(): _options_btn.grab_focus())


func _leave() -> void:
	if multiplayer.is_server():
		for p in get_tree().get_nodes_in_group("players"):
			p.persist()
	NetworkManager.leave_to_menu()
