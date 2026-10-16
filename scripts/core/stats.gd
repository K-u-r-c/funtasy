class_name Stats
extends Node
## Computes an actor's final stats: class base + level + allocated points + equipment + talents +
## passives + run modifiers + buffs + penalties (players) or monster definition + level/party
## scaling + elite modifiers (monsters). The rest of the game only reads `final` (host computes it;
## it is replicated to clients for the UI) and `skill_mods` (per-skill modifiers, "*" = all skills).
##
## Modifiers go into three buckets per key: `add` (flat), `pct` (summed percent) and `mul`
## (product). A stat ends up as (base + add) x (1 + pct) x mul.
## - Mod lists (talents, passives, legendaries, run modifiers: [{stat, value}]): keys ending in
##   `_pct` or `_mult` add to `pct` (so "+10% damage" ranks stack additively), others add flat.
## - Status effects ({key: value}): keys ending in `_mult` multiply, others add flat.

const PRIMARY := ["strength", "stamina", "agility", "intellect"]
## Pure multipliers exposed as `<key>_mult` in `final` (1.0 when nothing modifies them).
const MULTS := ["damage", "damage_taken", "healing", "healing_taken", "threat", "cooldown", "cost",
	"resource_regen", "resource_gen", "range", "melee_damage", "ranged_damage", "spell_damage",
	"boss_damage", "melee_damage_taken", "ranged_damage_taken", "spell_damage_taken", "cc_duration",
	"attack_speed", "scale"]

var final: Dictionary = {}
var skill_mods: Dictionary = {}


func get_stat(key: String, fallback: float = 0.0) -> float:
	var v: Variant = final.get(key, fallback)
	return float(v) if (v is float or v is int) else fallback


## Multiplier stat, e.g. mult("damage") -> final.damage_mult (1.0 when absent).
func mult(key: String) -> float:
	return get_stat(key + "_mult", 1.0)


func has_flag(flag: String) -> bool:
	return Array(final.get("flags", [])).has(flag)


class Buckets:
	var add := {}
	var pct := {}
	var mul := {}
	var flags := {}

	func a(k: String, v: float) -> void:
		add[k] = float(add.get(k, 0.0)) + v

	func p(k: String, v: float) -> void:
		pct[k] = float(pct.get(k, 0.0)) + v

	func m(k: String, v: float) -> void:
		mul[k] = float(mul.get(k, 1.0)) * v

	## One entry of a mod list ({stat, value} x rank): _pct/_mult are additive percents.
	func mod(stat: String, v: float) -> void:
		if stat.ends_with("_pct"):
			p(stat.trim_suffix("_pct"), v)
		elif stat.ends_with("_mult"):
			p(stat.trim_suffix("_mult"), v)
		else:
			a(stat, v)

	## A {key: value} dict from a status effect: _mult multiplies, others add.
	func status(stats: Dictionary, times: float = 1.0) -> void:
		for k in stats:
			var key := str(k)
			var v := float(stats[k])
			if key.ends_with("_mult"):
				m(key.trim_suffix("_mult"), pow(v, times))
			else:
				a(key, v * times)

	func val(k: String, base: float) -> float:
		return (base + float(add.get(k, 0.0))) * (1.0 + float(pct.get(k, 0.0))) * float(mul.get(k, 1.0))

	func factor(k: String) -> float:
		return (1.0 + float(pct.get(k, 0.0))) * float(mul.get(k, 1.0))


