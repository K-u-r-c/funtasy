class_name Stats
extends Node
## Computes an actor's final stats: class base + level + equipment + talents + buffs +
## penalties (players) or monster definition + level/party scaling (monsters).
## The rest of the game only reads `final` (host computes it; it is replicated to clients for
## the UI) and `skill_mods` (talent modifiers per skill id, "*" = all skills).

var final: Dictionary = {}
var skill_mods: Dictionary = {}


func get_stat(key: String, fallback: float = 0.0) -> float:
	return float(final.get(key, fallback))


func compute_player(class_def: Dictionary, level: int, equipment: Dictionary, talents: Dictionary, status_mods: Dictionary) -> void:
	var s := {}
	var base: Dictionary = class_def.base_stats
	var per: Dictionary = class_def.per_level
	for k in ["strength", "stamina", "agility", "intellect"]:
		s[k] = float(base.get(k, 0)) + float(per.get(k, 0)) * (level - 1)
	s.armor = 0.0
	s.crit_chance = float(GameData.bal("stats.base_crit_chance"))
	s.crit_damage = float(GameData.bal("stats.base_crit_damage"))
	for k in ["haste", "dodge", "leech"]:
		s[k] = 0.0
	var main_dps := 0.0
	var off_dps := 0.0
	var offclass := false
	for slot in equipment:
		var item: Dictionary = equipment[slot]
		if item.is_empty():
			continue
		s.armor += float(item.get("armor", 0))
		for k in item.get("stats", {}):
			s[k] = float(s.get(k, 0.0)) + float(item.stats[k])
		if item.get("kind") == "weapon":
			if slot == "main_hand":
				main_dps = float(item.get("dps", 0))
			elif slot == "off_hand":
				off_dps = float(item.get("dps", 0))
		if item.get("kind") in ["weapon", "offhand"] and not Array(item.get("classes", [])).has(class_def.id):
			offclass = true

	# Talents: "*_pct" multiply a stat, others add. Skill modifiers are summed per skill.
	var pct := {}
	var mult := {"damage_mult": 1.0, "damage_taken_mult": 1.0, "healing_mult": 1.0, "threat_mult": float(class_def.get("threat_mult", 1.0)),
		"move_speed_mult": 1.0, "resource_regen_mult": 1.0}
	skill_mods = {}
	var tree: Dictionary = GameData.talents.get(class_def.id, {})
	for node in tree.get("nodes", []):
		var rank := int(talents.get(node.id, 0))
		if rank <= 0:
			continue
		for m in node.mods:
			var v := float(m.value) * rank
			if m.has("skill"):
				var sm: Dictionary = skill_mods.get(m.skill, {})
				sm[m.field] = float(sm.get(m.field, 0.0)) + v
				skill_mods[m.skill] = sm
			else:
				match str(m.stat):
					"strength_pct", "stamina_pct", "agility_pct", "intellect_pct", "armor_pct", "max_hp_pct":
						pct[m.stat] = float(pct.get(m.stat, 0.0)) + v
					"move_speed_pct":
						mult.move_speed_mult += v
					"resource_regen_pct":
						mult.resource_regen_mult += v
					"healing_mult":
						mult.healing_mult += v
					"threat_mult":
						mult.threat_mult += v
					"damage_taken_pct":
						mult.damage_taken_mult += v
					"damage_mult":
						mult.damage_mult += v
					_:
						s[m.stat] = float(s.get(m.stat, 0.0)) + v
	for k in ["strength", "stamina", "agility", "intellect", "armor"]:
		s[k] = s[k] * (1.0 + float(pct.get(k + "_pct", 0.0)))

	for k in status_mods:
		if str(k).ends_with("_mult"):
			mult[k] = float(mult.get(k, 1.0)) * float(status_mods[k])
		else:
			s[k] = float(s.get(k, 0.0)) + float(status_mods[k])

	var unarmed := float(GameData.bal("stats.unarmed_dps"))
	s.weapon_dps = (main_dps if main_dps > 0.0 else unarmed) + off_dps * 0.5
	s.max_hp = (float(class_def.base_hp) + s.stamina * float(GameData.bal("stats.hp_per_stamina"))) * (1.0 + float(pct.get("max_hp_pct", 0.0)))
	if class_def.resource == "mana":
		s.max_resource = float(class_def.base_resource) + s.intellect * float(GameData.bal("stats.mana_per_intellect"))
		s.resource_regen = (float(GameData.bal("stats.mana_regen_base")) + s.intellect * float(GameData.bal("stats.mana_regen_per_intellect"))) * mult.resource_regen_mult
	else:
		s.max_resource = float(GameData.bal("fury.max"))
		s.resource_regen = 0.0
	s.crit_chance += s.agility * float(GameData.bal("stats.crit_per_agility"))
	s.power_melee = s.weapon_dps + s.strength * float(GameData.bal("stats.melee_power_per_strength"))
	s.power_ranged = s.weapon_dps + s.agility * float(GameData.bal("stats.ranged_power_per_agility"))
	s.power_spell = s.weapon_dps + s.intellect * float(GameData.bal("stats.spell_power_per_intellect"))
	s.strength_reduction = s.strength * float(GameData.bal("stats.damage_reduction_per_strength"))
	s.offclass = offclass
	s.damage_mult = mult.damage_mult * (float(GameData.bal("off_class.damage_mult")) if offclass else 1.0)
	s.cooldown_mult = float(GameData.bal("off_class.cooldown_mult")) if offclass else 1.0
	s.damage_taken_mult = mult.damage_taken_mult
	s.healing_mult = mult.healing_mult
	s.threat_mult = mult.threat_mult
	s.move_speed = float(GameData.bal("player.move_speed")) * mult.move_speed_mult
	s.level = level
	_clamp(s)
	final = s


