class_name LegendarySuite
extends SkillSuite
## Headless legendary checks (scenario "legendaries", solo host, --class=<id>): every legendary
## of the class is generated at level 30, worn by the hero (stats and procs recompiled) and its
## affix proven by the item's data `test` block: a cast / trigger with expectations (the skill
## suite's triggers and checks) or a named behavioural probe ("probe": measured wearing the item
## and wearing a copy stripped of its affix).

const SLOT_OF := {"head": "head", "chest": "chest", "legs": "legs", "boots": "boots", "gloves": "gloves",
	"main_hand": "main_hand", "off_hand": "off_hand", "ring": "ring_1", "necklace": "necklace"}

## Test keys that only looked at the compiled data (a flag, a stat...) and proved nothing: an
## affix is proven by a cast / trigger spec or a behavioural probe.
const DATA_ONLY_KEYS := ["flag", "stat", "stat_below", "skill_mod", "chance_proc", "titan_grip"]

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
	_wear(item)
	var t: Dictionary = lg.get("test", {})
	if t.has("probe"):
		await _probe(id, str(t.probe), item)
	elif DATA_ONLY_KEYS.any(func(k): return t.has(k)):
		da.check(false, "%s: its test only reads data (%s); it needs a probe" % [id, t.keys()])
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


# =========================================================================================
# Behavioural probes: each measures its affix wearing the legendary and wearing a copy stripped
# of it (same stats, no mods / flags / procs), and checks it works with and not without.
# =========================================================================================


var _dark_pair: Array = []  ## [hero spot, unlit spot in its sight] (Falconer's darkvision)
var _wall_pair: Array = []  ## two floor spots close together with a wall between (Softsteps)


func _probe(id: String, probe: String, item: Dictionary) -> void:
	match probe:
		"execute_visor":
			await _probe_execute_visor(id, item)
		"cc_reduction":
			await _probe_cc_reduction(id, item)
		"berserker":
			await _probe_berserker(id, item)
		"unstoppable":
			await _probe_unstoppable(id, item)
		"titan_grip":
			await _probe_titan_grip(id, item)
		"bonecrusher":
			await _probe_bonecrusher(id, item)
		"spell_reflect":
			await _probe_spell_reflect(id, item)
		"bleed_crit":
			await _probe_bleed_crit(id, item)
		"armor_power":
			await _probe_armor_power(id, item)
		"ambush":
			await _probe_ambush(id, item)
		"falconer":
			await _probe_falconer(id, item)
		"toxic_feeder":
			await _probe_toxic_feeder(id, item)
		"trapper":
			await _probe_trapper(id, item)
		"softsteps":
			await _probe_softsteps(id, item)
		"venom_stacks":
			await _probe_venom_stacks(id, item)
		"surehand":
			await _probe_surehand(id, item)
		"bramble_root":
			await _probe_bramble_root(id, item)
		"abyss_quiver":
			await _probe_abyss_quiver(id, item)
		"apex_mark":
			await _probe_apex_mark(id, item)
		"lava_walker":
			await _probe_lava_walker(id, item)
		"deep_frost":
			await _probe_deep_frost(id, item)
		"burn_leech":
			await _probe_burn_leech(id, item)
		"primal_cinder":
			await _probe_primal_cinder(id, item)
		"echo_cast":
			await _probe_echo_cast(id, item)
		"resist_ignore":
			await _probe_resist_ignore(id, item)
		"astral_shackles":
			await _probe_astral_shackles(id, item)
		"hourglass":
			await _probe_hourglass(id, item)
		"blood_mana":
			await _probe_blood_mana(id, item)
		"crusader_ground":
			await _probe_crusader_ground(id, item)
		"slippers":
			await _probe_slippers(id, item)
		"renew_mastery":
			await _probe_renew_mastery(id, item)
		"dawn_crosier":
			await _probe_dawn_crosier(id, item)
		"black_sacrament":
			await _probe_black_sacrament(id, item)
		"endless_grace":
			await _probe_endless_grace(id, item)
		"iron_zealot":
			await _probe_iron_zealot(id, item)
		"undying_sun":
			await _probe_undying_sun(id, item)
		"goddess_tear":
			await _probe_goddess_tear(id, item)
		_:
			da.check(false, "%s: unknown probe '%s'" % [id, probe])


## The legendary without its affix: same base and stats, no mods, flags or procs (`strip_stats`:
## stat keys that are part of the affix too).
func _bare(item: Dictionary, strip_stats: Array = []) -> Dictionary:
	var b: Dictionary = item.duplicate(true)
	b.mods = []
	b.flags = []
	b.procs = []
	for k in strip_stats:
		b.stats.erase(k)
	return b


## Runs `measure` (a coroutine) wearing the item, then wearing it bare, each from a clean state
## (the hero faces right, toward the dummies). Returns [with, without].
func _ab(item: Dictionary, measure: Callable, strip_stats: Array = []) -> Array:
	var out: Array = []
	for it in [item, _bare(item, strip_stats)]:
		_wear(it)
		_reset()
		p.status._dr.clear()
		p.iframe_left = 0.0
		p.auto_aim = _start + Vector2(200, 0)
		await da._wait(0.15)
		out.append(await measure.call())
	p.auto_aim = Vector2.INF
	_wear(item)
	return out


