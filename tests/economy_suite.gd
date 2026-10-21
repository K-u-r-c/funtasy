class_name EconomySuite
extends RefCounted
## Headless progression and economy checks on a solo host (scenario "economy"): stat points,
## run modifiers and their save round trip, gold, the Gold Key, elites, merchants, pacts and
## contracts. LAN parts (gold split, shared stock) run in the economy-lan pair.

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
	await stat_points()
	await run_mods()
	await talents_and_loadout()
	await gold()
	await elites_and_key()
	item_compare()
	await merchants()
	await map_markers()


func stat_points() -> void:
	var before_pts := p.stat_points
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.3)
	da.check(p.stat_points == before_pts + int(GameData.bal("progression.stat_points_per_level")), "level up gives %d stat points (%d)" % [GameData.bal("progression.stat_points_per_level"), p.stat_points])
	var str_before := p.stats.get_stat("strength")
	p.request_spend_stat.rpc_id(1, "strength", 2)
	await da._wait(0.3)
	da.check(p.stats.get_stat("strength") >= str_before + 1.99, "spending 2 points raises Strength (%.1f -> %.1f)" % [str_before, p.stats.get_stat("strength")])
	da.check(p.stat_points == before_pts + int(GameData.bal("progression.stat_points_per_level")) - 2, "two points were spent")
	p.request_spend_stat.rpc_id(1, "luck", 1)
	await da._wait(0.2)
	da.check(not p.allocated.has("luck"), "unknown stats are refused")
	var ch := p.to_character()
	da.check(int(ch.allocated.get("strength", 0)) == 2, "allocation is saved with the hero")


func run_mods() -> void:
	var hp_before := p.stats.get_stat("max_hp")
	p.host_add_run_mod("max_hp", -10.0, "Demonic tithe")
	p.host_add_run_mod("strength", 2.0, "Tome")
	await da._wait(0.3)
	da.check(absf(p.stats.get_stat("max_hp") - (hp_before - 10.0)) < 0.6 or p.stats.get_stat("max_hp") < hp_before, "run modifier lowers max health")
	var ch := p.to_character()
	da.check(ch.run_mods.size() >= 2, "run modifiers are saved with the hero")
	var saved: Dictionary = SaveSystem.load_game(str(GameState.game.get("id", "")))
	var found := false
	for m in saved.get("members", [{}])[0].get("run_mods", []):
		if str(m.get("source", "")) == "Demonic tithe":
			found = true
	da.check(found, "run modifiers reach the saved game file")
	p.host_add_gold(37)
	da.check(p.gold >= 37 and int(p.to_character().gold) == p.gold, "gold is kept on the hero")


func talents_and_loadout() -> void:
	# Talent tree v2: the two starters are free, tiers open per branch.
	var tree := p.talent_tree()
	da.check(tree.get("branches", []).size() == 3, "talent tree has 3 branches")
	da.check(p.unlocked_skills().size() == 2, "the primary and the basic skill are unlocked (%d)" % p.unlocked_skills().size())
	p.add_xp(Player.xp_to_next(p.level))
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.3)
	var deep := {}
	var low := {}
	for nd in tree.nodes:
		if nd.get("type", "") == "passive" and int(nd.get("tier", 0)) >= 1 and deep.is_empty():
			deep = nd
		if nd.get("type", "") == "passive" and int(nd.get("tier", 0)) == 0 and low.is_empty():
			low = nd
	var pts := p.talent_points
	p.request_learn_talent.rpc_id(1, str(deep.id))
	await da._wait(0.2)
	da.check(int(p.talents.get(deep.id, 0)) == 0, "a tier %d talent is locked without points in its branch" % int(deep.tier))
	p.request_learn_talent.rpc_id(1, str(low.id))
	await da._wait(0.2)
	da.check(int(p.talents.get(low.id, 0)) == 1 and p.talent_points == pts - 1, "a tier 0 passive can be learned")
	# Loadout: swapping is fine out of combat, a non-primary skill can't be the primary attack.
	var lo: Array = p.skills.duplicate()
	var swapped := lo.duplicate()
	swapped[1] = lo[2]
	swapped[2] = lo[1]
	p.resource._since_combat = 99.0
	p.request_loadout.rpc_id(1, swapped)
	await da._wait(0.2)
	da.check(p.skills == swapped, "loadout swap applied")
	var bad := swapped.duplicate()
	bad[0] = swapped[1]
	bad[1] = swapped[0]
	p.request_loadout.rpc_id(1, bad)
	await da._wait(0.2)
	da.check(p.skills == swapped, "a non-primary skill can't take the primary slot")
	p.resource.mark_combat()
	p.request_loadout.rpc_id(1, lo)
	await da._wait(0.2)
	da.check(p.skills == swapped, "the loadout can't change in combat")
	da.check(p.to_character().loadout == swapped, "the loadout is saved with the hero")


func gold() -> void:
	var rng := RandomNumberGenerator.new()
	var pile := LootTable.gold_pile("chest", 3, rng)
	da.check(int(pile.get("amount", 0)) > 0 and pile.kind == "gold", "chests drop gold piles (%d)" % int(pile.get("amount", 0)))
	var before := p.gold
	g.loot.drop_item(LootTable.make_gold(40, rng), p.global_position + Vector2(10, 0))
	await da._wait(0.3)
	var gi: Node = null
	for it in g.items_root.get_children():
		if it.item.get("kind", "") == "gold":
			gi = it
	da.check(gi != null, "a gold pile lies on the ground")
	if gi:
		g.loot.try_pickup(p, gi)
		await da._wait(0.2)
		da.check(p.gold == before + 40, "picking up 40 gold alone gives all of it (%d -> %d)" % [before, p.gold])


