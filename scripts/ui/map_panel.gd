extends Control
## Full map overlay (Map action): every discovered cell of the floor, players and the portal.

signal closed

var player: Player


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var title := UITheme.title("Map", 26)
	title.position = Vector2(40, 16)
	add_child(title)
	var hint := UITheme.label("[%s] / B: close" % InputSettings.prompt_for("map"), UITheme.TEXT_DIM, 12)
	hint.position = Vector2(40, 52)
	add_child(hint)
	var mm: Control = preload("res://scripts/ui/minimap.gd").new()
	mm.full_map = true
	mm.position = Vector2(40, 72)
	mm.size = Vector2(880, 450)
	add_child(mm)
