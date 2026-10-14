class_name ItemGenerator
extends RefCounted
## Creates item dictionaries (plain data, so they serialize into saves and RPCs as-is).
##
## Equipment item: {uid, base, kind, slot, hands, name, rarity, ilvl, req, armor, dps,
##   stats: {stat: value}, classes, appearance, tint, icon}
## Consumable:     {uid, base, kind: "consumable", name, icon, count, rarity: 1}
## Backpack:       {uid, base: "backpack", kind: "backpack", name, icon, capacity, rarity}

static var _uid_counter := 0


static func new_uid(rng: RandomNumberGenerator) -> String:
	_uid_counter += 1
	return "%x%x" % [rng.randi(), _uid_counter]


static func roll_rarity(rng: RandomNumberGenerator, bonus: float, min_tier: int) -> int:
	var weights: Array = GameData.bal("loot.rarity_weights")
	var adjusted: Array = []
	for i in weights.size():
		# Depth bonus shifts weight from common toward the higher tiers.
		adjusted.append(float(weights[i]) * (1.0 + bonus * i * 2.0) if i > 0 else float(weights[i]) * maxf(0.2, 1.0 - bonus * 3.0))
	var tier := _weighted_index(adjusted, rng) + 1
	return maxi(tier, min_tier)


static func generate_equipment(base_id: String, item_level: int, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = GameData.item_bases[base_id]
	var rar := GameData.rarity(tier)
	var mult := float(rar.base_mult)
	var lvl := maxi(item_level, 1)
	var item := {
		"uid": new_uid(rng), "base": base_id, "kind": base.kind, "slot": base.slot,
		"hands": int(base.get("hands", 1)), "rarity": tier, "ilvl": lvl, "req": lvl,
		"classes": base.get("classes", []), "appearance": base.get("appearance", ""),
		"tint": base.get("tint", "#ffffff"), "icon": base.icon, "stats": {},
	}
	if base.has("dps"):
		var d: Array = base.dps
		item.dps = snappedf((rng.randf_range(float(d[0]), float(d[1])) + float(base.get("dps_per_level", 0.0)) * (lvl - 1)) * mult, 0.1)
	if base.has("armor"):
		var a: Array = base.armor
		item.armor = roundi((rng.randf_range(float(a[0]), float(a[1])) + float(base.get("armor_per_level", 0.0)) * (lvl - 1)) * mult)
	# Common items carry only armor / DPS; implicit base stats start at Uncommon.
	if tier >= 2:
		for k in base.get("base_stats", {}):
			var r: Array = base.base_stats[k]
			item.stats[k] = roundi(rng.randf_range(float(r[0]), float(r[1])) * (1.0 + 0.1 * (lvl - 1)))
	var suffix := ""
	var growth := float(GameData.affixes.get("level_growth", 0.1))
	for group in ["primary", "secondary"]:
		var range_: Array = rar[group]
		var count := rng.randi_range(int(range_[0]), int(range_[1]))
		var pool: Array = GameData.affixes[group].duplicate()
		for i in count:
			if pool.is_empty():
				break
			var af: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			var v := rng.randf_range(float(af.min), float(af.max)) * (1.0 + growth * (lvl - 1)) + float(af.per_level) * (lvl - 1) * 0.5
			v *= mult
			var is_pct := Array(GameData.affixes.percent_stats).has(af.stat)
			v = snappedf(v, 0.005) if is_pct else float(roundi(v))
			item.stats[af.stat] = float(item.stats.get(af.stat, 0.0)) + v
			if suffix.is_empty():
				suffix = af.suffix
	item.name = base.name if suffix.is_empty() else "%s %s" % [base.name, suffix]
	return item


static func generate_consumable(id: String, count: int, rng: RandomNumberGenerator) -> Dictionary:
	var c: Dictionary = GameData.consumables[id]
	return {"uid": new_uid(rng), "base": id, "kind": "consumable", "name": c.name, "icon": c.icon,
		"count": count, "rarity": 1}


static func generate_backpack(depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = GameData.item_bases["backpack"]
	var caps: Array = base.capacities
	var idx := clampi(rng.randi_range(0, 1) + depth / 3, 0, caps.size() - 1)
	return {"uid": new_uid(rng), "base": "backpack", "kind": "backpack", "name": "%s (%d slots)" % [base.name, int(caps[idx])],
		"icon": base.icon, "capacity": int(caps[idx]), "rarity": clampi(idx + 2, 2, 5)}


## Human-readable tooltip lines: [text, color].
static func describe(item: Dictionary, class_id: String = "") -> Array:
	var lines: Array = []
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	lines.append([item.get("name", "?"), Color.from_string(rar.color, Color.WHITE)])
	match item.get("kind", ""):
		"consumable":
			var c: Dictionary = GameData.consumables.get(item.base, {})
			lines.append(["Consumable  x%d" % int(item.get("count", 1)), Color(0.7, 0.7, 0.7)])
			lines.append([c.get("description", ""), Color(0.85, 0.85, 0.8)])
			return lines
		"backpack":
			lines.append(["Backpack: %d slots (pick up to equip)" % int(item.capacity), Color(0.85, 0.85, 0.8)])
			return lines
	var slot_name: String = item.get("slot", "")
	var kind_txt := "%s %s" % [rar.name, slot_name.capitalize()]
	if item.get("kind") == "weapon":
		kind_txt += " (%s)" % ("Two-handed" if int(item.get("hands", 1)) == 2 else "One-handed")
	lines.append([kind_txt, Color(0.7, 0.7, 0.7)])
	if item.has("dps"):
		lines.append(["%.1f DPS" % float(item.dps), Color(1, 1, 1)])
	if item.has("armor") and int(item.armor) > 0:
		lines.append(["%d Armor" % int(item.armor), Color(1, 1, 1)])
	var names: Dictionary = GameData.affixes.stat_names
	for k in item.get("stats", {}):
		var v := float(item.stats[k])
		var txt := "+%d%% %s" % [roundi(v * 100.0), names.get(k, k)] if Array(GameData.affixes.percent_stats).has(k) else "+%d %s" % [int(v), names.get(k, k)]
		lines.append([txt, Color(0.55, 0.9, 0.55)])
	lines.append(["Requires level %d" % int(item.get("req", 1)), Color(0.75, 0.75, 0.75)])
	var classes: Array = item.get("classes", [])
	if not classes.is_empty():
		var cnames: Array = []
		for c in classes:
			cnames.append(GameData.classes.get(c, {}).get("name", c))
		var ok := class_id.is_empty() or classes.has(class_id)
		var penalty := "  (-%d%% damage, slower cooldowns for you)" % roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100.0)
		lines.append(["Class: %s%s" % [", ".join(cnames), "" if ok else penalty],
			Color(0.75, 0.75, 0.75) if ok else Color(0.95, 0.4, 0.35)])
	return lines


static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1
