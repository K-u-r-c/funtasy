class_name TuningSuite
extends RefCounted
## Tenth playtest tuning (scenario "tuning", solo mage): #103 leech heals half its rating, #104
## Fireball's 5 s cooldown, #109 ground-targeted skills stop at walls and closed doors.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func dummy(at: Vector2, extra: Dictionary = {}) -> Enemy:
	var d: Enemy = g.spawn_monster("training_dummy", at, false, extra)
	return d


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var start: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(start)
	await run_leech(start)
	await run_fireball(start)
	await run_walls()


## #103: a leech hit heals damage x Leech x combat.leech_efficiency (0.5, data), per hit and per
## AoE target; the panels and the skill tooltip show that share; monsters' leech and the party
## leech oil keep their numbers.
func run_leech(start: Vector2) -> void:
	var coef := float(GameData.bal("combat.leech_efficiency", 1.0))
	da.check(is_equal_approx(coef, 0.5), "heroes' leech heals half its rating (combat.leech_efficiency %.2f in data)" % coef)
	var dummies: Array = []
	for i in 3:
		dummies.append(dummy(g.nearest_floor(start + Vector2(50, -30 + i * 30))))
	await da._wait(0.5)
	p.run_mods = [{"stat": "leech", "value": 0.1, "source": "t"}]
	p.recompute_stats()
	var raw := p.stats.get_stat("leech")
	var ctx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	ctx.cannot_miss = true
	ctx.crit_chance = 0.0
	# One hit.
	p.health.hp = p.health.max_hp * 0.3
	var before := p.health.hp
	var dealt := Combat.instance.deal_damage(ctx, dummies[0], 40.0)
	var healed := p.health.hp - before
	var want := dealt * raw * coef
	da.check(dealt > 0.0 and absf(healed - want) < 0.6, "a hit with %d%% leech heals %.1f of %.1f damage (want %.1f, half of the old %.1f)" % [
		roundi(raw * 100.0), healed, dealt, want, dealt * raw])
	# An area hits every dummy: each target heals its own half share.
	p.health.hp = p.health.max_hp * 0.3
	before = p.health.hp
	var hp0 := 0.0
	for d in dummies:
		hp0 += d.health.hp
	var aoe_ctx := Combat.instance.make_ctx(p, {"id": "test_aoe", "school": "spell"})
	aoe_ctx.cannot_miss = true
	aoe_ctx.crit_chance = 0.0
	Combat.instance.apply_aoe({"type": "aoe", "radius": 120, "damage": {"base": 30, "coef": 0.0}}, aoe_ctx, start + Vector2(50, 0))
	var hp1 := 0.0
	for d in dummies:
		hp1 += d.health.hp
	healed = p.health.hp - before
	want = (hp0 - hp1) * raw * coef
	da.check(hp0 - hp1 > 0.0 and absf(healed - want) < 1.0, "an area's leech heals half per target hit (%.1f of %.1f, want %.1f)" % [healed, hp0 - hp1, want])
	# The coefficient is read from data.
	var combat_bal: Dictionary = GameData.balance.combat
	combat_bal.leech_efficiency = 1.0
	p.health.hp = p.health.max_hp * 0.3
	before = p.health.hp
	dealt = Combat.instance.deal_damage(ctx, dummies[0], 40.0)
	healed = p.health.hp - before
	combat_bal.leech_efficiency = coef
	da.check(absf(healed - dealt * raw) < 0.6, "the leech share follows the data coefficient (x1.0 heals %.1f of %.1f)" % [healed, dealt])
	# What the hero reads: the stat panels and the skill tooltip show the healed share.
	var shown := Combat.leech_share(float(p.stats.final.get("leech", 0.0)), float(p.stats.final.get("leech_efficiency_mult", 1.0)), true)
	da.check(is_equal_approx(shown, raw * coef), "the Leech rows show the share that heals (%.3f)" % shown)
	var rows := SkillInfo.rows(p, GameData.skill(str(p.class_def.primary_attack)))
	var tip := ""
	for r in rows:
		if str(r.k) == Loc.t("Leech"):
			tip = str(r.v)
	da.check(tip.begins_with("%d%%" % roundi(raw * coef * 100.0)), "the skill tooltip's leech line shows the healed share (%s)" % tip)
	# Monsters' leech (a Vampiric elite) is unscaled.
	var vamp := dummy(g.nearest_floor(start + Vector2(-60, 0)), {"elite": ["vampiric"]})
	await da._wait(0.3)
	vamp.set_process(false)
	vamp.set_physics_process(false)
	var vctx := Combat.instance.make_ctx(vamp, {"id": "test_bite", "school": "physical"})
	vctx.cannot_miss = true
	vctx.crit_chance = 0.0
	vamp.health.hp = vamp.health.max_hp * 0.5
	var vb := vamp.health.hp
	p.health.hp = p.health.max_hp
	var vd := Combat.instance.deal_damage(vctx, dummies[1], 30.0)
	var vh := vamp.health.hp - vb
	da.check(vd > 0.0 and absf(vh - vd * float(vctx.leech)) < 0.6, "a Vampiric elite's leech keeps its full share (%.1f of %.1f)" % [vh, vd])
	# The party leech oil (out of scope) keeps its 20%.
	p.run_mods = []
	p.recompute_stats()
	var octx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	octx.cannot_miss = true
	octx.crit_chance = 0.0
	p.status.apply("pact_leech_oil", 10.0, 0.0, octx)
	p.health.hp = p.health.max_hp * 0.3
	before = p.health.hp
	dealt = Combat.instance.deal_damage(octx, dummies[2], 40.0)
	healed = p.health.hp - before
	p.status.remove("pact_leech_oil")
	da.check(absf(healed - dealt * float(GameData.bal("combat.party_leech", 0.2))) < 0.6, "Unholy Leech Oil still heals 20%% of the party's damage (%.1f of %.1f)" % [healed, dealt])
	for d in dummies + [vamp]:
		if is_instance_valid(d):
			d.queue_free()
	p.health.hp = p.health.max_hp


