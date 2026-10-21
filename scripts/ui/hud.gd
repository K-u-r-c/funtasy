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
const ShopPanel := preload("res://scripts/ui/shop_panel.gd")
const PactPanel := preload("res://scripts/ui/pact_panel.gd")
const ForgePanel := preload("res://scripts/ui/forge_panel.gd")
const ShrinePanel := preload("res://scripts/ui/shrine_panel.gd")
const ConfirmDialog := preload("res://scripts/ui/confirm_dialog.gd")
const CodexPanel := preload("res://scripts/ui/codex_panel.gd")
const LoreReader := preload("res://scripts/ui/lore_reader.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const ModVotePanel := preload("res://scripts/ui/mod_vote_panel.gd")
const BoonPanel := preload("res://scripts/ui/boon_panel.gd")
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
var _stat_hint: HBoxContainer
var _gold_label: Label
var _key_icon: TextureRect
var _slots: Array = []
var _slot_tip: SkillTooltip
var _quick: Dictionary = {}
var _status_box: HBoxContainer
var _party_box: VBoxContainer
var _boss_panel: GlassWindow
var _boss_bar: StatBar
var _boss_name: Label
var _burst_label: Label  ## "Burst it down" bar of a boss grab (#12)
var _burst_bar: StatBar
var _messages: VBoxContainer
var _prompt_row: HBoxContainer
var _prompt_more: HBoxContainer
var _prompt_count: Label
var _prompt: Label
var _floor_label: Label
var _mix_label: Label  ## #70: "Overrun from ..." on a mixed floor
var _goal_label: Label
var _portal_label: Label
var _center_panel: PanelContainer
var _center_label: Label
var _ghost_hint: HBoxContainer
var _overlay: Control
var _relocalize_pending := false
var _back_to: Dictionary = {}  ## {tab, state}: the menu panel a book was opened from (#38)
var _radial: Control
var _wipe: Control
var _dodge_slot: Control
var _torch_label: Label
var _torch_icon: TextureRect
var _res_icon: TextureRect
var _goal_icon: TextureRect
var _last_message := ""
var level_banner: LevelBanner  ## #48
var floor_banner: FloorBanner  ## #70: the arrival on a floor
var _screen_fx: ScreenFx  ## #81: the low-health vignette and the big-hit edge flash
var _bag_icon: TextureRect
var _floor_badges: VBoxContainer  ## #70 / #71: what makes this floor different, a badge per line
var _mod_label: Label  ## #71: the floor modifier's name
var _hunt_row: HBoxContainer  ## #71 Hunted: the countdown to the next hunter
var event_tracker: EventTracker  ## #72
var npc_talk: NpcTalk  ## #78
var _hunt_label: Label
var _boon_row: HFlowContainer  ## #73: small icons of the hero's boons beside the portrait
var _boon_sig := ""
var _boon_hint: Label  ## #73: "A boon awaits" while this hero hasn't chosen
var _last_message_at := 0
## Layout test hook: fills every HUD block with worst-case content (boss bar, banner, three
## teammates, many status effects) so tests can check nothing overlaps on any screen shape.
var preview_full := false


func _ready() -> void:
	add_to_group("hud")
	_build_layout()
	EventBus.local_player_spawned.connect(func(p): player = p; _portrait.actor = p; _rebuild_skill_icons())
	EventBus.hud_message.connect(show_message)
	EventBus.interact_prompt.connect(_set_prompt)
	EventBus.floor_started.connect(_on_floor_started)
	EventBus.floor_started.connect(_announce_floor)
	EventBus.bindings_changed.connect(_rebuild_skill_icons)
	EventBus.input_device_changed.connect(func(_g): _rebuild_skill_icons())
	EventBus.local_loadout_changed.connect(_rebuild_skill_icons)
	EventBus.local_inventory_changed.connect(_refresh_quick)
	EventBus.locale_changed.connect(_relocalize)
	level_banner = LevelBanner.new()
	add_child(level_banner)
	floor_banner = FloorBanner.new()
	add_child(floor_banner)
	EventBus.local_level_up.connect(level_banner.show_level)
	EventBus.skill_refused.connect(func(slot: int):
		if slot >= 0 and slot < _slots.size():
			_slots[slot].refuse())
	EventBus.local_picked_up.connect(_fly_to_hud)
	_screen_fx = ScreenFx.new()
	add_child(_screen_fx)
	# #78: the NPCs' speech bubbles (under the overlays opened later).
	var bubbles := Control.new()
	bubbles.name = "Bubbles"
	bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubbles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bubbles)
	npc_talk = NpcTalk.new()
	bubbles.add_child(npc_talk)
	# The banner and the bubbles never cover an open window.
	EventBus.ui_overlay_changed.connect(func(open: bool):
		bubbles.visible = not open
		if open:
			floor_banner.visible = false)


## A new language (#32): the HUD is built again so every label picks up the new texts. The
## options window lives inside an overlay, so that waits until the overlay closes.
func _relocalize() -> void:
	if has_overlay():
		_relocalize_pending = true
		return
	_relocalize_pending = false
	_root.free()
	_slots.clear()
	_quick.clear()
	_build_layout()
	if player and is_instance_valid(player):
		_portrait.actor = player
		_rebuild_skill_icons()
		_refresh_quick()
	var game := get_tree().get_first_node_in_group("game")
	if game:
		_on_floor_started(int(game.depth))


