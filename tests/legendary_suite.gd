class_name LegendarySuite
extends SkillSuite
## Headless legendary checks (scenario "legendaries", solo host, --class=<id>): every legendary
## of the class is generated at level 30, worn by the hero (stats and procs recompiled) and its
## affix proven by the item's data `test` block: a flag, a stat, a skill modifier, a compiled
## proc, or a cast / trigger with expectations (the skill suite's triggers and checks).

const SLOT_OF := {"head": "head", "chest": "chest", "legs": "legs", "boots": "boots", "gloves": "gloves",
	"main_hand": "main_hand", "off_hand": "off_hand", "ring": "ring_1", "necklace": "necklace"}

var _rng := RandomNumberGenerator.new()


func run_legendaries(class_id: String) -> void:
	await _prepare()
	_unlock_all_skills()
	var ids: Array = GameData.legendaries.keys().filter(func(id): return str(GameData.legendaries[id]["class"]) == class_id)
	ids.sort()
	da.check(ids.size() == 27, "%s has %d legendaries in data" % [class_id, ids.size()])
	if not da.only.is_empty():
		ids = ids.filter(func(id): return da.only.has(id))
	for id in ids:
		await check_legendary(str(id))
	# A legendary drop roll from a boss picks a real legendary scaled to the item level.
	var lg := LootTable.roll_legendary([class_id], 12, _rng)
	da.check(int(lg.get("rarity", 0)) == 5 and lg.has("legendary") and int(lg.ilvl) == 12, "a legendary roll makes a level-12 legendary")


func check_legendary(id: String) -> void:
	var lg: Dictionary = GameData.legendaries[id]
	var item := ItemGenerator.make_legendary(id, 30, _rng)
	da.check(int(item.get("rarity", 0)) == 5 and item.name == lg.name and not item.get("stats", {}).is_empty(), "%s generates" % id)
	var low := ItemGenerator.make_legendary(id, 1, _rng)
	var k0: String = str(lg.stats.keys()[0])
	if absf(float(lg.stats[k0])) >= 1.0:
		da.check(float(low.stats[k0]) < float(item.stats[k0]), "%s scales its stats with the item level" % id)
	var tip := ItemGenerator.describe(item, str(lg["class"]), 30)
	da.check(tip.any(func(l): return str(l[0]) == str(lg.affix)), "%s tooltip shows its affix" % id)
	var saved: Dictionary = p.inv.equipment.duplicate(true)
	_reset()
	var before: Dictionary = p.stats.final.duplicate()
	_wear(item)
	var t: Dictionary = lg.get("test", {})
	if t.has("flag"):
		da.check(p.stats.has_flag(str(t.flag)), "%s: flag %s" % [id, t.flag])
	elif t.has("stat"):
		da.check(float(p.stats.get_stat(str(t.stat))) != float(before.get(str(t.stat), 0.0)), "%s: changes %s" % [id, t.stat])
	elif t.has("stat_below"):
		da.check(p.stats.mult("cc_duration") < float(t.stat_below[1]), "%s: crowd control duration x%.2f" % [id, p.stats.mult("cc_duration")])
	elif t.has("skill_mod"):
		da.check(p.stats.skill_mod(str(t.skill_mod[0]), str(t.skill_mod[1])) != 0.0, "%s: modifies %s %s" % [id, t.skill_mod[0], t.skill_mod[1]])
	elif t.has("chance_proc"):
		var found := p.static_procs.any(func(pr): return str(pr.get("event", "")) == str(t.chance_proc) and str(pr.get("_key", "")).begins_with("i:"))
		da.check(found, "%s: %s proc is live" % [id, t.chance_proc])
	elif t.has("titan_grip"):
		p.inv.equipment["main_hand"] = ItemGenerator.generate_equipment("warhammer", 10, 2, _rng)
		var sh := ItemGenerator.generate_equipment("shield", 10, 2, _rng)
		p.inv.backpack.append(sh)
		var err := p.inv.equip_from_backpack(p.inv.backpack.size() - 1, 99)
		da.check(err.is_empty() and p.inv.equipment.has("main_hand") and p.inv.equipment.has("off_hand"), "%s: a two-handed weapon and a shield together" % id)
	else:
		await _run_spec(id, t)
	p.inv.equipment = saved
	p.recompute_stats()
	await da._wait(0.05)


