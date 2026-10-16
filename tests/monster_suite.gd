class_name MonsterSuite
extends RefCounted
## Headless monster checks (scenario "monsters", solo host): every monster definition (minus
## test-only ones) is spawned next to an invulnerable hero; it must use its abilities, and each
## of its behaviour modules runs its own test_trigger / test_check. --biome=<id> limits the run
## to one biome's monsters.

var da: Node
var g: Node
var p: Player
var start := Vector2.ZERO


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run(biome: String = "") -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.4)
	start = g.layout.start
	var ids: Array = GameData.monsters.keys()
	ids.sort()
	var n := 0
	for id in ids:
		var def: Dictionary = GameData.monsters[id]
		if def.get("test_only", false) or (def.ai.get("abilities", []).is_empty() and def.get("behaviors", []).is_empty()):
			continue
		if not biome.is_empty() and str(def.get("biome", "")) != biome:
			continue
		n += 1
		await check_monster(str(id))
	da.check(n > 0, "monster suite ran %d monsters" % n)
	await check_lunges(biome)
	if biome.is_empty() or biome == "crypt":
		await check_shriek_keeps_torch()


## The banshee's shriek silences the hero and snuffs wall torches, but the carried torch only
## ever burns out (#3).
func check_shriek_keeps_torch() -> void:
	_keep_hero()
	p.host_teleport(start)
	p.torch_left = 60.0
	var e: Enemy = g.spawn_monster("banshee", g.nearest_floor(start + Vector2(90, 0)), false)
	await da._wait(0.3)
	e.behaviors = []
	e.add_threat(p, 10.0)
	p.iframe_left = 0.0  # the shriek must really land
	p.set_meta("test_seen_status", [])
	# Its own AI may already have shrieked ("Not ready" / "Busy"); either way the hero is hit.
	var err := Combat.instance.try_use_skill(e, "banshee_shriek", p.global_position)
	await da._wait(float(GameData.skill("banshee_shriek").get("cast_time", 0.0)) + 0.4)
	var hit: bool = p.status.has("silence") or Array(p.get_meta("test_seen_status", [])).has("silence")
	da.check(hit and p.torch_left > 50.0 and p.torch_sync > 0,
			"a hero hit by the banshee's shriek keeps the carried torch (%s, silenced %s, %.0f s left)" % [err, hit, p.torch_left])
	if is_instance_valid(e):
		e.queue_free()
	p.remove_meta("test_seen_status")
	_keep_hero()
	await da._wait(0.2)


## Leaps and charges (#2): refused in the grace after spotting a hero, then a wind-up of at
## least 0.8 s with a cast bar and a ground marker before the monster moves; one hit (even a
## crit, without the floor-1 easing) never kills a fresh level 1 hero of any class.
func check_lunges(biome: String) -> void:
	var lunges := {"ghoul": "ghoul_pounce", "brimstone_hound": "hound_leap", "archive_gargoyle": "gargoyle_dive",
		"dread_wight": "wight_shield_charge", "echo_unwritten": "echo_charge"}
	var min_hp := INF
	for cid in GameData.classes:
		p.stats.compute_player(GameData.classes[cid], 1, {}, {}, {}, {"allocated": {}, "run_mods": [], "mods": [], "skill_mods": []})
		min_hp = minf(min_hp, p.stats.get_stat("max_hp"))
	p.recompute_stats()
	var keep_depth: int = g.depth
	g.depth = 1
	var early: Array = GameData.bal("scaling.early_depths", [])
	var ease := float(early[0].get("damage", 1.0)) if not early.is_empty() else 1.0
	for id in lunges:
		if not biome.is_empty() and str(GameData.monsters[id].get("biome", "")) != biome:
			continue
		var sid: String = lunges[id]
		var sk := GameData.skill(sid)
		_keep_hero()
		p.host_teleport(start)
		var e: Enemy = g.spawn_monster(id, g.nearest_floor(start + Vector2(150, 0)), false)
		await da._wait(0.3)
		if not is_instance_valid(e):
			da.check(false, "%s spawned" % id)
			continue
		e.behaviors = []
		e.behavior_state = ""
		e._abilities = []
		e.add_threat(p, 10.0)
		var err := Combat.instance.try_use_skill(e, sid, p.global_position)
		da.check(not err.is_empty(), "%s: no %s right after spotting the hero (%s)" % [id, sid, err])
		e._aggro_since -= float(GameData.bal("ai.lunge_grace")) + 0.1
		e.cooldowns.erase(sid)
		var markers := int(Combat.instance.fx.get_meta("windup_markers", 0))
		var from := e.global_position
		err = Combat.instance.try_use_skill(e, sid, p.global_position)
		da.check(err.is_empty() and float(e.casting.get("left", 0.0)) >= 0.8 and float(sk.get("windup", 0.0)) >= 0.8,
				"%s: %s winds up for %.2f s (%s)" % [id, sid, float(e.casting.get("left", 0.0)), err])
		da.check(int(Combat.instance.fx.get_meta("windup_markers", 0)) == markers + 1 and e.has_meta("cast_end"),
				"%s: the wind-up shows a cast bar and a ground marker" % id)
		await da._wait(0.6)
		da.check(is_instance_valid(e) and e.global_position.distance_to(from) < 6.0, "%s: no movement during the wind-up" % id)
		await da._wait(float(sk.windup) + 0.4)
		da.check(is_instance_valid(e) and e.global_position.distance_to(from) > 20.0, "%s: the %s lands after the wind-up" % [id, sid])
		if is_instance_valid(e):
			var spec: Variant = _lunge_damage(sk)
			var ctx: Dictionary = Combat.instance.make_ctx(e, sk)
			var worst: float = Combat.instance.damage_value(spec, ctx, p) / ease * (1.0 + float(ctx.crit_damage))
			da.check(worst < min_hp, "%s: a level 1 hero survives a %s crit (%.0f < %.0f HP)" % [id, sid, worst, min_hp])
			e.queue_free()
		await da._wait(0.2)
	g.depth = keep_depth


