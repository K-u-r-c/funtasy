class_name BalanceSuite
extends RefCounted
## Balance probe (scenario "balance", solo host, --class=<id>): the levels-per-floor progression
## probe, then a hero at the progression curve's level on each depth in rare gear of the floor's
## item level, with every stat point in the class's main stat, meets every monster that can spawn
## there (tiers) and the biome's bosses. For each pair it measures, with the real host damage
## code, the hero's time to kill the monster with the primary attack and the monster's time to kill
## the hero with its first damaging ability (behaviour modules off). Prints a table and checks the
## pacing bands in balance.json "probe" (the GDD names no pacing targets; see docs/DECISIONS.md).

const MAIN_STAT := {"warrior": "strength", "ranger": "agility", "mage": "intellect", "priest": "intellect"}
const GEAR := {
	"warrior": {"main_hand": "sword", "off_hand": "shield", "head": "plate_helm", "chest": "plate_chest"},
	"ranger": {"main_hand": "bow", "head": "hood", "chest": "robe"},
	"mage": {"main_hand": "battle_staff", "off_hand": "trinket", "head": "hood", "chest": "robe"},
	"priest": {"main_hand": "holy_staff", "head": "hood", "chest": "robe"},
}
const COMMON_GEAR := {"legs": "greaves", "boots": "boots", "gloves": "gloves", "ring_1": "ring", "ring_2": "ring", "necklace": "necklace"}

