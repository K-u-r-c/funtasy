extends UIModal
## Talent tree overlay for the local player's class (data/talents/<class>.json).
## Accept on a node spends a point (host validates); rows unlock after spending
## `tier_points` points per row; some nodes require a previous one (drawn as links).

const NODE_PX := 48
const COL_W := 112

var _tree: Dictionary = {}
var _grid: GridContainer
var _links: Control
var _points: Label
var _card: VBoxContainer
var _buttons: Dictionary = {}  ## id -> [TalentNode, node dict]
var _tier_labels: Array = []
var _reset: Button
var _focused := ""
var _last_talents: Dictionary = {}
var _last_points := -1


func _init() -> void:
	title_text = "Talents"
	menu_tab = "talents"
	prompts = [["ui_accept", "Learn rank"], ["ui_cancel", "Close"]]


func _build() -> void:
	_tree = GameData.talents.get(player.class_id, {})
	_points = subtitle

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var tiers := VBoxContainer.new()
	body.add_child(tiers)
	_links = MarginContainer.new()
	_links.draw.connect(_draw_links)
	body.add_child(_links)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 6)
	_links.add_child(_grid)

	var by_pos := {}
	var max_row := 0
	for node in _tree.get("nodes", []):
		by_pos[Vector2i(int(node.col), int(node.row))] = node
		max_row = maxi(max_row, int(node.row))
	for row in max_row + 1:
		var tl := UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		tl.custom_minimum_size = Vector2(64, NODE_PX + 16)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tiers.add_child(tl)
		_tier_labels.append(tl)
		if row < max_row:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 6)
			tiers.add_child(gap)
		for col in 3:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(COL_W, NODE_PX + 16)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			cell.add_theme_constant_override("separation", 2)
			_grid.add_child(cell)
			var node: Dictionary = by_pos.get(Vector2i(col, row), {})
			if node.is_empty():
				continue
			var b := TalentNode.new()
			b.node = node
			b.icon_tex = _icon_for(node)
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func(): player.request_learn_talent.rpc_id(1, node.id))
			b.focus_entered.connect(func(): _focused = node.id; _show(node))
			b.mouse_entered.connect(func(): _show(node))
			cell.add_child(b)
			var name_l := UITheme.label(str(node.name), UITheme.TEXT, UITheme.FONT_SMALL)
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(name_l)
			_buttons[node.id] = [b, node]

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var card_panel := PanelContainer.new()
	card_panel.theme_type_variation = &"GlassInset"
	card_panel.custom_minimum_size = Vector2(240, 0)
	card_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(card_panel)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 4)
	card_panel.add_child(_card)
	_reset = AnimButton.new()
	_reset.text = "Reset talents (free)"
	_reset.custom_minimum_size = Vector2(240, 28)
	_reset.pressed.connect(func(): player.request_reset_talents.rpc_id(1))
	right.add_child(_reset)

	_wire_focus(by_pos, max_row)
	_refresh()
	for id in _buttons:
		_buttons[id][0].grab_focus.call_deferred()
		break


func _icon_for(node: Dictionary) -> Texture2D:
	for m in node.get("mods", []):
		if m.has("skill") and GameData.skills.has(m.skill):
			return GameData.texture("icons." + str(GameData.skill(m.skill).get("icon", "attack")))
	return null


## Explicit d-pad chains: left/right stay in the row, up/down follow the column (or the nearest
## node of the next row); the bottom row leads to the reset button.
func _wire_focus(by_pos: Dictionary, max_row: int) -> void:
	for id in _buttons:
		var b: TalentNode = _buttons[id][0]
		var p := Vector2i(int(b.node.col), int(b.node.row))
		var left := _find(by_pos, p, Vector2i(-1, 0), max_row)
		var right := _find(by_pos, p, Vector2i(1, 0), max_row)
		var up := _find(by_pos, p, Vector2i(0, -1), max_row)
		var down := _find(by_pos, p, Vector2i(0, 1), max_row)
		b.focus_neighbor_left = b.get_path_to(left) if left else b.get_path()
		b.focus_neighbor_right = b.get_path_to(right if right else _reset)
		b.focus_neighbor_top = b.get_path_to(up) if up else b.get_path()
		b.focus_neighbor_bottom = b.get_path_to(down if down else _reset)


