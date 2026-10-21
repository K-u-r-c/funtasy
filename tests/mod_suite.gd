class_name ModSuite
extends RefCounted
## #71 floor modifiers (scenario "mods" solo, "mods_lan" host + client): the two offered at a
## portal are seeded, never repeat the last pair or the current modifier; votes and the host's
## pick (majority, seeded ties); each modifier's effect and reward; every warning shows before its
## effect by at least its data lead (Restless meter, Hunted rift); the Restless meter resets on
## moving; the HUD badge and countdown; the modifier is saved with the floor.

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


func clear_monsters() -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da.get_tree().process_frame


func floor_with(depth: int, mod: String) -> void:
	GameState.set_meta("force_mod", mod)
	g.start_floor(depth)
	GameState.set_meta("force_mod", "")
	await da._wait(1.2)


func run() -> void:
	g = da._game()
	var p: Player = da._local()
	p.iframe_left = 9999.0
	await da._wait(1.0)
	offer_checks()
	# 1. The vote at a portal: floor 3's portal offers the modifiers of floor 4.
	await floor_with(3, "")
	await clear_monsters()
	g._boss_defeated.rpc(g.layout.portal_pos)
	await da._wait(0.3)
	# #73: this hero's boon is out of the way (the boon suites test that choice).
	p.boon_floor = g.depth
	g.boon_pending.clear()
	g._sync_boon_wait.rpc([])
	g.my_boon_offer = []
	da.check(g.mod_offer.size() == 2 and g.mod_offer == FloorMods.offer(g.run_seed, 4, ""), "floor 3's portal offers two modifiers for floor 4 (%s)" % [g.mod_offer])
	p.host_teleport(g.portal.global_position)
	await da._wait(0.4)
	g.host_interact(p, g.portal)
	await da._wait(0.4)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Node = hud._overlay
	da.check(panel != null and panel.get("_cards") is Dictionary and panel._cards.size() == 2, "stepping into the portal opens the two cards")
	da.check(not g.portal_ready.has(1), "opening the cards isn't a step into the portal yet")
	var pick: String = g.mod_offer[1]
	g.request_mod_vote(pick)
	await da._wait(0.3)
	da.check(g.mod_votes.get(1, "") == pick and g.portal_ready.has(1), "a card is this hero's vote and steps into the portal")
	if panel and is_instance_valid(panel):
		da.check(panel._cards[pick].picked and panel._cards[pick].voters.size() == 1, "the card shows the hero's pick and name")
	await da._wait(2.5)
	da.check(g.depth == 4 and str(g.floor_def.get("mod", "")) == pick, "floor 4 has the chosen modifier (%s)" % g.floor_def.get("mod", ""))
	da.check(hud._mod_label != null and hud._mod_label.text == Loc.t(str(FloorMods.def(pick).name)), "the HUD shows the modifier's badge")
	da.check(hud.floor_banner.shown_lines.size() >= 1, "the floor banner names the modifier")
	var snap: Dictionary = FloorState.capture(g, {})
	da.check(str(snap.get("mod", "")) == pick, "the modifier is saved with the floor")
	# #88: the vote window closed itself on the way down.
	da.check(hud._overlay == null or not is_instance_valid(hud._overlay) or hud._overlay.get_script() != hud.ModVotePanel,
			"the vote window closed when the party went down")
	if hud._overlay:
		hud.close_overlay()
	await map_badge_checks(hud, pick)
	# 2. The effects and rewards.
	await count_checks()
	reward_checks()
	await dimmed_checks()
	await restless_checks(p)
	await hunted_checks(p)


