extends UIModal
## Talent trees (#47, data/talents/<class>.json): three branches side by side, each a real tree.
## Nodes sit on their tier row and lane (`col`); lines run from each node's prerequisite down to
## it, dim while locked, glowing cyan when it can be learned and gold once learned. Forks (nodes
## sharing an `exclusive` group) carry an "or" marker; taking one closes the other. Skills are
## square frames, passives round ones with rank pips, keystones large gilded diamonds. Learning a
## rank flashes the node with a burst of sparks, fills its line from the prerequisite and lights
## the children it opened. Accept learns (the host validates: Player.talent_block_reason).
## Arrows / d-pad: up = prerequisite, down = first child, left / right = the next node on the row.

const LANES := 4
const LANE_W := 44
const ROW_H := 52
const HEAD_H := 42
const BRANCH_PAD := 6
const BRANCH_GAP := 8
const TIERS := 6
const LEFT_W := 22  ## the tier labels
const LOCKED := Color("3a4560")
const AVAILABLE := Color("6ee3f0")
const LEARNED := Color("e8b74a")
const CLOSED := Color("6a2a30")
## Branch backdrops, first to third: blood red, steel blue, old gold.
const BRANCH_TINTS := [Color("5a1418"), Color("16304e"), Color("4a3a12")]

var _tree: Dictionary = {}
var _points: Label
var _card: VBoxContainer
var _canvas: TreeCanvas
var _buttons: Dictionary = {}  ## id -> [TalentNode, node dict]
var _branch_labels: Dictionary = {}  ## branch id -> Label
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
	# The tree scrolls only when the screen is too small for it (1:1, #44).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_canvas = TreeCanvas.new()
	_canvas.panel = self
	scroll.add_child(_canvas)
	var branches: Array = _tree.get("branches", [])
	var bw := LANES * LANE_W + BRANCH_PAD * 2
	_canvas.custom_minimum_size = Vector2(LEFT_W + branches.size() * bw + (branches.size() - 1) * BRANCH_GAP, HEAD_H + TIERS * ROW_H + 4)
	scroll.custom_minimum_size = _canvas.custom_minimum_size.min(available_size() - Vector2(240, 80))
	for bi in branches.size():
		var br: Dictionary = branches[bi]
		var x0 := LEFT_W + bi * (bw + BRANCH_GAP)
		_canvas.branch_rects[br.id] = Rect2(x0, 0, bw, _canvas.custom_minimum_size.y)
		_canvas.branch_tints[br.id] = BRANCH_TINTS[bi % BRANCH_TINTS.size()]
		# The branch's emblem, its name and the points spent in it (#29).
		var hrow := HBoxContainer.new()
		hrow.alignment = BoxContainer.ALIGNMENT_CENTER
		hrow.add_theme_constant_override("separation", 4)
		hrow.position = Vector2(x0, 2)
		hrow.size = Vector2(bw, HEAD_H - 12)
		hrow.tooltip_text = Loc.t(str(br.get("description", "")))
		hrow.mouse_filter = Control.MOUSE_FILTER_PASS
		_canvas.add_child(hrow)
		hrow.add_child(UITheme.icon("branch_" + str(br.id), 22))
		var bl := UITheme.label(Loc.t(str(br.name)), UITheme.GOLD, UITheme.FONT_SMALL)
		# Long names (Polish) take a second line rather than an ellipsis.
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.max_lines_visible = 2
		bl.custom_minimum_size = Vector2(bw - 34, 0)
		bl.add_theme_constant_override("line_spacing", -2)
		hrow.add_child(bl)
		_branch_labels[br.id] = bl
	for nd in _tree.get("nodes", []):
		var b := TalentNode.new()
		b.node = nd.merged({"name": _node_name(nd)}, true)
		b.icon_tex = _icon_for(nd)
		b.custom_minimum_size = Vector2(44, 44) if str(nd.get("type", "")) == "keystone" else Vector2(38, 38)
		b.position = node_center(nd) - b.custom_minimum_size / 2.0
		b.size = b.custom_minimum_size
		var nid := str(nd.id)
		b.pressed.connect(func(): player.request_learn_talent.rpc_id(1, nid))
		b.focus_entered.connect(func(): _focused = nid; _show(nd))
		b.mouse_entered.connect(func(): _show(nd))
		_canvas.add_child(b)
		_buttons[nid] = [b, nd]

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
	card_panel.custom_minimum_size = Vector2(220, 0)
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
	_reset.custom_minimum_size = Vector2(220, 28)
	_reset.pressed.connect(func(): player.request_reset_talents.rpc_id(1))
	right.add_child(_reset)

	_wire_focus()
	_refresh(false)
	var first := ""
	for id in _buttons:
		if player.is_free_node(_buttons[id][1]):
			first = id
			break
	if first == "" and not _buttons.is_empty():
		first = _buttons.keys()[0]
	if first != "":
		_buttons[first][0].grab_focus.call_deferred()


