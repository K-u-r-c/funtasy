class_name SkillSuite
extends RefCounted
## Headless skill checks, driven by DevAuto on a solo host:
## - "skills" (--class=X): every skill of the class in GameData is cast by the hero on training
##   dummies and must visibly do something; passives must be passive.
## - "primitives": every test_* skill (data/skills/test_primitives.json, one per effect primitive)
##   is cast and its `test.expect` list is checked exactly.
## A skill's optional `test` block: {"setup": {...}, "expect": [...], "wait": s, "aim": "target" | "self"}.

const DUMMY_OFFSETS := [Vector2(64, 0), Vector2(98, 22), Vector2(128, -20)]

var da: Node
var g: Node
var p: Player
var dummies: Array = []
var warded: Enemy
var ally: Enemy  ## a dummy on the players' team: target of ally skills in solo
var _start := Vector2.ZERO
var _class_run := false
var _spawned: Enemy = null  ## a monster a legendary trigger spawned (Exorcist's Iron Striders)
var _spawned_seen: Array = []  ## statuses that landed on it


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run_class(class_id: String) -> void:
	var ids: Array = []
	for sid in GameData.skills:
		if str(sid).begins_with(class_id + "_"):
			ids.append(sid)
	ids.sort()
	await _prepare()
	_class_run = true
	# 30 talent-tree skills (GDD 3); a class primary outside them (the priest's Holy Strike, #9) comes
	# on top, drawn in the shared root since #106; every class skill has its node.
	var tree_ids: Array = p.talent_tree().get("nodes", []).filter(func(nd): return nd.get("type", "") == "skill").map(func(nd): return str(nd.skill))
	var extra: Array = ids.filter(func(x): return not tree_ids.has(x))
	var outside := 1 if class_id == "priest" else 0
	da.check(tree_ids.size() == 30 + outside and extra.is_empty(),
			"%s has 30 tree skills plus %d primary outside them (%d nodes, missing %s)" % [class_id, outside, tree_ids.size(), extra])
	_unlock_all_skills()
	await anim_rules(class_id)
	for sid in ids:
		await cast_and_check(str(sid))
	await run_keystones()
	# Tooltips: every skill describes what it does with the host formulas.
	var bare: Array = []
	for sid2 in ids:
		var sk: Dictionary = GameData.skill(str(sid2))
		var rows := SkillInfo.rows(p, sk)
		var useful := rows.any(func(r): return int(r.kind) in [SkillInfo.Kind.DAMAGE, SkillInfo.Kind.HEAL, SkillInfo.Kind.STATUS])
		if not useful and not sk.get("passive", false) and not sk.has("toggle"):
			bare.append(sid2)
	da.check(bare.is_empty(), "every %s skill tooltip shows damage, healing or a status (missing: %s)" % [class_id, bare])
	if class_id == "priest":
		await priest_heal_costs()


## #102: the priest's healing costs ~1.8x its old mana (data and a real cast's spend); a full mana
## bar affords clearly fewer Flash Heals; the other priest skills keep their costs.
const PRIEST_OLD_COSTS := {"priest_heal": 25, "priest_renew": 15, "priest_renewal": 45, "priest_holy_nova": 30, "priest_lightwell": 40}
func priest_heal_costs() -> void:
	var bad: Array = []
	for sid in PRIEST_OLD_COSTS:
		var now := float(GameData.skill(sid).get("cost", 0))
		if now < float(PRIEST_OLD_COSTS[sid]) * 1.7:
			bad.append("%s %d -> %.0f" % [sid, PRIEST_OLD_COSTS[sid], now])
	var cps := float(GameData.skill("priest_penance").channel.cost_per_second)
	if cps < 12.0 * 1.7:
		bad.append("penance %.0f/s" % cps)
	for sid2 in ["priest_smite", "priest_holy_strike", "priest_purify"]:
		var c := float(GameData.skill(sid2).get("cost", 0))
		if sid2 == "priest_purify" and c != 10.0 or sid2 != "priest_purify" and c != 0.0:
			bad.append("%s changed to %.0f" % [sid2, c])
	da.check(bad.is_empty(), "the priest's heals cost about 1.8x the old mana, the other skills the same (%s)" % [bad])
	# A real Flash Heal spends its new cost.
	await _reset()
	p.skills[1] = "priest_heal"
	p.cooldowns.clear()
	p.resource.value = p.resource.max_value
	var m0: float = p.resource.value
	var err: String = Combat.instance.try_use_skill(p, "priest_heal", p.global_position)
	await da._wait(1.0)
	var spent: float = m0 - p.resource.value
	var want: float = p.stats.cost_for(GameData.skill("priest_heal"))
	da.check(err.is_empty() and absf(spent - want) <= 2.0 and want >= 40.0, "a Flash Heal spends its new cost (%.0f mana, data %.0f)" % [spent, want])
	var bar: float = p.resource.max_value
	da.check(floori(bar / want) < floori(bar / (want * 25.0 / float(GameData.skill("priest_heal").cost))), "a full bar affords fewer Flash Heals (%d instead of %d)" % [floori(bar / want), floori(bar / (want * 25.0 / float(GameData.skill("priest_heal").cost)))])


