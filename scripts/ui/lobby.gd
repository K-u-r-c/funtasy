extends Control
## Pre-run lobby.
## Three numbered steps, left to right: (1) choose the hero (name, body, class - or a hero of the
## saved game), (2) confirm it under the big live preview, (3) the host starts the run.
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
var _gender_buttons: Dictionary = {}
var _class_desc: Label
var _preview: HeroPreview
var _gear_toggle: Button
var _confirm: AnimButton
var _hero_summary: Label
var _ready_label: Label
var _slots_box: VBoxContainer
var _hero_title: Label

var _roster_box: VBoxContainer
var _settings_box: GridContainer
var _start: AnimButton
var _status: Label
var _selected_class := "warrior"
var _selected_gender := ""
var _setting_controls: Dictionary = {}

const LOBBY_MAX_WIDTH := 1180


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
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_character_panel())
	body.add_child(_build_preview_panel())
	body.add_child(_build_party_panel())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	_start = AnimButton.new()
	_start.text = "Start run"
	_start.visible = multiplayer.is_server()
	_primary(_start)
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
	_select_gender(str(last.get("gender", "")))
	_select_class(str(last.get("class_id", "warrior")))
	_refresh_games()
	_refresh()
	_refresh_settings()
	_wire_focus()
	(_gender_buttons[_selected_gender] if not GameState.is_continuing() else _confirm).grab_focus()
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
# Step 1: the hero (left) and step 2: preview + confirm (centre)
# =========================================================================================


func _step_title(n: int, text: String) -> Label:
	return UITheme.label("%d  %s" % [n, text], UITheme.ACCENT, 18)


## Gold-framed primary action (Confirm hero, Start run).
func _primary(b: Button) -> void:
	for st in ["normal", "hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, UITheme.glass(Color("2a2412f0") if st == "pressed" else Color("1c1a10f0"), UITheme.GOLD, 2, 6))
	b.add_theme_color_override("font_color", UITheme.GOLD)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


func _build_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_hero_title = _step_title(1, "Choose your hero")
	v.add_child(_hero_title)
	# New game: name, body, class
	_new_box = VBoxContainer.new()
	_new_box.add_theme_constant_override("separation", 6)
	v.add_child(_new_box)
	_new_box.add_child(UITheme.label("Name", UITheme.TEXT_DIM, 13))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(280, 30)
	_name_edit.text_changed.connect(func(_t): _update_preview())
	_new_box.add_child(_name_edit)
	_new_box.add_child(UITheme.label("Body", UITheme.TEXT_DIM, 13))
	var genders := HBoxContainer.new()
	genders.add_theme_constant_override("separation", 6)
	_new_box.add_child(genders)
	for g in CharacterSprite.genders():
		var gb := Button.new()
		gb.text = str(GameData.assets.characters.genders[g].get("name", g.capitalize()))
		gb.toggle_mode = true
		gb.custom_minimum_size = Vector2(137, 30)
		gb.pressed.connect(_select_gender.bind(g))
		genders.add_child(gb)
		_gender_buttons[g] = gb
	_new_box.add_child(UITheme.label("Class", UITheme.TEXT_DIM, 13))
	var classes := GridContainer.new()
	classes.columns = 2
	classes.add_theme_constant_override("h_separation", 6)
	classes.add_theme_constant_override("v_separation", 6)
	_new_box.add_child(classes)
	for cid in ["warrior", "ranger", "mage", "priest"]:
		if not GameData.classes.has(cid):
			continue
		var b := Button.new()
		b.text = GameData.classes[cid].name
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(137, 30)
		b.add_theme_color_override("font_color", UITheme.hex(GameData.classes[cid].color))
		b.pressed.connect(_select_class.bind(cid))
		classes.add_child(b)
		_class_buttons[cid] = b
	_class_desc = UITheme.label("", UITheme.TEXT_DIM, 13)
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.custom_minimum_size = Vector2(280, 0)
	_new_box.add_child(_class_desc)
	# Saved game: pick one of its heroes
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 6)
	v.add_child(_slots_box)
	return panel


func _build_preview_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(_step_title(2, "Confirm"))
	_preview = HeroPreview.new()
	_preview.custom_minimum_size = Vector2(230, 170)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_preview)
	_hero_summary = UITheme.label("", UITheme.TEXT, 14)
	_hero_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hero_summary)
	var turn := HBoxContainer.new()
	turn.add_theme_constant_override("separation", 6)
	v.add_child(turn)
	for step in [-1, 1]:
		var tb := Button.new()
		tb.text = "<" if step < 0 else ">"
		tb.tooltip_text = "Turn left" if step < 0 else "Turn right"
		tb.custom_minimum_size = Vector2(36, 28)
		tb.pressed.connect(func(): _preview.rotate_by(step))
		turn.add_child(tb)
		if step < 0:
			_gear_toggle = Button.new()
			_gear_toggle.toggle_mode = true
			_gear_toggle.button_pressed = true
			_gear_toggle.text = "Class gear"
			_gear_toggle.tooltip_text = "Heroes start without equipment; this shows the class in typical gear."
			_gear_toggle.custom_minimum_size = Vector2(0, 28)
			_gear_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_gear_toggle.toggled.connect(func(_on): _update_preview())
			turn.add_child(_gear_toggle)
	_confirm = AnimButton.new()
	_confirm.custom_minimum_size = Vector2(230, 38)
	_confirm.text = "Confirm hero"
	_primary(_confirm)
	_confirm.pressed.connect(_on_confirm)
	v.add_child(_confirm)
	_ready_label = UITheme.label("", UITheme.GOOD, 13)
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ready_label.custom_minimum_size = Vector2(230, 0)
	v.add_child(_ready_label)
	return panel


