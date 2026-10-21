class_name UiStableSuite
extends RefCounted
## #85 long texts scroll instead of stretching the UI (scenario "ui_stable", run in English and in
## Polish, on a forge floor). The hero carries the item with the longest name and card, stacks of
## potions and gear, and talent points. Every game screen and trade window (character, inventory,
## talents, skill book, codex, Archibald, Malphas, the forge) is opened and every row, slot, talent
## and badge in it hovered and focused in turn: the window and the layout around the cards keep
## their size and place on every frame (one frame after each change and after the layout settles).
## The talent book: a click selects a talent without learning it, hovering another shows that one
## only while hovered, the card scrolls, the Learn button and a double-click learn.

var da: Node
var g: Node
var p: Player
var hud: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Window rect and the rects of the layout down to `depth` levels under the window's content (the
## cards' own text sits deeper and may change).
static func layout_rects(panel: Control, depth: int = 3) -> Dictionary:
	var out := {"window": panel.window.get_global_rect()}
	var stack: Array = [[panel.content, 0]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		if n is Control and (n as Control).is_visible_in_tree():
			out[str(panel.content.get_path_to(n))] = (n as Control).get_global_rect()
		# What sits inside a scroll area moves when it scrolls: the area itself must not.
		if int(e[1]) < depth and not n is ScrollContainer:
			for c in n.get_children():
				if c is Control:
					stack.append([c, int(e[1]) + 1])
	return out


static func diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a:
		if b.has(k) and not (Rect2(a[k]).position.distance_to(Rect2(b[k]).position) < 1.0 and Rect2(a[k]).size.distance_to(Rect2(b[k]).size) < 1.0):
			out.append("%s %s -> %s" % [k, a[k], b[k]])
	return out


## Hover / focus every control in `targets` of the open panel; the layout must not move.
func _sweep(what: String, targets: Array) -> void:
	var panel: Control = hud._overlay
	await da._wait(0.5)
	var base := layout_rects(panel)
	var moved: Array = []
	var n := 0
	for t in targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		n += 1
		for step in ["mouse", "focus"]:
			if step == "mouse":
				t.mouse_entered.emit()
			elif t.focus_mode != Control.FOCUS_NONE:
				t.grab_focus()
			else:
				continue
			await da.get_tree().process_frame
			moved.append_array(diff(base, layout_rects(panel)).map(func(x): return "%s (1st frame): %s" % [step, x]))
			await da.get_tree().process_frame
			await da.get_tree().process_frame
			moved.append_array(diff(base, layout_rects(panel)).map(func(x): return "%s: %s" % [step, x]))
			if step == "mouse":
				t.mouse_exited.emit()
		if moved.size() > 3:
			break
	for m in moved.slice(0, 4):
		da.log_line("MOVED %s: %s" % [what, m])
	da.check(n > 0 and moved.is_empty(), "%s (%s): hovering and focusing %d entries never moves or resizes the layout%s" % [what, Settings.language, n, "" if moved.is_empty() else " (%s)" % moved[0]])


func _buttons_under(root: Node, cls: Variant = null) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Control and nd != root and ((cls == null and (nd is BaseButton or nd is Badge)) or (cls != null and is_instance_of(nd, cls))):
			out.append(nd)
		stack.append_array(nd.get_children())
	return out


func run() -> void:
	g = da._game()
	p = da._local()
	hud = da.get_tree().get_first_node_in_group("hud")
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 85
	# The longest legendary (name and card) and a full backpack of mixed things.
	var best: Dictionary = {}
	var best_n := 0
	for id in GameData.legendaries:
		var it := ItemGenerator.make_legendary(str(id), 30, rng)
		var n := Loc.item_name(it).length() + JSON.stringify(ItemGenerator.describe(it, p.class_id, p.level)).length()
		if n > best_n:
			best_n = n
			best = it
	p.host_give_item(best)
	p.inv.add(ItemGenerator.generate_consumable("potion_health", 5, rng))
	p.inv.add(ItemGenerator.generate_consumable("potion_mana", 3, rng))
	for i in 6:
		p.host_give_item(ItemGenerator.generate_equipment(LootTable.pick_base([p.class_id], rng), 20, rng.randi_range(1, 5), rng))
	p.host_add_gold(5000)
	p.talent_points = 12
	p._inventory_changed()
	await da._wait(0.5)
	for t in UIModal.MENU_TABS:
		if t[0] == "map":
			continue
		hud.open_overlay(hud.menu_panel(t[0]))
		await da._wait(0.6)
		var panel: Control = hud._overlay
		var targets: Array = []
		match t[0]:
			"inventory":
				targets = panel._slots.values()
			"talents":
				targets = panel._buttons.values().map(func(x): return x[0])
			_:
				targets = _buttons_under(panel.content)
		await _sweep("the %s screen" % t[0], targets)
		if t[0] == "talents":
			await _talent_pin(panel)
		if t[0] == "inventory":
			var sc: ScrollContainer = panel._card_scroll
			for k in panel._slots:
				if panel._slots[k].get("item") is Dictionary and str(panel._slots[k].item.get("uid", "")) == str(best.get("uid", "")):
					panel._slots[k].grab_focus()
			await da._wait(0.3)
			da.check(sc.get_v_scroll_bar().max_value <= sc.size.y + 1.0 or sc.get_v_scroll_bar().visible,
					"the inventory card scrolls a long item instead of growing (%s)" % Settings.language)
	hud.close_overlay()
	await da._wait(0.3)
	for ps in [hud.ShopPanel, hud.PactPanel, hud.ForgePanel]:
		if ps == hud.ForgePanel and g.get("forge") == null:
			continue
		hud.open_overlay(ps.new())
		await da._wait(0.6)
		await _sweep("the %s" % str(ps.resource_path.get_file().get_basename()), _buttons_under(hud._overlay.content))
		hud.close_overlay()
		await da._wait(0.3)


## #85: click selects (no learning), hover is temporary, the card scrolls, Learn learns.
func _talent_pin(panel: Control) -> void:
	var ids: Array = panel._buttons.keys()
	var a := ""
	var b := ""
	for id in ids:
		if a.is_empty() and panel._buttons[id][0].can_learn:
			a = id
		elif b.is_empty() and id != a:
			b = id
	if a.is_empty() or b.is_empty():
		da.check(false, "two talents to compare")
		return
	var na: Control = panel._buttons[a][0]
	var nb: Control = panel._buttons[b][0]
	var before := p.talents.duplicate()
	var pts := p.talent_points
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	na._gui_input(click)
	await da._wait(0.3)
	da.check(na.has_focus() and str(panel._card.get_meta("node_id", "")) == a and p.talents == before and p.talent_points == pts,
			"a click selects the talent and shows its card without learning it")
	nb.mouse_entered.emit()
	await da.get_tree().process_frame
	da.check(str(panel._card.get_meta("node_id", "")) == b, "hovering another talent shows its card while hovered")
	nb.mouse_exited.emit()
	await da.get_tree().process_frame
	da.check(str(panel._card.get_meta("node_id", "")) == a and na.has_focus(), "leaving it brings back the selected talent's card")
	# The longest card scrolls (the wheel / stick move it) and the panel keeps its width.
	var longest := ""
	var ln := 0
	for id in ids:
		var n := JSON.stringify(TalentInfo.rows(p, panel._buttons[id][1])).length() + str(panel._buttons[id][1].get("description", "")).length()
		if n > ln:
			ln = n
			longest = id
	panel._buttons[longest][0].mouse_entered.emit()
	await da._wait(0.2)
	var sc: ScrollContainer = panel._card_scroll
	sc.scroll_vertical = 10000
	await da.get_tree().process_frame
	da.check(sc.scroll_vertical > 0 or sc.get_v_scroll_bar().max_value <= sc.size.y + 1.0, "the talent card scrolls a long description (%d px)" % sc.scroll_vertical)
	panel._buttons[longest][0].mouse_exited.emit()
	await da.get_tree().process_frame
	da.check(not panel._learn.disabled, "the Learn button is ready for the selected talent")
	panel._learn.pressed.emit()
	await da._wait(0.5)
	da.check(int(p.talents.get(a, 0)) > int(before.get(a, 0)) and p.talent_points == pts - 1, "the Learn button learns a rank of the selected talent")
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	var r0 := int(p.talents.get(a, 0))
	if na.can_learn:
		na._gui_input(dbl)
		await da._wait(0.5)
		da.check(int(p.talents.get(a, 0)) == r0 + 1, "a double-click learns a rank")