## #19: the animation of every skill comes from data (a skill's anim, the weapon's attack / cast
## animation), and an instant hero skill lands on its animation's impact frame, not before.
func anim_rules(class_id: String) -> void:
	var anims: Dictionary = GameData.assets.characters.anims
	var bad: Array = []
	for sid in GameData.skills:
		if str(sid).begins_with(class_id + "_") and not anims.has(str(GameData.skills[sid].get("anim", "attack"))):
			bad.append(sid)
	da.check(bad.is_empty(), "every %s skill names a known animation (%s)" % [class_id, bad])
	var saved: Dictionary = p.inv.equipment.get("main_hand", {})
	var want := {"sword": ["slash", "cast"], "greatsword": ["cleave", "cast"], "warhammer": ["cleave", "cast"], "bow": ["shoot_bow", "cast"],
		"crossbow": ["shoot_crossbow", "cast"], "sling": ["sling", "cast"], "arcane_wand": ["flick", "flick"], "holy_wand": ["slash", "flick"],
		"battle_staff": ["cleave", "cast"], "": ["bash", "cast"]}
	var wrong: Array = []
	for base in want:
		if str(base).is_empty():
			p.inv.equipment.erase("main_hand")
		else:
			p.inv.equipment["main_hand"] = {"base": base}
		var got := [Combat.anim_for(p, {"anim": "attack"}), Combat.anim_for(p, {"anim": "cast"})]
		if got != want[base]:
			wrong.append("%s: %s" % [base, got])
	if saved.is_empty():
		p.inv.equipment.erase("main_hand")
	else:
		p.inv.equipment["main_hand"] = saved
	da.check(wrong.is_empty(), "the main-hand weapon picks the attack and cast animations (%s)" % [wrong])
	da.check(Combat.anim_for(p, {"anim": "spin"}) == "spin" and Combat.anim_for(p, {"anim": "empower"}) == "empower", "a skill's own animation overrides the weapon's")
	_reset()
	var sid := str(GameData.classes[class_id].primary_attack)
	var sk := GameData.skill(sid)
	var anim := Combat.anim_for(p, sk)
	var delay := Combat.instance.impact_delay(p, sk, anim)
	var d0: Enemy = dummies[0]
	d0.health.hp = d0.health.max_hp
	var hp0 := d0.health.hp
	var err := Combat.instance.try_use_skill(p, sid, d0.global_position)
	var early := not p.impact_pending.is_empty() and is_equal_approx(d0.health.hp, hp0)
	await da._wait(delay + 0.7)
	da.check(err.is_empty() and delay > 0.05 and early and d0.health.hp < hp0,
			"%s (%s) lands on its impact frame after %.2f s, not at the press" % [sid, anim, delay])
	_reset()
	await interrupt_rules(class_id, sid, d0)
	# #22: the Amalgam's twins resist one school each but every class can hurt both.
	for twin_id in ["bile_twin", "gristle_twin"]:
		var tw: Enemy = g.spawn_monster(twin_id, g.nearest_floor(_start + Vector2(48, 0)), false)
		await da._wait(0.3)
		tw.status.apply("stun", 5.0, 1.0, null)
		var thp := tw.health.hp
		p.cooldowns.clear()
		Combat.instance.try_use_skill(p, sid, tw.global_position)
		await da._wait(delay + 0.9)
		da.check(tw.health.hp < thp, "%s's %s hurts the %s (%.0f -> %.0f)" % [class_id, sid, twin_id, thp, tw.health.hp])
		tw.queue_free()
		_reset()
		await da._wait(0.2)


## #26: a skill pressed mid-swing starts in the same frame and cuts the primary's pending blow
## off; the primary pressed during any pending swing, or a skill during a skill's, still waits.
func interrupt_rules(class_id: String, primary: String, target: Enemy) -> void:
	var tested: Array = []
	var bad: Array = []
	for sid in GameData.skills:
		var sk: Dictionary = GameData.skills[sid]
		if not str(sid).begins_with(class_id + "_") or sid == primary or sk.get("passive", false) or sk.has("toggle") \
				or sk.has("usable_if") or sk.get("requires_target", false) or int(sk.get("charges", 1)) > 1:
			continue
		_reset()
		p.resource.value = p.resource.max_value
		target.health.hp = target.health.max_hp
		var err0 := Combat.instance.try_use_skill(p, primary, target.global_position, {"primary": true})
		if not err0.is_empty() or not p.impact_pending.get("primary", false):
			bad.append("%s: primary swing didn't start (%s)" % [sid, err0])
			continue
		var again := Combat.instance.try_use_skill(p, primary, target.global_position, {"primary": true})
		var frame := Engine.get_process_frames()
		var err := Combat.instance.try_use_skill(p, str(sid), target.global_position)
		var cut := p.impact_pending.is_empty() or str(p.impact_pending.get("skill", "")) == str(sid)
		var shown := p._action_anim == Combat.anim_for(p, sk)
		if not err.is_empty() or Engine.get_process_frames() != frame or not cut or not shown or again != "Busy":
			bad.append("%s: %s, cut %s, anim %s, primary again %s" % [sid, err, cut, p._action_anim, again])
		tested.append(sid)
		if tested.size() >= 6:
			break
	da.check(tested.size() >= 3 and bad.is_empty(), "%s skills pressed mid-swing start in the same frame and cut the swing (%s)%s" % [class_id, tested, "" if bad.is_empty() else ": %s" % [bad]])
	_reset()
	await da._wait(0.3)


## Every skill node learned (their procs compile), no passive talents or keystones.
func _unlock_all_skills() -> void:
	var t := {}
	for nd in p.talent_tree().get("nodes", []):
		if nd.get("type", "") == "skill" and not nd.get("starter", false):
			t[nd.id] = 1
	p.talents = t
	p.recompute_stats()


