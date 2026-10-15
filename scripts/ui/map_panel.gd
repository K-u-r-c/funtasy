extends UIModal
## Full map overlay (Map action): every discovered cell of the floor, players and the portal.

const Minimap := preload("res://scripts/ui/minimap.gd")


func _init() -> void:
	title_text = "Map"
	menu_tab = "map"
	prompts = [["map", "Toggle map"], ["ui_cancel", "Close"]]


func _build() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var depth := int(game.depth) if game and "depth" in game else 0
	if depth > 0:
		subtitle.text = "Floor %d  -  %s" % [depth, str(game.floor_def.get("name", ""))]
	var mm: Control = Minimap.new()
	mm.full_map = true
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(mm)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	content.add_child(legend)
	for e in [["You / party", Color("6ee3f0")], ["Portal", Color(0.7, 0.4, 1.0)], ["Door", Color(0.75, 0.5, 0.25)], ["Lava", Color(0.85, 0.3, 0.05)]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		var sw := ColorRect.new()
		sw.color = e[1]
		sw.custom_minimum_size = Vector2(6, 6)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		item.add_child(UITheme.label(e[0], UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		legend.add_child(item)
