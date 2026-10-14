extends CanvasLayer
## In-game HUD: health/resource bars, skill bar (primary + skills 1-5 with cooldown sweeps),
## Q/E quick slots, XP bar, status effects, party frames, minimap, boss bar, messages and the
## interact prompt. Also hosts the overlays (inventory, talents, map, pause, radial menu);
## while one is open, gameplay input is blocked.

const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const TalentPanel := preload("res://scripts/ui/talent_panel.gd")
const MapPanel := preload("res://scripts/ui/map_panel.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const RadialMenu := preload("res://scripts/ui/radial_menu.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")

var player: Player
var _root: Control
var _hp_bar: ProgressBar
var _hp_text: Label
var _res_bar: ProgressBar
var _res_text: Label
var _xp_bar: ProgressBar
var _level_label: Label
var _slots: Array = []
var _quick: Dictionary = {}
var _status_box: HBoxContainer
var _party_box: VBoxContainer
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _messages: VBoxContainer
var _prompt: Label
var _floor_label: Label
var _center_label: Label
var _portal_label: Label
var _overlay: Control
var _radial: Control
var _wipe: Control
var _dodge_slot: Control


func _ready() -> void:
	add_to_group("hud")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_bottom()
	_build_top()
	EventBus.local_player_spawned.connect(func(p): player = p; _rebuild_skill_icons())
	EventBus.hud_message.connect(show_message)
	EventBus.interact_prompt.connect(func(t: String): _prompt.text = t)
	EventBus.floor_started.connect(func(d: int): _floor_label.text = "Floor %d" % d; _portal_label.text = "")
	EventBus.bindings_changed.connect(_rebuild_skill_icons)
	EventBus.input_device_changed.connect(func(_g): _rebuild_skill_icons())
	EventBus.local_inventory_changed.connect(_refresh_quick)


# =========================================================================================
# Layout
# =========================================================================================


func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -330
	bottom.offset_right = 330
	bottom.offset_top = -112
	bottom.offset_bottom = -4
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 3)
	_root.add_child(bottom)

	_prompt = UITheme.label("", Color(1, 0.95, 0.8), 14)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	bottom.add_child(_prompt)

	_status_box = HBoxContainer.new()
	_status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_box.custom_minimum_size = Vector2(0, 18)
	bottom.add_child(_status_box)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	bottom.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	_hp_bar = _make_bar(Color(0.75, 0.15, 0.15))
	left.add_child(_hp_bar)
	_hp_text = _bar_label(_hp_bar)
	_res_bar = _make_bar(Color(0.2, 0.4, 0.9))
	left.add_child(_res_bar)
	_res_text = _bar_label(_res_bar)

	for i in 6:
		var s := SkillSlot.new()
		s.slot = i
		row.add_child(s)
		_slots.append(s)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(6, 0)
	row.add_child(sep)
	for k in ["q", "e"]:
		var q := SkillSlot.new()
		q.quick_key = k
		row.add_child(q)
		_quick[k] = q
	_dodge_slot = SkillSlot.new()
	_dodge_slot.is_dodge = true
	row.add_child(_dodge_slot)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	bottom.add_child(xp_row)
	_level_label = UITheme.label("Lv 1", UITheme.ACCENT, 12)
	xp_row.add_child(_level_label)
	_xp_bar = _make_bar(Color(0.55, 0.35, 0.9))
	_xp_bar.custom_minimum_size = Vector2(0, 6)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_row.add_child(_xp_bar)


