extends UIModal
## Full map overlay (Map action): every discovered cell of the floor, players and the portal.

const Minimap := preload("res://scripts/ui/minimap.gd")


func _init() -> void:
	title_text = Loc.t("Map")
	menu_tab = "map"
	prompts = [["map", Loc.t("Toggle map")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var depth := int(game.depth) if game and "depth" in game else 0
	if depth > 0:
		subtitle.text = Loc.f("Floor %d  -  %s", [depth, FloorPlan.title(game.floor_def)])
	# #70 / #71: what makes this floor different, as focusable badges; the focused (or hovered)
	# one's card shows beside them, so a gamepad reads them too.
	var floor_badges := _floor_badges(game)
	if not floor_badges.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		var card_holder := MarginContainer.new()
		for b in floor_badges:
			b.focus_mode = Control.FOCUS_ALL
			var show_card := func():
				for c in card_holder.get_children():
					c.queue_free()
				card_holder.add_child(Badge.card(b.icon_key, b.title, b.lines, b.rim))
			b.focus_entered.connect(show_card)
			b.mouse_entered.connect(show_card)
			row.add_child(b)
		row.add_child(card_holder)
		floor_badges[0].grab_focus.call_deferred()
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


func _floor_badges(game: Node) -> Array:
	var out: Array = []
	if game == null:
		return out
	var mix := str(game.floor_def.get("mix", ""))
	if not mix.is_empty():
		var ov := Loc.t(str(GameData.floor_types[mix].get("overrun", "")))
		out.append(Badge.new("mod_overrun", ov.substr(0, 1).to_upper() + ov.substr(1), [[Loc.t("Part of the monsters here come from another biome.")]], UITheme.BADGE_INVASION, 28))
	var mod := str(game.floor_def.get("mod", ""))
	if not mod.is_empty():
		var md := FloorMods.def(mod)
		out.append(Badge.new(str(md.icon), Loc.t(str(md.name)), FloorMods.card_lines(mod), FloorMods.color(mod), 28))
	return out