func elites_and_key() -> void:
	var elites := 0
	for e in g.enemies_root.get_children():
		if e.is_elite():
			elites += 1
	var packs: Array = GameData.bal("elite.packs")
	da.check(elites >= int(packs[0]) and elites <= int(packs[1]), "the floor has %d elites" % elites)
	var e: Enemy = g.spawn_monster("ghoul", g.nearest_floor(p.global_position + Vector2(40, 0)), false, {"elite": ["vampiric", "shielded"], "key": true})
	await da._wait(0.4)
	da.check(e.is_elite() and e.display_name.begins_with("Vampiric Shielded"), "elite named after its modifiers (%s)" % e.display_name)
	da.check(e.health.absorb > 0.0 and e.stats.get_stat("leech") > 0.3, "elite modifiers apply (shield %d, leech %.2f)" % [e.health.absorb, e.stats.get_stat("leech")])
	var props_before: int = g.dungeon.props.size()
	var items_before: int = g.items_root.get_child_count()
	e.health.take(e.health.hp + e.health.absorb + 1.0)
	await da._wait(0.5)
	da.check(g.dungeon.props.size() == props_before + 1, "an elite altar rises where the elite died")
	var key: Node = null
	for it in g.items_root.get_children():
		if it.item.get("kind", "") == "gold_key":
			key = it
	da.check(key != null and g.items_root.get_child_count() >= items_before + 2, "the key carrier drops the Gold Key and gold")
	if key:
		p.host_teleport(key.global_position)
		await da._wait(0.2)
		g.loot.try_pickup(p, key)
		await da._wait(0.2)
		da.check(g.party_keys == 1, "the Gold Key goes to the party (%d)" % g.party_keys)
	var altar: Node = null
	for pr in g.dungeon.props.values():
		if pr.type == "elite_altar":
			altar = pr
	if altar:
		p.host_teleport(altar.global_position + Vector2(0, 16))
		await da._wait(0.2)
		var n: int = g.items_root.get_child_count()
		g.host_interact(p, altar)
		await da._wait(0.3)
		da.check(altar.opened and g.items_root.get_child_count() > n, "praying at the altar gives loot once")
	# #21 chest fallback: the chest named by key_chest drops the Gold Key when opened.
	var chest: Node = null
	for k in g.dungeon.props:
		if str(k).begins_with("Chest_") and g.dungeon.props[k].interactable():
			chest = g.dungeon.props[k]
			break
	if chest == null:
		da.check(false, "the floor has an unopened chest for the key fallback")
		return
	g.key_chest = chest.prop_id
	p.host_teleport(g.nearest_floor(chest.interact_pos()))
	await da._wait(0.3)
	g.host_interact(p, chest)
	await da._wait(0.4)
	var chest_key: Array = g.items_root.get_children().filter(func(it): return it.item.get("kind", "") == "gold_key")
	da.check(chest_key.size() == 1 and g.key_chest.is_empty(), "the key chest drops the Gold Key once (%d)" % chest_key.size())