## `extra` (all optional): allocated {stat: points}, run_mods [{stat, value}], mods [{stat, value}]
## (passive skills, keystones, legendaries), flags [..].
func compute_player(class_def: Dictionary, level: int, equipment: Dictionary, talents: Dictionary, status_mods: Dictionary, extra: Dictionary = {}) -> void:
	var b := Buckets.new()
	var base: Dictionary = class_def.base_stats
	var per: Dictionary = class_def.per_level
	var s := {}
	for k in PRIMARY:
		b.a(k, float(base.get(k, 0)) + float(per.get(k, 0)) * (level - 1))
	for k in extra.get("allocated", {}):
		b.a(str(k), float(extra.allocated[k]))
	b.a("crit_chance", float(GameData.bal("stats.base_crit_chance")))
	b.a("crit_damage", float(GameData.bal("stats.base_crit_damage")))
	var main_dps := 0.0
	var off_dps := 0.0
	var item_skill_mods: Array = []
	var offclass := false
	for slot in equipment:
		var item: Dictionary = equipment[slot]
		if item.is_empty():
			continue
		b.a("armor", float(item.get("armor", 0)))
		for k in item.get("stats", {}):
			b.mod(str(k), float(item.stats[k]))
		for m in item.get("mods", []):
			if m.has("skill"):
				item_skill_mods.append(m)
			else:
				b.mod(str(m.stat), float(m.value))
		for f in item.get("flags", []):
			b.flags[f] = true
		if item.get("kind") == "weapon":
			if slot == "main_hand":
				main_dps = float(item.get("dps", 0))
			elif slot == "off_hand":
				off_dps = float(item.get("dps", 0))
		if item.get("kind") in ["weapon", "offhand"] and not Array(item.get("classes", [])).has(class_def.id):
			offclass = true
	skill_mods = skill_mods_for(class_def, talents, extra.get("skill_mods", []) + item_skill_mods)
	var tree: Dictionary = GameData.talents.get(class_def.id, {})
	for node in tree.get("nodes", []):
		var rank := int(talents.get(node.id, 0))
		if rank <= 0:
			continue
		for m in node.get("mods", []):
			if not m.has("skill"):
				b.mod(str(m.stat), float(m.value) * rank)
		for f in node.get("flags", []):
			b.flags[f] = true
	for m in extra.get("mods", []):
		if not m.has("skill"):
			b.mod(str(m.stat), float(m.value))
	for m in extra.get("run_mods", []):
		b.mod(str(m.stat), float(m.value))
	for f in extra.get("flags", []):
		b.flags[f] = true
	_status_into(b, status_mods)

	for k in PRIMARY:
		s[k] = maxf(b.val(k, 0.0), 0.0)
	s.armor = maxf(b.val("armor", 0.0), 0.0)
	var unarmed := float(GameData.bal("stats.unarmed_dps"))
	s.weapon_dps = (main_dps if main_dps > 0.0 else unarmed) + off_dps * 0.5 + float(b.add.get("weapon_dps", 0.0))
	var hp_base: float = float(class_def.base_hp) + s.stamina * float(GameData.bal("stats.hp_per_stamina"))
	s.max_hp = maxf(b.val("max_hp", hp_base), 1.0)
	if class_def.resource == "mana":
		var mana_base: float = float(class_def.base_resource) + s.intellect * float(GameData.bal("stats.mana_per_intellect"))
		s.max_resource = b.val("max_resource", mana_base)
		if b.flags.has("mana_to_armor"):
			s.armor += s.max_resource * 0.15  # Signet of the Iron Zealot
		s.resource_regen = (float(GameData.bal("stats.mana_regen_base")) + s.intellect * float(GameData.bal("stats.mana_regen_per_intellect")) + float(b.add.get("mana_regen", 0.0))) * b.factor("resource_regen")
	else:
		s.max_resource = float(GameData.bal("fury.max"))
		s.resource_regen = 0.0
	s.crit_chance = float(b.add.get("crit_chance", 0.0)) + s.agility * float(GameData.bal("stats.crit_per_agility"))
	s.crit_damage = b.val("crit_damage", 0.0)
	s.power_melee = s.weapon_dps + s.strength * float(GameData.bal("stats.melee_power_per_strength")) + float(b.add.get("melee_power", 0.0))
	if b.flags.has("armor_to_power"):
		s.power_melee += s.armor * 0.2  # Ymir's Blood Drop
	s.power_ranged = s.weapon_dps + s.agility * float(GameData.bal("stats.ranged_power_per_agility")) + float(b.add.get("ranged_power", 0.0))
	s.power_spell = s.weapon_dps + s.intellect * float(GameData.bal("stats.spell_power_per_intellect")) + float(b.add.get("spell_power", 0.0))
	s.strength_reduction = s.strength * float(GameData.bal("stats.damage_reduction_per_strength"))
	s.offclass = offclass
	_secondaries(s, b)
	if offclass:
		s.damage_mult *= float(GameData.bal("off_class.damage_mult"))
		s.cooldown_mult *= float(GameData.bal("off_class.cooldown_mult"))
	s.threat_mult *= float(class_def.get("threat_mult", 1.0))
	s.move_speed = (float(GameData.bal("player.move_speed")) + float(b.add.get("move_speed", 0.0))) * b.factor("move_speed")
	s.level = level
	s.flags = b.flags.keys()
	_clamp(s)
	final = s


## `extra` (optional): mods [{stat, value}] and stats {key: value} from elite modifiers.
func compute_monster(def: Dictionary, level: int, hp_mult: float, dmg_mult: float, status_mods: Dictionary, extra: Dictionary = {}) -> void:
	var bs: Dictionary = def.base_stats
	var b := Buckets.new()
	for m in extra.get("mods", []):
		b.mod(str(m.stat), float(m.value))
	b.status(extra.get("stats", {}))
	_status_into(b, status_mods)
	var s := {}
	s.level = level
	s.max_hp = maxf(b.val("max_hp", float(bs.hp) * hp_mult), 1.0)
	var power := float(bs.damage) * dmg_mult
	s.power_melee = power
	s.power_ranged = power
	s.power_spell = power + float(b.add.get("spell_power", 0.0))
	s.weapon_dps = power
	s.armor = maxf(b.val("armor", float(bs.get("armor", 0)) * (1.0 + 0.1 * (level - 1))), 0.0)
	b.a("crit_chance", float(bs.get("crit_chance", 0.05)))
	b.a("crit_damage", float(GameData.bal("stats.base_crit_damage")))
	b.a("dodge", float(bs.get("dodge", 0.0)))
	b.a("magic_resist", float(bs.get("magic_resist", 0.0)))
	s.crit_chance = float(b.add.get("crit_chance", 0.0))
	s.crit_damage = b.val("crit_damage", 0.0)
	s.strength_reduction = 0.0
	s.max_resource = 0.0
	s.resource_regen = 0.0
	_secondaries(s, b)
	s.move_speed = (float(bs.move_speed) + float(b.add.get("move_speed", 0.0))) * b.factor("move_speed")
	s.flags = b.flags.keys()
	_clamp(s)
	final = s


