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
	for m in [["map_archibald", Loc.t("Archibald")], ["map_malphas", Loc.t("Malphas")], ["map_boss", Loc.t("Boss")], ["map_lock", Loc.t("Sealed")]]:
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
