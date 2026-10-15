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
var _start := Vector2.ZERO


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run_class(class_id: String) -> void:
	var ids: Array = []
	for sid in GameData.skills:
		if str(sid).begins_with(class_id + "_"):
			ids.append(sid)
	ids.sort()
	await _prepare()
	da.check(ids.size() >= 6, "%s has %d skills in data" % [class_id, ids.size()])
	for sid in ids:
		await cast_and_check(str(sid))


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
	await da._wait(0.6)


func _reset() -> void:
	p.casting = {}
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
	warded.host_teleport(g.nearest_floor(_start + Vector2(0, 70)))
	Combat.instance.clear_floor()
	for id in g.dungeon.obstacles.keys():
		g.dungeon.remove_obstacle(id)
	for m in g.enemies_root.get_children():
		if m.team == Actor.Team.PLAYERS:
			m.queue_free()


func _snapshot() -> Dictionary:
	var s := {"p_pos": p.global_position, "p_hp": p.health.hp, "p_absorb": p.health.absorb,
		"p_status": _ids(p), "zones": Combat.instance.zones.size(), "next_id": Combat.instance._next_id,
		"obstacles": g.dungeon.obstacles.size(), "tethers": Combat.instance.tethers.size(),
		"projectiles": Combat.instance.projectiles.size(), "minions": g.get_tree().get_nodes_in_group("minions").size(),
		"warded_hp": warded.health.hp}
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
	var proj_id := -1
	if setup.get("hostile_projectile", false):
		var mctx := Combat.instance.make_ctx(target, GameData.skill("skeleton_arrow"))
		proj_id = Combat.instance.spawn_projectile({"speed": 1.0, "range": 400, "damage": {"base": 1, "coef": 0}}, mctx, target.global_position - Vector2(30, 0), Vector2.LEFT)
	if setup.get("target_attacks", false):
		var tctx := Combat.instance.make_ctx(target, {"id": "test_attack", "school": "melee"})
		var tgt := target
		da.get_tree().create_timer(0.4).timeout.connect(func():
			tctx.melee_hit = true
			Combat.instance.deal_damage(tctx, p, 10.0))
	var before := _snapshot()
	var aim: Vector2 = target.global_position if str(t.get("aim", "target")) == "target" else p.global_position
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
	await da._wait(wait)
	var after := _snapshot()
	var expects: Array = t.get("expect", [])
	if expects.is_empty():
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
		"all_targets_damaged":
			return a.d0_hp < b.d0_hp and a.d1_hp < b.d1_hp and a.d2_hp < b.d2_hp
		"target_status":
			return target.status.has(arg) or Array(a.d0_status).has(arg) or _had_status(target, arg)
		"target_lost":
			return not target.status.has(arg)
		"self_status":
			return p.status.has(arg)
		"self_lost":
			return not p.status.has(arg)
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
			return dd > 0.0 and absf(dw - dd * 0.5) <= 1.5
		"warded_untouched":
			return is_equal_approx(float(a.warded_hp), float(b.warded_hp))
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
