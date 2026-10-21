class_name BoonSuite
extends LegendarySuite
## #73 boons (scenario "boons", solo host, --class=<id>; --only=<ids> limits the check): the pool
## sizes (at least 50 per class plus the shared ones), every boon of the class and the shared pool
## complete (name, text, kind, rarity, tags, an existing icon, Polish for its texts) and proven by
## its effect: a stat boon changes the stat it names, a skill boon its skill, a flag boon the flag,
## an item boon hands over its item, a synergy boon passes its data `test` (the legendary test
## format: a compiled proc, or a trigger / cast with expectations). Then the offers: three
## different boons, seeded, one of each kind, favouring owned tags; and a save round trip keeps
## them. Scenario "boons_lan": both heroes get their own offer after the boss and the portal waits.

const MIN_PER_CLASS := 50


func run_boons(class_id: String) -> void:
	await _prepare()
	_unlock_all_skills()
	# A modest kit, so percent boons (armor, block...) have something to scale.
	for slot_base in [["chest", "plate_chest"], ["head", "plate_helm"], ["boots", "boots"], ["gloves", "gloves"]]:
		p.inv.equipment[slot_base[0]] = ItemGenerator.generate_equipment(str(slot_base[1]), 10, 2, _rng)
	if not p.inv.equipment.has("off_hand") and class_id == "warrior":
		p.inv.equipment["off_hand"] = ItemGenerator.generate_equipment("shield", 10, 2, _rng)
	p.recompute_stats()
	var all: Array = GameData.boons.keys()
	for c in ["warrior", "ranger", "mage", "priest"]:
		var n := all.filter(func(id): return str(GameData.boons[id].get("class", "")) == c).size()
		da.check(n >= MIN_PER_CLASS, "%s has %d boons (at least %d)" % [c, n, MIN_PER_CLASS])
	var shared := all.filter(func(id): return str(GameData.boons[id].get("class", "")) == "any").size()
	da.check(shared >= 30, "%d shared boons" % shared)
	var ids: Array = all.filter(func(id): return str(GameData.boons[id].get("class", "")) in [class_id, "any"])
	ids.sort()
	if not da.only.is_empty():
		ids = ids.filter(func(id): return da.only.has(id))
	var incomplete := []
	for id in ids:
		var why := _incomplete(str(id))
		if not why.is_empty():
			incomplete.append("%s: %s" % [id, why])
	da.check(incomplete.is_empty(), "%s: every boon is complete (%d)%s" % [class_id, ids.size(), "" if incomplete.is_empty() else ": %s" % [incomplete.slice(0, 6)]])
	for id in ids:
		await check_boon(str(id))
	if da.only.is_empty():
		offer_checks(class_id)
		save_check(class_id)


func _incomplete(id: String) -> String:
	var d := Boons.def(id)
	for k in ["name", "text", "kind", "rarity", "tags", "icon"]:
		if not d.has(k):
			return "no %s" % k
	if not str(d.kind) in ["stat", "item", "synergy"]:
		return "kind %s" % d.kind
	if not GameData.asset_exists(str(d.icon)):
		return "icon %s missing" % d.icon
	if TranslationServer.get_translation_object("pl") != null:
		var tr := TranslationServer.get_translation_object("pl")
		for k in ["name", "text"]:
			if tr.get_message(str(d[k])) == StringName():
				return "no Polish for '%s'" % d[k]
	return ""