## #104: Fireball's cooldown is 5 s in data and a real cast waits that long (less haste); Ash
## Harvest's reset is checked by the boon tests (`boons-mage`).
func run_fireball(start: Vector2) -> void:
	var sk := GameData.skill("mage_fireball")
	da.check(is_equal_approx(float(sk.get("cooldown", 0.0)), 5.0), "Fireball's cooldown is 5 s in data (%.1f)" % float(sk.get("cooldown", 0.0)))
	p.host_teleport(start)
	p.cooldowns.clear()
	p.resource.value = p.resource.max_value
	await da._wait(0.2)
	var err := Combat.instance.try_use_skill(p, "mage_fireball", start + Vector2(120, 0))
	await da._wait(0.1)
	var left := p.cooldown_left("mage_fireball")
	var want := p.stats.cooldown_for(sk)
	da.check(err.is_empty() and want > 4.0 and absf(left - want) < 0.3, "a real Fireball goes on a ~5 s cooldown (%.2f s left, %.2f s with haste)%s" % [left, want, "" if err.is_empty() else ": " + err])


## Two floor points on either side of an ordinary door, along its normal: [door, a, b] or [].
func _door_sides() -> Array:
	for d in g.dungeon.doors:
		if d.sealed or not str(d.kind).is_empty() or d.floodgate or d.locked:
			continue
		var c: Vector2 = Rect2(d.world_rect).get_center()
		var n := Vector2(1, 0) if d.vertical else Vector2(0, 1)
		for off in [56.0, 72.0, 44.0]:
			var a: Vector2 = c - n * off
			var b: Vector2 = c + n * off
			if DungeonGenerator.walkable(g.dungeon.cell_at(g.dungeon.cell_of(a))) and DungeonGenerator.walkable(g.dungeon.cell_at(g.dungeon.cell_of(b))):
				return [d, a, b]
	return []


func _newest_zone() -> Dictionary:
	var best := -1
	for id in Combat.instance.zones:
		best = maxi(best, int(id))
	return Combat.instance.zones.get(best, {})


