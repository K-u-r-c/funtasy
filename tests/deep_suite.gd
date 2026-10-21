class_name DeepSuite
extends RefCounted
## #74 Deep variants (scenario "deep" solo, "deep_lan" host + client): corrupted monsters appear
## from floor 8 at the data share and never before; each corrupted ability warns before it acts
## and does its job; a corrupted monster is named, tinted, has its aura, more health and better
## loot; a boss met before (or from floor 11) fights ascended, and every ascended boss's extra
## mechanic strikes after its warning, on the host and on the client; ascended bosses drop more.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _keep() -> void:
	p.iframe_left = 9999.0
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.health.hp = p.health.max_hp


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	shares()
	await abilities()
	loot()
	ascension_rule()
	var ids: Array = GameData.bosses.keys()
	ids.sort()
	for id in ids:
		await ascended_boss(str(id))
	await BalanceSuite.new(da).run_deep()


## Over 6000 rolls per depth: none before floor 8, then the data share (+-3%) of eligible monsters,
## every ability seen; critters and bosses' parts never.
func shares() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 74
	var bad: Array = []
	var seen := {}
	for d in [5, 7, 8, 10, 14, 20, 30]:
		var n := 0
		var hit := 0
		for i in 6000:
			var ab: String = g.pick_corruption("ghoul", d, rng)
			n += 1
			if not ab.is_empty():
				hit += 1
				seen[ab] = true
		var want: float = g.corruption_share(d)
		if absf(float(hit) / n - want) > 0.03 or (d < 8 and hit > 0):
			bad.append("%d: %.3f vs %.3f" % [d, float(hit) / n, want])
	var critter: bool = g.pick_corruption("plague_rat", 20, rng).is_empty()
	da.check(bad.is_empty() and seen.size() == GameData.corruption.abilities.size() and critter,
		"corrupted monsters from floor 8 at the data share, every ability rolled, no critters (%s)" % ["ok" if bad.is_empty() else bad])


func _spawn(ab: String, at: Vector2) -> Enemy:
	return g.spawn_monster("ghoul", at, false, {"corrupt": ab})


## Every ability: the monster is named, tinted and wears its aura, has more health; its ability
## warns (lead >= its data warn) before it acts and does its job.
func abilities() -> void:
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	await da._wait(0.3)
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(80, 0))
	p.host_teleport(g.nearest_floor(spot + Vector2(-70, 0)))
	_keep()
	var plain: Enemy = g.spawn_monster("ghoul", spot + Vector2(0, 60), false)
	await da._wait(0.3)
	for ab in GameData.corruption.abilities:
		_keep()
		var m := _spawn(str(ab), spot)
		# A wounded neighbour for the ward.
		var buddy: Enemy = null
		if str(ab) == "shield":
			buddy = g.spawn_monster("ghoul", spot + Vector2(30, 10), false)
		await da._wait(0.3)
		if buddy:
			buddy.health.hp = buddy.health.max_hp * 0.5
		var b: CorruptBehavior = null
		for x in m.behaviors:
			if x is CorruptBehavior:
				b = x
		var tinted: bool = m.sprite.get_child_count() > 0 and m.sprite.get_child(0).self_modulate != Color.WHITE
		var looks: bool = m.display_name == Loc.f("Corrupted %s", [Loc.t(str(m.def.name))]) and m.get_node_or_null("DeepAura") != null and tinted \
			and m.health.max_hp > plain.health.max_hp * 1.15
		var look_txt := "%s / %s %s" % [m.display_name, tinted, [m.health.max_hp, plain.health.max_hp]]
		if b == null:
			da.check(false, "the corrupted ghoul has its %s ability" % ab)
			continue
		await b.test_trigger(self)
		var warn := float(GameData.corruption.abilities[ab].warn)
		await da._wait(warn + 0.6)
		var err: String = b.test_check(self)
		var lead := Telegraph.lead_of("corrupt_" + str(ab))
		da.check(looks and err.is_empty() and lead >= warn - 0.05, "Corrupted %s: named, tinted, aura, tougher; warned %.2f s (data %.2f) before it acted%s%s" % [ab, lead, warn, "" if err.is_empty() else ": " + err,
			"" if looks else " [look: %s]" % look_txt])
		for e in g.enemies_root.get_children():
			if e != plain and not e.is_boss:
				e.queue_free()
		await da._wait(0.3)
	plain.queue_free()


## A corrupted monster's loot override gives more and better drops than a plain one's.
func loot() -> void:
	var cl: Dictionary = GameData.corruption.loot
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var plain := 0
	var corrupt := 0
	GameState.set_meta("test_no_legendary", true)
	for i in 2000:
		plain += LootTable.roll("monster", 10, 10, ["warrior"], rng).size()
		corrupt += LootTable.roll("monster", 10, 10, ["warrior"], rng, {"drop_mult": float(cl.drop_mult), "gold_mult": float(cl.gold_mult), "rarity_up_chance": float(cl.rarity_up_chance)}).size()
	GameState.remove_meta("test_no_legendary")
	da.check(corrupt > plain * 1.12, "a corrupted monster drops more (%d vs %d over 2000 kills)" % [corrupt, plain])


