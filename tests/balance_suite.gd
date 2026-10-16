class_name BalanceSuite
extends RefCounted
## Balance probe (scenario "balance", solo host, --class=<id>): a hero of level = depth in rare
## gear of that item level, with every stat point in the class's main stat, meets every monster of
## the depth's biome (and the biome's bosses). For each pair it measures, with the real host damage
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


func run(depths: Array = [1, 2, 3, 4, 5, 8, 12, 16, 20]) -> void:
	g = da._game()
	p = da._local()
	_rng.seed = 11
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
		_gear_up(int(d))
		g.depth = int(d)
		var biome: String = g.floor_type_for(int(d))
		var ids: Array = GameData.monsters.keys().filter(func(id): return str(GameData.monsters[id].get("biome", "")) == biome)
		ids.sort()
		for id in ids:
			var def: Dictionary = GameData.monsters[id]
			if str(def.get("role", "")) in ["illusion", "boss_part"] or GameData.bosses.has(id):
				continue
			var row := await _measure(str(id), spot, false)
			if row.is_empty():
				continue
			var critter: bool = float(def.base_stats.hp) <= float(probe.get("critter_hp_max", 20.0))  # one-hit swarm by design
			if row.ttk > float(probe.get("normal_ttk_max", 12.0)) or (row.ttk < float(probe.get("normal_ttk_min", 0.3)) and not critter) \
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


## Rare (tier 3) gear of item level = depth and level = depth with all points in the main stat.
func _gear_up(level: int) -> void:
	p.level = level
	p.allocated = {MAIN_STAT[p.class_id]: 5 * (level - 1)}
	var eq := {}
	var gear: Dictionary = GEAR[p.class_id].duplicate()
	gear.merge(COMMON_GEAR)
	for slot in gear:
		eq[slot] = ItemGenerator.generate_equipment(str(gear[slot]), level, 3, _rng)
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
	var n := 24
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
