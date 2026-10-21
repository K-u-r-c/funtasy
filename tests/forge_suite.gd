class_name ForgeSuite
extends RefCounted
## #77 The blacksmith's forge (scenario "forge" solo with --forge=on, "forge_lan" host + client):
## about half of many seeded floors have a forge, a sealed leaf chamber reachable from the start
## with its own door and map icon; an upgrade costs the data price, raises item level and
## required level by one step and recomputes the item exactly as if it had dropped at that level
## (legendary scaling, boon uniques and old saves included), keeping its affixes; the cap and the
## "not enough gold" refusal hold; the window shows the comparison and plays the forging; the
## smith works his anvil and looks up at a hero; the client's upgrade goes through the host.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	p.iframe_left = 9999.0
	await da._wait(1.0)
	odds()
	layouts()
	await live_floor()
	same_as_dropped()
	await host_upgrades()
	await window()
	await long_list()
	await smith_anim()
	saved_with_floor()
	await BalanceSuite.new(da).run_forge()


## Over 400 floors the forge appears on floor_chance of them (+-8%), the same seed always agrees,
## and a forced floor has one.
func odds() -> void:
	var n := 400
	var yes := 0
	var forced := str(GameState.get_meta("force_forge", ""))
	GameState.remove_meta("force_forge")
	var stable := true
	for i in n:
		var sd := 5003 + i * 7919
		var f: bool = g.pick_forge(sd)
		stable = stable and f == g.pick_forge(sd)
		yes += 1 if f else 0
	if not forced.is_empty():
		GameState.set_meta("force_forge", forced)
	var want := float(GameData.merchants.blacksmith.floor_chance)
	var share := float(yes) / n
	da.check(absf(share - want) <= 0.08 and stable, "the forge is on %d%% of %d floors (data %d%%), seeded" % [roundi(share * 100), n, roundi(want * 100)])


## Every biome, 30 forced layouts each: one forge room with its pieces, one monster-proof forge
## door in its bottom wall, a dead end that seals with that door, never on the way to the boss
## (the boss is still the graph-farthest room), no monsters or loose props inside; and the merchant
## room is still there.
func layouts() -> void:
	var bad := ""
	for fid in ["crypt", "sewers", "foundry", "archives", "kurgan"]:
		var fd: Dictionary = GameData.floor_types[fid]
		for i in 30:
			var sd := 1777 + i * 104729
			var lay: Dictionary = DungeonGenerator.new().generate(sd, fd, 1.0, 1 + i % 10, "", true)
			var why := _forge_problem(lay)
			if not why.is_empty():
				bad = "%s seed %d: %s" % [fid, sd, why]
				break
		if not bad.is_empty():
			break
	da.check(bad.is_empty(), "150 forge floors: one sealed forge leaf with its door and pieces, the merchant room kept, the boss farthest%s" % ("" if bad.is_empty() else ": " + bad))
	var plain: Dictionary = DungeonGenerator.new().generate(1777, GameData.floor_types.crypt, 1.0, 1, "", false)
	da.check(plain.forge.is_empty() and not plain.rooms.any(func(r): return r.role == "forge"), "a floor without the forge has no forge room")