func _build_top() -> void:
	_party_box = VBoxContainer.new()
	_party_box.position = Vector2(10, 10)
	_party_box.add_theme_constant_override("separation", 4)
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_party_box)

	var mm := Minimap.new()
	mm.anchor_left = 1.0
	mm.anchor_right = 1.0
	mm.offset_left = -190
	mm.offset_right = -10
	mm.offset_top = 10
	mm.offset_bottom = 140
	_root.add_child(mm)

	_floor_label = UITheme.label("", UITheme.ACCENT, 14)
	_floor_label.anchor_left = 1.0
	_floor_label.anchor_right = 1.0
	_floor_label.offset_left = -190
	_floor_label.offset_top = 142
	_root.add_child(_floor_label)
	_portal_label = UITheme.label("", Color(0.8, 0.6, 1.0), 13)
	_portal_label.anchor_left = 1.0
	_portal_label.anchor_right = 1.0
	_portal_label.offset_left = -190
	_portal_label.offset_top = 160
	_root.add_child(_portal_label)

	_boss_panel = PanelContainer.new()
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -200
	_boss_panel.offset_right = 200
	_boss_panel.offset_top = 8
	_boss_panel.visible = false
	_root.add_child(_boss_panel)
	var bv := VBoxContainer.new()
	_boss_panel.add_child(bv)
	_boss_name = UITheme.label("", Color(1, 0.5, 0.4), 14)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_boss_name)
	_boss_bar = _make_bar(Color(0.7, 0.1, 0.1))
	_boss_bar.custom_minimum_size = Vector2(380, 12)
	bv.add_child(_boss_bar)

	_messages = VBoxContainer.new()
	_messages.anchor_left = 0.5
	_messages.anchor_right = 0.5
	_messages.offset_left = -300
	_messages.offset_right = 300
	_messages.offset_top = 80
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_messages)

	_center_label = UITheme.label("", Color(1, 0.5, 0.45), 22)
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center_label.offset_top = -120
	_center_label.offset_left = -300
	_center_label.offset_right = 300
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_center_label.add_theme_constant_override("outline_size", 6)
	_root.add_child(_center_label)


func _make_bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(150, 16)
	b.max_value = 1.0
	b.step = 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _bar_label(bar: ProgressBar) -> Label:
	var l := UITheme.label("", Color(1, 1, 1), 11)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	bar.add_child(l)
	return l


func _rebuild_skill_icons() -> void:
	if player == null or not is_instance_valid(player):
		return
	for i in _slots.size():
		var s: SkillSlot = _slots[i]
		var sk := GameData.skill(player.skills[i])
		s.icon = GameData.texture("icons." + str(sk.get("icon", "attack")))
		s.key_text = InputSettings.prompt_for(Player.SLOT_ACTIONS[i])
		s.tooltip = "%s\n%s" % [sk.name, sk.get("description", "")]
		s.cost = float(sk.get("cost", 0))
		s.queue_redraw()
	for k in _quick:
		_quick[k].key_text = InputSettings.prompt_for("quick_" + k)
	_dodge_slot.icon = GameData.texture("icons.dash")
	_dodge_slot.key_text = InputSettings.prompt_for("dodge")
	_res_bar.get_theme_stylebox("fill").bg_color = Color(0.85, 0.35, 0.1) if player.class_def.resource == "fury" else Color(0.2, 0.4, 0.9)
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
		else:
			q.icon = GameData.texture(str(GameData.consumables[base_id].icon))
			q.count = player.inv.count_of(base_id)
		q.queue_redraw()


# =========================================================================================
# Per frame
# =========================================================================================


func _process(_delta: float) -> void:
	if player and is_instance_valid(player):
		_hp_bar.value = player.health.fraction()
		_hp_text.text = "%d / %d%s" % [player.health.hp, player.health.max_hp, "  (+%d)" % player.health.absorb if player.health.absorb > 0.0 else ""]
		_res_bar.value = player.resource.fraction()
		_res_text.text = "%s %d / %d" % [str(player.resource.kind).capitalize(), player.resource.value, player.resource.max_value]
		_xp_bar.value = float(player.xp) / maxf(1.0, Player.xp_to_next(player.level))
		_level_label.text = "Lv %d%s" % [player.level, "  (+%d talent)" % player.talent_points if player.talent_points > 0 else ""]
		for i in _slots.size():
			var s: SkillSlot = _slots[i]
			var cd: Array = player.local_cd.get(i, [0.0, 1.0])
			s.cd_frac = clampf(float(cd[0]) / maxf(float(cd[1]), 0.01), 0.0, 1.0) if player.local_cd.has(i) else 0.0
			s.cd_left = float(cd[0]) if player.local_cd.has(i) else 0.0
			var cost := player.stats.cost_for(GameData.skill(player.skills[i]))
			s.unaffordable = cost > 0.0 and player.resource.value + 0.01 < cost
			s.queue_redraw()
		for k in _quick:
			_quick[k].cd_frac = clampf(player.item_cd_left / 8.0, 0.0, 1.0)
			_quick[k].cd_left = player.item_cd_left
			_quick[k].queue_redraw()
		_dodge_slot.cd_left = player._dodge_cd
		_dodge_slot.cd_frac = clampf(player._dodge_cd / float(GameData.bal("player.dodge_cooldown")), 0.0, 1.0)
		_dodge_slot.queue_redraw()
		_update_status()
		_update_center()
	_update_party()
	_update_boss()


