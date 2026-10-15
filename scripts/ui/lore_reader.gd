extends UIModal
## The Gothic lore reader (GDD 7, D19): a parchment page inside an Obsidian Glass frame with the
## book's title, provenance, classification, its text (scrollable with the stick / arrows /
## wheel) and, for tomes, what reading it changed.

const PARCHMENT := Color("2a2116f5")
const INK := Color("e8d9b8")

var book_id := ""
var note := ""
var _scroll: ScrollContainer


func _init() -> void:
	prompts = [["ui_up", "Scroll"], ["ui_cancel", "Close"]]
	max_size = Vector2(760, 520)
	fill_height = true


func _build() -> void:
	var b: Dictionary = GameData.lore_books.get(book_id, {})
	subtitle.text = "%s  -  %s" % [b.get("origin", ""), {"standard": "Lore", "tome": "Tome of Enlightenment", "legendary": "Legendary tome"}.get(str(b.get("classification", "")), "")]
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
	var text := UITheme.label(str(b.get("text", "")), INK, UITheme.FONT_BODY)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(520, 0)
	v.add_child(text)
	if str(b.get("classification", "")) != "standard":
		var eff := UITheme.label(str(b.get("effect_text", "")).replace(" (Permanent)", " for the rest of the run"), UITheme.GOLD, UITheme.FONT_SMALL)
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
