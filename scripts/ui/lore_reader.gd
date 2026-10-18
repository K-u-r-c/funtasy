extends UIModal
## The Gothic lore reader (GDD 7, D19): a parchment page inside an Obsidian Glass frame with the
## book's title, provenance, classification, its text (scrollable with the stick / arrows /
## wheel) and, for tomes, what reading it changed.

const PARCHMENT := Color("2a2116f5")
const INK := Color("e8d9b8")

var book_id := ""
var note := ""
var standalone := false  ## opened by the main menu's codex: closes itself on Cancel
var _scroll: ScrollContainer


func _init() -> void:
	prompts = [["ui_up", Loc.t("Scroll")], ["ui_cancel", Loc.t("Close")]]
	max_size = Vector2(760, 520)
	fill_height = true


func _build() -> void:
	var b: Dictionary = GameData.lore_books.get(book_id, {})
	# The book's kind as its icon before the title (#29): a scroll, a tome, a golden codex.
	var kind_icon: String = {"standard": "menu_save", "tome": "nav_skillbook", "legendary": "nav_codex"}.get(str(b.get("classification", "")), "menu_save")
	header.add_child(UITheme.icon(kind_icon, 32))
	header.move_child(header.get_child(header.get_child_count() - 1), 0)
	subtitle.text = "%s  -  %s" % [Loc.t(str(b.get("origin", ""))), {"standard": Loc.t("Lore"), "tome": Loc.t("Tome of Enlightenment"), "legendary": Loc.t("Legendary tome")}.get(str(b.get("classification", "")), "")]
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", UITheme.glass(PARCHMENT, Color("8a6a3a"), 2, 6))
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(page)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL
	page.add_child(_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	var text := UITheme.label(Loc.t(str(b.get("text", ""))), INK, UITheme.FONT_BODY)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(520, 0)
	v.add_child(text)
	if str(b.get("classification", "")) != "standard":
		var eff := UITheme.label(Loc.t(str(b.get("effect_text", ""))).replace(Loc.t(" (Permanent)"), Loc.t(" for the rest of the run")), UITheme.GOLD, UITheme.FONT_SMALL)
		v.add_child(eff)
	if not note.is_empty():
		content.add_child(UITheme.label(note, UITheme.GOOD, UITheme.FONT_SMALL))
	_scroll.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _scroll == null or not _scroll.has_focus():
		return
	var dir := Input.get_axis("ui_up", "ui_down")
	if absf(dir) > 0.2:
		_scroll.scroll_vertical += int(dir * 360.0 * delta)


func _unhandled_input(ev: InputEvent) -> void:
	if standalone and (ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		closed.emit()