## The hero's context for a hit with fixed numbers: no crit, never misses.
func _ctx(skill: Dictionary, caster: Actor = null) -> Dictionary:
	var c := Combat.instance.make_ctx(caster if caster else p, skill)
	c.crit_chance = 0.0
	c.cannot_miss = true
	return c


func _effect(a: Actor, sid: String) -> Dictionary:
	for e in a.status.effects:
		if e.id == sid:
			return e
	return {}


func _left(a: Actor, sid: String) -> float:
	return float(_effect(a, sid).get("remaining", 0.0))


func _cell_index(pos: Vector2) -> int:
	var c: Vector2i = g.dungeon.cell_of(pos)
	return c.y * g.dungeon.size.x + c.x


## Waits (at most `limit` s) for the hero's HP to change; returns the change.
func _hp_change(limit: float) -> float:
	var hp0 := p.health.hp
	var t := 0.0
	while t < limit and is_equal_approx(p.health.hp, hp0):
		await da.get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return p.health.hp - hp0


func _fmt(v: Variant) -> String:
	if v is float:
		return "%.2f" % v
	if v is Array:
		return "[%s]" % ", ".join(PackedStringArray(Array(v).map(func(x): return _fmt(x))))
	return str(v)


func _report(id: String, ok: bool, what: String, r: Array) -> void:
	da.check(ok, "%s: %s (with %s, without %s)" % [id, what, _fmt(r[0]), _fmt(r[1])])


# --- Warrior -----------------------------------------------------------------------------------


func _probe_execute_visor(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		var near: Vector2 = g.nearest_floor(p.global_position + Vector2(32, 0))
		d0.host_teleport(near)
		d0.health.hp = d0.health.max_hp * 0.35
		await da._wait(0.1)
		var err := Combat.instance.try_use_skill(p, "warrior_execute", d0.global_position)
		await da._wait(0.8)
		d0.host_teleport(g.nearest_floor(_start + DUMMY_OFFSETS[0] + Vector2(0, 40)))
		var gh: Enemy = g.spawn_monster("ghoul", near, false)
		await da._wait(0.2)
		gh.status.apply("stun", 5.0, 0.0, null)
		gh.health.hp = 1.0
		await da._wait(0.1)
		gh.stats.final.dodge = 0.0
		p.cooldowns.clear()
		p.resource.value = p.resource.max_value
		var err2 := Combat.instance.try_use_skill(p, "warrior_execute", gh.global_position)
		await da._wait(0.8)
		var dead := not is_instance_valid(gh) or not gh.is_alive()
		if not dead:
			gh.queue_free()
		return [err, err2, dead, p.cooldown_left("warrior_execute")])
	_report(id, str(r[0][0]).is_empty() and str(r[1][0]) == "Target health too high", "Execute reaches a target at 35% HP", r)
	_report(id, r[0][1] == "" and r[0][2] and r[1][2] and r[0][3] <= 0.0 and r[1][3] > 0.0, "a killing Execute resets its cooldown", r)


func _probe_cc_reduction(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> float:
		p.status.apply("stun", 4.0, 0.0, Combat.instance.env_ctx(0.0))
		var left := _left(p, "stun")
		p.status.remove("stun")
		return left)
	_report(id, r[1] >= 3.9 and absf(r[0] / r[1] - 0.25) < 0.02, "a 4 s stun lasts 75% shorter", r)


func _probe_berserker(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		p.health.hp = p.health.max_hp * 0.5
		var dmg := Combat.instance.deal_damage(_ctx({"id": "test_strike", "school": "melee"}), dummies[0], 1000.0)
		p.resource.value = 50.0
		p.resource._since_combat = 99.0
		await da._wait(0.6)
		return [dmg, p.resource.value])
	_report(id, r[1][0] > 0.0 and absf(r[0][0] / r[1][0] - 1.25) < 0.02, "at 50% HP a hit deals +25% damage", r)
	_report(id, r[0][1] >= 49.9 and r[1][1] < 48.0, "Fury doesn't decay out of combat", r)


func _probe_unstoppable(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var idx := _cell_index(p.global_position)
		var old: int = g.dungeon.cells[idx]
		g.dungeon.cells[idx] = DungeonGenerator.CELL_SLUDGE
		var sludge: FloorMechanic = load("res://scripts/dungeon/mechanics/sludge_drag_taint.gd").new()
		sludge.setup(g, {})
		sludge.physics(1.0)
		var slowed := p.status.has("sewage_slow")
		g.dungeon.cells[idx] = DungeonGenerator.CELL_LAVA
		var lost := -(await _hp_change(1.2))
		g.dungeon.cells[idx] = old
		p.status.clear_all()
		return [slowed, lost])
	_report(id, not r[0][0] and r[1][0], "sewer sludge doesn't slow", r)
	_report(id, r[1][1] > 0.0 and r[0][1] > 0.0 and r[0][1] <= r[1][1] * 0.3, "lava burns 80% less", r)


func _probe_titan_grip(id: String, item: Dictionary) -> void:
	var hammer := ItemGenerator.generate_equipment("warhammer", 10, 2, _rng)
	var shield := ItemGenerator.generate_equipment("shield", 10, 2, _rng)
	var r := await _ab(item, func() -> bool:
		var bp: Array = p.inv.backpack.duplicate()
		p.inv.equipment.erase("off_hand")
		p.inv.equipment["main_hand"] = hammer.duplicate(true)
		p.inv.backpack.append(shield.duplicate(true))
		var err := p.inv.equip_from_backpack(p.inv.backpack.size() - 1, 99)
		var both: bool = err.is_empty() and int(p.inv.equipment.get("main_hand", {}).get("hands", 1)) == 2 \
				and str(p.inv.equipment.get("off_hand", {}).get("base", "")) == "shield"
		p.inv.backpack = bp
		p.inv.equipment.erase("off_hand")
		return both)
	_report(id, r[0] and not r[1], "a two-handed weapon and a shield together", r)


