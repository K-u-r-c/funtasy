extends UIModal
## Skill Book (D1): every skill the hero has unlocked in the talent tree, and the six-slot bar
## (primary attack + 1-5). Pick a skill (click / Accept), then a slot to put it there; a skill
## already on the bar swaps places. Passives are listed but never slotted. The host validates
## the new loadout (request_loadout); it can only change out of combat.

const ICON := 40

var _list: GridContainer
var _bar: HBoxContainer
var _slot_buttons: Array = []
var _skill_buttons: Dictionary = {}  ## skill id -> Button
var _picked := ""
var _tooltip: SkillTooltip
var _hint: Label
var _last_sig := ""


func _init() -> void:
	title_text = Loc.t("Skill Book")
	menu_tab = "skillbook"
	prompts = [["ui_accept", Loc.t("Pick / place")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	subtitle.text = Loc.f("%s  -  pick a skill, then a slot", [player.class_def.name])
	_hint = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	content.add_child(_hint)
	content.add_child(UITheme.section(Loc.t("Skill bar"), "act_skills"))
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	content.add_child(_bar)
	for i in Player.SLOT_ACTIONS.size():
		var b := SlotButton.new()
		b.slot = i
		b.pressed.connect(_on_slot.bind(i))
		b.mouse_entered.connect(func(): _tip(b, str(player.skills[i]), i))
		b.focus_entered.connect(func(): if InputSettings.focus_nav_active(): _tip(b, str(player.skills[i]), i))
		b.mouse_exited.connect(func(): _tooltip.hide_for(b))
		b.focus_exited.connect(func(): _tooltip.hide_for(b))
		_bar.add_child(b)
		_slot_buttons.append(b)
	content.add_child(UITheme.section(Loc.t("Unlocked skills"), "nav_skillbook"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	content.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 3
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_list)
	_tooltip = SkillTooltip.new()
	add_child(_tooltip)
	_rebuild()
	if not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus.call_deferred()


func _process(_delta: float) -> void:
	var sig := "%s|%s" % [player.skills, player.talents]
	if sig != _last_sig:
		_rebuild()


func _rebuild() -> void:
	_last_sig = "%s|%s" % [player.skills, player.talents]
	for i in _slot_buttons.size():
		var b: SlotButton = _slot_buttons[i]
		b.skill = str(player.skills[i])
		b.picked = false
		b.queue_redraw()
	var unlocked := player.unlocked_skills()
	for id in _skill_buttons.keys():
		if not unlocked.has(id):
			_skill_buttons[id].queue_free()
			_skill_buttons.erase(id)
	for sid in unlocked:
		if _skill_buttons.has(sid):
			continue
		var sk: Dictionary = GameData.skills.get(sid, {})
		var b := Button.new()
		b.text = Loc.t(str(sk.get("name", sid))) + (Loc.t("  (passive)") if sk.get("passive", false) else "")
		b.icon = GameData.texture("icons." + str(sk.get("icon", "attack")))
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(220, ICON + 4)
		b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		b.toggle_mode = true
		b.pressed.connect(_on_skill.bind(sid))
		b.mouse_entered.connect(func(): _tip(b, sid, player.skills.find(sid)))
		b.focus_entered.connect(func(): if InputSettings.focus_nav_active(): _tip(b, sid, player.skills.find(sid)))
		b.mouse_exited.connect(func(): _tooltip.hide_for(b))
		b.focus_exited.connect(func(): _tooltip.hide_for(b))
		if sk.get("passive", false):
			b.modulate = Color(0.75, 0.8, 0.9)
		_list.add_child(b)
		_skill_buttons[sid] = b
	for sid in _skill_buttons:
		var on_bar: bool = player.skills.has(sid)
		_skill_buttons[sid].button_pressed = sid == _picked
		_skill_buttons[sid].add_theme_color_override("font_color", UITheme.GOLD if on_bar else UITheme.TEXT)
	_wire_focus()
	_hint.text = Loc.f("%d skills unlocked. Learn more in the Talents tab.", [unlocked.size()]) if _picked.is_empty() \
		else Loc.f("Now choose a slot for %s.", [GameData.skills.get(_picked, {}).get("name", _picked)])


func _wire_focus() -> void:
	# The bar leads down into the list; the list's top row leads back up to the bar.
	var items := _list.get_children().filter(func(c): return not c.is_queued_for_deletion())
	for i in _slot_buttons.size():
		var sb: Control = _slot_buttons[i]
		if not items.is_empty():
			sb.focus_neighbor_bottom = sb.get_path_to(items[mini(i * items.size() / _slot_buttons.size(), items.size() - 1)])
	for j in mini(_list.columns, items.size()):
		items[j].focus_neighbor_top = items[j].get_path_to(_slot_buttons[mini(j * 2, _slot_buttons.size() - 1)])


func _tip(anchor: Control, sid: String, slot: int) -> void:
	if GameData.skills.has(sid):
		_tooltip.show_skill(player, sid, anchor, slot)


func _on_skill(sid: String) -> void:
	if GameData.skills.get(sid, {}).get("passive", false):
		notice(Loc.t("Passive skills work as soon as they are learned."), UITheme.TEXT_DIM)
		_picked = ""
	else:
		_picked = "" if _picked == sid else sid
	_rebuild()
	if not _picked.is_empty():
		_slot_buttons[0].grab_focus()


func _on_slot(i: int) -> void:
	if _picked.is_empty():
		notice(Loc.t("Pick a skill below first."), UITheme.TEXT_DIM)
		return
	var lo: Array = player.skills.duplicate()
	var old := lo.find(_picked)
	if old >= 0:
		lo[old] = lo[i]
	lo[i] = _picked
	var err := player.loadout_error(lo)
	if not err.is_empty():
		notice(Loc.f(err, player.loadout_error_args))
		return
	if player.in_combat():
		notice(Loc.t("Can't change skills in combat"))
		return
	player.request_loadout.rpc_id(1, lo)
	AudioManager.play_sfx("equip", 0.0)
	_picked = ""
	_rebuild()


## One bar slot: icon, key glyph, "primary" mark.
class SlotButton:
	extends Button
	var slot := 0
	var skill := ""
	var picked := false
	var _icon: Texture2D
	var _empty: Texture2D
	var _primary: Texture2D
	var _glyph: InputGlyph

	func _init() -> void:
		custom_minimum_size = Vector2(56, 58)
		_empty = UITheme.icon_tex("slot_rune")
		_primary = UITheme.icon_tex("menu_play")
		tooltip_text = Loc.t("Primary attack") if slot == 0 else ""
		focus_mode = Control.FOCUS_ALL
		_glyph = InputGlyph.new("")
		_glyph.position = Vector2(2, 2)
		_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glyph)
		focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))

	func _ready() -> void:
		_glyph.action = Player.SLOT_ACTIONS[slot]

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size.round())
		var edge := UITheme.GOLD if has_focus() else UITheme.GOLD_DIM
		draw_style_box(UITheme.cached_glass(Color("0a0e17f2"), edge, 2 if has_focus() else 1, 0), r)
		var sk: Dictionary = GameData.skills.get(skill, {})
		if not sk.is_empty():
			# Held in a member: a texture freed right after _draw would render as a white quad.
			_icon = GameData.texture("icons." + str(sk.get("icon", "attack")))
			draw_texture_rect(_icon, Rect2((r.size.x - 32) / 2.0, 16, 32, 32), false)
		elif _empty:
			# An empty slot shows a dim rune stone instead of words (#29).
			draw_texture_rect(_empty, Rect2((r.size.x - 24) / 2.0, 20, 24, 24), false, Color(0.75, 0.82, 1.0, 0.35))
		if slot == 0 and _primary:
			# The primary attack's slot is marked with crossed swords in the corner.
			draw_texture_rect(_primary, Rect2(r.size.x - 18, 2, 16, 16), false)
