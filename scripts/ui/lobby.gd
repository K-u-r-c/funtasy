extends Control
## Pre-run lobby.
## The host chooses the game: a new game (everyone creates a fresh level 1 hero) or a saved game
## (it keeps its party size; every player takes one of its heroes). Heroes only exist inside
## their game, so a hero can't be brought into another party. The host also edits the game
## settings (generated from data/game_settings.json) and starts once the party is ready.

var _game_opt: OptionButton
var _delete_btn: Button
var _game_desc: Label
var _saved: Array = []  ## host: saved games listed in _game_opt (index - 1)

var _new_box: VBoxContainer
var _name_edit: LineEdit
var _class_buttons: Dictionary = {}
var _class_desc: Label
var _confirm: AnimButton
var _slots_box: VBoxContainer

var _roster_box: VBoxContainer
var _settings_box: GridContainer
var _start: AnimButton
var _status: Label
var _selected_class := "warrior"
var _setting_controls: Dictionary = {}

const LOBBY_MAX_WIDTH := 1100


func _ready() -> void:
	var bg := Control.new()
	bg.set_script(preload("res://scripts/ui/menu_background.gd"))
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 24)
	add_child(root)
	# Ultrawide: keep the lobby a centered column instead of stretching it across the screen.
	var fit := func():
		var side := maxi(24, int((get_viewport_rect().size.x - LOBBY_MAX_WIDTH) / 2.0))
		root.add_theme_constant_override("margin_left", side)
		root.add_theme_constant_override("margin_right", side)
	get_viewport().size_changed.connect(fit)
	fit.call()
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

	GameState.roster_changed.connect(_refresh)
	GameState.game_changed.connect(_refresh)
	GameState.settings_changed.connect(_refresh_settings)
	NetworkManager.peer_joined.connect(func(_id): _refresh())
	NetworkManager.peer_left.connect(func(_id): _refresh())

	var last: Dictionary = GameState.last_hero
	_name_edit.text = str(last.get("name", NetworkManager.local_name().substr(0, 16)))
	_select_class(str(last.get("class_id", "warrior")))
	_refresh_games()
	_refresh()
	_refresh_settings()
	(_game_opt if multiplayer.is_server() else _confirm).grab_focus()
	AudioManager.play_music("menu")


func _session_text() -> String:
	match NetworkManager.backend:
		NetworkManager.Backend.STEAM:
			return "Steam lobby" + (" (id %d)" % NetworkManager.lobby_id if multiplayer.is_server() else "")
		NetworkManager.Backend.ENET:
			return "LAN game on port %d" % NetworkManager.last_port
		NetworkManager.Backend.SOLO:
			return "Solo game"
	return ""


# =========================================================================================
# Left panel: game choice + hero choice
# =========================================================================================


func _build_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	v.add_child(UITheme.label("Game", UITheme.ACCENT, 18))
	var game_row := HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 6)
	v.add_child(game_row)
	_game_opt = OptionButton.new()
	_game_opt.custom_minimum_size = Vector2(330, 30)
	_game_opt.disabled = not multiplayer.is_server()
	_game_opt.item_selected.connect(_on_game_selected)
	_game_opt.fit_to_longest_item = false
	game_row.add_child(_game_opt)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.visible = multiplayer.is_server()
	_delete_btn.pressed.connect(_on_delete_game)
	game_row.add_child(_delete_btn)
	_game_desc = UITheme.label("", UITheme.TEXT_DIM, 13)
	_game_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_desc.custom_minimum_size = Vector2(410, 0)
	v.add_child(_game_desc)

	v.add_child(UITheme.label("Your hero", UITheme.ACCENT, 18))
	# New game: name + class
	_new_box = VBoxContainer.new()
	_new_box.add_theme_constant_override("separation", 8)
	v.add_child(_new_box)
	var name_row := HBoxContainer.new()
	name_row.add_child(UITheme.label("Name "))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(260, 30)
	name_row.add_child(_name_edit)
	_new_box.add_child(name_row)
	var classes := HBoxContainer.new()
	classes.add_theme_constant_override("separation", 6)
	_new_box.add_child(classes)
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
	_new_box.add_child(_class_desc)
	_confirm = AnimButton.new()
	_confirm.pressed.connect(_on_confirm)
	_new_box.add_child(_confirm)
	# Saved game: pick one of its heroes
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 6)
	v.add_child(_slots_box)
	return panel