var da: Node
var g: Node
var p: Player
var _rng := RandomNumberGenerator.new()


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Levels per floor (#8): a party of `n` equal heroes clears every pack, elite and the boss of
## floors 1..`floors`, kill by kill with the game's own kill_xp / monster_level_at (the level
## rises during the floor, so later kills are worth more). Splitting slimes, summons and other
## spawned adds are left out. Averaged over seeds; returns the solo party's level at the start
## of each depth (index = depth) for the pacing probe below.
func run_progression(max_depth: int = 20) -> Array:
	g = da._game()
	p = da._local()
	var probe: Dictionary = GameData.bal("probe", {})
	var floors := int(probe.get("xp_probe_floors", 5))
	var seeds := int(probe.get("xp_probe_seeds", 4))
	var band: Array = probe.get("levels_per_floor", [2.0, 3.0])
	var cap := int(GameData.bal("progression.max_level"))
	var curve: Array = []
	curve.resize(max_depth + 2)
	curve.fill(0.0)
	var bad: Array = []
	for n in [1, 4]:
		var gained: Array = []
		gained.resize(max_depth + 1)
		gained.fill(0.0)
		var last := floors if n > 1 else max_depth
		for si in seeds:
			var lvl := 1
			var xp := 0
			for d in range(1, last + 1):
				var start := float(lvl) + (float(xp) / Player.xp_to_next(lvl) if lvl < cap else 0.0)
				if n == 1:
					curve[d] += start / seeds
				var fd: Dictionary = GameData.floor_types[g.floor_type_for(d)]
				var seed_v := 9001 + si * 7919 + d * 131
				var lay: Dictionary = DungeonGenerator.new().generate(seed_v, fd, 1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (n - 1), d, "archibald")
				var elites: Dictionary = g._pick_elites(lay, seed_v, true)
				var kills: Array = []
				for gi in lay.spawns.size():
					for mi in lay.spawns[gi].monsters.size():
						kills.append([GameData.monsters[str(lay.spawns[gi].monsters[mi].id)], elites.has(Vector2i(gi, mi))])
				kills.append([GameData.bosses[g.pick_boss(fd, seed_v)], false])
				for k in kills:
					xp += g.kill_xp(k[0], g.monster_level_at(d, float(lvl)), bool(k[1]), n)
					while lvl < cap and xp >= Player.xp_to_next(lvl):
						xp -= Player.xp_to_next(lvl)
						lvl += 1
				var end := float(lvl) + (float(xp) / Player.xp_to_next(lvl) if lvl < cap else 0.0)
				gained[d] += (end - start) / seeds
			if n == 1:
				curve[last + 1] += (float(lvl) + (float(xp) / Player.xp_to_next(lvl) if lvl < cap else 0.0)) / seeds
		for d in range(1, floors + 1):
			print("[balance] progression party %d floor %d: +%.2f levels" % [n, d, gained[d]])
			if gained[d] < float(band[0]) or gained[d] > float(band[1]):
				bad.append("%d heroes floor %d +%.2f" % [n, d, gained[d]])
	da.check(bad.is_empty(), "clearing a floor gives %s levels on floors 1-%d, solo and 4 players (outside: %s)" % [band, floors, bad])
	# Floors 1-3 against the numbers before the playtest fixes (one level per floor, monster level
	# 1 x (depth-1) + 0.5 x party + 0.5, +22% HP / +14% damage per level, no easing): a normal
	# monster at the party's mid-floor level must be clearly weaker (#8).
	var weaker: Array = []
	for d in range(1, 4):
		var old_lvl := maxi(1, roundi(1.0 * (d - 1) + 0.5 * d + 0.5))
		var old := Vector2(1.0 + 0.22 * (old_lvl - 1), 1.0 + 0.14 * (old_lvl - 1))
		var lvl_now: int = g.monster_level_at(d, float(_curve_level(curve, d)))
		var now: Vector2 = g.spawn_mults(d, lvl_now, false, 1)
		print("[balance] floor %d normal monster: before L%d hp x%.2f dmg x%.2f | now L%d hp x%.2f dmg x%.2f" % [d, old_lvl, old.x, old.y, lvl_now, now.x, now.y])
		if now.x > old.x * 0.85 or now.y > old.y * 0.85:
			weaker.append(d)
	da.check(weaker.is_empty(), "floors 1-3 monsters have clearly less HP and damage than before (not on floors %s)" % [weaker])
	for d in range(1, max_depth + 1):
		print("[balance] progression solo level at the start of depth %d: %.1f (monsters L%d, items L%d)" % [d, curve[d],
			g.monster_level_at(d, curve[d]), g.item_level_at(g.monster_level_at(d, curve[d]))])
	return curve


## The heroes' level on `d` in the pacing probe: the progression curve's level halfway through
## the floor.
func _curve_level(curve: Array, d: int) -> int:
	return clampi(roundi((float(curve[d]) + float(curve[d + 1])) / 2.0), 1, int(GameData.bal("progression.max_level")))


func run(depths: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 20]) -> void:
	g = da._game()
	p = da._local()
	_rng.seed = 11
	var curve := run_progression(20)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var probe: Dictionary = GameData.bal("probe", {})
	var start: Vector2 = g.layout.start
	var spot: Vector2 = g.nearest_floor(start + Vector2(70, 0))
	var bad: Array = []
	print("[balance] class depth biome monster | level hp | hero_hit ttk_s | mon_hit ttd_s")
	for d in depths:
		_gear_up(_curve_level(curve, int(d)), int(d))
		g.depth = int(d)
		var biome: String = g.floor_type_for(int(d))
		# Only the monsters that can spawn there (tiers, #8).
		var ids: Array = GameData.floor_types[biome].monsters.map(func(m): return str(m.id)).filter(func(id): return DungeonGenerator.spawnable(id, int(d)))
		ids.sort()
		for id in ids:
			var def: Dictionary = GameData.monsters[id]
			if str(def.get("role", "")) in ["illusion", "boss_part"] or GameData.bosses.has(id):
				continue
			var row := await _measure(str(id), spot, false)
			if row.is_empty():
				continue
			var critter: bool = float(def.base_stats.hp) <= float(probe.get("critter_hp_max", 20.0))  # one-hit swarm by design
			# The eased first floors (#8) may lose trash to a single hit.
			var one_hit_ok: bool = critter or int(d) < int(probe.get("normal_ttk_min_from_depth", 1))
			if row.ttk > float(probe.get("normal_ttk_max", 12.0)) or (row.ttk < float(probe.get("normal_ttk_min", 0.3)) and not one_hit_ok) \
					or row.ttd < float(probe.get("normal_ttd_min", 4.0)):
				bad.append("%s@%d ttk %.1f ttd %.1f" % [id, d, row.ttk, row.ttd])
		for bid in GameData.floor_types[biome].get("bosses", []):
			var brow := await _measure(str(bid), spot, true)
			if brow.is_empty():
				continue
			if brow.ttk > float(probe.get("boss_ttk_max", 240.0)) or brow.ttk < float(probe.get("boss_ttk_min", 25.0)) \
					or brow.ttd < float(probe.get("boss_ttd_min", 3.0)):
				bad.append("%s@%d ttk %.1f ttd %.1f" % [bid, d, brow.ttk, brow.ttd])
	da.check(bad.is_empty(), "%s: every monster and boss inside the pacing bands (outside: %s)" % [p.class_id, bad])


## Simple start (#1): a brand-new level 1 hero (the new-character kit and gear, no points)
## against every monster of the floor pools of the first depths, primary attack only. Bands in
## balance.json "probe" (fresh_*): each monster dies quickly and needs long to kill the hero.
func run_fresh(depths: Array = [1, 2]) -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var probe: Dictionary = GameData.bal("probe", {})
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(70, 0))
	var fresh := GameState.new_character("Fresh", p.class_id)
	var keep_eq: Dictionary = p.inv.equipment
	var keep_depth: int = g.depth
	p.level = 1
	p.allocated = {}
	p.inv.equipment = fresh.equipment.duplicate(true)
	p.recompute_stats()
	var bad: Array = []
	print("[balance] fresh class depth biome monster | level hp | hero_hit ttk_s | mon_hit ttd_s")
	for d in depths:
		g.depth = int(d)
		var biome: String = g.floor_type_for(int(d))
		for entry in GameData.floor_types[biome].monsters:
			if not DungeonGenerator.spawnable(str(entry.id), int(d)):
				continue
			var row := await _measure(str(entry.id), spot, false)
			if row.is_empty():
				continue
			if row.ttk > float(probe.get("fresh_ttk_max", 6.0)) or row.ttd < float(probe.get("fresh_ttd_min", 10.0)):
				bad.append("%s@%d ttk %.1f ttd %.1f" % [entry.id, d, row.ttk, row.ttd])
		for bid in GameData.floor_types[biome].get("bosses", []):
			var brow := await _measure(str(bid), spot, true)
			if not brow.is_empty() and (brow.ttk > float(probe.get("fresh_boss_ttk_max", 150.0)) or brow.ttd < float(probe.get("fresh_boss_ttd_min", 6.0))):
				bad.append("%s@%d ttk %.1f ttd %.1f" % [bid, d, brow.ttk, brow.ttd])
	da.check(bad.is_empty(), "%s: a new level 1 hero beats every floor 1-2 monster and boss comfortably (outside: %s)" % [p.class_id, bad])
	g.depth = keep_depth
	p.inv.equipment = keep_eq
	p.recompute_stats()


