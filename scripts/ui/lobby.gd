extends Control
## Pre-run lobby. Every player picks a name + class (a saved character with the same name and
## class is loaded automatically), the host edits the game settings (generated from
## data/game_settings.json) and starts the run once everyone has confirmed a character.

var _name_edit: LineEdit
var _class_buttons: Dictionary = {}
var _class_desc: Label
var _saved_box: VBoxContainer
var _confirm: AnimButton
var _roster_box: VBoxContainer
var _settings_box: GridContainer
var _start: AnimButton
var _status: Label
var _selected_class := "warrior"
var _setting_controls: Dictionary = {}


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 24)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.title("Lobby", 34))
	head.add_child(UITheme.label(_session_text(), UITheme.TEXT_DIM, 14))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_character_panel())
	body.add_child(_build_party_panel())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	_start = AnimButton.new()
	_start.text = "Start run"
	_start.visible = multiplayer.is_server()
	_start.pressed.connect(_on_start)
	bottom.add_child(_start)
	var leave := AnimButton.new()
	leave.text = "Leave"
	leave.pressed.connect(func(): NetworkManager.leave_to_menu())
	bottom.add_child(leave)
	_status = UITheme.label("", UITheme.TEXT_DIM, 14)
	bottom.add_child(_status)

	GameState.roster_changed.connect(_refresh_roster)
	GameState.settings_changed.connect(_refresh_settings)
	NetworkManager.peer_joined.connect(func(_id): _refresh_roster())
	NetworkManager.peer_left.connect(func(_id): _refresh_roster())

	var saved := SaveSystem.list_characters()
	if not GameState.local_character.is_empty():
		_name_edit.text = GameState.local_character.name
		_select_class(GameState.local_character.class_id)
	elif not saved.is_empty():
		_name_edit.text = saved[0].name
		_select_class(saved[0].class_id)
	else:
		_name_edit.text = NetworkManager.local_name().substr(0, 16)
		_select_class("warrior")
	_refresh_saved()
	_refresh_roster()
	_refresh_settings()
	_confirm.grab_focus()
	AudioManager.play_music("menu")
	# Coming back from a run: re-announce our (possibly updated) character.
	if not GameState.local_character.is_empty():
		GameState.submit_local_character()


func _session_text() -> String:
	match NetworkManager.backend:
		NetworkManager.Backend.STEAM:
			return "Steam lobby" + (" (id %d)" % NetworkManager.lobby_id if multiplayer.is_server() else "")
		NetworkManager.Backend.ENET:
			return "LAN game on port %d" % NetworkManager.last_port
		NetworkManager.Backend.SOLO:
			return "Solo game"
	return ""


# --- Character panel ------------------------------------------------------------------------


func _build_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.label("Your character", UITheme.ACCENT, 18))
	var name_row := HBoxContainer.new()
	name_row.add_child(UITheme.label("Name "))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(260, 30)
	_name_edit.text_changed.connect(func(_t): _refresh_confirm_text())
	name_row.add_child(_name_edit)
	v.add_child(name_row)

	var classes := HBoxContainer.new()
	classes.add_theme_constant_override("separation", 6)
	v.add_child(classes)
	for cid in ["warrior", "ranger", "mage", "priest"]:
		if not GameData.classes.has(cid):
			continue
		var b := Button.new()
		b.text = GameData.classes[cid].name
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(100, 32)
		b.add_theme_color_override("font_color", UITheme.hex(GameData.classes[cid].color))
		b.pressed.connect(_select_class.bind(cid))
		classes.add_child(b)
		_class_buttons[cid] = b
	_class_desc = UITheme.label("", UITheme.TEXT_DIM, 13)
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.custom_minimum_size = Vector2(410, 54)
	v.add_child(_class_desc)

	_confirm = AnimButton.new()
	_confirm.pressed.connect(_on_confirm)
	v.add_child(_confirm)

	v.add_child(UITheme.label("Saved characters", UITheme.ACCENT, 14))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	v.add_child(scroll)
	_saved_box = VBoxContainer.new()
	_saved_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_saved_box)
	return panel


func _select_class(cid: String) -> void:
	_selected_class = cid
	for k in _class_buttons:
		_class_buttons[k].set_pressed_no_signal(k == cid)
	var c: Dictionary = GameData.classes[cid]
	_class_desc.text = "%s  Resource: %s." % [c.description, str(c.resource).capitalize()]
	_refresh_confirm_text()


