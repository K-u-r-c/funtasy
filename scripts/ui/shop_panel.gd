extends UIModal
## Archibald the Gilded's shop (GDD 5.1): the floor's shared stock on the left (buy), the
## local hero's backpack on the right (sell). Accept / click buys or sells the focused row;
## the host validates every trade (Merchants.request_buy / request_sell) and the stock change
## reaches every player. #94: a sold-out line is greyed, stamped "Sold", can't be pressed and moves
## to the end of the list, for every hero (a teammate's purchase too); a purchase stamps its line
## and its item flies to the backpack.

var merchants: Merchants
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _last_sig := ""
var _gold_chip: PanelContainer
var _left_seen: Dictionary = {}  ## stock index -> how many were left at the last rebuild (#94)
var _my_buy := -1  ## the stock line this hero just asked to buy
var bought_fx := 0  ## purchase animations played (tests)


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
	# What is for sale first; sold-out lines after it, greyed and stamped (#94).
	var order: Array = range(merchants.stock.size())
	order.sort_custom(func(x, y):
		var sx := int(merchants.stock[x].left) <= 0
		var sy := int(merchants.stock[y].left) <= 0
		return x < y if sx == sy else sy)
	var just: Array = []
	for i in order:
		var e: Dictionary = merchants.stock[i]
		var sold_out := int(e.left) <= 0
		var txt := "%s%s" % [Loc.item_name(e.item), "  x%d" % int(e.left) if int(e.left) > 1 else ""]
		var b := _row(txt, e.item, sold_out or player.gold < int(e.price), -1 if sold_out else int(e.price), player.gold >= int(e.price), false, Loc.t("Sold") if sold_out else "")
		var idx: int = i
		b.set_meta("stock_index", idx)
		b.pressed.connect(func():
			_my_buy = idx
			merchants.request_buy.rpc_id(1, idx))
		_buy_list.add_child(b)
		if _left_seen.has(idx) and int(e.left) < int(_left_seen[idx]):
			just.append(b)
		_left_seen[idx] = int(e.left)
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
	for b in just:
		_bought(b, int(b.get_meta("stock_index")) == _my_buy)


## #94: a line was just bought: its stamp arrives and the row flashes; this hero's own purchase
## also flies its item to the backpack column.
func _bought(row: Button, mine: bool) -> void:
	bought_fx += 1
	(func():
		if not is_instance_valid(row):
			return
		UITheme.stamp_in(row)
		if not mine or row.icon == null:
			return
		_my_buy = -1
		AudioManager.play_sfx("coin", 0.05)
		var fly := TextureRect.new()
		fly.texture = row.icon
		fly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly.size = Vector2(24, 24)
		fly.top_level = true
		fly.z_index = 20
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fly)
		fly.global_position = row.get_global_rect().position + Vector2(6, 3)
		var bag: Control = _sell_list.get_parent().get_parent().get_child(0)
		var tw := fly.create_tween()
		tw.tween_property(fly, "global_position", bag.get_global_rect().position + Vector2(4, 0), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(fly, "modulate:a", 0.0, 0.45).set_delay(0.25)
		tw.tween_callback(fly.queue_free)).call_deferred()


## One trade row: the item's icon and name in its rarity colour, and its price as a coin chip on
## the right (red when it can't be afforded, green when selling; a cross when sold out / unwanted).
func _row(text: String, item: Dictionary, dim: bool, price: int, affordable := true, selling := false, stamp_text := "") -> Button:
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
	if not stamp_text.is_empty():
		# #94: bought - greyed (the stamp itself stays bright), stamped, not pressable.
		b.disabled = true
		b.self_modulate = Color(0.5, 0.5, 0.56)
		b.tooltip_text = Loc.t("Sold out")
		b.add_child(UITheme.stamp(stamp_text, UITheme.DANGER))
		tag.free()
	else:
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
