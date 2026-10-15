extends CanvasLayer
## In-game HUD. Corner elements are pinned to the viewport edges inside a safe-zone margin
## (data: ui.safe_margin), so they follow the screen from 1:1 to 32:9:
##   top-left     player frame (live portrait, HP with damage trail + shield, resource),
##                status effects, party frames
##   top-right    minimap + objective tracker (floor, goal, portal, torch)
##   top-center   boss bar + message feed
##   bottom-center downed/ghost banner, interact prompt + action bar (primary + skills 1-5 with radial cooldown
##                sweeps, Q/E quick slots, dodge) and the XP bar
## Also hosts the overlays (inventory, talents, map, pause, radial menu); while one is open,
## gameplay input is blocked.

const CharacterPanel := preload("res://scripts/ui/character_panel.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const TalentPanel := preload("res://scripts/ui/talent_panel.gd")
const MapPanel := preload("res://scripts/ui/map_panel.gd")
const SkillBookPanel := preload("res://scripts/ui/skill_book_panel.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const RadialMenu := preload("res://scripts/ui/radial_menu.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")
const COOLDOWN_SHADER := preload("res://assets/shaders/cooldown_radial.gdshader")

var player: Player
var _root: Control
var _safe: MarginContainer
var _layer: Control
var _portrait: CharacterPortrait
var _name_label: Label
var _hp_bar: StatBar
var _res_bar: StatBar
var _xp_bar: StatBar
var _level_label: Label
var _talent_hint: HBoxContainer
var _slots: Array = []
var _quick: Dictionary = {}
var _status_box: HBoxContainer
var _party_box: VBoxContainer
var _boss_panel: GlassWindow
var _boss_bar: StatBar
var _boss_name: Label
var _messages: VBoxContainer
var _prompt_row: HBoxContainer
var _prompt: Label
var _floor_label: Label
var _goal_label: Label
var _portal_label: Label
var _center_panel: PanelContainer
var _center_label: Label
var _spectate_hint: HBoxContainer
var _overlay: Control
var _radial: Control
var _wipe: Control
var _dodge_slot: Control
var _torch_label: Label
var _last_message := ""
var _last_message_at := 0
## Layout test hook: fills every HUD block with worst-case content (boss bar, banner, three
## teammates, many status effects) so tests can check nothing overlaps on any screen shape.
var preview_full := false


func _ready() -> void:
	add_to_group("hud")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_safe = MarginContainer.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := int(GameData.bal("ui.safe_margin", 10))
	for side in ["left", "right", "top", "bottom"]:
		_safe.add_theme_constant_override("margin_" + side, m)
	_root.add_child(_safe)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_layer)
	_build_top_left()
	_build_top_right()
	_build_center()
	_build_bottom()
	EventBus.local_player_spawned.connect(func(p): player = p; _portrait.actor = p; _rebuild_skill_icons())
	EventBus.hud_message.connect(show_message)
	EventBus.interact_prompt.connect(_set_prompt)
	EventBus.floor_started.connect(_on_floor_started)
	EventBus.bindings_changed.connect(_rebuild_skill_icons)
	EventBus.input_device_changed.connect(func(_g): _rebuild_skill_icons())
	EventBus.local_loadout_changed.connect(_rebuild_skill_icons)
	EventBus.local_inventory_changed.connect(_refresh_quick)


# =========================================================================================
# Layout
# =========================================================================================


## Pins `c` to an edge/corner of the safe area; it keeps its minimum size and grows inwards.
func _pin(c: Control, anchor_x: float, anchor_y: float) -> void:
	c.anchor_left = anchor_x
	c.anchor_right = anchor_x
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.grow_horizontal = Control.GROW_DIRECTION_END if anchor_x == 0.0 else (Control.GROW_DIRECTION_BEGIN if anchor_x == 1.0 else Control.GROW_DIRECTION_BOTH)
	c.grow_vertical = Control.GROW_DIRECTION_END if anchor_y == 0.0 else (Control.GROW_DIRECTION_BEGIN if anchor_y == 1.0 else Control.GROW_DIRECTION_BOTH)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(c)


func _build_top_left() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_pin(col, 0.0, 0.0)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"GlassHud"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	frame.add_child(row)
	_portrait = CharacterPortrait.new(true, 2)
	row.add_child(_portrait)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bars)
	_name_label = UITheme.label("", UITheme.TEXT, UITheme.FONT_BODY)
	bars.add_child(_name_label)
	_hp_bar = StatBar.new(Color("c23a3a"), Vector2(168, 16))
	_hp_bar.ticks = 4
	_hp_bar.flash_on_damage = true
	bars.add_child(_hp_bar)
	_res_bar = StatBar.new(Color("3b6fe0"), Vector2(168, 11))
	bars.add_child(_res_bar)
	_status_box = HBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 3)
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status_box)
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 4)
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_party_box)


