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
	p.boons = []
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
	# #73: from floor 3 the hero carries an average boon set: one per boss so far, each the
	# middle-ish pick of a seeded offer (the same set every run).
	p.boons = average_boons(p.class_id, at_depth)
	p.recompute_stats()
	p.health.hp = p.health.max_hp


## The boons a hero of `class_id` has gathered by floor `at_depth` (one per boss before it,
## none before floor 3), picked by a fixed rule from seeded offers.
static func average_boons(class_id: String, at_depth: int) -> Array:
	var owned: Array = []
	if at_depth < 3:
		return owned
	for f in range(1, at_depth):
		var o := Boons.offer(class_id, owned, hash([class_id, f, 733]))
		if not o.is_empty():
			owned.append(o[f % o.size()])
	return owned


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


# --- Floor cost probe (#71: floor modifiers; reused by #72-#77) --------------------------------


var _mon_cache: Dictionary = {}  ## "id@depth" -> {ttk, ttd, hp_hero} for the geared hero


## The cost and reward of clearing a whole floor of `fd` at `depth` for a party of `n` heroes like
## the probe hero, averaged over `seeds` layouts: every pack fought at once in its room (the party
## kills them weakest first with n x the hero's primary attack, each monster hits for as long as it
## lives, spread over the party), elites and the boss included, with the game's own spawn scaling.
## Monster health is counted in seconds of one hero's primary attack (the probe's ttk).
## Returns {time (s of fighting), damage (per hero, in hero health), deaths (rooms where a hero's
## share exceeds its health), gold, loot (gold-valued items), xp}. `extra` models what the layout
## can't show: restless (the share of fight time a hero stands still), hunters (count per floor).
func floor_cost(depth: int, n: int, fd: Dictionary, seeds: int = 6, extra: Dictionary = {}, hero_depth: int = -1) -> Dictionary:
	var probe: Dictionary = GameData.bal("probe", {})
	# The hero as the progression curve has it on `hero_depth` (default: this floor).
	var hd := depth if hero_depth < 0 else hero_depth
	var lvl := _curve_level(_curve, hd)
	# The same gear for every call on this hero floor, so only the floor changes the numbers.
	_rng.seed = 11 + lvl * 31 + hd
	_gear_up(lvl, hd)
	g.depth = depth
	var mlvl: int = g.monster_level_at(depth, float(lvl))
	var hp_ratio: float = g.spawn_mults(depth, mlvl, false, n).x / g.spawn_mults(depth, mlvl, false, 1).x
	var dmg_ratio: float = g.spawn_mults(depth, mlvl, false, n).y / g.spawn_mults(depth, mlvl, false, 1).y
	var boss_hp_ratio: float = g.spawn_mults(depth, mlvl, true, n).x / g.spawn_mults(depth, mlvl, true, 1).x
	var count_mult := (1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (n - 1)) * FloorMods.num(fd, "count_mult")
	var out := {"time": 0.0, "damage": 0.0, "deaths": 0.0, "gold": 0.0, "loot": 0.0, "xp": 0.0}
	var ov := FloorMods.loot_override(fd)
	var rarity_gold: Array = probe.get("rarity_gold", [4, 12, 40, 110, 300])
	for s in seeds:
		var fseed := 7000 + s * 977  # the same layouts on every depth: only the depth differs
		var lay: Dictionary = DungeonGenerator.new().generate(fseed, fd, count_mult, depth)
		var elite_n := roundi(2.0 * FloorMods.num(fd, "elite_mult"))
		var elites_left := elite_n
		var fights: Array = []
		for grp in lay.spawns:
			var pack: Array = []
			for m in grp.monsters:
				var st: Dictionary = await _mon_stats(str(m.id), depth)
				if st.is_empty():
					continue
				var elite := elites_left > 0 and pack.is_empty()
				if elite:
					elites_left -= 1
				var hp: float = float(st.hp) * hp_ratio * (float(GameData.bal("elite.hp_mult")) if elite else 1.0)
				var dps: float = float(st.dps) * dmg_ratio * (float(GameData.bal("elite.damage_mult")) if elite else 1.0)
				pack.append([hp, dps, str(m.id), elite])
			if not pack.is_empty():
				fights.append(pack)
		# Hunters: elites of the pool with the hunter's extra health, one fight each.
		for h in int(extra.get("hunters", 0)):
			var hid := str(fd.monsters[0].id)
			var hst: Dictionary = await _mon_stats(hid, depth)
			var hm := FloorMods.def("hunted")
			var hhp: float = float(hst.hp) * hp_ratio * float(GameData.bal("elite.hp_mult")) * (float(hm.hp_mult) + float(hm.hp_mult_per_extra) * (n - 1))
			fights.append([[hhp, float(hst.dps) * dmg_ratio * float(GameData.bal("elite.damage_mult")) * float(hm.damage_mult), hid, true]])
		var boss_id := str(fd.get("bosses", [""])[0])
		var bst: Dictionary = await _mon_stats(boss_id, depth, true)
		if not bst.is_empty():
			fights.append([[float(bst.hp) * boss_hp_ratio, float(bst.dps) * dmg_ratio, boss_id, false]])
		# Health is in seconds of one probe hero's primary attack, so the party kills n x as fast.
		var party_dps := float(n)
		var still := float(extra.get("restless_still", 0.0))
		for pack in fights:
			pack.sort_custom(func(a, b): return a[0] < b[0])
			var t := 0.0
			var room_dmg := 0.0
			for mon in pack:
				t += float(mon[0]) / maxf(party_dps, 0.01)
				room_dmg += float(mon[1]) * t
			# Restless: the share of the fight a hero stands still past the limit adds burns and
			# makes every hit land harder (the curse's stacks).
			if still > 0.0:
				var rm := FloorMods.def("restless")
				var stacks := minf(float(rm.max_stacks), 1.0 + t * still)
				room_dmg *= 1.0 + still * (pow(1.06, stacks) - 1.0)
				room_dmg += float(n) * still * t / float(rm.tick) * float(rm.burn_pct) * p.health.max_hp
			room_dmg *= float(extra.get("damage_factor", 1.0))
			out.time += t / seeds
			var share := room_dmg / float(n) / p.health.max_hp
			out.damage += share / seeds
			if share > 1.0:
				out.deaths += 1.0 / seeds
			for mon in pack:
				out.xp += float(g.kill_xp(GameData.bosses.get(mon[2], GameData.monsters.get(mon[2], {})), mlvl, mon[3], n)) * FloorMods.num(fd, "xp_mult") / seeds
		# Loot and gold: the average of many rolls per kill.
		var kills := 0
		for pack in fights:
			kills += pack.size()
		var lv := _loot_value(depth, ov, rarity_gold)
		out.gold += float(lv.gold) * kills / seeds
		out.loot += float(lv.items) * kills / seeds
	return out


