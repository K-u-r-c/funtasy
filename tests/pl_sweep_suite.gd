class_name PlSweepSuite
extends RefCounted
## Polish sweep (scenario "pl_sweep", solo, run in Polish): everything the game writes for the
## player is read back and checked for English left over - an English word of a key whose
## Polish differs, or a raw id ("max_hp", "{"):
## - the descriptions of every item base at every rarity, every legendary, consumable and pact
##   potion, every class skill and every talent node;
## - the hover text of every status effect (HUD chips) and of every control on the HUD, the game
##   menu panels, the pause menu and options, both merchants (and Malphas's tithe dialog);
## - messages and floating texts while the floor happens: an elite dies, the boss is beaten,
##   loot is picked up, a skill is refused, a merchant door is tried.

var da: Node
var g: Node
var p: Player
var _en := {}  ## English words of keys whose Polish differs
var _pl := {}  ## words of the Polish entries
var found := {}  ## "where: word" -> text
var _msgs: Array = []
## Common English words: any of these in a Polish text is English left over, key or no key.
const ENGLISH := ["the", "and", "with", "your", "you", "for", "from", "when", "each", "that", "this", "into", "every",
	"after", "while", "until", "below", "above", "health", "damage", "target", "enemy", "enemies", "seconds", "per",
	"heals", "deals", "grants", "restores", "increases", "reduces", "chance", "level", "gold", "item", "items"]


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _load_words() -> void:
	var tr := I18nSuite.entries()
	for k in tr:
		for w in I18nSuite._words(tr[k]):
			_pl[w] = true
	for k in tr:
		if tr[k] == k:
			continue
		for w in I18nSuite._words(k):
			if not _pl.has(w):
				_en[w] = true


func scan_text(where: String, s: String) -> void:
	if s.strip_edges().is_empty():
		return
	for w in I18nSuite._words(s):
		if _en.has(w) and w != p.display_name:
			found["%s: %s" % [where, w]] = s.strip_edges().left(60)
	for w in RegEx.create_from_string("[A-Za-z]+").search_all(s):
		if ENGLISH.has(w.get_string().to_lower()):
			found["%s: %s" % [where, w.get_string()]] = s.strip_edges().left(60)
	var raw := RegEx.create_from_string("\\b[a-z]+_[a-z_]+\\b|[{}]")
	var m := raw.search(s)
	if m:
		found["%s: %s" % [where, m.get_string()]] = s.strip_edges().left(60)


func scan_tree(root: Node, where: String) -> void:
	for n in I18nSuite._all(root):
		if not (n is Control) or not n.is_visible_in_tree():
			continue
		var s := ""
		if n is Label or n is Button:
			s = n.text
		elif n is RichTextLabel:
			s = n.get_parsed_text()
		elif n is LineEdit:
			s = n.placeholder_text
		scan_text(where, s + "\n" + n.tooltip_text)
		# Hover cards built on demand.
		if n.has_method("_make_custom_tooltip") and not n.tooltip_text.is_empty():
			var tip: Variant = n._make_custom_tooltip(n.tooltip_text)
			if tip is Node:
				scan_text(where + "/tip", I18nSuite._texts(tip))
				tip.free()


func _rows_text(rows: Array) -> String:
	var parts: Array = []
	for r in rows:
		if r is Dictionary:
			parts.append("%s %s" % [r.get("k", ""), r.get("v", "")])
		elif r is Array and not r.is_empty():
			parts.append(str(r[0]))
	return "\n".join(parts)


func run() -> void:
	g = da._game()
	p = da._local()
	_load_words()
	Settings.set_language("pl")
	await da._wait(0.5)
	p.iframe_left = 9999.0
	EventBus.hud_message.connect(func(t: String, _c: Color): _msgs.append(t))
	descriptions()
	await statuses()
	await screens()
	await events()
	await menus()
	for m in _msgs:
		scan_text("message", m)
	da.check(found.is_empty(), "nothing English or raw on the Polish screens, cards and messages (%d): %s" % [found.size(), found.keys().slice(0, 25).map(func(k): return "%s [%s]" % [k, found[k]])])
	Settings.set_language("en")