func _lunge_damage(sk: Dictionary) -> Variant:
	for eff in sk.effects:
		if eff.has("path_damage"):
			return eff.path_damage
		for sub in eff.get("on_arrive", []):
			if sub.has("damage"):
				return sub.damage
	return {"base": 0, "coef": 0}


func check_monster(id: String) -> void:
	var def: Dictionary = GameData.monsters[id]
	_keep_hero()
	p.host_teleport(start)
	var e: Enemy = g.spawn_monster(id, g.nearest_floor(start + Vector2(80, 0)), false)
	await da._wait(0.3)
	if not is_instance_valid(e):
		da.check(false, "%s spawned" % id)
		return
	e.add_threat(p, 10.0)
	var abilities: Array = def.ai.get("abilities", [])
	var used := abilities.is_empty()
	var t := 0.0
	while t < 8.0 and not used and is_instance_valid(e):
		_keep_hero()
		var uses: Dictionary = Combat.instance.get_meta("uses", {})
		for sid in abilities:
			if uses.has("%s:%s" % [e.name, sid]):
				used = true
		await da._wait(0.25)
		t += 0.25
	# Ambushers (mimics, perched gargoyles, ink pools) only strike once their behaviour springs:
	# their ability check waits until the behaviour tests below have run.
	if used:
		da.check(used, "%s used one of its abilities" % id)
	if is_instance_valid(e):
		for b in e.behaviors:
			await b.test_trigger(self)
			var bt := 0.0
			var err := "not checked"
			while bt < float(b.params.get("test_wait", 4.0)):
				_keep_hero()
				err = b.test_check(self)
				if err.is_empty():
					break
				await da._wait(0.25)
				bt += 0.25
			da.check(err.is_empty(), "%s behaviour %s%s" % [id, b.params.get("id", "?"), "" if err.is_empty() else ": " + err])
	if not used:
		var t2 := 0.0
		while t2 < 6.0 and not used:
			_keep_hero()
			var uses2: Dictionary = Combat.instance.get_meta("uses", {})
			for sid in abilities:
				if uses2.has("%s:%s" % [e.name if is_instance_valid(e) else "", sid]):
					used = true
			await da._wait(0.25)
			t2 += 0.25
		da.check(used, "%s used one of its abilities" % id)
	for m in g.enemies_root.get_children():
		m.queue_free()
	Combat.instance.clear_floor()
	await da._wait(0.3)


func _keep_hero() -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.iframe_left = 9999.0
	p.health.hp = p.health.max_hp
	p.status.clear_all()
