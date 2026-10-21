extends UIModal
## #73: the boon choice after a boss. Three large cards (icon, name, what it does, its kind and
## tags; the rim in its rarity colour) and Skip. Choosing sends the pick to the host; the card
## flies to the hero's portrait and shrinks into it, the boon flares on the hero (every peer
## sees that). Mouse, keyboard and gamepad (left / right between the cards, accept to choose).

var game: Node
var _cards: Array = []
var _ids: Array = []
var _done := false


func _init() -> void:
	title_text = Loc.t("Choose a boon")
	title_icon = "nav_talents"
	prompts = [["ui_accept", Loc.t("Choose")], ["ui_cancel", Loc.t("Later")]]


func _build() -> void:
	game = get_tree().get_first_node_in_group("game")
	_ids = game.my_boon_offer.duplicate()
	var intro := UITheme.label(Loc.t("It stays with you for the rest of the run"), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	for i in _ids.size():
		var id := str(_ids[i])
		var d := Boons.def(id)
		var card := ChoiceCard.new(str(d.get("icon", "")).trim_prefix("icons."), Loc.t(str(d.get("name", id))), Boons.card_lines(id), Boons.color(id))
		var idx: int = i
		card.pressed.connect(func(): _choose(idx))
		row.add_child(card)
		_cards.append(card)
	var skip := Button.new()
	skip.text = Loc.t("Skip the boon")
	skip.focus_mode = Control.FOCUS_ALL
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(func(): _choose(-1))
	content.add_child(skip)
	for i in _cards.size():
		_cards[i].focus_neighbor_left = _cards[(i - 1 + _cards.size()) % _cards.size()].get_path()
		_cards[i].focus_neighbor_right = _cards[(i + 1) % _cards.size()].get_path()
		_cards[i].focus_neighbor_bottom = skip.get_path()
	skip.focus_neighbor_top = _cards[0].get_path() if not _cards.is_empty() else NodePath()
	if not _cards.is_empty():
		_cards[0].grab_focus.call_deferred()


func _choose(index: int) -> void:
	if _done:
		return
	_done = true
	game.request_boon.rpc_id(1, index)
	if index < 0 or index >= _cards.size():
		closed.emit()
		return
	# The card flies to the portrait (top left) and shrinks into it.
	var card: ChoiceCard = _cards[index]
	card.flash()
	for c in _cards:
		if c != card:
			var t0: Tween = c.create_tween()
			t0.tween_property(c, "modulate:a", 0.0, 0.2)
	var hud := get_tree().get_first_node_in_group("hud")
	var to := Vector2(60, 60)
	if hud and hud.has_method("portrait_center"):
		to = hud.portrait_center()
	var from := card.global_position
	card.top_level = true
	card.global_position = from
	var tw := card.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(card, "global_position", to - ChoiceCard.SIZE * 0.1, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "scale", Vector2(0.2, 0.2), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(window, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(dim, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): closed.emit())