func _find(by_pos: Dictionary, from: Vector2i, step: Vector2i, max_row: int) -> Control:
	if step.y == 0:
		var c := from.x + step.x
		while c >= 0 and c < 3:
			if by_pos.has(Vector2i(c, from.y)):
				return _buttons[by_pos[Vector2i(c, from.y)].id][0]
			c += step.x
		return null
	var r := from.y + step.y
	while r >= 0 and r <= max_row:
		if by_pos.has(Vector2i(from.x, r)):
			return _buttons[by_pos[Vector2i(from.x, r)].id][0]
		for dc in [1, -1, 2, -2]:
			if by_pos.has(Vector2i(from.x + dc, r)):
				return _buttons[by_pos[Vector2i(from.x + dc, r)].id][0]
		r += step.y
	return null


func _process(_delta: float) -> void:
	if player.talents != _last_talents or player.talent_points != _last_points:
		_refresh()


func _spent() -> int:
	var spent := 0
	for k in player.talents:
		spent += int(player.talents[k])
	return spent


func _refresh() -> void:
	_last_talents = player.talents.duplicate()
	_last_points = player.talent_points
	_points.text = "%s  -  %d point%s to spend" % [player.class_def.name, player.talent_points, "" if player.talent_points == 1 else "s"]
	_points.add_theme_color_override("font_color", UITheme.GOOD if player.talent_points > 0 else UITheme.TEXT_DIM)
	var spent := _spent()
	var tier_pts := int(_tree.get("tier_points", 2))
	for i in _tier_labels.size():
		var need := i * tier_pts
		_tier_labels[i].text = "Tier %d\n%s" % [i + 1, "open" if spent >= need else "%d pts" % need]
		_tier_labels[i].add_theme_color_override("font_color", UITheme.GOLD if spent >= need else UITheme.TEXT_DIM)
	for id in _buttons:
		var b: TalentNode = _buttons[id][0]
		var node: Dictionary = _buttons[id][1]
		b.rank = int(player.talents.get(id, 0))
		b.unlocked = _unlocked(node, spent)
		b.can_learn = b.unlocked and b.rank < int(node.max_rank) and player.talent_points > 0
		b.queue_redraw()
	_links.queue_redraw()
	if _buttons.has(_focused):
		_show(_buttons[_focused][1])


func _unlocked(node: Dictionary, spent: int) -> bool:
	if spent < int(node.row) * int(_tree.get("tier_points", 2)):
		return false
	for req in node.get("requires", []):
		if int(player.talents.get(req, 0)) <= 0:
			return false
	return true


func _show(node: Dictionary) -> void:
	for c in _card.get_children():
		c.queue_free()
	var rank := int(player.talents.get(node.id, 0))
	_card.add_child(UITheme.label(str(node.name), UITheme.GOLD, UITheme.FONT_BODY))
	_card.add_child(UITheme.label("Rank %d / %d" % [rank, int(node.max_rank)], UITheme.CYAN, UITheme.FONT_SMALL))
	_card.add_child(HSeparator.new())
	var d := UITheme.label(str(node.description), UITheme.TEXT, UITheme.FONT_SMALL)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(220, 0)
	_card.add_child(d)
	var reqs: Array = []
	if int(node.row) > 0:
		reqs.append("%d points in the tree" % (int(node.row) * int(_tree.get("tier_points", 2))))
	for r in node.get("requires", []):
		reqs.append(str(_buttons.get(r, [null, {"name": r}])[1].name))
	if not reqs.is_empty():
		var ok := _unlocked(node, _spent())
		var rl := UITheme.label("Requires: %s" % ", ".join(reqs), UITheme.GOOD if ok else UITheme.DANGER, UITheme.FONT_SMALL)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size = Vector2(220, 0)
		_card.add_child(rl)


