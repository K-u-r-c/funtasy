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
	await merchants()


func stat_points() -> void:
	var before_pts := p.stat_points
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.3)
	da.check(p.stat_points == before_pts + int(GameData.bal("progression.stat_points_per_level")), "level up gives %d stat points (%d)" % [GameData.bal("progression.stat_points_per_level"), p.stat_points])
	var str_before := p.stats.get_stat("strength")
	p.request_spend_stat.rpc_id(1, "strength", 2)
	await da._wait(0.3)
	da.check(p.stats.get_stat("strength") >= str_before + 1.99, "spending 2 points raises Strength (%.1f -> %.1f)" % [str_before, p.stats.get_stat("strength")])
	da.check(p.stat_points == before_pts + 3, "two points were spent")
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
	# Talent tree v2: starters are free, tiers open per branch.
	var tree := p.talent_tree()
	da.check(tree.get("branches", []).size() == 3, "talent tree has 3 branches")
	da.check(p.unlocked_skills().size() >= 6, "starter skills are unlocked (%d)" % p.unlocked_skills().size())
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


func merchants() -> void:
	var m: Dictionary = g.layout.get("merchant", {})
	da.check(not m.is_empty(), "the floor has a merchant chamber")
	if m.is_empty():
		return
	var room: Rect2i = g.layout.rooms[int(m.room)].rect
	var spawned_inside := false
	for e in g.enemies_root.get_children():
		if room.has_point(g.dungeon.cell_of(e.global_position)) and not e.is_elite() and e.def_id != "ghoul":
			spawned_inside = true
	da.check(not spawned_inside, "no monsters spawn in the merchant chamber")
	da.check(g.dungeon.is_safe(g.dungeon.cell_center(room.get_center())) and g.dungeon.astar.is_point_solid(room.get_center()), "monsters can't path into the merchant chamber")
	var probe: Enemy = g.spawn_monster("ghoul", g.nearest_floor(m.portal + Vector2(0, 30)), false)
	await da._wait(0.3)
	p.host_teleport(m.archibald + Vector2(0, 16))
	await da._wait(0.2)
	da.check(not probe._valid_target(p), "monsters don't target a hero inside the merchant chamber")
	probe.queue_free()
	var mer: Merchants = g.merchants
	da.check(mer.stock.size() >= 5 and mer.contracts.size() == 2, "Archibald has stock (%d) and Malphas 2 contracts" % mer.stock.size())
	var portal: Node = g.dungeon.props["Merchant_Portal"]
	var arch: Node = g.dungeon.props["Merchant_Archibald"]
	p.host_teleport(m.portal + Vector2(0, 20))
	await da._wait(0.3)
	g.add_party_key(-g.party_keys)
	g.host_interact(p, portal)
	await da._wait(0.2)
	da.check(not mer.portal_open, "the Gilded Portal stays shut without a Gold Key")
	g.add_party_key(1)
	g.host_interact(p, portal)
	await da._wait(0.3)
	da.check(mer.portal_open and g.party_keys == 0, "the Gold Key opens the Gilded Portal and is used up")
	# Buying: the stock is shared, gold is checked.
	p.host_add_gold(5000)
	var gold0 := p.gold
	var price := int(mer.stock[0].price)
	mer.request_buy.rpc_id(1, 0)
	await da._wait(0.3)
	da.check(p.gold == gold0 - price and int(mer.stock[0].left) == 0, "buying takes %d gold and empties that stock line" % price)
	mer.request_buy.rpc_id(1, 0)
	await da._wait(0.2)
	da.check(p.gold == gold0 - price, "a sold-out line can't be bought again")
	var idx: int = p.inv.backpack.size() - 1
	var sp := Merchants.sell_price(p.inv.backpack[idx])
	mer.request_sell.rpc_id(1, idx)
	await da._wait(0.3)
	da.check(p.gold == gold0 - price + sp and sp > 0, "selling pays %d gold" % sp)
	# Malphas: the tithe once per floor, then contracts and pacts.
	var altar: Node = g.dungeon.props["Merchant_Altar"]
	p.host_teleport(m.altar + Vector2(0, 20))
	await da._wait(0.3)
	var mods0 := p.run_mods.size()
	g.host_interact(p, altar)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0, "kneeling only asks for the tithe")
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.3)
	da.check(p.run_mods.size() == mods0 + 1 and str(p.run_mods[-1].source) == "Demonic tithe", "the tithe takes a stat for the run")
	mer.request_tithe.rpc_id(1, true)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 + 1, "the tithe is paid once per floor")
	mer.request_contract.rpc_id(1, 0)
	await da._wait(0.3)
	da.check(p.run_mods.size() == mods0 + 3, "a contract swaps two stats for the run")
	mer.request_contract.rpc_id(1, 0)
	await da._wait(0.2)
	da.check(p.run_mods.size() == mods0 + 3, "each contract is signed once")
	mer.request_pact.rpc_id(1, "hellfire")
	await da._wait(0.3)
	da.check(p.inv.count_of("pact_hellfire") == 1 and p.run_mods.size() == mods0 + 4, "a pact potion costs its stat")
	var haste0 := p.stats.get_stat("haste")
	p.inv.quick.q = "pact_hellfire"
	p.request_use_quick.rpc_id(1, "q")
	await da._wait(0.4)
	da.check(p.status.has("pact_hellfire") and p.stats.get_stat("haste") > haste0 + 0.5, "Hellfire Ichor gives +100%% haste (%.2f)" % p.stats.get_stat("haste"))
	mer.request_pact.rpc_id(1, "colossus")
	await da._wait(1.0)  # the shared potion cooldown
	var sta0 := p.stats.get_stat("stamina")
	p.inv.quick.e = "pact_colossus"
	p.request_use_quick.rpc_id(1, "e")
	await da._wait(0.4)
	var expect := 100.0 * GameData.level_scale(p.level)
	da.check(absf(p.stats.get_stat("stamina") - sta0 - expect) < 2.0, "Colossus Draught adds %.0f Stamina at level %d (D15)" % [expect, p.level])



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
	# The merchant chamber: the client buys from the shared stock.
	var m: Dictionary = g.layout.merchant
	g.add_party_key(1)
	p.host_teleport(m.portal + Vector2(0, 18))
	c.host_teleport(m.archibald + Vector2(14, 16))
	await da._wait(0.5)
	g.host_interact(p, g.dungeon.props["Merchant_Portal"])
	c.host_add_gold(1000)
	await da._wait(0.4)
	var price := int(g.merchants.stock[0].price)
	var cg2 := c.gold
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_buy", 0])
	await da._wait(0.8)
	da.check(int(g.merchants.stock[0].left) == 0 and c.gold == cg2 - price, "the client bought stock line 0 for %d gold" % price)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_check_stock", 0])
	await da._wait(0.4)
	# The client pays the tithe and signs a contract.
	c.host_teleport(m.altar + Vector2(0, 18))
	await da._wait(0.4)
	var mods := c.run_mods.size()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["eco_tithe", null])
	await da._wait(0.8)
	da.check(c.run_mods.size() == mods + 1, "the client's tithe is a run modifier on the client's hero")
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
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