func _forge_problem(lay: Dictionary) -> String:
	var fg: Dictionary = lay.get("forge", {})
	if fg.is_empty():
		return "no forge"
	if lay.get("merchant", {}).is_empty():
		return "no merchant room"
	if lay.rooms.filter(func(r): return r.role == "forge").size() != 1 or lay.rooms[int(fg.room)].role != "forge":
		return "forge rooms: %d" % lay.rooms.filter(func(r): return r.role == "forge").size()
	for k in GameData.merchants.blacksmith.pieces:
		if not fg.has(k):
			return "missing piece %s" % k
	var rect: Rect2i = lay.rooms[int(fg.room)].rect
	for k in GameData.merchants.blacksmith.pieces:
		if not Rect2(Vector2(rect.position * 32) - Vector2(4, 4), Vector2(rect.size * 32) + Vector2(8, 8)).has_point(fg[k]):
			return "piece %s outside the room" % k
	var adj: Array = DungeonGenerator.room_graph(lay.cells, lay.size, lay.rooms)
	var hops: Dictionary = DungeonGenerator.room_hops(adj, 0)
	var boss := int(lay.boss_room)
	if not hops.has(int(fg.room)):
		return "forge unreachable"
	for i in lay.rooms.size():
		if i != boss and lay.rooms[i].role != "prison" and int(hops.get(i, 999)) >= int(hops[boss]):
			return "room %d (%s) as far as the boss" % [i, lay.rooms[i].role]
	if DungeonGenerator.room_openings(lay.cells, lay.size, rect) != 1 or adj[int(fg.room)].size() != 1:
		return "forge is not a dead end"
	var doors: Array = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(rect.grow(1)))
	if doors.size() != 1 or str(doors[0].kind) != "forge" or not doors[0].monster_proof or Rect2i(doors[0].rect).position.y != rect.end.y:
		return "forge doors %s" % [doors.map(func(d): return [d.kind, d.monster_proof])]
	for grp in lay.spawns:
		if int(grp.room) == int(fg.room) and not grp.monsters.is_empty():
			return "monsters in the forge"
	for pr in lay.props:
		if rect.has_point(Vector2i(Vector2(pr.pos) / 32.0)):
			return "a loose %s in the forge" % pr.type
	return ""


## The live floor (forced): the pieces stand, the smith can be talked to, monsters can't path in
## or target anyone inside, and the forge shows on the map once its door has been seen.
func live_floor() -> void:
	var fg: Dictionary = g.layout.get("forge", {})
	da.check(not fg.is_empty() and g.has_forge, "the test floor has the forge")
	if fg.is_empty():
		return
	var names: Array = g.dungeon.props.keys().filter(func(k): return str(k).begins_with("Forge_"))
	da.check(names.size() == GameData.merchants.blacksmith.pieces.size() and g.dungeon.props["Forge_npc"].interactable(),
		"the smith, anvil, hearth, barrel, rack, coals and ingots stand in the forge (%s)" % [names])
	var rect: Rect2i = g.layout.rooms[int(fg.room)].rect
	da.check(g.dungeon.is_safe(g.dungeon.cell_center(rect.get_center())) and g.dungeon.astar.is_point_solid(rect.get_center()), "monsters can't path into the forge")
	var door: Node = g.dungeon.leaf_door("forge")
	da.check(door != null and door.monster_proof and not door.sealed and door.type_def.get("art_closed", "") == "props.door_forge", "the forge has its own unsealed, monster-proof door")
	var before: bool = g.dungeon.map_markers().any(func(m): return m.kind == "forge")
	for c in door.cells:
		g.dungeon.mark_discovered(c)
	var mk: Array = g.dungeon.map_markers().filter(func(m): return m.kind == "forge")
	da.check(not before and mk.size() == 1 and GameData.texture("ui.map_forge") != null, "the forge's anvil shows on the map once its door is seen")
	# Talking to the smith opens the window.
	p.host_teleport(fg.npc + Vector2(0, 30))
	await da._wait(0.4)
	var offer: Dictionary = g.find_interactable(p, 0)
	g.host_interact(p, g.dungeon.props["Forge_npc"])
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(hud._overlay != null and hud._overlay.get("stage") != null, "talking to Rolf opens the forge window (prompt: %s)" % offer.get("text", ""))
	hud.close_overlay()
	await da._wait(0.3)


