extends UIModal
## #72 The bargain shrine: the idol's two bargains as large cards (the gift in gold, the price in
## warning amber); choosing one strikes it (the host applies the floor-long buff and takes the
## price), "Walk away" leaves the shrine untouched. Mouse, keyboard and gamepad.

var offers: Array = []
var game: Node
var cards: Dictionary = {}  ## bargain id -> ChoiceCard (tests)
var _chosen := false


func _init() -> void:
	title_text = Loc.t("Bargain Shrine")
	title_icon = "ev_shrine"
	prompts = [["ui_accept", Loc.t("Strike the bargain")], ["ui_cancel", Loc.t("Walk away")]]


func _build() -> void:
	game = get_tree().get_first_node_in_group("game")
	var intro := UITheme.label(Loc.t("The faceless idol offers strength for the rest of this floor - and names its price."), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(520, 0)
	content.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	content.add_child(row)
	var col := Color.from_string(str(FloorEvents.def("shrine").get("color", "#a66cff")), Color.MEDIUM_PURPLE)
	for id in offers:
		var b := _bargain(str(id))
		if b.is_empty():
			continue
		var lines := [[Loc.t(str(b.text)), UITheme.GOLD, [Loc.t("The gift"), UITheme.GOLD]],
			[Loc.t(str(b.cost_text)), UITheme.WARN_SOFT, [Loc.t("The price"), UITheme.WARN]]]
		var card := ChoiceCard.new("ev_shrine", Loc.t(str(b.name)), lines, col)
		var bid := str(id)
		card.pressed.connect(func(): _choose(bid))
		row.add_child(card)
		cards[bid] = card
	var leave := Button.new()
	leave.text = Loc.t("Walk away")
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.custom_minimum_size = Vector2(180, 32)
	leave.pressed.connect(func(): get_tree().get_first_node_in_group("hud").close_overlay())
	content.add_child(leave)
	var list := cards.values()
	for i in list.size():
		list[i].focus_neighbor_left = list[(i - 1 + list.size()) % list.size()].get_path()
		list[i].focus_neighbor_right = list[(i + 1) % list.size()].get_path()
		list[i].focus_neighbor_bottom = leave.get_path()
	if not list.is_empty():
		list[0].grab_focus.call_deferred()


func _bargain(id: String) -> Dictionary:
	for b in FloorEvents.def("shrine").get("bargains", []):
		if str(b.id) == id:
			return b
	return {}


func _choose(id: String) -> void:
	if _chosen:
		return
	_chosen = true
	game.events.request_bargain.rpc_id(1, id)
	if cards.has(id):
		cards[id].flash()
	for k in cards:
		if k != id:
			cards[k].create_tween().tween_property(cards[k], "modulate:a", 0.25, 0.25)
	await get_tree().create_timer(0.55).timeout
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("close_overlay"):
		hud.close_overlay()
