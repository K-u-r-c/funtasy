extends UIModal
## The library codex (D18): all 205 books grouped by where they come from. Books this profile
## has read show their title and can be reopened; the rest are "???". A tab of the game menu and
## a page of the main menu (standalone: no player, closes on Cancel itself).

const LoreReader := preload("res://scripts/ui/lore_reader.gd")

var standalone := false
var _buttons: Dictionary = {}  ## book id -> its list button
var _selected := ""
var _list: VBoxContainer
var _page: Label
var _page_title: Label


func _init() -> void:
	title_text = Loc.t("Codex")
	menu_tab = "codex"  ## the main menu clears it (standalone)
	prompts = [["ui_accept", Loc.t("Read")], ["ui_cancel", Loc.t("Close")]]


func _build() -> void:
	subtitle.text = Loc.f("%d / %d books read", [Codex.count(), GameData.lore_order.size()])
	# Progress as a gauge next to the title (the count stays in the subtitle).
	var gauge := StatBar.new(UITheme.GOLD, Vector2(140, 8))
	gauge.show_text = false
	gauge.ticks = 7
	gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(gauge)
	header.move_child(gauge, subtitle.get_index() + 1)
	gauge.set_values.call_deferred(float(Codex.count()) / maxf(1.0, GameData.lore_order.size()))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UITheme.glass(LoreReader.PARCHMENT, Color("8a6a3a"), 2, 6))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	_page_title = UITheme.label("", UITheme.GOLD, UITheme.FONT_BODY)
	_page_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_title.custom_minimum_size = Vector2(200, 0)
	rv.add_child(_page_title)
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(ps)
	_page = UITheme.label(Loc.t("Read books to fill the codex. It is kept across every run."), LoreReader.INK, UITheme.FONT_SMALL)
	_page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.custom_minimum_size = Vector2(320, 0)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_page)
	var origin := ""
	var first: Button = null
	# #76: the legendary story first, its chapters in order under the cycle's name.
	var cyc: Array = LoreCycle.chapters()
	if not cyc.is_empty():
		_list.add_child(UITheme.section(Loc.t(str(GameData.lore_books[cyc[0]].cycle)), "nav_codex"))
	for cid in cyc:
		var cb: Dictionary = GameData.lore_books[cid]
		var ck := Codex.is_read(cid)
		var cbtn := _book_button(cid, ("%s  %s" % [LoreCycle.chapter_text(cb), Loc.t(str(cb.title))]) if ck else "%s  ???" % LoreCycle.chapter_text(cb), ck)
		if ck:
			cbtn.add_theme_color_override("font_color", UITheme.GOLD)
		if first == null:
			first = cbtn
	for id in GameData.lore_order:
		var b: Dictionary = GameData.lore_books[id]
		if b.has("chapter"):
			continue
		if str(b.origin) != origin:
			origin = str(b.origin)
			_list.add_child(UITheme.section(Loc.t(origin), "nav_codex"))
		var known := Codex.is_read(id)
		var btn := Button.new()
		btn.text = ("%03d  %s" % [int(b.number), Loc.t(str(b.title))]) if known else "%03d  ???" % int(b.number)
		# Read books show a scroll in their class's colour, the rest a padlock (#29).
		btn.icon = UITheme.icon_tex("menu_save" if known else "sil_lock")
		btn.add_theme_constant_override("icon_max_width", 16)
		var cls := str(b.get("classification", "standard"))
		if known and cls != "standard":
			btn.add_theme_color_override("font_color", UITheme.GOLD if cls == "legendary" else UITheme.CYAN)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		btn.disabled = not known
		btn.focus_mode = Control.FOCUS_ALL
		var bid: String = id
		btn.focus_entered.connect(_show.bind(bid))
		btn.mouse_entered.connect(_show.bind(bid))
		btn.pressed.connect(_read.bind(bid))
		_list.add_child(btn)
		_buttons[bid] = btn
		if first == null:
			first = btn
	var back: Button = _buttons.get(str(restore.get("book", "")))
	if back:
		first = back
	if first:
		first.grab_focus.call_deferred()


## One codex row (a chapter of the cycle): focus and hover show the page, accept reads it.
func _book_button(bid: String, text: String, known: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.icon = UITheme.icon_tex("menu_save" if known else "sil_lock")
	btn.add_theme_constant_override("icon_max_width", 16)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	btn.disabled = not known
	btn.focus_mode = Control.FOCUS_ALL
	btn.focus_entered.connect(_show.bind(bid))
	btn.mouse_entered.connect(_show.bind(bid))
	btn.pressed.connect(_read.bind(bid))
	_list.add_child(btn)
	_buttons[bid] = btn
	return btn


func save_state() -> Dictionary:
	return {"book": _selected}


## Accept on a read book opens it in the lore reader; closing the reader comes back here (#38).
func _read(id: String) -> void:
	_show(id)
	if not Codex.is_read(id):
		return
	if standalone:
		var r: UIModal = LoreReader.new()
		r.book_id = id
		r.set("standalone", true)
		r.title_text = Loc.t(str(GameData.lore_books[id].get("title", "Book")))
		get_parent().add_child(r)
		set_process_unhandled_input(false)
		r.closed.connect(func():
			r.queue_free()
			set_process_unhandled_input(true)
			if _buttons.has(id):
				_buttons[id].grab_focus())
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_book(id, "")


func _show(id: String) -> void:
	_selected = id
	if not Codex.is_read(id):
		_page_title.text = "???"
		_page.text = Loc.t("Not read yet. Books drop from bookshelves, secret containers and elite altars.")
		return
	var b: Dictionary = GameData.lore_books[id]
	_page_title.text = Loc.t(str(b.title))
	var where := Loc.t(str(b.origin))
	if b.has("chapter"):
		where = "%s - %s" % [Loc.t(str(b.cycle)), LoreCycle.chapter_text(b)]
	_page.text = "%s\n\n%s" % [where, Loc.t(str(b.text))]


func _unhandled_input(ev: InputEvent) -> void:
	if standalone and ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