## #109: aimed through a closed door, Meteor Strike, an area, a zone and a trap land on the
## caster's side and spare the dummy beyond it; through the open door they hit; a prop in the way
## moves nothing; a monster's area can't reach a hero through the door; the aim preview shows the
## clamped point.
func run_walls() -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var sides := _door_sides()
	da.check(not sides.is_empty(), "an ordinary door with floor on both sides")
	if sides.is_empty():
		return
	var door: Node = sides[0]
	var a: Vector2 = sides[1]
	var b: Vector2 = sides[2]
	var mid: Vector2 = Rect2(door.world_rect).get_center()
	var n: Vector2 = (b - a).normalized()
	p.iframe_left = 9999.0
	p.host_teleport(a)
	door.host_set_open(false)
	await da._wait(0.5)
	var dm := dummy(b)
	await da._wait(0.4)
	dm.set_physics_process(false)
	dm.status.clear_all()
	var hp0: float = dm.health.hp
	var ctx := Combat.instance.make_ctx(p, {"id": "test_ground", "school": "spell", "damage_type": "fire"})
	ctx.cannot_miss = true
	var boom := {"type": "aoe", "at": "aim", "max_range": 300, "radius": 90, "damage": {"base": 30, "coef": 0.0}, "damage_type": "fire"}
	var at := Combat.instance.clamp_reachable(a, b, 300.0)
	da.check((at - mid).dot(n) < 0.0, "an area aimed through a closed door lands on the caster's side (%.0f px short of the door)" % -(at - mid).dot(n))
	Combat.instance.run_effect(boom, ctx, a, b)
	var zone := {"type": "zone", "at": "aim", "max_range": 300, "radius": 90, "duration": 1.0, "tick": 0.25, "damage": {"base": 10, "coef": 0.0}}
	Combat.instance.run_effect(zone, ctx, a, b)
	var zpos: Vector2 = _newest_zone().get("pos", b)
	var trap := {"type": "trap", "at": "aim", "max_range": 300, "trigger_radius": 30, "duration": 1.0, "damage": {"base": 10, "coef": 0.0}}
	Combat.instance.run_effect(trap, ctx, a, b)
	var tpos: Vector2 = _newest_zone().get("pos", b)
	p.talents["m_s_meteor"] = 1
	p.cooldowns.erase("mage_meteor")
	p.resource.value = p.resource.max_value
	var err := Combat.instance.try_use_skill(p, "mage_meteor", b)
	await da._wait(2.4)
	da.check((zpos - mid).dot(n) < 0.0 and (tpos - mid).dot(n) < 0.0, "a zone and a trap aimed through a closed door are put down on the caster's side")
	da.check(err.is_empty() and is_equal_approx(dm.health.hp, hp0), "Meteor Strike, an area and a zone aimed into the next room spare the monster behind the closed door (%d -> %d)%s" % [hp0, dm.health.hp, "" if err.is_empty() else " (" + err + ")"])
	# The same through the open door: hit.
	door.host_set_open(true)
	await da._wait(0.4)
	Combat.instance.run_effect(boom, ctx, a, b)
	await da._wait(0.2)
	da.check(dm.health.hp < hp0, "through the open door the area hits (%d -> %d)" % [hp0, dm.health.hp])
	# A prop in the way moves nothing.
	var start: Vector2 = g.nearest_floor(g.layout.start)
	g.dungeon._add_prop("TestCrate109", "crate", g.nearest_floor(start + Vector2(50, 0)))
	await da._wait(0.2)
	var far: Vector2 = start + Vector2(110, 0)
	da.check(Combat.instance.clamp_reachable(start, far, 300.0).distance_to(far) < 0.5, "a prop between caster and aim doesn't move the point")
	# A monster's area can't reach a hero through the closed door.
	door.host_set_open(false)
	await da._wait(0.4)
	p.host_teleport(b)
	dm.global_position = a
	await da._wait(0.3)
	p.iframe_left = 0.0
	var php: float = p.health.hp
	var mctx := Combat.instance.make_ctx(dm, {"id": "test_monster_ground", "school": "spell"})
	mctx.cannot_miss = true
	Combat.instance.run_effect(boom, mctx, a, b)
	await da._wait(0.2)
	da.check(is_equal_approx(p.health.hp, php), "a monster's area can't hit a hero through a closed door (%d -> %d)" % [php, p.health.hp])
	p.iframe_left = 9999.0
	# The aim preview shows the clamped point.
	p.host_teleport(a)
	await da._wait(0.3)
	var keep: Array = p.skills.duplicate()
	var lo := keep.duplicate()
	lo[1] = "mage_meteor"
	p.skills = lo
	p.auto_aim = b
	await da._wait(0.1)
	var info := p.preview_info(1)
	p.auto_aim = Vector2.INF
	p.skills = keep
	da.check((Vector2(info.aim) - mid).dot(n) < 0.0, "the aim preview shows Meteor Strike landing on the caster's side of the door")
	door.host_set_open(true)
	if is_instance_valid(dm):
		dm.queue_free()

