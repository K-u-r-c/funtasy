extends UIModal
## Archibald the Gilded's shop (GDD 5.1): the floor's shared stock on the left (buy), the
## local hero's backpack on the right (sell). Accept / click buys or sells the focused row;
## the host validates every trade (Merchants.request_buy / request_sell) and the stock change
## reaches every player, so an item bought by one teammate disappears for the others.

var merchants: Merchants
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _card: VBoxContainer
var _last_sig := ""


func _init() -> void:
	title_text = "Archibald the Gilded"
	fill_height = true
	prompts = [["ui_accept", "Buy / sell"], ["ui_cancel", "Leave"]]


func _build() -> void:
	merchants = get_tree().get_first_node_in_group("game").merchants
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_buy_list = _column(body, "For sale (shared with the party)")
	_sell_list = _column(body, "Your backpack - sell")
	var cardp := PanelContainer.new()
	cardp.theme_type_variation = &"GlassInset"
	cardp.custom_minimum_size = Vector2(230, 0)
	body.add_child(cardp)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 3)
	cardp.add_child(_card)
	merchants.changed.connect(_rebuild)
	EventBus.local_inventory_changed.connect(_rebuild)
	_rebuild()


func _column(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	col.add_child(UITheme.label(title, UITheme.GOLD, UITheme.FONT_BODY))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	return list


func _process(_delta: float) -> void:
	var sig := "%d|%d" % [player.gold, player.inv.backpack.size()]
	if sig != _last_sig:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_last_sig = "%d|%d" % [player.gold, player.inv.backpack.size()]
	subtitle.text = "Gold: %d" % player.gold
	var focus_idx := -1
	var focused := get_viewport().gui_get_focus_owner()
	var rows: Array = _buy_list.get_children() + _sell_list.get_children()
	if focused in rows:
		focus_idx = rows.find(focused)
	for c in _buy_list.get_children() + _sell_list.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	for i in merchants.stock.size():
		var e: Dictionary = merchants.stock[i]
		var sold_out := int(e.left) <= 0
		var txt := "%s%s  -  %d g" % [e.item.get("name", "?"), "  x%d" % int(e.left) if int(e.left) > 1 else "", int(e.price)]
		if sold_out:
			txt = "%s  -  sold out" % e.item.get("name", "?")
		var b := _row(txt, e.item, sold_out or player.gold < int(e.price))
		var idx: int = i
		b.pressed.connect(func(): merchants.request_buy.rpc_id(1, idx))
		_buy_list.add_child(b)
	for j in player.inv.backpack.size():
		var it: Dictionary = player.inv.backpack[j]
		var price := Merchants.sell_price(it)
		var b2 := _row("%s  -  %s" % [it.get("name", "?"), "%d g" % price if price > 0 else "not wanted"], it, price <= 0)
		var bj: int = j
		b2.pressed.connect(func(): merchants.request_sell.rpc_id(1, bj))
		_sell_list.add_child(b2)
	if _sell_list.get_child_count() == 0:
		_sell_list.add_child(UITheme.label("Nothing to sell.", UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	var all: Array = _buy_list.get_children() + _sell_list.get_children()
	all = all.filter(func(c): return c is Button)
	if not all.is_empty():
		all[clampi(focus_idx, 0, all.size() - 1)].grab_focus.call_deferred()


func _row(text: String, item: Dictionary, dim: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.custom_minimum_size = Vector2(250, 30)
	if GameData.asset_exists(str(item.get("icon", ""))):
		b.icon = GameData.texture(str(item.icon))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 24)
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	b.add_theme_color_override("font_color", Color.from_string(rar.color, Color.WHITE).darkened(0.35 if dim else 0.0))
	b.focus_entered.connect(_show.bind(item))
	b.mouse_entered.connect(_show.bind(item))
	return b


func _show(item: Dictionary) -> void:
	for c in _card.get_children():
		c.queue_free()
	for line in ItemGenerator.describe(item, player.class_id, player.level):
		var l := UITheme.label(str(line[0]), line[1], UITheme.FONT_SMALL)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(214, 0)
		_card.add_child(l)