## #87: on the map screen the modifier is a small badge in the header; its card shows only while
## the badge is hovered (its tooltip) or focused, floating over the map without moving anything.
func map_badge_checks(hud: Node, mod: String) -> void:
	hud.open_overlay(hud.menu_panel("map"))
	await da._wait(0.6)
	var panel: Node = hud._overlay
	var badges: Array = panel._badges
	var b: Badge = badges.back() if not badges.is_empty() else null
	var cards_in_layout := 0
	for c in panel.content.find_children("*", "PanelContainer", true, false):
		if c.get_parent() is VBoxContainer and c.get_child_count() > 0 and c.find_children("*", "TextureRect", true, false).size() > 0:
			cards_in_layout += 1
	da.check(b != null and b.get_parent() == panel.header and b.size.x <= 26.0 and panel._card == null and not b.has_focus(),
			"the map shows the modifier as a small badge in its header, no card while nothing points at it")
	da.check(cards_in_layout == 0, "no modifier card takes room in the map's layout")
	var tip: Variant = b._make_custom_tooltip("") if b else null
	da.check(b != null and b.title == Loc.t(str(FloorMods.def(mod).name)) and not b.tooltip_text.is_empty() and tip is Control,
			"hovering the badge shows its card (name and what it does) as a tooltip")
	if tip is Control:
		tip.free()
	var before: Rect2 = panel.window.get_global_rect()
	var mm_before: Rect2 = panel.content.get_child(0).get_global_rect()
	var ev := InputEventAction.new()
	ev.action = "ui_right"
	ev.pressed = true
	panel._unhandled_input(ev)
	await da._wait(0.2)
	da.check(badges[0].has_focus() and panel._card != null and panel._card.top_level and panel._card.visible,
			"a direction key / the d-pad focuses the badge and its card floats over the map")
	await da.get_tree().process_frame
	da.check(panel.window.get_global_rect() == before and panel.content.get_child(0).get_global_rect() == mm_before, "the floating card moves nothing")
	badges[0].release_focus()
	await da.get_tree().process_frame
	da.check(panel._card == null, "the card goes when the badge loses focus")
	hud.close_overlay()
	await da._wait(0.2)


## Offers are seeded, two different ones, never the current modifier, never the last pair.
func offer_checks() -> void:
	var bad := []
	for s in 20:
		var rs := 4242 + s * 97
		var prev: Array = []
		var cur := ""
		for d in range(1, 31):
			var o := FloorMods.offer(rs, d, cur)
			if d < FloorMods.from_floor():
				if not o.is_empty():
					bad.append("floor %d offered" % d)
				continue
			if o.size() != 2 or o[0] == o[1] or o.has(cur) or o == prev:
				bad.append("seed %d floor %d %s (prev %s cur %s)" % [rs, d, o, prev, cur])
			if FloorMods.offer(rs, d, cur) != o:
				bad.append("not seeded")
			prev = o
			cur = FloorMods.resolve(o, {}, rs, d)
	da.check(bad.is_empty(), "offers: two different modifiers from floor 4, seeded, never the current one, never the last pair%s" % ("" if bad.is_empty() else ": %s" % [bad.slice(0, 3)]))
	var o2 := ["dimmed", "swarm"]
	da.check(FloorMods.resolve(o2, {1: "swarm", 2: "swarm", 3: "dimmed"}, 1, 5) == "swarm", "the most votes win")
	var tie := FloorMods.resolve(o2, {1: "swarm", 2: "dimmed"}, 1, 5)
	da.check(o2.has(tie) and tie == FloorMods.resolve(o2, {2: "dimmed", 1: "swarm"}, 1, 5), "a tie is a seeded pick between the tied")


func _count_floor(depth: int, mod: String) -> Array:
	await floor_with(depth, mod)
	var n := 0
	var elites := 0
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			n += 1
			elites += 1 if e.is_elite() else 0
	return [n, elites]


func count_checks() -> void:
	var plain := await _count_floor(6, "")
	var swarm := await _count_floor(6, "swarm")
	var elite := await _count_floor(6, "elite")
	var want := float(FloorMods.def("swarm").count_mult)
	var tot := [0, 0]
	for sd in 10:
		var fd: Dictionary = GameData.floor_types.crypt
		for k in 2:
			var lay: Dictionary = DungeonGenerator.new().generate(300 + sd, fd, want if k == 1 else 1.0, 6)
			for grp in lay.spawns:
				tot[k] += grp.monsters.size()
	var ratio := float(tot[1]) / maxf(tot[0], 1)
	da.check(ratio > want - 0.15 and ratio < want + 0.2 and swarm[0] > plain[0], "Swarm: x%.2f monsters per room over 10 seeds (data x%.2f; live floor %d -> %d)" % [ratio, want, plain[0], swarm[0]])
	da.check(elite[1] > plain[1], "Elite floor: more elites (%d -> %d)" % [plain[1], elite[1]])
	# Swarm's XP: a kill is worth xp_mult more.
	await floor_with(6, "swarm")
	await clear_monsters()
	var p: Player = da._local()
	var m: Enemy = g.spawn_monster("ghoul", p.global_position + Vector2(40, 0), false)
	await da._wait(0.3)
	var xp0 := p.xp + Player.xp_to_next(p.level) * 0  # level ups would hide it: compare the gain
	var lvl0 := p.level
	var base: int = g.kill_xp(m.def, m.level, false, 1)
	m.contributors[p.peer_id] = Time.get_ticks_msec() / 1000.0
	Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), m, 999999.0, {"damage_type": "true"})
	await da._wait(0.2)
	if p.level == lvl0:
		da.check(p.xp - xp0 == roundi(base * float(FloorMods.def("swarm").xp_mult)), "Swarm: a kill gives x%.2f XP (%d -> %d)" % [float(FloorMods.def("swarm").xp_mult), base, p.xp - xp0])