func _update_status() -> void:
	var shown: Array = player.status.shown
	while _status_box.get_child_count() < shown.size():
		var l := UITheme.label("", Color.WHITE, 11)
		var sb := UITheme.box(Color(0, 0, 0, 0.6), Color(0.3, 0.3, 0.3), 1, 2, 3)
		l.add_theme_stylebox_override("normal", sb)
		_status_box.add_child(l)
	for i in _status_box.get_child_count():
		var l2: Label = _status_box.get_child(i)
		if i < shown.size():
			var s: Array = shown[i]
			var def: Dictionary = GameData.status_effects.get(s[0], {})
			l2.visible = true
			l2.text = "%s%s %ds" % [def.get("name", s[0]), " x%d" % s[2] if int(s[2]) > 1 else "", ceili(float(s[1]))]
			l2.add_theme_color_override("font_color", Color.from_string(str(def.get("color", "#ffffff")), Color.WHITE))
		else:
			l2.visible = false


func _update_center() -> void:
	match player.life_state:
		Player.Life.DOWNED:
			_center_label.text = "You are down! A teammate can revive you (%ds)" % ceili(player.downed_left)
		Player.Life.GHOST:
			_center_label.text = "You are a ghost until the next floor.\n[%s] to switch spectated player" % InputSettings.prompt_for("attack")
		_:
			_center_label.text = ""


func _update_party() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var players: Array = game.players_root.get_children()
	while _party_box.get_child_count() < players.size():
		_party_box.add_child(PartyFrame.new())
	for i in _party_box.get_child_count():
		var f: PartyFrame = _party_box.get_child(i)
		f.visible = i < players.size()
		if f.visible:
			f.p = players[i]
			f.queue_redraw()


func _update_boss() -> void:
	var b := get_tree().get_first_node_in_group("boss")
	if b and is_instance_valid(b) and b.aggro:
		_boss_panel.visible = true
		_boss_name.text = "%s%s" % [b.display_name, "  - Enraged!" if b.phase > 0 else ""]
		_boss_bar.value = b.health.fraction()
	else:
		_boss_panel.visible = false


func set_portal_status(inside: int, alive: int) -> void:
	_portal_label.text = "Portal: %d / %d players ready" % [inside, alive]


func show_message(text: String, color: Color = Color.WHITE) -> void:
	var l := UITheme.label(text, color, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	_messages.add_child(l)
	if _messages.get_child_count() > 4:
		_messages.get_child(0).queue_free()
	var t := l.create_tween()
	t.tween_interval(2.6)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)