## Each keystone alone: its stat, flag or triggered effect.
func run_keystones() -> void:
	for nd in p.talent_tree().get("nodes", []):
		if nd.get("type", "") != "keystone":
			continue
		var t: Dictionary = nd.get("test", {})
		da.check(not t.is_empty(), "keystone %s has a test" % nd.id)
		if t.is_empty():
			continue
		_reset()
		var talents := {}
		for n2 in p.talent_tree().get("nodes", []):
			if n2.get("type", "") == "skill" and not n2.get("starter", false):
				talents[n2.id] = 1
		talents[nd.id] = 1
		p.talents = talents
		p.recompute_stats()
		await da._wait(0.2)
		p.health.hp = p.health.max_hp * 0.5
		if t.has("stat_above"):
			da.check(p.stats.get_stat(str(t.stat_above[0]), 1.0) > float(t.stat_above[1]), "keystone %s raises %s (%.2f)" % [nd.id, t.stat_above[0], p.stats.get_stat(str(t.stat_above[0]), 1.0)])
		if t.has("stat_flag"):
			da.check(p.stats.has_flag(str(t.stat_flag)), "keystone %s sets %s" % [nd.id, t.stat_flag])
		for stt in t.get("setup_target", []):
			Combat.instance.apply_status(Combat.instance.make_ctx(p, {"id": "test", "school": "spell"}), dummies[0], str(stt), 8.0, 2.0)
		if t.has("trigger") or t.has("cast"):
			var before := _snapshot()
			if t.has("cast"):
				var err := Combat.instance.try_use_skill(p, str(t.cast), dummies[0].global_position)
				da.check(err.is_empty(), "keystone %s: %s cast" % [nd.id, t.cast])
				if t.has("then_remove"):
					await da._wait(0.3)
					p.status.remove(str(t.then_remove))
			else:
				await _trigger(str(t.trigger))
			await da._wait(float(t.get("wait", 0.8)))
			var after := _snapshot()
			for ex in t.get("expect", []):
				da.check(_expect(str(ex), before, after, dummies[0], -1), "keystone %s: %s" % [nd.id, ex])
	_unlock_all_skills()


## Fires a proc trigger by hand: melee_hits, crit:<skill>, fatal, kill, dodge, block, heal.
func _trigger(what: String) -> void:
	var kind := what.get_slice(":", 0)
	var arg := what.get_slice(":", 1) if what.contains(":") else ""
	var d0: Enemy = dummies[0]
	match kind:
		"melee_hits", "hits", "crit":
			var sid := arg if not arg.is_empty() else str(p.skills[0])
			var ctx := Combat.instance.make_ctx(p, GameData.skill(sid))
			ctx.melee_hit = kind == "melee_hits" or str(GameData.skill(sid).get("school", "")) == "melee"
			if kind == "crit":
				ctx.guaranteed_crit = true
			for i in (1 if kind == "crit" else 3):
				Combat.instance.deal_damage(ctx, d0, 5.0)
				await da._wait(0.05)
		"fatal", "fatal_later":
			if kind == "fatal_later":
				await da._wait(1.0)  # some history to rewind to
			Combat.instance.deal_damage(Combat.instance.make_ctx(d0, {"id": "test", "school": "spell"}), p, p.health.max_hp * 3.0, {"damage_type": "true"})
		"permafrost", "wait":
			if not arg.is_empty():
				await da._wait(float(arg))  # auras tick on their own
		"overheal":
			ally.health.hp = ally.health.max_hp * 0.9
			Combat.instance.heal(Combat.instance.make_ctx(p, {"id": "test", "school": "spell"}), ally, ally.health.max_hp * 0.5)
		"kill":
			var victim: Enemy = g.spawn_monster("ghoul", g.nearest_floor(_start + Vector2(40, 30)), false)
			await da._wait(0.2)
			Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), victim, victim.health.hp * 5.0, {"damage_type": "true"})
		"dodge":
			Combat.instance.fire(p, "on_dodge", {"target": d0, "attacker": d0})
		"block":
			Combat.instance.fire(p, "on_block", {"target": p, "attacker": d0, "amount": 10.0, "blocked_amount": 10.0})
		"heal":
			ally.health.hp = ally.health.max_hp * 0.5
			Combat.instance.heal(Combat.instance.make_ctx(p, {"id": "test", "school": "spell"}), ally, ally.health.max_hp * 0.8)
		"cast_skill":
			Combat.instance.try_use_skill(p, arg, d0.global_position)
		"cast4":
			for i in 4:
				Combat.instance.fire(p, "on_skill_cast", {"skill": str(p.skills[0]), "school": str(GameData.skill(str(p.skills[0])).get("school", "")), "target": null, "ctx": {}})
		"poison_kill":
			var v2: Enemy = g.spawn_monster("ghoul", g.nearest_floor(d0.global_position + Vector2(0, 20)), false)
			await da._wait(0.2)
			var pctx := Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0])))
			Combat.instance.apply_status(pctx, v2, "poison", 5.0, 1.0)
			Combat.instance.deal_damage(pctx, v2, v2.health.hp * 5.0, {"damage_type": "true"})
		"dot":
			Combat.instance.apply_status(Combat.instance.make_ctx(p, {"id": "test", "school": "spell"}), d0, arg, 4.0, 3.0)
			await da._wait(1.2)
		# Legendary triggers ---------------------------------------------------------------
		"low_hp":
			p.health.hp = p.health.max_hp * 0.25
			Combat.instance.fire(p, "on_low_hp", {"target": d0})
		"hits5":
			var c5 := Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0])))
			for i in 5:
				Combat.instance.deal_damage(c5, d0, 2.0)
				await da._wait(0.05)
		"crit_taken":
			var cc := Combat.instance.test_ctx(d0, {"id": "test_attack", "school": "melee"})
			cc.guaranteed_crit = true
			Combat.instance.deal_damage(cc, p, 5.0)
		"dodge_roll":
			Combat.instance.fire(p, "on_dodge_roll", {"target": d0, "dir": Vector2.RIGHT})
		"ally_big_hit":
			ally.host_teleport(g.nearest_floor(p.global_position + Vector2(-40, 0)))
			ally.health.hp = ally.health.max_hp
			await da._wait(0.1)
			var bc := Combat.instance.test_ctx(d0, {"id": "test_attack", "school": "melee"})
			Combat.instance.deal_damage(bc, ally, ally.health.max_hp * 0.5, {"damage_type": "true"})
		"unlit":
			var best := p.global_position
			for y in range(2, g.dungeon.size.y - 2, 2):
				for x in range(2, g.dungeon.size.x - 2, 2):
					var c2 := Vector2i(x, y)
					if g.dungeon.cell_at(c2) == DungeonGenerator.CELL_FLOOR and not g.dungeon.in_safe_cell(c2) and not LightLayers.is_lit(g.get_tree(), g.dungeon.cell_center(c2), true):
						best = g.dungeon.cell_center(c2)
			p.host_teleport(best)
			await da._wait(1.4)
		"move":
			# Whole cells back and forth (nearest_floor snaps to cell centres).
			for i in 8:
				p.host_teleport(g.nearest_floor(p.global_position + Vector2(g.dungeon.tile * (1 if i % 2 == 0 else -1), 0)))
				await da.get_tree().physics_frame
				await da.get_tree().physics_frame
		"two_elements":
			Combat.instance.fire(p, "on_skill_cast", {"skill": "mage_fireball", "school": "spell", "target": null, "ctx": {}})
			Combat.instance.fire(p, "on_skill_cast", {"skill": "mage_bolt", "school": "spell", "target": null, "ctx": {}})
		"kill_shadow":
			var vs: Enemy = g.spawn_monster("ghoul", g.nearest_floor(d0.global_position + Vector2(0, 24)), false)
			await da._wait(0.2)
			var sc := Combat.instance.test_ctx(p, {"id": "mage_shadow_bolt", "school": "spell", "damage_type": "shadow"})
			sc.damage_type = "shadow"
			Combat.instance.deal_damage(sc, vs, vs.health.hp * 5.0, {"damage_type": "shadow"})
		"cast5":
			for i in 5:
				Combat.instance.fire(p, "on_skill_cast", {"skill": str(p.skills[0]), "school": "spell", "target": null, "ctx": {}})
		"trample_undead":
			_spawned = g.spawn_monster("skeletal_footman", g.nearest_floor(p.global_position + Vector2(10, 0)), false)
			_spawned_seen = []
			_spawned.set_meta("test_seen_status", _spawned_seen)  # outlives the monster (the holy burst can kill it)
			await da._wait(1.4)
		"ally_behind":
			p.facing = Vector2.RIGHT
			ally.host_teleport(g.nearest_floor(p.global_position + Vector2(-50, 0)))
			await da._wait(1.3)
		"crit_heal":
			Combat.instance.fire(p, "on_heal", {"target": ally, "amount": 60.0, "crit": true})
		"phys_hits":
			var pc := Combat.instance.test_ctx(p, {"id": "test_strike", "school": "melee", "damage_type": "physical"})
			pc.damage_type = "physical"
			pc.melee_hit = true
			for i in 3:
				Combat.instance.deal_damage(pc, d0, 5.0, {"damage_type": "physical"})
				await da._wait(0.05)
		"clear_target":
			d0.status.clear_all()
			d0.set_meta("test_seen_status", [])
		"break_ally_shield":
			ally.health.absorb = 0.0
			ally.status.remove("pw_shield")


