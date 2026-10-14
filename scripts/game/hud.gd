extends CanvasLayer
## In-game HUD, pause menu and game-over screen (all built in code).

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _floor_label: Label
var _hp_label: Label
var _roster: Label
var _stairs_label: Label
var _pause: Control
var _over: Control
var _over_label: Label
var _settings_open := false
var _resume_btn: AnimButton
var _back_btn: AnimButton

@onready var game = get_parent()


func _ready() -> void:
	layer = 10
	_floor_label = _make_label(Vector2(8, 6), 12)
	_hp_label = _make_label(Vector2(8, 22), 12)
	_roster = _make_label(Vector2(500, 6), 9)
	_stairs_label = _make_label(Vector2(0, 330), 10)
	_stairs_label.size.x = 640
	_stairs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause = _build_pause()
	_over = _build_game_over()
	set_floor(0)
	set_kills(0)


func _process(_delta: float) -> void:
	var lines: PackedStringArray = []
	var me = game.players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	for p in game.players_root.get_children():
		lines.append("%s  %s" % [p.display_name, "down" if not p.alive else "%d/%d" % [p.hp, p.MAX_HP]])
	_roster.text = "\n".join(lines)
	if me:
		_hp_label.text = "HP  " + "♥".repeat(me.hp) + "·".repeat(maxi(me.MAX_HP - me.hp, 0)) \
			+ ("   (down - wait for the party)" if not me.alive else "")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _over.visible and not _settings_open:
		get_viewport().set_input_as_handled()
		_set_pause(not _pause.visible)


func set_floor(depth: int) -> void:
	_floor_label.text = "Floor %d   Kills %d" % [depth, game.kills]


func set_kills(_total: int) -> void:
	_floor_label.text = "Floor %d   Kills %d" % [game.depth, game.kills]


func set_stairs_status(gathered: int, alive: int) -> void:
	_stairs_label.text = "Gather at the stairs to descend (%d/%d)" % [gathered, alive] \
		if gathered > 0 else "Find the stairs - everyone must stand on them"


func show_game_over(final_depth: int, final_kills: int) -> void:
	_pause.hide()
	_over_label.text = "The party has fallen\nReached floor %d  -  %d kills" % [final_depth, final_kills]
	_over.modulate.a = 0.0
	_over.show()
	game.input_blocked = true
	create_tween().tween_property(_over, "modulate:a", 1.0, 0.5)
	_back_btn.grab_focus()


func _set_pause(on: bool) -> void:
	_pause.visible = on
	game.input_blocked = on
	if on:
		_resume_btn.grab_focus()


func _make_label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l


func _build_pause() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(220, 100)
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_resume_btn = _menu_button(box, "Resume", func(): _set_pause(false))
	_menu_button(box, "Settings", _open_settings)
	_menu_button(box, "Leave to menu", func(): Net.leave_to_menu())
	return root


func _build_game_over() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(200, 110)
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)
	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	box.add_child(title)
	_over_label = Label.new()
	box.add_child(_over_label)
	_back_btn = _menu_button(box, "Back to menu", func(): Net.leave_to_menu())
	return root


func _menu_button(parent: Control, text: String, action: Callable) -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_settings_open = true
	var s := SETTINGS_SCENE.instantiate()
	add_child(s)
	s.closed.connect(func():
		_settings_open = false
		_resume_btn.grab_focus())