## Centre of a node in the canvas: its branch column, lane and tier row.
func node_center(nd: Dictionary) -> Vector2:
	var r: Rect2 = _canvas.branch_rects.get(str(nd.get("branch", "")), Rect2())
	return Vector2(r.position.x + BRANCH_PAD + (int(nd.get("col", 0)) + 0.5) * LANE_W,
			HEAD_H + (int(nd.get("tier", 0)) + 0.5) * ROW_H)


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


## The nodes whose prerequisite is `id`, left to right.
func children_of(id: String) -> Array:
	var out: Array = []
	for k in _buttons:
		if Array(_buttons[k][1].get("requires", [])).has(id):
			out.append(_buttons[k][1])
	out.sort_custom(func(a, b): return node_center(a).x < node_center(b).x)
	return out


## D-pad / arrows along the tree: up to the prerequisite (or the nearest node a row up), down to
## the first child (or the nearest node a row down; the last row leads to the reset button),
## left / right to the next node on the same row, across branches.
func _wire_focus() -> void:
	for id in _buttons:
		var b: TalentNode = _buttons[id][0]
		var nd: Dictionary = _buttons[id][1]
		var c := node_center(nd)
		var t := int(nd.get("tier", 0))
		var reqs: Array = nd.get("requires", [])
		var up: Control = _buttons[str(reqs[0])][0] if not reqs.is_empty() and _buttons.has(str(reqs[0])) else _nearest(c, t - 1)
		var kids := children_of(id)
		var down: Control = _buttons[str(kids[0].id)][0] if not kids.is_empty() else _nearest(c, t + 1)
		var left := _side(c, t, -1)
		var right := _side(c, t, 1)
		b.focus_neighbor_top = b.get_path_to(up) if up else b.get_path()
		b.focus_neighbor_bottom = b.get_path_to(down if down else _reset)
		b.focus_neighbor_left = b.get_path_to(left) if left else b.get_path()
		b.focus_neighbor_right = b.get_path_to(right if right else _reset)
	var any: Control = _nearest(Vector2(0, 0), TIERS - 1)
	if any:
		_reset.focus_neighbor_top = _reset.get_path_to(any)


func _nearest(c: Vector2, tier: int) -> Control:
	var best: Control = null
	var bd := INF
	for id in _buttons:
		var nd: Dictionary = _buttons[id][1]
		if int(nd.get("tier", 0)) == tier:
			var d := absf(node_center(nd).x - c.x)
			if d < bd:
				bd = d
				best = _buttons[id][0]
	return best


func _side(c: Vector2, tier: int, dir: int) -> Control:
	var best: Control = null
	var bd := INF
	for id in _buttons:
		var nd: Dictionary = _buttons[id][1]
		var x := node_center(nd).x
		if int(nd.get("tier", 0)) == tier and (x - c.x) * dir > 0.5 and absf(x - c.x) < bd:
			bd = absf(x - c.x)
			best = _buttons[id][0]
	return best


func _process(_delta: float) -> void:
	if player.talents != _last_talents or player.talent_points != _last_points:
		_refresh(true)