func run_primitives() -> void:
	var ids: Array = []
	for sid in GameData.skills:
		if str(sid).begins_with("test_"):
			ids.append(sid)
	ids.sort()
	await _prepare()
	var covered := {}
	for sid in ids:
		for eff in GameData.skills[sid].effects:
			covered[str(eff.type)] = true
			for sub in eff.get("effects", []) + eff.get("on_arrive", []) + eff.get("on_start", []) + eff.get("tick_effects", []) + eff.get("on_hit", []):
				covered[str(sub.type)] = true
	for stid in GameData.status_effects:
		if str(stid).begins_with("test_"):
			for sub2 in GameData.status_effects[stid].get("on_expire", []):
				covered[str(sub2.type)] = true
			for pr in GameData.status_effects[stid].get("procs", []):
				for sub3 in pr.get("do", []):
					covered[str(sub3.type)] = true
	for t in Combat.EFFECT_TYPES:
		if t in ["summon", "resource", "absorb", "heal", "status", "remove_status", "melee", "projectile", "aoe", "trap", "dash",
				"taunt", "revive", "resource_drain", "toggle_status", "zone"]:
			continue  # covered by the class kits and monster abilities
		da.check(covered.has(t), "effect primitive '%s' has a test skill" % t)
	for sid in ids:
		await cast_and_check(str(sid))


func _prepare() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.4)
	_start = g.layout.start
	p.host_teleport(_start)
	p.iframe_left = 0.0
	for i in DUMMY_OFFSETS.size():
		var d: Enemy = g.spawn_monster("training_dummy", g.nearest_floor(_start + DUMMY_OFFSETS[i]), false)
		d.set_meta("test_seen_status", [])
		dummies.append(d)
	warded = g.spawn_monster("training_dummy_warded", g.nearest_floor(_start + Vector2(0, 70)), false)
	ally = g.spawn_monster("training_dummy", g.nearest_floor(_start + Vector2(-110, 0)), false, {"team": Actor.Team.PLAYERS})
	await da._wait(0.6)