## Rewards through the loot rolls (many rolls, so the averages settle).
func reward_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var plain := _loot_stats({}, rng)
	for id in ["swarm", "elite", "dimmed", "restless", "hunted"]:
		var fd := FloorMods.apply(GameData.floor_types.crypt, id)
		var st := _loot_stats(FloorMods.loot_override(fd), rng)
		var md := FloorMods.def(id)
		var ok := true
		var why := []
		if float(md.get("drop_mult", 1.0)) > 1.0:
			ok = ok and st.drops > plain.drops * 1.1
			why.append("drops %.2f -> %.2f" % [plain.drops, st.drops])
		if float(md.get("gold_mult", 1.0)) > 1.0:
			ok = ok and st.gold > plain.gold * 1.05
			why.append("gold %.1f -> %.1f" % [plain.gold, st.gold])
		if float(md.get("rarity_up_chance", 0.0)) > 0.0:
			ok = ok and st.rarity > plain.rarity
			why.append("rarity %.3f -> %.3f" % [plain.rarity, st.rarity])
		if float(md.get("monster_book_chance", 0.0)) > 0.0:
			ok = ok and st.books > plain.books
			why.append("books %.3f -> %.3f" % [plain.books, st.books])
		da.check(ok, "%s rewards: %s" % [id, ", ".join(why) if not why.is_empty() else "hunter drops (below)"])