func _refresh_games() -> void:
	_game_opt.clear()
	_game_opt.add_item("New game")
	_saved = SaveSystem.list_games() if multiplayer.is_server() else []
	for g in _saved:
		_game_opt.add_item(_game_title(g))
	if multiplayer.is_server():
		var idx := 0
		for i in _saved.size():
			if _saved[i].id == GameState.game_info.get("id", ""):
				idx = i + 1
		_game_opt.select(idx)


func _game_title(g: Dictionary) -> String:
	var names: Array = []
	for m in g.members:
		names.append(m.name)
	return "Floor %d - %d player%s - %s" % [int(g.get("depth", 1)), int(g.party_size), "" if int(g.party_size) == 1 else "s", ", ".join(names)]


func _on_game_selected(idx: int) -> void:
	if idx == 0:
		GameState.select_new_game()
	else:
		GameState.select_saved_game(str(_saved[idx - 1].id))
	_refresh()


func _on_delete_game() -> void:
	var idx := _game_opt.selected
	if idx <= 0:
		return
	SaveSystem.delete_game(str(_saved[idx - 1].id))
	GameState.select_new_game()
	_refresh_games()
	_status.text = "Saved game deleted."


func _select_class(cid: String) -> void:
	if not GameData.classes.has(cid):
		cid = "warrior"
	_selected_class = cid
	for k in _class_buttons:
		_class_buttons[k].set_pressed_no_signal(k == cid)
	var c: Dictionary = GameData.classes[cid]
	_class_desc.text = "%s  Resource: %s." % [c.description, str(c.resource).capitalize()]
	_confirm.text = "Play as a new %s (level 1)" % c.name


func _on_confirm() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm.is_empty():
		_status.text = "Enter a name first."
		return
	GameState.choose_new_character(nm, _selected_class)
	_status.text = "Hero confirmed."


func _refresh_slots() -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	if not GameState.is_continuing():
		return
	var taken := {}
	for id in GameState.roster:
		taken[int(GameState.roster[id].get("slot", -1))] = id
	var members: Array = GameState.game_info.get("members", [])
	for i in members.size():
		var m: Dictionary = members[i]
		var cdef: Dictionary = GameData.classes.get(m.class_id, {})
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(410, 32)
		var who := ""
		if taken.has(i):
			who = "  (you)" if taken[i] == multiplayer.get_unique_id() else "  (taken)"
		b.text = "%s - %s, level %d%s" % [m.name, cdef.get("name", m.class_id), int(m.level), who]
		b.add_theme_color_override("font_color", UITheme.hex(cdef.get("color", "#ffffff")))
		b.disabled = taken.has(i) and taken[i] != multiplayer.get_unique_id()
		b.pressed.connect(func(): GameState.claim_slot(i))
		_slots_box.add_child(b)


# =========================================================================================
# Right panel: party + settings
# =========================================================================================


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


func _refresh() -> void:
	var cont := GameState.is_continuing()
	_new_box.visible = not cont
	_delete_btn.disabled = not cont
	if cont:
		var info: Dictionary = GameState.game_info
		_game_desc.text = "Continue from floor %d. This game needs exactly %d player%s; each player takes one of its heroes." % [int(info.depth), int(info.party_size), "" if int(info.party_size) == 1 else "s"]
		if not multiplayer.is_server():
			_game_opt.clear()
			_game_opt.add_item("Saved game: floor %d, %d players" % [int(info.depth), int(info.party_size)])
	else:
		_game_desc.text = "Everyone starts a fresh level 1 hero. The game is saved by the host and ends for good if the whole party falls."
		if not multiplayer.is_server():
			_game_opt.clear()
			_game_opt.add_item("New game")
	_refresh_slots()
	_refresh_roster()


func _refresh_roster() -> void:
	for c in _roster_box.get_children():
		c.queue_free()
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
			row.add_child(UITheme.label("Player %d" % id, UITheme.TEXT_DIM))
			row.add_child(UITheme.label("choosing a hero...", UITheme.TEXT_DIM))
		_roster_box.add_child(row)
	if multiplayer.is_server():
		var problem := GameState.start_problem()
		_start.disabled = not problem.is_empty()
		_start.text = "Start run (%d player%s)" % [ids.size(), "" if ids.size() == 1 else "s"]
		_status.text = problem
	elif GameState.roster.has(multiplayer.get_unique_id()):
		_status.text = "Waiting for the host to start..."
	else:
		_status.text = "Pick your hero."


func _on_start() -> void:
	if multiplayer.is_server() and GameState.start_problem().is_empty():
		NetworkManager.start_run()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") and not _name_edit.has_focus():
		get_viewport().set_input_as_handled()
		NetworkManager.leave_to_menu()