func _reset() -> void:
	p.casting = {}
	p.impact_pending = {}
	p.channel = {}
	p.charging = {}
	p.cooldowns.clear()
	p.skill_charges.clear()
	p.status.clear_all()
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.host_teleport(_start)
	p.facing = Vector2.RIGHT
	p.recompute_stats()
	p.health.hp = p.health.max_hp
	p.health.absorb = 0.0
	p.resource.value = p.resource.max_value
	for i in dummies.size():
		var d: Enemy = dummies[i]
		d.status.clear_all()
		d.set_meta("test_seen_status", [])
		d.casting = {}
		d.health.hp = d.health.max_hp
		d.health.absorb = 0.0
		d.host_teleport(g.nearest_floor(_start + DUMMY_OFFSETS[i]))
		d._knock = Vector2.ZERO
		if d.threat:
			d.threat.clear()
	warded.status.clear_all()
	warded.health.hp = warded.health.max_hp
	ally.status.clear_all()
	ally.health.hp = ally.health.max_hp * 0.5
	ally.health.absorb = 0.0
	ally.host_teleport(g.nearest_floor(_start + Vector2(-110, 0)))
	ally.set_meta("test_seen_status", [])
	p.set_meta("test_seen_status", [])
	warded.host_teleport(g.nearest_floor(_start + Vector2(0, 70)))
	Combat.instance.clear_floor()
	for id in g.dungeon.obstacles.keys():
		g.dungeon.remove_obstacle(id)
	for m in g.enemies_root.get_children():
		if m.team == Actor.Team.PLAYERS and m != ally and not dummies.has(m):  # a charmed dummy is still on our side
			m.queue_free()


func _snapshot() -> Dictionary:
	var s := {"p_pos": p.global_position, "p_hp": p.health.hp, "p_absorb": p.health.absorb,
		"p_status": _ids(p), "zones": Combat.instance.zones.size(), "next_id": Combat.instance._next_id,
		"obstacles": g.dungeon.obstacles.size(), "tethers": Combat.instance.tethers.size(),
		"projectiles": Combat.instance.projectiles.size(), "minions": g.get_tree().get_nodes_in_group("minions").size(),
		"warded_hp": warded.health.hp, "ally_hp": ally.health.hp, "ally_pos": ally.global_position, "ally_absorb": ally.health.absorb}
	for i in dummies.size():
		var d: Enemy = dummies[i]
		s["d%d_hp" % i] = d.health.hp
		s["d%d_pos" % i] = d.global_position
		s["d%d_status" % i] = _ids(d)
	return s


func _ids(a: Actor) -> Array:
	var out: Array = []
	for e in a.status.effects:
		out.append(e.id)
	out.sort()
	return out


func cast_and_check(sid: String) -> void:
	var sk := GameData.skill(sid)
	var t: Dictionary = sk.get("test", {})
	if sk.get("passive", false):
		var err0 := Combat.instance.try_use_skill(p, sid, p.global_position)
		da.check(err0 == "Passive", "%s is passive" % sid)
		if t.has("trigger"):
			_reset()
			await da._wait(0.1)
			var b0 := _snapshot()
			await _trigger(str(t.trigger))
			await da._wait(float(t.get("wait", 0.5)))
			var a0 := _snapshot()
			for ex0 in t.get("expect", []):
				da.check(_expect(str(ex0), b0, a0, dummies[0], -1), "%s (passive): %s" % [sid, ex0])
		elif _class_run:
			da.check(false, "passive %s has a trigger test" % sid)
		return
	_reset()
	await da._wait(0.15)
	var setup: Dictionary = t.get("setup", {})
	# Heals need someone hurt to show.
	if JSON.stringify(sk.effects).contains("heal"):
		p.health.hp = p.health.max_hp * 0.5
	var target: Enemy = dummies[0]
	var ctx := Combat.instance.make_ctx(p, sk)
	for st in setup.get("target_status", []):
		target.status.apply(str(st), 6.0, 5.0, ctx)
	for st2 in setup.get("self_status", []):
		p.status.apply(str(st2), 6.0, 1.0, Combat.instance.env_ctx(1.0))
	# Status stats land on the next physics frame; the cast below reads them now.
	p.recompute_stats()
	target.recompute_stats()
	if setup.has("target_hp"):
		target.health.hp = target.health.max_hp * float(setup.target_hp)
	if setup.has("self_hp"):
		p.health.hp = p.health.max_hp * float(setup.self_hp)
	if setup.get("threat", false):
		for d in dummies:
			d.add_threat(p, 500.0)
	if setup.get("target_casting", false):
		target.casting = {"skill": "cultist_bolt", "aim": p.global_position, "left": 5.0, "extra": {}}
	if setup.has("self_cooldown"):
		p.cooldowns[str(setup.self_cooldown)] = 30.0
	if setup.has("target_absorb"):
		target.health.absorb = float(setup.target_absorb)
		target.health.absorb_time = 99.0
	if setup.has("self_torch"):
		p.torch_left = float(setup.self_torch)
	var proj_id := -1
	if setup.get("hostile_projectile", false):
		var mctx := Combat.instance.make_ctx(target, GameData.skill("skeleton_arrow"))
		proj_id = Combat.instance.spawn_projectile({"speed": 1.0, "range": 400, "damage": {"base": 1, "coef": 0}}, mctx, target.global_position - Vector2(30, 0), Vector2.LEFT)
	if setup.has("target_attacks"):
		var tctx := Combat.instance.make_ctx(target, {"id": "test_attack", "school": "melee"})
		var at_delay := 0.4 if setup.target_attacks is bool else float(setup.target_attacks)
		da.get_tree().create_timer(at_delay).timeout.connect(func():
			tctx.melee_hit = true
			tctx.cannot_miss = true
			Combat.instance.deal_damage(tctx, p, 10.0))
	var before := _snapshot()
	var aim: Vector2 = target.global_position
	match str(t.get("aim", "target")):
		"self":
			aim = p.global_position
		"ally":
			aim = ally.global_position
		"far":
			aim = dummies[2].global_position
	p.aim_pos = aim
	p.auto_aim = aim
	var err := Combat.instance.try_use_skill(p, sid, aim)
	da.check(err.is_empty(), "%s cast%s" % [sid, "" if err.is_empty() else " refused: " + err])
	if not err.is_empty():
		return
	if sk.has("charge_time"):
		await da._wait(float(sk.charge_time) + 0.05)
		Combat.instance.release_charge(p, aim)
	var wait := float(t.get("wait", 0.0))
	if wait <= 0.0:
		wait = 0.8 + float(sk.get("cast_time", 0.0)) + float(sk.get("channel", {}).get("duration", 0.0)) + _max_delay(sk.effects)
	if "recast" in t.get("expect", []):
		await da._wait(0.3)
		var err2 := Combat.instance.try_use_skill(p, sid, aim)
		da.check(err2.is_empty(), "%s second charge cast%s" % [sid, "" if err2.is_empty() else ": " + err2])
	if t.has("then"):
		# The skill lands on its animation's impact frame (#19).
		await da._wait(0.2 + CharacterSprite.impact_time(CharacterSprite.body_key(p.gender), Combat.anim_for(p, sk)))
		await _trigger(str(t.then))
	await da._wait(wait)
	var after := _snapshot()
	var expects: Array = t.get("expect", [])
	if expects.is_empty():
		if _class_run:
			da.check(false, "%s has a test block with expectations" % sid)
		da.check(_changed(before, after), "%s had an effect" % sid)
	for ex in expects:
		da.check(_expect(str(ex), before, after, target, proj_id), "%s: %s" % [sid, ex])


