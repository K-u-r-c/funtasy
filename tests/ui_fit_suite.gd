class_name UiFitSuite
extends RefCounted
## #44 long text never pushes UI off the screen (scenario "ui_fit", run in English and in Polish):
## at 16:9, 32:9, 4:3 and 1:1 the HUD shows the longest message, interaction prompt, tracker line
## and party names the data can produce, the bar's skill card, then every game screen opens with
## the longest strings in it (the item with the longest name in the backpack and its tooltip, the
## talent with the longest card, the longest lore book, a dialog with a long title and body, the
## options with the rebinding list). Every visible Control, clipped by the scroll areas it sits
## in, must stay inside the screen.

var da: Node
var g: Node
var p: Player
var hud: Node

const SIZES := [Vector2i(1920, 1080), Vector2i(3840, 1080), Vector2i(1280, 960), Vector2i(720, 720)]


func _init(dev_auto: Node) -> void:
	da = dev_auto


## With --shot=<dir>: a screenshot for the review (worst cases before / after the fix).
func _snap(name_: String) -> void:
	if str(da.shot).is_empty():
		return
	await da.get_tree().process_frame
	var img := da.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(str(da.shot))
	img.save_png(str(da.shot).path_join("%s_%s.png" % [name_, Settings.language]))


## The visible part of `c` (cut by every clipping ancestor), in viewport coordinates.
static func visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var n: Node = c.get_parent()
	while n:
		if n is Control and (n as Control).clip_contents:
			r = r.intersection((n as Control).get_global_rect())
		n = n.get_parent()
	return r


## Controls under `root` that show outside `vp` (paths and rects).
static func offenders(root: Node, vp: Rect2) -> Array:
	var out: Array = []
	var stack: Array = [root]
	var outer := vp.grow(1.0)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		if n is Control:
			var c := n as Control
			if c.size.x >= 1.0 and c.size.y >= 1.0 and c.modulate.a > 0.01:
				var r := visible_rect(c)
				if r.size.x >= 1.0 and r.size.y >= 1.0 and not outer.encloses(r):
					var txt := ""
					if c is Label or c is Button:
						txt = " '%s'" % str(c.text).left(30)
					out.append("%s%s %s" % [c.get_class(), txt, r])
		stack.append_array(n.get_children())
	return out


## The longest translated line (no line breaks) up to `cap` characters: the worst HUD message.
static func longest_line(cap: int) -> String:
	var f := FileAccess.open("res://data/i18n/translations.csv", FileAccess.READ)
	var best := ""
	if f == null:
		return best
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2:
			continue
		var t := Loc.t(row[0])
		if t.contains("\n") or t.contains("%") or t.length() > cap:
			continue
		if t.length() > best.length():
			best = t
	return best


func _check_screen(what: String, tag: String) -> void:
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	var vp := da.get_viewport().get_visible_rect()
	var bad := offenders(hud, vp)
	for b in bad.slice(0, 4):
		da.log_line("OFF %s %s: %s" % [what, tag, b])
	da.check(bad.is_empty(), "%s fits on screen at %s (%d outside%s)" % [what, tag, bad.size(), ": %s" % bad[0] if not bad.is_empty() else ""])