func _status_into(b: Buckets, status_mods: Dictionary) -> void:
	for k in status_mods:
		if str(k) == "flags":
			for f in status_mods.flags:
				b.flags[f] = true
	var plain := status_mods.duplicate()
	plain.erase("flags")
	b.status(plain)


## Secondary stats and multipliers shared by players and monsters.
func _secondaries(s: Dictionary, b: Buckets) -> void:
	for k in ["haste", "dodge", "leech", "miss_chance", "block_chance", "block_value", "magic_resist",
			"magic_pen", "armor_pen", "dodge_physical", "reflect_melee", "thorns"]:
		s[k] = float(b.add.get(k, 0.0)) * b.factor(k)
	for k in MULTS:
		s[k + "_mult"] = b.factor(k)
	# Per damage type multipliers (fire_damage_mult, ...) and any other multiplier a mod named.
	for k in b.pct.keys() + b.mul.keys():
		if not s.has(k) and not s.has(k + "_mult") and not PRIMARY.has(k) and k not in ["armor", "max_hp", "max_resource", "move_speed", "crit_damage", "resource_regen"]:
			s[k + "_mult"] = b.factor(k)
	# Flat bonuses that don't fit a bucket formula are passed through (e.g. spell_power).
	for k in b.add:
		if not s.has(k) and not PRIMARY.has(k):
			s[k] = float(b.add[k])


func _clamp(s: Dictionary) -> void:
	s.dodge = clampf(float(s.get("dodge", 0.0)), 0.0, float(GameData.bal("stats.max_dodge")))
	s.haste = clampf(float(s.get("haste", 0.0)), -0.5, float(GameData.bal("stats.max_haste")))
	s.crit_chance = clampf(float(s.get("crit_chance", 0.0)), 0.0, 1.0)
	s.leech = maxf(float(s.get("leech", 0.0)), 0.0)
	s.block_chance = clampf(float(s.get("block_chance", 0.0)), 0.0, float(GameData.bal("stats.max_block", 0.75)))
	s.magic_resist = clampf(float(s.get("magic_resist", 0.0)), -1.0, float(GameData.bal("stats.max_magic_resist", 0.75)))
	s.miss_chance = clampf(float(s.get("miss_chance", 0.0)), 0.0, 1.0)


## Per-skill modifiers ({skill: {field: summed value}}) from talents plus extra mod entries that
## name a skill (passives, legendaries). Static so any peer can rebuild them from the replicated
## talents (clients only receive `final`).
static func skill_mods_for(class_def: Dictionary, talents: Dictionary, extra_mods: Array = []) -> Dictionary:
	var out := {}
	var tree: Dictionary = GameData.talents.get(class_def.get("id", ""), {})
	for node in tree.get("nodes", []):
		var rank := int(talents.get(node.id, 0))
		if rank <= 0:
			continue
		for m in node.get("mods", []):
			if m.has("skill"):
				_add_skill_mod(out, m, rank)
	for m in extra_mods:
		if m.has("skill"):
			_add_skill_mod(out, m, 1)
	return out


static func _add_skill_mod(out: Dictionary, m: Dictionary, rank: int) -> void:
	for sid in (m.skill if m.skill is Array else [m.skill]):
		var sm: Dictionary = out.get(sid, {})
		sm[m.field] = float(sm.get(m.field, 0.0)) + float(m.value) * rank
		out[sid] = sm


func skill_mod(skill_id: String, field: String) -> float:
	var v := 0.0
	if skill_mods.has(skill_id):
		v += float(skill_mods[skill_id].get(field, 0.0))
	if skill_mods.has("*"):
		v += float(skill_mods["*"].get(field, 0.0))
	return v


## Effective cooldown after haste, talents, statuses and the off-class penalty.
func cooldown_for(skill: Dictionary) -> float:
	var cd := float(skill.cooldown) * (1.0 + skill_mod(skill.id, "cooldown_mult"))
	cd *= mult("cooldown")
	cd -= skill_mod(skill.id, "cooldown_flat")
	cd /= (1.0 + get_stat("haste"))
	return maxf(cd, 0.1)


func cost_for(skill: Dictionary) -> float:
	var c := float(skill.get("cost", 0)) * (1.0 + skill_mod(skill.id, "cost_mult"))
	if str(skill.get("school", "")) == "spell":
		c *= mult("spell_cost")
	return maxf(c * mult("cost"), 0.0)


func power_for(school: String) -> float:
	match school:
		"melee":
			return get_stat("power_melee")
		"ranged":
			return get_stat("power_ranged")
	return get_stat("power_spell")