## Anything a skill can visibly do (resources and cooldowns of the caster don't count).
func _changed(b: Dictionary, a: Dictionary) -> bool:
	for k in b:
		if k == "p_hp":
			if a.p_hp > b.p_hp + p.health.max_hp * 0.06:
				return true
			continue
		if k.ends_with("_pos"):
			if a[k].distance_to(b[k]) > 6.0:
				return true
			continue
		if a[k] != b[k]:
			return true
	return false


func _expect(ex: String, b: Dictionary, a: Dictionary, target: Enemy, proj_id: int) -> bool:
	var arg := ex.get_slice(":", 1)
	match ex.get_slice(":", 0):
		"target_damaged":
			return a.d0_hp < b.d0_hp
		"any_target_damaged":
			return a.d0_hp < b.d0_hp or a.d1_hp < b.d1_hp or a.d2_hp < b.d2_hp
		"any_enemy_damaged":
			return a.d0_hp < b.d0_hp or a.d1_hp < b.d1_hp or a.d2_hp < b.d2_hp or a.warded_hp < b.warded_hp
		"two_targets_damaged":
			return [a.d0_hp < b.d0_hp, a.d1_hp < b.d1_hp, a.d2_hp < b.d2_hp, a.warded_hp < b.warded_hp].count(true) >= 2
		"target_charmed":
			return target.team == Actor.Team.PLAYERS or target.status.has_flag("charmed")
		"all_targets_damaged":
			return a.d0_hp < b.d0_hp and a.d1_hp < b.d1_hp and a.d2_hp < b.d2_hp
		"target_status":
			return target.status.has(arg) or Array(a.d0_status).has(arg) or _had_status(target, arg)
		"target_lost":
			return not target.status.has(arg)
		"self_status":
			return p.status.has(arg) or _had_status(p, arg)
		"self_healed":
			return a.p_hp > b.p_hp + 0.5  # a 1% heal of a level 1 hero is about 1.4
		"self_alive":
			return p.is_alive() and p.life_state == Player.Life.ALIVE
		"ally_healed":
			return a.ally_hp > b.ally_hp + 1.0
		"ally_status":
			return ally.status.has(arg) or _had_status(ally, arg)
		"ally_moved":
			return a.ally_pos.distance_to(b.ally_pos) > 12.0
		"ally_absorb":
			return a.ally_absorb > b.ally_absorb
		"target_dead":
			return not is_instance_valid(target) or not target.is_alive()
		"self_lost":
			return not p.status.has(arg)
		"self_resource_gain":
			return float(a.get("p_res", 0.0)) - float(b.get("p_res", 0.0)) >= float(arg) - 0.01
		"all_targets_status":
			return dummies.all(func(d): return d.status.has(arg) or _had_status(d, arg))
		"other_target_status":
			return dummies.slice(1).any(func(d): return d.status.has(arg) or _had_status(d, arg))
		"ally_status":
			return ally.status.has(arg) or _had_status(ally, arg)
		"dodge_ready":
			return p._dodge_cd_host <= 0.0
		"cooldown_reduced":
			return float(p.cooldowns.get(arg, 0.0)) < 29.0
		"spawned_status":
			return _spawned_seen.has(arg)
		"torch_kept":
			return p.torch_left > 0.0
		"target_absorb_gone":
			return target.health.absorb <= 0.0
		"caster_moved":
			return a.p_pos.distance_to(b.p_pos) > 12.0
		"target_moved":
			return a.d0_pos.distance_to(b.d0_pos) > 8.0
		"zone":
			return int(a.next_id) > int(b.next_id)
		"obstacle":
			return int(a.obstacles) > int(b.obstacles) or int(a.next_id) > int(b.next_id) and not g.dungeon.obstacles.is_empty()
		"tether":
			return int(a.next_id) > int(b.next_id)
		"projectiles_destroyed":
			return proj_id >= 0 and not Combat.instance.projectiles.has(proj_id)
		"threat_dropped":
			for d in dummies:
				if d.threat and d.threat.value_of(p) > 1.0:
					return false
			return true
		"target_interrupted":
			return target.casting.is_empty()
		"cooldown_reset":
			return p.cooldown_left(arg) <= 0.0
		"self_hp_lower":
			return a.p_hp < b.p_hp
		"minion":
			return int(a.minions) > int(b.minions)
		"recast":
			return true
		"warded_takes_half":
			var dd: float = b.d0_hp - a.d0_hp
			var dw: float = b.warded_hp - a.warded_hp
			if not (dd > 0.0 and absf(dw - dd * 0.5) <= 1.5):
				print("[test] warded check: dummy took %.1f, warded took %.1f" % [dd, dw])
			return dd > 0.0 and absf(dw - dd * 0.5) <= 1.5
		"warded_resists":
			# #22: an immune type deals combat.immunity_reduction less, never nothing.
			var d0: float = b.d0_hp - a.d0_hp
			var dr: float = b.warded_hp - a.warded_hp
			var want := d0 * (1.0 - float(GameData.bal("combat.immunity_reduction", 0.8)))
			if not (dr > 0.0 and absf(dr - want) <= maxf(1.5, want * 0.25)):
				print("[test] warded immunity check: dummy took %.1f, warded took %.1f (want %.1f)" % [d0, dr, want])
			return dr > 0.0 and absf(dr - want) <= maxf(1.5, want * 0.25)
	push_error("SkillSuite: unknown expectation '%s'" % ex)
	return false