## Raising an item one level gives exactly the item that drops at that level: every rarity of
## many bases, a legendary (D7 scaling), a boon's unique item; an old save's item still grows.
func same_as_dropped() -> void:
	var bad := ""
	var bases: Array = GameData.item_bases.keys().filter(func(b): return str(GameData.item_bases[b].get("kind", "")) in ["weapon", "offhand", "armor", "jewelry"])
	bases.sort()
	var tested := 0
	for bi in bases.size():
		var b: String = bases[bi]
		for tier in range(1, 5):
			var lvl := 1 + (bi * 3 + tier) % 25
			var r1 := RandomNumberGenerator.new()
			r1.seed = 900 + bi * 17 + tier
			ItemGenerator._uid_counter = 5000
			var it := ItemGenerator.generate_equipment(b, lvl, tier, r1)
			var r2 := RandomNumberGenerator.new()
			r2.seed = 900 + bi * 17 + tier
			ItemGenerator._uid_counter = 5000
			var want := ItemGenerator.generate_equipment(b, lvl + 1, tier, r2)
			var got := ItemGenerator.at_level(it, lvl + 1)
			var why := _differs(got, want)
			if why.is_empty() and (got.name != it.name or got.uid != it.uid):
				why = "name / uid not kept"
			tested += 1
			if not why.is_empty():
				bad = "%s r%d L%d: %s" % [b, tier, lvl, why]
				break
		if not bad.is_empty():
			break
	da.check(bad.is_empty(), "%d rolled items raised a level match the same items dropped there (name and uid kept)%s" % [tested, "" if bad.is_empty() else ": " + bad])
	var lg := ItemGenerator.make_legendary("crown_blood_chieftain", 4, RandomNumberGenerator.new())
	var lg5 := ItemGenerator.make_legendary("crown_blood_chieftain", 5, RandomNumberGenerator.new())
	var up := ItemGenerator.at_level(lg, 5)
	da.check(_differs(up, lg5).is_empty() and up.affix == lg.affix and up.procs == lg.procs and up.uid == lg.uid,
		"a legendary raised to 5 scales like one dropped at 5 and keeps its affix and procs (%s)" % _differs(up, lg5))
	var bd: Dictionary = {}
	for id in GameData.boons:
		if str(GameData.boons[id].get("give", {}).get("type", "")) == "unique":
			bd = GameData.boons[id]
			break
	if not bd.is_empty():
		var ra := RandomNumberGenerator.new()
		ra.seed = 77
		ItemGenerator._uid_counter = 6000
		var u6: Dictionary = Boons.give_items(bd, p, 6, ra)[0]
		var rb := RandomNumberGenerator.new()
		rb.seed = 77
		ItemGenerator._uid_counter = 6000
		var u7: Dictionary = Boons.give_items(bd, p, 7, rb)[0]
		da.check(_differs(ItemGenerator.at_level(u6, 7), u7).is_empty(), "a boon's unique item raised to 7 matches the one given at 7 (%s)" % _differs(ItemGenerator.at_level(u6, 7), u7))
	# An item saved before the rolls were kept still grows.
	var old := ItemGenerator.generate_equipment("plate_chest", 5, 3, RandomNumberGenerator.new())
	old.erase("rolls")
	var oup := ItemGenerator.at_level(old, 6)
	var grew: bool = int(oup.ilvl) == 6 and int(oup.req) == 6 and int(oup.armor) > int(old.armor) and oup.stats.keys() == old.stats.keys()
	for k in old.stats:
		grew = grew and float(oup.stats[k]) >= float(old.stats[k])
	da.check(grew, "an item from an older save still grows a level, keeping its stats")


func _differs(a: Dictionary, b: Dictionary) -> String:
	for k in ["ilvl", "req", "dps", "armor", "rarity", "quality", "affix", "base"]:
		if a.has(k) != b.has(k) or (a.has(k) and str(a[k]) != str(b[k])):
			return "%s %s vs %s" % [k, a.get(k), b.get(k)]
	if a.stats.keys().size() != b.stats.keys().size():
		return "stats %s vs %s" % [a.stats, b.stats]
	for k in a.stats:
		if not b.stats.has(k) or absf(float(a.stats[k]) - float(b.stats[k])) > 0.0001:
			return "stat %s %s vs %s" % [k, a.stats.get(k), b.stats.get(k)]
	return ""


