extends UIModal
## #71: the vote at the portal. The two floor modifiers offered for the next floor as large cards
## (icon, name, what it does in warning amber, what it gives in gold) with the names of the heroes
## who voted for each; choosing a card is this hero's vote and steps into the portal; "Back" takes
## the vote back. The host's pick (most votes, ties by a seeded draw) applies to the next floor.
## Mouse, keyboard and gamepad (left / right between the cards, accept to vote).

var game: Node
var _cards: Dictionary = {}  ## mod id -> ChoiceCard
var _status: Label


func _init() -> void:
	title_text = Loc.t("Choose the next floor")
	title_icon = "nav_map"
	prompts = [["ui_accept", Loc.t("Vote")], ["ui_cancel", Loc.t("Back")]]


func _build() -> void:
	game = get_tree().get_first_node_in_group("game")
	var intro := UITheme.label(Loc.f("Floor %d - more danger, more reward", [int(game.depth) + 1]), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	content.add_child(row)
	for id in game.mod_offer:
		var md := FloorMods.def(str(id))
		var card := ChoiceCard.new(str(md.get("icon", "")), Loc.t(str(md.get("name", id))), FloorMods.card_lines(str(id)), FloorMods.color(str(id)))
		var mid: String = str(id)
		card.pressed.connect(func(): _vote(mid))
		row.add_child(card)
		_cards[mid] = card
	_status = UITheme.label("", UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_status)
	var cards := _cards.values()
	for i in cards.size():
		cards[i].focus_neighbor_left = cards[(i - 1 + cards.size()) % cards.size()].get_path()
		cards[i].focus_neighbor_right = cards[(i + 1) % cards.size()].get_path()
	EventBus.mod_vote_changed.connect(_refresh)
	_refresh(false)
	if not cards.is_empty():
		var mine := str(game.mod_votes.get(multiplayer.get_unique_id(), ""))
		(_cards[mine] if _cards.has(mine) else cards[0]).grab_focus.call_deferred()


func _vote(id: String) -> void:
	game.request_mod_vote.rpc_id(1, id)
	if _cards.has(id):
		_cards[id].flash()


func _refresh(locked: bool) -> void:
	if not is_inside_tree():
		return
	var me := multiplayer.get_unique_id()
	for id in _cards:
		var who: Array = []
		for peer in game.mod_votes:
			if str(game.mod_votes[peer]) == id:
				var pl: Player = game.player_by_peer(int(peer))
				if pl:
					who.append([pl.display_name, Color.from_string(str(pl.class_def.get("color", "#ffffff")), Color.WHITE)])
		_cards[id].set_voters(who)
		_cards[id].picked = str(game.mod_votes.get(me, "")) == id
		_cards[id].disabled = locked
	var alive: int = game.players_root.get_children().filter(func(pl): return pl.life_state == Player.Life.ALIVE).size()
	_status.text = Loc.t("The portal is opening...") if locked else Loc.f("%d of %d heroes have chosen", [game.mod_votes.size(), alive])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Back: the vote (and the step into the portal) is taken back.
		if game.mod_votes.has(multiplayer.get_unique_id()):
			game.request_mod_vote.rpc_id(1, "")
		get_viewport().set_input_as_handled()
		closed.emit()