func _build_layout() -> void:
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
	_hp_bar = StatBar.new(Color("c23a3a"), Vector2(156, 16))
	_hp_bar.ticks = 4
	_hp_bar.flash_on_damage = true
	_hp_bar.set_ornate()
	bars.add_child(_bar_row("hud_health", _hp_bar))
	_res_bar = StatBar.new(Color("3b6fe0"), Vector2(156, 11))
	_res_icon = UITheme.icon("stat_mana", 16)
	bars.add_child(_bar_row("", _res_bar, _res_icon))
	_boon_row = HFlowContainer.new()
	_boon_row.add_theme_constant_override("h_separation", 2)
	_boon_row.add_theme_constant_override("v_separation", 2)
	_boon_row.custom_minimum_size = Vector2(0, 0)  # as wide as the portrait frame above it
	col.add_child(_boon_row)
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
	_floor_badges = VBoxContainer.new()
	_floor_badges.add_theme_constant_override("separation", 2)
	v.add_child(_floor_badges)
	# #72: the floor's events the hero has found.
	event_tracker = EventTracker.new()
	v.add_child(event_tracker)
	# Each tracker line leads with its icon (#29): the goal (skull / stairs), the portal, the torch.
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 4)
	v.add_child(grow)
	_goal_icon = UITheme.icon("hud_boss", 16)
	grow.add_child(_goal_icon)
	_goal_label = UITheme.label("", UITheme.TEXT, UITheme.FONT_SMALL)
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.custom_minimum_size = Vector2(156, 0)
	grow.add_child(_goal_label)
	_portal_label = UITheme.label("", Color(0.8, 0.6, 1.0), UITheme.FONT_SMALL)
	_portal_label.visible = false
	v.add_child(_portal_label)
	_boon_hint = UITheme.label(Loc.t("A boon awaits: step into the portal"), UITheme.GOLD, UITheme.FONT_SMALL)
	_boon_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boon_hint.custom_minimum_size = Vector2(156, 0)
	_boon_hint.visible = false
	v.add_child(_boon_hint)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	v.add_child(trow)
	_torch_icon = UITheme.icon("hud_torch", 16)
	trow.add_child(_torch_icon)
	_torch_label = UITheme.label("", Color(1.0, 0.7, 0.35), UITheme.FONT_SMALL)
	_torch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_torch_label.custom_minimum_size = Vector2(156, 0)
	trow.add_child(_torch_label)


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
	_burst_label = UITheme.label("", Color("b8ff7a"), UITheme.FONT_SMALL)
	_burst_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_burst_label.visible = false
	bv.add_child(_burst_label)
	_burst_bar = StatBar.new(Color("7fd94a"), Vector2(360, 8))
	_burst_bar.visible = false
	bv.add_child(_burst_bar)
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
	_ghost_hint = HBoxContainer.new()
	_ghost_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_ghost_hint.add_theme_constant_override("separation", 4)
	# #82: a ghost roams the floor; doors are the one thing it can still work.
	_ghost_hint.add_child(InputGlyph.new("interact"))
	_ghost_hint.add_child(UITheme.label(Loc.t("Roam the floor - only doors still answer you"), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	cv.add_child(_ghost_hint)

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
	# More than one thing at this spot (#35): "1/2" and the button that switches.
	_prompt_more = HBoxContainer.new()
	_prompt_more.add_theme_constant_override("separation", 4)
	_prompt_more.visible = false
	ph.add_child(_prompt_more)
	_prompt_more.add_child(UITheme.icon("act_reset", 16))
	_prompt_count = UITheme.label("", UITheme.GOLD, UITheme.FONT_SMALL)
	_prompt_more.add_child(_prompt_count)
	_prompt_more.add_child(InputGlyph.new("interact_next"))

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
	# #43: hovering a skill on the bar opens the same card as the Skill Book, with the numbers.
	_slot_tip = SkillTooltip.new()
	_root.add_child(_slot_tip)
	for i in 6:
		var s := SkillSlot.new()
		s.slot = i
		row.add_child(s)
		_slots.append(s)
		s.mouse_entered.connect(func():
			if player and is_instance_valid(player) and i < player.skills.size() and GameData.skills.has(str(player.skills[i])):
				_slot_tip.show_for(player, i, s))
		s.mouse_exited.connect(func(): _slot_tip.hide_for(s))
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
	xp_row.add_child(UITheme.icon("ui_crown", 16))
	_level_label = UITheme.label(Loc.t("Lv 1"), UITheme.GOLD, UITheme.FONT_SMALL)
	xp_row.add_child(_level_label)
	xp_row.add_child(UITheme.icon("hud_xp", 12))
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
	_talent_hint.add_child(UITheme.icon("nav_talents", 16))
	_talent_hint.add_child(UITheme.label(Loc.t("Talent point"), UITheme.GOOD, UITheme.FONT_SMALL))
	_talent_hint.tooltip_text = Loc.t("Talent points to spend")
	UIFx.pulse(_talent_hint)
	xp_row.add_child(_talent_hint)
	_stat_hint = HBoxContainer.new()
	_stat_hint.add_theme_constant_override("separation", 3)
	_stat_hint.visible = false
	_stat_hint.add_child(InputGlyph.new("character"))
	_stat_hint.add_child(UITheme.icon("act_plus", 16))
	_stat_hint.add_child(UITheme.label(Loc.t("Stat points"), UITheme.GOOD, UITheme.FONT_SMALL))
	_stat_hint.tooltip_text = Loc.t("Stat points to spend")
	UIFx.pulse(_stat_hint)
	xp_row.add_child(_stat_hint)
	_key_icon = TextureRect.new()
	_key_icon.texture = UITheme.icon_tex("hud_key")
	_key_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_key_icon.custom_minimum_size = Vector2(16, 16)
	_key_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_key_icon.tooltip_text = Loc.t("Gold Key: Archibald trades for it")
	_key_icon.visible = false
	xp_row.add_child(_key_icon)
	var coin := TextureRect.new()
	coin.texture = UITheme.icon_tex("hud_gold")
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.custom_minimum_size = Vector2(16, 16)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	xp_row.add_child(coin)
	_gold_label = UITheme.label("0", UITheme.GOLD, UITheme.FONT_SMALL)
	_gold_label.custom_minimum_size = Vector2(34, 0)
	xp_row.add_child(_gold_label)
	# #81: the backpack a picked-up item flies into.
	_bag_icon = UITheme.icon("nav_inventory", 16)
	_bag_icon.tooltip_text = Loc.t("Backpack")
	xp_row.add_child(_bag_icon)


## A bar led by its icon (heart, mana crystal or fury flame).
func _bar_row(icon_key: String, bar: StatBar, ic: TextureRect = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic if ic else UITheme.icon(icon_key, 16))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	return h


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(UITheme.EDGE, 0.8)
	d.custom_minimum_size = Vector2(1, 28)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _set_prompt(t: String, index: int = 0, count: int = 0) -> void:
	_prompt_more.visible = count > 1
	if count > 1:
		_prompt_count.text = "%d/%d" % [index + 1, count]
	if _prompt.text == t:
		return
	var show := not t.is_empty()
	if show:
		_prompt.text = t
		fit_label(_prompt)
	var tw := _prompt_row.create_tween()
	tw.tween_property(_prompt_row, "modulate:a", 1.0 if show else 0.0, 0.12)
	if not show:
		tw.tween_callback(func(): if _prompt_row.modulate.a <= 0.01: _prompt.text = "")


func _on_floor_started(d: int) -> void:
	var game := get_tree().get_first_node_in_group("game")
	var fname := str(game.floor_def.get("name", "")) if game else ""
	_floor_label.text = Loc.f("Floor %d%s", [d, "  " + Loc.t(fname) if not fname.is_empty() else ""])
	# #70: a mixed floor names its invader under the floor's name.
	var mix := str(game.floor_def.get("mix", "")) if game else ""
	var mod := str(game.floor_def.get("mod", "")) if game else ""
	for c in _floor_badges.get_children():
		c.queue_free()
	# A fresh label each floor (a label left out of the tree would leak at exit).
	_mix_label = UITheme.label("", UITheme.BADGE_INVASION.lightened(0.2), UITheme.FONT_SMALL)
	_mix_label.visible = not mix.is_empty()
	_hunt_row = null
	_mod_label = null
	var inv_line := _badge_line(Badge.new("mod_overrun", "", [[Loc.t("Part of the monsters here come from another biome.")]], UITheme.BADGE_INVASION, 22), _mix_label)
	inv_line.visible = not mix.is_empty()
	_floor_badges.add_child(inv_line)
	if not mix.is_empty():
		var ov := Loc.t(str(GameData.floor_types[mix].get("overrun", "")))
		_mix_label.text = ov.substr(0, 1).to_upper() + ov.substr(1)
		inv_line.get_child(0).title = _mix_label.text
		inv_line.get_child(0).tooltip_text = _mix_label.text
	if not mod.is_empty():
		var md := FloorMods.def(mod)
		_mod_label = UITheme.label(Loc.t(str(md.get("name", mod))), FloorMods.color(mod).lightened(0.25), UITheme.FONT_SMALL)
		_floor_badges.add_child(_badge_line(Badge.new(str(md.icon), Loc.t(str(md.name)), FloorMods.card_lines(mod), FloorMods.color(mod), 22), _mod_label))
		if mod == "hunted":
			_hunt_label = UITheme.label("", UITheme.WARN_SOFT, UITheme.FONT_SMALL)
			_hunt_row = _badge_line(UITheme.icon("mod_hunted", 16), _hunt_label)
			_floor_badges.add_child(_hunt_row)
	_floor_badges.visible = not mix.is_empty() or not mod.is_empty()
	_portal_label.text = ""
	_portal_label.visible = false


## #70: the arrival banner, once per floor (not when the HUD is rebuilt); #71 adds the modifier.
func _announce_floor(d: int) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game and floor_banner and d > 0:
		var extra: Array = []
		var mod := str(game.floor_def.get("mod", ""))
		if not mod.is_empty():
			var md := FloorMods.def(mod)
			extra.append([str(md.icon), "%s - %s" % [Loc.t(str(md.name)), Loc.t(str(md.danger))], FloorMods.color(mod)])
		floor_banner.show_floor(game.floor_def, d, extra)


## A tracker line: a badge (or icon) and its text.
func _badge_line(b: Control, l: Label) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(128, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	h.add_child(l)
	return h


## #71: the portal's vote (opened when this hero steps into the portal).
func open_mod_vote() -> void:
	open_overlay(ModVotePanel.new())


## #73: this hero's boon offer arrived: the cards open after a breath (or at once from the
## portal), unless another window is open (the tracker then says a boon awaits).
func offer_boons() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null or game.my_boon_offer.is_empty():
		return
	var near_portal: bool = game.portal != null and player and player.global_position.distance_to(game.portal.global_position) < 80.0
	if not near_portal:
		await get_tree().create_timer(float(GameData.bal("boons.choose_delay"))).timeout
	if has_overlay() or game.my_boon_offer.is_empty():
		return
	open_overlay(BoonPanel.new())


## #81: a picked-up item flies from where it lay to the backpack button, gold to the gold count.
func _fly_to_hud(world_pos: Vector2, kind: String, icon: Texture2D) -> void:
	if icon == null:
		return
	var vp := get_viewport()
	var from := vp.get_canvas_transform() * world_pos
	var target: Control = _gold_label if kind == "gold" else _dodge_slot
	var bag := _bag_target()
	if kind != "gold" and bag:
		target = bag
	var to := target.get_global_rect().get_center()
	var t := TextureRect.new()
	t.texture = icon
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.size = Vector2(20, 20)
	t.position = from - Vector2(10, 10)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(t)
	GameplayFx.note("fly_" + kind)
	var mid := (from + to) / 2.0 + Vector2(0, -60)
	var tw := t.create_tween()
	tw.tween_method(func(u: float):
		t.position = from.lerp(mid, u).lerp(mid.lerp(to, u), u) - Vector2(10, 10)
		t.scale = Vector2.ONE * (1.0 - 0.4 * u), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		t.queue_free()
		var p2 := target.create_tween()
		target.pivot_offset = target.size / 2.0
		p2.tween_property(target, "scale", Vector2(1.15, 1.15), 0.06)
		p2.tween_property(target, "scale", Vector2.ONE, 0.12))


## The backpack icon in the bottom bar.
func _bag_target() -> Control:
	return _bag_icon


## Screen centre of the portrait (where a chosen boon's card flies to).
func portrait_center() -> Vector2:
	return _portrait.get_global_rect().get_center() if _portrait else Vector2(60, 60)


## #73: the boon icons beside the portrait (rebuilt when they change), the "boon awaits" hint.
func _update_boons() -> void:
	var game := get_tree().get_first_node_in_group("game")
	_boon_hint.visible = game != null and not game.my_boon_offer.is_empty()
	var sig := str(player.boons)
	if sig == _boon_sig:
		return
	_boon_sig = sig
	for c in _boon_row.get_children():
		c.queue_free()
	var cap := int(GameData.bal("boons.hud_icons"))
	for i in player.boons.size():
		if i >= cap:
			_boon_row.add_child(UITheme.label("+%d" % (player.boons.size() - cap), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
			break
		var bid := str(player.boons[player.boons.size() - 1 - i])
		var bd := Boons.def(bid)
		_boon_row.add_child(Badge.new(str(bd.get("icon", "")).trim_prefix("icons."), Loc.t(str(bd.get("name", bid))), Boons.card_lines(bid), Boons.color(bid), 18))


func _rebuild_skill_icons() -> void:
	if player == null or not is_instance_valid(player):
		return
	for i in _slots.size():
		var s: SkillSlot = _slots[i]
		var sk: Dictionary = GameData.skills.get(str(player.skills[i]), {})  # {} = empty slot
		s.icon = GameData.texture("icons." + str(sk.icon)) if sk.has("icon") else null
		s.action = Player.SLOT_ACTIONS[i]
		s.tooltip = "" if not sk.is_empty() else Loc.t("Empty slot - learn skills in the Talents tab")
		s.cost = float(sk.get("cost", 0))
		s.queue_redraw()
	for k in _quick:
		_quick[k].action = "quick_" + k
	_dodge_slot.icon = GameData.texture("icons.dash")
	_dodge_slot.action = "dodge"
	_dodge_slot.tooltip = Loc.t("Dodge")
	_res_bar.fill_color = Color("e0701c") if player.class_def.resource == "fury" else Color("3b6fe0")
	_res_icon.texture = UITheme.icon_tex("stat_fury" if player.class_def.resource == "fury" else "stat_mana")
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
			q.tooltip = Loc.f("Quick slot %s (hold to choose)", [k.to_upper()])
		else:
			q.icon = GameData.texture(str(GameData.consumables[base_id].icon))
			q.count = player.inv.count_of(base_id)
			q.tooltip = Loc.t(str(GameData.consumables[base_id].name))
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
				"%s %d / %d" % [Loc.t(str(player.resource.kind).capitalize()), player.resource.value, player.resource.max_value])
		_xp_bar.set_values(float(player.xp) / maxf(1.0, Player.xp_to_next(player.level)))
		_level_label.text = Loc.f("Lv %d", [player.level])
		_talent_hint.visible = player.talent_points > 0
		_stat_hint.visible = player.stat_points > 0
		_talent_hint.get_child(2).text = str(player.talent_points)
		_stat_hint.get_child(2).text = str(player.stat_points)
		_gold_label.text = str(player.gold)
		var game := get_tree().get_first_node_in_group("game")
		_key_icon.visible = game != null and int(game.get("party_keys")) > 0
		_portrait.tint = Color.WHITE if player.life_state == Player.Life.ALIVE else Color(0.45, 0.45, 0.55)
		for i in _slots.size():
			var s: SkillSlot = _slots[i]
			var cd: Array = player.local_cd.get(i, [0.0, 1.0])
			s.set_cooldown(clampf(float(cd[0]) / maxf(float(cd[1]), 0.01), 0.0, 1.0) if player.local_cd.has(i) else 0.0,
					float(cd[0]) if player.local_cd.has(i) else 0.0)
			s.set_charge(player.charge_frac(i))
			var slot_sk: Dictionary = GameData.skills.get(str(player.skills[i]), {})
			var cost := player.stats.cost_for(slot_sk) if not slot_sk.is_empty() else 0.0
			s.unaffordable = cost > 0.0 and player.resource.value + 0.01 < cost
		for k in _quick:
			_quick[k].set_cooldown(clampf(player.item_cd_left / maxf(player.item_cd_total, 0.01), 0.0, 1.0), player.item_cd_left)
		_dodge_slot.set_cooldown(clampf(player._dodge_cd / float(GameData.bal("player.dodge_cooldown")), 0.0, 1.0), player._dodge_cd)
		_update_status()
		_update_center()
		_update_tracker()
		_update_boons()
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
	_update_hunt()
	var game := get_tree().get_first_node_in_group("game")
	var goal := ""
	_goal_icon.texture = UITheme.icon_tex("hud_stairs" if game and game.portal else "hud_boss")
	if game and game.portal:
		goal = Loc.t("The way down is open: step into the portal")
	else:
		var b := get_tree().get_first_node_in_group("boss")
		if b and is_instance_valid(b) and b.aggro:
			goal = Loc.f("Defeat %s", [b.display_name])
		else:
			goal = Loc.t("Find and defeat the floor boss")
	_goal_label.text = goal
	# #80: no torch line when the party plays without torches.
	_torch_icon.get_parent().visible = GameState.torches_on()
	var t: int = player.torch_sync
	_torch_icon.modulate = Color(1, 1, 1, 1.0 if t > 0 else 0.35)
	if t <= 0:
		_torch_label.text = Loc.t("No light - take a torch from a wall")
		_torch_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		return
	_torch_label.text = Loc.f("Torch %d:%02d", [t / 60, t % 60])
	var warn := int(Player.torch_warning())
	_torch_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25) if t <= warn else Color(1.0, 0.7, 0.35))


## #71 Hunted: "Hunter in 0:42"; amber, then red and pulsing in the last seconds.
func _update_hunt() -> void:
	if _hunt_row == null or not is_instance_valid(_hunt_row):
		return
	var game := get_tree().get_first_node_in_group("game")
	var at: float = game.hunt_next_at if game else -1.0
	_hunt_row.visible = at >= 0.0
	if at < 0.0:
		return
	var left := maxf(at - float(game.floor_time), 0.0)
	var warn := float(FloorMods.num(game.floor_def, "warn", 4.5))
	_hunt_label.text = Loc.f("Hunter in %d:%02d", [int(left) / 60, int(left) % 60]) if left > 0.0 else Loc.t("The hunter is here")
	var hot := left <= warn + 6.0
	_hunt_label.add_theme_color_override("font_color", UITheme.WARN if hot else UITheme.WARN_SOFT)
	_hunt_row.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 160.0)) if hot else 1.0


