class_name LootTable
extends RefCounted
## Host-only loot rolls. Fully random, but weapons/off-hands of classes present in the party get
## a weight boost (balance: loot.party_class_weight).


static func roll(source: String, item_level: int, depth: int, party_classes: Array, rng: RandomNumberGenerator, override: Dictionary = {}) -> Array:
	var count := 0
	var min_tier := 1
	match source:
		"monster":
			count = 1 if rng.randf() < float(GameData.bal("loot.monster_drop_chance")) else 0
		"prop":
			count = 1
		"chest":
			var r: Array = GameData.bal("loot.chest_drops")
			count = rng.randi_range(int(r[0]), int(r[1]))
			min_tier = int(GameData.bal("loot.chest_min_rarity"))
		"altar", "secret":
			count = 1 if source == "altar" else rng.randi_range(1, 2)
			min_tier = 2
		"bookshelf", "elite":
			count = 0
		"boss":
			var rb: Array = override.get("drops", GameData.bal("loot.boss_drops"))
			count = rng.randi_range(int(rb[0]), int(rb[1]))
			min_tier = int(override.get("min_rarity", GameData.bal("loot.boss_min_rarity")))
	var out: Array = []
	var g := gold_pile(source, item_level, rng)
	if not g.is_empty():
		out.append(g)
	var bonus := float(GameData.bal("scaling.rarity_bonus_per_depth")) * (depth - 1)
	for i in count:
		var r2 := rng.randf()
		if source != "boss" and r2 < float(GameData.bal("loot.consumable_chance")):
			out.append(_consumable(rng))
		elif source != "boss" and r2 < float(GameData.bal("loot.consumable_chance")) + float(GameData.bal("loot.backpack_chance")):
			out.append(ItemGenerator.generate_backpack(depth, rng))
		else:
			var base_id := pick_base(party_classes, rng)
			var tier := ItemGenerator.roll_rarity(rng, bonus, min_tier)
			out.append(ItemGenerator.generate_equipment(base_id, item_level, tier, rng))
	return out


static func pick_base(party_classes: Array, rng: RandomNumberGenerator) -> String:
	var ids: Array = []
	var weights: Array = []
	var boost := float(GameData.bal("loot.party_class_weight"))
	for id in GameData.item_bases:
		var b: Dictionary = GameData.item_bases[id]
		if b.kind == "backpack":
			continue
		var w := 1.0
		var classes: Array = b.get("classes", [])
		for c in classes:
			if party_classes.has(c):
				w = boost
				break
		ids.append(id)
		weights.append(w)
	return ids[ItemGenerator._weighted_index(weights, rng)]


static func _consumable(rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array = GameData.consumables.keys()
	var weights: Array = []
	for id in ids:
		weights.append(float(GameData.consumables[id].get("weight", 1)))
	var id: String = ids[ItemGenerator._weighted_index(weights, rng)]
	return ItemGenerator.generate_consumable(id, 1 + int(rng.randf() < 0.3), rng)


## A gold pile for this source (D12), or {}.
static func gold_pile(source: String, item_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var range_: Variant = (GameData.bal("gold") as Dictionary).get(source)
	if not range_ is Array:
		return {}
	if source == "monster" and rng.randf() > float(GameData.bal("gold.monster_chance")):
		return {}
	var amount := roundi(rng.randi_range(int(range_[0]), int(range_[1])) * (1.0 + float(GameData.bal("gold.per_level")) * (item_level - 1)))
	return make_gold(amount, rng)


static func make_gold(amount: int, rng: RandomNumberGenerator) -> Dictionary:
	return {"kind": "gold", "base": "gold", "amount": amount, "name": "%d Gold" % amount, "icon": "items.gold",
		"rarity": 1, "uid": ItemGenerator.new_uid(rng)}
