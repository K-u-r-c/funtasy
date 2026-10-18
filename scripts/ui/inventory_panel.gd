extends UIModal
## Inventory overlay: paper doll (equipment around a live portrait), backpack grid, Q/E quick
## slots, character stats and an item card with a comparison against the equipped item.
## Mouse: click = equip / unequip (potions: put on Q), drag and drop between the paper doll,
## the backpack and the quick slots, drag outside the window = drop on the ground, RMB = drop.
## Gamepad: A = equip / unequip, X = drop, Y = put a potion on E. Everything goes through the
## same host-validated intents.

const COLS := 6
const SLOT_PX := 40
const LEFT_SLOTS := ["head", "chest", "legs", "boots"]
const RIGHT_SLOTS := ["necklace", "ring_1", "ring_2", "gloves"]
const HAND_SLOTS := ["main_hand", "off_hand"]
## Silhouette of what each equipment slot takes, drawn while it is empty (#29).
const SLOT_ICONS := {"head": "slot_head", "chest": "slot_chest", "legs": "slot_legs", "boots": "slot_feet",
	"gloves": "slot_hands", "main_hand": "slot_main_hand", "off_hand": "slot_off_hand", "ring_1": "slot_ring",
	"ring_2": "slot_ring", "necklace": "slot_neck"}

var _slots: Dictionary = {}  ## key ("e:slot" / "b:index" / "q:q") -> ItemSlot
var _bag_grid: GridContainer
var _equip_root: HBoxContainer
var _hands: HBoxContainer
var _quick_row: HBoxContainer
var _card: VBoxContainer
var _stats: GridContainer
var _offclass: Label
var _cap_label: Label
var _dragging := false
var _portrait: CharacterPortrait
var _focus_key := ""


func save_state() -> Dictionary:
	return {"focus": _focus_key}
var _shown_key := ""
var _last_stats: Dictionary = {}
var _last_level := -1


func _init() -> void:
	title_text = Loc.t("Inventory")
	menu_tab = "inventory"


