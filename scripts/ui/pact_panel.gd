extends UIModal
## Malphas the Soul Broker (GDD 5.2-5.3): two stat contracts of this floor and the ten pact
## potions, all paid with run-permanent stat losses. Each row shows exactly what changes
## (before -> after for the hero's current stats). The host validates every bargain.

var merchants: Merchants
var _list: VBoxContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _last_sig := ""


func _init() -> void:
	title_text = Loc.t("Malphas the Soul Broker")
	title_icon = "stat_leech"
	fill_height = true
	prompts = [["ui_accept", Loc.t("Make the pact")], ["ui_cancel", Loc.t("Leave")]]


func _build() -> void:
	merchants = get_tree().get_first_node_in_group("game").merchants
	subtitle.text = Loc.t("Every price is paid in flesh - for the rest of the run")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	# The card keeps its size; a long text scrolls inside it (#85).
	var cardp := UITheme.scroll_card(270)
	body.add_child(cardp)
	_card = cardp.get_meta("content")
	_card_scroll = cardp.get_meta("scroll")
	merchants.changed.connect(_rebuild)
	_rebuild()


## A right-aligned row of stat chips (icon + signed value) over a list row; `arrow_icon` between
## the first group and `then` (contracts: give -> get). `left` > 0 pins it to the row's left.
func _chips(first: Array, left: int, arrow_icon := "", then: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if left > 0:
		h.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		h.offset_left = left
	else:
		h.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		h.offset_left = -260
		h.offset_right = -8
		h.alignment = BoxContainer.ALIGNMENT_END
	h.offset_top = -13
	h.offset_bottom = 13
	var add := func(group: Array) -> void:
		for g in group:
			var m: Dictionary = g[0]
			var st := str(m.stat).trim_suffix("_pct")
			var chip := UITheme.chip(str(UITheme.STAT_ICONS.get(st, "sil_star")), Merchants.mod_text(m).split(" ")[0], g[1], Color(g[1], 0.5))
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(chip)
	add.call(first)
	if not then.is_empty():
		var arrow := UITheme.icon(arrow_icon, 16)
		arrow.flip_h = true
		h.add_child(arrow)
		add.call(then)
	return h


func _process(delta: float) -> void:
	# The hero can be freed before the window when a session ends.
	if not is_instance_valid(player):
		return
	UITheme.stick_scroll(_card_scroll, delta)
	if str(player.run_mods.size()) != _last_sig:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_last_sig = str(player.run_mods.size())
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(UITheme.section(Loc.t("Contracts"), "menu_save"))
	var pool: Array = GameData.merchants.get("malphas", {}).get("contracts", [])
	for i in merchants.contracts.size():
		var c: Dictionary = pool[int(merchants.contracts[i])]
		var b := _row("")
		# What it takes (red) and what it gives (green), each with its stat's icon (#29).
		b.add_child(_chips([[c.give, UITheme.DANGER]], 10, "menu_back", [[c.get, UITheme.GOOD]]))
		b.tooltip_text = Loc.f("Sacrifice %s  ->  gain %s", [Merchants.mod_text(c.give), Merchants.mod_text(c.get)])
		var slot: int = i
		b.pressed.connect(func(): merchants.request_contract.rpc_id(1, slot))
		b.focus_entered.connect(_show_mods.bind(Loc.t("Contract"), "", [c.give, c.get]))
		b.mouse_entered.connect(_show_mods.bind(Loc.t("Contract"), "", [c.give, c.get]))
		_list.add_child(b)
	_list.add_child(UITheme.section(Loc.t("Pact potions"), "ui_potion"))
	var ids: Array = GameData.pact_consumables.keys()
	for pid in ids:
		var d: Dictionary = GameData.pact_consumables[pid]
		var b2 := _row(Loc.t(str(d.name)))
		b2.add_child(_chips(d.cost.map(func(c): return [c, UITheme.DANGER]), -1))
		b2.icon = GameData.texture(str(d.icon))
		b2.expand_icon = true
		b2.add_theme_constant_override("icon_max_width", 22)
		var id: String = pid
		b2.pressed.connect(func(): merchants.request_pact.rpc_id(1, id))
		b2.focus_entered.connect(_show_mods.bind(Loc.t(d.name), Loc.t(d.description), d.cost))
		b2.mouse_entered.connect(_show_mods.bind(Loc.t(d.name), Loc.t(d.description), d.cost))
		_list.add_child(b2)
	var first := _list.get_children().filter(func(c): return c is Button)
	if not first.is_empty():
		first[0].grab_focus.call_deferred()
		first[0].focus_entered.emit()


func _row(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.custom_minimum_size = Vector2(320, 32)
	return b


## The card: what the bargain does and the exact before -> after of every stat it touches.
func _show_mods(title: String, desc: String, mods: Array) -> void:
	UITheme.clear(_card)
	_card_scroll.scroll_vertical = 0
	_card.add_child(UITheme.card_line([title, UITheme.GOLD], 240))
	if not desc.is_empty():
		_card.add_child(UITheme.card_line([desc, UITheme.TEXT], 240))
	_card.add_child(HSeparator.new())
	var after := _preview(mods)
	for m in mods:
		var k := _final_key(str(m.stat))
		var before := player.stats.get_stat(k)
		var aft := float(after.get(k, before))
		var col := UITheme.GOOD if aft > before else UITheme.DANGER
		_card.add_child(UITheme.card_line(["%s: %s -> %s" % [Merchants.stat_name(str(m.stat)), _fmt(k, before), _fmt(k, aft)], col], 240))


## Stats as they would be with the extra run modifiers (same Stats code as the host).
func _preview(mods: Array) -> Dictionary:
	var st := Stats.new()
	var extra := player.stat_extra()
	extra.run_mods = player.run_mods + mods
	st.compute_player(player.class_def, player.level, player.inv.equipment, player.talents, player.status.stat_mods(), extra)
	var out := st.final
	st.free()
	return out


static func _final_key(stat: String) -> String:
	return "max_hp" if stat == "max_hp_pct" else stat


static func _fmt(k: String, v: float) -> String:
	if k in ["crit_chance", "dodge", "haste", "leech"]:
		return "%.1f%%" % (v * 100.0)
	return "%d" % roundi(v)
