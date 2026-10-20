class_name I18nSuite
extends RefCounted
## #32 localization checks (scenario "i18n" on a solo host, "i18n_lan" on a LAN pair):
## - every key of data/i18n/translations.csv has a Polish entry, and every Polish character is a
##   glyph of the pixel font (or already in the English key, which uses the same fallback);
## - switching the language changes a UI label, an item tooltip, a skill tooltip and a lore book;
## - the language option in Options (opened from the pause menu, mid-run) switches the language
##   and the HUD rebuilds in it without errors;
## - in Polish, no visible text of the HUD and of the game menus shows an English word that has a
##   translation (the "untranslated key" scan);
## - LAN: a host message travels as a key and every peer shows it in its own language.

var da: Node
var g: Node
var p: Player
var _en_words := {}  ## English words of keys whose Polish differs
var _pl_words := {}  ## every word of the Polish entries (names like "Archibald" appear in both)


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	p.iframe_left = 9999.0
	every_key()
	await language_switch()
	await options_switch()
	await visible_scan()
	Settings.set_language("en")


## The CSV as {english: polish}.
static func entries() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://data/i18n/translations.csv", FileAccess.READ)
	if f == null:
		return out
	f.get_csv_line()  # header
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			out[row[0]] = row[1]
	return out


func every_key() -> void:
	var tr := entries()
	var missing: Array = []
	for k in tr:
		if str(tr[k]).strip_edges().is_empty():
			missing.append(k)
	da.check(tr.size() > 2000 and missing.is_empty(), "every one of %d translation keys has a Polish entry (missing: %s)" % [tr.size(), missing.slice(0, 5)])
	da.check(TranslationServer.get_loaded_locales().has("pl"), "the Polish translation is loaded")
	# A fresh copy of the font: the cached one carries the default font as a fallback.
	var font: FontFile = ResourceLoader.load(GameData.asset_path("ui.font"), "", ResourceLoader.CACHE_MODE_IGNORE)
	var bad := {}
	for k in tr:
		var pl: String = tr[k]
		for i in pl.length():
			var ch := pl[i]
			# "|" splits the plural forms of a Polish entry (Loc.plural).
			if ch.strip_edges().is_empty() or ch == "|" or str(k).contains(ch):
				continue
			if not font.has_char(pl.unicode_at(i)):
				bad[ch] = k
	da.check(bad.is_empty(), "every Polish character is in the pixel font (missing: %s)" % [bad.keys()])
	bad.clear()
	for k in ["ą", "ć", "ę", "ł", "ń", "ó", "ś", "ź", "ż", "Ą", "Ć", "Ę", "Ł", "Ń", "Ó", "Ś", "Ź", "Ż"]:
		if not font.has_char(k.unicode_at(0)):
			bad[k] = "glyph"
	da.check(bad.is_empty(), "the pixel font has every Polish letter")
	for k in tr:
		for w in _words(tr[k]):
			_pl_words[w] = true
		if tr[k] == k:
			continue
		for w in _words(k):
			_en_words[w] = k


