class_name LoreSuite
extends RefCounted
## Headless lore checks (scenario "lore", solo host): the imported library, drop categories,
## reading standard books / tomes / the legendary tome, the codex file and bookshelf drops.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	p.iframe_left = 9999.0
	library()
	drops()
	await reading()
	await back_to_panel()
	await bookshelf()


func library() -> void:
	var counts := {}
	for id in GameData.lore_order:
		var c := str(GameData.lore_books[id].classification)
		counts[c] = int(counts.get(c, 0)) + 1
	# #69: 105 books + 100 new ones (17 lore and 3 tomes per biome).
	da.check(GameData.lore_order.size() == 205 and counts == {"standard": 158, "tome": 46, "legendary": 1},
		"205 books imported: %s" % [counts])
	var unparsed := GameData.lore_order.filter(func(id):
		var b: Dictionary = GameData.lore_books[id]
		return b.classification != "standard" and b.effect.is_empty())
	da.check(unparsed.is_empty(), "every tome has a parsed effect")


func drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {"standard": 0, "tome": 0, "legendary": 0}
	var wrong_biome := 0
	for i in 3000:
		var b := LootTable.roll_book("crypt", rng)
		var def: Dictionary = GameData.lore_books[b.book]
		counts[def.classification] += 1
		if not def.biome in ["crypt", "ancient", "transcendent"]:
			wrong_biome += 1
	da.check(absf(counts.standard / 3000.0 - 0.8) < 0.04 and absf(counts.tome / 3000.0 - 0.18) < 0.04 and counts.legendary > 20,
		"book categories roll 80 / 18 / 2 (%s)" % [counts])
	da.check(wrong_biome == 0, "Crypt floors only drop Crypt and Ancient Lore books")


func reading() -> void:
	var std := ""
	var tome := ""
	for id in GameData.lore_order:
		var b: Dictionary = GameData.lore_books[id]
		if std.is_empty() and b.classification == "standard":
			std = id
		if tome.is_empty() and b.classification == "tome" and b.effect.mods[0].stat == "armor":
			tome = id
	var rng := RandomNumberGenerator.new()
	p.host_give_item(LootTable.make_book(std, rng))
	p.host_give_item(LootTable.make_book(tome, rng))
	p.host_give_item(LootTable.make_book("lore_105", rng))
	await da._wait(0.3)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	p.request_read_book.rpc_id(1, _index_of(std))
	await da._wait(0.4)
	da.check(Codex.is_read(std) and _index_of(std) >= 0, "a standard book enters the codex and stays in the backpack")
	da.check(hud._overlay != null and str(hud._overlay.get("book_id")) == std, "the lore reader opens for the reader")
	hud.close_overlay()
	var armor0 := p.stats.get_stat("armor")
	p.request_read_book.rpc_id(1, _index_of(tome))
	await da._wait(0.4)
	da.check(_index_of(tome) < 0 and p.stats.get_stat("armor") > armor0, "a tome is consumed and raises armor (%.0f -> %.0f)" % [armor0, p.stats.get_stat("armor")])
	hud.close_overlay()
	var tp := p.talent_points
	var sp := p.stat_points
	p.request_read_book.rpc_id(1, _index_of("lore_105"))
	await da._wait(0.4)
	da.check(p.talent_points == tp + 1 and p.stat_points == sp + 5, "the legendary tome gives +1 talent point and +5 stat points")
	da.check(int(p.to_character().bonus_stat_points) == 5, "the legendary tome's points are saved")
	hud.close_overlay()
	var file := SaveSystem.base_dir + "codex.json"
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else {}
	da.check(saved is Dictionary and Array(saved.get("read", [])).has(tome), "the codex is saved per profile, outside the game save")
	var fresh: Node = load("res://autoload/codex.gd").new()
	fresh._ready()
	da.check(fresh.is_read(std) and fresh.is_read("lore_105"), "the codex survives a restart (and so a wipe)")
	fresh.free()


func bookshelf() -> void:
	var shelf: Node = null
	for pr in g.dungeon.props.values():
		if pr.type == "bookshelf" and pr.destructible():
			shelf = pr
			break
	if shelf == null:
		g.dungeon.spawn_prop.rpc("TestShelf", "bookshelf", g.nearest_floor(p.global_position + Vector2(50, 0)))
		await da._wait(0.2)
		shelf = g.dungeon.props["TestShelf"]
	var before: Array = g.items_root.get_children().filter(func(i): return i.item.get("kind", "") == "book")
	for i in 20:
		if before.size() < g.items_root.get_children().filter(func(it): return it.item.get("kind", "") == "book").size():
			break
		shelf.def = shelf.def.merged({"drop_chance": 1.0}, true)
		shelf.take_damage(999.0, Combat.instance.make_ctx(p, GameData.skill(p.skills[0])))
		await da._wait(0.3)
	var after: Array = g.items_root.get_children().filter(func(i): return i.item.get("kind", "") == "book")
	da.check(after.size() > before.size(), "a broken bookshelf drops a book")


## #38: a book read from the inventory (or opened from the codex) goes back to that panel, with
## the selection kept, when the reader is closed with Cancel.
func back_to_panel() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.close_overlay()
	var std := ""
	for id in GameData.lore_order:
		if GameData.lore_books[id].classification == "standard":
			std = id
	p.host_give_item(LootTable.make_book(std, RandomNumberGenerator.new()))
	await da._wait(0.3)
	var i := _index_of(std)
	hud.open_overlay(hud.menu_panel("inventory"))
	await da._wait(0.4)
	var inv: Node = hud._overlay
	inv._slots["b:%d" % i].grab_focus()
	await da._wait(0.2)
	inv._accept_backpack(i)
	await da._wait(0.5)
	da.check(hud._overlay != null and str(hud._overlay.get("book_id")) == std, "reading a book from the inventory opens the reader")
	da._action("ui_cancel")
	await da._wait(0.5)
	var back: Node = hud._overlay
	da.check(back != null and str(back.get("menu_tab")) == "inventory" and str(back._focus_key) == "b:%d" % i,
			"Cancel in the reader returns to the inventory with the book still selected (%s)" % [back._focus_key if back else "closed"])
	# The codex: Accept on a read book opens it, Cancel comes back to the same book.
	hud._switch_tab("codex")
	await da._wait(0.4)
	var codex: Node = hud._overlay
	codex._buttons[std].grab_focus()
	await da._wait(0.2)
	codex._buttons[std].pressed.emit()
	await da._wait(0.5)
	da.check(hud._overlay != null and str(hud._overlay.get("book_id")) == std, "Accept on a read book in the codex opens the reader")
	da._action("ui_cancel")
	await da._wait(0.5)
	var c2: Node = hud._overlay
	da.check(c2 != null and str(c2.get("menu_tab")) == "codex" and str(c2._selected) == std and c2._buttons[std].has_focus(),
			"Cancel in the reader returns to the codex on the same book")
	hud.close_overlay()
	await da._wait(0.3)


func _index_of(book: String) -> int:
	for i in p.inv.backpack.size():
		if str(p.inv.backpack[i].get("book", "")) == book:
			return i
	return -1
