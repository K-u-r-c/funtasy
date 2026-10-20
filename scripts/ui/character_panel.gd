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
var _last_points := -1
var _points_label: Label
var _plus: Dictionary = {}  ## stat -> Button
var _mods_label: Label
var _mods_box: HFlowContainer
var _gold_label: Label


func _init() -> void:
	title_text = Loc.t("Character")
	menu_tab = "character"
	prompts = [["character", Loc.t("Close")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	subtitle.text = Loc.f("%s  -  Level %d %s", [player.display_name, player.level, player.class_def.name])
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
	# Class crest + level badge instead of a sentence.
	var crest := HBoxContainer.new()
	crest.alignment = BoxContainer.ALIGNMENT_CENTER
	crest.add_theme_constant_override("separation", 6)
	hv.add_child(crest)
	var ci := UITheme.icon("class_" + str(player.class_id), 24)
	ci.tooltip_text = Loc.t(str(player.class_def.name))
	crest.add_child(ci)
	var lv := UITheme.chip("ui_crown", "", Color.from_string(str(player.class_def.get("color", "#ffffff")), UITheme.TEXT), UITheme.GOLD_DIM)
	lv.tooltip_text = Loc.t("Level")
	crest.add_child(lv)
	_level_label = lv.get_meta("label")
	var xprow := HBoxContainer.new()
	xprow.add_theme_constant_override("separation", 4)
	xprow.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_child(xprow)
	xprow.add_child(UITheme.icon("hud_xp", 16))
	_xp_bar = StatBar.new(Color("8a5ce6"), Vector2(176, 8))
	_xp_bar.show_text = false
	_xp_bar.ticks = 10
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xprow.add_child(_xp_bar)
	_xp_label = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_xp_label)
	var gold := UITheme.chip("hud_gold", "", UITheme.GOLD, UITheme.GOLD_DIM)
	gold.tooltip_text = Loc.t("Gold")
	gold.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hv.add_child(gold)
	_gold_label = gold.get_meta("label")
	_offclass = UITheme.label("", UITheme.DANGER, UITheme.FONT_SMALL)
	_offclass.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offclass.custom_minimum_size = Vector2(196, 0)
	hv.add_child(_offclass)

	# Stats
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 4)
	body.add_child(stats_col)
	stats_col.add_child(UITheme.section(Loc.t("Attributes"), "nav_character"))
	# Free stat points: a points badge and one "+" button per primary stat, shown by its icon.
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 4)
	stats_col.add_child(prow)
	var pts := UITheme.chip("act_plus", "", UITheme.TEXT_DIM)
	pts.tooltip_text = Loc.t("Free stat points")
	pts.custom_minimum_size = Vector2(58, 0)
	prow.add_child(pts)
	_points_label = pts.get_meta("label")
	UIFx.pulse(pts)
	for st in Stats.PRIMARY:
		var b := Button.new()
		b.text = "+"
		b.icon = UITheme.icon_tex(UITheme.STAT_ICONS.get(st, ""))
		b.add_theme_constant_override("icon_max_width", 16)
		b.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		b.custom_minimum_size = Vector2(44, 22)
		b.tooltip_text = "+1 %s. %s" % [Loc.t(str(st).capitalize()), Loc.t(STAT_HELP.get(str(st).capitalize(), ""))]
		b.pressed.connect(func():
			player.request_spend_stat.rpc_id(1, st, 1)
			UIFx.flash(b))
		prow.add_child(b)
		_plus[st] = b
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 6
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 1)
	stats_col.add_child(_stats_grid)
	stats_col.add_child(UITheme.section(Loc.t("Run blessings and curses"), "hud_boss"))
	_mods_box = HFlowContainer.new()
	_mods_box.add_theme_constant_override("h_separation", 4)
	_mods_box.add_theme_constant_override("v_separation", 4)
	_mods_box.custom_minimum_size = Vector2(300, 0)
	stats_col.add_child(_mods_box)
	_mods_label = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	_mods_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mods_label.custom_minimum_size = Vector2(300, 0)
	_mods_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_col.add_child(_mods_label)

	# Skills
	var skills_col := VBoxContainer.new()
	skills_col.add_theme_constant_override("separation", 4)
	skills_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(skills_col)
	skills_col.add_child(UITheme.section(Loc.t("Skills"), "act_skills"))
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
	if player.stats.final != _last_stats or player.level != _last_level or player.stat_points != _last_points:
		_refresh()
	_xp_bar.set_values(float(player.xp) / maxf(1.0, Player.xp_to_next(player.level)))