var _curve: Array = []


## One kill's average gold and gold-valued items on `depth` with the floor's loot override.
func _loot_value(depth: int, ov: Dictionary, rarity_gold: Array) -> Dictionary:
	var key := "%d %s" % [depth, ov]
	if _mon_cache.has(key):
		return _mon_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = depth * 13
	var gold := 0.0
	var items := 0.0
	var n := 1500
	for i in n:
		for it in LootTable.roll("monster", g.item_level_at(g.monster_level_at(depth, float(depth))), depth, ["warrior"], rng, ov):
			if str(it.get("kind", "")) == "gold":
				gold += int(it.amount)
			elif it.has("rarity"):
				items += float(rarity_gold[clampi(int(it.rarity) - 1, 0, rarity_gold.size() - 1)])
	var out := {"gold": gold / n, "items": items / n}
	_mon_cache[key] = out
	return out


## A monster's health and damage per second against the probe hero (real damage code), cached.
func _mon_stats(id: String, depth: int, boss: bool = false) -> Dictionary:
	var key := "%s@%d L%d" % [id, depth, p.level]
	if _mon_cache.has(key):
		return _mon_cache[key]
	if not (GameData.bosses if boss else GameData.monsters).has(id):
		return {}
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(70, 0))
	var row := await _measure(id, spot, boss)
	if row.is_empty():
		return {}
	var out := {"hp": float(row.ttk), "dps": p.health.max_hp / maxf(float(row.ttd), 0.01)}
	_mon_cache[key] = out
	return out