## Item card comparison (#11): a 2H weapon against the main AND off hand together (the off-hand
## stats it would remove are losses), an off-hand item against a worn 2H weapon.
func item_compare() -> void:
	var panel: Script = load("res://scripts/ui/inventory_panel.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var inv := Inventory.new()
	var sword := ItemGenerator.generate_equipment("sword", 10, 2, rng)
	var relic := ItemGenerator.generate_equipment("trinket", 10, 5, rng)
	inv.equipment = {"main_hand": sword, "off_hand": relic}
	var staff := ItemGenerator.generate_equipment("holy_staff", 10, 1, rng)
	staff.erase("stats")
	var rep2: Array = inv.replaced_by(staff)
	var lines: Array = panel.compare_lines(staff, rep2)
	var relic_stats: Dictionary = relic.get("stats", {})
	var losses_ok := not relic_stats.is_empty()
	for k in relic_stats:
		var label: String = GameData.affixes.stat_names.get(k, k)
		var found := false
		for l in lines:
			if str(l[0]).contains(label) and str(l[0]).begins_with("-") and l[1] == UITheme.DANGER:
				found = true
		losses_ok = losses_ok and (found or float(staff.get("stats", {}).get(k, 0.0)) >= float(relic_stats[k]))
	da.check(rep2.size() == 2 and rep2.has(sword) and rep2.has(relic) and losses_ok,
			"a 2H weapon compares against the main and the off hand: the relic's stats show as losses (%s)" % [lines])
	# An off-hand item against a worn 2H weapon: the weapon's DPS is what it would cost.
	var inv2 := Inventory.new()
	inv2.equipment = {"main_hand": staff}
	var shield := ItemGenerator.generate_equipment("shield", 10, 2, rng)
	var rep3: Array = inv2.replaced_by(shield)
	var lines2: Array = panel.compare_lines(shield, rep3)
	da.check(rep3 == [staff] and lines2.any(func(l): return str(l[0]).begins_with("-") and str(l[0]).contains(str(GameData.affixes.stat_names.get("dps", "dps")))),
			"an off-hand item compares against the worn 2H weapon it would replace (%s)" % [lines2])
	# A 1H weapon goes next to a 1H weapon (nothing replaced) and replaces a 2H one.
	var inv3 := Inventory.new()
	inv3.equipment = {"main_hand": sword}
	da.check(inv3.replaced_by(ItemGenerator.generate_equipment("sword", 10, 1, rng)).is_empty()
			and inv2.replaced_by(ItemGenerator.generate_equipment("sword", 10, 1, rng)) == [staff], "a 1H weapon compares against whatever it would replace")


## Rare upgrade drops (#8): about loot.upgrade_chance of the items come 2-3 levels above the item
## level and one rarity tier higher (clamped at Relic).
func upgrade_drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var n := 20000
	var ups := 0
	var bad := ""
	var lv: Array = GameData.bal("loot.upgrade_levels")
	for i in n:
		var tier := 1 + i % 5
		var r := LootTable.upgrade_roll(10, tier, rng)
		if int(r[0]) != 10:
			ups += 1
			if int(r[0]) < 10 + int(lv[0]) or int(r[0]) > 10 + int(lv[1]) or int(r[1]) != mini(tier + 1, 5):
				bad = "%s from tier %d" % [r, tier]
		elif int(r[1]) != tier:
			bad = "rarity changed without an upgrade"
	var rate := float(ups) / n
	var want := float(GameData.bal("loot.upgrade_chance"))
	da.check(absf(rate - want) < 0.006 and bad.is_empty(), "%.1f%% of drops are +2-3 level, +1 rarity upgrades (want %.0f%%)%s" % [rate * 100.0, want * 100.0, "" if bad.is_empty() else ": " + bad])
	var top := LootTable.upgrade_roll(int(GameData.bal("progression.max_level")), 5, RandomNumberGenerator.new())
	da.check(int(top[0]) <= int(GameData.bal("progression.max_level")), "an upgrade never goes past the level cap")
	# Every equipment drop goes through it: chest rolls show the upgrades too.
	var seen := 0
	var items := 0
	for i in 3000:
		for it in LootTable.roll("chest", 8, 3, ["warrior"], rng):
			if it.get("kind", "") in ["weapon", "armor", "jewelry"] or it.has("slot"):
				if not it.has("legendary"):
					items += 1
					if int(it.get("ilvl", 8)) > 8:
						seen += 1
	da.check(items > 0 and absf(float(seen) / items - want) < 0.01, "chest equipment: %d of %d are upgrades" % [seen, items])


func merchants() -> void:
	await upgrade_drops()
	await merchant_rules()
	merchant_odds()
	await _force_merchant("archibald")
	var m: Dictionary = g.layout.get("merchant", {})
	da.check(not m.is_empty() and str(m.npc) == "archibald", "the floor has a merchant room (%s)" % m.get("npc", "none"))
	if m.is_empty():
		return
	var room: Rect2i = g.layout.rooms[int(m.room)].rect
	var spawned_inside := false
	for e in g.enemies_root.get_children():
		if room.has_point(g.dungeon.cell_of(e.global_position)) and not e.is_elite() and e.def_id != "ghoul":
			spawned_inside = true
	da.check(not spawned_inside, "no monsters spawn in the merchant room")
	da.check(g.dungeon.is_safe(g.dungeon.cell_center(room.get_center())) and g.dungeon.astar.is_point_solid(room.get_center()), "monsters can't path into the merchant room")
	var probe: Enemy = g.spawn_monster("ghoul", g.nearest_floor(m.pos + Vector2(0, 60)), false)
	await da._wait(0.3)
	p.host_teleport(m.pos + Vector2(0, 16))
	await da._wait(0.2)
	da.check(not probe._valid_target(p), "monsters don't target a hero inside the merchant room")
	probe.queue_free()
	var mer: Merchants = g.merchants
	da.check(mer.stock.size() >= 5, "Archibald has stock (%d)" % mer.stock.size())
	var arch: Node = g.dungeon.props["Merchant"]
	await sealed_door_rules(room)
	p.host_teleport(m.pos + Vector2(0, 16))
	await da._wait(0.2)
	g.host_interact(p, arch)
	await da._wait(0.3)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(mer.shop_open and hud._overlay != null, "inside the opened vault Archibald trades")
	# Buying: the stock is shared, gold is checked. #94: through the window's row.
	p.host_add_gold(5000)
	var gold0 := p.gold
	var cost := int(mer.stock[0].price)
	var shop: Node = hud._overlay
	for r in shop._buy_list.get_children():
		if r is Button and int(r.get_meta("stock_index", -1)) == 0:
			r.pressed.emit()
	await da._wait(0.5)
	da.check(p.gold == gold0 - cost and int(mer.stock[0].left) == 0, "buying takes %d gold and empties that stock line" % cost)
	sold_line_checks(shop, 0, "solo")
	hud.close_overlay()
	mer.request_buy.rpc_id(1, 0)
	await da._wait(0.2)
	da.check(p.gold == gold0 - cost, "a sold-out line can't be bought again")
	var idx: int = p.inv.backpack.size() - 1
	var sp := Merchants.sell_price(p.inv.backpack[idx])
	mer.request_sell.rpc_id(1, idx)
	await da._wait(0.3)
	da.check(p.gold == gold0 - cost + sp and sp > 0, "selling pays %d gold" % sp)
	price_rules()
	stock_rules()
	var mods_a := p.run_mods.size()
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods_a, "no tithe on a floor without Malphas")
	# Malphas: the tithe once per floor, then contracts and pacts.
	await _force_merchant("malphas")
	m = g.layout.merchant
	var mal_def: Dictionary = GameData.merchants.malphas
	da.check(str(m.npc) == "malphas" and mer.contracts.size() == int(mal_def.contracts_per_floor) and mer.pacts.size() == int(mal_def.pacts_per_floor),
			"Malphas has the merchant room, %d contracts and %d pact potions (%d, %s)" % [int(mal_def.contracts_per_floor), int(mal_def.pacts_per_floor), mer.contracts.size(), mer.pacts])
	malphas_offer_rules()
	var mal_door: Node = g.dungeon.leaf_door("merchant")
	var mal_room: Rect2i = g.layout.rooms[int(m.room)].rect
	da.check(mal_door.sealed and not mal_door.is_open and mal_door.door_type == "malphas" and mal_door.monster_proof, "Malphas's door is his own blood-sealed door")
	p.host_teleport(m.pos + Vector2(0, 16))
	await da._wait(0.3)
	var mods0 := p.run_mods.size()
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 and mal_door.sealed, "the blood price is paid at the door, not from inside")
	p.host_teleport(g.nearest_floor(outside_door(mal_door, mal_room)))
	await da._wait(0.3)
	g.host_interact(p, mal_door)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 and mal_door.sealed and not mal_door.is_open, "using the sealed door only names the blood price")
	hud.close_overlay()
	var price := Merchants.blood_price(int(g.layout.seed))
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.3)
	da.check(p.run_mods.size() == mods0 + 1 and str(p.run_mods[-1].source) == "Demonic tithe" and str(p.run_mods[-1].stat) == str(price.stat)
			and not mal_door.sealed and mal_door.is_open, "the blood price (%s) takes a stat for the run and opens Malphas's door" % Merchants.mod_text(price))
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 + 1, "the blood price is paid once per floor")
	p.host_teleport(m.pos + Vector2(0, 16))
	await da._wait(0.3)
	var mal: Node = g.dungeon.props["Merchant"]
	g.host_interact(p, mal)
	await da._wait(0.2)
	da.check(hud._overlay != null, "behind the broken seal Malphas bargains")
	hud.close_overlay()
	var gold1 := p.gold
	mer.request_buy.rpc_id(1, 1)
	await da._wait(0.2)
	da.check(p.gold == gold1, "Archibald's stock can't be bought on a Malphas floor")
	mer.request_contract.rpc_id(1, 0)
	await da._wait(0.3)
	da.check(p.run_mods.size() == mods0 + 3, "a contract swaps two stats for the run")
	mer.request_contract.rpc_id(1, 0)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 + 3, "each contract is signed once")
	# #94: Malphas's window marks the signed contract.
	g.host_interact(p, mal)
	await da._wait(0.3)
	var pp: Node = hud._overlay
	var signed_row: Button = null
	var rows_c: Array = pp._list.get_children().filter(func(c): return c is Button and str(c.get_meta("key", "")).begins_with("c"))
	for r in rows_c:
		if str(r.get_meta("key", "")) == "c0":
			signed_row = r
	da.check(signed_row != null and signed_row.disabled and signed_row.get_node_or_null("Stamp") != null and rows_c.back() == signed_row,
			"the signed contract is stamped Signed, greyed and last")
	# #95: only the floor's two potions are for sale, each once per hero (the test puts these two
	# on offer).
	var other := ""
	for pid in GameData.pact_consumables:
		if not str(pid) in ["hellfire", "colossus"]:
			other = str(pid)
	mer.pacts = ["colossus", "hellfire"]
	mer.request_pact.rpc_id(1, other)
	await da._wait(0.3)
	da.check(p.inv.count_of("pact_" + other) == 0 and p.run_mods.size() == mods0 + 3, "a potion Malphas doesn't offer this floor can't be bought (%s)" % other)
	mer._sync.rpc(mer.stock, mer.contracts, mer.shop_open, ["colossus", "hellfire"])
	await da._wait(0.2)
	var marked0: int = pp.marked
	mer.request_pact.rpc_id(1, "hellfire")
	await da._wait(0.3)
	da.check(p.inv.count_of("pact_hellfire") == 1 and p.run_mods.size() == mods0 + 4, "a pact potion costs its stat")
	var pact_row: Button = null
	for r3 in pp._list.get_children():
		if r3 is Button and str(r3.get_meta("key", "")) == "phellfire":
			pact_row = r3
	da.check(pact_row != null and pact_row.disabled and pact_row.get_node_or_null("Stamp") != null and pp.marked > marked0,
			"the bought potion is stamped Bought at once, greyed")
	hud.close_overlay()
	mer.request_pact.rpc_id(1, "hellfire")
	await da._wait(0.3)
	da.check(p.inv.count_of("pact_hellfire") == 1 and p.run_mods.size() == mods0 + 4, "each potion is bought once per hero per floor")
	var haste0 := p.stats.get_stat("haste")
	p.inv.quick.q = "pact_hellfire"
	p.request_use_quick.rpc_id(1, "q")
	await da._wait(0.4)
	da.check(p.status.has("pact_hellfire") and p.stats.get_stat("haste") > haste0 + 0.5, "Hellfire Ichor gives +100%% haste (%.2f)" % p.stats.get_stat("haste"))
	mer.request_pact.rpc_id(1, "colossus")
	await da._wait(1.0)  # the shared potion cooldown
	var sta0 := p.stats.get_stat("stamina")
	p.inv.quick.e = "pact_colossus"
	var tries := 0
	while not p.status.has("pact_colossus") and tries < 8:
		p.request_use_quick.rpc_id(1, "e")
		await da._wait(0.4)
		tries += 1
	var expect := 100.0 * GameData.level_scale(p.level)
	var got := p.stats.get_stat("stamina") - sta0
	da.check(absf(got - expect) < 2.0, "Colossus Draught adds %.0f Stamina at level %d (D15, got %.1f)" % [expect, p.level, got])