func check_boon(id: String) -> void:
	var d := Boons.def(id)
	_reset()
	var keep_boons := p.boons.duplicate()
	var keep_eq: Dictionary = p.inv.equipment.duplicate(true)
	var keep_bp: Array = p.inv.backpack.duplicate(true)
	p.recompute_stats()
	var before: Dictionary = p.stats.final.duplicate()
	p.proc_cd.clear()  # a partner boon tested just before mustn't still be on its internal cooldown
	var before_items := p.inv.backpack.size()
	var before_cap := p.inv.capacity
	var before_eq := p.inv.equipment.size()
	# A synergy's test may need its partner boon (an explosion for burning ground...).
	for w in d.get("test", {}).get("with", []):
		p.host_add_boon(str(w), 20, _rng)
	p.host_add_boon(id, 20, _rng)
	await da._wait(0.05)
	da.check(p.boons.has(id), "%s: joins the hero's boons" % id)
	var t: Dictionary = d.get("test", {})
	match str(d.kind):
		"stat":
			var changed := []
			var same := []
			for m in d.get("mods", []):
				var key := _final_key(str(m.stat))
				if float(p.stats.final.get(key, 1.0 if key.ends_with("_mult") else 0.0)) != float(before.get(key, 1.0 if key.ends_with("_mult") else 0.0)):
					changed.append(key)
				else:
					same.append(key)
			for sm in d.get("skill_mods", []):
				if p.stats.skill_mod(str(sm.skill), str(sm.field)) != 0.0:
					changed.append(str(sm.skill))
				else:
					same.append("%s.%s" % [sm.skill, sm.field])
			da.check(not changed.is_empty() and same.is_empty(), "%s: changes %s%s" % [id, changed, "" if same.is_empty() else " but not %s" % [same]])
		"item":
			var got: bool = p.inv.backpack.size() > before_items or p.inv.capacity > before_cap or g.items_root.get_children().any(func(it): return it.global_position.distance_to(p.global_position) < 40.0)
			da.check(got, "%s: hands over its %s" % [id, str(d.get("give", {}).get("type", "item"))])
		"synergy":
			if t.has("flag"):
				da.check(p.stats.has_flag(str(t.flag)), "%s: flag %s" % [id, t.flag])
			elif t.has("chance_proc") or t.is_empty():
				var ev := str(t.get("chance_proc", d.get("procs", [{}])[0].get("event", "")))
				var found := p.static_procs.any(func(pr): return str(pr.get("event", "")) == ev and str(pr.get("_key", "")).begins_with("b:%s:" % id))
				da.check(found, "%s: %s proc is live" % [id, ev])
			elif t.has("skill_mod"):
				da.check(p.stats.skill_mod(str(t.skill_mod[0]), str(t.skill_mod[1])) != 0.0, "%s: modifies %s" % [id, t.skill_mod])
			else:
				await _run_spec(id, t)
	for it in g.items_root.get_children():
		if it.global_position.distance_to(p.global_position) < 60.0:
			it.queue_free()
	p.boons = keep_boons
	p.inv.equipment = keep_eq
	p.inv.backpack = keep_bp
	p.inv.capacity = before_cap
	p.recompute_stats()
	await da._wait(0.05)


## The key a mod's stat shows under in Stats.final.
func _final_key(stat: String) -> String:
	if stat.ends_with("_pct") or stat.ends_with("_mult"):
		var base := stat.trim_suffix("_pct").trim_suffix("_mult")
		if base in ["strength", "stamina", "agility", "intellect", "armor", "max_hp", "max_resource", "move_speed"]:
			return base
		return base + "_mult"
	return stat


