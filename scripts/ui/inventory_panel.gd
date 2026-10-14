extends Control
## Inventory overlay: equipment slots, backpack grid, character stats and item details.
## Mouse or gamepad: Accept = equip / unequip (consumables: assign to Q),
## Secondary (RMB / X) = drop on the ground (that's how items are traded),
## Tertiary (R / Y) = assign a consumable to E.

signal closed

var player: Player
var _equip_grid: GridContainer
var _bag_grid: GridContainer
var _info: VBoxContainer
var _stats: Label
var _cap_label: Label
var _focus_key := ""
var _buttons: Dictionary = {}  ## key ("e:slot" / "b:index") -> Button
var _last_stats: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := HBoxContainer.new()
	root.position = Vector2(24, 20)
	root.size = Vector2(912, 500)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(250, 490)
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UITheme.label("Equipment", UITheme.ACCENT, 18))
	_equip_grid = GridContainer.new()
	_equip_grid.columns = 2
	_equip_grid.add_theme_constant_override("h_separation", 6)
	_equip_grid.add_theme_constant_override("v_separation", 4)
	lv.add_child(_equip_grid)
	lv.add_child(UITheme.label("Stats", UITheme.ACCENT, 16))
	_stats = UITheme.label("", UITheme.TEXT, 12)
	lv.add_child(_stats)

	var mid := PanelContainer.new()
	mid.custom_minimum_size = Vector2(330, 490)
	root.add_child(mid)
	var mv := VBoxContainer.new()
	mid.add_child(mv)
	var mh := HBoxContainer.new()
	mv.add_child(mh)
	mh.add_child(UITheme.label("Backpack", UITheme.ACCENT, 18))
	_cap_label = UITheme.label("", UITheme.TEXT_DIM, 13)
	mh.add_child(_cap_label)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 6
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	mv.add_child(_bag_grid)
	var help := UITheme.label("", UITheme.TEXT_DIM, 11)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(310, 0)
	help.text = "A/Enter/Click: equip, unequip, or put a potion on Q\nX/RMB: drop on the ground (give it to a teammate)\nY/R: put a potion on E\nB/Esc/I: close"
	mv.add_child(help)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 490)
	root.add_child(right)
	_info = VBoxContainer.new()
	right.add_child(_info)

	EventBus.local_inventory_changed.connect(_rebuild)
	_rebuild()


func _process(_delta: float) -> void:
	if player and is_instance_valid(player) and player.stats.final != _last_stats:
		_last_stats = player.stats.final.duplicate()
		_refresh_stats()


func _rebuild() -> void:
	if player == null or not is_instance_valid(player):
		return
	var inv: Inventory = player.inv
	_buttons.clear()
	for c in _equip_grid.get_children():
		c.queue_free()
	for c in _bag_grid.get_children():
		c.queue_free()
	for slot in Inventory.SLOTS:
		var item: Dictionary = inv.equipment.get(slot, {})
		if slot == "off_hand" and item.is_empty() and int(inv.equipment.get("main_hand", {}).get("hands", 1)) == 2:
			item = {"name": "(two-handed weapon)", "rarity": 1}
		var b := _item_button(item, Inventory.SLOT_NAMES[slot], Vector2(116, 40))
		b.pressed.connect(func(): player.request_unequip.rpc_id(1, slot))
		_bind(b, "e:" + slot, item, false, slot)
		_equip_grid.add_child(b)
	for i in inv.capacity:
		var item2: Dictionary = inv.backpack[i] if i < inv.backpack.size() else {}
		var b2 := _item_button(item2, "", Vector2(48, 48))
		var idx := i
		b2.pressed.connect(func(): _accept_backpack(idx))
		_bind(b2, "b:%d" % i, item2, true, str(i))
		_bag_grid.add_child(b2)
	_cap_label.text = "  %d / %d" % [inv.backpack.size(), inv.capacity]
	_wire_focus()
	_refresh_stats()
	var target: Button = _buttons.get(_focus_key, _buttons.get("b:0"))
	if target:
		target.grab_focus.call_deferred()


func _bind(b: Button, key: String, item: Dictionary, from_bag: bool, id: String) -> void:
	_buttons[key] = b
	b.focus_entered.connect(func():
		_focus_key = key
		_show_info(item))
	b.mouse_entered.connect(func(): _show_info(item))
	b.gui_input.connect(func(ev: InputEvent):
		if item.is_empty() or not item.has("uid"):
			return
		if ev.is_action_pressed("ui_secondary"):
			player.request_drop.rpc_id(1, from_bag, id)
			accept_event()
		elif ev.is_action_pressed("ui_tertiary") and item.get("kind") == "consumable":
			player.request_assign_quick.rpc_id(1, "e", item.base)
			accept_event())