## Rare (tier 3) gear of the floor's item level, the hero at `level` with all points in the main stat.
func _gear_up(level: int, at_depth: int) -> void:
	p.level = level
	p.allocated = {MAIN_STAT[p.class_id]: int(GameData.bal("progression.stat_points_per_level")) * (level - 1)}
	var eq := {}
	var gear: Dictionary = GEAR[p.class_id].duplicate()
	gear.merge(COMMON_GEAR)
	var ilvl: int = g.item_level_at(g.monster_level_at(at_depth, float(level)))
	for slot in gear:
		eq[slot] = ItemGenerator.generate_equipment(str(gear[slot]), ilvl, 3, _rng)
	p.inv.equipment = eq
	p.recompute_stats()
	p.health.hp = p.health.max_hp


func _measure(id: String, spot: Vector2, boss: bool) -> Dictionary:
	var m: Enemy = g.spawn_monster(id, spot, boss)
	await da._wait(0.2)
	if not is_instance_valid(m):
		return {}
	m.set_process(false)
	# Baseline numbers: behaviour modules (burrowing, disguises, frontal shields) and statuses off.
	m.behaviors = []
	m.behavior_state = ""
	m.status.clear_all()
	var hero_hit := _avg_hit(p, GameData.skill(str(GameData.classes[p.class_id].primary_attack)), m)
	var cd := maxf(p.stats.cooldown_for(GameData.skill(str(GameData.classes[p.class_id].primary_attack))), 0.35)
	var ttk: float = m.health.max_hp / maxf(hero_hit / cd, 0.01)
	var mon_hit := 0.0
	var mon_cd := 1.0
	var abilities: Array = Array(m.def.get("ai", {}).get("abilities", [])).duplicate()
	if m.def.has("phases"):
		abilities.append_array(m.def.phases[0].get("abilities", []))
	for sid in abilities:
		var sk := GameData.skill(str(sid))
		if _damage_spec(sk).is_empty():
			continue
		mon_hit = _avg_hit(m, sk, p)
		mon_cd = maxf(float(sk.get("cooldown", 1.0)), float(GameData.bal("ai.think_interval")))
		break
	var ttd: float = p.health.max_hp / maxf(mon_hit / mon_cd, 0.01)
	print("[balance] %s %d %s %s | L%d %d | %.1f %.1fs | %.1f %.1fs" % [p.class_id, g.depth, g.floor_type_for(g.depth), id,
		m.level, roundi(m.health.max_hp), hero_hit, ttk, mon_hit, ttd])
	var row := {"ttk": ttk, "ttd": ttd}
	m.queue_free()
	await da._wait(0.1)
	return row


## The first damage spec of a skill (projectile, melee arc, hit, aoe...).
func _damage_spec(sk: Dictionary) -> Dictionary:
	for e in sk.get("effects", []):
		if e is Dictionary and e.has("damage"):
			return e
	return {}


## Average damage the attacker's skill really deals to the target (armor, resists, crits).
func _avg_hit(att: Actor, sk: Dictionary, target: Actor) -> float:
	var eff := _damage_spec(sk)
	if eff.is_empty():
		return 0.0
	var total := 0.0
	var n := 400  # damage ranges, crits and misses over 24 hits swung the averages by ±15% (flaky near the band edges)
	for i in n:
		var ctx := Combat.instance.test_ctx(att, sk)
		target.health.hp = target.health.max_hp
		var amount := Combat.instance.damage_value(eff.damage, ctx, target)
		var max_hp := target.health.max_hp
		target.health.max_hp = 1e9  # a lethal crit would end the sample (reassembling bones, splits)
		target.health.hp = 1e9
		var before := target.health.hp
		target.health.absorb = 0.0
		var iframes: float = target.get("iframe_left") if target.get("iframe_left") != null else 0.0
		if target is Player:
			target.iframe_left = 0.0
		Combat.instance.deal_damage(ctx, target, amount, {"no_procs": true})
		total += maxf(before - target.health.hp, 0.0)
		if target is Player and target.life_state != Player.Life.ALIVE:
			target.revive(1.0)
		target.health.max_hp = max_hp
		target.health.hp = max_hp
		if target is Player:
			target.iframe_left = iframes
	return total / n
