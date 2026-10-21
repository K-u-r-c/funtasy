extends UIModal
## Full map overlay (Map action): every discovered cell of the floor, players and the portal.

const Minimap := preload("res://scripts/ui/minimap.gd")

var _badges: Array = []  ## the floor's badges (#87)
var _card: Control  ## the focused badge's floating card


func _init() -> void:
	title_text = Loc.t("Map")
	menu_tab = "map"
	prompts = [["map", Loc.t("Toggle map")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var depth := int(game.depth) if game and "depth" in game else 0
	if depth > 0:
		subtitle.text = Loc.f("Floor %d  -  %s", [depth, FloorPlan.title(game.floor_def)])
	# #70 / #71: what makes this floor different, as small focusable badges in the header (#87):
	# the card with the name and what it does floats over the map only while a badge is hovered
	# (the badge's own tooltip) or focused (keyboard / gamepad: any direction focuses the first).
	_badges = _floor_badges(game)
	for b in _badges:
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_entered.connect(_float_card.bind(b))
		b.focus_exited.connect(_float_card.bind(null))
		header.add_child(b)
		header.move_child(b, subtitle.get_index() + 1)
	var mm: Control = Minimap.new()
	mm.full_map = true
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(mm)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	content.add_child(legend)
	for e in [[Loc.t("You / party"), Color("6ee3f0")], [Loc.t("Portal"), Color(0.7, 0.4, 1.0)], [Loc.t("Door"), Color(0.75, 0.5, 0.25)], [Loc.t("Lava"), Color(0.85, 0.3, 0.05)]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		var sw := ColorRect.new()
		sw.color = e[1]
		sw.custom_minimum_size = Vector2(6, 6)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		item.add_child(UITheme.label(e[0], UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		legend.add_child(item)
	# The chamber marks (#28) with their own icons.
	for m in [["map_archibald", Loc.t("Archibald")], ["map_malphas", Loc.t("Malphas")], ["map_forge", Loc.t("Forge")], ["map_boss", Loc.t("Boss")], ["map_lock", Loc.t("Sealed")]]:
		var mi := HBoxContainer.new()
		mi.add_theme_constant_override("separation", 4)
		var t := TextureRect.new()
		t.texture = GameData.texture("ui." + str(m[0]))
		t.custom_minimum_size = Vector2(12, 12)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mi.add_child(t)
		mi.add_child(UITheme.label(m[1], UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		legend.add_child(mi)


## #87: the focused badge's card, floating under the header over the map (never in the layout).
func _float_card(b: Badge) -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	if b == null or not is_instance_valid(b):
		return
	_card = Badge.card(b.icon_key, b.title, b.lines, b.rim)
	_card.top_level = true
	_card.z_index = 10
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_card.global_position = b.get_global_rect().position + Vector2(0, b.size.y + 6)


func _unhandled_input(ev: InputEvent) -> void:
	if _badges.is_empty() or get_viewport().gui_get_focus_owner() != null:
		return
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if ev.is_action_pressed(a):
			_badges[0].grab_focus()
			get_viewport().set_input_as_handled()
			return


func _floor_badges(game: Node) -> Array:
	var out: Array = []
	if game == null:
		return out
	var mix := str(game.floor_def.get("mix", ""))
	if not mix.is_empty():
		var ov := Loc.t(str(GameData.floor_types[mix].get("overrun", "")))
		out.append(Badge.new("mod_overrun", ov.substr(0, 1).to_upper() + ov.substr(1), [[Loc.t("Part of the monsters here come from another biome.")]], UITheme.BADGE_INVASION, 24))
	var mod := str(game.floor_def.get("mod", ""))
	if not mod.is_empty():
		var md := FloorMods.def(mod)
		out.append(Badge.new(str(md.icon), Loc.t(str(md.name)), FloorMods.card_lines(mod), FloorMods.color(mod), 24))
	return out