func _build_top_right() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassHud"
	_pin(panel, 1.0, 0.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var mm := Minimap.new()
	mm.custom_minimum_size = Vector2(176, 124)
	v.add_child(mm)
	_floor_label = UITheme.label("", UITheme.GOLD, UITheme.FONT_BODY)
	v.add_child(_floor_label)
	_goal_label = UITheme.label("", UITheme.TEXT, UITheme.FONT_SMALL)
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.custom_minimum_size = Vector2(176, 0)
	v.add_child(_goal_label)
	_portal_label = UITheme.label("", Color(0.8, 0.6, 1.0), UITheme.FONT_SMALL)
	_portal_label.visible = false
	v.add_child(_portal_label)
	_torch_label = UITheme.label("", Color(1.0, 0.7, 0.35), UITheme.FONT_SMALL)
	_torch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_torch_label.custom_minimum_size = Vector2(176, 0)
	v.add_child(_torch_label)


func _build_center() -> void:
	# Top center: boss bar with the message feed stacked under it (they never overlap).
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	_pin(top, 0.5, 0.0)
	_boss_panel = GlassWindow.new(true)
	_boss_panel.visible = false
	_boss_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_boss_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	_boss_panel.add_child(bv)
	_boss_name = UITheme.label("", Color("ff7a5c"), UITheme.FONT_BODY)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_boss_name)
	_boss_bar = StatBar.new(Color("a3202a"), Vector2(360, 12))
	_boss_bar.ticks = 10
	_boss_bar.flash_on_damage = true
	bv.add_child(_boss_bar)
	_messages = VBoxContainer.new()
	_messages.add_theme_constant_override("separation", 3)
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_messages)