## Item, skill and talent cards.
func descriptions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in GameData.item_bases:
		if str(GameData.item_bases[b].kind) == "backpack":
			scan_text("item", "\n".join(ItemGenerator.describe(ItemGenerator.generate_backpack(10, rng)).map(func(l): return str(l[0]))))
			continue
		for tier in range(1, 6):
			var it := ItemGenerator.generate_equipment(str(b), 12, tier, rng)
			scan_text("item %s" % b, "\n".join(ItemGenerator.describe(it, p.class_id, p.level).map(func(l): return str(l[0]))))
	for lid in GameData.legendaries:
		var lg := ItemGenerator.make_legendary(str(lid), 20, rng)
		scan_text("legendary %s" % lid, "\n".join(ItemGenerator.describe(lg, p.class_id, p.level).map(func(l): return str(l[0]))))
	for cid in GameData.consumables:
		scan_text("consumable %s" % cid, "\n".join(ItemGenerator.describe(ItemGenerator.generate_consumable(str(cid), 2, rng)).map(func(l): return str(l[0]))))
	# Every skill, monsters' too: their names show on cast bars.
	for sid in GameData.skills:
		var sk: Dictionary = GameData.skills[sid]
		scan_text("skill %s" % sid, Loc.t(str(sk.get("name", sid))) + "\n" + _rows_text(SkillInfo.rows(p, sk)))
	for cls in GameData.classes:
		for nd in GameData.talents.get(cls, {}).get("nodes", []):
			scan_text("talent %s" % nd.id, _rows_text(TalentInfo.rows(p, nd)))


## Every status on the HUD, with its hover text.
func statuses() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var ids: Array = GameData.status_effects.keys()
	var i := 0
	while i < ids.size():
		var batch := ids.slice(i, i + 12)
		p.status.shown = batch.map(func(id): return [id, 9.0, 2])
		hud._update_status()
		await da.get_tree().process_frame
		scan_tree(hud._status_box, "status")
		i += 12
	p.status.shown = []


func screens() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	scan_tree(hud, "hud")
	for t in UIModal.MENU_TABS:
		hud.open_overlay(hud.menu_panel(t[0]))
		await da._wait(0.4)
		scan_tree(hud._overlay, t[0])
		hud.close_overlay()
	hud.open_overlay(preload("res://scripts/ui/pause_menu.gd").new())
	await da._wait(0.3)
	scan_tree(hud._overlay, "pause")
	hud._overlay._open_settings()
	await da._wait(0.4)
	for c in hud._overlay.get_children():
		if c.has_method("_relocalize"):
			for k in c._tabs.get_tab_count():
				c._tabs.current_tab = k
				await da._wait(0.2)
				scan_tree(c, "options")
			c._close()
	await da._wait(0.3)
	hud.close_overlay()
	for kind in ["archibald", "malphas"]:
		hud.open_merchant(kind)
		await da._wait(0.4)
		scan_tree(hud._overlay, kind)
		hud.close_overlay()
	# Malphas's tithe, as his door asks it.
	g.merchants._ask_tithe("Malphas's seal asks for blood: %s for the rest of the run. The door then stays open for the whole party.", [Merchants.blood_price(int(g.layout.get("seed", 0)))])
	await da._wait(0.4)
	scan_tree(hud._overlay, "tithe")
	hud.close_overlay()


## The main menu and the lobby, built next to the game for a moment.
func menus() -> void:
	for path in [NetworkManager.MENU_SCENE, "res://scenes/menus/lobby.tscn"]:
		var scene: Node = load(path).instantiate()
		da.get_tree().root.add_child(scene)
		await da._wait(0.6)
		scan_tree(scene, path.get_file())
		scene.queue_free()
		await da._wait(0.2)


## Things that happen on a floor, each with its messages and floating texts.
func events() -> void:
	var fx_texts := func() -> void:
		for l in g.world_ui.get_children():
			if l is Label:
				scan_text("floating", l.text)
	# An elite falls (its altar message), loot and gold are picked up.
	var e: Node = g.spawn_monster(str(g.floor_def.monsters[0].id), p.global_position + Vector2(40, 0), false, {"elite": [GameData.elite_modifiers.keys()[0]]})
	await da._wait(0.3)
	for i in 6:
		if is_instance_valid(e) and e.is_alive():
			Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), e, e.health.hp + 50.0, {"damage_type": "true"})
			await da._wait(0.2)
	fx_texts.call()
	await da._wait(0.5)
	for gi in g.items_root.get_children():
		g.loot.try_pickup(p, gi)
	await da._wait(0.3)
	fx_texts.call()
	# A refused skill and a refused loadout.
	p.request_loadout.rpc_id(1, ["", "", "", "", "", ""])
	await da._wait(0.3)
	# The merchant's sealed door without the key.
	var door: Node = g.dungeon.leaf_door("merchant")
	if door and door.sealed:
		g.merchants.host_door(p, door)
		await da._wait(0.3)
	# The boss falls.
	var boss: Node = da.get_tree().get_first_node_in_group("boss")
	if boss:
		for i in 6:
			if is_instance_valid(boss) and boss.is_alive():
				Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), boss, boss.health.hp + 50.0, {"damage_type": "true"})
				await da._wait(0.3)
	await da._wait(0.5)
	fx_texts.call()
	scan_tree(da.get_tree().get_first_node_in_group("hud"), "hud after events")