## #71: every floor modifier makes a floor about as hard as one floor deeper (time to clear and
## damage taken, within probe.mod_band of the next floor's), for 1 and 4 heroes, and its reward
## (gold, loot, XP) grows at least as much as its cost. Restless is judged with how long this
## class stands still (probe.restless_still_<melee|ranged>), Hunted with the hunters a clear brings.
func run_mods(depths: Array = [5, 9, 14]) -> void:
	g = da._game()
	p = da._local()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	_curve = run_progression(20)
	# The damage rolls use the global generator: seeded, every run measures the same numbers.
	seed(71)
	var probe: Dictionary = GameData.bal("probe", {})
	var band: Array = probe.get("mod_cost_band", [1.03, 1.45])
	var bad: Array = []
	var rows: Array = []
	var steps: Array = []
	var melee: bool = p.class_id in ["warrior", "priest"]
	print("[balance] mods class depth n mod | time dmg deaths | plain(d) plain(d+1) | reward gold loot xp")
	for d in depths:
		for n in [1, 4]:
			var biome: String = g.floor_type_for(int(d))
			var fd: Dictionary = GameData.floor_types[biome]
			var base := await floor_cost(int(d), n, fd)
			# One floor deeper for the same party: the same biome's floor d+1 for heroes still at
			# floor d's level (what a modifier should cost).
			var deeper := await floor_cost(int(d) + 1, n, fd, 6, {}, int(d))
			var step: float = _effort(deeper) / maxf(_effort(base), 0.01)
			for id in FloorMods.defs():
				var mfd := FloorMods.apply(fd, str(id))
				var extra := {}
				match str(id):
					"restless":
						extra.restless_still = float(probe.get("restless_still_melee" if melee else "restless_still_ranged", 0.2))
					"hunted":
						var hm := FloorMods.def("hunted")
						var clear := float(base.time) + float(probe.get("travel_s_per_floor", 120.0))
						extra.hunters = int(floor(maxf(clear - float(hm.first), 0.0) / float(hm.interval))) + 1
					"dimmed":
						extra.damage_factor = float(probe.get("dimmed_damage_factor", 1.1))
				var c := await floor_cost(int(d), n, mfd, 6, extra)
				var cost: float = _effort(c) / maxf(_effort(base), 0.01)
				var bonus := 0.0
				# A hunter's sure fine item comes on top of the loot model.
				if str(id) == "hunted":
					bonus = float(extra.hunters) * float(probe.get("rarity_gold", [4, 12, 40, 110, 300])[3])
				var reward: float = (float(c.gold) / maxf(float(base.gold), 0.01) + (float(c.loot) + bonus) / maxf(float(base.loot), 0.01) + float(c.xp) / maxf(float(base.xp), 0.01)) / 3.0
				print("[balance] mods %s %d %d %s | %.0fs %.2f %.1f | step x%.2f | reward x%.2f cost x%.2f | %.0f %.0f %.0f" % [p.class_id, d, n, id,
					c.time, c.damage, c.deaths, step, reward, cost, c.gold, c.loot, c.xp])
				rows.append([str(id), int(d), n, cost, reward])
				if reward - 1.0 < (cost - 1.0) * float(probe.get("mod_reward_min", 0.8)):
					bad.append("%s@%d x%d reward x%.2f < cost x%.2f" % [id, d, n, reward, cost])
			steps.append(step)
	# One floor deeper costs this much on average (over the probe depths and party sizes; it
	# measured x1.02-x1.21 across the classes and runs, so probe.mod_cost_band is set around it).
	var mean_step := 0.0
	for st in steps:
		mean_step += float(st) / steps.size()
	var lo := float(band[0])
	var hi := float(band[1])
	print("[balance] mods %s: one floor deeper costs x%.2f on average; band x%.2f-x%.2f" % [p.class_id, mean_step, lo, hi])
	for r in rows:
		if float(r[3]) < lo or float(r[3]) > hi:
			bad.append("%s@%d x%d cost x%.2f (band x%.2f-x%.2f)" % [r[0], r[1], r[2], r[3], lo, hi])
	da.check(bad.is_empty(), "%s: every floor modifier costs about one floor deeper and pays for it (outside: %s)" % [p.class_id, bad])


## One number for how hard a floor is: fighting time and damage taken, equally weighted.
static func _effort(c: Dictionary) -> float:
	return 0.5 * float(c.time) + 0.5 * float(c.damage) * 60.0