## Client side of run_lan.
func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"eco_check_gold":
			da.check(p.gold == int(arg), "the client's wallet shows %d gold" % int(arg))
		"eco_buy":
			g.merchants.request_buy.rpc_id(1, int(arg))
		"eco_check_stock":
			da.check(int(g.merchants.stock[int(arg)].left) == 0 and g.merchants.portal_open, "the client sees the shared stock line sold out")
		"eco_tithe":
			g.merchants.request_tithe.rpc_id(1, true)
			await da._wait(0.5)
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(hud._overlay != null, "after the tithe Malphas's window opens on the client")
			hud.close_overlay()
		"eco_read":
			for i in p.inv.backpack.size():
				if str(p.inv.backpack[i].get("book", "")) == str(arg):
					p.request_read_book.rpc_id(1, i)
			await da._wait(0.5)
			var hud2: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(Codex.is_read(str(arg)) and hud2._overlay != null and str(hud2._overlay.get("book_id")) == str(arg), "the client reads the book in its own reader")
			hud2.close_overlay()
		"eco_progress":
			p.request_spend_stat.rpc_id(1, "intellect", 1)
			var lo: Array = p.skills.duplicate()
			var t = lo[1]
			lo[1] = lo[2]
			lo[2] = t
			p.request_loadout.rpc_id(1, lo)
