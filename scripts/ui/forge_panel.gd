extends UIModal
## #77 Rolf Hult's forge: the local hero's gear (worn, then the backpack) on the left, the anvil in
## the middle and the chosen piece's "now -> after" card on the right, with the price, the hero's
## gold and the Forge button (disabled, with the reason, when the piece can't be raised). #90: a
## click / accept on a row only selects it (accept then moves to the button); hovering another row
## previews its card while hovered; the Forge button forges one step of the selected piece; the
## host validates it (Forge.request_upgrade),
## the anvil plays the forging and the card flashes the raised numbers. #91: no message; a warm
## light sweeps the card and gold motes rise from it (the layout never moves). #89: forging again while
## the anvil works ends that animation at once, so upgrades can be clicked through.

var forge: Forge
var stage: ForgeStage
var _list: VBoxContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _button: Button
var _reason: Label
var _gold_chip: PanelContainer
var _sel_uid := ""
var _last_sig := ""
var flashed: Array = []  ## the card's numbers that just rose with a forging (tests)
var _pending: Dictionary = {}  ## the forged piece's "after", shown once the anvil is done
var _was: Dictionary = {}  ## the piece before its last forging: the card flashes what rose
var rows: Array = []  ## [{button, where, key, item}] (tests)
var shines := 0  ## success lights played (tests)
var _card_panel: PanelContainer
var _shine: ColorRect
const SHINE := preload("res://assets/shaders/forge_shine.gdshader")


func _init() -> void:
	var bs: Dictionary = GameData.merchants.get("blacksmith", {})
	title_text = Loc.t(str(bs.get("name", "Rolf Hult")))
	subtitle_text = Loc.t(str(bs.get("title", "")))
	title_icon = "forge"
	fill_height = true
	prompts = [["ui_accept", Loc.t("Select")], ["ui_cancel", Loc.t("Leave")]]