func run() -> void:
	g = da._game()
	p = da._local()
	hud = da.get_tree().get_first_node_in_group("hud")
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var rng := RandomNumberGenerator.new()
	# The longest strings the data gives.
	var leg_id := ""
	for id in GameData.legendaries:
		var it := ItemGenerator.make_legendary(str(id), 30, rng)
		if leg_id.is_empty() or Loc.item_name(it).length() > Loc.item_name(ItemGenerator.make_legendary(leg_id, 30, rng)).length():
			leg_id = str(id)
	var long_item := ItemGenerator.make_legendary(leg_id, 30, rng)
	var book := ""
	for id in GameData.lore_books:
		if book.is_empty() or Loc.t(str(GameData.lore_books[id].get("title", ""))).length() > Loc.t(str(GameData.lore_books[book].get("title", ""))).length():
			book = str(id)
	var node_long: Dictionary = {}
	var node_len := 0
	for node in p.talent_tree().nodes:
		var n := JSON.stringify(TalentInfo.rows(p, node)).length()
		if n > node_len:
			node_len = n
			node_long = node
	var boss_name := ""
	var boss_id := ""
	for id in GameData.bosses:
		var nm := Loc.name(str(GameData.bosses[id].get("name", id)))
		if nm.length() > boss_name.length():
			boss_name = nm
			boss_id = str(id)
	# That boss, awake far away: its bar and the tracker carry its name.
	var boss: Node = g.spawn_monster(boss_id, g.layout.boss_pos, true)
	await da._wait(0.3)
	boss.add_threat(p, 1.0)
	boss.set_physics_process(false)
	var message := longest_line(140)
	p.display_name = "WWWWWWWWWWWWWWWW"  # the lobby's 16-character limit, widest glyph
	p.host_give_item(long_item)
	da.log_line("longest: item '%s', book %s, talent %s, boss '%s', message %d chars" % [Loc.item_name(long_item), book, node_long.get("id", ""), boss_name, message.length()])
	var win := da.get_window()
	for s in SIZES:
		win.size = s
		await da._wait(0.4)
		var vp := da.get_viewport().get_visible_rect()
		var tag := "%dx%d %s" % [s.x, s.y, Settings.language]
		# HUD with everything at once.
		hud.preview_full = true
		hud._last_message = ""
		hud.show_message(message, Color.WHITE)
		hud.show_message(Loc.f("Pick up %s - Backpack is full", [Loc.item_name(long_item)]), Color(1, 0.6, 0.5))
		hud._set_prompt(Loc.f("Pick up %s - Backpack is full", [Loc.item_name(long_item)]), 0, 3)
		await da._wait(0.4)
		await _check_screen("the HUD with the longest message, prompt and tracker", tag)
		if s == SIZES[0]:
			await _snap("fit_hud")
		hud._slots[1].mouse_entered.emit()
		await da._wait(0.3)
		await _check_screen("the bar's skill card", tag)
		hud._slots[1].mouse_exited.emit()
		hud._set_prompt("")
		hud.preview_full = false
		# Every game screen.
		for t in UIModal.MENU_TABS:
			hud.open_overlay(hud.menu_panel(t[0]))
			await da._wait(0.6)
			if t[0] == "talents":
				hud._overlay._show(node_long)
				await da._wait(0.2)
			if t[0] == "inventory":
				# The longest item's tooltip.
				for k in hud._overlay._slots:
					var sl: Node = hud._overlay._slots[k]
					if sl.get("item") is Dictionary and str(sl.item.get("uid", "")) == str(long_item.get("uid", "")):
						sl.grab_focus()
				await da._wait(0.3)
			await _check_screen("the %s screen" % t[0], tag)
		hud.close_overlay()
		var reader: Control = hud.LoreReader.new()
		reader.book_id = book
		reader.title_text = Loc.t(str(GameData.lore_books[book].get("title", "")))
		hud.open_overlay(reader)
		await da._wait(0.6)
		await _check_screen("the lore reader with the longest title", tag)
		hud.close_overlay()
		var dlg: Control = hud.ConfirmDialog.new()
		dlg.title_text = Loc.name(boss_name)
		dlg.body_text = message + " " + message
		hud.open_overlay(dlg)
		await da._wait(0.6)
		await _check_screen("a dialog with a long title and body", tag)
		hud.close_overlay()
		for panel_script in [hud.ShopPanel, hud.PactPanel, hud.PauseMenu]:
			hud.open_overlay(panel_script.new())
			await da._wait(0.6)
			await _check_screen("the %s" % str(panel_script.resource_path.get_file().get_basename()), tag)
		if hud._overlay and hud._overlay.has_method("_open_settings"):
			hud._overlay._open_settings()
			await da._wait(0.6)
			var menu: Node = hud._overlay.get_child(hud._overlay.get_child_count() - 1)
			for i in menu._tabs.get_tab_count():
				menu._tabs.current_tab = i
				await da._wait(0.3)
				await _check_screen("the options tab %d" % i, tag)
		hud.close_overlay()
		await da._wait(0.3)
	win.size = Vector2i(1920, 1080)
	boss.stop_mechanics()
	boss.queue_free()


## The menus before a run (scenario "ui_fit_menus"): the main menu, every Options tab and the
## lobby with a 16-character name of the widest glyph, at every aspect ratio.
func run_menus() -> void:
	var win := da.get_window()
	var mm: Node = da.get_tree().current_scene
	for sz in SIZES:
		win.size = sz
		await da._wait(0.4)
		var tag := "%dx%d %s" % [sz.x, sz.y, Settings.language]
		await _check_scene("the main menu", tag)
		mm.open_settings()
		await da._wait(0.5)
		for i in mm._overlay._tabs.get_tab_count():
			mm._overlay._tabs.current_tab = i
			await da._wait(0.3)
			await _check_scene("the main menu's options tab %d" % i, tag)
		mm._overlay.queue_free()
		mm._overlay = null
		await da._wait(0.3)
	NetworkManager.host_solo()
	await da._wait_until(func(): return da.get_tree().current_scene.name == "Lobby", 10.0)
	await da._wait(0.8)
	var lobby: Node = da.get_tree().current_scene
	lobby._name_edit.text = "WWWWWWWWWWWWWWWW"
	lobby._name_edit.text_changed.emit(lobby._name_edit.text)
	# Confirmed: the roster row carries the long name too.
	lobby._confirm.pressed.emit()
	await da._wait(0.6)
	for sz in SIZES:
		win.size = sz
		await da._wait(0.5)
		await _check_scene("the lobby with a 16-character name", "%dx%d %s" % [sz.x, sz.y, Settings.language])
		if sz == SIZES[0]:
			await _snap("fit_lobby")
	win.size = Vector2i(1920, 1080)


func _check_scene(what: String, tag: String) -> void:
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	var vp := da.get_viewport().get_visible_rect()
	var bad := offenders(da.get_tree().current_scene, vp)
	for b in bad.slice(0, 4):
		da.log_line("OFF %s %s: %s" % [what, tag, b])
	da.check(bad.is_empty(), "%s fits on screen at %s (%d outside%s)" % [what, tag, bad.size(), ": %s" % bad[0] if not bad.is_empty() else ""])
