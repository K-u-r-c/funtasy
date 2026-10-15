extends UIModal
## Malphas the Soul Broker (GDD 5.2-5.3): two stat contracts of this floor and the ten pact
## potions, all paid with run-permanent stat losses. Each row shows exactly what changes
## (before -> after for the hero's current stats). The host validates every bargain.

var merchants: Merchants
var _list: VBoxContainer
var _card: VBoxContainer
var _last_sig := ""


func _init() -> void:
	title_text = "Malphas the Soul Broker"
	fill_height = true
	prompts = [["ui_accept", "Make the pact"], ["ui_cancel", "Leave"]]


func _build() -> void:
	merchants = get_tree().get_first_node_in_group("game").merchants
	subtitle.text = "Every price is paid in flesh - for the rest of the run"
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
	var cardp := PanelContainer.new()
	cardp.theme_type_variation = &"GlassInset"
	cardp.custom_minimum_size = Vector2(260, 0)
	body.add_child(cardp)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 3)
	cardp.add_child(_card)
	merchants.changed.connect(_rebuild)
	_rebuild()


func _process(_delta: float) -> void:
	if str(player.run_mods.size()) != _last_sig:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_last_sig = str(player.run_mods.size())
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(UITheme.label("Contracts", UITheme.GOLD, UITheme.FONT_BODY))
	var pool: Array = GameData.merchants.get("malphas", {}).get("contracts", [])
	for i in merchants.contracts.size():
		var c: Dictionary = pool[int(merchants.contracts[i])]
		var b := _row("Sacrifice %s  ->  gain %s" % [Merchants.mod_text(c.give), Merchants.mod_text(c.get)])
		var slot: int = i
		b.pressed.connect(func(): merchants.request_contract.rpc_id(1, slot))
		b.focus_entered.connect(_show_mods.bind("Contract", "", [c.give, c.get]))
		b.mouse_entered.connect(_show_mods.bind("Contract", "", [c.give, c.get]))
		_list.add_child(b)
	_list.add_child(UITheme.label("Pact potions", UITheme.GOLD, UITheme.FONT_BODY))
	var ids: Array = GameData.pact_consumables.keys()
	for pid in ids:
		var d: Dictionary = GameData.pact_consumables[pid]
		var b2 := _row("%s  -  costs %s" % [d.name, ", ".join(d.cost.map(func(c): return Merchants.mod_text(c)))])
		b2.icon = GameData.texture(str(d.icon))
		b2.expand_icon = true
		b2.add_theme_constant_override("icon_max_width", 22)
		var id: String = pid
		b2.pressed.connect(func(): merchants.request_pact.rpc_id(1, id))
		b2.focus_entered.connect(_show_mods.bind(d.name, d.description, d.cost))
		b2.mouse_entered.connect(_show_mods.bind(d.name, d.description, d.cost))
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
	b.custom_minimum_size = Vector2(320, 28)
	return b


## The card: what the bargain does and the exact before -> after of every stat it touches.
func _show_mods(title: String, desc: String, mods: Array) -> void:
	for c in _card.get_children():
		c.queue_free()
	_card.add_child(UITheme.label(title, UITheme.GOLD, UITheme.FONT_BODY))
	if not desc.is_empty():
		var d := UITheme.label(desc, UITheme.TEXT, UITheme.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(244, 0)
		_card.add_child(d)
	_card.add_child(HSeparator.new())
	var after := _preview(mods)
	for m in mods:
		var k := _final_key(str(m.stat))
		var before := player.stats.get_stat(k)
		var aft := float(after.get(k, before))
		var col := UITheme.GOOD if aft > before else UITheme.DANGER
		_card.add_child(UITheme.label("%s: %s -> %s" % [Merchants.stat_name(str(m.stat)), _fmt(k, before), _fmt(k, aft)], col, UITheme.FONT_SMALL))


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