## Gamepad / keyboard order follows the steps: hero choices -> preview controls -> Confirm ->
## Start run (host) or Leave.
func _wire_focus() -> void:
	var cls: Array = _class_buttons.values()
	var gens: Array = _gender_buttons.values()
	_name_edit.focus_neighbor_bottom = gens[0].get_path()
	for g in gens:
		g.focus_neighbor_top = _name_edit.get_path()
		g.focus_neighbor_bottom = cls[0].get_path()
	for i in cls.size():
		cls[i].focus_neighbor_top = (gens[mini(i % 2, gens.size() - 1)] if i < 2 else cls[i - 2]).get_path()
		if i >= cls.size() - 2:
			cls[i].focus_neighbor_bottom = _gear_toggle.get_path()
	_gear_toggle.focus_neighbor_top = cls[cls.size() - 2].get_path()
	_gear_toggle.focus_neighbor_bottom = _confirm.get_path()
	_confirm.focus_neighbor_top = _gear_toggle.get_path()
	_confirm.focus_neighbor_bottom = (_start if _start.visible else _start.get_parent().get_child(1)).get_path()


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
	_update_preview()


func _select_gender(g: String) -> void:
	_selected_gender = CharacterSprite.valid_gender(g)
	for k in _gender_buttons:
		_gender_buttons[k].set_pressed_no_signal(k == _selected_gender)
	_update_preview()


func _update_preview() -> void:
	if _preview == null:
		return
	var gender := _selected_gender
	var cid := _selected_class
	var nm := _name_edit.text.strip_edges()
	var level := 1
	if GameState.is_continuing():
		# Saved game: show this player's hero (or the first one).
		var members: Array = GameState.game_info.get("members", [])
		var mine: Dictionary = GameState.roster.get(multiplayer.get_unique_id(), {})
		var slot := maxi(int(mine.get("slot", 0)), 0)
		if slot < members.size():
			gender = str(members[slot].get("gender", ""))
			cid = str(members[slot].class_id)
			nm = str(members[slot].name)
			level = int(members[slot].level)
	_preview.set_look(gender, class_look(cid) if _gear_toggle.button_pressed else {})
	var gname := str(GameData.assets.characters.get("genders", {}).get(CharacterSprite.valid_gender(gender), {}).get("name", ""))
	_hero_summary.text = "%s - %s %s, level %d" % [nm if not nm.is_empty() else "?", gname, GameData.classes.get(cid, {}).get("name", cid), level]


## The class's typical gear (data/classes/<id>.json "preview_gear", item base ids) in the
## Inventory.appearance format: layer -> [appearance, tint].
static func class_look(cid: String) -> Dictionary:
	var out := {}
	for base_id in GameData.classes.get(cid, {}).get("preview_gear", []):
		var base: Dictionary = GameData.item_bases.get(base_id, {})
		if str(base.get("appearance", "")).is_empty():
			continue
		var layer := str(base.slot)
		if layer == "weapon":
			layer = "offhand" if out.has("weapon") else "weapon"
		elif layer == "off_hand" or base.get("kind") == "offhand":
			layer = "offhand"
		out[layer] = [str(base.appearance), str(base.get("tint", "#ffffff"))]
	return out


func _on_confirm() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm.is_empty():
		_status.text = "Enter a name first."
		return
	GameState.choose_new_character(nm, _selected_class, _selected_gender)


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
		b.custom_minimum_size = Vector2(280, 32)
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	# The game choice (host) sits with the party: it is about the whole run, not one hero.
	v.add_child(UITheme.label("Game", UITheme.ACCENT, 18))
	var game_row := HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 6)
	v.add_child(game_row)
	_game_opt = OptionButton.new()
	_game_opt.custom_minimum_size = Vector2(0, 30)
	_game_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_game_desc.custom_minimum_size = Vector2(240, 0)
	v.add_child(_game_desc)
	v.add_child(UITheme.label("Party", UITheme.ACCENT, 18))
	_roster_box = VBoxContainer.new()
	_roster_box.custom_minimum_size = Vector2(0, 60)
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
	_confirm.visible = not cont
	_hero_title.text = "1  Take a hero of this game" if cont else "1  Choose your hero"
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
	_update_preview()
	var mine: Dictionary = GameState.roster.get(multiplayer.get_unique_id(), {})
	if mine.is_empty():
		_ready_label.text = "" if cont else "Not ready yet: confirm your hero."
		_ready_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_confirm.text = "Confirm hero"
	else:
		_ready_label.text = "Ready as %s." % mine.name
		_ready_label.add_theme_color_override("font_color", UITheme.GOOD)
		_confirm.text = "Update hero"


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
			var gname := str(GameData.assets.characters.get("genders", {}).get(str(r.get("gender", "")), {}).get("name", ""))
			row.add_child(UITheme.label("%s%s, level %d" % [gname + " " if not gname.is_empty() else "", cdef.get("name", r.class_id), int(r.level)], UITheme.hex(cdef.get("color", "#ffffff"))))
		else:
			row.add_child(UITheme.label("Player %d" % id, UITheme.TEXT_DIM))
			row.add_child(UITheme.label("choosing a hero...", UITheme.TEXT_DIM))
		_roster_box.add_child(row)
	if multiplayer.is_server():
		var problem := GameState.start_problem()
		_start.disabled = not problem.is_empty()
		_start.text = "3  Start run (%d player%s)" % [ids.size(), "" if ids.size() == 1 else "s"]
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