func offer_checks(class_id: String) -> void:
	var bad := []
	for s in 40:
		var o := Boons.offer(class_id, [], 900 + s)
		var kinds := o.map(func(id): return str(Boons.def(str(id)).kind))
		if o.size() != 3 or o[0] == o[1] or o[1] == o[2] or o[0] == o[2]:
			bad.append("seed %d: %s" % [s, o])
		elif not (kinds.has("stat") and kinds.has("item") and kinds.has("synergy")):
			bad.append("seed %d kinds %s" % [s, kinds])
		if Boons.offer(class_id, [], 900 + s) != o:
			bad.append("not seeded")
	da.check(bad.is_empty(), "%s offers: three different boons, one of each kind, seeded%s" % [class_id, "" if bad.is_empty() else ": %s" % [bad.slice(0, 3)]])
	# Owning boons of a tag makes that tag come back more often: the class's own most common tag
	# (the shared pool's tags would drown it), three class boons of it owned, picked across the pool.
	var tag_counts := {}
	var own_pool: Array = Boons.pool_for(class_id).filter(func(id): return str(Boons.def(str(id)).get("class", "")) == class_id)
	for id in own_pool:
		for tg in Boons.def(str(id)).tags:
			tag_counts[tg] = int(tag_counts.get(tg, 0)) + 1
	var best_tag := ""
	for tg in tag_counts:
		if best_tag.is_empty() or int(tag_counts[tg]) > int(tag_counts[best_tag]):
			best_tag = tg
	var tagged: Array = own_pool.filter(func(id): return Boons.def(str(id)).tags.has(best_tag))
	var owned: Array = [tagged[0], tagged[tagged.size() / 2], tagged[-1]]
	var with := 0
	var without := 0
	for s in 400:
		for id in Boons.offer(class_id, owned, 3000 + s):
			with += 1 if Boons.def(str(id)).tags.has(best_tag) else 0
		for id in Boons.offer(class_id, [], 3000 + s):
			without += 1 if Boons.def(str(id)).tags.has(best_tag) else 0
	da.check(with > without * 1.3, "%s: owning %s boons brings more %s boons (%d vs %d of 1200 cards)" % [class_id, best_tag, best_tag, with, without])


func save_check(class_id: String) -> void:
	var picks: Array = Boons.pool_for(class_id).slice(0, 3)
	p.boons = picks.duplicate()
	GameState.characters[p.peer_id] = p.to_character()
	p.boons = []
	p._host_init()
	da.check(p.boons == picks, "%s: a saved hero keeps its boons (%s)" % [class_id, p.boons])
	p.boons = []
	p.recompute_stats()


## LAN: after the boss both heroes get their own three, the portal waits until both chose.
func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	p.iframe_left = 9999.0
	c.iframe_left = 9999.0
	g._boss_defeated.rpc(g.layout.portal_pos)
	await da._wait(0.6)
	da.check(g.boon_pending.has(p.peer_id) and g.boon_pending.has(c.peer_id) and g.boon_pending[p.peer_id] != g.boon_pending[c.peer_id],
			"host: both heroes have their own three boons")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["bn_offer", g.boon_pending[c.peer_id]])
	await da._wait(0.5)
	for pl in [p, c]:
		pl.host_teleport(g.portal.global_position)
		g.portal_ready[pl.peer_id] = true
	g._try_descend()
	await da._wait(0.6)
	da.check(g._descend_timer < 0.0 and g.depth == 1, "host: with boons unchosen the portal waits")
	# The client's cards open after the breath before them; then each picks.
	await da._wait(float(GameData.bal("boons.choose_delay")) + 1.2)
	g.request_boon(1)
	await da._wait(0.4)
	da.check(p.boons.size() == 1 and g._descend_timer < 0.0, "host: my pick is in, the portal still waits for the client")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["bn_pick", 0])
	await da._wait(1.0)
	da.check(c.boons.size() == 1 and str(c.boons[0]) == str(g.boon_pending.get(c.peer_id, [c.boons[0]])[0]), "host: the client's pick applied (%s)" % [c.boons])
	g._try_descend()
	await da._wait(2.5)
	da.check(g.depth == 2, "host: everyone chose, the party descends")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["bn_kept", null])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var me: Player = da._local()
	match cmd:
		"bn_offer":
			da.check(g.my_boon_offer == arg and g.my_boon_offer.size() == 3, "client: my own three boons arrived (%s)" % [g.my_boon_offer])
			await da._wait(float(GameData.bal("boons.choose_delay")) + 0.6)
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(hud._overlay != null and hud._overlay.get("_cards") is Array and hud._overlay._cards.size() == 3, "client: the boon cards opened")
		"bn_pick":
			var hud2: Node = da.get_tree().get_first_node_in_group("hud")
			if hud2._overlay and hud2._overlay.has_method("_choose"):
				hud2._overlay._choose(int(arg))
			else:
				g.request_boon.rpc_id(1, int(arg))
		"bn_kept":
			da.check(me.boons.size() == 1, "client: my boon is mine on the next floor (%s)" % [me.boons])