func _probe_bonecrusher(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> int:
		var ctx := _ctx({"id": "test_strike", "school": "melee"})
		for i in 60:
			p.cooldowns["warrior_shield_bash"] = 30.0
			p.cooldowns["warrior_cleave"] = 30.0
			Combat.instance.deal_damage(ctx, dummies[0], 5.0)
			if p.cooldown_left("warrior_shield_bash") <= 0.0 or p.cooldown_left("warrior_cleave") <= 0.0:
				return i + 1
		return 0)
	_report(id, r[0] > 0 and r[1] == 0, "melee hits reset Shield Slam / Cleave (hits until a reset)", r)


func _probe_spell_reflect(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> int:
		var mctx := Combat.instance.make_ctx(dummies[0], {"id": "test_bolt", "school": "spell", "damage_type": "shadow"})
		var ids: Array = []
		for i in 20:
			ids.append(Combat.instance.spawn_projectile({"speed": 300.0, "range": 200, "radius": 4, "damage": {"base": 1, "coef": 0}},
					mctx, p.global_position + Vector2(40, 0), Vector2.LEFT))
		var seen := {}
		for f in 30:
			await da.get_tree().physics_frame
			for pid in ids:
				if Combat.instance.projectiles.has(pid) and str(Combat.instance.projectiles[pid].ctx.get("skill", "")) == "reflect":
					seen[pid] = true
		return seen.size())
	_report(id, r[0] > 0 and r[1] == 0, "hostile spell bolts at the shield come back (of 20)", r)


func _probe_bleed_crit(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> float:
		var d0: Enemy = dummies[0]
		var ctx := Combat.instance.make_ctx(p, GameData.skill("warrior_cleave"))
		ctx.crit_chance = 1.0
		ctx.crit_damage = 1.0
		Combat.instance.apply_status(ctx, d0, "bleed", 5.0, 100.0)
		var hp0 := d0.health.hp
		Combat.instance.status_tick(d0, _effect(d0, "bleed"))
		return hp0 - d0.health.hp)
	_report(id, r[1] > 0.0 and r[0] >= r[1] * 1.8, "a bleed tick crits (100% crit chance)", r)


func _probe_armor_power(id: String, item: Dictionary) -> void:
	var chest := ItemGenerator.generate_equipment("plate_chest", 30, 1, _rng)
	var r := await _ab(item, func() -> Array:
		p.inv.equipment["chest"] = chest.duplicate(true)
		p.recompute_stats()
		var ctx := _ctx(GameData.skill("warrior_cleave"))
		var dmg := Combat.instance.deal_damage(ctx, dummies[0], Combat.value_of({"base": 0, "coef": 1.0}, ctx))
		return [p.stats.get_stat("power_melee"), p.stats.get_stat("armor"), dmg])
	_report(id, r[0][1] > 20.0 and absf((r[0][0] - r[1][0]) - r[0][1] * 0.2) < 0.5 and r[0][2] > r[1][2],
			"20% of armor becomes melee power and damage (power, armor, hit)", r)


# --- Ranger ------------------------------------------------------------------------------------


func _probe_ambush(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		var armor := (float(GameData.bal("stats.armor_constant")) + float(GameData.bal("stats.armor_per_level")) * p.level) * 2.0
		var ctx := _ctx({"id": "test_shot", "school": "ranged"})
		ctx.crit_damage = 0.0  # a hit from stealth always crits: keep the numbers comparable
		ctx.armor_pen = 0.0
		d0.stats.final.armor = armor
		var near := Combat.instance.deal_damage(ctx, d0, 1000.0)
		p.status.apply("stealth", 5.0, 0.0, Combat.instance.make_ctx(p, {"id": "test", "school": "spell"}))
		d0.stats.final.armor = armor
		var hidden := Combat.instance.deal_damage(ctx, d0, 1000.0)
		var home := d0.global_position
		d0.global_position = p.global_position + Vector2(260, 0)
		d0.stats.final.armor = armor
		var far := Combat.instance.deal_damage(ctx, d0, 1000.0)
		d0.global_position = home
		d0.recompute_stats()
		return [near, hidden, far])
	_report(id, r[1][0] > 0.0 and absf(r[0][0] / r[1][0] - 1.0) < 0.02, "a near hit still meets the armor (near, stealth, far)", r)
	_report(id, r[0][1] >= r[1][1] * 2.0 and r[0][2] >= r[1][2] * 2.0, "hits from stealth and beyond 200 px ignore the armor (near, stealth, far)", r)