## Statuses can end before the snapshot (short CC); the harness records applications.
func _had_status(a: Actor, id: String) -> bool:
	return Array(a.get_meta("test_seen_status", [])).has(id)


func _max_delay(effects: Array) -> float:
	var m := 0.0
	for e in effects:
		m = maxf(m, float(e.get("delay", 0.0)) + _max_delay(e.get("effects", [])))
	return m


# =========================================================================================
# LAN pair (host + priest client): a channel started and released by the client's real input,
# and an ally skill from the client landing on the host's hero.
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
	var start: Vector2 = g.layout.start
	p.host_teleport(start)
	c.host_teleport(g.nearest_floor(start + Vector2(-60, 0)))
	var d: Enemy = g.spawn_monster("training_dummy", g.nearest_floor(start + Vector2(60, 0)), false)
	for pl in [p, c]:
		pl.iframe_left = 9999.0
	# The client learns Penance and slots it on 1, Flash Heal on 2.
	var t := c.talents.duplicate()
	t["p_s_penance"] = 1
	c.talents = t
	c.recompute_stats()
	var lo: Array = c.skills.duplicate()
	lo[1] = "priest_penance"
	lo[2] = "priest_heal"
	if lo.count("priest_penance") > 1 or lo.count("priest_heal") > 1:
		lo = ["priest_smite", "priest_penance", "priest_heal", "priest_holy_shield", "priest_consecration", "priest_rebuke"]
	c.resource._since_combat = 99.0
	c.skills = lo
	await da._wait(0.6)
	da.check(str(c.skills[1]) == "priest_penance", "client has Penance on slot 1")
	var hp0 := d.health.hp
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_channel", d.global_position])
	var started: bool = await da._wait_until(func(): return not c.channel.is_empty(), 3.0)
	da.check(started, "the client's held key starts the channel on the host")
	var stopped: bool = await da._wait_until(func(): return c.channel.is_empty(), 3.0)
	await da._wait(0.2)
	da.check(stopped and d.health.hp < hp0, "releasing the key stops the channel early (dummy took %d)" % roundi(hp0 - d.health.hp))
	p.health.hp = p.health.max_hp * 0.4
	var php := p.health.hp
	c.cooldowns.clear()
	c.resource.value = c.resource.max_value
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_heal_host", p.global_position])
	await da._wait(1.5)
	da.check(p.health.hp > php + 1.0, "the client's Flash Heal aimed at the host heals the host (%d -> %d)" % [php, p.health.hp])
	await lan_interrupt(c, d)
	await lan_charge(c, d)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


## #26 over LAN: the client holds its primary (a melee swing with a pending impact) and taps
## Flash Heal mid-swing; the host starts the heal as soon as the press arrives, cutting the swing.
func lan_interrupt(c: Player, d: Enemy) -> void:
	await da._wait(1.0)
	c.cooldowns.clear()
	c.resource.value = c.resource.max_value
	c.host_teleport(g.nearest_floor(d.global_position + Vector2(-30, 0)))
	await da._wait(0.3)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_hold_attack", d.global_position])
	var swinging: bool = await da._wait_until(func(): return c.impact_pending.get("primary", false), 3.0)
	var key := "%s:%s" % [c.name, "priest_heal"]
	var uses0 := int(Combat.instance.get_meta("uses", {}).get(key, 0))
	var cut0 := int(Combat.instance.get_meta("swings_cut", 0))
	var t0 := Time.get_ticks_msec()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_tap_2", p.global_position])
	var started: bool = await da._wait_until(func(): return int(Combat.instance.get_meta("uses", {}).get(key, 0)) > uses0, 2.0)
	var ms := Time.get_ticks_msec() - t0
	var cut: bool = int(Combat.instance.get_meta("swings_cut", 0)) > cut0 and c.impact_pending.is_empty() and str(c.casting.get("skill", "")) == "priest_heal"
	# Round trip on localhost is a few frames; the swing alone would hold it for its impact delay.
	da.check(swinging and started and cut and ms < 250, "the client's heal pressed mid-swing starts at once on the host (%d ms, swing cut %s)" % [ms, cut])
	await da._wait(1.2)


