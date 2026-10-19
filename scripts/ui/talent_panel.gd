extends UIModal
## Talent tree overlay v2 (D1, GDD 8): three branch columns x tiers 0-5 for the local player's
## class (data/talents/<class>.json). Skill nodes unlock skills for the Skill Book, passive
## nodes have ranks, keystones (T2 / T5) one rank. Tier N of a branch opens after N x
## `tier_points` points spent in that branch. Accept spends a point (host validates).

const NODE_PX := 40
const CELL_W := 46
const TIERS := 6

var _tree: Dictionary = {}
var _points: Label
var _card: VBoxContainer
var _buttons: Dictionary = {}  ## id -> [TalentNode, node dict]
var _grid_pos: Dictionary = {}  ## Vector2i(column, tier) -> node id
var _branch_labels: Dictionary = {}  ## branch id -> Label
var _cols_per_branch := 3
var _reset: Button
var _points_chip: PanelContainer
var _focused := ""
var _last_talents: Dictionary = {}
var _last_points := -1


func _init() -> void:
	title_text = Loc.t("Talents")
	menu_tab = "talents"
	prompts = [["ui_accept", Loc.t("Learn rank")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	_tree = GameData.talents.get(player.class_id, {})
	_points = subtitle
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	# Tier labels column
	var tiers := VBoxContainer.new()
	tiers.add_theme_constant_override("separation", 4)
	body.add_child(tiers)
	var head_gap := Control.new()
	head_gap.custom_minimum_size = Vector2(0, 34)
	tiers.add_child(head_gap)
	for t in TIERS:
		var tl := UITheme.label("T%d" % t, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
		tl.custom_minimum_size = Vector2(26, NODE_PX + 4)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if t == 2 or t == 5:
			tl.text += "\n" + Loc.t("Key")
			tl.add_theme_color_override("font_color", UITheme.GOLD_DIM)
		tiers.add_child(tl)

	var per_tier := {}  ## "branch:tier" -> [nodes]
	for nd in _tree.get("nodes", []):
		var k := "%s:%d" % [nd.get("branch", ""), int(nd.get("tier", 0))]
		if not per_tier.has(k):
			per_tier[k] = []
		per_tier[k].append(nd)
		_cols_per_branch = maxi(_cols_per_branch, per_tier[k].size())
	var branches: Array = _tree.get("branches", [])
	for bi in branches.size():
		var br: Dictionary = branches[bi]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		body.add_child(col)
		var head := PanelContainer.new()
		head.theme_type_variation = &"GlassInset"
		head.custom_minimum_size = Vector2(_cols_per_branch * CELL_W, 30)
		head.tooltip_text = Loc.t(str(br.get("description", "")))
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(head)
		# The branch's emblem, its name and the points spent in it (#29).
		var hrow := HBoxContainer.new()
		hrow.alignment = BoxContainer.ALIGNMENT_CENTER
		hrow.add_theme_constant_override("separation", 4)
		hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(hrow)
		hrow.add_child(UITheme.icon("branch_" + str(br.id), 24))
		var bl := UITheme.label(Loc.t(str(br.name)), UITheme.GOLD, UITheme.FONT_SMALL)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(_cols_per_branch * CELL_W - 40, 0)
		hrow.add_child(bl)
		_branch_labels[br.id] = bl
		for t in TIERS:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", CELL_W - NODE_PX)
			row.custom_minimum_size = Vector2(_cols_per_branch * CELL_W, NODE_PX + 4)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			col.add_child(row)
			var list: Array = per_tier.get("%s:%d" % [br.id, t], [])
			for i in list.size():
				var nd: Dictionary = list[i]
				var b := TalentNode.new()
				b.node = nd.merged({"name": _node_name(nd), "col": bi * 10 + i, "row": t}, true)
				b.icon_tex = _icon_for(nd)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				var nid := str(nd.id)
				b.pressed.connect(func(): player.request_learn_talent.rpc_id(1, nid))
				b.focus_entered.connect(func(): _focused = nid; _show(nd))
				b.mouse_entered.connect(func(): _show(nd))
				row.add_child(b)
				_buttons[nid] = [b, nd]
				_grid_pos[Vector2i(bi * _cols_per_branch + i, t)] = nid

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_points_chip = UITheme.chip("act_plus", "", UITheme.GOOD, UITheme.GOLD_DIM)
	_points_chip.tooltip_text = Loc.t("Talent points to spend")
	_points_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UIFx.pulse(_points_chip)
	right.add_child(_points_chip)
	var card_panel := PanelContainer.new()
	card_panel.theme_type_variation = &"GlassInset"
	card_panel.custom_minimum_size = Vector2(230, 0)
	card_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(card_panel)
	# The card scrolls when a skill's numbers run longer than the panel (#43 / #44).
	var card_scroll := ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_panel.add_child(card_scroll)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 4)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(_card)
	_reset = AnimButton.new()
	_reset.text = Loc.t("Reset talents (free)")
	_reset.icon = UITheme.icon_tex("act_reset")
	_reset.add_theme_constant_override("icon_max_width", 16)
	_reset.custom_minimum_size = Vector2(230, 28)
	_reset.pressed.connect(func(): player.request_reset_talents.rpc_id(1))
	right.add_child(_reset)

	_wire_focus()
	_refresh()
	var first: String = _grid_pos.get(Vector2i(0, 0), "")
	if first == "" and not _buttons.is_empty():
		first = _buttons.keys()[0]
	if first != "":
		_buttons[first][0].grab_focus.call_deferred()


func _node_name(nd: Dictionary) -> String:
	if nd.get("type", "") == "skill":
		return Loc.t(str(GameData.skills.get(str(nd.skill), {}).get("name", nd.skill)))
	return Loc.t(str(nd.get("name", nd.id)))


func _icon_for(node: Dictionary) -> Texture2D:
	if node.has("icon") and GameData.asset_exists("icons." + str(node.icon)):
		return GameData.texture("icons." + str(node.icon))
	if node.get("type", "") == "skill" and GameData.skills.has(str(node.skill)):
		return GameData.texture("icons." + str(GameData.skill(str(node.skill)).get("icon", "attack")))
	for m in node.get("mods", []):
		if m.has("skill") and GameData.skills.has(m.skill):
			return GameData.texture("icons." + str(GameData.skill(m.skill).get("icon", "attack")))
	return null


## D-pad / arrows: left/right walk the grid row across branches, up/down the nearest node of
## the next tier; the bottom of every column leads to the reset button.
func _wire_focus() -> void:
	var max_col := 0
	for k in _grid_pos:
		max_col = maxi(max_col, k.x)
	for k in _grid_pos:
		var b: TalentNode = _buttons[_grid_pos[k]][0]
		var left := _scan(k, Vector2i(-1, 0), max_col)
		var right := _scan(k, Vector2i(1, 0), max_col)
		var up := _scan(k, Vector2i(0, -1), max_col)
		var down := _scan(k, Vector2i(0, 1), max_col)
		b.focus_neighbor_left = b.get_path_to(left) if left else b.get_path()
		b.focus_neighbor_right = b.get_path_to(right if right else _reset)
		b.focus_neighbor_top = b.get_path_to(up) if up else b.get_path()
		b.focus_neighbor_bottom = b.get_path_to(down if down else _reset)


func _scan(from: Vector2i, step: Vector2i, max_col: int) -> Control:
	if step.y == 0:
		var c := from.x + step.x
		while c >= 0 and c <= max_col:
			if _grid_pos.has(Vector2i(c, from.y)):
				return _buttons[_grid_pos[Vector2i(c, from.y)]][0]
			c += step.x
		return null
	var r := from.y + step.y
	while r >= 0 and r < TIERS:
		for dc in [0, 1, -1, 2, -2, 3, -3]:
			if _grid_pos.has(Vector2i(from.x + dc, r)):
				return _buttons[_grid_pos[Vector2i(from.x + dc, r)]][0]
		r += step.y
	return null


func _process(_delta: float) -> void:
	if player.talents != _last_talents or player.talent_points != _last_points:
		_refresh()


func _refresh() -> void:
	_last_talents = player.talents.duplicate()
	_last_points = player.talent_points
	_points.text = "%s  -  %s" % [Loc.t(str(player.class_def.name)), Loc.plural(player.talent_points, "%d point to spend", "%d points to spend")]
	if _points_chip:
		_points_chip.get_meta("label").text = "%d" % player.talent_points
		_points_chip.get_meta("label").add_theme_color_override("font_color", UITheme.GOOD if player.talent_points > 0 else UITheme.TEXT_DIM)
	_points.add_theme_color_override("font_color", UITheme.GOOD if player.talent_points > 0 else UITheme.TEXT_DIM)
	for br in _tree.get("branches", []):
		_branch_labels[br.id].text = "%s (%d)" % [Loc.t(str(br.name)), player.branch_points(br.id)]
	for id in _buttons:
		var b: TalentNode = _buttons[id][0]
		var node: Dictionary = _buttons[id][1]
		b.rank = player.node_rank(node)
		b.unlocked = _unlocked(node)
		b.can_learn = b.unlocked and not player.is_free_node(node) and b.rank < int(node.get("max_rank", 1)) and player.talent_points > 0
		b.queue_redraw()
	if _buttons.has(_focused):
		_show(_buttons[_focused][1])


func _unlocked(node: Dictionary) -> bool:
	if player.is_free_node(node):
		return true
	if player.branch_points(str(node.get("branch", ""))) < int(node.get("tier", 0)) * int(_tree.get("tier_points", 2)):
		return false
	for req in node.get("requires", []):
		if player.node_rank(player.talent_node(str(req))) <= 0:
			return false
	return true


func _show(node: Dictionary) -> void:
	for c in _card.get_children():
		c.queue_free()
	var rank := player.node_rank(node)
	var kind := str(node.get("type", "passive"))
	_card.add_child(UITheme.label(_node_name(node), UITheme.GOLD, UITheme.FONT_BODY))
	var tag: String = {"skill": Loc.t("Skill"), "passive": Loc.t("Passive talent"), "keystone": Loc.t("Keystone")}.get(kind, kind.capitalize())
	if player.is_free_node(node):
		tag += Loc.t(" - known from the start")
	else:
		tag += Loc.f(" - rank %d / %d", [rank, int(node.get("max_rank", 1))])
	_card.add_child(UITheme.label(tag, UITheme.CYAN, UITheme.FONT_SMALL))
	_card.add_child(HSeparator.new())
	# Passives: what the ranks learned so far give and what the next one adds, with stat icons.
	if kind != "skill" and not node.get("mods", []).is_empty():
		var nums := HFlowContainer.new()
		nums.add_theme_constant_override("h_separation", 4)
		nums.add_theme_constant_override("v_separation", 4)
		for m in node.mods:
			if m.has("skill"):
				continue
			var st := str(m.stat).trim_suffix("_pct").trim_suffix("_mult")
			var per := float(m.value)
			var pct := str(m.stat).ends_with("_pct") or str(m.stat).ends_with("_mult") or st in ["crit_chance", "crit_damage", "haste", "dodge", "leech", "block_chance", "magic_resist", "armor_pen", "magic_pen", "max_traps"]
			var now := per * maxi(rank, 1)
			var txt := ("%+d%%" % roundi(now * 100.0)) if pct else ("%+d" % roundi(now))
			var c := UITheme.chip(str(UITheme.STAT_ICONS.get(st, "sil_star")), txt, UITheme.GOOD if rank > 0 else UITheme.TEXT_DIM,
					Color(UITheme.GOOD, 0.5) if rank > 0 else UITheme.EDGE)
			nums.add_child(c)
		if nums.get_child_count() > 0:
			_card.add_child(nums)
	# #43: exactly what it does, with this hero's numbers, generated from the data.
	for r in TalentInfo.rows(player, node):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.add_child(UITheme.label(r.k, UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		var v := UITheme.label(r.v, SkillTooltip.color_for(int(r.kind)), UITheme.FONT_SMALL)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(200, 0)
		row.add_child(v)
		_card.add_child(row)
	# The flavour text stays, second and dimmer.
	var desc := Loc.t(str(node.get("description", "")))
	if kind == "skill":
		var sk: Dictionary = GameData.skills.get(str(node.skill), {})
		desc = Loc.t(str(sk.get("description", ""))) + (Loc.t("\nPassive: always active once learned.") if sk.get("passive", false) else Loc.t("\nLearn it, then slot it in the Skill Book."))
	_card.add_child(HSeparator.new())
	var d := UITheme.label(desc, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(200, 0)
	_card.add_child(d)
	var need := int(node.get("tier", 0)) * int(_tree.get("tier_points", 2))
	if need > 0 and not player.is_free_node(node):
		var ok := _unlocked(node)
		var rl := UITheme.label(Loc.f("Requires %d points in this branch", [need]), UITheme.GOOD if ok else UITheme.DANGER, UITheme.FONT_SMALL)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size = Vector2(210, 0)
		_card.add_child(rl)


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
		if str(node.get("type", "")) == "keystone":
			edge = UITheme.GOLD_DIM.darkened(0.3)
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
			for w in Loc.t(str(node.get("name", "?"))).split(" "):
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
