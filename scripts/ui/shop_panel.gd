extends UIModal
## Archibald the Gilded's shop (GDD 5.1): the floor's shared stock on the left (buy), the
## local hero's backpack on the right (sell). Accept / click buys or sells the focused row;
## the host validates every trade (Merchants.request_buy / request_sell) and the stock change
## reaches every player, so an item bought by one teammate disappears for the others.

var merchants: Merchants
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _last_sig := ""
var _gold_chip: PanelContainer


func _init() -> void:
	title_text = Loc.t("Archibald the Gilded")
	title_icon = "hud_merchant"
	fill_height = true
	prompts = [["ui_accept", Loc.t("Buy / sell")], ["ui_cancel", Loc.t("Leave")]]


func _build() -> void:
	merchants = get_tree().get_first_node_in_group("game").merchants
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_buy_list = _column(body, Loc.t("For sale (shared with the party)"), "hud_chest")
	_sell_list = _column(body, Loc.t("Your backpack - sell"), "slot_backpack")
	_gold_chip = UITheme.chip("hud_gold", "", UITheme.GOLD, UITheme.GOLD_DIM)
	_gold_chip.tooltip_text = Loc.t("Your gold")
	_gold_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_gold_chip)
	# The item card keeps its size; a long item scrolls inside it (#85).
	var cardp := UITheme.scroll_card(240)
	body.add_child(cardp)
	_card = cardp.get_meta("content")
	_card_scroll = cardp.get_meta("scroll")
	merchants.changed.connect(_rebuild)
	EventBus.local_inventory_changed.connect(_rebuild)
	_rebuild()


func _column(parent: Control, title: String, icon_key: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	col.add_child(UITheme.section(title, icon_key))
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


func _process(delta: float) -> void:
	# The hero can be freed before the window when a session ends.
	if not is_instance_valid(player):
		return
	UITheme.stick_scroll(_card_scroll, delta)
	var sig := "%d|%d" % [player.gold, player.inv.backpack.size()]
	if sig != _last_sig:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_last_sig = "%d|%d" % [player.gold, player.inv.backpack.size()]
	subtitle.text = Loc.f("Gold: %d", [player.gold])
	subtitle.visible = false  # the gold chip shows it
	_gold_chip.get_meta("label").text = str(player.gold)
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
		var txt := "%s%s" % [Loc.item_name(e.item), "  x%d" % int(e.left) if int(e.left) > 1 else ""]
		var b := _row(txt, e.item, sold_out or player.gold < int(e.price), -1 if sold_out else int(e.price), player.gold >= int(e.price))
		var idx: int = i
		b.pressed.connect(func(): merchants.request_buy.rpc_id(1, idx))
		_buy_list.add_child(b)
	for j in player.inv.backpack.size():
		var it: Dictionary = player.inv.backpack[j]
		var price := Merchants.sell_price(it)
		var b2 := _row(Loc.item_name(it), it, price <= 0, price if price > 0 else -1, true, true)
		var bj: int = j
		b2.pressed.connect(func(): merchants.request_sell.rpc_id(1, bj))
		_sell_list.add_child(b2)
	if _sell_list.get_child_count() == 0:
		_sell_list.add_child(UITheme.label(Loc.t("Nothing to sell."), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	var all: Array = _buy_list.get_children() + _sell_list.get_children()
	all = all.filter(func(c): return c is Button)
	if not all.is_empty():
		all[clampi(focus_idx, 0, all.size() - 1)].grab_focus.call_deferred()


## One trade row: the item's icon and name in its rarity colour, and its price as a coin chip on
## the right (red when it can't be afforded, green when selling; a cross when sold out / unwanted).
func _row(text: String, item: Dictionary, dim: bool, price: int, affordable := true, selling := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.custom_minimum_size = Vector2(250, 30)
	if GameData.asset_exists(str(item.get("icon", ""))):
		b.icon = ItemLooks.icon(item)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 24)
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	b.add_theme_color_override("font_color", Color.from_string(rar.color, Color.WHITE).darkened(0.35 if dim else 0.0))
	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	tag.offset_left = -70
	tag.offset_right = -8
	tag.offset_top = -12
	tag.offset_bottom = 12
	tag.alignment = BoxContainer.ALIGNMENT_END
	if price >= 0:
		tag.add_child(UITheme.icon("hud_gold", 16))
		var pc := UITheme.GOOD if selling else (UITheme.GOLD if affordable else UITheme.DANGER)
		var pl := UITheme.label(str(price), pc, UITheme.FONT_BODY)
		tag.add_child(pl)
	else:
		tag.add_child(UITheme.icon("sil_lock", 16, Color(1, 1, 1, 0.5)))
	b.add_child(tag)
	b.focus_entered.connect(_show.bind(item))
	b.mouse_entered.connect(_show.bind(item))
	return b


func _show(item: Dictionary) -> void:
	UITheme.clear(_card)
	_card_scroll.scroll_vertical = 0
	for line in ItemGenerator.describe(item, player.class_id, player.level):
		_card.add_child(UITheme.card_line(line, 210))
