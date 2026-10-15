extends UIModal
## Character overlay (Character action, C): the hero at large scale with level and XP, every
## stat the Stats component computes (hover a stat for what it does) and the six skills as a
## compact list; hovering or focusing a skill opens its SkillTooltip (damage, cooldown, cost...).

const STAT_HELP := {
	"Health": "Maximum health. Raised by Stamina.",
	"Strength": "Melee damage and a little damage reduction.",
	"Stamina": "Maximum health.",
	"Agility": "Ranged damage and critical strike chance.",
	"Intellect": "Spell damage and mana / fury generation.",
	"Armor": "Reduces physical damage taken.",
	"Weapon DPS": "Base damage of your weapons; every attack and skill scales with it.",
	"Crit chance": "Chance for a hit to be critical.",
	"Crit damage": "Extra damage of critical hits.",
	"Haste": "Shorter cooldowns and cast times, faster attacks.",
	"Dodge": "Chance to avoid a hit completely.",
	"Leech": "Heals you for a share of the damage you deal.",
	"Melee power": "Weapon DPS + Strength bonus used by melee skills.",
	"Ranged power": "Weapon DPS + Agility bonus used by ranged skills.",
	"Spell power": "Weapon DPS + Intellect bonus used by spells.",
	"Damage reduction": "Reduction against every hit from Strength.",
	"Move speed": "Walking speed in pixels per second.",
}

var _stats_grid: GridContainer
var _skills_box: VBoxContainer
var _level_label: Label
var _xp_bar: StatBar
var _xp_label: Label
var _offclass: Label
var _skill_rows: Array = []
var _tooltip: SkillTooltip
var _tips_armed := false
var _last_stats: Dictionary = {}
var _last_level := -1


func _init() -> void:
	title_text = "Character"
	menu_tab = "character"
	prompts = [["character", "Close"], ["ui_cancel", "Close"]]


func _build() -> void:
	subtitle.text = "%s  -  Level %d %s" % [player.display_name, player.level, player.class_def.name]
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	# Hero
	var hero := PanelContainer.new()
	hero.theme_type_variation = &"GlassInset"
	body.add_child(hero)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hero.add_child(hv)
	var portrait := CharacterPortrait.new(false, 3)
	portrait.actor = player
	portrait.frame_color = Color.from_string(str(player.class_def.get("color", "#ffffff")), Color.WHITE).darkened(0.25)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hv.add_child(portrait)
	var name_l := UITheme.label(player.display_name, UITheme.GOLD, UITheme.FONT_BODY)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(name_l)
	_level_label = UITheme.label("", Color.from_string(str(player.class_def.get("color", "#ffffff")), UITheme.TEXT), UITheme.FONT_SMALL)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_level_label)
	_xp_bar = StatBar.new(Color("8a5ce6"), Vector2(196, 8))
	_xp_bar.show_text = false
	_xp_bar.ticks = 10
	hv.add_child(_xp_bar)
	_xp_label = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_xp_label)
	_offclass = UITheme.label("", UITheme.DANGER, UITheme.FONT_SMALL)
	_offclass.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offclass.custom_minimum_size = Vector2(196, 0)
	hv.add_child(_offclass)

	# Stats
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 4)
	body.add_child(stats_col)
	stats_col.add_child(UITheme.label("Attributes", UITheme.GOLD, UITheme.FONT_BODY))
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 1)
	stats_col.add_child(_stats_grid)

	# Skills
	var skills_col := VBoxContainer.new()
	skills_col.add_theme_constant_override("separation", 4)
	skills_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(skills_col)
	skills_col.add_child(UITheme.label("Skills", UITheme.GOLD, UITheme.FONT_BODY))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	skills_col.add_child(scroll)
	_skills_box = VBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 4)
	_skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_skills_box)
	for i in player.skills.size():
		var row := SkillRow.new()
		row.slot = i
		_skills_box.add_child(row)
		_skill_rows.append(row)
		row.mouse_entered.connect(_show_tip.bind(row))
		row.focus_entered.connect(_focus_tip.bind(row))
		row.mouse_exited.connect(_hide_tip.bind(row))
		row.focus_exited.connect(_hide_tip.bind(row))
	_tooltip = SkillTooltip.new()
	add_child(_tooltip)
	_refresh()
	if not _skill_rows.is_empty():
		_skill_rows[0].grab_focus.call_deferred()
	(func(): _tips_armed = true).call_deferred()


