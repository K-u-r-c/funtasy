class_name ItemGenerator
extends RefCounted
## Creates item dictionaries (plain data, so they serialize into saves and RPCs as-is).
##
## Equipment item: {uid, base, kind, slot, hands, name, rarity, ilvl, req, armor, dps,
##   stats: {stat: value}, classes, appearance, tint, icon}
## Consumable:     {uid, base, kind: "consumable", name, icon, count, rarity: 1}
## Backpack:       {uid, base: "backpack", kind: "backpack", name, icon, capacity, rarity}

## Slot names in the item kind line ("Rare Head"), as translation keys.
const SLOT_LABELS := {"head": "Head", "chest": "Chest", "legs": "Legs", "boots": "Boots", "gloves": "Gloves",
	"main_hand": "Main Hand", "off_hand": "Off Hand", "offhand": "Off Hand", "weapon": "Weapon", "ring": "Ring", "necklace": "Necklace"}

static var _uid_counter := 0


static func new_uid(rng: RandomNumberGenerator) -> String:
	_uid_counter += 1
	return "%x%x" % [rng.randi(), _uid_counter]


static func roll_rarity(rng: RandomNumberGenerator, depth: int, min_tier: int) -> int:
	var tier := _weighted_index(rarity_weights_at(depth), rng) + 1
	return maxi(tier, min_tier)


## #65: the drop rarity weights on floor `depth`: very slowly from the floor-1 weights toward the
## deep ones (balance loot.rarity_weights / rarity_weights_deep / rarity_deep_depth).
static func rarity_weights_at(depth: int) -> Array:
	var shallow: Array = GameData.bal("loot.rarity_weights")
	var deep: Array = GameData.bal("loot.rarity_weights_deep", shallow)
	var t := clampf(float(depth - 1) / maxf(float(GameData.bal("loot.rarity_deep_depth", 50)) - 1.0, 1.0), 0.0, 1.0)
	var out: Array = []
	for i in shallow.size():
		out.append(lerpf(float(shallow[i]), float(deep[i]), t))
	return out


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
	# Worn family, icon and colour variant (#20), from the item's own uid: the look never shifts the
	# caller's stat rolls.
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = hash(str(item.uid))
	ItemLooks.apply(item, look_rng)
	# #64: the quality and the name come from the uid too (another stream, same reason).
	var name_rng := RandomNumberGenerator.new()
	name_rng.seed = hash(str(item.uid) + "#name")
	var quality := roll_quality(name_rng)
	if not quality.is_empty():
		mult *= float(quality.mult)
		item.quality = str(quality.id)
		item.quality_mult = float(quality.mult)
	# #77: the raw rolls are kept on the item, so the forge can recompute it at another level
	# exactly as if it had dropped there (the same rng draws in the same order as before).
	var rolls := {}
	if base.has("dps"):
		var d: Array = base.dps
		rolls.dps = rng.randf_range(float(d[0]), float(d[1]))
	if base.has("armor"):
		var a: Array = base.armor
		rolls.armor = rng.randf_range(float(a[0]), float(a[1]))
	# Common items carry only armor / DPS; implicit base stats start at Uncommon.
	if tier >= 2:
		rolls.base = {}
		for k in base.get("base_stats", {}):
			var r: Array = base.base_stats[k]
			rolls.base[k] = rng.randf_range(float(r[0]), float(r[1]))
	rolls.affix = []
	for group in ["primary", "secondary"]:
		var range_: Array = rar[group]
		var count := rng.randi_range(int(range_[0]), int(range_[1]))
		var pool: Array = GameData.affixes[group].duplicate()
		for i in count:
			if pool.is_empty():
				break
			var af: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			rolls.affix.append([str(af.stat), rng.randf_range(float(af.min), float(af.max)), group])
	item.rolls = rolls
	var values := apply_level(item, lvl)
	var rolled: Array = []  ## [stat, strength of the roll 0..1, primary]
	for i in rolls.affix.size():
		var af := _affix_def(str(rolls.affix[i][2]), str(rolls.affix[i][0]))
		var span := float(af.max) - float(af.min)
		rolled.append([str(af.stat), (float(values[i]) / mult - float(af.min)) / span if span > 0.0 else 0.5, rolls.affix[i][2] == "primary"])
	item.name = item_name(str(base.name), rolled, quality, name_rng)
	return item