func _wear(item: Dictionary) -> void:
	var slot: String = SLOT_OF.get(str(GameData.legendaries[item.legendary].slot), "head")
	if slot == "main_hand" and int(item.get("hands", 1)) == 2:
		p.inv.equipment.erase("off_hand")
	if slot == "off_hand" and int(p.inv.equipment.get("main_hand", {}).get("hands", 1)) == 2 and not Inventory.stays_with_two_hand(item):
		p.inv.equipment.erase("main_hand")
	p.inv.equipment[slot] = item
	p.recompute_stats()


func _run_spec(id: String, t: Dictionary) -> void:
	var setup: Dictionary = t.get("setup", {})
	var target: Enemy = dummies[0]
	if setup.has("self_hp"):
		p.health.hp = p.health.max_hp * float(setup.self_hp)
	if setup.has("self_resource"):
		p.resource.value = float(setup.self_resource)
	if setup.has("self_cooldown"):
		p.cooldowns[str(setup.self_cooldown)] = 30.0
	for st in setup.get("target_status", []):
		target.status.apply(str(st), 6.0, 5.0, Combat.instance.make_ctx(p, {"id": "t", "school": "spell"}))
	for st2 in setup.get("ally_status", []):
		ally.status.apply(str(st2), 6.0, 2.0, Combat.instance.env_ctx(1.0))
	if setup.get("target_near", false):
		target.host_teleport(g.nearest_floor(p.global_position + Vector2(28, 0)))
	if setup.get("cluster", false):
		for i in range(1, dummies.size()):
			dummies[i].host_teleport(g.nearest_floor(target.global_position + Vector2.from_angle(TAU * i / 3.0) * 34.0))
	if setup.get("ally_near", false):
		ally.host_teleport(g.nearest_floor(p.global_position + Vector2(-30, 0)))
	if setup.get("ally_hurt", false):
		ally.health.hp = ally.health.max_hp * 0.4
	if setup.has("target_attacks"):
		var tctx := Combat.instance.make_ctx(target, {"id": "test_attack", "school": "melee"})
		da.get_tree().create_timer(0.3).timeout.connect(func():
			tctx.melee_hit = true
			tctx.cannot_miss = true
			Combat.instance.deal_damage(tctx, p, 10.0))
	if p.has_method("host_reset_dodge"):
		p._dodge_cd_host = 5.0
	await da._wait(0.1)
	var b := _snapshot()
	b.p_res = p.resource.value
	if t.has("cast"):
		var sid := str(t.cast)
		var aim: Vector2 = target.global_position
		match str(t.get("aim", "target")):
			"ally":
				aim = ally.global_position
			"far":
				aim = dummies[2].global_position
			"self":
				aim = p.global_position
		p.aim_pos = aim
		p.auto_aim = aim
		p.cooldowns.erase(sid)
		var err := Combat.instance.try_use_skill(p, sid, aim)
		da.check(err.is_empty() or err == "Passive", "%s: %s cast%s" % [id, sid, "" if err.is_empty() else " refused: " + err])
		if GameData.skill(sid).has("charge_time"):
			await da._wait(float(GameData.skill(sid).charge_time) + 0.05)
			Combat.instance.release_charge(p, aim)
		if "recast" in t.get("expect", []):
			await da._wait(0.3)
			var err2 := Combat.instance.try_use_skill(p, sid, aim)
			da.check(err2.is_empty(), "%s: %s second charge%s" % [id, sid, "" if err2.is_empty() else ": " + err2])
	elif t.has("trap"):
		Combat.instance.try_use_skill(p, str(t.trap), target.global_position)
	elif t.has("trigger"):
		await _trigger(str(t.trigger))
	if t.has("then"):
		await da._wait(0.3)
		await _trigger(str(t.then))
	await da._wait(float(t.get("wait", 1.0)))
	var a := _snapshot()
	a.p_res = p.resource.value
	for ex in t.get("expect", []):
		if str(ex) == "recast":
			continue
		da.check(_expect(str(ex), b, a, target, -1), "%s: %s" % [id, ex])