func _build() -> void:
	var game := get_tree().get_first_node_in_group("game")
	forge = game.forge
	_gold_chip = UITheme.chip("hud_gold", "", UITheme.GOLD, UITheme.GOLD_DIM)
	_gold_chip.tooltip_text = Loc.t("Your gold")
	_gold_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_gold_chip)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	body.add_child(col)
	col.add_child(UITheme.section(Loc.t("Your gear"), "slot_backpack"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	var mid := PanelContainer.new()
	mid.theme_type_variation = &"GlassInset"
	body.add_child(mid)
	stage = ForgeStage.new()
	stage.finished.connect(_on_forged_done)
	mid.add_child(stage)
	# The card keeps its size; a long piece scrolls inside it (#85); the reason and the button stay
	# under it.
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cv)
	var cardp := UITheme.scroll_card(256)
	cv.add_child(cardp)
	_card_panel = cardp
	# #91: the success light, over the card (the panel stretches it over its whole rect).
	_shine = ColorRect.new()
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.material = ShaderMaterial.new()
	_shine.material.shader = SHINE
	_shine.visible = false
	cardp.add_child(_shine)
	_card = cardp.get_meta("content")
	_card_scroll = cardp.get_meta("scroll")
	_reason = UITheme.label("", UITheme.DANGER, UITheme.FONT_SMALL)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Two lines kept for the reason, so its coming and going never moves the card (#85).
	_reason.custom_minimum_size = Vector2(224, 30)
	_reason.max_lines_visible = 2
	cv.add_child(_reason)
	_button = Button.new()
	_button.text = Loc.t("Forge (+1 item level)")
	_button.icon = UITheme.icon_tex("forge")
	_button.custom_minimum_size = Vector2(0, 34)
	_button.pressed.connect(_forge_selected)
	cv.add_child(_button)
	forge.forged.connect(_on_forged)
	EventBus.local_inventory_changed.connect(_rebuild)
	_rebuild()


func _process(delta: float) -> void:
	# The hero can be freed before the window when a session ends.
	if not is_instance_valid(player):
		return
	UITheme.stick_scroll(_card_scroll, delta)
	if _sig() != _last_sig:
		_rebuild()


func _sig() -> String:
	return "%d|%d|%d" % [player.gold, player.level, hash(player.inv.to_dict())]


func _entries() -> Array:
	var out: Array = []
	for slot in Inventory.SLOTS:
		var it: Dictionary = player.inv.equipment.get(slot, {})
		if not it.is_empty() and Forge.workable(it):
			out.append({"where": "equip", "key": slot, "item": it})
	for i in player.inv.backpack.size():
		var it2: Dictionary = player.inv.backpack[i]
		if Forge.workable(it2):
			out.append({"where": "bag", "key": str(i), "item": it2})
	return out


func _floor_ilvl() -> int:
	var game := get_tree().get_first_node_in_group("game")
	return game.item_level() if game else 1


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_last_sig = _sig()
	_gold_chip.get_meta("label").text = str(player.gold)
	var focused := get_viewport().gui_get_focus_owner()
	var refocus := focused == null or rows.any(func(r): return r.button == focused)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	var entries := _entries()
	var section := ""
	for e in entries:
		var sec := Loc.t("Worn") if e.where == "equip" else Loc.t("Backpack")
		if sec != section:
			section = sec
			var l := UITheme.label(sec, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
			_list.add_child(l)
		var b := _row(e.item)
		var uid := str(e.item.get("uid", ""))
		b.pressed.connect(_choose_row.bind(uid))
		b.focus_entered.connect(_select.bind(uid))
		b.mouse_entered.connect(func(): _show(_row_of(uid)))
		b.mouse_exited.connect(func(): _show(_row_of(_sel_uid)))
		_list.add_child(b)
		rows.append({"button": b, "where": e.where, "key": e.key, "item": e.item})
	if rows.is_empty():
		_list.add_child(UITheme.label(Loc.t("Nothing Rolf can work."), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
		_show({})
		return
	var sel: Dictionary = rows[0]
	for r in rows:
		if str(r.item.get("uid", "")) == _sel_uid:
			sel = r
	_sel_uid = str(sel.item.get("uid", ""))
	_show(sel)
	if refocus:
		sel.button.grab_focus.call_deferred()


## One gear row: icon, name in its rarity colour, its item level, and the price of the next step
## as a coin chip (red when unaffordable; a lock at the forge's cap).
func _row(item: Dictionary) -> Button:
	var b := Button.new()
	b.text = "%s  %s" % [Loc.item_name(item), Loc.f("Lv %d", [int(item.get("ilvl", 1))])]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.custom_minimum_size = Vector2(260, 30)
	if GameData.asset_exists(str(item.get("icon", ""))):
		b.icon = ItemLooks.icon(item)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 24)
	var why := Forge.refusal(item, player.level, _floor_ilvl(), player.gold, Forge.party(get_tree()))
	var capped := int(item.get("ilvl", 1)) >= Forge.cap_for(player.level, _floor_ilvl())
	b.add_theme_color_override("font_color", UITheme.rarity_color(int(item.get("rarity", 1))).darkened(0.35 if capped else 0.0))
	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	tag.offset_left = -70
	tag.offset_right = -8
	tag.offset_top = -12
	tag.offset_bottom = 12
	tag.alignment = BoxContainer.ALIGNMENT_END
	if capped:
		tag.add_child(UITheme.icon("sil_lock", 16, Color(1, 1, 1, 0.5)))
	else:
		tag.add_child(UITheme.icon("hud_gold", 16))
		tag.add_child(UITheme.label(str(Forge.cost(item, Forge.party(get_tree()))), UITheme.GOLD if str(why[0]).is_empty() else UITheme.DANGER, UITheme.FONT_BODY))
	b.add_child(tag)
	return b


## The selected piece (#90): its card stays unless another row is hovered.
func _select(uid: String) -> void:
	_sel_uid = uid
	_show(_row_of(uid))


## A row clicked / accepted: it is selected; with the keyboard or a gamepad the focus moves on to
## the Forge button (the mouse clicks the button itself).
func _choose_row(uid: String) -> void:
	_select(uid)
	if InputSettings.last_kind != "mouse" and not _button.disabled:
		_button.grab_focus()


func _row_of(uid: String) -> Dictionary:
	for r in rows:
		if str(r.item.get("uid", "")) == uid:
			return r
	return {}


## The card: the piece now and after one step, the price and the hero's gold.
func _show(r: Dictionary) -> void:
	UITheme.clear(_card)
	if r.is_empty():
		_button.disabled = true
		_reason.text = ""
		stage.show_item({})
		return
	var item: Dictionary = r.item
	var shown_uid := str(item.get("uid", ""))
	# While the anvil works the piece, the card still shows it as it was.
	var forging := stage.busy() and str(_was.get("uid", "")) == shown_uid
	if forging:
		item = _was
	if not stage.busy():
		stage.show_item(item)
	var rar := UITheme.rarity_color(int(item.get("rarity", 1)))
	var name_l := UITheme.label(Loc.item_name(item), rar, UITheme.FONT_BODY)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(224, 0)
	_card.add_child(name_l)
	var cap := Forge.cap_for(player.level, _floor_ilvl())
	var lvl := int(item.get("ilvl", 1))
	var after := ItemGenerator.at_level(item, mini(lvl + int(Forge.cfg("step", 1)), maxi(cap, lvl)))
	var was: Dictionary = _was if str(_was.get("uid", "")) == shown_uid and not forging else {}
	_compare(Loc.t("Item level"), float(lvl), float(after.ilvl), false, "ui_crown", false, float(was.get("ilvl", lvl)))
	_compare(Loc.t("Requires level"), float(item.get("req", 1)), float(after.req), false, "sil_lock", true, float(was.get("req", item.get("req", 1))))
	if item.has("dps"):
		_compare(Loc.t("DPS"), float(item.dps), float(after.dps), false, "stat_weapon_dps", false, float(was.get("dps", item.dps)))
	if item.has("armor"):
		_compare(Loc.t("Armor"), float(item.armor), float(after.armor), false, "stat_armor", false, float(was.get("armor", item.armor)))
	var names: Dictionary = GameData.affixes.stat_names
	var pct: Array = GameData.affixes.percent_stats
	for k in item.get("stats", {}):
		var v := float(item.stats[k])
		_compare(Loc.t(str(names.get(k, k))), v, float(after.stats.get(k, v)), pct.has(k) or (absf(v) < 1.0 and v != 0.0),
			str(UITheme.STAT_ICONS.get(str(k).trim_suffix("_pct"), "sil_star")), false, float(was.get("stats", {}).get(k, v)))
	if item.has("affix"):
		_card.add_child(UITheme.card_line([Loc.t(str(item.affix)), Color(1.0, 0.72, 0.3), "sil_star"], 224))
	if int(item.get("forged", 0)) > 0:
		_card.add_child(UITheme.card_line([Loc.f("Forged %d times at Rolf's anvil", [int(item.forged)]) if int(item.forged) > 1 else Loc.t("Forged once at Rolf's anvil"), UITheme.GOLD, "forge"], 224))
	_card.add_child(UITheme.divider())
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 6)
	price.add_child(UITheme.label(Loc.t("Price"), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	var why := Forge.refusal(item, player.level, _floor_ilvl(), player.gold, Forge.party(get_tree()))
	var at_cap := lvl >= cap
	if not at_cap:
		price.add_child(UITheme.icon("hud_gold", 16))
		price.add_child(UITheme.label(str(Forge.cost(item, Forge.party(get_tree()))), UITheme.GOLD if player.gold >= Forge.cost(item, Forge.party(get_tree())) else UITheme.DANGER, UITheme.FONT_BODY))
	else:
		price.add_child(UITheme.icon("sil_lock", 16, Color(1, 1, 1, 0.6)))
	_card.add_child(price)
	# The button and its reason are for the selected piece, whatever is previewed.
	var sel := _row_of(_sel_uid)
	var swhy: Array = Forge.refusal(sel.item, player.level, _floor_ilvl(), player.gold, Forge.party(get_tree())) if not sel.is_empty() else ["", []]
	_reason.text = Loc.f(str(swhy[0]), swhy[1]) if not str(swhy[0]).is_empty() else ""
	_button.disabled = sel.is_empty() or not str(swhy[0]).is_empty()


## One "now -> after" line, green where the number rises (red where it would fall); `was` is the
## number before the last forging: when it rose, the "now" number flashes gold.
func _compare(label: String, now: float, after: float, percent: bool, icon_key: String, plain := false, was: float = 0.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UITheme.icon(icon_key, 16))
	var l := UITheme.label(label, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var fmt := func(v: float) -> String:
		if percent:
			return "%d%%" % roundi(v * 100.0)
		return ("%.1f" % v) if absf(v - roundf(v)) > 0.01 else str(roundi(v))
	var nl := UITheme.label(fmt.call(now), UITheme.TEXT, UITheme.FONT_SMALL)
	h.add_child(nl)
	if now > was + 0.0001:
		if not flashed.has(label):
			flashed.append(label)
		nl.add_theme_color_override("font_color", UITheme.GOLD)
		var tw := nl.create_tween()
		tw.tween_property(nl, "self_modulate", Color(2.2, 2.0, 1.4), 0.08)
		tw.tween_property(nl, "self_modulate", Color.WHITE, 0.5)
		for i in 2:
			tw.tween_property(nl, "self_modulate", Color(1.6, 1.5, 1.1), 0.25)
			tw.tween_property(nl, "self_modulate", Color.WHITE, 0.35)
	var col := UITheme.TEXT_DIM
	if after > now + 0.0001:
		col = UITheme.WARN_SOFT if plain else UITheme.GOOD
	elif after < now - 0.0001:
		col = UITheme.DANGER
	h.add_child(UITheme.label("->", UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	h.add_child(UITheme.label(fmt.call(after), col, UITheme.FONT_SMALL))
	_card.add_child(h)


func _forge_selected() -> void:
	if stage.busy():
		stage.finish_now()  # shows the last result, rebuilds the list
	var r := _row_of(_sel_uid)
	if r.is_empty():
		return
	var why := Forge.refusal(r.item, player.level, _floor_ilvl(), player.gold, Forge.party(get_tree()))
	if not str(why[0]).is_empty():
		notice(Loc.f(str(why[0]), why[1]))
		UIFx.deny(_button)
		return
	forge.request_upgrade.rpc_id(1, str(r.where), str(r.key), _sel_uid)


## The host made the upgrade: the anvil plays it, then the card shows the new numbers.
func _on_forged(before: Dictionary, after: Dictionary) -> void:
	flashed.clear()
	_pending = after
	_was = before
	_sel_uid = str(after.get("uid", ""))
	stage.play(before)


func _on_forged_done() -> void:
	stage.show_item(_pending)
	_pending = {}
	_rebuild()
	_was = {}
	_shine_card()


## #91: a warm light sweeps across the card, its rim glows and fades, gold motes rise.
func _shine_card() -> void:
	shines += 1
	var mat: ShaderMaterial = _shine.material
	mat.set_shader_parameter("px_size", _card_panel.size)
	mat.set_shader_parameter("progress", 0.0)
	_shine.visible = true
	var tw := _shine.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _shine.visible = false)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 0.7
	p.lifetime = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_card_panel.size.x * 0.45, 4)
	p.position = Vector2(_card_panel.size.x / 2.0, _card_panel.size.y * 0.7)
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 2.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.6, 1.25, 0.6))
	grad.set_color(1, Color(1.0, 0.55, 0.2, 0.0))
	p.color_ramp = grad
	p.material = CanvasItemMaterial.new()
	p.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shine.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