## #77: sets a rolled item's level-dependent numbers (DPS, armor, stats, item and required level)
## for `lvl` from its kept raw rolls, the same formulas generate_equipment uses; a boon's unique
## item adds its own stats (`extra_stats`, growing by `extra_growth` per level). Returns the
## affix values in roll order.
static func apply_level(item: Dictionary, lvl: int) -> Array:
	var base: Dictionary = GameData.item_bases.get(str(item.base), {})
	var qm := float(item.get("quality_mult", 1.0))
	var mult := float(GameData.rarity(int(item.rarity)).base_mult) * qm
	var r: Dictionary = item.rolls
	item.ilvl = lvl
	item.req = lvl
	if r.has("dps"):
		item.dps = snappedf((float(r.dps) + float(base.get("dps_per_level", 0.0)) * (lvl - 1)) * mult, 0.1)
	if r.has("armor"):
		item.armor = roundi((float(r.armor) + float(base.get("armor_per_level", 0.0)) * (lvl - 1)) * mult)
	var stats := {}
	for k in r.get("base", {}):
		stats[k] = roundi(float(r.base[k]) * (1.0 + 0.1 * (lvl - 1)) * qm)
	var growth := float(GameData.affixes.get("level_growth", 0.1))
	var pct: Array = GameData.affixes.percent_stats
	var values: Array = []
	for a in r.get("affix", []):
		var af := _affix_def(str(a[2]), str(a[0]))
		var v := (float(a[1]) * (1.0 + growth * (lvl - 1)) + float(af.get("per_level", 0.0)) * (lvl - 1) * 0.5) * mult
		v = snappedf(v, 0.005) if pct.has(str(a[0])) else float(roundi(v))
		stats[str(a[0])] = float(stats.get(str(a[0]), 0.0)) + v
		values.append(v)
	var eg := float(item.get("extra_growth", 0.0))
	for k in item.get("extra_stats", {}):
		stats[k] = float(stats.get(k, 0.0)) + float(item.extra_stats[k]) * (1.0 + eg * (lvl - 1))
	item.stats = stats
	return values


static func _affix_def(group: String, stat: String) -> Dictionary:
	for af in GameData.affixes.get(group, []):
		if str(af.stat) == stat:
			return af
	return {"stat": stat, "min": 0.0, "max": 0.0, "per_level": 0.0}


## #77: a copy of gear `item` raised to item level `lvl`, its numbers recomputed as if it had
## dropped there: rarity, affixes, quality, name and a legendary's affix kept (legendaries by
## D7). An item from before the rolls were kept scales its numbers by the level growth instead.
static func at_level(item: Dictionary, lvl: int) -> Dictionary:
	var out := item.duplicate(true)
	lvl = maxi(lvl, 1)
	if out.has("legendary"):
		_legendary_numbers(out, GameData.legendaries.get(str(out.legendary), {}), lvl)
	elif out.has("rolls"):
		apply_level(out, lvl)
	else:
		var from := maxi(int(out.get("ilvl", 1)), 1)
		var g := float(GameData.affixes.get("level_growth", 0.1))
		var ratio := (1.0 + g * (lvl - 1)) / (1.0 + g * (from - 1))
		var base: Dictionary = GameData.item_bases.get(str(out.get("base", "")), {})
		var qm := float(out.get("quality_mult", 1.0)) * float(GameData.rarity(int(out.get("rarity", 1))).base_mult)
		if out.has("dps"):
			out.dps = snappedf(float(out.dps) + float(base.get("dps_per_level", 0.0)) * (lvl - from) * qm, 0.1)
		if out.has("armor"):
			out.armor = roundi(float(out.armor) + float(base.get("armor_per_level", 0.0)) * (lvl - from) * qm)
		var pct: Array = GameData.affixes.percent_stats
		for k in out.get("stats", {}):
			var v := float(out.stats[k]) * ratio
			out.stats[k] = snappedf(v, 0.005) if pct.has(k) else float(roundi(v))
		out.ilvl = lvl
		out.req = lvl
	return out


## #64: a better-made item (data "qualities", best first), or {} for an ordinary one.
static func roll_quality(rng: RandomNumberGenerator) -> Dictionary:
	for q in GameData.affixes.get("qualities", []):
		if rng.randf() < float(q.chance):
			return q
	return {}