## #77 The forge against a floor's gold: on each probe depth, for a party of 1 and of 4, what it
## costs a hero per floor to keep a legendary (and an Epic) at the floor's item level, as a share
## of that hero's gold from the floor (monster piles, the elites and the boss; chests and sales come
## on top). The legendary's share must sit inside probe.forge_legendary_share (a real sink that a
## hero can still pay), an Epic's under it, and the first step of an early legendary must cost
## less than one floor's gold.
func run_forge(depths: Array = [2, 4, 6, 9, 12, 16, 20]) -> void:
	g = da._game()
	p = da._local()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	_curve = run_progression(21)
	seed(77)
	var probe: Dictionary = GameData.bal("probe", {})
	var band: Array = probe.get("forge_legendary_share", [0.2, 0.6])
	var bad: Array = []
	var gold_cfg: Dictionary = GameData.bal("gold", {})
	print("[balance] forge depth n | ilvl -> next | hero gold/floor | legendary/floor share | epic/floor share | first step")
	for d in depths:
		var lvl := _curve_level(_curve, int(d))
		var il: int = g.item_level_at(g.monster_level_at(int(d), float(lvl)))
		var il2: int = g.item_level_at(g.monster_level_at(int(d) + 1, float(_curve_level(_curve, int(d) + 1))))
		var lg := ItemGenerator.make_legendary("crown_blood_chieftain", il, RandomNumberGenerator.new())
		var ep := ItemGenerator.generate_equipment("plate_helm", il, 4, RandomNumberGenerator.new())
		ep.erase("quality_mult")
		for n in [1, 4]:
			var keep_lg := 0.0
			var keep_ep := 0.0
			for step in range(il, il2):
				keep_lg += Forge.cost(ItemGenerator.at_level(lg, step), n)
				keep_ep += Forge.cost(ItemGenerator.at_level(ep, step), n)
			var fd: Dictionary = GameData.floor_types[g.floor_type_for(int(d))]
			var c := await floor_cost(int(d), n, fd, 3)
			var scale: float = 1.0 + float(gold_cfg.get("per_level", 0.18)) * (il - 1)
			var extra: float = (_avg(gold_cfg.get("boss", [60, 120])) + 2.0 * _avg(gold_cfg.get("elite", [25, 45]))) * scale
			var per_hero: float = (float(c.gold) + extra) / n
			var s_lg := keep_lg / maxf(per_hero, 1.0)
			var s_ep := keep_ep / maxf(per_hero, 1.0)
			var first := float(Forge.cost(lg, n))
			print("[balance] forge %d %d | %d -> %d | %.0f | %.0f %.2f | %.0f %.2f | %.0f" % [d, n, il, il2, per_hero, keep_lg, s_lg, keep_ep, s_ep, first])
			# Past the level cap nothing needs keeping current.
			if il2 > il and (s_lg < float(band[0]) or s_lg > float(band[1])):
				bad.append("legendary@%d x%d share %.2f" % [d, n, s_lg])
			if s_ep > s_lg:
				bad.append("epic@%d x%d share %.2f above the legendary's" % [d, n, s_ep])
			if int(d) <= 4 and first > per_hero:
				bad.append("first step@%d x%d %.0f > a floor's %.0f" % [d, n, first, per_hero])
	da.check(bad.is_empty(), "the forge keeps a legendary current for %d-%d%% of a hero's floor gold, 1 and 4 heroes (outside: %s)" % [roundi(float(band[0]) * 100), roundi(float(band[1]) * 100), bad])


static func _avg(r: Variant) -> float:
	return (float(r[0]) + float(r[1])) / 2.0 if r is Array else float(r)