## The host-side upgrade: price, levels, numbers, affixes, the worn item's effect on the hero,
## the cap, not enough gold and out of reach.
func host_upgrades() -> void:
	var fg: Dictionary = g.layout.forge
	p.level = 10
	p.recompute_stats()
	p.host_teleport(fg.npc + Vector2(0, 30))
	await da._wait(0.3)
	var helm := ItemGenerator.generate_equipment("plate_helm", 3, 3, RandomNumberGenerator.new())
	p.inv.equipment["head"] = helm
	p._inventory_changed()
	await da._wait(0.2)
	var armor0: float = p.stats.get_stat("armor")
	p.gold = 0
	p.host_add_gold(1000)
	var price := Forge.cost(helm)
	g.forge.request_upgrade.rpc_id(1, "equip", "head", str(helm.uid))
	await da._wait(0.2)
	var now: Dictionary = p.inv.equipment.get("head", {})
	var want := ItemGenerator.at_level(helm, 4)
	da.check(p.gold == 1000 - price and price == Forge.cost(helm) and price > 0, "the upgrade costs the data price (%d gold)" % price)
	da.check(int(now.ilvl) == 4 and int(now.req) == 4 and int(now.get("forged", 0)) == 1 and _differs(now, want).is_empty() and now.uid == helm.uid,
		"the worn helm is item level 4, requires 4, numbers as dropped at 4, affixes kept (%s)" % _differs(now, want))
	# One step may round to the same armor: forge on until the helm's armor rises.
	for i in 3:
		if int(p.inv.equipment.head.get("armor", 0)) > int(helm.get("armor", 0)):
			break
		g.forge.request_upgrade.rpc_id(1, "equip", "head", str(helm.uid))
		await da._wait(0.2)
	da.check(p.stats.get_stat("armor") > armor0, "the hero's armor rises with the forged helm (%d -> %d)" % [armor0, p.stats.get_stat("armor")])
	p.gold = 1000 - price
	# A legendary in the backpack, twice in a row: the price grows with its level.
	var lg := ItemGenerator.make_legendary("crown_blood_chieftain", 2, RandomNumberGenerator.new())
	p.host_give_item(lg)
	var bi: int = p.inv.backpack.size() - 1
	var c1 := Forge.cost(lg)
	g.forge.request_upgrade.rpc_id(1, "bag", str(bi), str(lg.uid))
	await da._wait(0.1)
	var lg3: Dictionary = p.inv.backpack[bi]
	var c2 := Forge.cost(lg3)
	g.forge.request_upgrade.rpc_id(1, "bag", str(bi), str(lg.uid))
	await da._wait(0.1)
	var lg4: Dictionary = p.inv.backpack[bi]
	da.check(int(lg4.ilvl) == 4 and int(lg4.forged) == 2 and c2 > c1 and lg4.affix == lg.affix and p.gold == 1000 - price - c1 - c2,
		"a legendary in the backpack forged twice: level 4, the second step dearer (%d, %d)" % [c1, c2])
	var cost_r: Array = []
	for r in range(1, 6):
		var it := ItemGenerator.generate_equipment("plate_helm", 5, r, RandomNumberGenerator.new()) if r < 5 else ItemGenerator.make_legendary("crown_blood_chieftain", 5, RandomNumberGenerator.new())
		it.erase("quality_mult")
		cost_r.append(Forge.cost(it))
	# #92: every step costs 1.5x the old price (base 10 -> 15), for every rarity and level.
	var off: Array = []
	for r in range(1, 6):
		for lv in [1, 5, 12, 25]:
			var it2 := ItemGenerator.generate_equipment("plate_helm", lv, r, RandomNumberGenerator.new())
			var rm: Array = Forge.cfg("rarity_mult")
			var old := 10.0 * float(rm[r - 1]) * pow(1.0 + float(Forge.cfg("per_level")) * (lv - 1), float(Forge.cfg("level_exponent"))) * float(it2.get("quality_mult", 1.0))
			if absi(Forge.cost(it2) - roundi(old * 1.5)) > 1:
				off.append("r%d L%d %d vs %.0f" % [r, lv, Forge.cost(it2), old])
	da.check(off.is_empty(), "forging costs 1.5x the old price (%s)" % [off])
	var rising := true
	for i in range(1, cost_r.size()):
		rising = rising and cost_r[i] > cost_r[i - 1]
	da.check(rising, "rarer items cost more to forge (%s)" % [cost_r])
	# The cap: the hero's level and the floor's item level.
	var cap := Forge.cap_for(p.level, g.item_level())
	var top := ItemGenerator.generate_equipment("boots", cap, 2, RandomNumberGenerator.new())
	p.host_give_item(top)
	var ti: int = p.inv.backpack.size() - 1
	var g0 := p.gold
	g.forge.request_upgrade.rpc_id(1, "bag", str(ti), str(top.uid))
	await da._wait(0.1)
	da.check(int(p.inv.backpack[ti].ilvl) == cap and p.gold == g0 and not str(Forge.refusal(top, p.level, g.item_level(), p.gold)[0]).is_empty(),
		"an item at the cap (item level %d = min(hero %d, floor %d)) is refused, no gold taken" % [cap, p.level, g.item_level()])
	da.check(Forge.cap_for(5, 9) == 5 and Forge.cap_for(12, 7) == 7, "the cap is the hero's level, never above the floor's item level")
	# Not enough gold.
	var cheap := ItemGenerator.generate_equipment("gloves", 1, 2, RandomNumberGenerator.new())
	p.host_give_item(cheap)
	var ci: int = p.inv.backpack.size() - 1
	p.gold = Forge.cost(cheap) - 1
	g.forge.request_upgrade.rpc_id(1, "bag", str(ci), str(cheap.uid))
	await da._wait(0.1)
	da.check(int(p.inv.backpack[ci].ilvl) == 1 and p.gold == Forge.cost(cheap) - 1, "not enough gold: refused, the item and gold unchanged")
	# Out of reach of the smith.
	p.gold = 500
	p.host_teleport(g.nearest_floor(g.layout.start))
	await da._wait(0.3)
	g.forge.request_upgrade.rpc_id(1, "bag", str(ci), str(cheap.uid))
	await da._wait(0.1)
	da.check(int(p.inv.backpack[ci].ilvl) == 1 and p.gold == 500, "away from the smith nothing is forged")
	# A stale uid (the list changed) is ignored.
	p.host_teleport(fg.npc + Vector2(0, 30))
	await da._wait(0.3)
	g.forge.request_upgrade.rpc_id(1, "bag", str(ci), "nope")
	await da._wait(0.1)
	da.check(int(p.inv.backpack[ci].ilvl) == 1, "a request for a different item is ignored")