func _update_center() -> void:
	var t := Loc.t("You are a ghost until the next floor.") if preview_full else ""
	var ghost := preview_full
	match player.life_state:
		Player.Life.DOWNED:
			t = Loc.f("You are down! A teammate can revive you (%ds)", [ceili(player.downed_left)])
		Player.Life.GHOST:
			t = Loc.t("You are a ghost until the next floor.")
			ghost = true
	_center_label.text = t
	_ghost_hint.visible = ghost
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
		_boss_name.text = Loc.f("%s  - Phase 2", [b.display_name])
		_boss_bar.set_values(0.5, 0.0, "50%")
	elif b and is_instance_valid(b) and b.aggro:
		if not _boss_panel.visible:
			_boss_panel.visible = true
			UIFx.pop_in(_boss_panel, false)
		var phases: Array = b.def.get("phases", [])
		var title := ""
		if b.phase > 0 and b.phase < phases.size():
			title = "  - " + Loc.t(str(phases[b.phase].get("title", Loc.f("Phase %d", [(b.phase + 1)]))))
		_boss_name.text = Loc.name(b.display_name) + title
		_boss_bar.set_values(b.health.fraction(), 0.0, "%d%%" % ceili(b.health.fraction() * 100.0))
		var bb: Vector2 = b.get("burst_bar") if b.get("burst_bar") != null else Vector2.ZERO
		_burst_label.visible = bb.y > 0.0
		_burst_bar.visible = bb.y > 0.0
		if bb.y > 0.0:
			var held := ""
			for p2 in get_tree().get_nodes_in_group("players"):
				if not p2.held_by.is_empty():
					held = Loc.t("You are held") if p2 == player else Loc.f("%s is held", [p2.display_name])
			_burst_label.text = Loc.f("%s - Burst it down! %.1f s", [held, bb.y]) if not held.is_empty() else Loc.f("Burst it down! %.1f s", [bb.y])
			_burst_bar.set_values(bb.x, 0.0, "%d%%" % roundi(bb.x * 100.0))
	else:
		_boss_panel.visible = false