## #64: "[Prefix] Base [suffix]": the prefix from the quality, the suffix from the strongest rolled
## primary stat - or the pair of the two strongest when there are two - else the strongest
## secondary, each picked from its pool (affixes.json suffix_pools).
static func item_name(base_name: String, rolled: Array, quality: Dictionary, rng: RandomNumberGenerator) -> String:
	var pools: Dictionary = GameData.affixes.get("suffix_pools", {})
	var prim := rolled.filter(func(r): return r[2])
	var pick := prim if not prim.is_empty() else rolled
	pick.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var key := ""
	if prim.size() >= 2:
		var order := ["strength", "stamina", "agility", "intellect"]
		var two := [str(pick[0][0]), str(pick[1][0])]
		two.sort_custom(func(a, b): return order.find(a) < order.find(b))
		key = "+".join(two)
	elif not pick.is_empty():
		key = str(pick[0][0])
	var out := base_name
	var pool: Array = pools.get(key, [])
	if not pool.is_empty():
		out = "%s %s" % [out, pool[rng.randi_range(0, pool.size() - 1)]]
	var prefixes: Array = quality.get("prefixes", [])
	if not prefixes.is_empty():
		out = "%s %s" % [prefixes[rng.randi_range(0, prefixes.size() - 1)], out]
	return out