func compute_monster(def: Dictionary, level: int, hp_mult: float, dmg_mult: float, status_mods: Dictionary) -> void:
	var b: Dictionary = def.base_stats
	var s := {}
	s.level = level
	s.max_hp = float(b.hp) * hp_mult
	var power := float(b.damage) * dmg_mult
	s.power_melee = power
	s.power_ranged = power
	s.power_spell = power
	s.weapon_dps = power
	s.armor = float(b.get("armor", 0)) * (1.0 + 0.1 * (level - 1))
	s.crit_chance = float(b.get("crit_chance", 0.05))
	s.crit_damage = float(GameData.bal("stats.base_crit_damage"))
	s.dodge = float(b.get("dodge", 0.0))
	s.haste = 0.0
	s.leech = 0.0
	s.strength_reduction = 0.0
	s.damage_mult = 1.0
	s.damage_taken_mult = 1.0
	s.healing_mult = 1.0
	s.threat_mult = 1.0
	s.cooldown_mult = 1.0
	s.move_speed = float(b.move_speed)
	s.max_resource = 0.0
	s.resource_regen = 0.0
	for k in status_mods:
		if str(k).ends_with("_mult"):
			var base_key := str(k).trim_suffix("_mult")
			if base_key == "move_speed":
				s.move_speed *= float(status_mods[k])
			else:
				s[k] = float(s.get(k, 1.0)) * float(status_mods[k])
		else:
			s[k] = float(s.get(k, 0.0)) + float(status_mods[k])
	_clamp(s)
	final = s


func _clamp(s: Dictionary) -> void:
	s.dodge = clampf(float(s.get("dodge", 0.0)), 0.0, float(GameData.bal("stats.max_dodge")))
	s.haste = clampf(float(s.get("haste", 0.0)), -0.5, float(GameData.bal("stats.max_haste")))
	s.crit_chance = clampf(float(s.get("crit_chance", 0.0)), 0.0, 1.0)
	s.leech = maxf(float(s.get("leech", 0.0)), 0.0)


## Talent modifier for a skill field, summed with the "*" wildcard.
func skill_mod(skill_id: String, field: String) -> float:
	var v := 0.0
	if skill_mods.has(skill_id):
		v += float(skill_mods[skill_id].get(field, 0.0))
	if skill_mods.has("*"):
		v += float(skill_mods["*"].get(field, 0.0))
	return v


## Effective cooldown after haste, talents and the off-class penalty.
func cooldown_for(skill: Dictionary) -> float:
	var cd := float(skill.cooldown) * (1.0 + skill_mod(skill.id, "cooldown_mult"))
	cd *= get_stat("cooldown_mult", 1.0)
	cd /= (1.0 + get_stat("haste"))
	return maxf(cd, 0.1)


func cost_for(skill: Dictionary) -> float:
	return maxf(float(skill.get("cost", 0)) * (1.0 + skill_mod(skill.id, "cost_mult")), 0.0)


func power_for(school: String) -> float:
	match school:
		"melee":
			return get_stat("power_melee")
		"ranged":
			return get_stat("power_ranged")
	return get_stat("power_spell")