## Words (letters only, 4+ long) of a text.
static func _words(s: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("[A-Za-zÀ-ž]{4,}")
	for m in re.search_all(s):
		out.append(m.get_string())
	return out


## UI title, an item's tooltip, a skill's tooltip and a lore book in English, then in Polish.
func language_switch() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var item := ItemGenerator.generate_equipment("sword", 5, 3, rng)
	var sk: Dictionary = GameData.skills.get(str(p.skills[0]), {})
	var seen := {}
	for lang in ["en", "pl"]:
		Settings.set_language(lang)
		await da._wait(0.3)
		hud.open_overlay(hud.menu_panel("inventory"))
		await da._wait(0.3)
		var title := _texts(hud._overlay.header)
		hud.close_overlay()
		var tip := " | ".join(ItemGenerator.describe(item, p.class_id, p.level).map(func(l): return str(l[0])))
		var rows := " | ".join(SkillInfo.rows(p, sk).map(func(r): return "%s %s" % [r.k, r.v]))
		hud.open_book("lore_001", "")
		await da._wait(0.4)
		var book := _texts(hud._overlay)
		hud.close_overlay()
		seen[lang] = {"title": title, "tip": tip, "skill": Loc.t(str(sk.name)) + " " + rows, "book": book}
		await da._wait(0.2)
	var en: Dictionary = seen.en
	var pl: Dictionary = seen.pl
	da.check(en.title.contains("Inventory") and pl.title.contains("Ekwipunek"), "the language switch changes a UI label (%s -> %s)" % [en.title, pl.title])
	da.check(en.tip != pl.tip and en.tip.contains("Sword") and pl.tip.contains("Miecz") and pl.tip.contains("Wymaga poziomu"),
			"the language switch changes an item tooltip (%s -> %s)" % [en.tip.left(60), pl.tip.left(60)])
	da.check(en.skill != pl.skill and pl.skill.contains(Loc.t("Cooldown")) and not pl.skill.contains("Cooldown"),
			"the language switch changes a skill tooltip (%s -> %s)" % [en.skill.left(60), pl.skill.left(60)])
	var opening := str(GameData.lore_books["lore_001"].text).substr(1, 24)
	da.check(en.book.contains(opening) and not pl.book.contains(opening) and pl.book.contains("Dziennik Ostatniego Grabarza"),
			"the language switch changes a lore book (%s -> %s)" % [en.book.left(40), pl.book.left(40)])


## Pause -> Options -> Language mid-run: the options window and then the HUD rebuild in Polish.
func options_switch() -> void:
	Settings.set_language("en")
	await da._wait(0.3)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(preload("res://scripts/ui/pause_menu.gd").new())
	await da._wait(0.4)
	var pause: Node = hud._overlay
	pause._open_settings()
	await da._wait(0.4)
	var menu: Node = null
	for c in pause.get_children():
		if c.has_method("_relocalize"):
			menu = c
	da.check(menu != null and menu._lang_opt != null and menu._lang_opt.item_count == Settings.LANGUAGES.size(),
			"Options offer every language (%s)" % [Settings.LANGUAGES.map(func(l): return l[1])])
	if menu == null:
		return
	var idx := -1
	for i in menu._lang_opt.item_count:
		if str(menu._lang_opt.get_item_metadata(i)) == "pl":
			idx = i
	menu._lang_opt.select(idx)
	menu._lang_opt.item_selected.emit(idx)
	await da._wait(0.5)
	da.check(TranslationServer.get_locale().begins_with("pl") and Settings.language == "pl", "picking Polski switches the language")
	da.check(_texts(menu).contains("Opcje") and _texts(menu).contains("Język"), "the options window rebuilds in Polish")
	var cfg := ConfigFile.new()
	cfg.load(SaveSystem.SETTINGS_PATH)  # user://settings.cfg (moved under the test profile)
	da.check(str(cfg.get_value("game", "language", "")) == "pl", "the language is saved to the settings file (%s)" % SaveSystem.SETTINGS_PATH)
	menu._close()
	await da._wait(0.8)
	da.check(not hud.has_overlay(), "closing Options after a new language returns to the game")
	await da._wait(0.3)
	da.check(hud._floor_label.text.begins_with("Piętro") and hud._slots.size() == 6, "the HUD rebuilds in Polish (%s, %d slots)" % [hud._floor_label.text, hud._slots.size()])
	p.add_xp(5)
	await da._wait(0.3)


## In Polish: every visible text of the HUD and of each game menu, then the pause and options
## windows, must not show an English word that has a Polish translation.
func visible_scan() -> void:
	Settings.set_language("pl")
	await da._wait(0.4)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var found := {}
	_scan(hud, "hud", found)
	for t in UIModal.MENU_TABS:
		hud.open_overlay(hud.menu_panel(t[0]))
		await da._wait(0.4)
		_scan(hud._overlay, t[0], found)
		hud.close_overlay()
	hud.open_overlay(preload("res://scripts/ui/pause_menu.gd").new())
	await da._wait(0.3)
	_scan(hud._overlay, "pause", found)
	hud._overlay._open_settings()
	await da._wait(0.4)
	for c in hud._overlay.get_children():
		if c.has_method("_relocalize"):
			for i in c._tabs.get_tab_count():
				c._tabs.current_tab = i
				await da._wait(0.2)
				_scan(c, "options", found)
			c._close()
	await da._wait(0.3)
	hud.close_overlay()
	for kind in ["archibald", "malphas"]:
		hud.open_merchant(kind)
		await da._wait(0.4)
		_scan(hud._overlay, kind, found)
		hud.close_overlay()
	hud.open_book("lore_050", "")
	await da._wait(0.4)
	_scan(hud._overlay, "book", found)
	hud.close_overlay()
	# The main menu, built next to the game for a moment.
	var menu: Node = load(NetworkManager.MENU_SCENE).instantiate()
	da.get_tree().root.add_child(menu)
	await da._wait(0.5)
	_scan(menu, "main_menu", found)
	menu.queue_free()
	await da._wait(0.2)
	da.check(found.is_empty(), "no English word on the Polish screens (%s)" % [found.keys().slice(0, 12).map(func(k): return "%s: %s" % [k, found[k]])])


func _scan(root: Node, where: String, found: Dictionary) -> void:
	for n in _all(root):
		if not (n is Control) or not n.is_visible_in_tree():
			continue
		var s := ""
		if n is Label or n is Button:
			s = n.text
		elif n is RichTextLabel:
			s = n.get_parsed_text()
		elif n is TabBar:
			for i in n.tab_count:
				s += n.get_tab_title(i) + " "
		elif n is TabContainer:
			for i in n.get_tab_count():
				s += n.get_tab_title(i) + " "
		s += " " + n.tooltip_text
		for w in _words(s):
			if _en_words.has(w) and not _pl_words.has(w) and w != p.display_name:
				found["%s/%s" % [where, w]] = s.strip_edges().left(40)


static func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


static func _texts(n: Node) -> String:
	var parts: Array = []
	for c in _all(n):
		if c is Label or c is Button:
			parts.append(c.text)
		elif c is RichTextLabel:
			parts.append(c.get_parsed_text())
	return " ".join(parts)


# --- LAN ------------------------------------------------------------------------------------


## Host in Polish, client in English: a host broadcast and a host-side refusal arrive as keys and
## each peer shows its own language.
func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	Settings.set_language("pl")
	var got: Array = []
	var cb := func(text: String, _c: Color): got.append(text)
	EventBus.hud_message.connect(cb)
	g.broadcast_message.rpc("The boss is defeated! A portal opens...", "#c080ff")
	await da._wait(0.3)
	da.check(got.has("Boss pokonany! Otwiera się portal..."), "the Polish host shows the broadcast in Polish (%s)" % [got])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["i18n_seen", "The boss is defeated! A portal opens..."])
	await da._wait(0.6)
	EventBus.hud_message.disconnect(cb)
	Settings.set_language("en")


func client_cmd(cmd: String, arg: Variant) -> void:
	match cmd:
		"i18n_seen":
			# The client runs in English: the message it got shows the English text.
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			var texts := _texts(hud)
			da.check(TranslationServer.get_locale().begins_with("en") and texts.contains(str(arg)),
					"the English client shows the host's message in English")
