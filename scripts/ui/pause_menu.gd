extends Control
## In-game menu. The game keeps running underneath (it's online co-op).

signal closed

const SETTINGS_MENU := preload("res://scripts/ui/settings_menu.gd")

var player: Player
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	center.add_child(_box)
	_box.add_child(UITheme.title("Paused", 30))
	_box.add_child(UITheme.label("(the game keeps running for your party)", UITheme.TEXT_DIM, 12))
	_add("Resume", func(): closed.emit())
	_add("Options", _open_settings)
	_add("Leave to main menu" if not multiplayer.is_server() else "End session (host)", _leave)
	_box.get_child(2).grab_focus.call_deferred()


func _add(text: String, cb: Callable) -> void:
	var b := AnimButton.new()
	b.text = text
	b.pressed.connect(cb)
	_box.add_child(b)


func _open_settings() -> void:
	var s: Control = SETTINGS_MENU.new()
	add_child(s)
	s.closed.connect(func(): _box.get_child(3).grab_focus())


func _leave() -> void:
	if player and is_instance_valid(player) and multiplayer.is_server():
		for p in get_tree().get_nodes_in_group("players"):
			p.persist()
	GameState.save_local_character()
	NetworkManager.leave_to_menu()