## #72 The events against the floor they stand on, for a party of 1 and of 4 on several depths:
## the arena's three waves (fought one by one, the last with its elite) and the mimic, priced in
## fight time and damage like floor_cost prices a room, against their rewards (the chest's items
## at probe.rarity_gold, its gold). Each must pay at least probe.event_value_min x what the
## floor's own fights pay per second of fighting, at most event_value_max x (worth seeking out,
## never the only thing worth doing), and no wave may kill a hero that fights it at full health.
func run_events(depths: Array = [3, 6, 10, 16]) -> void:
	g = da._game()
	p = da._local()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	_curve = run_progression(20)
	seed(72)
	var probe: Dictionary = GameData.bal("probe", {})
	var vmin := float(probe.get("event_value_min", 0.8))
	var vmax := float(probe.get("event_value_max", 3.0))
	var rarity_gold: Array = probe.get("rarity_gold", [4, 12, 40, 110, 300])
	var bad: Array = []
	print("[balance] events class depth n | floor time dmg reward/s | arena time dmg max_wave reward value | mimic time dmg reward value")
	for d in depths:
		for n in [1, 4]:
			var fd: Dictionary = GameData.floor_types[g.floor_type_for(int(d))]
			var base := await floor_cost(int(d), n, fd, 3)
			var floor_rate: float = (float(base.gold) + float(base.loot)) / maxf(float(base.time), 1.0)
			var lvl := _curve_level(_curve, int(d))
			var il: int = g.item_level_at(g.monster_level_at(int(d), float(lvl)))
			var mlvl: int = g.monster_level_at(int(d), float(lvl))
			var hp_ratio: float = g.spawn_mults(int(d), mlvl, false, n).x / g.spawn_mults(int(d), mlvl, false, 1).x
			var dmg_ratio: float = g.spawn_mults(int(d), mlvl, false, n).y / g.spawn_mults(int(d), mlvl, false, 1).y
			# The arena: its waves from the floor's pool (the pool's average monster).
			var pool: Array = fd.monsters.filter(func(m): return DungeonGenerator.spawnable(str(m.id), int(d)) and not GameData.monsters.get(str(m.id), {}).get("role", "") in ["illusion", "boss_part"])
			var avg_hp := 0.0
			var avg_dps := 0.0
			var wsum := 0.0
			for m in pool:
				var stt: Dictionary = await _mon_stats(str(m.id), int(d))
				if stt.is_empty():
					continue
				avg_hp += float(stt.hp) * float(m.weight)
				avg_dps += float(stt.dps) * float(m.weight)
				wsum += float(m.weight)
			avg_hp /= maxf(wsum, 0.01)
			avg_dps /= maxf(wsum, 0.01)
			var count_mult: float = 1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (n - 1)
			var a_time := 0.0
			var a_dmg := 0.0
			var max_wave := 0.0
			for w in FloorEvents.def("arena").get("waves", []):
				var pack: Array = []
				for i in roundi(float(w.get("count", 3)) * count_mult):
					pack.append([avg_hp * hp_ratio, avg_dps * dmg_ratio])
				for i in int(w.get("elites", 0)):
					pack.append([avg_hp * hp_ratio * float(GameData.bal("elite.hp_mult")), avg_dps * dmg_ratio * float(GameData.bal("elite.damage_mult"))])
				var pc := _pack_cost(pack, n)
				a_time += pc.x
				a_dmg += pc.y / n / p.health.max_hp
				max_wave = maxf(max_wave, pc.y / n / p.health.max_hp)
			var a_reward := _event_reward("arena", il, int(d), rarity_gold)
			var a_value: float = a_reward / maxf(a_time, 1.0) / maxf(floor_rate, 0.01)
			# The mimic: one monster of its own.
			var ms: Dictionary = await _mon_stats("chest_mimic", int(d))
			# An elite with the chest's extra weight.
			var mc := _pack_cost([[float(ms.get("hp", 10.0)) * hp_ratio * float(GameData.bal("elite.hp_mult")) * FloorEvents.num("cursed_chest", "mimic_hp_mult", 1.0),
				float(ms.get("dps", 1.0)) * dmg_ratio * float(GameData.bal("elite.damage_mult")) * FloorEvents.num("cursed_chest", "mimic_damage_mult", 1.0)]], n)
			var m_reward := _event_reward("cursed", il, int(d), rarity_gold)
			var m_value: float = m_reward / maxf(mc.x, 1.0) / maxf(floor_rate, 0.01)
			print("[balance] events %s %d %d | %.0fs %.2f %.1f | %.0fs %.2f %.2f %.0f x%.2f | %.0fs %.2f %.0f x%.2f" % [p.class_id, d, n,
				base.time, base.damage, floor_rate, a_time, a_dmg, max_wave, a_reward, a_value, mc.x, mc.y / n / p.health.max_hp, m_reward, m_value])
			if a_value < vmin or a_value > vmax:
				bad.append("arena@%d x%d value x%.2f" % [d, n, a_value])
			if m_value < vmin or m_value > vmax:
				bad.append("mimic@%d x%d value x%.2f" % [d, n, m_value])
			if mc.y / n / p.health.max_hp >= 1.0:
				bad.append("mimic@%d x%d deals %.2f of a hero's health" % [d, n, mc.y / n / p.health.max_hp])
			if max_wave >= 1.0:
				bad.append("arena@%d x%d a wave deals %.2f of a hero's health" % [d, n, max_wave])
	da.check(bad.is_empty(), "%s: the arena and the mimic pay x%.1f-x%.1f of the floor's rate and no wave kills (outside: %s)" % [p.class_id, vmin, vmax, bad])