## #93: over 150 seeded floors Archibald offers the data's number of pieces, at the floor's item
## level up to ilvl_above higher, with the data's rarity mix (Epic about a fifth, Relics rare but
## there), mostly for the party's classes, plus every consumable line; the same seed, the same stock.
func stock_rules() -> void:
	var a: Dictionary = GameData.merchants.archibald
	var mer: Merchants = g.merchants
	var il := 10
	var counts := {}
	var n_eq := 0
	var mine := 0
	var bad := ""
	for sd in 150:
		mer.host_new_floor(1000 + sd * 7, il)
		var eq: Array = mer.stock.filter(func(e): return str(e.item.get("kind", "")) != "consumable")
		if eq.size() != int(a.equipment):
			bad = "seed %d: %d pieces" % [sd, eq.size()]
		for e in eq:
			n_eq += 1
			var r := int(e.item.rarity)
			counts[r] = int(counts.get(r, 0)) + 1
			var lv := int(e.item.ilvl)
			if lv < il or lv > il + int(a.ilvl_above[1]):
				bad = "item level %d on a floor of %d" % [lv, il]
			if Array(GameData.item_bases.get(str(e.item.base), {}).get("classes", [])).has(p.class_id):
				mine += 1
		var cons := mer.stock.filter(func(e): return str(e.item.get("kind", "")) == "consumable").size()
		if cons < a.consumables.size() - 1:
			bad = "only %d consumable lines" % cons
	var total_w := 0.0
	for k in a.rarity_weights:
		total_w += float(a.rarity_weights[k])
	var off := ""
	for k in a.rarity_weights:
		var want := float(a.rarity_weights[k]) / total_w
		var got := float(counts.get(int(k), 0)) / n_eq
		if absf(got - want) > 0.03:
			off += " r%s %.2f vs %.2f" % [k, got, want]
	da.check(bad.is_empty(), "Archibald offers %d pieces a floor at item level %d-%d and every consumable line%s" % [int(a.equipment), il, il + int(a.ilvl_above[1]), "" if bad.is_empty() else ": " + bad])
	da.check(off.is_empty() and int(counts.get(4, 0)) > 0 and int(counts.get(5, 0)) > 0, "the rarity mix follows the data, Epics and rare Relics included (%s)%s" % [counts, off])
	da.check(float(mine) / n_eq > 0.4, "most pieces are for the party's classes (%.0f%%)" % (100.0 * mine / n_eq))
	mer.host_new_floor(4242, il)
	var key := func(e): return "%s/%d/%d" % [str(e.item.get("base", "")), int(e.item.get("rarity", 1)), int(e.item.get("ilvl", 1))]
	var a1 := mer.stock.map(key)
	mer.host_new_floor(4242, il)
	da.check(a1 == mer.stock.map(key), "the same floor seed gives the same pieces (base, rarity, level)")