func _accept_backpack(i: int) -> void:
	if i >= player.inv.backpack.size():
		return
	var item: Dictionary = player.inv.backpack[i]
	if item.get("kind") == "consumable":
		player.request_assign_quick.rpc_id(1, "q", item.base)
	else:
		player.request_equip.rpc_id(1, i)


func _item_button(item: Dictionary, caption: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	var border := Color(0.25, 0.2, 0.18)
	if not item.is_empty():
		border = Color.from_string(GameData.rarity(int(item.get("rarity", 1))).color, Color.WHITE)
	var sb := UITheme.box(Color(0.08, 0.07, 0.09), border.darkened(0.3), 2, 3, 2)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := UITheme.box(Color(0.16, 0.12, 0.12), border, 2, 3, 2)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.ACCENT, 3, 3, 2))
	if item.has("icon"):
		b.icon = GameData.texture(str(item.icon))
		b.expand_icon = true
	b.text = caption if item.is_empty() or not item.has("icon") else ""
	if caption != "" and item.has("icon"):
		b.text = ""
		b.tooltip_text = caption
	if item.get("kind") == "consumable":
		b.text = "x%d" % int(item.count)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 11)
	return b


func _wire_focus() -> void:
	# Let the gamepad cross from the equipment column to the backpack and back.
	var eq: Array = _equip_grid.get_children()
	var bag: Array = _bag_grid.get_children()
	if eq.is_empty() or bag.is_empty():
		return
	for i in range(1, eq.size(), 2):
		var target: Control = bag[mini((i / 2) * 6, bag.size() - 1)]
		eq[i].focus_neighbor_right = eq[i].get_path_to(target)
	for r in range(0, bag.size(), 6):
		var row := r / 6
		var e: Control = eq[mini(row * 2 + 1, eq.size() - 1)]
		bag[r].focus_neighbor_left = bag[r].get_path_to(e)


func _show_info(item: Dictionary) -> void:
	for c in _info.get_children():
		c.queue_free()
	if item.is_empty() or not item.has("uid"):
		_info.add_child(UITheme.label("Empty slot", UITheme.TEXT_DIM))
		return
	for line in ItemGenerator.describe(item, player.class_id):
		var l := UITheme.label(str(line[0]), line[1], 18 if _info.get_child_count() == 0 else 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(280, 0)
		_info.add_child(l)
	if item.get("kind") in ["weapon", "offhand", "armor", "jewelry"]:
		var eq := _equipped_for(item)
		if not eq.is_empty() and eq.uid != item.uid:
			_info.add_child(UITheme.label("", UITheme.TEXT_DIM, 6))
			_info.add_child(UITheme.label("Currently equipped:", UITheme.TEXT_DIM, 12))
			for line in ItemGenerator.describe(eq, player.class_id):
				var l2 := UITheme.label(str(line[0]), Color(line[1]).darkened(0.25), 12)
				l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l2.custom_minimum_size = Vector2(280, 0)
				_info.add_child(l2)


func _equipped_for(item: Dictionary) -> Dictionary:
	match str(item.slot):
		"weapon":
			return player.inv.equipment.get("main_hand", {})
		"offhand":
			return player.inv.equipment.get("off_hand", {})
		"ring":
			return player.inv.equipment.get("ring_1", {})
	return player.inv.equipment.get(str(item.slot), {})


func _refresh_stats() -> void:
	var s: Dictionary = player.stats.final
	if s.is_empty():
		return
	var lines := [
		"Level %d %s" % [player.level, player.class_def.name],
		"Health %d   %s %d" % [s.get("max_hp", 0), str(player.class_def.resource).capitalize(), s.get("max_resource", 0)],
		"Strength %d   Stamina %d" % [s.get("strength", 0), s.get("stamina", 0)],
		"Agility %d   Intellect %d" % [s.get("agility", 0), s.get("intellect", 0)],
		"Armor %d   Weapon DPS %.1f" % [s.get("armor", 0), s.get("weapon_dps", 0)],
		"Crit %d%%  Crit dmg +%d%%" % [roundi(float(s.get("crit_chance", 0)) * 100), roundi(float(s.get("crit_damage", 0)) * 100)],
		"Haste %d%%  Dodge %d%%  Leech %d%%" % [roundi(float(s.get("haste", 0)) * 100), roundi(float(s.get("dodge", 0)) * 100), roundi(float(s.get("leech", 0)) * 100)],
	]
	if bool(s.get("offclass", false)):
		lines.append("OFF-CLASS WEAPON: -%d%% damage, slower cooldowns" % roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100))
	_stats.text = "\n".join(lines)
