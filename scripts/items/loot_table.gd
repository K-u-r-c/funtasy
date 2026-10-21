class_name LootTable
extends RefCounted
## Host-only loot rolls. Fully random, but weapons/off-hands of classes present in the party get
## a weight boost (balance: loot.party_class_weight).


static func roll(source: String, item_level: int, depth: int, party_classes: Array, rng: RandomNumberGenerator, override: Dictionary = {}) -> Array:
	var count := 0
	var min_tier := 1
	match source:
		"monster":
			count = 1 if rng.randf() < float(GameData.bal("loot.monster_drop_chance")) or GameState.get_meta("test_force_drop", false) else 0
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
	# Lore books (D20): bookshelves always, altars and secret containers sometimes.
	var book_chance := {"bookshelf": 1.0, "altar": float(GameData.bal("lore.altar_book_chance")),
		"secret": float(GameData.bal("lore.secret_book_chance"))}.get(source, 0.0) as float
	if book_chance > 0.0 and rng.randf() < book_chance:
		var b := roll_book(str(override.get("biome", "")), rng)
		if not b.is_empty():
			out.append(b)
			if source == "altar":
				count = 0
	# Legendaries (GDD 6): bosses, elites and chests can drop one, weighted to the party's classes.
	var lchance := float((GameData.bal("legendary.drop_chance") as Dictionary).get(source, 0.0))
	# Tests (#75): no chance legendaries, or a sure one from a boss.
	if GameState.get_meta("test_no_legendary", false):
		lchance = 0.0
	elif source == "boss" and GameState.get_meta("test_force_legendary", false):
		lchance = 1.0
	if lchance > 0.0 and rng.randf() < lchance:
		var lg := roll_legendary(party_classes, item_level, rng)
		if not lg.is_empty():
			out.append(lg)
	for i in count:
		var r2 := rng.randf()
		if source != "boss" and r2 < float(GameData.bal("loot.consumable_chance")):
			out.append(_consumable(rng))
		elif source != "boss" and r2 < float(GameData.bal("loot.consumable_chance")) + float(GameData.bal("loot.backpack_chance")):
			out.append(ItemGenerator.generate_backpack(depth, rng))
		else:
			var base_id := pick_base(party_classes, rng)
			var tier := ItemGenerator.roll_rarity(rng, depth, min_tier)
			var up := upgrade_roll(item_level, tier, rng)
			out.append(ItemGenerator.generate_equipment(base_id, int(up[0]), int(up[1]), rng))
	return out


## A rare upgrade (#8): with loot.upgrade_chance an item comes `loot.upgrade_levels` levels above
## the current item level (the hero grows into it) and one rarity tier higher. Returns
## [item level, rarity].
static func upgrade_roll(item_level: int, tier: int, rng: RandomNumberGenerator) -> Array:
	if rng.randf() >= float(GameData.bal("loot.upgrade_chance", 0.0)):
		return [item_level, tier]
	var lv: Array = GameData.bal("loot.upgrade_levels", [2, 3])
	var cap := int(GameData.bal("progression.max_level"))
	return [mini(item_level + rng.randi_range(int(lv[0]), int(lv[1])), cap), mini(tier + int(GameData.bal("loot.upgrade_rarity", 1)), 5)]


static func roll_legendary(party_classes: Array, item_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array = GameData.legendaries.keys()
	if ids.is_empty():
		return {}
	var boost := float(GameData.bal("legendary.party_class_weight", 3.0))
	var weights: Array = ids.map(func(id): return boost if party_classes.has(GameData.legendaries[id]["class"]) else 1.0)
	return ItemGenerator.make_legendary(str(ids[ItemGenerator._weighted_index(weights, rng)]), item_level, rng)


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


## D20: category first (80 / 18 / 2), then a book of that category from the biome (+ Ancient
## Lore anywhere; the legendary tome has no biome). Books the host hasn't read weigh more.
static func roll_book(biome: String, rng: RandomNumberGenerator) -> Dictionary:
	var cw: Dictionary = GameData.bal("lore.category_weights")
	var cats: Array = cw.keys()
	var ws: Array = cats.map(func(c): return float(cw[c]))
	var cat: String = cats[ItemGenerator._weighted_index(ws, rng)]
	var pool: Array = []
	var weights: Array = []
	for id in GameData.lore_order:
		var b: Dictionary = GameData.lore_books[id]
		if b.classification != cat:
			continue
		if cat != "legendary" and not (b.biome == biome or b.biome == "ancient" or biome.is_empty()):
			continue
		pool.append(id)
		weights.append(1.0 if Codex.is_read(id) else float(GameData.bal("lore.unread_weight")))
	if pool.is_empty():
		return {}
	return make_book(str(pool[ItemGenerator._weighted_index(weights, rng)]), rng)


static func make_book(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var b: Dictionary = GameData.lore_books[id]
	return {"kind": "book", "base": "book", "book": id, "name": b.title, "classification": b.classification,
		"icon": "items.book_" + str(b.classification), "rarity": int(GameData.bal("lore.rarity")[b.classification]),
		"uid": ItemGenerator.new_uid(rng)}