## #94 (on the peer whose window `shop` is): stock line `idx` is sold out and shows it - greyed,
## stamped Sold, not pressable, at the end of the list, and its purchase played the stamp.
func sold_line_checks(shop: Node, idx: int, who: String) -> void:
	var rows: Array = shop._buy_list.get_children().filter(func(c): return c is Button)
	var row: Button = null
	for r in rows:
		if int(r.get_meta("stock_index", -1)) == idx:
			row = r
	da.check(row != null and row.disabled and row.get_node_or_null("Stamp") != null and row.self_modulate.v < 0.7,
			"%s: the bought line is greyed, stamped and can't be pressed" % who)
	var after_open := false
	for r2 in rows.slice(rows.find(row) + 1) if row else []:
		after_open = after_open or not r2.disabled
	da.check(row != null and not after_open and shop.bought_fx >= 1, "%s: it moved after everything still for sale and its stamp arrived (%d)" % [who, shop.bought_fx])


## #95: over 120 seeded floors Malphas offers exactly the data's number of different contracts and
## pact potions, every potion turns up somewhere, and the same seed gives the same offer.
func malphas_offer_rules() -> void:
	var mal: Dictionary = GameData.merchants.malphas
	var mer: Merchants = g.merchants
	var keep := [mer.stock.duplicate(true), mer.contracts.duplicate(), mer.pacts.duplicate()]
	var bad := ""
	var seen := {}
	for sd in 120:
		mer.host_new_floor(500 + sd * 13, 10)
		var cs := {}
		for c in mer.contracts:
			cs[c] = true
		var ps := {}
		for pid in mer.pacts:
			ps[pid] = true
			seen[pid] = true
		if cs.size() != int(mal.contracts_per_floor) or ps.size() != int(mal.pacts_per_floor):
			bad = "seed %d: %d contracts, %d potions" % [sd, cs.size(), ps.size()]
	mer.host_new_floor(777, 10)
	var first := [mer.contracts.duplicate(), mer.pacts.duplicate()]
	mer.host_new_floor(777, 10)
	da.check(bad.is_empty() and first == [mer.contracts, mer.pacts], "every floor: %d different contracts and %d different potions, the same for the same seed%s" % [int(mal.contracts_per_floor), int(mal.pacts_per_floor), "" if bad.is_empty() else ": " + bad])
	da.check(seen.size() == GameData.pact_consumables.size(), "every pact potion is on offer on some floor (%d of %d)" % [seen.size(), GameData.pact_consumables.size()])
	mer._sync.rpc(keep[0], keep[1], mer.shop_open, keep[2])


## #24: merchants sell at 3x the old price (buy_mult was 1.0) and still pay the old 30% of the
## item value; a hero buys back a sold item at 10x what it fetched.
func price_rules() -> void:
	const OLD_BUY_MULT := 1.0
	const OLD_SELL_MULT := 0.3
	var bad := ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 24
	var items: Array = []
	for i in 40:
		items.append(ItemGenerator.generate_equipment(LootTable.pick_base(["warrior", "mage"], rng), rng.randi_range(1, 30), rng.randi_range(1, 5), rng))
	for cid in GameData.merchants.archibald.consumables:
		items.append(ItemGenerator.generate_consumable(str(cid), 1, rng))
	for e in g.merchants.stock:
		items.append(e.item)
	for it in items:
		var v := Merchants.item_value(it)
		var buy := Merchants.buy_price(it)
		var sell := Merchants.sell_price(it)
		if buy != maxi(1, roundi(v * OLD_BUY_MULT * 3.0)):
			bad = "%s: buy %d, value %d" % [it.get("name", "?"), buy, v]
		elif sell != roundi(v * OLD_SELL_MULT):
			bad = "%s: sell %d, value %d" % [it.get("name", "?"), sell, v]
		elif v >= 10 and absf(float(buy) / float(sell) - 3.0 / OLD_SELL_MULT) > 1.0:
			bad = "%s: buy / sell %d / %d" % [it.get("name", "?"), buy, sell]
	for e in g.merchants.stock:
		if int(e.price) != Merchants.buy_price(e.item):
			bad = "stock line %s priced %d" % [e.item.get("name", "?"), int(e.price)]
	da.check(bad.is_empty(), "merchants sell at 3x the old price, buy at the old 30%%, ratio 10:1 (%d items)%s" % [items.size(), "" if bad.is_empty() else ": " + bad])


## One merchant per floor (#6), over many seeds: exactly one merchant (both appear), in its own
## room behind an ordinary door, no portal or altarpiece, and the Gold Key only on Archibald floors.
func merchant_rules() -> void:
	var seen := {}
	var bad := ""
	var keys := {"archibald": 0, "malphas": 0}
	var fd: Dictionary = g.floor_def
	for i in 24:
		var seed_value := 4242 + i * 7919
		var npc: String = g.pick_merchant(seed_value)
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1, npc)
		var m: Dictionary = lay.get("merchant", {})
		if m.is_empty() or str(m.npc) != npc or not GameData.merchants.get("floor_pick", {}).has(npc):
			bad = "seed %d: merchant %s" % [seed_value, m]
			continue
		seen[npc] = true
		var room: Rect2i = lay.rooms[int(m.room)].rect
		if lay.rooms[int(m.room)].role != "merchant" or lay.rooms.filter(func(r): return r.role == "merchant").size() != 1:
			bad = "seed %d: no single merchant room" % seed_value
		var doors: Array = lay.doors.filter(func(d): return Rect2i(d.rect).intersects(room.grow(1)))
		if doors.is_empty() or doors.any(func(d): return d.get("floodgate", false)):
			bad = "seed %d: the merchant room has no ordinary door" % seed_value
		if lay.props.any(func(pr): return str(pr.type) in ["gilded_portal", "demon_altar", "archibald", "malphas"]):
			bad = "seed %d: a portal / altarpiece / second merchant in the props" % seed_value
		var elites: Dictionary = g._pick_elites(lay, seed_value, npc == "archibald")
		if not g.pick_key_carrier(lay, seed_value, npc == "archibald", elites.keys()).is_empty():
			keys[npc] += 1
	da.check(bad.is_empty(), "every floor has exactly one merchant in its own room%s" % ("" if bad.is_empty() else ": " + bad))
	da.check(seen.has("archibald") and seen.has("malphas"), "both merchants appear across seeds (%s)" % [seen.keys()])
	da.check(keys.malphas == 0 and keys.archibald > 0, "the Gold Key drops only on Archibald floors (%s)" % [keys])
	var live: Array = g.dungeon.props.keys().filter(func(k): return str(k).begins_with("Merchant"))
	da.check(live == ["Merchant"] and not g.dungeon.props.has("Merchant_Portal") and not g.dungeon.props.has("Merchant_Altar"),
			"the live floor has one merchant and no portal or altarpiece (%s)" % [live])