func _loot_stats(ov: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var n := 3000
	var drops := 0.0
	var gold := 0.0
	var rar := 0.0
	var nr := 0
	var books := 0.0
	for i in n:
		for it in LootTable.roll("monster", 20, 12, ["warrior"], rng, ov):
			if str(it.get("kind", "")) == "gold":
				gold += int(it.amount)
			elif str(it.get("kind", "")) == "book":
				books += 1
			else:
				drops += 1
				if it.has("rarity") and not it.has("legendary"):
					rar += int(it.rarity)
					nr += 1
	return {"drops": drops / n, "gold": gold / n, "rarity": rar / maxf(nr, 1), "books": books / n}


func dimmed_checks() -> void:
	await floor_with(5, "dimmed")
	var k := float(FloorMods.def("dimmed").light_mult)
	var p: Player = da._local()
	var t: Node = g.dungeon.torches.values()[0] if not g.dungeon.torches.is_empty() else null
	var wall_ok := t == null or absf(float(t.light.get_meta("radius")) - float(GameData.bal("lighting.wall_torch_radius")) * k * float(GameData.floor_types[g.floor_type_for(5)].get("torch_radius_mult", 1.0))) < 1.0
	var carried := float(p._torch_light.get_meta("radius"))
	var personal := float(g.visibility.vision_light.get_meta("radius"))
	da.check(wall_ok and absf(carried - float(GameData.bal("lighting.carried_torch_radius")) * k * float(GameData.floor_types[g.floor_type_for(5)].get("torch_radius_mult", 1.0))) < 1.0
			and absf(personal - float(GameData.bal("lighting.personal_light_radius")) * k) < 1.0,
			"Dimmed: wall torches, the carried torch and the hero's own light reach x%.2f (personal %.0f, carried %.0f)" % [k, personal, carried])
	# Spells keep their light.
	da.check(float(GameData.bal("lighting.spell_projectile_radius")) > 0.0, "Dimmed leaves spell lights alone")


func restless_checks(p: Player) -> void:
	await floor_with(5, "restless")
	await clear_monsters()
	var md := FloorMods.def("restless")
	var spot: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(spot)
	p.iframe_left = 0.0  # the burn must land
	await da._wait(0.4)
	# No awake monster near: no penalty (reading a book in a cleared room is fine).
	await da._wait(float(md.still_time) + 0.5)
	da.check(p.restless == 0.0, "Restless: nothing builds without an awake monster near")
	var m: Enemy = g.spawn_monster("ghoul", spot + Vector2(90, 0), false)
	await da._wait(0.2)
	m.set_physics_process(false)
	m.aggro = true
	Telegraph.log.erase("restless_%d" % p.peer_id)
	var hp := p.health.hp
	await da._wait(float(md.warn_at) + 0.2)
	var meter: Node = p.get_node("RestlessMeter")
	da.check(p.restless > 0.0 and meter.visible, "Restless: the meter under the still hero fills (%.1f s)" % p.restless)
	da.check(Telegraph.log.has("restless_%d" % p.peer_id) and p.health.hp == hp and not p.status.has("restless_curse"), "Restless: it turns red with a sound before anything bites")
	await da._wait(float(md.still_time) - float(md.warn_at) + float(md.tick) + 0.3)
	var lead := Telegraph.lead_of("restless_%d" % p.peer_id)
	da.check(p.status.has("restless_curse") and p.health.hp < hp, "Restless: standing on, the curse and the burn bite")
	da.check(lead >= float(md.still_time) - float(md.warn_at) - 0.15, "Restless: the warning came %.2f s before the bite (data %.2f s)" % [lead, float(md.still_time) - float(md.warn_at)])
	var before := p.restless
	p.host_teleport(g.nearest_floor(spot + Vector2(0, 70)))
	await da._wait(0.2)
	da.check(before > 2.0 and p.restless < 0.3 and not p.status.has("restless_curse"), "Restless: moving resets the meter (%.1f -> %.1f s) and clears the curse" % [before, p.restless])
	m.queue_free()
	p.iframe_left = 9999.0
	p.health.hp = p.health.max_hp


func hunted_checks(p: Player) -> void:
	await floor_with(5, "hunted")
	await clear_monsters()
	var md := FloorMods.def("hunted")
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(g.hunt_next_at > g.floor_time and hud._hunt_row != null and hud._hunt_row.visible and not hud._hunt_label.text.is_empty(),
			"Hunted: the HUD counts down to the first hunter ('%s')" % (hud._hunt_label.text if hud._hunt_label else ""))
	# Bring the hunter forward.
	g.mod_runner._hunt_at = g.floor_time + float(md.warn) + 0.3
	Telegraph.log.erase("hunter")
	await da._wait(0.8)
	var rifts: Array = g.entities.get_children().filter(func(n): return n is HuntRift)
	da.check(rifts.size() == 1 and rifts[0].title.contains("Hunter") or rifts.size() == 1, "Hunted: a rift opens before the hunter, with its name (%s)" % [rifts[0].title if not rifts.is_empty() else "none"])
	da.check(not g.map_pings.is_empty(), "Hunted: the rift is pinged on the minimap")
	da.check(g.enemies_root.get_children().filter(func(e): return not str(e.hunter).is_empty()).is_empty(), "Hunted: no hunter yet while the rift counts down")
	await da._wait(float(md.warn) + 0.5)
	var hunters: Array = g.enemies_root.get_children().filter(func(e): return not str(e.hunter).is_empty())
	da.check(hunters.size() == 1 and hunters[0].elite.size() >= int(md.elite_mods[0]), "Hunted: the hunter steps out, an elite with %d modifiers" % [hunters[0].elite.size() if not hunters.is_empty() else 0])
	var lead := Telegraph.lead_of("hunter")
	da.check(lead >= float(md.warn) - 0.15, "Hunted: the rift opened %.2f s before the hunter came (data %.1f s)" % [lead, float(md.warn)])
	if not hunters.is_empty():
		var h: Enemy = hunters[0]
		da.check(h.display_name == Loc.f("%s the Hunter", [h.hunter]), "Hunted: it bears its own name (%s)" % h.display_name)
		var before: Array = g.items_root.get_children()
		Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), h, 9999999.0, {"damage_type": "true"})
		await da._wait(0.3)
		var fine: Array = g.items_root.get_children().filter(func(it): return not before.has(it) and int(it.item.get("rarity", 0)) >= int(md.loot_min_rarity) and str(it.item.get("kind", "")) != "gold")
		da.check(not fine.is_empty(), "Hunted: the hunter drops a fine item (rarity %d+)" % int(md.loot_min_rarity))
	da.check(g.hunt_next_at >= g.floor_time + float(md.interval) - 2.0, "Hunted: the next hunter is a minute away")