func _probe_falconer(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var sk := GameData.skill("ranger_shot")
		var pid := Combat.instance.spawn_projectile(sk.effects[0], Combat.instance.make_ctx(p, sk), p.global_position, Vector2.RIGHT)
		var reach := float(Combat.instance.projectiles[pid].left)
		var seen := await _sees_in_dark()
		return [reach, seen])
	_report(id, absf(r[0][0] / r[1][0] - 1.35) < 0.01, "a shot flies 35% further", r)
	_report(id, r[0][1] == 1 and r[1][1] == 0, "the hero sees an unlit spot in sight (1 seen, 0 not, -1 no spot)", r)
	# The range is for ranged skills only: a spell keeps its reach.
	_wear(item)
	da.check(is_equal_approx(p.stats.skill_mod("mage_fireball", "range_mult"), 0.0) and p.stats.skill_mod("ranger_shot", "range_mult") > 0.3,
		"%s: only ranged skills reach further (a spell doesn't)" % id)


## 1 when the hero sees an unlit floor spot in line of sight beyond its own light, 0 when not, -1
## when the floor has no such spot.
func _sees_in_dark() -> int:
	if _dark_pair.is_empty():
		_dark_pair = _find_dark_pair()
	if _dark_pair.is_empty():
		return -1
	p.torch_left = 0.0
	p.host_teleport(_dark_pair[0])
	for i in 4:
		await da.get_tree().physics_frame
	var seen: bool = g.visibility.sees(_dark_pair[1])
	p.host_teleport(_start)
	return 1 if seen else 0


func _find_dark_pair() -> Array:
	var vis: Visibility = g.visibility
	var dist := vis.personal_radius + 40.0
	var lights: Array = []
	for l in g.get_tree().get_nodes_in_group(LightLayers.GROUP):
		if l.is_visible_in_tree() and l != vis.vision_light and not p.is_ancestor_of(l) and float(l.get_meta("radius", 0.0)) > 0.0:
			lights.append([l.global_position, float(l.get_meta("radius", 0.0))])
	var space: PhysicsDirectSpaceState2D = g.get_viewport().world_2d.direct_space_state
	var d: Node = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			if d.cell_at(Vector2i(x, y)) != DungeonGenerator.CELL_FLOOR:
				continue
			var from: Vector2 = d.cell_center(Vector2i(x, y))
			for k in 8:
				var to: Vector2 = from + Vector2.from_angle(TAU * k / 8.0) * dist
				if d.cell_at(d.cell_of(to)) != DungeonGenerator.CELL_FLOOR or vis._cell_lit(to, lights, 6.0):
					continue
				var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), to + Vector2(0, -6), Combat.LOS_MASK)
				if space.intersect_ray(q).is_empty():
					return [from, to]
	return []


func _probe_toxic_feeder(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var mctx := Combat.instance.make_ctx(dummies[0], {"id": "test_cloud", "school": "spell", "damage_type": "nature"})
		p.resource.value = 0.0
		p.resource.regen_per_second = 0.0
		p.stats.final.dodge = 0.0
		Combat.instance.add_zone({"type": "zone", "radius": 40, "duration": 1.2, "tick": 0.5, "damage": {"base": 6, "coef": 0},
				"damage_type": "nature", "color": "#66ff44"}, mctx, p.global_position)
		await da._wait(1.1)
		var mana := p.resource.value
		var lost := p.health.max_hp - p.health.hp
		var poisoned := Combat.instance.apply_status(mctx, p, "poison", 5.0, 3.0) and p.status.has("poison")
		return [mana, lost, poisoned])
	_report(id, r[0][0] >= 9.9 and r[1][0] < 1.0 and r[0][1] <= 0.0 and r[1][1] > 0.0, "a poison cloud feeds mana and doesn't hurt (mana, HP lost)", r)
	_report(id, not r[0][2] and r[1][2], "poison doesn't take hold", r)


func _probe_trapper(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var sk := GameData.skill("ranger_snare_trap")
		var ctx := Combat.instance.make_ctx(p, sk)
		var last := -1
		for i in 7:
			last = Combat.instance.add_zone(sk.effects[0], ctx, p.global_position + Vector2(-40, -40 + i * 4))
		var mine: int = Combat.instance.zones.values().filter(func(z): return z.trap and z.ctx.get("caster") == p).size()
		return [mine, float(Combat.instance.zones[last].radius)])
	_report(id, r[0][0] == 2 * r[1][0] and r[1][0] >= 1 and absf(r[0][1] / r[1][1] - 1.5) < 0.01, "twice the traps stay out, triggering 50% wider (traps, radius)", r)


func _probe_softsteps(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var plate: Node2D = load("res://scripts/dungeon/pressure_plate.gd").new()
		plate.setup(g.dungeon.cell_of(p.global_position), g.dungeon.tile, "Plate_probe")
		plate.position = p.global_position
		g.dungeon.add_child(plate)
		plate.host_tick(0.016, [p], g.dungeon)
		var armed: bool = plate._armed_left >= 0.0
		plate.queue_free()
		var heard := await _heard_through_wall()
		return [armed, heard])
	_report(id, not r[0][0] and r[1][0], "a pressure plate doesn't click", r)
	_report(id, r[0][1] == 0 and r[1][1] == 1, "a monster behind a wall doesn't hear the fight (1 heard, 0 not, -1 no spot)", r)