func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	_pin(bottom, 0.5, 1.0)

	# Downed / ghost banner right above the action bar.
	_center_panel = PanelContainer.new()
	_center_panel.theme_type_variation = &"GlassHud"
	_center_panel.visible = false
	_center_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_center_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	_center_panel.add_child(cv)
	_center_label = UITheme.label("", Color("ff8a75"), UITheme.FONT_BODY)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_center_label)
	_spectate_hint = HBoxContainer.new()
	_spectate_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_spectate_hint.add_theme_constant_override("separation", 4)
	_spectate_hint.add_child(InputGlyph.new("attack"))
	_spectate_hint.add_child(UITheme.label("Switch spectated player", UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	cv.add_child(_spectate_hint)

	_prompt_row = HBoxContainer.new()
	_prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_row.add_theme_constant_override("separation", 5)
	_prompt_row.modulate.a = 0.0
	bottom.add_child(_prompt_row)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"GlassHud"
	_prompt_row.add_child(chip)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 5)
	chip.add_child(ph)
	ph.add_child(InputGlyph.new("interact"))
	_prompt = UITheme.label("", Color("fff2cc"), UITheme.FONT_BODY)
	ph.add_child(_prompt)

	var bar := PanelContainer.new()
	bar.theme_type_variation = &"GlassHud"
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(bar)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	bar.add_child(bv)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	bv.add_child(row)
	for i in 6:
		var s := SkillSlot.new()
		s.slot = i
		row.add_child(s)
		_slots.append(s)
		if i == 0:
			row.add_child(_divider())
	row.add_child(_divider())
	for k in ["q", "e"]:
		var q := SkillSlot.new()
		q.quick_key = k
		row.add_child(q)
		_quick[k] = q
	row.add_child(_divider())
	_dodge_slot = SkillSlot.new()
	_dodge_slot.is_dodge = true
	row.add_child(_dodge_slot)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	bv.add_child(xp_row)
	_level_label = UITheme.label("Lv 1", UITheme.GOLD, UITheme.FONT_SMALL)
	xp_row.add_child(_level_label)
	_xp_bar = StatBar.new(Color("8a5ce6"), Vector2(0, 6))
	_xp_bar.show_text = false
	_xp_bar.ticks = 10
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(_xp_bar)
	_talent_hint = HBoxContainer.new()
	_talent_hint.add_theme_constant_override("separation", 3)
	_talent_hint.visible = false
	_talent_hint.add_child(InputGlyph.new("talents"))
	_talent_hint.add_child(UITheme.label("Talent point", UITheme.GOOD, UITheme.FONT_SMALL))
	xp_row.add_child(_talent_hint)


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(UITheme.EDGE, 0.8)
	d.custom_minimum_size = Vector2(1, 28)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _set_prompt(t: String) -> void:
	if _prompt.text == t:
		return
	var show := not t.is_empty()
	if show:
		_prompt.text = t
	var tw := _prompt_row.create_tween()
	tw.tween_property(_prompt_row, "modulate:a", 1.0 if show else 0.0, 0.12)
	if not show:
		tw.tween_callback(func(): if _prompt_row.modulate.a <= 0.01: _prompt.text = "")


func _on_floor_started(d: int) -> void:
	var game := get_tree().get_first_node_in_group("game")
	var fname := str(game.floor_def.get("name", "")) if game else ""
	_floor_label.text = "Floor %d%s" % [d, "  " + fname if not fname.is_empty() else ""]
	_portal_label.text = ""
	_portal_label.visible = false


func _rebuild_skill_icons() -> void:
	if player == null or not is_instance_valid(player):
		return
	for i in _slots.size():
		var s: SkillSlot = _slots[i]
		var sk := GameData.skill(player.skills[i])
		s.icon = GameData.texture("icons." + str(sk.get("icon", "attack")))
		s.action = Player.SLOT_ACTIONS[i]
		s.tooltip = "%s\n%s" % [sk.name, sk.get("description", "")]
		s.cost = float(sk.get("cost", 0))
		s.queue_redraw()
	for k in _quick:
		_quick[k].action = "quick_" + k
	_dodge_slot.icon = GameData.texture("icons.dash")
	_dodge_slot.action = "dodge"
	_dodge_slot.tooltip = "Dodge"
	_res_bar.fill_color = Color("e0701c") if player.class_def.resource == "fury" else Color("3b6fe0")
	_name_label.text = player.display_name
	_refresh_quick()


func _refresh_quick() -> void:
	if player == null or not is_instance_valid(player):
		return
	for k in _quick:
		var q: SkillSlot = _quick[k]
		var base_id: String = player.inv.quick.get(k, "")
		if base_id.is_empty():
			q.icon = null
			q.count = -1
			q.tooltip = "Quick slot %s (hold to choose)" % k.to_upper()
		else:
			q.icon = GameData.texture(str(GameData.consumables[base_id].icon))
			q.count = player.inv.count_of(base_id)
			q.tooltip = str(GameData.consumables[base_id].name)
		q.queue_redraw()


# =========================================================================================
# Per frame
# =========================================================================================


func _process(_delta: float) -> void:
	if player and is_instance_valid(player):
		var h := player.health
		_hp_bar.set_values(h.fraction(), h.absorb / maxf(1.0, float(h.max_hp)),
				"%d / %d%s" % [h.hp, h.max_hp, "  +%d" % h.absorb if h.absorb > 0.0 else ""])
		_res_bar.set_values(player.resource.fraction(), 0.0,
				"%s %d / %d" % [str(player.resource.kind).capitalize(), player.resource.value, player.resource.max_value])
		_xp_bar.set_values(float(player.xp) / maxf(1.0, Player.xp_to_next(player.level)))
		_level_label.text = "Lv %d" % player.level
		_talent_hint.visible = player.talent_points > 0
		_portrait.tint = Color.WHITE if player.life_state == Player.Life.ALIVE else Color(0.45, 0.45, 0.55)
		for i in _slots.size():
			var s: SkillSlot = _slots[i]
			var cd: Array = player.local_cd.get(i, [0.0, 1.0])
			s.set_cooldown(clampf(float(cd[0]) / maxf(float(cd[1]), 0.01), 0.0, 1.0) if player.local_cd.has(i) else 0.0,
					float(cd[0]) if player.local_cd.has(i) else 0.0)
			var cost := player.stats.cost_for(GameData.skill(player.skills[i]))
			s.unaffordable = cost > 0.0 and player.resource.value + 0.01 < cost
		for k in _quick:
			_quick[k].set_cooldown(clampf(player.item_cd_left / maxf(player.item_cd_total, 0.01), 0.0, 1.0), player.item_cd_left)
		_dodge_slot.set_cooldown(clampf(player._dodge_cd / float(GameData.bal("player.dodge_cooldown")), 0.0, 1.0), player._dodge_cd)
		_update_status()
		_update_center()
		_update_tracker()
	_update_party()
	_update_boss()


func _update_status() -> void:
	var shown: Array = player.status.shown
	if preview_full:
		shown = []
		for id in GameData.status_effects.keys().slice(0, 10):
			shown.append([id, 9.0, 2])
	while _status_box.get_child_count() < shown.size():
		_status_box.add_child(StatusChip.new())
	for i in _status_box.get_child_count():
		var chip: StatusChip = _status_box.get_child(i)
		chip.visible = i < shown.size()
		if chip.visible:
			var s: Array = shown[i]
			chip.set_effect(str(s[0]), float(s[1]), int(s[2]))


func _update_tracker() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var goal := ""
	if game and game.portal:
		goal = "The way down is open: step into the portal"
	else:
		var b := get_tree().get_first_node_in_group("boss")
		if b and is_instance_valid(b) and b.aggro:
			goal = "Defeat %s" % b.display_name
		else:
			goal = "Find and defeat the floor boss"
	_goal_label.text = goal
	var t: int = player.torch_sync
	if t <= 0:
		_torch_label.text = "No light - take a torch from a wall"
		_torch_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		return
	_torch_label.text = "Torch %d:%02d" % [t / 60, t % 60]
	var warn := int(GameData.bal("lighting.carried_torch_warning"))
	_torch_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25) if t <= warn else Color(1.0, 0.7, 0.35))


