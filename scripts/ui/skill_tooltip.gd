class_name SkillTooltip
extends PanelContainer
## Obsidian Glass card describing one skill (SkillInfo rows). Shown next to an anchor control
## (hovered or focused skill row) and kept inside the viewport.

const WIDTH := 300.0
const GAP := 8.0

var player: Player
var slot := -1
var _anchor: Control
var _icon: TextureRect
var _name: Label
var _glyph: InputGlyph
var _tag: Label
var _desc: Label
var _grid: GridContainer
var _foot: Label
var _sig := ""


func _init() -> void:
	top_level = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	add_theme_stylebox_override("panel", UITheme.glass(Color("080b12f5"), UITheme.GOLD_DIM, 1, 10))
	custom_minimum_size = Vector2(WIDTH, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.glass(Color("05070bf2"), UITheme.GOLD_DIM, 1, 2))
	top.add_child(frame)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(32, 32)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	_name = UITheme.label("", UITheme.GOLD, UITheme.FONT_BODY)
	tv.add_child(_name)
	_tag = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	tv.add_child(_tag)
	_glyph = InputGlyph.new("")
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_glyph)
	_desc = UITheme.label("", UITheme.TEXT, UITheme.FONT_SMALL)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	v.add_child(_desc)
	v.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 2)
	v.add_child(_grid)
	_foot = UITheme.label("Damage before the target's armor.", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	v.add_child(_foot)


func show_for(p: Player, p_slot: int, anchor: Control) -> void:
	player = p
	slot = p_slot
	_anchor = anchor
	_sig = ""
	refresh()
	visible = true
	_place.call_deferred()


func hide_for(anchor: Control) -> void:
	if anchor == _anchor:
		visible = false
		_anchor = null


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(player) or not is_instance_valid(_anchor) or not _anchor.is_visible_in_tree():
		visible = false
		return
	refresh()
	_place()


## Rebuilds the rows when anything they depend on changed (stats, level, talents, bindings).
func refresh() -> void:
	var sig := "%s|%d|%s|%d" % [player.stats.final, player.level, player.talents, slot]
	if sig == _sig:
		return
	_sig = sig
	var sk := GameData.skill(player.skills[slot])
	_icon.texture = GameData.texture("icons." + str(sk.get("icon", "attack")))
	_name.text = str(sk.get("name", "?"))
	_tag.text = ("Primary attack" if slot == 0 else "Skill %d" % slot) + "  -  " + str(sk.get("school", "")).capitalize()
	_glyph.action = Player.SLOT_ACTIONS[slot]
	_desc.text = str(sk.get("description", ""))
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var deals := false
	for r in SkillInfo.rows(player, sk):
		var k := UITheme.label(r.k, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		_grid.add_child(k)
		var v := UITheme.label(r.v, _color(int(r.kind)), UITheme.FONT_SMALL)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(150, 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(v)
		deals = deals or int(r.kind) == SkillInfo.Kind.DAMAGE
	_foot.visible = deals
	reset_size()


func _color(kind: int) -> Color:
	match kind:
		SkillInfo.Kind.DAMAGE:
			return Color("ff9a6a")
		SkillInfo.Kind.HEAL:
			return UITheme.GOOD
		SkillInfo.Kind.STATUS:
			return UITheme.CYAN
		SkillInfo.Kind.TALENT:
			return UITheme.GOLD
	return UITheme.TEXT


## Right of the anchor if it fits, otherwise left of it; always inside the visible rect.
func _place() -> void:
	if not is_instance_valid(_anchor):
		return
	var vp := get_viewport_rect()
	var a := _anchor.get_global_rect()
	var s := get_combined_minimum_size()
	size = s
	var pos := Vector2(a.end.x + GAP, a.position.y)
	if pos.x + s.x > vp.end.x - GAP:
		pos.x = a.position.x - GAP - s.x
	if pos.x < vp.position.x + GAP:
		pos.x = clampf(a.position.x, vp.position.x + GAP, vp.end.x - GAP - s.x)
		pos.y = a.end.y + GAP
		if pos.y + s.y > vp.end.y - GAP:
			pos.y = a.position.y - GAP - s.y
	pos.y = clampf(pos.y, vp.position.y + GAP, maxf(vp.position.y + GAP, vp.end.y - GAP - s.y))
	global_position = pos.round()
