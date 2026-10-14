extends Control
## Talent tree overlay for the local player's class (data/talents/<class>.json).
## Accept on a node spends a point (host validates); rows unlock after spending
## `tier_points` points per row; some nodes require a previous one.

signal closed

var player: Player
var _grid: GridContainer
var _desc: Label
var _points: Label
var _buttons: Dictionary = {}
var _focused := ""
var _last_talents: Dictionary = {}
var _last_points := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 440)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UITheme.title("%s Talents" % player.class_def.name, 26))
	_points = UITheme.label("", UITheme.GOOD, 16)
	head.add_child(_points)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(_grid)
	_desc = UITheme.label("", UITheme.TEXT, 14)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(600, 48)
	v.add_child(_desc)
	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	var reset := Button.new()
	reset.text = "Reset talents (free)"
	reset.pressed.connect(func(): player.request_reset_talents.rpc_id(1))
	bottom.add_child(reset)
	bottom.add_child(UITheme.label("   B/Esc/T: close", UITheme.TEXT_DIM, 12))
	_build()


func _build() -> void:
	var tree: Dictionary = GameData.talents.get(player.class_id, {})
	var by_pos := {}
	var max_row := 0
	for node in tree.get("nodes", []):
		by_pos[Vector2i(int(node.col), int(node.row))] = node
		max_row = maxi(max_row, int(node.row))
	for row in max_row + 1:
		for col in 3:
			var node: Dictionary = by_pos.get(Vector2i(col, row), {})
			if node.is_empty():
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(190, 50)
				_grid.add_child(spacer)
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 50)
			b.focus_mode = Control.FOCUS_ALL
			b.pressed.connect(func(): player.request_learn_talent.rpc_id(1, node.id))
			b.focus_entered.connect(func(): _focused = node.id; _show(node))
			b.mouse_entered.connect(func(): _show(node))
			_grid.add_child(b)
			_buttons[node.id] = [b, node]
	_refresh()
	for id in _buttons:
		_buttons[id][0].grab_focus.call_deferred()
		break


func _process(_delta: float) -> void:
	if player.talents != _last_talents or player.talent_points != _last_points:
		_refresh()


func _refresh() -> void:
	_last_talents = player.talents.duplicate()
	_last_points = player.talent_points
	_points.text = "   Points: %d" % player.talent_points
	var tree: Dictionary = GameData.talents.get(player.class_id, {})
	var spent := 0
	for k in player.talents:
		spent += int(player.talents[k])
	for id in _buttons:
		var b: Button = _buttons[id][0]
		var node: Dictionary = _buttons[id][1]
		var rank := int(player.talents.get(id, 0))
		b.text = "%s\n%d / %d" % [node.name, rank, int(node.max_rank)]
		var unlocked := spent >= int(node.row) * int(tree.get("tier_points", 2))
		for req in node.get("requires", []):
			if int(player.talents.get(req, 0)) <= 0:
				unlocked = false
		b.modulate = Color(1, 1, 1) if unlocked or rank > 0 else Color(0.5, 0.5, 0.55)
		if rank >= int(node.max_rank):
			b.add_theme_color_override("font_color", UITheme.ACCENT)
	if _buttons.has(_focused):
		_show(_buttons[_focused][1])


func _show(node: Dictionary) -> void:
	var req := ""
	if node.has("requires"):
		var names: Array = []
		for r in node.requires:
			names.append(_buttons.get(r, [null, {"name": r}])[1].name)
		req = "  Requires: %s." % ", ".join(names)
	_desc.text = "%s: %s%s" % [node.name, node.description, req]