## Node states from the hero; with `animate`, the ranks learned since the last refresh play the
## learn animation and the nodes they opened flash.
func _refresh(animate: bool) -> void:
	var before := _last_talents
	var was_open := {}
	for id in _buttons:
		was_open[id] = _buttons[id][0].can_learn or _buttons[id][0].rank > 0
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
		b.free = player.is_free_node(node)
		var why := player.talent_block_reason(node, true)
		b.closed = why == "closed"
		b.unlocked = why in ["", "maxed", "free"]
		b.can_learn = b.unlocked and not b.free and b.rank < int(node.get("max_rank", 1)) and player.talent_points > 0
		b.queue_redraw()
	if animate:
		for id in _buttons:
			var gained := int(player.talents.get(id, 0)) > int(before.get(id, 0))
			if gained:
				_learned_fx(id)
		for id in _buttons:
			var b2: TalentNode = _buttons[id][0]
			if not was_open[id] and b2.can_learn:
				b2.opened_flash()
	_canvas.queue_redraw()
	if _buttons.has(_focused):
		_show(_buttons[_focused][1])


## A rank was learned: the node flashes and bursts, its line fills from the prerequisite.
func _learned_fx(id: String) -> void:
	var b: TalentNode = _buttons[id][0]
	b.learn_flash()
	_canvas.fill_line(id)
	var p := CPUParticles2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	p.texture = GameData.texture("fx.pixel")
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 40
	p.lifetime = 0.8
	p.spread = 180.0
	p.gravity = Vector2(0, 40)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.damping_min = 30.0
	p.damping_max = 60.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(2.0, 1.6, 0.6))
	g.set_color(1, Color(1.0, 0.6, 0.2, 0.0))
	p.color_ramp = g
	p.position = node_center(_buttons[id][1])
	p.z_index = 2
	_canvas.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	AudioManager.play_sfx("buff", 0.05)


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
	# What it needs: the prerequisite (and its ranks), the points in the branch, the fork.
	if not player.is_free_node(node):
		for req in node.get("requires", []):
			var pn := player.talent_node(str(req))
			var need := int(node.get("requires_rank", 1))
			var have := player.node_rank(pn)
			var txt := Loc.f("Requires %s", [_node_name(pn)]) if need <= 1 else Loc.f("Requires %s at rank %d", [_node_name(pn), need])
			_card.add_child(_wrapped(txt, UITheme.GOOD if have >= need else UITheme.DANGER))
		var gate := player.branch_gate(node)
		if gate > 0:
			var ok := player.branch_points(str(node.get("branch", ""))) - int(player.talents.get(str(node.id), 0)) >= gate
			_card.add_child(_wrapped(Loc.f("Requires %d points in this branch", [gate]), UITheme.GOOD if ok else UITheme.DANGER))
		var other := player.fork_sibling(node)
		if not other.is_empty():
			if player.node_rank(other) > 0:
				_card.add_child(_wrapped(Loc.f("Path closed: you chose %s", [_node_name(other)]), UITheme.DANGER))
			else:
				_card.add_child(_wrapped(Loc.f("Fork: this or %s", [_node_name(other)]), UITheme.GOLD))
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
			var txt2 := ("%+d%%" % roundi(now * 100.0)) if pct else ("%+d" % roundi(now))
			var c := UITheme.chip(str(UITheme.STAT_ICONS.get(st, "sil_star")), txt2, UITheme.GOOD if rank > 0 else UITheme.TEXT_DIM,
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
		v.custom_minimum_size = Vector2(190, 0)
		row.add_child(v)
		_card.add_child(row)
	# The flavour text stays, second and dimmer.
	var desc := Loc.t(str(node.get("description", "")))
	if kind == "skill":
		var sk: Dictionary = GameData.skills.get(str(node.skill), {})
		desc = Loc.t(str(sk.get("description", ""))) + (Loc.t("\nPassive: always active once learned.") if sk.get("passive", false) else Loc.t("\nLearn it, then slot it in the Skill Book."))
	_card.add_child(HSeparator.new())
	_card.add_child(_wrapped(desc, UITheme.TEXT_DIM))


func _wrapped(text: String, color: Color) -> Label:
	var l := UITheme.label(text, color, UITheme.FONT_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(196, 0)
	return l


## The tree's backdrop and lines: one tinted glass column per branch with its emblem faint in
## the middle, tier labels down the left (keystone tiers marked), and the prerequisite lines.
class TreeCanvas:
	extends Control
	var panel: Node
	var branch_rects: Dictionary = {}  ## branch id -> Rect2
	var branch_tints: Dictionary = {}  ## branch id -> Color
	var _divider: Texture2D
	var _fills: Dictionary = {}  ## node id -> 0..1 while its line fills in gold
	var _emblems: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = true

	func fill_line(id: String) -> void:
		_fills[id] = 0.0
		var tw := create_tween()
		tw.tween_method(func(v: float): _fills[id] = v; queue_redraw(), 0.0, 1.0, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): _fills.erase(id); queue_redraw())

	func _process(_delta: float) -> void:
		queue_redraw()  # available lines and keystones shimmer

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var f := UITheme.font()
		if _divider == null:
			_divider = UITheme.icon_tex("orn_divider")
		for bid in branch_rects:
			var r: Rect2 = branch_rects[bid]
			draw_style_box(UITheme.cached_glass(Color("0b0f19e6"), UITheme.EDGE, 1, 0), r)
			# The branch's colour rising from the top and fading down the tree.
			var tint: Color = branch_tints.get(bid, Color.BLACK)
			var g := r.grow(-1)
			draw_polygon(PackedVector2Array([g.position, g.position + Vector2(g.size.x, 0), g.end, Vector2(g.position.x, g.end.y)]),
					PackedColorArray([Color(tint, 0.55), Color(tint, 0.55), Color(tint, 0.0), Color(tint, 0.0)]))
			# A faint emblem behind the tree and a gilded rule under the heading.
			if not _emblems.has(bid):
				_emblems[bid] = UITheme.icon_tex("branch_" + str(bid))
			var em: Texture2D = _emblems[bid]
			if em:
				var es := Vector2(96, 96)
				draw_texture_rect(em, Rect2(r.get_center() - es / 2.0 + Vector2(0, 20), es), false, Color(1, 1, 1, 0.07))
			if _divider:
				var dw := minf(float(_divider.get_width()), r.size.x - 12.0)
				draw_texture_rect(_divider, Rect2(r.position + Vector2((r.size.x - dw) / 2.0, HEAD_H - 10), Vector2(dw, 14)), false, Color(1, 1, 1, 0.85))
		for tier in TIERS:
			var y := HEAD_H + (tier + 0.5) * ROW_H
			var key := tier == 2 or tier == 5
			var txt := "T%d" % tier
			draw_string(f, Vector2(2, y + 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, UITheme.GOLD_DIM if key else UITheme.TEXT_DIM)
			if key:
				var d := Vector2(10, y + 12)
				draw_colored_polygon(PackedVector2Array([d + Vector2(0, -3), d + Vector2(3, 0), d + Vector2(0, 3), d + Vector2(-3, 0)]), UITheme.GOLD_DIM)
		if panel == null:
			return
		# Lines: from the bottom of the prerequisite down to the child, elbowed at mid-row.
		var forks := {}
		for id in panel._buttons:
			var b: Control = panel._buttons[id][0]
			var nd: Dictionary = panel._buttons[id][1]
			for req in nd.get("requires", []):
				if not panel._buttons.has(str(req)):
					continue
				var a: Vector2 = panel.node_center(panel._buttons[str(req)][1])
				var c: Vector2 = panel.node_center(nd)
				var state := "locked"
				if b.closed:
					state = "closed"
				elif b.rank > 0 or b.free:
					state = "learned"
				elif b.can_learn or b.unlocked:
					state = "available"
				_line(a, c, state, t, float(_fills.get(id, 1.0)))
				if nd.has("exclusive"):
					var k := "%s|%s" % [req, nd.exclusive]
					forks[k] = forks.get(k, []) + [a.lerp(c, 0.5)]
		# The fork marker: an "or" diamond where two exclusive paths part.
		for k in forks:
			var pts: Array = forks[k]
			if pts.size() < 2:
				continue
			var m := (Vector2(pts[0]) + Vector2(pts[1])) / 2.0
			var or_txt := Loc.t("Or").to_lower()
			var w := f.get_string_size(or_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var hw := w / 2.0 + 6.0
			var dia := PackedVector2Array([m + Vector2(0, -7), m + Vector2(hw, 0), m + Vector2(0, 7), m + Vector2(-hw, 0)])
			draw_colored_polygon(dia, Color("0b0f19"))
			draw_polyline(dia + PackedVector2Array([dia[0]]), UITheme.GOLD_DIM, 1.0)
			draw_string(f, m + Vector2(-w / 2.0, 3), or_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.GOLD)

	func _line(a: Vector2, c: Vector2, state: String, t: float, fill: float) -> void:
		# Straight from the bottom of the prerequisite to the top of the node.
		var dir := (c - a).normalized()
		var pts := PackedVector2Array([a + dir * 20.0, c - dir * 20.0])
		match state:
			"learned":
				if fill < 1.0:
					# The fill runs from the prerequisite down to the new rank.
					draw_polyline(pts, Color(LOCKED, 1.0), 2.0)
					draw_polyline(_partial(pts, fill), Color(LEARNED, 0.35), 6.0)
					draw_polyline(_partial(pts, fill), Color(1.8, 1.4, 0.5), 2.0)
				else:
					draw_polyline(pts, Color(LEARNED, 0.22), 6.0)
					draw_polyline(pts, LEARNED, 2.0)
			"available":
				var p := 0.55 + 0.45 * sin(t * 4.0)
				draw_polyline(pts, Color(AVAILABLE, 0.18 * p), 6.0)
				draw_polyline(pts, Color(AVAILABLE, 0.55 + 0.35 * p), 1.5)
			"closed":
				draw_polyline(pts, Color(CLOSED, 0.8), 1.0)
			_:
				draw_polyline(pts, LOCKED, 1.5)

	func _partial(pts: PackedVector2Array, frac: float) -> PackedVector2Array:
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var want := total * frac
		var out := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			if want <= seg:
				out.append(pts[i].lerp(pts[i + 1], want / maxf(seg, 0.001)))
				return out
			want -= seg
			out.append(pts[i + 1])
		return out


## One talent: a square frame for skills, a round one for passives (rank pips below), a large
## gilded diamond for keystones. States: locked (dim, padlock), available (cyan pulse), learned
## (gold), maxed (gold, brighter, a star), closed by a fork (red cross).
class TalentNode:
	extends Button
	var node: Dictionary
	var icon_tex: Texture2D
	var rank := 0
	var free := false
	var unlocked := false
	var can_learn := false
	var closed := false
	var _t := 0.0
	var _flash := 0.0
	var _open_flash := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		var clear := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(s, clear)
		button_down.connect(func(): AudioManager.play_sfx("ui_press", 0.05))
		focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))

	func _kind() -> String:
		return str(node.get("type", "passive"))

	func learn_flash() -> void:
		_flash = 1.0
		var tw := create_tween()
		tw.tween_property(self, "_flash", 0.0, 0.6)

	func opened_flash() -> void:
		_open_flash = 1.0
		var tw := create_tween()
		tw.tween_property(self, "_open_flash", 0.0, 0.8)

	func _process(delta: float) -> void:
		_t += delta
		if can_learn or _flash > 0.0 or _open_flash > 0.0 or _kind() == "keystone" or has_focus():
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size.round())
		var c := r.get_center()
		var kind := _kind()
		var maxed := rank >= int(node.get("max_rank", 1))
		var learned := rank > 0 or free
		var edge := UITheme.EDGE
		if learned:
			edge = UITheme.GOLD if maxed else UITheme.GOLD_DIM
		elif closed:
			edge = CLOSED
		elif can_learn:
			edge = UITheme.CYAN.lerp(UITheme.CYAN_DIM, roundf((0.5 + 0.5 * sin(_t * 4.0)) * 3.0) / 3.0)
		var bg := Color("0a0e17") if unlocked or learned else Color("06080d")
		if is_hovered() or has_focus():
			bg = Color("16203a")
		var dim := Color.WHITE if unlocked or learned else Color(0.38, 0.4, 0.48)
		if closed:
			dim = Color(0.35, 0.25, 0.27)
		var isz := 28.0 if kind == "keystone" else 24.0
		var ir := Rect2(c - Vector2(isz, isz) / 2.0 + Vector2(0, -2), Vector2(isz, isz))
		match kind:
			"keystone":
				var h := r.size.x / 2.0 - 1.0
				var glow := 0.35 + 0.25 * sin(_t * 2.5) if learned or can_learn else 0.12
				draw_circle(c, h + 3.0, Color(UITheme.GOLD, glow * 0.25))
				var dia := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
				draw_colored_polygon(dia, bg)
				var ring := dia + PackedVector2Array([dia[0]])
				draw_polyline(ring, edge, 2.0)
				var inner := PackedVector2Array()
				for p in ring:
					inner.append(c + (p - c) * 0.82)
				draw_polyline(inner, Color(edge, 0.6), 1.0)
				# A spark circling a keystone that is learned or can be learned.
				if learned or can_learn:
					var a := _t * 2.0
					draw_circle(c + Vector2.from_angle(a) * (h + 1.0), 1.5, Color(1.0, 0.9, 0.5, 0.9))
			"passive":
				var rad := r.size.x / 2.0 - 2.0
				draw_circle(c, rad, bg)
				draw_arc(c, rad, 0.0, TAU, 28, edge, 2.0 if maxed else 1.5)
			_:
				draw_style_box(UITheme.cached_glass(bg, edge, 2 if maxed else 1, 0, UITheme.CYAN if can_learn else Color(0, 0, 0, 0)), r.grow(-2))
		if icon_tex:
			draw_texture_rect(icon_tex, ir, false, dim)
		else:
			var f := UITheme.font()
			var initials := ""
			for w in Loc.t(str(node.get("name", "?"))).split(" "):
				if not w.is_empty() and initials.length() < 2:
					initials += w[0]
			var tw := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			draw_string(f, Vector2(roundf(c.x - tw / 2.0), c.y + 4), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, UITheme.GOLD * dim)
		# Rank pips under ranked nodes.
		var mr := int(node.get("max_rank", 1))
		if mr > 1:
			var pw := 4.0
			var total := mr * pw + (mr - 1) * 2.0
			var x0 := roundf(c.x - total / 2.0)
			for i in mr:
				draw_rect(Rect2(x0 + i * (pw + 2.0), r.size.y - 4, pw, 3), UITheme.GOLD if i < rank else Color("1c2333"))
		if maxed and learned and not free and kind != "skill":
			draw_colored_polygon(_star(r.position + Vector2(r.size.x - 5, 5), 3.0), UITheme.GOLD)
		if closed:
			draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), Color(0.9, 0.25, 0.25, 0.8), 2.0)
			draw_line(c + Vector2(6, -6), c + Vector2(-6, 6), Color(0.9, 0.25, 0.25, 0.8), 2.0)
		elif not unlocked and not learned:
			var lc := Vector2(r.size.x - 9, 3)
			draw_rect(Rect2(lc + Vector2(1, 0), Vector2(4, 1)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(1, 0), Vector2(1, 3)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(4, 0), Vector2(1, 3)), UITheme.TEXT_DIM)
			draw_rect(Rect2(lc + Vector2(0, 3), Vector2(6, 4)), UITheme.TEXT_DIM)
		if has_focus():
			for k in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var corner: Vector2 = r.position + r.size * k
				var sx := 1.0 if k.x == 0.0 else -1.0
				var sy := 1.0 if k.y == 0.0 else -1.0
				draw_line(corner, corner + Vector2(5 * sx, 0), UITheme.GOLD, 1.0)
				draw_line(corner, corner + Vector2(0, 5 * sy), UITheme.GOLD, 1.0)
		# Learn flash: a white bloom and a ring spreading out; a newly opened node rings in cyan.
		if _flash > 0.0:
			draw_circle(c, r.size.x * 0.5, Color(1.0, 0.95, 0.7, 0.55 * _flash))
			draw_arc(c, r.size.x * (0.5 + 0.6 * (1.0 - _flash)), 0.0, TAU, 32, Color(1.6, 1.3, 0.5, _flash), 2.0)
		if _open_flash > 0.0:
			draw_arc(c, r.size.x * (0.5 + 0.4 * (1.0 - _open_flash)), 0.0, TAU, 32, Color(UITheme.CYAN, _open_flash), 2.0)

	func _star(p: Vector2, s: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in 10:
			var rr := s if i % 2 == 0 else s * 0.45
			out.append(p + Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * rr)
		return out