## One pack fought at once by `n` probe heroes (as floor_cost does): Vector2(time s, damage).
func _pack_cost(pack: Array, n: int) -> Vector2:
	pack.sort_custom(func(a, b): return a[0] < b[0])
	var t := 0.0
	var dmg := 0.0
	for mon in pack:
		t += float(mon[0]) / maxf(float(n), 0.01)
		dmg += float(mon[1]) * t
	return Vector2(t, dmg)


## The average gold value of an event's reward: its items at rarity_gold and its gold pile.
func _event_reward(source: String, il: int, depth: int, rarity_gold: Array) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = depth * 31 + source.length()
	var total := 0.0
	var runs := 300
	for i in runs:
		for it in LootTable.roll(source, il, depth, ["warrior"], rng):
			if str(it.get("kind", "")) == "gold":
				total += int(it.amount)
			elif it.has("rarity"):
				total += float(rarity_gold[clampi(int(it.rarity) - 1, 0, rarity_gold.size() - 1)])
	return total / runs


## #76 The legendary story read in full (+5 talent points, +25 stat points into the main stat) on a
## hero of the probe's curve, against a floor's monsters: the cycle is worth having but never
## breaks the pacing bands - every monster of the probe depths still takes at least
## probe.cycle_ttk_min of its usual time to kill, and the hero survives at most cycle_ttd_max x.
func run_cycle(depths: Array = [6, 12, 20]) -> void:
	g = da._game()
	p = da._local()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var curve := run_progression(20)
	seed(76)
	var probe: Dictionary = GameData.bal("probe", {})
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(70, 0))
	var chapters := LoreCycle.chapters().size()
	var tp := 0
	var sp := 0
	for id in LoreCycle.chapters():
		tp += int(GameData.lore_books[id].effect.get("talent_points", 0))
		sp += int(GameData.lore_books[id].effect.get("stat_points", 0))
	var bad: Array = []
	var rows: Array = []
	for d in depths:
		_rng.seed = 11 + int(d)
		_gear_up(_curve_level(curve, int(d)), int(d))
		g.depth = int(d)
		var biome: String = g.floor_type_for(int(d))
		var ids: Array = GameData.floor_types[biome].monsters.map(func(m): return str(m.id)).filter(func(id): return DungeonGenerator.spawnable(id, int(d)) and not GameData.monsters[id].get("role", "") in ["illusion", "boss_part"])
		ids.sort()
		var id: String = ids[0]
		var base := await _measure(id, spot, false)
		_rng.seed = 11 + int(d)
		_gear_up(_curve_level(curve, int(d)), int(d))
		p.allocated[MAIN_STAT[p.class_id]] = int(p.allocated.get(MAIN_STAT[p.class_id], 0)) + sp
		p.recompute_stats()
		p.health.hp = p.health.max_hp
		var full := await _measure(id, spot, false)
		var k := float(full.ttk) / maxf(float(base.ttk), 0.01)
		var t := float(full.ttd) / maxf(float(base.ttd), 0.01)
		rows.append("%d %s ttk x%.2f ttd x%.2f" % [d, id, k, t])
		if k < float(probe.get("cycle_ttk_min", 0.75)) or t > float(probe.get("cycle_ttd_max", 1.35)):
			bad.append(rows[-1])
	print("[balance] cycle %s (%d chapters, +%d talent, +%d stat): %s" % [p.class_id, chapters, tp, sp, rows])
	da.check(chapters == 5 and tp == 5 and sp == 25 and bad.is_empty(), "%s: the full legendary story (+%d talent, +%d stat points) helps without breaking the pacing (%s)" % [p.class_id, tp, sp, rows])