func _update_center() -> void:
	var t := "You are a ghost until the next floor." if preview_full else ""
	var ghost := preview_full
	match player.life_state:
		Player.Life.DOWNED:
			t = "You are down! A teammate can revive you (%ds)" % ceili(player.downed_left)
		Player.Life.GHOST:
			t = "You are a ghost until the next floor."
			ghost = true
	_center_label.text = t
	_spectate_hint.visible = ghost
	_center_panel.visible = not t.is_empty()


func _update_party() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var others: Array = []
	for p in game.players_root.get_children():
		if p != player:
			others.append(p)
	if preview_full:
		others = [player, player, player]
	while _party_box.get_child_count() < others.size():
		_party_box.add_child(PartyFrame.new())
	for i in _party_box.get_child_count():
		var f: PartyFrame = _party_box.get_child(i)
		f.visible = i < others.size()
		if f.visible:
			f.set_player(others[i])


func _update_boss() -> void:
	var b := get_tree().get_first_node_in_group("boss")
	if preview_full and b:
		_boss_panel.visible = true
		_boss_name.text = "%s  - Enraged!" % b.display_name
		_boss_bar.set_values(0.5, 0.0, "50%")
	elif b and is_instance_valid(b) and b.aggro:
		if not _boss_panel.visible:
			_boss_panel.visible = true
			UIFx.pop_in(_boss_panel, false)
		_boss_name.text = "%s%s" % [b.display_name, "  - Enraged!" if b.phase > 0 else ""]
		_boss_bar.set_values(b.health.fraction(), 0.0, "%d%%" % ceili(b.health.fraction() * 100.0))
	else:
		_boss_panel.visible = false


func set_portal_status(inside: int, alive: int) -> void:
	_portal_label.text = "Portal: %d / %d players ready" % [inside, alive]
	_portal_label.visible = true