func _build() -> void:
	_focus_key = str(restore.get("focus", _focus_key))
	_cap_label = subtitle

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	content.add_child(body)

	# Paper doll + stats
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(UITheme.section(Loc.t("Equipment"), "slot_chest"))
	_equip_root = HBoxContainer.new()
	_equip_root.add_theme_constant_override("separation", 6)
	left.add_child(_equip_root)
	var lcol := _slot_column(LEFT_SLOTS)
	_equip_root.add_child(lcol)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	_equip_root.add_child(mid)
	_portrait = CharacterPortrait.new(false, 2)
	_portrait.actor = player
	_portrait.frame_color = UITheme.EDGE
	mid.add_child(_portrait)
	_hands = HBoxContainer.new()
	_hands.alignment = BoxContainer.ALIGNMENT_CENTER
	_hands.add_theme_constant_override("separation", 6)
	mid.add_child(_hands)
	for s in HAND_SLOTS:
		_hands.add_child(_make_equip_slot(s))
	_equip_root.add_child(_slot_column(RIGHT_SLOTS))
	left.add_child(UITheme.section(Loc.t("Attributes"), "nav_character"))
	_stats = GridContainer.new()
	_stats.columns = 8
	_stats.add_theme_constant_override("h_separation", 8)
	_stats.add_theme_constant_override("v_separation", 1)
	left.add_child(_stats)
	_offclass = UITheme.label("", UITheme.DANGER, UITheme.FONT_SMALL)
	left.add_child(_offclass)

	# Backpack + quick slots
	var bag := VBoxContainer.new()
	bag.add_theme_constant_override("separation", 6)
	body.add_child(bag)
	bag.add_child(UITheme.section(Loc.t("Backpack"), "slot_backpack"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLS * (SLOT_PX + 4) + 4, 4 * (SLOT_PX + 4))
	scroll.follow_focus = true
	bag.add_child(scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = COLS
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_bag_grid)
	bag.add_child(UITheme.section(Loc.t("Quick slots"), "ui_potion"))
	_quick_row = HBoxContainer.new()
	_quick_row.add_theme_constant_override("separation", 8)
	bag.add_child(_quick_row)
	for k in ["q", "e"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(InputGlyph.new("quick_" + k))
		var qs := ItemSlot.new(SLOT_PX)
		qs.slot_key = "q:" + k
		qs.placeholder = k.to_upper()
		qs.placeholder_icon = UITheme.icon_tex("slot_potion")
		qs.draggable = false
		qs.accepts = func(d: Dictionary) -> bool: return d.item.get("kind") == "consumable"
		qs.item_dropped.connect(func(d: Dictionary): player.request_assign_quick.rpc_id(1, k, d.item.base))
		qs.pressed.connect(func(): player.request_assign_quick.rpc_id(1, k, "__clear__"))
		qs.focus_entered.connect(_on_focus.bind(qs))
		qs.mouse_entered.connect(_show_card.bind(qs))
		_slots[qs.slot_key] = qs
		box.add_child(qs)
		_quick_row.add_child(box)

	# Item card
	var card_panel := PanelContainer.new()
	card_panel.theme_type_variation = &"GlassInset"
	card_panel.custom_minimum_size = Vector2(250, 0)
	card_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(card_panel)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 3)
	card_panel.add_child(_card)

	# Anything dragged out of the window and released over the backdrop is dropped on the ground.
	dim.set_drag_forwarding(Callable(), _can_drop_ground, _drop_ground)

	prompts = _prompts_for({})
	EventBus.local_inventory_changed.connect(_rebuild)
	_rebuild()


func _section(text: String) -> Label:
	var l := UITheme.label(text, UITheme.GOLD, UITheme.FONT_BODY)
	return l


func _slot_column(slots: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	for s in slots:
		col.add_child(_make_equip_slot(s))
	return col


func _make_equip_slot(slot: String) -> ItemSlot:
	var b := ItemSlot.new(SLOT_PX)
	b.slot_key = "e:" + slot
	b.placeholder = {"head": Loc.t("Head"), "chest": Loc.t("Chest"), "legs": Loc.t("Legs"), "boots": Loc.t("Feet"), "gloves": Loc.t("Hands"),
		"main_hand": Loc.t("Main"), "off_hand": Loc.t("Off"), "ring_1": Loc.t("Ring"), "ring_2": Loc.t("Ring"), "necklace": Loc.t("Neck")}.get(slot, "")
	b.placeholder_icon = UITheme.icon_tex(str(SLOT_ICONS.get(slot, "")))
	b.tooltip_text = Loc.t(Inventory.SLOT_NAMES[slot])
	b.accepts = func(d: Dictionary) -> bool: return str(d.from).begins_with("b:") and _fits(d.item, slot)
	b.item_dropped.connect(func(d: Dictionary): _try_equip(int(str(d.from).get_slice(":", 1)), b))
	b.pressed.connect(func(): player.request_unequip.rpc_id(1, slot))
	_wire(b)
	_slots[b.slot_key] = b
	return b


func _wire(b: ItemSlot) -> void:
	b.focus_entered.connect(_on_focus.bind(b))
	b.mouse_entered.connect(_show_card.bind(b))
	b.gui_input.connect(_slot_input.bind(b))


func _fits(item: Dictionary, slot: String) -> bool:
	match str(item.get("slot", "")):
		"weapon":
			return slot in HAND_SLOTS
		"offhand":
			return slot == "off_hand"
		"ring":
			return slot in ["ring_1", "ring_2"]
	return str(item.get("slot", "")) == slot


func _process(_delta: float) -> void:
	if player and is_instance_valid(player) and player.stats.final != _last_stats:
		_last_stats = player.stats.final.duplicate()
		_refresh_stats()
	var dragging := get_viewport().gui_is_dragging()
	if dragging and not _dragging:
		notice(Loc.t("Release outside the window to drop it on the ground"), UITheme.CYAN)
	_dragging = dragging
	if player and is_instance_valid(player) and player.level != _last_level:
		# Level-ups unlock gear: refresh the lock marks and the card.
		_last_level = player.level
		_rebuild()


# --- Contents --------------------------------------------------------------------------------


func _rebuild() -> void:
	if player == null or not is_instance_valid(player):
		return
	var inv: Inventory = player.inv
	for slot in Inventory.SLOTS:
		var b: ItemSlot = _slots["e:" + slot]
		var item: Dictionary = inv.equipment.get(slot, {})
		b.ghost_icon = null
		if slot == "off_hand" and item.is_empty() and int(inv.equipment.get("main_hand", {}).get("hands", 1)) == 2:
			b.ghost_icon = ItemLooks.icon(inv.equipment.main_hand)
		b.set_item(item)
	# Backpack slots are recreated only when the capacity changes.
	if _bag_grid.get_child_count() != inv.capacity:
		for c in _bag_grid.get_children():
			_slots.erase(c.slot_key)
			c.queue_free()
		for i in inv.capacity:
			var b2 := ItemSlot.new(SLOT_PX)
			b2.slot_key = "b:%d" % i
			var idx := i
			b2.accepts = func(d: Dictionary) -> bool: return str(d.from).begins_with("e:")
			b2.item_dropped.connect(func(d: Dictionary): player.request_unequip.rpc_id(1, str(d.from).get_slice(":", 1)))
			b2.pressed.connect(func(): _accept_backpack(idx))
			_wire(b2)
			_slots[b2.slot_key] = b2
			_bag_grid.add_child(b2)
	for i in inv.capacity:
		var bag_item: Dictionary = inv.backpack[i] if i < inv.backpack.size() else {}
		_slots["b:%d" % i].set_item(bag_item)
		_slots["b:%d" % i].locked = ItemGenerator.too_high_level(bag_item, player.level)
	for k in ["q", "e"]:
		var base_id: String = inv.quick.get(k, "")
		var qi: Dictionary = {}
		if not base_id.is_empty():
			qi = {"uid": "quick", "kind": "consumable", "base": base_id, "rarity": 1,
				"icon": GameData.consumables[base_id].icon, "count": inv.count_of(base_id),
				"name": GameData.consumables[base_id].name}
		_slots["q:" + k].set_item(qi)
	_cap_label.text = Loc.f("Backpack %d / %d", [inv.backpack.size(), inv.capacity])
	_wire_focus()
	_refresh_stats()
	var target: ItemSlot = _slots.get(_focus_key, _slots.get("b:0"))
	if target and not target.has_focus():
		target.grab_focus.call_deferred()
	elif target:
		_show_card(target)


## Explicit d-pad chains: left column <-> right column (across the portrait) <-> backpack
## <-> quick slots; hands sit under the columns. Edges stop instead of wrapping.
func _wire_focus() -> void:
	var l: Array = LEFT_SLOTS.map(func(k): return _slots["e:" + k])
	var r: Array = RIGHT_SLOTS.map(func(k): return _slots["e:" + k])
	var h: Array = HAND_SLOTS.map(func(k): return _slots["e:" + k])
	var bag: Array = _bag_grid.get_children()
	var q: ItemSlot = _slots["q:q"]
	var e: ItemSlot = _slots["q:e"]
	var rows := ceili(bag.size() / float(COLS))
	for i in l.size():
		_link(l[i], l[i], r[i], l[maxi(i - 1, 0)], l[i + 1] if i + 1 < l.size() else h[0])
		var bag_row: Control = bag[mini(i, rows - 1) * COLS] if not bag.is_empty() else q
		_link(r[i], l[i], bag_row, r[maxi(i - 1, 0)], r[i + 1] if i + 1 < r.size() else h[1])
	_link(h[0], h[0], h[1], l[-1], h[0])
	_link(h[1], h[0], q, r[-1], h[1])
	for i in bag.size():
		var row := i / COLS
		var col := i % COLS
		var left: Control = bag[i - 1] if col > 0 else r[mini(row, r.size() - 1)]
		var right: Control = bag[i + 1] if col < COLS - 1 and i + 1 < bag.size() else bag[i]
		var up: Control = bag[i - COLS] if row > 0 else bag[i]
		var down: Control = bag[i + COLS] if i + COLS < bag.size() else (q if col < COLS / 2 else e)
		_link(bag[i], left, right, up, down)
	var last_row := (rows - 1) * COLS
	_link(q, h[1], e, bag[last_row] if not bag.is_empty() else r[-1], q)
	_link(e, q, e, bag[mini(last_row + COLS / 2, bag.size() - 1)] if not bag.is_empty() else r[-1], e)


func _link(c: Control, left: Control, right: Control, up: Control, down: Control) -> void:
	c.focus_neighbor_left = c.get_path_to(left)
	c.focus_neighbor_right = c.get_path_to(right)
	c.focus_neighbor_top = c.get_path_to(up)
	c.focus_neighbor_bottom = c.get_path_to(down)
	c.focus_next = c.get_path_to(right if right != c else down)
	c.focus_previous = c.get_path_to(left if left != c else up)


func _accept_backpack(i: int) -> void:
	if i >= player.inv.backpack.size():
		return
	var item: Dictionary = player.inv.backpack[i]
	if item.get("kind") == "consumable":
		player.request_assign_quick.rpc_id(1, "q", item.base)
	elif item.get("kind") == "book":
		player.request_read_book.rpc_id(1, i)
	else:
		_try_equip(i, _slots["b:%d" % i])


## Equips backpack[i], or explains right away why the character can't wear it (the host
## checks again either way).
func _try_equip(i: int, from: ItemSlot) -> void:
	var item: Dictionary = player.inv.backpack[i] if i < player.inv.backpack.size() else {}
	if ItemGenerator.too_high_level(item, player.level):
		AudioManager.play_sfx("ui_error", 0.0)
		UIFx.flash(from, 0.6)
		notice(Loc.f("%s requires level %d - you are level %d", [item.get("name", Loc.t("This item")), int(item.req), player.level]))
		return
	player.request_equip.rpc_id(1, i)


func _slot_input(ev: InputEvent, b: ItemSlot) -> void:
	if not b.has_item() or b.slot_key.begins_with("q:"):
		return
	var from_bag := b.slot_key.begins_with("b:")
	if ev.is_action_pressed("ui_secondary"):
		AudioManager.play_sfx("ui_drop", 0.05)
		player.request_drop.rpc_id(1, from_bag, b.slot_key.get_slice(":", 1))
		accept_event()
	elif ev.is_action_pressed("ui_tertiary") and b.item.get("kind") == "consumable":
		player.request_assign_quick.rpc_id(1, "e", b.item.base)
		accept_event()


func _can_drop_ground(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == ItemSlot.DRAG_TYPE and not str(data.get("from")).begins_with("q:")


func _drop_ground(_at: Vector2, data: Variant) -> void:
	var from := str(data.from)
	AudioManager.play_sfx("ui_drop", 0.05)
	player.request_drop.rpc_id(1, from.begins_with("b:"), from.get_slice(":", 1))


# --- Item card + prompts ---------------------------------------------------------------------


func _on_focus(b: ItemSlot) -> void:
	_focus_key = b.slot_key
	_show_card(b)


func _show_card(b: ItemSlot) -> void:
	_shown_key = b.slot_key
	footer.set_prompts(_prompts_for(b.item, b.slot_key))
	for c in _card.get_children():
		c.queue_free()
	if not b.has_item():
		var eh := HBoxContainer.new()
		eh.add_theme_constant_override("separation", 6)
		var ei := UITheme.icon("", 32, Color(0.75, 0.82, 1.0, 0.45))
		ei.texture = b.placeholder_icon if b.placeholder_icon else UITheme.icon_tex("slot_backpack")
		eh.add_child(ei)
		eh.add_child(UITheme.label(Loc.t("Empty slot"), UITheme.TEXT_DIM))
		_card.add_child(eh)
		var hint := Loc.t("Drag an item here or pick one from the backpack.") if b.slot_key.begins_with("e:") \
				else (Loc.t("Drag a potion here to bind it.") if b.slot_key.begins_with("q:") else "")
		if not hint.is_empty():
			_card.add_child(_wrap(UITheme.label(hint, UITheme.TEXT_DIM, UITheme.FONT_SMALL)))
		return
	var item: Dictionary = b.item
	if b.slot_key.begins_with("q:"):
		item = {"name": item.name, "kind": "consumable", "base": item.base, "count": item.count, "rarity": 1}
	var lines := ItemGenerator.describe(item, player.class_id, player.level)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var icon := ItemSlot.new(SLOT_PX)
	icon.focus_mode = Control.FOCUS_NONE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draggable = false
	icon.item = b.item
	icon.locked = b.locked
	head.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.add_child(_wrap(UITheme.label(str(lines[0][0]), lines[0][1], UITheme.FONT_BODY)))
	if lines.size() > 1:
		names.add_child(_wrap(UITheme.label(str(lines[1][0]), UITheme.TEXT_DIM, UITheme.FONT_SMALL)))
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_card.add_child(head)
	if ItemGenerator.too_high_level(item, player.level):
		var warn := PanelContainer.new()
		warn.add_theme_stylebox_override("panel", UITheme.glass(Color("3a0c0cd8"), UITheme.DANGER, 1, 6))
		var wl := _wrap(UITheme.label(Loc.f("Level too low to equip: needs level %d (you are %d)", [int(item.get("req", 1)), player.level]), Color("ffb3a8"), UITheme.FONT_SMALL))
		warn.add_child(wl)
		_card.add_child(warn)
	_card.add_child(HSeparator.new())
	for i in range(2, lines.size()):
		_card.add_child(UITheme.card_line(lines[i], 234))
	if item.get("kind") in ["weapon", "offhand", "armor", "jewelry"] and b.slot_key.begins_with("b:"):
		# Compared with everything equipping it would take off (#11): a 2H weapon against both
		# hands, an off-hand item against a 2H weapon.
		var replaced: Array = player.inv.replaced_by(item)
		_card.add_child(HSeparator.new())
		if replaced.is_empty():
			_card.add_child(UITheme.label(Loc.t("Nothing equipped there"), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		else:
			var vs: Array = replaced.map(func(r): return Loc.item_name(r))
			var top := 1
			for r in replaced:
				top = maxi(top, int(r.get("rarity", 1)))
			_card.add_child(_wrap(UITheme.label(Loc.f("vs %s", [" + ".join(vs)]), UITheme.rarity_color(top), UITheme.FONT_SMALL)))
			for d in compare_lines(item, replaced):
				_card.add_child(UITheme.label(d[0], d[1], UITheme.FONT_SMALL))


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Stat changes if `item` replaced all of `replaced` (their stats are summed): [[text, color], ...].
static func compare_lines(item: Dictionary, replaced: Array) -> Array:
	var sum := {"dps": 0.0, "armor": 0.0, "stats": {}}
	for r in replaced:
		sum.dps += float(r.get("dps", 0.0))
		sum.armor += float(r.get("armor", 0.0))
		for k in r.get("stats", {}):
			sum.stats[k] = float(sum.stats.get(k, 0.0)) + float(r.stats[k])
	return _diff(item, sum)


## Stat changes if `item` replaced `eq`: [[text, color], ...] (green = gain, red = loss).
static func _diff(item: Dictionary, eq: Dictionary) -> Array:
	var out: Array = []
	var names: Dictionary = GameData.affixes.stat_names
	var pct: Array = GameData.affixes.percent_stats
	var keys: Array = ["dps", "armor"]
	for k in item.get("stats", {}):
		if not keys.has(k):
			keys.append(k)
	for k in eq.get("stats", {}):
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var a := float(item.get(k, item.get("stats", {}).get(k, 0.0)))
		var b := float(eq.get(k, eq.get("stats", {}).get(k, 0.0)))
		var d := a - b
		if absf(d) < 0.001:
			continue
		var label: String = Loc.t(str(names.get(k, k)))
		var txt := ""
		if pct.has(k):
			txt = "%+d%% %s" % [roundi(d * 100.0), label]
		elif k == "dps":
			txt = "%+.1f %s" % [d, label]
		else:
			txt = "%+d %s" % [roundi(d), label]
		out.append([txt, UITheme.GOOD if d > 0.0 else UITheme.DANGER])
	if out.is_empty():
		out.append([Loc.t("No stat change"), UITheme.TEXT_DIM])
	return out


func _prompts_for(item: Dictionary, key: String = "") -> Array:
	var out: Array = []
	var has := not item.is_empty() and item.has("uid")
	if key.begins_with("q:"):
		out.append(["ui_accept", Loc.t("Clear slot")])
	elif has and key.begins_with("e:"):
		out.append(["ui_accept", Loc.t("Unequip")])
		out.append(["ui_secondary", Loc.t("Drop")])
	elif has and item.get("kind") == "book":
		out.append(["ui_accept", Loc.t("Read")])
		out.append(["ui_secondary", Loc.t("Drop")])
	elif has and item.get("kind") == "consumable":
		out.append(["ui_accept", Loc.t("Put on Q")])
		out.append(["ui_tertiary", Loc.t("Put on E")])
		out.append(["ui_secondary", Loc.t("Drop")])
	elif has and ItemGenerator.too_high_level(item, player.level):
		out.append(["ui_accept", Loc.f("Equip (needs level %d)", [int(item.get("req", 1))])])
		out.append(["ui_secondary", Loc.t("Drop")])
	elif has:
		out.append(["ui_accept", Loc.t("Equip")])
		out.append(["ui_secondary", Loc.t("Drop")])
	out.append(["ui_cancel", Loc.t("Close")])
	return out


func _refresh_stats() -> void:
	var s: Dictionary = player.stats.final
	if s.is_empty():
		return
	for c in _stats.get_children():
		c.queue_free()
	var rows := [
		["Health", "%d" % s.get("max_hp", 0)], [str(player.class_def.resource).capitalize(), "%d" % s.get("max_resource", 0)],
		["Strength", "%d" % s.get("strength", 0)], ["Stamina", "%d" % s.get("stamina", 0)],
		["Agility", "%d" % s.get("agility", 0)], ["Intellect", "%d" % s.get("intellect", 0)],
		["Armor", "%d" % s.get("armor", 0)], ["DPS", "%.1f" % s.get("weapon_dps", 0)],
		["Crit", "%d%%" % roundi(float(s.get("crit_chance", 0)) * 100)], ["Crit dmg", "+%d%%" % roundi(float(s.get("crit_damage", 0)) * 100)],
		["Haste", "%d%%" % roundi(float(s.get("haste", 0)) * 100)], ["Dodge", "%d%%" % roundi(float(s.get("dodge", 0)) * 100)],
		["Leech", "%d%%" % roundi(float(s.get("leech", 0)) * 100)], ["Level", "%d" % player.level],
	]
	# Icon + value, the stat's name on hover (#29).
	var icons := {"Health": "hud_health", "Mana": "stat_mana", "Fury": "stat_fury", "Strength": "stat_strength",
		"Stamina": "stat_stamina", "Agility": "stat_agility", "Intellect": "stat_intellect", "Armor": "stat_armor",
		"DPS": "stat_weapon_dps", "Crit": "stat_crit_chance", "Crit dmg": "stat_crit_damage", "Haste": "stat_haste",
		"Dodge": "stat_dodge", "Leech": "stat_leech", "Level": "ui_crown"}
	for r in rows:
		var ic := UITheme.icon(str(icons.get(r[0], "sil_star")), 16)
		ic.tooltip_text = Loc.t(r[0])
		_stats.add_child(ic)
		var v := UITheme.label(r[1], UITheme.TEXT, UITheme.FONT_SMALL)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(34, 0)
		v.tooltip_text = Loc.t(r[0])
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		_stats.add_child(v)
	_offclass.text = Loc.f("Off-class weapon: -%d%% damage, slower cooldowns", [roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100)]) \
			if bool(s.get("offclass", false)) else ""