## A ghoul next to a wall raises the pack alert for the hero: 1 when the monster behind the wall is
## alerted too, 0 when not, -1 when the floor has no such spot.
func _heard_through_wall() -> int:
	if _wall_pair.is_empty():
		_wall_pair = _find_wall_pair()
	if _wall_pair.is_empty():
		return -1
	var a: Enemy = g.spawn_monster("ghoul", _wall_pair[0], false)
	var b: Enemy = g.spawn_monster("training_dummy", _wall_pair[1], false)
	await da._wait(0.2)
	p.host_teleport(_wall_pair[0])
	# The pack alert the ghoul raises when it spots the hero (called directly: whether the ghoul's
	# own think tick spots the hero in time is not what this measures).
	a.set_physics_process(false)
	b.set_physics_process(false)
	a._alert_nearby(p)
	await da._wait(0.1)
	var heard := 1 if b.aggro else 0
	p.host_teleport(_start)
	a.queue_free()
	b.queue_free()
	await da._wait(0.1)
	return heard


func _find_wall_pair() -> Array:
	var d: Node = g.dungeon
	var r := float(GameData.bal("threat.aggro_share_radius")) - 20.0
	var reach := int(r / d.tile)
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			var c := Vector2i(x, y)
			if d.cell_at(c) != DungeonGenerator.CELL_FLOOR or d.cell_center(c).distance_to(_start) < 300.0:
				continue
			var a: Vector2 = d.cell_center(c)
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var c2 := c + Vector2i(dx, dy)
					var b: Vector2 = d.cell_center(c2)
					if d.cell_at(c2) == DungeonGenerator.CELL_FLOOR and a.distance_to(b) <= r and Combat.instance.wall_between(a, b):
						return [a, b]
	return []


func _probe_venom_stacks(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> int:
		var ctx := Combat.instance.make_ctx(p, {"id": "test_poison", "school": "ranged"})
		for i in 8:
			Combat.instance.apply_status(ctx, dummies[0], "poison", 5.0, 1.0)
		return dummies[0].status.stacks_of("poison"))
	_report(id, r[0] == 6 and r[1] == 3, "poison stacks to 6", r)


func _probe_surehand(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		var ctx := Combat.instance.make_ctx(p, {"id": "test_shot", "school": "ranged"})
		ctx.crit_chance = 0.0
		p.stats.final.miss_chance = 1.0
		var aimed := Combat.instance.deal_damage(ctx, d0, 100.0)
		p.recompute_stats()
		d0.facing = (p.global_position - d0.global_position).normalized()
		d0.stats.final.block_chance = 1.0
		d0.stats.final.block_value = 0.0
		var through := Combat.instance.deal_damage(_ctx({"id": "test_shot", "school": "ranged"}), d0, 100.0)
		d0.recompute_stats()
		return [aimed, through])
	_report(id, r[0][0] > 0.0 and r[1][0] < 0.0, "a shot can't miss (at 100% miss chance; -1 = missed)", r)
	_report(id, r[1][1] > 0.0 and r[0][1] >= r[1][1] * 1.8, "a shield doesn't block the shot", r)


func _probe_bramble_root(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		var ctx := _ctx(GameData.skill("ranger_shot"))
		for i in 50:
			Combat.instance.deal_damage(ctx, d0, 5.0)
			if d0.status.has("root"):
				return [i + 1, _left(d0, "root")]
		return [0, 0.0])
	_report(id, r[0][0] > 0 and absf(r[0][1] - 1.5) < 0.1 and r[1][0] == 0, "basic shots root for 1.5 s (shots until a root, its time)", r)


func _probe_abyss_quiver(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var sk := GameData.skill("ranger_hunters_mark")
		var free := 0
		for i in 40:
			p.resource.value = p.resource.max_value
			p.cooldowns.clear()
			Combat.instance._pay(p, sk, "ranger_hunters_mark")
			if p.resource.value >= p.resource.max_value - 0.01:
				free += 1
		p.cooldowns.clear()
		var d0: Enemy = dummies[0]
		var d1: Enemy = dummies[1]
		d0.host_teleport(p.global_position + Vector2(50, 0))
		d1.host_teleport(p.global_position + Vector2(90, 0))
		dummies[2].host_teleport(g.nearest_floor(p.global_position + Vector2(-60, 0)))
		await da._wait(0.1)
		var h0 := d0.health.hp
		var h1 := d1.health.hp
		var shot := GameData.skill("ranger_shot")
		Combat.instance.spawn_projectile(shot.effects[0], _ctx(shot), p.global_position, Vector2.RIGHT)
		await da._wait(0.4)
		return [free, d0.health.hp < h0, d1.health.hp < h1])
	_report(id, r[0][0] > 0 and r[1][0] == 0, "some shots cost no mana (of 40)", r)
	_report(id, r[0][1] and r[0][2] and r[1][1] and not r[1][2], "an arrow pierces the first enemy (first hit, second hit)", r)


func _probe_apex_mark(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		d0.aggro = true  # no boss engagement (music, arena) for a dummy playing a boss
		d0.is_boss = true
		var err := Combat.instance.try_use_skill(p, "ranger_hunters_mark", d0.global_position)
		await da._wait(0.7)
		var res := [err, _left(d0, "hunters_mark"), d0.status.has("apex_mark"), d0.stats.get_stat("crit_taken")]
		d0.is_boss = false
		return res)
	_report(id, str(r[0][0]).is_empty() and r[0][1] > 1000.0 and r[1][1] > 0.0 and r[1][1] <= 15.5, "Hunter's Mark stays on a boss (seconds left)", r)
	_report(id, r[0][2] and r[0][3] >= 0.1 and not r[1][2], "the marked boss takes +10% crit chance", r)


# --- Mage --------------------------------------------------------------------------------------


