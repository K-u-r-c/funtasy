extends UIModal
## Malphas the Soul Broker (GDD 5.2-5.3): the floor's five stat contracts and its two pact potions
## (#95, seeded), all paid with run-permanent stat losses. Each row shows exactly what changes
## (before -> after for the hero's current stats). The host validates every bargain.

var merchants: Merchants
var _list: VBoxContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _last_sig := ""
var _seen: Dictionary = {}  ## keys stamped at the last rebuild (#94), to animate new ones
var marked := 0  ## stamps that arrived (tests)
var _built := false


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
	var focused := get_viewport().gui_get_focus_owner()
	var focus_key := str(focused.get_meta("key", "")) if focused and _list.is_ancestor_of(focused) else ""
	UITheme.clear(_list)
	_list.add_child(UITheme.section(Loc.t("Contracts"), "menu_save"))
	var pool: Array = GameData.merchants.get("malphas", {}).get("contracts", [])
	# #94: what this hero already signed / bought goes last, greyed and stamped.
	var slots: Array = range(merchants.contracts.size())
	slots.sort_custom(func(x, y):
		var sx: bool = merchants.my_signed.has(x)
		var sy: bool = merchants.my_signed.has(y)
		return x < y if sx == sy else sy)
	var just: Array = []
	for i in slots:
		var c: Dictionary = pool[int(merchants.contracts[i])]
		var b := _row("")
		# What it takes (red) and what it gives (green), each with its stat's icon (#29).
		b.add_child(_chips([[c.give, UITheme.DANGER]], 10, "menu_back", [[c.get, UITheme.GOOD]]))
		b.tooltip_text = Loc.f("Sacrifice %s  ->  gain %s", [Merchants.mod_text(c.give), Merchants.mod_text(c.get)])
		var slot: int = i
		b.set_meta("key", "c%d" % slot)
		b.pressed.connect(func(): merchants.request_contract.rpc_id(1, slot))
		b.focus_entered.connect(_show_mods.bind(Loc.t("Contract"), "", [c.give, c.get]))
		b.mouse_entered.connect(_show_mods.bind(Loc.t("Contract"), "", [c.give, c.get]))
		if merchants.my_signed.has(slot):
			_mark(b, Loc.t("Signed"))
			if _built and not _seen.has("c%d" % slot):
				just.append(b)
		_list.add_child(b)
	_list.add_child(UITheme.section(Loc.t("Pact potions"), "ui_potion"))
	var ids: Array = merchants.pacts.duplicate()
	ids.sort_custom(func(x, y):
		var sx: bool = merchants.my_pacts.has(x)
		var sy: bool = merchants.my_pacts.has(y)
		return merchants.pacts.find(x) < merchants.pacts.find(y) if sx == sy else sy)
	for pid in ids:
		var d: Dictionary = GameData.pact_consumables[pid]
		var b2 := _row(Loc.t(str(d.name)))
		b2.add_child(_chips(d.cost.map(func(c): return [c, UITheme.DANGER]), -1))
		b2.icon = GameData.texture(str(d.icon))
		b2.expand_icon = true
		b2.add_theme_constant_override("icon_max_width", 22)
		var id: String = pid
		b2.set_meta("key", "p" + id)
		b2.pressed.connect(func(): merchants.request_pact.rpc_id(1, id))
		b2.focus_entered.connect(_show_mods.bind(Loc.t(d.name), Loc.t(d.description), d.cost))
		b2.mouse_entered.connect(_show_mods.bind(Loc.t(d.name), Loc.t(d.description), d.cost))
		if merchants.my_pacts.has(id):
			_mark(b2, Loc.t("Bought"))
			if _built and not _seen.has("p" + id):
				just.append(b2)
		_list.add_child(b2)
	_seen.clear()
	for k in merchants.my_signed:
		_seen["c%d" % int(k)] = true
	for k2 in merchants.my_pacts:
		_seen["p" + str(k2)] = true
	var rows := _list.get_children().filter(func(c): return c is Button)
	var target: Button = null
	for r in rows:
		if str(r.get_meta("key", "")) == focus_key:
			target = r
	if target == null and not rows.is_empty():
		target = rows[0]
	if target:
		target.grab_focus.call_deferred()
		target.focus_entered.emit()
	_built = true
	for r2 in just:
		marked += 1
		(func(): if is_instance_valid(r2): UITheme.stamp_in(r2)).call_deferred()


## #94: a contract this hero signed / a potion it bought: greyed, stamped, not pressable again.
func _mark(b: Button, word: String) -> void:
	b.disabled = true
	b.self_modulate = Color(0.5, 0.5, 0.56)
	for c in b.get_children():
		c.modulate.a = 0.45
	b.add_child(UITheme.stamp(word, UITheme.GOLD))


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