## The window: one row per workable item, the comparison card, the price and the gold, the button
## disabled with a reason at the cap; forging plays the anvil (strikes, quench, glow) and the card
## flashes the raised numbers.
func window() -> void:
	var fg: Dictionary = g.layout.forge
	p.host_teleport(fg.npc + Vector2(0, 30))
	p.gold = 800
	await da._wait(0.3)
	g.host_interact(p, g.dungeon.props["Forge_npc"])
	await da._wait(0.6)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Node = hud._overlay
	if panel == null or panel.get("rows") == null:
		da.check(false, "the forge window is open")
		return
	var workable := 0
	for s in p.inv.equipment:
		workable += 1 if Forge.workable(p.inv.equipment[s]) else 0
	for it in p.inv.backpack:
		workable += 1 if Forge.workable(it) else 0
	da.check(panel.rows.size() == workable, "one row per workable item (%d)" % workable)
	var top_row: Dictionary = {}
	var cheap_row: Dictionary = {}
	for r in panel.rows:
		if int(r.item.ilvl) >= Forge.cap_for(p.level, g.item_level()):
			top_row = r
		elif r.item.base == "gloves":
			cheap_row = r
	top_row.button.grab_focus()
	await da._wait(0.2)
	da.check(panel._button.disabled and not panel._reason.text.is_empty(), "at the cap the Forge button is off with the reason (%s)" % panel._reason.text)
	cheap_row.button.grab_focus()
	await da._wait(0.2)
	da.check(not panel._button.disabled and panel._card.get_child_count() >= 4, "a workable item shows its now -> after card and the button is on")
	# #90: a click on a row only selects it; hovering another previews it; the button forges.
	var g_sel := p.gold
	var lvl_sel := int(cheap_row.item.ilvl)
	cheap_row.button.pressed.emit()
	await da._wait(0.4)
	var still: Dictionary = {}
	for it in p.inv.backpack:
		if it.uid == cheap_row.item.uid:
			still = it
	da.check(p.gold == g_sel and int(still.get("ilvl", 0)) == lvl_sel and panel._sel_uid == str(cheap_row.item.uid) and not panel.stage.busy(),
			"clicking a row selects it and forges nothing")
	top_row.button.mouse_entered.emit()
	await da.get_tree().process_frame
	var shown: String = panel._card.get_child(0).text if panel._card.get_child_count() > 0 else ""
	da.check(shown == Loc.item_name(top_row.item) and panel._sel_uid == str(cheap_row.item.uid) and not panel._button.disabled,
			"hovering another row previews its card; the selection and the button stay")
	top_row.button.mouse_exited.emit()
	await da.get_tree().process_frame
	shown = panel._card.get_child(0).text if panel._card.get_child_count() > 0 else ""
	da.check(shown == Loc.item_name(still), "leaving it shows the selected piece again")
	var kind0 := InputSettings.last_kind
	InputSettings.last_kind = "pad"
	cheap_row.button.grab_focus()
	cheap_row.button.pressed.emit()
	await da.get_tree().process_frame
	da.check(panel._button.has_focus(), "with a gamepad, accept on a row moves on to the Forge button")
	InputSettings.last_kind = kind0
	var lvl0 := int(cheap_row.item.ilvl)
	# #91: from the press until the light is gone the window, the card and the list keep their
	# rects on every frame; no "forged" message; the card's light plays.
	var msgs: Array = []
	var on_msg := func(t: String, _c: Color): msgs.append(t)
	EventBus.hud_message.connect(on_msg)
	var watch := [panel.window, panel._card_panel, panel._list.get_parent(), panel.stage]
	var rects0: Array = watch.map(func(c): return c.get_global_rect())
	var jumps: Array = []
	var shines0: int = panel.shines
	var lit := [false]  # an array: a lambda can't assign a captured local
	var sampler := func():
		for i in watch.size():
			if not watch[i].get_global_rect().is_equal_approx(rects0[i]):
				jumps.append("%s %s -> %s" % [watch[i].name, rects0[i], watch[i].get_global_rect()])
		lit[0] = lit[0] or panel._shine.visible
	da.get_tree().process_frame.connect(sampler)
	panel._button.pressed.emit()
	await da._wait_until(func(): return panel.stage.phase == "strike", 2.0)
	da.check(panel.stage.phase == "strike", "forging: the hammer strikes on the anvil")
	await da._wait_until(func(): return panel.stage.phase == "", 4.0)
	var took: float = panel.stage.last_duration
	await da._wait(0.2)
	da.check(panel.stage.strikes == 3 and panel.flashed.size() >= 2, "three strikes, the quench and the glow; the card flashes the raised numbers (%s)" % [panel.flashed])
	da.check(took > 0.5 and took < 2.0, "the forging is short (%.2f s, it was 3)" % took)
	var now: Dictionary = {}
	for it in p.inv.backpack:
		if it.uid == cheap_row.item.uid:
			now = it
	da.check(int(now.get("ilvl", 0)) == lvl0 + 1, "the gloves came back one level higher")
	await da._wait(0.9)
	da.get_tree().process_frame.disconnect(sampler)
	EventBus.hud_message.disconnect(on_msg)
	da.check(jumps.is_empty(), "the window, the card and the list never move during the forging and after it (%s)" % [jumps.slice(0, 2)])
	da.check(msgs.is_empty(), "no text message about the upgrade (%s)" % [msgs])
	da.check(panel.shines == shines0 + 1 and lit[0] and not panel._shine.visible, "a light sweeps the card once the piece is back, then goes")
	# #89: clicking through: Forge again while the anvil works ends its animation at once and the
	# next step goes out; each step is paid once.
	var gold0 := p.gold
	var c1 := Forge.cost(now)
	panel._forge_selected()
	await da._wait_until(func(): return panel.stage.phase == "strike", 2.0)
	da.check(not panel._button.disabled, "the Forge button stays ready while the anvil works")
	var mid: Dictionary = {}
	for it in p.inv.backpack:
		if it.uid == cheap_row.item.uid:
			mid = it
	var c2 := Forge.cost(mid)
	panel._forge_selected()
	da.check(panel.stage.phase == "" or panel.stage.strikes == 0, "forging again ends the running animation at once")
	await da._wait(0.3)
	for it in p.inv.backpack:
		if it.uid == cheap_row.item.uid:
			now = it
	da.check(int(now.get("ilvl", 0)) == lvl0 + 3 and p.gold == gold0 - c1 - c2, "two quick clicks forge two steps, each paid once (%d -> %d, %d gold)" % [lvl0 + 1, int(now.get("ilvl", 0)), gold0 - p.gold])
	await da._wait_until(func(): return panel.stage.phase == "", 3.0)
	hud.close_overlay()
	await da._wait(0.3)