## Ascended from floor 11, or when the run met the boss before.
func ascension_rule() -> void:
	var saved: Variant = GameState.game.get("bosses_met")
	GameState.game.bosses_met = []
	var a: bool = not g.is_ascended("morvath", 3) and g.is_ascended("morvath", 11)
	GameState.game.bosses_met = ["morvath"]
	var b: bool = g.is_ascended("morvath", 3) and not g.is_ascended("vespera", 3)
	if saved == null:
		GameState.game.erase("bosses_met")
	else:
		GameState.game.bosses_met = saved
	da.check(a and b, "a boss ascends from floor 11, or when the run has met it before")


## Boss `id` ascended: its name, its halo and aura, more health, its ascended mechanic in the
## phase; the mechanic warns then strikes; its drops are richer.
func ascended_boss(id: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	Combat.instance.clear_floor()
	await da._wait(0.4)
	var boss_pos: Vector2 = g.layout.boss_pos
	_keep()
	p.host_teleport(g.nearest_floor(boss_pos + Vector2(0, 70)))
	var plain_hp: float = 0.0
	var plain: Enemy = g.spawn_monster(id, boss_pos + Vector2(400, 0), true)
	await da._wait(0.2)
	if plain:
		plain_hp = plain.health.max_hp
		plain.queue_free()
	var boss: Enemy = g.spawn_monster(id, boss_pos, true, {"ascended": true})
	await da._wait(0.4)
	if not is_instance_valid(boss):
		da.check(false, "%s spawned ascended" % id)
		return
	boss.add_threat(p, 10.0)
	var m: BossMechanic = null
	for x in boss.mechanics:
		if str(x.params.get("id", "")) == "ascension":
			m = x
	var looks: bool = boss.display_name == Loc.f("Ascended %s", [Loc.t(str(boss.def.name))]) and boss.get_node_or_null("DeepAura") != null and boss.health.max_hp > plain_hp * 1.1
	if m == null:
		da.check(false, "%s has its ascended mechanic" % id)
		return
	_keep()
	await m.test_trigger(self)
	_keep()
	var err: String = m.test_check(self)
	da.check(looks and err.is_empty(), "Ascended %s: named, halo, tougher; %s warns then strikes%s" % [id, boss.def.ascended.name, "" if err.is_empty() else ": " + err])
	boss.queue_free()
	await da._wait(0.3)


# =========================================================================================
# LAN
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var boss_pos: Vector2 = g.layout.boss_pos
	p.host_teleport(g.nearest_floor(boss_pos + Vector2(-40, 80)))
	c.host_teleport(g.nearest_floor(boss_pos + Vector2(40, 80)))
	# A corrupted, volatile monster dies next to the client: both see the warning first.
	var vm: Enemy = g.spawn_monster("ghoul", g.nearest_floor(boss_pos + Vector2(40, 40)), false, {"corrupt": "burst"})
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["deep_corrupt", str(vm.name)])
	await da._wait(0.6)
	Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), vm, 999999.0, {"damage_type": "true"})
	await da._wait(2.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["deep_warned", "corrupt_burst"])
	await da._wait(0.6)
	var ids: Array = GameData.bosses.keys()
	ids.sort()
	for id in ids:
		for e in g.enemies_root.get_children():
			e.queue_free()
		Combat.instance.clear_floor()
		await da._wait(0.4)
		for h in [p, c]:
			h.iframe_left = 9999.0
			if h.life_state != Player.Life.ALIVE:
				h.revive(1.0)
		var boss: Enemy = g.spawn_monster(str(id), boss_pos, true, {"ascended": true})
		await da._wait(0.5)
		boss.add_threat(p, 10.0)
		var m: BossMechanic = null
		for x in boss.mechanics:
			if str(x.params.get("id", "")) == "ascension":
				m = x
		await m.test_trigger(self)
		da.check(m.test_check(self).is_empty(), "host: ascended %s's %s struck after its warning" % [id, boss.def.ascended.name])
		NetworkManager.to_clients("DevAuto", "client_cmd", ["deep_boss", [str(boss.name), "ascended_" + str(m.params.key)]])
		await da._wait(0.6)
		boss.queue_free()
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	match cmd:
		"deep_corrupt":
			var e: Node = g.enemies_root.get_node_or_null(NodePath(str(arg)))
			da.check(e != null and e.corrupt == "burst" and e.get_node_or_null("DeepAura") != null, "client: the corrupted monster wears its aura and name (%s)" % (e.display_name if e else "?"))
		"deep_warned":
			# The burst may reach a busy client a moment after the host's word to check it.
			await da._wait_until(func(): return Telegraph.lead_of(str(arg)) >= 0.0, 3.0)
			da.check(Telegraph.lead_of(str(arg)) >= float(GameData.corruption.abilities.burst.warn) - 0.15, "client: the volatile corpse warned %.2f s before it burst" % Telegraph.lead_of(str(arg)))
		"deep_boss":
			var b: Node = g.enemies_root.get_node_or_null(NodePath(str(arg[0])))
			var lead := Telegraph.lead_of(str(arg[1]))
			da.check(b != null and b.ascended and b.get_node_or_null("DeepAura") != null and lead > 0.5,
				"client: ascended %s with its halo; its %s warned %.2f s before it struck" % [b.def_id if b else "?", arg[1], lead])