func _probe_lava_walker(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var idx := _cell_index(p.global_position)
		var old: int = g.dungeon.cells[idx]
		p.health.hp = p.health.max_hp * 0.5
		g.dungeon.cells[idx] = DungeonGenerator.CELL_LAVA
		var change := await _hp_change(1.2)
		g.dungeon.cells[idx] = old
		await da.get_tree().physics_frame
		await da.get_tree().physics_frame
		var dmg := Combat.instance.deal_damage(_ctx({"id": "test_fire", "school": "spell", "damage_type": "fire"}), dummies[0], 1000.0, {"damage_type": "fire"})
		return [change, dmg])
	_report(id, r[0][0] > 0.0 and r[1][0] < 0.0, "lava heals instead of burning (HP change)", r)
	_report(id, r[1][1] > 0.0 and absf(r[0][1] / r[1][1] - 1.3) < 0.02, "after lava, fire hits 30% harder", r)


func _probe_deep_frost(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var ctx := Combat.instance.make_ctx(p, GameData.skill("mage_frost_nova"))
		Combat.instance.apply_status(ctx, dummies[0], "freeze", 2.0, 0.0)
		var frozen := _left(dummies[0], "freeze")
		var gh: Enemy = g.spawn_monster("ghoul", g.nearest_floor(_start + Vector2(0, -60)), false)
		await da._wait(0.2)
		Combat.instance.apply_status(ctx, gh, "freeze", 3.0, 0.0)
		var before: int = Combat.instance._next_id
		Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill("mage_frost_nova")), gh, gh.health.max_hp * 5.0, {"damage_type": "true"})
		var shards := 0
		for pid in Combat.instance.projectiles:
			if int(pid) > before and Combat.instance.projectiles[pid].team == p.team:
				shards += 1
		if is_instance_valid(gh) and gh.is_alive():
			gh.queue_free()
		return [frozen, shards])
	_report(id, absf(r[0][0] - 3.0) < 0.05 and absf(r[1][0] - 2.0) < 0.05, "a 2 s freeze lasts 1 s longer", r)
	_report(id, r[0][1] >= r[1][1] + 8, "a frozen foe shatters into 8 shards on death", r)


func _probe_burn_leech(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var d0: Enemy = dummies[0]
		p.health.hp = p.health.max_hp * 0.5
		Combat.instance.apply_status(_ctx(GameData.skill("mage_fireball")), d0, "burn", 4.0, 200.0)
		var hp0 := p.health.hp
		var dh := d0.health.hp
		Combat.instance.status_tick(d0, _effect(d0, "burn"))
		return [p.health.hp - hp0, dh - d0.health.hp])
	_report(id, r[0][1] > 0.0 and absf((r[0][0] - r[1][0]) - r[0][1] * 0.2) <= 1.0, "a burn tick heals for 20% (healed, burn damage)", r)


func _probe_primal_cinder(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var m0 := p.resource.value
		var err := Combat.instance.try_use_skill(p, "mage_fireball", dummies[0].global_position)
		var spent := m0 - p.resource.value
		var cd := p.cooldown_left("mage_fireball")
		await da._wait(0.8)
		return [err, spent, cd])
	_report(id, str(r[0][0]).is_empty() and r[0][2] <= 0.11 and r[1][2] >= 1.0, "Fireball has no cooldown (seconds)", r)
	_report(id, r[1][1] > 0.0 and absf(r[0][1] - r[1][1] * 0.7) < 0.6, "Fireball costs 30% less mana", r)


func _probe_echo_cast(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> int:
		var n := 0
		for i in 100:
			var before: int = Combat.instance._next_id
			Combat.instance.fire(p, "on_skill_cast", {"skill": "mage_bolt", "school": "spell", "target": null, "ctx": {}})
			for pid in Combat.instance.projectiles:
				var pc: Dictionary = Combat.instance.projectiles[pid].ctx
				if int(pid) > before and pc.get("from_proc", false) and str(pc.get("skill", "")) == "mage_bolt":
					n += 1
		return n)
	_report(id, r[0] > 0 and r[1] == 0, "spells echo a free duplicate (echoes of 100 casts)", r)


func _probe_resist_ignore(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> float:
		var ctx := _ctx(GameData.skill("mage_fireball"))
		ctx.magic_pen = 0.0
		return Combat.instance.deal_damage(ctx, warded, 1000.0, {"damage_type": "fire"}))
	_report(id, r[1] > 0.0 and absf(r[0] / r[1] - 1.4) < 0.02, "a 50% fire resistance counts as 30%", r)


func _probe_astral_shackles(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var ctx := _ctx({"id": "test_arcane", "school": "spell", "damage_type": "arcane"})
		dummies[0].status.apply("slow", 5.0, 0.0, ctx)
		var slowed := Combat.instance.deal_damage(ctx, dummies[0], 1000.0, {"damage_type": "arcane"})
		var plain := Combat.instance.deal_damage(ctx, dummies[1], 1000.0, {"damage_type": "arcane"})
		return [slowed, plain])
	var gain: float = (r[0][0] / r[0][1]) / (r[1][0] / r[1][1]) if r[0][1] > 0.0 and r[1][0] > 0.0 and r[1][1] > 0.0 else 0.0
	_report(id, absf(gain - 1.2) < 0.02, "a slowed foe takes +20% damage (slowed, other)", r)