func set_portal_status(inside: int, alive: int) -> void:
	_portal_label.text = Loc.f("Portal: %d / %d players ready", [inside, alive])
	_portal_label.visible = true


## #44: a one-line HUD text wider than `ui.message_max_width` (and the screen) wraps instead of
## pushing its column off the screen.
func fit_label(l: Label) -> void:
	var vp := get_viewport().get_visible_rect().size
	var cap := minf(float(GameData.bal("ui.message_max_width", 380)), vp.x - 2.0 * float(GameData.bal("ui.safe_margin")) - 40.0)
	var font: Font = l.get_theme_font("font")
	var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x if font else 0.0
	if w > cap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = cap
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = 0.0


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
	fit_label(l)
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
	var t := UITheme.title(Loc.t("Your party has fallen"), UITheme.FONT_TITLE)
	t.add_theme_color_override("font_color", UITheme.DANGER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := UITheme.label(Loc.f("Reached floor %d. This game is over and its heroes are gone.\nReturning to the lobby...", [final_depth]), UITheme.TEXT, UITheme.FONT_BODY)
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
		"codex":
			return CodexPanel.new()
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


## The lore reader for a book the local player just read (D19). Opened over a game menu panel
## (the inventory, the codex), closing it goes back to that panel with its selection (#38).
func open_book(book_id: String, note: String) -> void:
	var back := {}
	if _overlay and is_instance_valid(_overlay) and not str(_overlay.get("menu_tab") if _overlay.get("menu_tab") != null else "").is_empty():
		back = {"tab": str(_overlay.menu_tab), "state": _overlay.save_state()}
	var r := LoreReader.new()
	r.book_id = book_id
	r.note = note
	r.title_text = Loc.t(str(GameData.lore_books.get(book_id, {}).get("title", "Book")))
	open_overlay(r)
	_back_to = back


## Merchants -> local player: open Archibald's shop or Malphas's bargains.
func open_merchant(kind: String) -> void:
	open_overlay(ShopPanel.new() if kind == "archibald" else PactPanel.new())


## #77: Rolf Hult's forge window.
func open_forge() -> void:
	open_overlay(ForgePanel.new())


## #72: the bargain shrine's choice cards.
func open_shrine(offers: Array) -> void:
	var sp := ShrinePanel.new()
	sp.offers = offers
	open_overlay(sp)


## Malphas asks the local player for the blood tithe (D13).
func ask_tithe(text: String) -> void:
	var d := ConfirmDialog.new()
	d.title_text = Loc.t("Malphas the Soul Broker")
	d.body_text = text
	d.yes_text = Loc.t("Pay the tithe")
	d.no_text = Loc.t("Turn away")
	d.title_icon = "stat_leech"
	d.yes_icon = "stat_leech"
	d.no_icon = "menu_back"
	var game := get_tree().get_first_node_in_group("game")
	if game:
		# The price as a stat chip: what the hero loses for the rest of the run.
		var price: Dictionary = Merchants.blood_price(int(game.layout.get("seed", 0)))
		d.chips = [[str(UITheme.STAT_ICONS.get(str(price.stat).trim_suffix("_pct"), "hud_health")), Merchants.mod_text(price), UITheme.DANGER]]
	d.on_answer = func(ok: bool):
		if ok and game:
			game.merchants.request_tithe.rpc_id(1, true)
	open_overlay(d)


func open_overlay(panel: Control) -> void:
	_back_to = {}
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
	var back := _back_to
	_back_to = {}
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if not back.is_empty():
		var panel := menu_panel(str(back.tab))
		panel.set("from_tab", true)
		panel.set("restore", back.state)
		open_overlay(panel)
		return
	if player and is_instance_valid(player):
		player.input_blocked = false
	EventBus.ui_overlay_changed.emit(false)
	if _relocalize_pending:
		_relocalize.call_deferred()


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
	var charge := -1.0  ## #54: how full the charge-up skill in this slot is while held, -1 = not charging
	var _glyph: InputGlyph
	var _sweep: ColorRect
	var _text: Control
	var _mat: ShaderMaterial
	var _ready_flash := 0.0
	var _refuse := 0.0  ## #81: the red flash of a refused press
	var _shake := 0.0
	var _empty_icon: Texture2D

	func _ready() -> void:
		# Loaded here: a texture first loaded inside _draw renders blank.
		_empty_icon = UITheme.icon_tex("slot_potion" if not quick_key.is_empty() else ("" if is_dodge else "slot_rune"))

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

	## #81: a refused press: the slot shakes and flashes red with a short sound.
	func refuse() -> void:
		_refuse = 1.0
		AudioManager.play_sfx("ui_error", 0.02)
		GameplayFx.note("slot_refused")
		# The shake moves the drawing, not the control (the bar's container lays it out).
		var tw := create_tween()
		tw.tween_method(func(v: float):
			_refuse = v
			_shake = sin(v * 40.0) * 3.0 * v
			queue_redraw(), 1.0, 0.0, 0.3)

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
		draw_set_transform(Vector2(roundf(_shake), 0))
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
		elif _empty_icon:
			# An empty quick slot shows a potion, an empty skill slot a rune stone (#29).
			draw_texture_rect(_empty_icon, Rect2(8, 8, 24, 24), false, Color(0.75, 0.82, 1.0, 0.3))
		if _refuse > 0.0:
			draw_rect(r.grow(-1), Color(1.0, 0.15, 0.1, 0.4 * _refuse))
			draw_rect(r, Color(1.0, 0.25, 0.2, _refuse), false, 1.5)
		if _ready_flash > 0.0:
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.35 * _ready_flash))
			var g := roundf((1.0 - _ready_flash) * 4.0)
			draw_rect(r.grow(g), Color(UITheme.GOLD, _ready_flash), false, 1.0)

	func set_charge(v: float) -> void:
		if absf(v - charge) > 0.005:
			charge = v
			_text.queue_redraw()

	func _draw_text() -> void:
		var f := UITheme.font()
		var fs := UITheme.FONT_SMALL
		if charge >= 0.0:
			# The charge rises through the icon in gold; a full charge pulses its frame.
			var h := roundf(32.0 * charge)
			var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 100.0) if charge >= 1.0 else 1.0
			_text.draw_rect(Rect2(4, 36 - h, 32, h), Color(1.0, 0.8, 0.34, 0.32 * pulse))
			_text.draw_line(Vector2(4, 36 - h), Vector2(36, 36 - h), Color(1.0, 0.86, 0.45, pulse), 1.0)
			_text.draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), Color(UITheme.GOLD, pulse), false, 1.0)
			if charge >= 1.0:
				_text.queue_redraw()
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
	var _icon: Texture2D
	var _icon_key := ""

	func _init(px: int = 22) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_effect(id: String, left: float, stacks: int) -> void:
		if id != _id or left > _max:
			_max = left
		_id = id
		_left = left
		_stacks = stacks
		var def: Dictionary = GameData.status_effects.get(id, {})
		var time_txt := Loc.t("Active") if left < 0.0 else "%ds" % ceili(left)
		tooltip_text = "%s%s - %s" % [Loc.t(str(def.get("name", id))), " x%d" % stacks if stacks > 1 else "", time_txt]
		queue_redraw()

	func _draw() -> void:
		var def: Dictionary = GameData.status_effects.get(_id, {})
		var col := Color.from_string(str(def.get("color", "#ffffff")), Color.WHITE)
		var debuff := bool(def.get("debuff", false))
		var r := Rect2(Vector2.ZERO, size.round())
		draw_style_box(UITheme.cached_glass(Color("070a10f0"), UITheme.DANGER if debuff else col.darkened(0.2), 1, 0), r)
		draw_rect(Rect2(2, 2, r.size.x - 4, r.size.y - 6), Color(col, 0.22))
		var f := UITheme.font()
		var icon_key := StatusChip.icon_key(_id)
		if not icon_key.is_empty():
			# Held in a member: a texture freed right after _draw would render as a white quad.
			if _icon_key != icon_key:
				_icon_key = icon_key
				_icon = GameData.texture(icon_key)
			draw_texture_rect(_icon, Rect2(2, 2, r.size.x - 4, r.size.y - 5), false)
		else:
			var name_: String = Loc.t(str(def.get("name", _id)))
			var t := name_.substr(0, 2)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			draw_string_outline(f, Vector2(roundf((r.size.x - tw) / 2.0), 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
			draw_string(f, Vector2(roundf((r.size.x - tw) / 2.0), 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, col)
		if _stacks > 1:
			draw_string_outline(f, Vector2(r.size.x - 7, 9), str(_stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color.BLACK)
			draw_string(f, Vector2(r.size.x - 7, 9), str(_stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, Color.WHITE)
		var frac := 1.0 if _left < 0.0 else clampf(_left / maxf(_max, 0.01), 0.0, 1.0)
		draw_rect(Rect2(2, r.size.y - 3, roundf((r.size.x - 4) * frac), 1), col)

	## The asset key of a status's icon (#37): its own "icon" in data, else status_icons.<id>.
	static func icon_key(id: String) -> String:
		var key := str(GameData.status_effects.get(id, {}).get("icon", "status_icons." + id))
		return key if GameData.asset_exists(key) else ""

	## The effects to show, most important first: debuffs, then buffs; the soonest to end first,
	## effects without an end last.
	static func ordered(shown: Array) -> Array:
		var out := shown.duplicate()
		var rank := func(s: Array) -> float:
			var debuff := bool(GameData.status_effects.get(str(s[0]), {}).get("debuff", false))
			var left := float(s[1])
			return (0.0 if debuff else 10000.0) + (5000.0 if left < 0.0 else left)
		out.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
		return out


## Compact teammate frame: mini portrait, name/level/state, HP + resource bars.
class PartyFrame:
	extends PanelContainer
	var p: Player
	var _portrait: CharacterPortrait
	var _name: Label
	var _hp: StatBar
	var _res: StatBar
	var _effects: HBoxContainer
	var _more: Label
	var _picked := false
	var _target_icon: TextureRect
	const MAX_EFFECTS := 7

	func _init() -> void:
		theme_type_variation = &"GlassHud"
		# A click picks this teammate as the friendly target (#39).
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(p):
				var me: Player = get_tree().get_first_node_in_group("hud").player
				if me:
					me.set_friendly_target(0 if me.friendly_peer == p.peer_id else p.peer_id)
					me._click_select = true
				accept_event())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		add_child(row)
		_portrait = CharacterPortrait.new(true, 1)
		row.add_child(_portrait)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(v)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 3)
		name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_row)
		_target_icon = UITheme.icon("ui_target", 12)
		_target_icon.visible = false
		name_row.add_child(_target_icon)
		_name = UITheme.label("", UITheme.TEXT, UITheme.FONT_SMALL)
		name_row.add_child(_name)
		_hp = StatBar.new(Color("3fbf5a"), Vector2(118, 7))
		_hp.show_text = false
		v.add_child(_hp)
		_res = StatBar.new(Color("3b6fe0"), Vector2(118, 4))
		_res.show_text = false
		v.add_child(_res)
		# The teammate's buffs and debuffs (#37), replicated with Status:shown.
		_effects = HBoxContainer.new()
		_effects.add_theme_constant_override("separation", 2)
		_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_effects)
		_more = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		_more.visible = false
		_effects.add_child(_more)

	func set_player(pl: Player) -> void:
		p = pl
		_portrait.actor = pl
		if not is_instance_valid(pl):
			return
		var state := ""
		match pl.life_state:
			Player.Life.DOWNED:
				state = Loc.f("  DOWN %d", [ceili(pl.downed_left)])
			Player.Life.GHOST:
				state = Loc.t("  GHOST")
		_name.text = Loc.f("%s  Lv%d%s", [pl.display_name, pl.level, state])
		# The picked friendly target (#39): a gold frame and a chevron before the name.
		var me: Player = get_tree().get_first_node_in_group("hud").player if is_inside_tree() else null
		var picked := me != null and me.friendly_peer == pl.peer_id
		if picked != _picked:
			_picked = picked
			if picked:
				add_theme_stylebox_override("panel", UITheme.glass(Color("0d111af0"), UITheme.GOLD, 2, 4, Color(UITheme.GOLD, 0.35), true))
			else:
				remove_theme_stylebox_override("panel")
		_target_icon.visible = picked
		# How to pick and clear (#40), with the current device's binding for Tab.
		var tip := Loc.f("Click: pick for ally spells. Click again or on empty ground: clear. %s: next ally, then none.", [InputSettings.prompt_for("target_ally")])
		if tooltip_text != tip:
			tooltip_text = tip
		_name.add_theme_color_override("font_color", UITheme.DANGER if not state.is_empty() else UITheme.TEXT)
		_portrait.tint = Color.WHITE if state.is_empty() else Color(0.45, 0.45, 0.55)
		_portrait.frame_color = Color.from_string(str(pl.class_def.get("color", "#ffffff")), Color.WHITE).darkened(0.2)
		_hp.set_values(pl.health.fraction(), pl.health.absorb / maxf(1.0, float(pl.health.max_hp)))
		_res.fill_color = Color("e0701c") if pl.resource.kind == "fury" else Color("3b6fe0")
		_res.set_values(pl.resource.fraction())
		set_effects(pl.status.shown)

	func set_effects(shown: Array) -> void:
		var list := StatusChip.ordered(shown)
		var n := mini(list.size(), MAX_EFFECTS)
		while _effects.get_child_count() - 1 < n:
			var c := StatusChip.new(16)
			_effects.add_child(c)
			_effects.move_child(_more, _effects.get_child_count() - 1)
		var i := 0
		for c in _effects.get_children():
			if c == _more:
				continue
			c.visible = i < n
			if c.visible:
				c.set_effect(str(list[i][0]), float(list[i][1]), int(list[i][2]))
			i += 1
		_more.visible = list.size() > MAX_EFFECTS
		_more.text = "+%d" % (list.size() - MAX_EFFECTS)
		_effects.visible = n > 0