func _refresh() -> void:
	_last_stats = player.stats.final.duplicate()
	_last_level = player.level
	_last_points = player.stat_points
	_points_label.text = "%d" % player.stat_points
	_points_label.add_theme_color_override("font_color", UITheme.GOOD if player.stat_points > 0 else UITheme.TEXT_DIM)
	for st in _plus:
		_plus[st].disabled = player.stat_points <= 0
	_gold_label.text = "%d" % player.gold
	_refresh_mods()
	var s: Dictionary = player.stats.final
	_level_label.text = "%d" % player.level
	_xp_label.text = "%d / %d" % [player.xp, Player.xp_to_next(player.level)]
	_offclass.text = Loc.f("Off-class weapon: -%d%% damage, slower cooldowns", [roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100)]) \
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
		var ic := UITheme.icon(str(UITheme.STAT_ICONS.get(ROW_STAT.get(r[0], ""), "")), 16)
		ic.tooltip_text = Loc.t(STAT_HELP.get(r[0], ""))
		_stats_grid.add_child(ic)
		var k := UITheme.label(Loc.t(r[0]), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		k.tooltip_text = Loc.t(STAT_HELP.get(r[0], ""))
		k.mouse_filter = Control.MOUSE_FILTER_PASS if not k.tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
		_stats_grid.add_child(k)
		var v := UITheme.label(r[1], UITheme.TEXT, UITheme.FONT_SMALL)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(40, 0)
		_stats_grid.add_child(v)
	for row in _skill_rows:
		row.refresh(player)


## Run modifiers as chips: the stat's icon and the summed value, green or red; the sources
## are in the tooltip. Nothing yet: a dim line.
func _refresh_mods() -> void:
	for c in _mods_box.get_children():
		c.queue_free()
	var sums := {}
	var order: Array = []
	var srcs := {}
	for m in player.run_mods:
		var k := str(m.stat)
		if not sums.has(k):
			order.append(k)
		sums[k] = float(sums.get(k, 0.0)) + float(m.value)
		srcs[k] = str(srcs.get(k, "")) + "%s%s %s\n" % ["+" if float(m.value) >= 0 else "", _fmt(k, float(m.value)), Loc.name(str(m.get("source", "")))]
	for k in order:
		var v := float(sums[k])
		var key := str(UITheme.STAT_ICONS.get(k.trim_suffix("_pct"), "sil_star"))
		var c := UITheme.chip(key, "%s%s" % ["+" if v >= 0 else "", _fmt(k, v)], UITheme.GOOD if v >= 0 else UITheme.DANGER,
				Color(UITheme.GOOD, 0.5) if v >= 0 else Color(UITheme.DANGER, 0.5))
		c.tooltip_text = "%s\n%s" % [_stat_name(k), str(srcs[k]).strip_edges()]
		_mods_box.add_child(c)
	_mods_label.text = run_mods_text(player.run_mods) if order.is_empty() else ""
	_mods_label.visible = order.is_empty()


## Stat icon of each row of the attribute grid.
const ROW_STAT := {"Health": "max_hp", "Mana": "mana", "Fury": "fury", "Mana regen": "resource_regen",
	"Strength": "strength", "Stamina": "stamina", "Agility": "agility", "Intellect": "intellect", "Armor": "armor",
	"Weapon DPS": "weapon_dps", "Crit chance": "crit_chance", "Crit damage": "crit_damage", "Haste": "haste",
	"Dodge": "dodge", "Leech": "leech", "Melee power": "power_melee", "Ranged power": "power_ranged",
	"Spell power": "power_spell", "Damage reduction": "strength_reduction", "Move speed": "move_speed"}


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
		var sk: Dictionary = GameData.skills.get(str(p.skills[slot]), {})
		_icon.texture = GameData.texture("icons." + str(sk.get("icon", "attack"))) if not sk.is_empty() else UITheme.icon_tex("slot_rune")
		_icon.modulate = Color.WHITE if not sk.is_empty() else Color(1, 1, 1, 0.25)
		_name.add_theme_color_override("font_color", UITheme.GOLD if not sk.is_empty() else UITheme.TEXT_DIM)
		if sk.is_empty():
			_name.text = "-"
		else:
			_name.text = Loc.t(str(sk.get("name", "?"))) if slot > 0 else Loc.f("%s  (primary)", [sk.get("name", "?")])
		_glyph.action = Player.SLOT_ACTIONS[slot]


## Run modifiers summed per stat, e.g. "Strength +2, Max health -10" ("none" when empty).
static func run_mods_text(mods: Array) -> String:
	if mods.is_empty():
		return Loc.t("None yet: tomes, the demonic tithe, contracts and pacts change you for the whole run.")
	var sums := {}
	var order: Array = []
	for m in mods:
		var k := str(m.stat)
		if not sums.has(k):
			order.append(k)
		sums[k] = float(sums.get(k, 0.0)) + float(m.value)
	var parts: Array = []
	for k in order:
		var v := float(sums[k])
		parts.append("%s %s%s" % [_stat_name(k), "+" if v >= 0 else "", _fmt(k, v)])
	return ", ".join(parts)


static func _stat_name(k: String) -> String:
	return {"max_hp": Loc.t("Max health"), "max_resource": Loc.t("Max mana"), "crit_chance": Loc.t("Crit chance"), "move_speed": Loc.t("Move speed"),
		"max_hp_pct": Loc.t("Max health")}.get(k, Loc.t(k.replace("_", " ").capitalize()))


static func _fmt(k: String, v: float) -> String:
	if k in ["crit_chance", "leech", "dodge", "haste", "max_hp_pct"] or k.ends_with("_pct"):
		return "%d%%" % roundi(v * 100.0)
	return "%d" % roundi(v)
