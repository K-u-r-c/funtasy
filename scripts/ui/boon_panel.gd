extends UIModal
## #73: the boon choice after a boss. Three large cards (icon, name, what it does, its kind and
## tags; the rim in its rarity colour) and Skip. Choosing sends the pick to the host; the card
## flies to the hero's portrait and shrinks into it, the boon flares on the hero (every peer
## sees that). Mouse, keyboard and gamepad (left / right between the cards, accept to choose).
## #96: under each card a Reroll button draws that card again, once per card on this floor's
## offer (down from a card reaches its button).

var game: Node
var _cards: Array = []
var _ids: Array = []
var _rerolls: Array = []  ## the Reroll button under each card (#96)
var _row: HBoxContainer
var _skip: Button
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
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	content.add_child(_row)
	for i in _ids.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_row.add_child(col)
		var card := _make_card(i)
		col.add_child(card)
		_cards.append(card)
		var rr := AnimButton.new()
		rr.icon = UITheme.icon_tex("act_reset")
		rr.add_theme_constant_override("icon_max_width", 16)
		rr.custom_minimum_size = Vector2(ChoiceCard.SIZE.x, 28)
		rr.focus_mode = Control.FOCUS_ALL
		var idx: int = i
		rr.pressed.connect(func(): _reroll(idx))
		col.add_child(rr)
		_rerolls.append(rr)
		_mark_reroll(i)
	var skip := Button.new()
	skip.text = Loc.t("Skip the boon")
	skip.focus_mode = Control.FOCUS_ALL
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(func(): _choose(-1))
	content.add_child(skip)
	_skip = skip
	_wire()
	if not _cards.is_empty():
		_cards[0].grab_focus.call_deferred()


func _make_card(i: int) -> ChoiceCard:
	var id := str(_ids[i])
	var d := Boons.def(id)
	var card := ChoiceCard.new(str(d.get("icon", "")).trim_prefix("icons."), Loc.t(str(d.get("name", id))), Boons.card_lines(id), Boons.color(id))
	card.pressed.connect(func(): _choose(i))
	return card


## Left / right between the cards and between their Reroll buttons; down from a card to its
## button, then to Skip.
func _wire() -> void:
	var n := _cards.size()
	for i in n:
		_cards[i].focus_neighbor_left = _cards[(i - 1 + n) % n].get_path()
		_cards[i].focus_neighbor_right = _cards[(i + 1) % n].get_path()
		_cards[i].focus_neighbor_bottom = _rerolls[i].get_path()
		_rerolls[i].focus_neighbor_top = _cards[i].get_path()
		_rerolls[i].focus_neighbor_left = _rerolls[(i - 1 + n) % n].get_path()
		_rerolls[i].focus_neighbor_right = _rerolls[(i + 1) % n].get_path()
		_rerolls[i].focus_neighbor_bottom = _skip.get_path()
	_skip.focus_neighbor_top = _rerolls[0].get_path() if n > 0 else NodePath()


func _mark_reroll(i: int) -> void:
	var game_: Node = get_tree().get_first_node_in_group("game") if is_inside_tree() else game
	var used: bool = game_ != null and game_.my_boon_rerolled.size() > i and bool(game_.my_boon_rerolled[i])
	_rerolls[i].text = Loc.t("Rerolled") if used else Loc.t("Reroll")
	_rerolls[i].disabled = used or _done
	_rerolls[i].tooltip_text = Loc.t("Each card can be rerolled once per floor") if used else Loc.t("Draw this card again (once per floor)")


func _reroll(i: int) -> void:
	if _done or _rerolls[i].disabled:
		return
	_rerolls[i].disabled = true
	AudioManager.play_sfx("ui_press", 0.0)
	game.request_boon_reroll.rpc_id(1, i)


## #96: the host drew card `i` again: the new card takes its place with a flash.
func rerolled(i: int, id: String) -> void:
	if i < 0 or i >= _cards.size():
		return
	_ids[i] = id
	var old: ChoiceCard = _cards[i]
	var had_focus := old.has_focus()
	var col := old.get_parent()
	var card := _make_card(i)
	col.remove_child(old)
	old.queue_free()
	col.add_child(card)
	col.move_child(card, 0)
	_cards[i] = card
	_wire()
	_mark_reroll(i)
	card.flash()
	AudioManager.play_sfx("buff", 0.0)
	if had_focus:
		card.grab_focus.call_deferred()


func _choose(index: int) -> void:
	if _done:
		return
	_done = true
	for rr in _rerolls:
		rr.disabled = true
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