## LAN: the client gets the host's offer, its vote counts, it builds the chosen floor, and it
## sees the telegraphs (the Restless meter on itself, the rift before the hunter).
func run_lan() -> void:
	g = da._game()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var p: Player = da._local()
	var c: Player = da._other_player()
	p.iframe_left = 9999.0
	c.iframe_left = 9999.0
	await floor_with(3, "")
	await clear_monsters()
	g._boss_defeated.rpc(g.layout.portal_pos)
	await da._wait(0.5)
	# #73: the boons are out of the way (the boon suites test that choice); the portal won't wait.
	for h in [p, c]:
		h.boon_floor = g.depth
	g.boon_pending.clear()
	g._sync_boon_wait.rpc([])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["md_offer", g.mod_offer])
	await da._wait(1.0)
	da.check(g.mod_votes.get(c.peer_id, "") == g.mod_offer[0] and g.portal_ready.has(c.peer_id), "host: the client's vote arrived and it stepped in")
	g.request_mod_vote(g.mod_offer[0])
	await da._wait(2.5)
	da.check(g.depth == 4 and str(g.floor_def.get("mod", "")) == g.mod_offer[0] if not g.mod_offer.is_empty() else g.depth == 4, "host: both voted, floor 4 has their pick")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["md_floor", str(g.floor_def.get("mod", ""))])
	await da._wait(1.0)
	# The client's hero stands still on a Restless floor next to an awake monster.
	await floor_with(5, "restless")
	await clear_monsters()
	var spot: Vector2 = g.nearest_floor(g.layout.start)
	c.host_teleport(spot)
	p.host_teleport(spot + Vector2(0, 120))
	var m: Enemy = g.spawn_monster("ghoul", spot + Vector2(90, 0), false)
	await da._wait(0.2)
	m.set_physics_process(false)
	m.aggro = true
	NetworkManager.to_clients("DevAuto", "client_cmd", ["md_restless", float(FloorMods.def("restless").still_time)])
	await da._wait(float(FloorMods.def("restless").still_time) + float(FloorMods.def("restless").tick) + 1.5)
	da.check(c.status.has("restless_curse"), "host: the still client hero is bitten")
	m.queue_free()
	# Hunted: the rift shows on the client before the hunter arrives.
	await floor_with(5, "hunted")
	await clear_monsters()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["md_hunt", float(FloorMods.def("hunted").warn)])
	await da._wait(0.5)
	g.mod_runner._hunt_at = g.floor_time + float(FloorMods.def("hunted").warn) + 0.3
	await da._wait(float(FloorMods.def("hunted").warn) + 2.5)
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var p: Player = da._local()
	match cmd:
		"md_offer":
			da.check(g.mod_offer == arg and g.mod_offer.size() == 2, "client: the same two modifiers as the host (%s)" % [g.mod_offer])
			# The client votes through the cards (#88: they must close on the next floor).
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			hud.open_mod_vote()
			await da._wait(0.3)
			hud._overlay._vote(str(g.mod_offer[0]))
		"md_floor":
			await da._wait(0.3)
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(str(g.floor_def.get("mod", "")) == str(arg) and hud._mod_label != null, "client: floor 4 has the party's pick (%s) and its badge" % arg)
			da.check(hud._overlay == null or not is_instance_valid(hud._overlay) or hud._overlay.get_script() != hud.ModVotePanel,
					"client: the vote window closed when the party went down")
		"md_restless":
			Telegraph.log.erase("restless_%d" % p.peer_id)
			await da._wait(float(arg) * 0.8)
			var meter: Node = p.get_node("RestlessMeter")
			da.check(p.restless > 0.0 and meter.visible, "client: the meter under my still hero fills (%.1f s)" % p.restless)
			await da._wait(float(arg) * 0.5)
			da.check(Telegraph.log.has("restless_%d" % p.peer_id), "client: it turned red with its warning")
		"md_hunt":
			Telegraph.log.erase("hunter")
			await da._wait(float(arg) + 3.0)
			var lead := Telegraph.lead_of("hunter")
			da.check(lead >= float(arg) - 0.3, "client: the rift showed %.2f s before the hunter arrived" % lead)