func show_message(text: String, color: Color = Color.WHITE) -> void:
	if _overlay and is_instance_valid(_overlay) and _overlay.has_method("notice"):
		_overlay.notice(text, color)
	# The same message again within a moment (e.g. holding a skill without resource) is dropped.
	var now := Time.get_ticks_msec()
	if text == _last_message and now - _last_message_at < 1500:
		return
	_last_message = text
	_last_message_at = now
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"GlassHud"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, color, UITheme.FONT_BODY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	_messages.add_child(chip)
	if _messages.get_child_count() > 4:
		_messages.get_child(0).queue_free()
	chip.modulate.a = 0.0
	var t := chip.create_tween()
	t.tween_property(chip, "modulate:a", 1.0, 0.15)
	t.tween_interval(2.6)
	t.tween_property(chip, "modulate:a", 0.0, 0.8)
	t.tween_callback(chip.queue_free)


func show_wipe(final_depth: int) -> void:
	close_overlay()
	_wipe = ColorRect.new()
	_wipe.color = Color(0.05, 0.0, 0.0, 0.0)
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_wipe)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe.add_child(center)
	var win := GlassWindow.new(true)
	center.add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	var t := UITheme.title("Your party has fallen", UITheme.FONT_TITLE)
	t.add_theme_color_override("font_color", UITheme.DANGER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := UITheme.label("Reached floor %d. This game is over and its heroes are gone.\nReturning to the lobby..." % final_depth, UITheme.TEXT, UITheme.FONT_BODY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	v.add_child(l)
	_wipe.create_tween().tween_property(_wipe, "color:a", 0.8, 1.5)
	UIFx.pop_in(win, false)


# =========================================================================================
# Overlays + radial menu
# =========================================================================================


## Game menu panels by tab id (= the input action that opens them).
func menu_panel(id: String) -> Control:
	match id:
		"character":
			return CharacterPanel.new()
		"inventory":
			return InventoryPanel.new()
		"talents":
			return TalentPanel.new()
		"map":
			return MapPanel.new()
		"skillbook":
			return SkillBookPanel.new()
	return null


func _unhandled_input(ev: InputEvent) -> void:
	if player == null or _wipe != null:
		return
	# D-pad buttons double as menu navigation, so inside an overlay they never switch/close it.
	var nav := ev.is_action("ui_left") or ev.is_action("ui_right") or ev.is_action("ui_up") or ev.is_action("ui_down")
	if _overlay != null:
		var tab: String = str(_overlay.get("menu_tab")) if _overlay.get("menu_tab") != null else ""
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause") \
				or (not tab.is_empty() and not nav and ev.is_action_pressed(tab)):
			get_viewport().set_input_as_handled()
			AudioManager.play_sfx("ui_back", 0.03)
			close_overlay()
			return
		if tab.is_empty():
			return
		var next := ""
		if ev.is_action_pressed("ui_tab_next"):
			next = _overlay.neighbor_tab(1)
		elif ev.is_action_pressed("ui_tab_prev"):
			next = _overlay.neighbor_tab(-1)
		elif not nav:
			for t in UIModal.MENU_TABS:
				if ev.is_action_pressed(t[0]):
					next = t[0]
		if not next.is_empty():
			get_viewport().set_input_as_handled()
			_switch_tab(next)
		return
	var panel: Control = null
	for t in UIModal.MENU_TABS:
		if ev.is_action_pressed(t[0]):
			panel = menu_panel(t[0])
	if panel == null and ev.is_action_pressed("pause"):
		panel = PauseMenu.new()
	if panel == null:
		return
	open_overlay(panel)
	get_viewport().set_input_as_handled()


func open_overlay(panel: Control) -> void:
	close_overlay()
	close_radial()
	_overlay = panel
	panel.set("player", player)
	_root.add_child(panel)
	if panel.has_signal("closed"):
		panel.closed.connect(close_overlay)
	if panel.has_signal("switch_tab"):
		panel.switch_tab.connect(_switch_tab)
	player.input_blocked = true
	EventBus.ui_overlay_changed.emit(true)


func _switch_tab(id: String) -> void:
	var panel := menu_panel(id)
	panel.set("from_tab", true)
	open_overlay(panel)


func close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if player and is_instance_valid(player):
		player.input_blocked = false
	EventBus.ui_overlay_changed.emit(false)


func has_overlay() -> bool:
	return _overlay != null


func open_radial(slot: String) -> void:
	if _overlay != null or player == null:
		return
	close_radial()
	_radial = RadialMenu.new()
	_radial.player = player
	_radial.slot = slot
	_root.add_child(_radial)


## Closes the radial menu and returns the chosen consumable id ("" = none).
func close_radial() -> String:
	if _radial == null or not is_instance_valid(_radial):
		_radial = null
		return ""
	var picked: String = _radial.selected_id()
	_radial.queue_free()
	_radial = null
	return picked


# =========================================================================================
# Widgets
# =========================================================================================


## Action bar slot: icon, live key glyph, radial cooldown sweep (shader), cooldown seconds,
## "ready" flash when the cooldown ends, stack count for quick slots.
class SkillSlot:
	extends Control
	var slot := -1
	var quick_key := ""
	var is_dodge := false
	var icon: Texture2D
	var action := "":
		set(v):
			action = v
			if _glyph:
				_glyph.action = v
	var tooltip := ""
	var cost := 0.0
	var cd_frac := 0.0
	var cd_left := 0.0
	var unaffordable := false:
		set(v):
			if v != unaffordable:
				unaffordable = v
				queue_redraw()
	var count := -1
	var _glyph: InputGlyph
	var _sweep: ColorRect
	var _text: Control
	var _mat: ShaderMaterial
	var _ready_flash := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_PASS
		_sweep = ColorRect.new()
		_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sweep.position = Vector2(4, 4)
		_sweep.size = Vector2(32, 32)
		_mat = ShaderMaterial.new()
		_mat.shader = COOLDOWN_SHADER
		_mat.set_shader_parameter("rect_size", Vector2(32, 32))
		_sweep.material = _mat
		add_child(_sweep)
		_text = Control.new()
		_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_text.draw.connect(_draw_text)
		add_child(_text)
		_glyph = InputGlyph.new(action)
		_glyph.position = Vector2(-3, -6)
		add_child(_glyph)

	func _get_tooltip(_at: Vector2) -> String:
		return tooltip

	func set_cooldown(frac: float, left: float) -> void:
		if cd_frac > 0.0 and frac <= 0.0:
			_ready_flash = 1.0
			var tw := create_tween()
			tw.tween_method(func(v: float): _ready_flash = v; queue_redraw(), 1.0, 0.0, 0.35)
		if frac != cd_frac or absf(left - cd_left) > 0.05:
			cd_frac = frac
			cd_left = left
			_mat.set_shader_parameter("progress", frac)
			queue_redraw()
			_text.queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size.round())
		_text.queue_redraw()
		var ready := cd_frac <= 0.0 and not unaffordable and icon != null
		draw_style_box(UITheme.cached_glass(Color("070a10f0"), UITheme.GOLD_DIM if ready else UITheme.EDGE, 1, 0), r)
		var f := UITheme.font()
		if icon:
			var tint := Color(0.42, 0.46, 0.62) if unaffordable else Color.WHITE
			draw_texture_rect(icon, Rect2(5, 6, 32, 32), false, Color(0, 0, 0, 0.4))
			draw_texture_rect(icon, Rect2(4, 4, 32, 32), false, tint)
			if unaffordable:
				draw_rect(Rect2(4, 34, 32, 2), Color("3b6fe0"))
		elif not quick_key.is_empty():
			var t := "empty"
			var tw2 := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			draw_string(f, Vector2(roundf((r.size.x - tw2) / 2.0), 25), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, Color(UITheme.TEXT_DIM, 0.5))
		if _ready_flash > 0.0:
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.35 * _ready_flash))
			var g := roundf((1.0 - _ready_flash) * 4.0)
			draw_rect(r.grow(g), Color(UITheme.GOLD, _ready_flash), false, 1.0)

	func _draw_text() -> void:
		var f := UITheme.font()
		var fs := UITheme.FONT_SMALL
		if cd_frac > 0.0 and cd_left > 0.05:
			var txt := "%.1f" % cd_left if cd_left < 10.0 else "%d" % int(cd_left)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY).x
			var p := Vector2(roundf((size.x - tw) / 2.0), 26)
			_text.draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY, 4, Color.BLACK)
			_text.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY, Color.WHITE)
		if count >= 0:
			var c := str(count)
			var cw := f.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cp := Vector2(size.x - cw - 3, size.y - 3)
			_text.draw_string_outline(f, cp, c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
			_text.draw_string(f, cp, c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if count > 0 else UITheme.DANGER)


## Status effect chip: colored frame, initials, stacks, a draining timer line.
class StatusChip:
	extends Control
	var _id := ""
	var _left := 0.0
	var _max := 0.0
	var _stacks := 1

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_effect(id: String, left: float, stacks: int) -> void:
		if id != _id or left > _max:
			_max = left
		_id = id
		_left = left
		_stacks = stacks
		var def: Dictionary = GameData.status_effects.get(id, {})
		var time_txt := "active" if left < 0.0 else "%ds" % ceili(left)
		tooltip_text = "%s%s - %s" % [def.get("name", id), " x%d" % stacks if stacks > 1 else "", time_txt]
		queue_redraw()

	func _draw() -> void:
		var def: Dictionary = GameData.status_effects.get(_id, {})
		var col := Color.from_string(str(def.get("color", "#ffffff")), Color.WHITE)
		var debuff := bool(def.get("debuff", false))
		var r := Rect2(Vector2.ZERO, size.round())
		draw_style_box(UITheme.cached_glass(Color("070a10f0"), UITheme.DANGER if debuff else col.darkened(0.2), 1, 0), r)
		draw_rect(Rect2(2, 2, r.size.x - 4, r.size.y - 6), Color(col, 0.22))
		var f := UITheme.font()
		var icon_key := "status_icons." + _id
		if GameData.asset_exists(icon_key):
			draw_texture_rect(GameData.texture(icon_key), Rect2(2, 2, r.size.x - 4, r.size.y - 5), false)
		else:
			var name_: String = str(def.get("name", _id))
			var t := name_.substr(0, 2)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			draw_string_outline(f, Vector2(roundf((r.size.x - tw) / 2.0), 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
			draw_string(f, Vector2(roundf((r.size.x - tw) / 2.0), 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, col)
		if _stacks > 1:
			draw_string_outline(f, Vector2(r.size.x - 7, 9), str(_stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
			draw_string(f, Vector2(r.size.x - 7, 9), str(_stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, Color.WHITE)
		var frac := 1.0 if _left < 0.0 else clampf(_left / maxf(_max, 0.01), 0.0, 1.0)
		draw_rect(Rect2(2, r.size.y - 3, roundf((r.size.x - 4) * frac), 1), col)


## Compact teammate frame: mini portrait, name/level/state, HP + resource bars.
class PartyFrame:
	extends PanelContainer
	var p: Player
	var _portrait: CharacterPortrait
	var _name: Label
	var _hp: StatBar
	var _res: StatBar

	func _init() -> void:
		theme_type_variation = &"GlassHud"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		add_child(row)
		_portrait = CharacterPortrait.new(true, 1)
		row.add_child(_portrait)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(v)
		_name = UITheme.label("", UITheme.TEXT, UITheme.FONT_SMALL)
		v.add_child(_name)
		_hp = StatBar.new(Color("3fbf5a"), Vector2(118, 7))
		_hp.show_text = false
		v.add_child(_hp)
		_res = StatBar.new(Color("3b6fe0"), Vector2(118, 4))
		_res.show_text = false
		v.add_child(_res)

	func set_player(pl: Player) -> void:
		p = pl
		_portrait.actor = pl
		if not is_instance_valid(pl):
			return
		var state := ""
		match pl.life_state:
			Player.Life.DOWNED:
				state = "  DOWN %d" % ceili(pl.downed_left)
			Player.Life.GHOST:
				state = "  GHOST"
		_name.text = "%s  Lv%d%s" % [pl.display_name, pl.level, state]
		_name.add_theme_color_override("font_color", UITheme.DANGER if not state.is_empty() else UITheme.TEXT)
		_portrait.tint = Color.WHITE if state.is_empty() else Color(0.45, 0.45, 0.55)
		_portrait.frame_color = Color.from_string(str(pl.class_def.get("color", "#ffffff")), Color.WHITE).darkened(0.2)
		_hp.set_values(pl.health.fraction(), pl.health.absorb / maxf(1.0, float(pl.health.max_hp)))
		_res.fill_color = Color("e0701c") if pl.resource.kind == "fury" else Color("3b6fe0")
		_res.set_values(pl.resource.fraction())