func _probe_hourglass(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var err := Combat.instance.try_use_skill(p, "mage_fireball", dummies[0].global_position)
		var cd := p.cooldown_left("mage_fireball")
		await da._wait(0.8)
		p.cooldowns.clear()
		p.resource.value = p.resource.max_value
		var err2 := Combat.instance.try_use_skill(p, "mage_time_warp", p.global_position)
		await da._wait(0.8)
		return [err + err2, cd, _left(p, "time_warp")])
	_report(id, str(r[0][0]).is_empty() and r[1][1] > 0.0 and absf(r[0][1] / r[1][1] - 0.8) < 0.02, "spell cooldowns are 20% shorter (Fireball)", r)
	_report(id, r[1][2] > 0.0 and absf((r[0][2] - r[1][2]) - 5.0) < 0.3, "Time Warp lasts 5 s longer", r)
	_wear(item)
	da.check(is_equal_approx(p.stats.skill_mod("warrior_cleave", "cooldown_mult"), 0.0) and p.stats.skill_mod("mage_fireball", "cooldown_mult") < -0.15,
		"%s: only spells' cooldowns are cut (a melee skill's isn't)" % id)


func _probe_blood_mana(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		p.resource.value = 0.0
		var hp0 := p.health.hp
		var cost := Combat.instance._cost_of(p, GameData.skill("mage_fireball"))
		var err := Combat.instance.try_use_skill(p, "mage_fireball", dummies[0].global_position)
		var spent := hp0 - p.health.hp
		await da._wait(0.8)
		return [err, spent, cost])
	_report(id, str(r[0][0]).is_empty() and absf(r[0][1] - r[0][2] * 2.0) < 1.0 and str(r[1][0]) == "Not enough Mana" and r[1][1] == 0.0,
			"with no mana a spell costs 2 HP per mana (error, HP spent, cost)", r)


# --- Priest ------------------------------------------------------------------------------------


func _probe_crusader_ground(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var err := Combat.instance.try_use_skill(p, "priest_consecration", p.global_position)
		await da._wait(0.8)
		var d0: Enemy = dummies[0]
		var actx := Combat.instance.test_ctx(d0, {"id": "test_attack", "school": "melee"})
		actx.crit_chance = 0.0
		p.stats.final.block_chance = 0.0  # only the Consecration may block
		var taken := Combat.instance.deal_damage(actx, p, p.health.max_hp * 0.3)
		var h0 := d0.health.hp
		Combat.instance.deal_damage(_ctx({"id": "test_strike", "school": "melee"}), dummies[1], 100.0)
		return [err, taken, h0 - d0.health.hp])
	_report(id, str(r[0][0]).is_empty() and r[1][1] > 0.0 and r[0][1] <= r[1][1] * 0.6, "in Consecration a frontal blow is blocked (damage taken)", r)
	_report(id, r[0][2] > 0.0 and r[1][2] <= 0.0, "in Consecration a melee strike hits the other foes in the ring", r)


func _probe_slippers(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> float:
		ally.health.hp = ally.health.max_hp * 0.4
		var err := Combat.instance.try_use_skill(p, "priest_heal", ally.global_position)
		var t := float(p.casting.get("left", 0.0)) if err.is_empty() else -1.0
		await da._wait(0.8)
		return t)
	_report(id, r[1] > 0.0 and absf(r[0] / r[1] - 0.7) < 0.02, "Flash Heal casts 30% faster (seconds)", r)


func _probe_renew_mastery(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var ctx := Combat.instance.make_ctx(p, GameData.skill("priest_renew"))
		ally.health.hp = ally.health.max_hp * 0.3
		for i in 3:
			Combat.instance.apply_status(ctx, ally, "renew", 12.0, 5.0)
		var stacks := ally.status.stacks_of("renew")
		ally.status.remove("renew")
		Combat.instance.apply_status(ctx, ally, "renew", 12.0, 5.0)
		# Ticks in 2.7 s: every 1 s plain (1, 2), every 0.75 s after the first with the gloves (1, 1.75, 2.5).
		var ticks := 0
		var last := ally.health.hp
		var t := 0.0
		while t < 2.7:
			await da.get_tree().physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			if ally.health.hp > last + 0.01:
				ticks += 1
			last = ally.health.hp
		ally.status.remove("renew")
		return [stacks, ticks])
	_report(id, r[0][0] == 3 and r[1][0] == 1, "Renew stacks 3 times", r)
	_report(id, r[0][1] > r[1][1] and r[1][1] >= 1, "Renew ticks faster (heals in 2.7 s)", r)


func _probe_dawn_crosier(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var res: Array = []
		var had_char := GameState.characters.has(0)
		for k in 2:
			# A second hero falls next to the priest (the Crosier only saves someone else). Peer 0:
			# its owner RPCs (inventory) stay on the host instead of going to an unknown peer.
			var fallen := Player.new()
			fallen.setup({"peer": 0, "pos": g.nearest_floor(_start + Vector2(-40, 30)), "class_id": "warrior", "name": "Fallen", "level": 1})
			g.add_child(fallen)
			await da._wait(0.2)
			Combat.instance.deal_damage(Combat.instance.test_ctx(dummies[0], {"id": "test_attack", "school": "spell"}), fallen, fallen.health.max_hp * 3.0, {"damage_type": "true"})
			res.append(fallen.life_state == Player.Life.ALIVE and fallen.health.hp >= fallen.health.max_hp * 0.45)
			fallen.queue_free()
			await da._wait(0.1)
		if p.has_meta("crosier_used"):
			p.remove_meta("crosier_used")
		if not had_char:
			GameState.characters.erase(0)
		return res)
	_report(id, r[0] == [true, false] and r[1] == [false, false], "a fallen ally rises at 50% HP, once (first death, second death)", r)