## #54 over LAN: the client holds Power Shot (slot 3). While it charges on the host no mana is spent
## and no cooldown runs; the release fires it and only then pays and starts the cooldown. A
## release the client can no longer pay for and a charge broken by a stun spend nothing, and the
## client is told why.
func lan_charge(c: Player, d: Enemy) -> void:
	var sid := "ranger_power_shot"
	var lo: Array = c.skills.duplicate()
	lo[3] = sid
	c.skills = lo
	c.cooldowns.clear()
	c.resource.value = c.resource.max_value
	c.host_teleport(g.nearest_floor(d.global_position + Vector2(-90, 0)))
	await da._wait(1.0)
	var cost := c.stats.cost_for(GameData.skill(sid))
	var key := "%s:%s" % [c.name, sid]
	# Paid on release.
	var m0 := c.resource.value
	var hp0 := d.health.hp
	var uses0 := int(Combat.instance.get_meta("uses", {}).get(key, 0))
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_charge", [d.global_position, 1.2, ""]])
	var held: bool = await da._wait_until(func(): return not c.charging.is_empty(), 3.0)
	await da._wait(0.5)
	da.check(held and c.resource.value >= m0 - 0.01 and c.cooldown_left(sid) <= 0.0,
			"LAN: while the client holds Power Shot no mana is spent and no cooldown runs (%.1f / %.1f)" % [c.resource.value, m0])
	await da._wait_until(func(): return c.charging.is_empty(), 3.0)
	await da._wait(0.4)
	da.check(c.cooldown_left(sid) > 0.0 and c.resource.value <= m0 - cost + 0.5 and d.health.hp < hp0
			and int(Combat.instance.get_meta("uses", {}).get(key, 0)) == uses0 + 1,
			"LAN: the release fires Power Shot, then spends %d mana and starts the cooldown (%.1f -> %.1f)" % [cost, m0, c.resource.value])
	await da._wait(0.8)
	# Too little mana on release.
	c.cooldowns.clear()
	c.resource.value = c.resource.max_value
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_charge", [d.global_position, 1.2, "Charge cancelled: not enough Mana"]])
	var held2: bool = await da._wait_until(func(): return not c.charging.is_empty(), 3.0)
	da.check(held2, "LAN: the client charges Power Shot again")
	c.resource.value = cost * 0.5
	var m1 := c.resource.value
	await da._wait_until(func(): return c.charging.is_empty(), 3.0)
	await da._wait(0.3)
	da.check(c.cooldown_left(sid) <= 0.0 and c.resource.value >= m1 - 0.01, "LAN: a release without enough mana spends nothing (%.1f -> %.1f)" % [m1, c.resource.value])
	await da._wait(1.0)
	# Interrupted by a stun.
	c.resource.value = c.resource.max_value
	var m2 := c.resource.value
	NetworkManager.to_clients("DevAuto", "client_cmd", ["sk_charge", [d.global_position, 1.4, "Charge interrupted"]])
	var held3: bool = await da._wait_until(func(): return not c.charging.is_empty(), 3.0)
	da.check(held3, "LAN: the client charges Power Shot a third time")
	await da._wait(0.3)
	c.status.apply("stun", 0.5, 0.0, null)
	await da._wait(0.3)
	da.check(c.charging.is_empty() and c.cooldown_left(sid) <= 0.0 and c.resource.value >= m2 - 0.01, "LAN: a stunned charge spends nothing")
	await da._wait(1.5)


func client_cmd(cmd: String, arg: Variant) -> void:
	p = da._local()
	match cmd:
		"sk_charge":
			# Hold skill 3 for arg[1] s at arg[0]; arg[2]: the message expected when it is cancelled.
			p.auto_aim = arg[0]
			p.local_cd.clear()  # the host cleared the cooldown for the test
			var got: Array = []
			var cb := func(t: String, _col: Color): got.append(t)
			EventBus.hud_message.connect(cb)
			Input.action_press("skill_3")
			await da._wait(0.5)
			var charging := p.charge_slot == 3 and p.charge_frac(3) > 0.0 and not p.local_cd.has(3)
			await da._wait(float(arg[1]) - 0.5)
			Input.action_release("skill_3")
			await da._wait(0.6)
			EventBus.hud_message.disconnect(cb)
			p.auto_aim = Vector2.INF
			if str(arg[2]).is_empty():
				da.check(charging, "client: holding Power Shot shows the charge with no cooldown sweep")
				da.check(p.local_cd.has(3) and p.charge_slot == -1, "client: the cooldown sweep starts when Power Shot fires")
			else:
				da.check(got.has(Loc.t(str(arg[2]))) and not p.local_cd.has(3) and p.charge_slot == -1,
						"client: the cancelled charge says '%s' and starts no cooldown (%s)" % [arg[2], got])
		"sk_hold_attack":
			p.auto_aim = arg
			Input.action_press("attack")
			await da._wait(1.2)
			Input.action_release("attack")
		"sk_tap_2":
			p.auto_aim = arg
			var f0 := Engine.get_process_frames()
			Input.action_press("skill_2")
			await da._wait(0.12)
			Input.action_release("skill_2")
			da.log_line("skill_2 tapped at frame %d" % f0)
		"sk_channel":
			p.auto_aim = arg
			Input.action_press("skill_1")
			await da._wait(0.9)
			Input.action_release("skill_1")
		"sk_heal_host":
			p.auto_aim = arg
			Input.action_press("skill_2")
			await da._wait(0.15)
			Input.action_release("skill_2")