## #21: over 2000 seeds the merchant is Archibald ~80% of the time, an Archibald floor has the Gold
## Key ~80% of the time (elite, or a chest / the boss when the floor has no elite), Malphas floors
## never have one, and the same seed always gives the same merchant and carrier.
func merchant_odds() -> void:
	var fd: Dictionary = g.floor_def
	var n := 2000
	var archi := 0
	var keyed := 0
	var malphas_keys := 0
	var no_elite_bad := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var seed_value := 9001 + i * 104729
		var npc: String = g.pick_merchant(seed_value)
		var key_floor := npc == "archibald"
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1, npc)
		var elites: Dictionary = g._pick_elites(lay, seed_value, key_floor)
		var carrier: Dictionary = g.pick_key_carrier(lay, seed_value, key_floor, elites.keys())
		if carrier != g.pick_key_carrier(lay, seed_value, key_floor, elites.keys()) or npc != g.pick_merchant(seed_value):
			da.check(false, "seed %d: merchant / key carrier is not deterministic" % seed_value)
			return
		var elite_key := elites.values().filter(func(e): return e.get("key", false)).size()
		if elite_key != (1 if carrier.get("kind", "") == "elite" else 0):
			da.check(false, "seed %d: elite key flags %d disagree with the carrier %s" % [seed_value, elite_key, carrier])
			return
		if key_floor:
			archi += 1
			keyed += 0 if carrier.is_empty() else 1
		elif not carrier.is_empty():
			malphas_keys += 1
		# The same floor stripped of its elites must still get the key (chest fallback).
		var bare: Dictionary = g.pick_key_carrier(lay, seed_value, key_floor, [])
		if bare.is_empty() != carrier.is_empty() or (not bare.is_empty() and bare.kind != "chest"):
			no_elite_bad += 1
	var share := float(archi) / n
	var key_rate := float(keyed) / maxi(archi, 1)
	da.check(absf(share - 0.8) <= 0.03, "Archibald is the merchant on %.1f%% of %d floors (80%% +-3)" % [share * 100.0, n])
	da.check(absf(key_rate - 0.8) <= 0.03, "the Gold Key is on %.1f%% of Archibald floors (80%% +-3)" % [key_rate * 100.0])
	da.check(malphas_keys == 0, "no Gold Key on Malphas floors (%d)" % malphas_keys)
	da.check(no_elite_bad == 0, "without elites the same floors get the key from a chest (%d mismatches, %d ms)" % [no_elite_bad, Time.get_ticks_msec() - t0])
	var c1: Dictionary = g.pick_key_carrier({"spawns": [], "chests": []}, 77, true, [])
	var c2: Dictionary = g.pick_key_carrier({"spawns": [], "chests": [Vector2.ONE, Vector2.ZERO]}, 77, true, [])
	da.check(c1.is_empty() or c1.kind == "boss", "no elite and no chest -> the boss carries the key (%s)" % [c1])
	da.check(c2.is_empty() or (c2.kind == "chest" and int(c2.index) in [0, 1]), "no elite -> a chest carries the key (%s)" % [c2])


## #23: Archibald's vault door, seen from outside: sealed, it holds against everything (Interact
## without the key, a sword swing, a monster) and blocks movement and sight; the Gold Key opens it
## at the door and is used up there.
func sealed_door_rules(room: Rect2i) -> void:
	var door: Node = g.dungeon.leaf_door("merchant")
	da.check(door != null and door.door_type == "archibald" and door.sealed and not door.is_open and not door.vertical,
			"Archibald's room has its own sealed vault door on a front wall")
	if door == null:
		return
	p.host_teleport(g.nearest_floor(outside_door(door, room)))
	await da._wait(0.3)
	da.check(door.interact_text().contains("Gold Key") and not door.type_art("art_closed").is_empty(), "the vault door says what it costs and is drawn as Archibald's (%s)" % door.interact_text())
	g.add_party_key(-g.party_keys)
	g.host_interact(p, door)
	await da._wait(0.2)
	da.check(door.sealed and not door.is_open and not g.merchants.shop_open, "without the Gold Key the vault stays sealed")
	door.host_set_open(true)  # the path every swing, monster and lever takes
	await da._wait(0.2)
	var solid: bool = not door._shape.disabled and g.dungeon.blocks_sight(door.cells[0]) and door.monster_proof
	da.check(not door.is_open and solid, "a sealed door can't be forced open and blocks movement, sight and monsters")
	var probe: Enemy = g.spawn_monster("ghoul", g.nearest_floor(outside_door(door, room)), false)
	await da._wait(0.2)
	var dir: Vector2 = (door.world_rect.get_center() - probe.global_position).normalized()
	probe.global_position = door.world_rect.get_center() - dir * 20.0
	await da._wait(1.0 + float(GameData.bal("world.door_enemy_open_delay")))
	da.check(not door.is_open, "a monster waiting at the sealed door never gets in")
	probe.queue_free()
	g.add_party_key(1)
	g.host_interact(p, door)
	await da._wait(0.3)
	da.check(not door.sealed and door.is_open and g.party_keys == 0 and g.merchants.shop_open, "the Gold Key, used at the door, unseals it and Archibald trades (sealed %s, open %s, keys %d, %.0f px from the door)"
			% [door.sealed, door.is_open, g.party_keys, p.global_position.distance_to(door.interact_pos())])


## #28: the map shows the merchant room (its merchant's sign) and the boss chamber only once this
## peer has seen its door or a cell of it.
func map_markers() -> void:
	for npc in ["archibald", "malphas"]:
		await _force_merchant(npc)
		var d: Dungeon = g.dungeon
		d.discovered.fill(0)
		var none := d.map_markers().is_empty()
		for c in d.leaf_door("merchant").cells:
			d.mark_discovered(c)
		var mk: Array = d.map_markers()
		var ok: bool = mk.size() == 1 and mk[0].kind == "merchant" and mk[0].npc == npc and mk[0].locked == d.leaf_door("merchant").sealed \
				and Rect2i(g.layout.rooms[int(g.layout.merchant.room)].rect).has_point(mk[0].cell)
		d.discovered.fill(0)
		var br: Rect2i = g.layout.rooms[int(g.layout.boss_room)].rect
		d.mark_discovered(br.position + Vector2i(1, 1))
		var mk2: Array = d.map_markers()
		var boss_ok: bool = mk2.size() == 1 and mk2[0].kind == "boss" and br.has_point(mk2[0].cell)
		da.check(none and ok and boss_ok, "%s floor: no marker before discovery, the %s sign after seeing its door, the boss mark after seeing the chamber (%s / %s)" % [npc, npc, mk, mk2])
	# Live: walking up to the merchant door shows its sign through the real fog of war.
	var door: Node = g.dungeon.leaf_door("merchant")
	g.dungeon.discovered.fill(0)
	p.host_teleport(g.nearest_floor(outside_door(door, g.layout.rooms[int(g.layout.merchant.room)].rect)))
	await da._wait(0.8)
	da.check(g.dungeon.map_markers().any(func(m): return m.kind == "merchant" and m.npc == "malphas"), "standing at Malphas's door puts his sign on the map")
	p.host_teleport(g.layout.start)
	await da._wait(0.3)