func _probe_black_sacrament(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		# Low enough that no heal reaches the cap; no crits, so the leech share is the same both runs.
		p.health.hp = p.health.max_hp * 0.2
		p.stats.final["crit_chance"] = 0.0
		var gh: Enemy = g.spawn_monster("ghoul", g.nearest_floor(_start + Vector2(0, 50)), false)
		await da._wait(0.2)
		gh.status.apply("stun", 5.0, 0.0, null)
		gh.health.hp = 1.0
		await da._wait(0.1)
		gh.stats.final.dodge = 0.0
		var hp0 := p.health.hp
		var err := Combat.instance.try_use_skill(p, "priest_shadow_word_death", gh.global_position)
		await da._wait(0.8)
		var dead := not is_instance_valid(gh) or not gh.is_alive()
		if not dead:
			gh.queue_free()
		return [err, dead, p.cooldown_left("priest_shadow_word_death"), (p.health.hp - hp0) / p.health.max_hp])
	_report(id, str(r[0][0]).is_empty() and r[0][1] and r[1][1] and r[0][2] <= 0.0 and r[1][2] > 0.0, "a killing Shadow Word: Death resets its cooldown", r)
	_report(id, absf(r[0][3] - r[1][3] - 0.3) <= 0.03, "a killing Shadow Word: Death heals 30% max HP (HP fraction gained)", r)


func _probe_endless_grace(id: String, item: Dictionary) -> void:
	var measure := func() -> Array:
		var sk := GameData.skill("priest_heal")
		var ctx := _ctx(sk)
		var out: Array = []
		for frac in [0.2, 0.6]:
			ally.health.hp = ally.health.max_hp * frac
			var h0 := ally.health.hp
			Combat.instance.run_effect(sk.effects[0], ctx, p.global_position, ally.global_position)
			out.append(ally.health.hp - h0)
		return out
	var r := await _ab(item, measure, ["low_hp_heal_below", "low_hp_heal_bonus"])
	_report(id, r[0][1] > 0.0 and r[1][1] > 0.0 and absf(r[0][0] / r[0][1] - 1.6) < 0.05 and absf(r[1][0] / r[1][1] - 1.0) < 0.05,
			"a heal on an ally below 30% HP is 60% stronger (at 20%, at 60%)", r)


func _probe_iron_zealot(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var actx := Combat.instance.test_ctx(dummies[0], {"id": "test_attack", "school": "melee"})
		actx.crit_chance = 0.0
		p.stats.final.block_chance = 0.0
		var taken := Combat.instance.deal_damage(actx, p, p.health.max_hp * 0.5)
		return [p.stats.get_stat("armor"), p.stats.get_stat("max_resource"), taken])
	_report(id, absf((r[0][0] - r[1][0]) - r[0][1] * 0.15) < 1.0 and r[0][2] < r[1][2], "15% of max mana becomes armor, blows hurt less (armor, mana, taken)", r)


func _probe_undying_sun(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var err := Combat.instance.try_use_skill(p, "priest_apotheosis", p.global_position)
		await da._wait(0.8)
		var left := _left(p, "apotheosis")
		var h0: float = dummies[0].health.hp
		await da._wait(1.2)
		return [err, left, h0 - dummies[0].health.hp])
	_report(id, str(r[0][0]).is_empty() and r[1][1] > 0.0 and absf((r[0][1] - r[1][1]) - 6.0) < 0.3, "Apotheosis lasts 6 s longer", r)
	_report(id, r[0][2] > 0.0 and r[1][2] <= 0.0, "Apotheosis scorches undead nearby (damage to an undead dummy)", r)


func _probe_goddess_tear(id: String, item: Dictionary) -> void:
	var r := await _ab(item, func() -> Array:
		var err := Combat.instance.try_use_skill(p, "priest_guardian_spirit", p.global_position)
		await da._wait(0.8)
		var cd := p.cooldown_left("priest_guardian_spirit")
		var spirit := p.status.has("guardian_spirit")
		p.resource.value = 0.0
		p.health.hp = p.health.max_hp * 0.5
		Combat.instance.deal_damage(Combat.instance.test_ctx(dummies[0], {"id": "test", "school": "spell"}), p, p.health.max_hp * 3.0, {"damage_type": "true"})
		await da.get_tree().process_frame
		await da.get_tree().process_frame
		return [err, spirit, cd, p.health.fraction(), p.resource.fraction(), p.life_state == Player.Life.ALIVE])
	var want := 20.0 / (1.0 + p.stats.get_stat("haste"))
	_report(id, str(r[0][0]).is_empty() and r[0][1] and absf((r[1][2] - r[0][2]) - want) < 0.3, "Guardian Spirit's cooldown is 20 s shorter", r)
	_report(id, r[0][5] and r[1][5] and r[0][3] >= 0.99 and r[0][4] >= 0.99 and r[1][3] < 0.6 and r[1][4] < 0.3,
			"a saving Guardian Spirit restores all HP and mana (HP, mana)", r)