## Keyboard/gamepad focus opens the tooltip too, except for the focus the panel grabs on open.
func _focus_tip(row: SkillRow) -> void:
	if _tips_armed and InputSettings.focus_nav_active():
		_show_tip(row)


func _show_tip(row: SkillRow) -> void:
	_tooltip.show_for(player, row.slot, row)


## Leaving a row with the mouse falls back to the focused row's tooltip (gamepad/keyboard).
func _hide_tip(row: SkillRow) -> void:
	_tooltip.hide_for(row)
	var f := get_viewport().gui_get_focus_owner()
	if f is SkillRow and f != row and InputSettings.focus_nav_active():
		_show_tip(f)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if player.stats.final != _last_stats or player.level != _last_level:
		_refresh()
	_xp_bar.set_values(float(player.xp) / maxf(1.0, Player.xp_to_next(player.level)))


func _refresh() -> void:
	_last_stats = player.stats.final.duplicate()
	_last_level = player.level
	var s: Dictionary = player.stats.final
	_level_label.text = "Level %d %s" % [player.level, player.class_def.name]
	_xp_label.text = "XP %d / %d" % [player.xp, Player.xp_to_next(player.level)]
	_offclass.text = "Off-class weapon: -%d%% damage, slower cooldowns" % roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100) \
			if bool(s.get("offclass", false)) else ""
	for c in _stats_grid.get_children():
		c.queue_free()
	var res_name := str(player.class_def.resource).capitalize()
	var rows: Array = [
		["Health", "%d" % s.get("max_hp", 0)],
		[res_name, "%d" % s.get("max_resource", 0)],
		["Strength", "%d" % s.get("strength", 0)],
		["Stamina", "%d" % s.get("stamina", 0)],
		["Agility", "%d" % s.get("agility", 0)],
		["Intellect", "%d" % s.get("intellect", 0)],
		["Armor", "%d" % s.get("armor", 0)],
		["Weapon DPS", "%.1f" % s.get("weapon_dps", 0)],
		["Crit chance", "%d%%" % roundi(float(s.get("crit_chance", 0)) * 100)],
		["Crit damage", "+%d%%" % roundi(float(s.get("crit_damage", 0)) * 100)],
		["Haste", "%d%%" % roundi(float(s.get("haste", 0)) * 100)],
		["Dodge", "%d%%" % roundi(float(s.get("dodge", 0)) * 100)],
		["Leech", "%d%%" % roundi(float(s.get("leech", 0)) * 100)],
		["Melee power", "%d" % roundi(float(s.get("power_melee", 0)))],
		["Ranged power", "%d" % roundi(float(s.get("power_ranged", 0)))],
		["Spell power", "%d" % roundi(float(s.get("power_spell", 0)))],
		["Damage reduction", "%d%%" % roundi(float(s.get("strength_reduction", 0)) * 100)],
		["Move speed", "%d" % roundi(float(s.get("move_speed", 0)))],
	]
	if player.class_def.resource == "mana":
		rows.insert(2, ["Mana regen", "%.1f / s" % float(s.get("resource_regen", 0))])
	for r in rows:
		var k := UITheme.label(r[0], UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		k.tooltip_text = STAT_HELP.get(r[0], "")
		k.mouse_filter = Control.MOUSE_FILTER_PASS if not k.tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
		_stats_grid.add_child(k)
		var v := UITheme.label(r[1], UITheme.TEXT, UITheme.FONT_SMALL)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(44, 0)
		_stats_grid.add_child(v)
	for row in _skill_rows:
		row.refresh(player)


## One skill in the compact list: icon, name and key glyph (details in the tooltip).
class SkillRow:
	extends PanelContainer
	var slot := 0
	var _icon: TextureRect
	var _name: Label
	var _glyph: InputGlyph

	func _init() -> void:
		theme_type_variation = &"GlassInset"
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UITheme.glass(Color("05070bf2"), UITheme.GOLD_DIM, 1, 2))
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(frame)
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(32, 32)
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(_icon)
		_name = UITheme.label("", UITheme.GOLD, UITheme.FONT_BODY)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_name)
		_glyph = InputGlyph.new("")
		_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_glyph)
		focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))

	func refresh(p: Player) -> void:
		var sk := GameData.skill(p.skills[slot])
		_icon.texture = GameData.texture("icons." + str(sk.get("icon", "attack")))
		_name.text = str(sk.get("name", "?")) if slot > 0 else "%s  (primary)" % sk.get("name", "?")
		_glyph.action = Player.SLOT_ACTIONS[slot]