## A spot in front of a leaf chamber's door, outside the chamber.
static func outside_door(door: Node, room: Rect2i) -> Vector2:
	var c: Vector2 = door.world_rect.get_center()
	var tile := float(GameData.bal("world.tile_size"))
	var room_c := Vector2(room.get_center()) * tile
	return c + Vector2(0, signf(c.y - room_c.y)) * tile * 2.0


## Host: rebuilds the current floor with `npc` as its merchant (test hook "force_merchant").
func _force_merchant(npc: String) -> void:
	GameState.set_meta("force_merchant", npc)
	g.start_floor(g.depth)
	GameState.remove_meta("force_merchant")
	await da._wait(1.5)
	p = da._local()
	p.iframe_left = 9999.0


# =========================================================================================
# LAN pair (host + client): split gold, shared stock, client intents, the reader is local
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
	# Gold: a pile picked up by the host is split with the client.
	var hg := p.gold
	var cg := c.gold
	g.loot.drop_item(LootTable.make_gold(41, g.loot.rng), p.global_position + Vector2(8, 0))
	await da._wait(0.4)
	for it in g.items_root.get_children():
		if it.item.get("kind", "") == "gold":
			g.loot.try_pickup(p, it)
	await da._wait(0.4)
	da.check(p.gold == hg + 21 and c.gold == cg + 20, "41 gold split host +%d / client +%d" % [p.gold - hg, c.gold - cg])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_check_gold", c.gold])
	await da._wait(0.5)
	# One merchant per floor (#6): the client sees the host's pick; on an Archibald floor the client
	# buys from the shared stock.
	await _force_merchant("archibald")
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
	var m: Dictionary = g.layout.merchant
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_check_merchant", "archibald"])
	var vault: Node = g.dungeon.leaf_door("merchant")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_door", [true, "archibald"]])
	await da._wait(0.5)
	g.add_party_key(1)
	p.host_teleport(g.nearest_floor(outside_door(vault, g.layout.rooms[int(m.room)].rect)))
	await da._wait(0.3)
	g.host_interact(p, vault)
	await da._wait(0.4)
	da.check(not vault.sealed and g.merchants.shop_open, "the host opens the vault with the Gold Key")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_door", [false, "archibald"]])
	p.host_teleport(m.pos + Vector2(-14, 18))
	c.host_teleport(m.pos + Vector2(14, 16))
	await da._wait(0.5)
	c.host_add_gold(1000)
	await da._wait(0.4)
	var price := int(g.merchants.stock[0].price)
	var cg2 := c.gold
	# #94: the host's window is open while the client buys: the line shows sold for the host too.
	var hud2: Node = da.get_tree().get_first_node_in_group("hud")
	hud2.open_overlay(hud2.ShopPanel.new())
	await da._wait(0.4)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_buy", 0])
	await da._wait(0.8)
	da.check(int(g.merchants.stock[0].left) == 0 and c.gold == cg2 - price, "the client bought stock line 0 for %d gold" % price)
	sold_line_checks(hud2._overlay, 0, "host (a teammate's purchase)")
	hud2.close_overlay()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_check_stock", 0])
	await da._wait(0.8)
	# On a Malphas floor the client pays the tithe.
	await _force_merchant("malphas")
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
	m = g.layout.merchant
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_check_merchant", "malphas"])
	var seal: Node = g.dungeon.leaf_door("merchant")
	c.host_teleport(g.nearest_floor(outside_door(seal, g.layout.rooms[int(m.room)].rect)))
	await da._wait(0.4)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_door", [true, "malphas"]])
	await da._wait(0.4)
	var mods := c.run_mods.size()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_tithe", null])
	await da._wait(0.8)
	da.check(c.run_mods.size() == mods + 1 and not seal.sealed and seal.is_open, "the client's blood price is a run modifier on the client's hero and opens the door")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_door", [false, "malphas"]])
	await da._wait(0.4)
	c.host_teleport(m.pos + Vector2(0, 18))
	await da._wait(0.4)
	# #95: the client sees the same five contracts and two potions, and buys a potion only once.
	var mods_p := c.run_mods.size()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_offer", [g.merchants.contracts, g.merchants.pacts]])
	await da._wait(1.2)
	var pid0 := str(g.merchants.pacts[0])
	da.check(c.inv.count_of("pact_" + pid0) == 1 and c.run_mods.size() == mods_p + GameData.pact_consumables[pid0].cost.size(),
			"host: the client bought %s once (two requests, one potion and one price)" % pid0)
	await lan_markers(c)
	# Reading: only the reader's screen opens the book; only the reader's codex learns it.
	c.host_give_item(LootTable.make_book("lore_007", g.loot.rng))
	await da._wait(0.4)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_read", "lore_007"])
	await da._wait(0.8)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(hud._overlay == null and not Codex.is_read("lore_007"), "the host's screen and codex are untouched by the client's reading")
	# Client loadout and stat points.
	c.add_xp(Player.xp_to_next(c.level))
	c.resource._since_combat = 99.0
	await da._wait(0.4)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_progress", null])
	await da._wait(1.0)
	da.check(int(c.allocated.get("intellect", 0)) == 1, "the client spent a stat point through the host")
	da.check(str(c.skills[1]) == str(c.default_loadout()[2]) and str(c.skills[2]) == str(c.default_loadout()[1]), "the client's loadout swap went through")
	# A legendary on the client's hero: equipped through the real request, its proc runs on the host.
	var lg := ItemGenerator.make_legendary("stormweaver_grips", c.level, g.loot.rng)
	c.host_give_item(lg)
	await da._wait(0.4)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_legendary", str(lg.name)])
	await da._wait(1.0)
	da.check(str(c.inv.equipment.get("gloves", {}).get("legendary", "")) == "stormweaver_grips", "the client equipped a legendary through the host")
	c.cooldowns.erase("mage_lightning")
	c.resource.value = c.resource.max_value
	var cast_err := Combat.instance.try_use_skill(c, "mage_lightning", c.global_position + Vector2(80, 0))
	await da._wait(0.3)
	da.check(cast_err.is_empty() and c.status.has("storm_weave"), "the client's legendary proc fires on the host (Stormweaver Grips)%s" % ("" if cast_err.is_empty() else ": " + cast_err))
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_legendary_status", "storm_weave"])
	await da._wait(0.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


## #28 over LAN: each peer marks what it has seen itself. The client, sent to the boss door, gets
## the boss mark; the host, who never went there, doesn't. Then the client finds Malphas's door.
func lan_markers(c: Player) -> void:
	var boss_door: Node = g.dungeon.leaf_door("boss")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_markers_reset", null])
	await da._wait(0.6)
	c.host_teleport(g.nearest_floor(outside_door(boss_door, g.layout.rooms[int(g.layout.boss_room)].rect)))
	await da._wait(1.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_markers", "boss"])
	await da._wait(0.6)
	da.check(not g.dungeon.map_markers().any(func(m): return m.kind == "boss"), "the host's map has no boss mark: only the client saw the chamber")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_markers_reset", null])
	await da._wait(0.6)
	c.host_teleport(g.nearest_floor(outside_door(g.dungeon.leaf_door("merchant"), g.layout.rooms[int(g.layout.merchant.room)].rect)))
	await da._wait(1.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_markers", "malphas"])
	await da._wait(0.6)


## Client side of run_lan.
func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"eco_check_gold":
			da.check(p.gold == int(arg), "the client's wallet shows %d gold" % int(arg))
		"eco_markers_reset":
			g.dungeon.discovered.fill(0)
			da.check(g.dungeon.map_markers().is_empty(), "the client's map has no merchant or boss mark after a reset")
		"eco_markers":
			var mk: Array = g.dungeon.map_markers()
			var want := func(m): return m.kind == "boss" if str(arg) == "boss" else (m.kind == "merchant" and m.npc == str(arg))
			da.check(mk.any(want), "the client's map shows the %s mark it found itself (%s)" % [arg, mk])
		"eco_buy":
			g.merchants.request_buy.rpc_id(1, int(arg))
		"eco_check_stock":
			da.check(int(g.merchants.stock[int(arg)].left) == 0 and g.merchants.shop_open, "the client sees the shared stock line sold out")
			var hudc: Node = da.get_tree().get_first_node_in_group("hud")
			hudc.open_overlay(hudc.ShopPanel.new())
			await da._wait(0.4)
			var rows: Array = hudc._overlay._buy_list.get_children().filter(func(x): return x is Button)
			var row: Button = null
			for r in rows:
				if int(r.get_meta("stock_index", -1)) == int(arg):
					row = r
			da.check(row != null and row.disabled and row.get_node_or_null("Stamp") != null and rows.back() == row, "client: my window shows the line sold, stamped and last")
			hudc.close_overlay()
		"eco_check_merchant":
			await da._wait(1.0)
			var mp: Node = g.dungeon.props.get("Merchant")
			da.check(str(g.merchant_id) == str(arg) and str(g.layout.merchant.npc) == str(arg) and mp != null and str(mp.type) == str(arg)
					and not g.dungeon.props.has("Merchant_Portal"), "the client sees the same single merchant (%s)" % arg)
		"eco_offer":
			da.check(g.merchants.contracts == arg[0] and g.merchants.pacts == arg[1], "client: the same five contracts and two potions as the host (%s)" % [g.merchants.pacts])
			g.merchants.request_pact.rpc_id(1, str(arg[1][0]))
			await da._wait(0.3)
			g.merchants.request_pact.rpc_id(1, str(arg[1][0]))
			await da._wait(0.3)
			da.check(g.merchants.my_pacts == [str(arg[1][0])], "client: the host told me what I bought (%s)" % [g.merchants.my_pacts])
		"eco_tithe":
			var door0: Node = g.dungeon.leaf_door("merchant")
			da.check(door0.interact_text().contains(Merchants.mod_text(Merchants.blood_price(int(g.layout.seed)))), "the client's door prompt names the same blood price (%s)" % door0.interact_text())
			g.merchants.request_tithe.rpc_id(1, true)
		"eco_door":
			await da._wait(0.3)
			var door: Node = g.dungeon.leaf_door("merchant")
			var want_sealed: bool = arg[0]
			da.check(door != null and door.door_type == str(arg[1]) and door.sealed == want_sealed and door.is_open == not want_sealed,
					"the client sees %s's door %s" % [arg[1], "sealed" if want_sealed else "open"])
		"eco_read":
			for i in p.inv.backpack.size():
				if str(p.inv.backpack[i].get("book", "")) == str(arg):
					p.request_read_book.rpc_id(1, i)
			await da._wait(0.5)
			var hud2: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(Codex.is_read(str(arg)) and hud2._overlay != null and str(hud2._overlay.get("book_id")) == str(arg), "the client reads the book in its own reader")
			hud2.close_overlay()
		"eco_legendary":
			for i in p.inv.backpack.size():
				if str(p.inv.backpack[i].get("name", "")) == str(arg):
					var tip := ItemGenerator.describe(p.inv.backpack[i], p.class_id, p.level)
					var affix := str(GameData.legendaries["stormweaver_grips"].affix)
					da.check(tip.any(func(l): return str(l[0]) == affix), "the client's item card shows the legendary affix")
					p.request_equip.rpc_id(1, i)
					break
		"eco_legendary_status":
			da.check(p.status.has(str(arg)) and str(p.inv.equipment.get("gloves", {}).get("legendary", "")) == "stormweaver_grips",
				"the client sees its legendary worn and its proc status")
		"eco_progress":
			p.request_spend_stat.rpc_id(1, "intellect", 1)
			var lo: Array = p.skills.duplicate()
			var t = lo[1]
			lo[1] = lo[2]
			lo[2] = t
			p.request_loadout.rpc_id(1, lo)