## #97: with more gear than fits, the list scrolls down and stays there - while the mouse moves
## over rows, while a row is selected and forged, after the forging and when the gold changes.
func long_list() -> void:
	var fg: Dictionary = g.layout.forge
	p.host_teleport(fg.npc + Vector2(0, 30))
	p.inv.capacity = maxi(p.inv.capacity, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	while p.inv.backpack.size() < 30:
		p.inv.backpack.append(ItemGenerator.generate_equipment(LootTable.pick_base([p.class_id], rng), 2, rng.randi_range(1, 3), rng))
	p._inventory_changed()
	p.gold = 5000
	await da._wait(0.3)
	g.host_interact(p, g.dungeon.props["Forge_npc"])
	await da._wait(0.6)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Node = hud._overlay
	var sc: ScrollContainer = panel._list.get_parent()
	# The first row is selected; the wheel then takes the list to its end.
	panel.rows[0].button.grab_focus()
	await da._wait(0.2)
	sc.scroll_vertical = 100000
	await da._wait(0.3)
	var bottom := sc.scroll_vertical
	da.check(bottom > 100, "a long list scrolls down (%d px)" % bottom)
	var low: Array = panel.rows.slice(panel.rows.size() - 6)
	for r in low:
		r.button.mouse_entered.emit()
		await da._wait(0.15)
		r.button.mouse_exited.emit()
	await da._wait(0.5)
	da.check(sc.scroll_vertical == bottom, "hovering rows keeps the list where it was (%d -> %d)" % [bottom, sc.scroll_vertical])
	p.host_add_gold(-1)
	await da._wait(0.5)
	da.check(sc.scroll_vertical == bottom, "a change of gold doesn't send the list back up (%d -> %d)" % [bottom, sc.scroll_vertical])
	p.host_give_item(ItemGenerator.generate_consumable("potion_health", 1, rng))
	await da._wait(0.5)
	da.check(sc.scroll_vertical == bottom, "a change in the backpack doesn't either (%d -> %d)" % [bottom, sc.scroll_vertical])
	# A low row is picked and forged: the list stays down through the forging and after it.
	var pick: Dictionary = low[low.size() - 2]
	pick.button.grab_focus()
	pick.button.pressed.emit()
	await da._wait(0.2)
	var at := sc.scroll_vertical
	panel._button.pressed.emit()
	await da._wait_until(func(): return panel.stage.phase == "", 4.0)
	await da._wait(0.5)
	da.check(sc.scroll_vertical == at and panel._sel_uid == str(pick.item.uid), "after forging a low row the list stays where it was, the row still selected (%d -> %d)" % [at, sc.scroll_vertical])
	hud.close_overlay()
	await da._wait(0.3)


## The smith works on his own: strikes with impacts, a rest, and he looks up at a hero close by;
## an upgrade has him strike the piece and quench it.
func smith_anim() -> void:
	var anim: NpcAnim = g.dungeon.props["Forge_npc"].get_node("NpcAnim")
	p.host_teleport(g.nearest_floor(g.layout.start))
	# The window's forging may still be on the anvil: let it finish first.
	await da._wait_until(func(): return anim._queue.is_empty(), 8.0)
	anim.log.clear()
	anim._look_cd = 0.0
	var i0 := anim.impacts
	await da._wait_until(func(): return anim.impacts > i0, 12.0)
	da.check(anim.impacts > i0 and anim.log.has("strike"), "Rolf hammers his anvil on his own (sparks on the impact; %s)" % [anim.log])
	p.host_teleport(g.layout.forge.npc + Vector2(0, 40))
	await da._wait_until(func(): return anim.log.has("look"), 14.0)
	da.check(anim.log.has("look"), "Rolf looks up when a hero comes close")
	var i1 := anim.impacts
	anim.work_piece()
	await da._wait(5.0)
	da.check(anim.impacts >= i1 + 3, "an upgrade: three strikes on the piece and the quench")


## #55: the forge is part of the floor's save.
func saved_with_floor() -> void:
	var snap: Dictionary = FloorState.capture(g, {})
	da.check(bool(snap.get("forge", false)), "the floor's save records its forge")


# =========================================================================================
# LAN
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	var fg: Dictionary = g.layout.get("forge", {})
	da.check(not fg.is_empty(), "host: the floor has the forge")
	if fg.is_empty():
		return
	c.iframe_left = 9999.0
	c.level = 9
	c.recompute_stats()
	# The floor's item level is ~3 for a party of levels 1 and 9: a level 2 ring can rise to 3.
	var ring := ItemGenerator.generate_equipment("ring", 2, 4, RandomNumberGenerator.new())
	c.host_give_item(ring)
	c.gold = 0
	c.host_add_gold(500)
	c.host_teleport(fg.npc + Vector2(0, 30))
	await da._wait(1.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fg_forge", str(ring.uid)])
	await da._wait_until(func(): return c.inv.backpack.any(func(it): return it.uid == ring.uid and int(it.ilvl) == 3), 6.0)
	var got: Dictionary = {}
	for it in c.inv.backpack:
		if it.uid == ring.uid:
			got = it
	var price := Forge.cost(ring, 2)
	da.check(int(got.get("ilvl", 0)) == 3 and c.gold == 500 - price and price < Forge.cost(ring, 1) and _differs(got, ItemGenerator.at_level(ring, 3)).is_empty(),
		"host: the client's ring forged through the RPC (item level 3, %d gold paid: the price for a hero of two)" % price)
	await da._wait(3.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"fg_forge":
			da.check(g.has_forge and not g.layout.get("forge", {}).is_empty() and g.dungeon.props.has("Forge_npc"), "client: the forge stands on my floor too")
			p.request_interact.rpc_id(1, g.dungeon.props["Forge_npc"].get_path())
			await da._wait_until(func(): return da.get_tree().get_first_node_in_group("hud")._overlay != null, 3.0)
			var panel: Node = da.get_tree().get_first_node_in_group("hud")._overlay
			da.check(panel != null and panel.get("rows") != null, "client: talking to Rolf opens my forge window")
			if panel == null or panel.get("rows") == null:
				return
			for r in panel.rows:
				if str(r.item.uid) == str(arg):
					r.button.grab_focus()
			await da._wait(0.2)
			panel._forge_selected()
			await da._wait_until(func(): return panel.stage.phase == "strike", 3.0)
			da.check(panel.stage.phase == "strike", "client: the anvil plays my forging")
			await da._wait_until(func(): return panel.stage.phase == "", 4.0)
			var mine: Dictionary = {}
			for it in p.inv.backpack:
				if str(it.uid) == str(arg):
					mine = it
			da.check(int(mine.get("ilvl", 0)) == 3 and panel.flashed.size() >= 1, "client: my ring is item level 3 and the card flashed it")