func show_wipe(final_depth: int) -> void:
	close_overlay()
	_wipe = ColorRect.new()
	_wipe.color = Color(0.05, 0.0, 0.0, 0.0)
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_wipe)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.offset_left = -250
	v.offset_right = 250
	v.offset_top = -60
	_wipe.add_child(v)
	var t := UITheme.title("Your party has fallen", 34)
	t.add_theme_color_override("font_color", Color(0.9, 0.2, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var rules: Dictionary = GameData.bal("wipe", {})
	var lost: Array = []
	if rules.get("lose_equipment", true):
		lost.append("equipped items")
	if rules.get("lose_backpack", true):
		lost.append("backpack contents")
	var l := UITheme.label("Reached floor %d. Lost: %s. Levels and talents are kept.\nReturning to the lobby..." % [final_depth, ", ".join(lost) if not lost.is_empty() else "nothing"], UITheme.TEXT, 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	_wipe.create_tween().tween_property(_wipe, "color:a", 0.8, 1.5)


# =========================================================================================
# Overlays + radial menu
# =========================================================================================


func _unhandled_input(ev: InputEvent) -> void:
	if player == null or _wipe != null:
		return
	if _overlay != null:
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause") \
				or (ev.is_action_pressed("inventory") and _overlay is InventoryPanel) \
				or (ev.is_action_pressed("talents") and _overlay is TalentPanel) \
				or (ev.is_action_pressed("map") and _overlay is MapPanel):
			get_viewport().set_input_as_handled()
			close_overlay()
		return
	if ev.is_action_pressed("inventory"):
		open_overlay(InventoryPanel.new())
	elif ev.is_action_pressed("talents"):
		open_overlay(TalentPanel.new())
	elif ev.is_action_pressed("map"):
		open_overlay(MapPanel.new())
	elif ev.is_action_pressed("pause"):
		open_overlay(PauseMenu.new())
	else:
		return
	get_viewport().set_input_as_handled()


func open_overlay(panel: Control) -> void:
	close_overlay()
	close_radial()
	_overlay = panel
	panel.set("player", player)
	_root.add_child(panel)
	if panel.has_signal("closed"):
		panel.closed.connect(close_overlay)
	player.input_blocked = true
	EventBus.ui_overlay_changed.emit(true)


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


class SkillSlot:
	extends Control
	var slot := -1
	var quick_key := ""
	var is_dodge := false
	var icon: Texture2D
	var key_text := ""
	var tooltip := ""
	var cost := 0.0
	var cd_frac := 0.0
	var cd_left := 0.0
	var unaffordable := false
	var count := -1

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _get_tooltip(_at: Vector2) -> String:
		return tooltip

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.05, 0.04, 0.06, 0.85))
		if icon:
			draw_texture_rect(icon, r.grow(-4), false, Color(0.45, 0.45, 0.5) if unaffordable else Color.WHITE)
		if cd_frac > 0.0:
			var c := r.get_center()
			var pts := PackedVector2Array([c])
			var steps := 24
			for i in steps + 1:
				var a := -PI / 2.0 + TAU * (1.0 - cd_frac) + TAU * cd_frac * float(i) / steps
				pts.append(c + Vector2.from_angle(a) * 30.0)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
			if cd_left > 0.05:
				var f := ThemeDB.fallback_font
				var txt := "%.1f" % cd_left if cd_left < 10.0 else "%d" % int(cd_left)
				draw_string_outline(f, Vector2(4, 26), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 13, 3, Color.BLACK)
				draw_string(f, Vector2(4, 26), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 13, Color(1, 1, 1))
		draw_rect(r, Color(0.45, 0.35, 0.25), false, 1.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(2, 11), key_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2, 9, 3, Color.BLACK)
		draw_string(font, Vector2(2, 11), key_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2, 9, Color(1, 0.9, 0.6))
		if count >= 0:
			draw_string_outline(font, Vector2(2, size.y - 3), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 11, 3, Color.BLACK)
			draw_string(font, Vector2(2, size.y - 3), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 11, Color.WHITE)


class PartyFrame:
	extends Control
	var p: Player

	func _init() -> void:
		custom_minimum_size = Vector2(170, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if p == null or not is_instance_valid(p):
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var cc := Color.from_string(str(p.class_def.get("color", "#ffffff")), Color.WHITE)
		draw_rect(Rect2(0, 0, 3, size.y), cc)
		var f := ThemeDB.fallback_font
		var state := ""
		match p.life_state:
			Player.Life.DOWNED:
				state = "  DOWN %d" % ceili(p.downed_left)
			Player.Life.GHOST:
				state = "  GHOST"
		draw_string(f, Vector2(7, 12), "%s  Lv%d%s" % [p.display_name, p.level, state], HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 11, Color.WHITE)
		draw_rect(Rect2(7, 17, size.x - 12, 5), Color(0.15, 0.05, 0.05))
		draw_rect(Rect2(7, 17, (size.x - 12) * p.health.fraction(), 5), Color(0.3, 0.85, 0.35))
		draw_rect(Rect2(7, 23, size.x - 12, 3), Color(0.05, 0.05, 0.12))
		var rc := Color(0.85, 0.35, 0.1) if p.resource.kind == "fury" else Color(0.25, 0.45, 0.95)
		draw_rect(Rect2(7, 23, (size.x - 12) * p.resource.fraction(), 3), rc)
