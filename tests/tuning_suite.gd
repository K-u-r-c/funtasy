class_name TuningSuite
extends RefCounted
## Tenth playtest tuning (scenario "tuning", solo mage): #103 leech heals half its rating.

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
