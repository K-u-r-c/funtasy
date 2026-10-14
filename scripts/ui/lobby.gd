extends Control
## Pre-run lobby: roster of connected players; the host starts the run.

var _list: VBoxContainer
var _start: AnimButton
var _hint: Label


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	var title := Label.new()
	title.text = "Lobby"
	title.position = Vector2(60, 40)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	add_child(title)

	var info := Label.new()
	info.position = Vector2(62, 90)
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0))
	match Net.backend:
		Net.Backend.STEAM:
			info.text = "Steam lobby %d" % Net.lobby_id if Net.is_host() else "Steam lobby"
		Net.Backend.ENET:
			info.text = "LAN game - port %d" % Net.DEFAULT_PORT if Net.is_host() else "LAN game"
	add_child(info)

	_list = VBoxContainer.new()
	_list.position = Vector2(60, 130)
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)

	var actions := VBoxContainer.new()
	actions.position = Vector2(60, 250)
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)

	_start = AnimButton.new()
	_start.text = "Start run"
	_start.visible = Net.is_host()
	_start.pressed.connect(Net.start_run)
	actions.add_child(_start)

	var leave := AnimButton.new()
	leave.text = "Leave"
	leave.pressed.connect(Net.leave_to_menu)
	actions.add_child(leave)

	_hint = Label.new()
	_hint.position = Vector2(60, 335)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_hint.text = "" if Net.is_host() else "Waiting for the host to start..."
	add_child(_hint)

	Net.players_changed.connect(_refresh)
	_refresh()
	(_start if Net.is_host() else leave).grab_focus()
	var delay := 0.0
	for b in actions.get_children():
		b.play_intro(delay)
		delay += 0.06


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for id in Net.players:
		var l := Label.new()
		l.text = "%s%s" % [Net.players[id], "  (host)" if id == 1 else ""]
		l.add_theme_font_size_override("font_size", 16)
		_list.add_child(l)
	var count := Net.players.size()
	_start.text = "Start run (%d player%s)" % [count, "" if count == 1 else "s"]