func _draw_links() -> void:
	var origin := _links.global_position
	for id in _buttons:
		var b: TalentNode = _buttons[id][0]
		for req in b.node.get("requires", []):
			if not _buttons.has(req):
				continue
			var a: TalentNode = _buttons[req][0]
			var from := (a.global_position - origin + Vector2(a.size.x / 2.0, a.size.y)).round()
			var to := (b.global_position - origin + Vector2(b.size.x / 2.0, 0)).round()
			var lit := int(player.talents.get(req, 0)) > 0
			var col := UITheme.GOLD if lit else UITheme.EDGE
			var mid_y := roundf((from.y + to.y) / 2.0)
			_links.draw_rect(Rect2(from.x - 1, from.y, 2, mid_y - from.y), col)
			_links.draw_rect(Rect2(minf(from.x, to.x) - 1, mid_y - 1, absf(to.x - from.x) + 2, 2), col)
			_links.draw_rect(Rect2(to.x - 1, mid_y, 2, to.y - mid_y), col)
			if lit:
				_links.draw_rect(Rect2(to.x - 2, to.y - 3, 4, 3), col)


## One talent: framed icon (or initials), rank pips, state colors.
class TalentNode:
	extends Button
	var node: Dictionary
	var icon_tex: Texture2D
	var rank := 0
	var unlocked := false
	var can_learn := false
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(NODE_PX, NODE_PX)
		focus_mode = Control.FOCUS_ALL
		var clear := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(s, clear)
		button_down.connect(func(): AudioManager.play_sfx("ui_press", 0.05))
		focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))

	func _process(delta: float) -> void:
		if can_learn:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size.round())
		var maxed := rank >= int(node.get("max_rank", 1))
		var edge := UITheme.EDGE
		if maxed:
			edge = UITheme.GOLD
		elif rank > 0:
			edge = UITheme.GOLD_DIM
		elif can_learn:
			# Pulse in 4 discrete steps (pixel look, and few cached styles).
			edge = UITheme.CYAN.lerp(UITheme.CYAN_DIM, roundf((0.5 + 0.5 * sin(_t * 4.0)) * 3.0) / 3.0)
		var bg := Color("0a0e17f2") if unlocked or rank > 0 else Color("06080df2")
		if is_hovered() or button_pressed:
			bg = Color("16203af2")
		var press := Vector2(0, 1) if button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) else Vector2.ZERO
		draw_style_box(UITheme.cached_glass(bg, edge, 2 if maxed else 1, 0, UITheme.CYAN if can_learn else Color(0, 0, 0, 0)), r)
		var dim := Color.WHITE if unlocked or rank > 0 else Color(0.4, 0.42, 0.5)
		var ir := Rect2(((r.size - Vector2(32, 32)) / 2.0).round() + Vector2(0, -3) + press, Vector2(32, 32))
		if icon_tex:
			draw_texture_rect(icon_tex, ir, false, dim)
		else:
			var f := UITheme.font()
			var initials := ""
			for w in str(node.get("name", "?")).split(" "):
				if not w.is_empty() and initials.length() < 2:
					initials += w[0]
			var tw := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY).x
			draw_string(f, Vector2(roundf((r.size.x - tw) / 2.0), ir.get_center().y + 6) + press, initials,
					HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY, UITheme.GOLD * dim)
		# Rank pips
		var mr := int(node.get("max_rank", 1))
		var pw := 5.0
		var total := mr * pw + (mr - 1) * 2.0
		var x0 := roundf((r.size.x - total) / 2.0)
		for i in mr:
			var pr := Rect2(x0 + i * (pw + 2.0), r.size.y - 6, pw, 3)
			draw_rect(pr, UITheme.GOLD if i < rank else Color("1c2333"))
		if not unlocked and rank == 0:
			# small padlock
			var lc := Vector2(r.size.x - 9, 4)
			draw_rect(Rect2(lc + Vector2(1, 0), Vector2(4, 1)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(1, 0), Vector2(1, 3)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(4, 0), Vector2(1, 3)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(0, 3), Vector2(6, 4)), UITheme.TEXT_DIM)