func _refresh_confirm_text() -> void:
	var nm := _name_edit.text.strip_edges()
	var saved := SaveSystem.load_character(nm, _selected_class) if not nm.is_empty() else {}
	var lvl := " (new, level 1)" if saved.is_empty() else " (level %d)" % int(saved.level)
	_confirm.text = "Play as %s%s" % [GameData.classes[_selected_class].name, lvl]


func _refresh_saved() -> void:
	for c in _saved_box.get_children():
		c.queue_free()
	for ch in SaveSystem.list_characters():
		var b := Button.new()
		var cname: String = GameData.classes.get(ch.class_id, {}).get("name", ch.class_id)
		b.text = "%s - %s, level %d" % [ch.name, cname, int(ch.level)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_name_edit.text = ch.name
			_select_class(ch.class_id)
			_confirm.grab_focus())
		_saved_box.add_child(b)


func _on_confirm() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm.is_empty():
		_status.text = "Enter a name first."
		return
	GameState.select_character(nm, _selected_class)
	GameState.save_local_character()
	_refresh_saved()
	_status.text = "Character confirmed."


# --- Party + settings -----------------------------------------------------------------------


func _build_party_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.label("Party", UITheme.ACCENT, 18))
	_roster_box = VBoxContainer.new()
	_roster_box.custom_minimum_size = Vector2(0, 130)
	v.add_child(_roster_box)
	v.add_child(UITheme.label("Game settings" + ("" if multiplayer.is_server() else " (host only)"), UITheme.ACCENT, 18))
	_settings_box = GridContainer.new()
	_settings_box.columns = 2
	_settings_box.add_theme_constant_override("h_separation", 16)
	_settings_box.add_theme_constant_override("v_separation", 6)
	v.add_child(_settings_box)
	for d in GameData.game_settings:
		var l := UITheme.label(d.label)
		l.tooltip_text = d.get("description", "")
		_settings_box.add_child(l)
		var ctrl: Control
		match d.type:
			"bool":
				var cb := CheckButton.new()
				cb.toggled.connect(func(on: bool): GameState.set_setting(d.id, on))
				ctrl = cb
			"enum":
				var ob := OptionButton.new()
				for o in d.options:
					ob.add_item(o)
				ob.item_selected.connect(func(i: int): GameState.set_setting(d.id, i))
				ctrl = ob
			_:
				ctrl = UITheme.label("?")
		ctrl.tooltip_text = d.get("description", "")
		if ctrl is BaseButton:
			ctrl.disabled = not multiplayer.is_server()
		_settings_box.add_child(ctrl)
		_setting_controls[d.id] = ctrl
	return panel


func _refresh_settings() -> void:
	for id in _setting_controls:
		var c: Control = _setting_controls[id]
		var v: Variant = GameState.setting(id)
		if c is CheckButton:
			c.set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			c.select(int(v))


func _refresh_roster() -> void:
	for c in _roster_box.get_children():
		c.queue_free()
	var waiting := 0
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers() if multiplayer.is_server() else [])
	for id in GameState.roster:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		if GameState.roster.has(id):
			var r: Dictionary = GameState.roster[id]
			var cdef: Dictionary = GameData.classes.get(r.class_id, {})
			row.add_child(UITheme.label("%s%s" % [r.name, "  (host)" if id == 1 else ""]))
			row.add_child(UITheme.label("%s, level %d" % [cdef.get("name", r.class_id), int(r.level)], UITheme.hex(cdef.get("color", "#ffffff"))))
		else:
			waiting += 1
			row.add_child(UITheme.label("Player %d" % id, UITheme.TEXT_DIM))
			row.add_child(UITheme.label("choosing a character...", UITheme.TEXT_DIM))
		_roster_box.add_child(row)
	if multiplayer.is_server():
		var all_ready := waiting == 0 and GameState.roster.has(1)
		_start.disabled = not all_ready
		_start.text = "Start run (%d player%s)" % [ids.size(), "" if ids.size() == 1 else "s"]
		if not all_ready:
			_status.text = "Waiting for every player to confirm a character."
		else:
			_status.text = ""
	elif GameState.roster.has(multiplayer.get_unique_id()):
		_status.text = "Waiting for the host to start..."


func _on_start() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager.start_run()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") and not _name_edit.has_focus():
		get_viewport().set_input_as_handled()
		NetworkManager.leave_to_menu()