## A named legendary (GDD 6, D6/D7): rarity 5, fixed stats and affix scaled from their level-30
## values to `item_level`, the legendary's procs / mods / flags carried on the item.
static func make_legendary(id: String, item_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var lg: Dictionary = GameData.legendaries.get(id, {})
	if lg.is_empty():
		return {}
	var base: Dictionary = GameData.item_bases.get(str(lg.base), {})
	var lvl := maxi(item_level, 1)
	var item := {
		"uid": new_uid(rng), "base": str(lg.base), "legendary": id, "kind": base.get("kind", "armor"), "slot": base.get("slot", lg.slot),
		"hands": int(base.get("hands", 1)), "rarity": 5, "ilvl": lvl, "req": lvl, "classes": [lg["class"]],
		"appearance": base.get("appearance", ""), "tint": "#ffffff", "name": lg.name,
		"icon": lg.icon if GameData.asset_exists(str(lg.icon)) else base.get("icon", "items.ring"),
		"stats": {}, "mods": lg.get("mods", []).duplicate(true), "flags": lg.get("flags", []).duplicate(), "procs": lg.get("procs", []).duplicate(true),
		"affix": lg.affix,
	}
	ItemLooks.apply_legendary(item, lg)  # its own worn look and colours (#20)
	_legendary_numbers(item, lg, lvl)
	return item


## A legendary's level-dependent numbers at `lvl` (D7): percentages stay fixed, flat numbers
## scale with the item level.
static func _legendary_numbers(item: Dictionary, lg: Dictionary, lvl: int) -> void:
	var scale := Combat.legendary_scale(lvl)
	var pct: Array = GameData.affixes.percent_stats
	item.ilvl = lvl
	item.req = lvl
	item.stats = {}
	for k in lg.get("stats", {}):
		var v := float(lg.stats[k])
		item.stats[k] = v if (pct.has(k) or k.ends_with("_mult") or k.ends_with("_pct") or absf(v) < 1.0) else float(roundi(v * scale))
	if lg.has("armor"):
		item.armor = roundi(float(lg.armor) * scale)
	if lg.has("dps"):
		item.dps = snappedf(float(lg.dps) * scale, 0.1)


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
## True when `item` is gear whose required level is above `char_level`.
static func too_high_level(item: Dictionary, char_level: int) -> bool:
	return item.get("kind") in ["weapon", "offhand", "armor", "jewelry"] and int(item.get("req", 1)) > char_level


## Tooltip lines [[text, color], ...]. With `char_level` > 0 a level requirement above it is
## shown in red with the character's level.
static func describe(item: Dictionary, class_id: String = "", char_level: int = 0) -> Array:
	var lines: Array = []
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	lines.append([Loc.item_name(item), Color.from_string(rar.color, Color.WHITE)])
	match item.get("kind", ""):
		"consumable":
			var c: Dictionary = GameData.consumables.get(item.base, {})
			lines.append([Loc.f("Consumable  x%d", [int(item.get("count", 1))]), Color(0.7, 0.7, 0.7)])
			lines.append([Loc.t(c.get("description", "")), Color(0.85, 0.85, 0.8)])
			return lines
		"backpack":
			lines.append([Loc.f("Backpack: %d slots (pick up to equip)", [int(item.capacity)]), Color(0.85, 0.85, 0.8)])
			return lines
		"book":
			var bk: Dictionary = GameData.lore_books.get(str(item.get("book", "")), {})
			lines.append([{"standard": Loc.t("Lore book"), "tome": Loc.t("Tome of Enlightenment"), "legendary": Loc.t("Legendary tome")}.get(str(bk.get("classification", "")), Loc.t("Book")), Color(0.7, 0.7, 0.7)])
			lines.append([Loc.t(str(bk.get("origin", ""))), Color(0.6, 0.6, 0.65)])
			if str(bk.get("classification", "")) != "standard":
				lines.append([Loc.t(str(bk.get("effect_text", ""))).replace(Loc.t(" (Permanent)"), Loc.t(" for this run")), Color(0.55, 0.9, 0.55)])
			lines.append([Loc.t("Read it: Accept / click"), Color(0.85, 0.85, 0.8)])
			return lines
		"gold", "gold_key":
			return lines
	var slot_name: String = item.get("slot", "")
	var kind_txt := Loc.f("%s %s", [Loc.t(rar.name), Loc.t(str(SLOT_LABELS.get(slot_name, slot_name.capitalize())))])
	if item.get("kind") == "weapon":
		kind_txt += " (%s)" % (Loc.t("Two-handed") if int(item.get("hands", 1)) == 2 else Loc.t("One-handed"))
	lines.append([kind_txt, Color(0.7, 0.7, 0.7)])
	if item.has("dps"):
		lines.append([Loc.f("%.1f DPS", [float(item.dps)]), Color(1, 1, 1), "stat_weapon_dps"])
	if item.has("legendary"):
		lines.append([Loc.t("Legendary"), Color.from_string(rar.color, Color.ORANGE)])
	if item.has("armor") and int(item.armor) > 0:
		lines.append([Loc.f("%d Armor", [int(item.armor)]), Color(1, 1, 1), "stat_armor"])
	var names: Dictionary = GameData.affixes.stat_names
	for k in item.get("stats", {}):
		var v := float(item.stats[k])
		var is_pct := Array(GameData.affixes.percent_stats).has(k) or (absf(v) < 1.0 and v != 0.0)
		var txt := ("%+d%% %s" % [roundi(v * 100.0), Loc.t(str(names.get(k, k)))]) if is_pct else ("%+d %s" % [int(v), Loc.t(str(names.get(k, k)))])
		lines.append([txt, Color(0.55, 0.9, 0.55), str(UITheme.STAT_ICONS.get(str(k).trim_suffix("_pct"), "sil_star"))])
	if item.has("affix"):
		lines.append([Loc.t(str(item.affix)), Color(1.0, 0.72, 0.3), "sil_star"])
	if int(item.get("forged", 0)) > 0:
		lines.append([Loc.f("Forged %d times at Rolf's anvil", [int(item.forged)]) if int(item.forged) > 1 else Loc.t("Forged once at Rolf's anvil"), Color(0.95, 0.72, 0.35), "forge"])
	if item.has("quality"):
		# #64: what the prefix stands for.
		var label := ""
		for q in GameData.affixes.get("qualities", []):
			if str(q.id) == str(item.quality):
				label = str(q.label)
		if not label.is_empty():
			lines.append([Loc.f("%s: +%d%% to every stat", [Loc.t(label), roundi((float(item.get("quality_mult", 1.0)) - 1.0) * 100.0)]), Color(0.95, 0.85, 0.55), "sil_star"])
		var lg: Dictionary = GameData.legendaries.get(str(item.get("legendary", "")), {})
		if lg.has("description"):
			lines.append([Loc.t(str(lg.description)), Color(0.6, 0.6, 0.65)])
	if char_level > 0 and too_high_level(item, char_level):
		lines.append([Loc.f("Requires level %d (you are level %d)", [int(item.get("req", 1)), char_level]), Color(0.95, 0.4, 0.35), "sil_lock"])
	else:
		lines.append([Loc.f("Requires level %d", [int(item.get("req", 1))]), Color(0.75, 0.75, 0.75), "ui_crown"])
	var classes: Array = item.get("classes", [])
	if not classes.is_empty():
		var cnames: Array = []
		for c in classes:
			cnames.append(Loc.t(str(GameData.classes.get(c, {}).get("name", c))))
		var ok := class_id.is_empty() or classes.has(class_id)
		var penalty := Loc.f("  (-%d%% damage, slower cooldowns for you)", [roundi((1.0 - float(GameData.bal("off_class.damage_mult"))) * 100.0)])
		lines.append([Loc.f("Class: %s%s", [", ".join(cnames), "" if ok else penalty]),
			Color(0.75, 0.75, 0.75) if ok else Color(0.95, 0.4, 0.35), "class_" + str(classes[0])])
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
