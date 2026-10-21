class_name Boons
extends RefCounted
## #73 boons (data/boons/*.json): after every boss each hero picks one of three, kept for the
## rest of the run (Player.boons, saved with the hero, gone with a wipe like everything else).
## Three kinds: "stat" (mods / skill_mods), "item" (`give`: an item handed over at once) and
## "synergy" (procs and flags that change how skills and effects work together). Every boon has
## its own icon, a rarity (1-4, the item rarity colours), tags and a data `test` (the legendary
## test format), so the boon suite proves each one. Offers are seeded per hero and weighted toward
## the tags the hero already has (more of a tag, more weight) (with a chance of a fresh one), one card of each kind when it can.


static func cfg(key: String) -> Variant:
	return GameData.bal("boons." + key)


static func def(id: String) -> Dictionary:
	return GameData.boons.get(id, {})


## The boons a hero of `class_id` can be offered: its class's and the shared ones.
static func pool_for(class_id: String) -> Array:
	var out: Array = []
	for id in GameData.boons:
		var c := str(GameData.boons[id].get("class", "any"))
		if c == class_id or c == "any":
			out.append(id)
	out.sort()
	return out


## The tags of the boons in `owned`, with their counts.
static func tags_of(owned: Array) -> Dictionary:
	var t := {}
	for id in owned:
		for tg in def(str(id)).get("tags", []):
			t[tg] = int(t.get(tg, 0)) + 1
	return t


## Host: three different boons for a hero of `class_id` who owns `owned`; `seed_v` makes it
## the same every time for that hero and floor. One stat, one item and one synergy boon when the
## pool has them, else whatever weighs most.
static func offer(class_id: String, owned: Array, seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var have := tags_of(owned)
	var pool := pool_for(class_id).filter(func(id): return not owned.has(id) or bool(def(str(id)).get("stackable", false)))
	var rar_w: Array = cfg("rarity_weights")
	var tag_w := float(cfg("tag_weight"))
	var fresh := rng.randf() < float(cfg("fresh_chance"))
	var out: Array = []
	var kinds := ["stat", "item", "synergy"]
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	for slot in 3:
		var kind: String = kinds[slot]
		var cands: Array = pool.filter(func(id): return str(def(str(id)).get("kind", "")) == kind and not out.has(id))
		if cands.is_empty():
			cands = pool.filter(func(id): return not out.has(id))
		if cands.is_empty():
			break
		var weights: Array = []
		for id in cands:
			var d := def(str(id))
			var w := float(rar_w[clampi(int(d.get("rarity", 1)) - 1, 0, rar_w.size() - 1)])
			var shared := 0
			# The more boons of a tag the hero has, the more that tag comes back (up to 3 each).
			for tg in d.get("tags", []):
				shared += mini(int(have.get(tg, 0)), 3)
			# The last card may be a fresh direction: no tag the hero has.
			if fresh and slot == 2:
				w *= 2.0 if shared == 0 else 0.5
			else:
				w *= 1.0 + tag_w * shared
			weights.append(w)
		out.append(str(cands[ItemGenerator._weighted_index(weights, rng)]))
	return out


## Host (#96): a new boon for card `index` of the offer `current`: the same kind when the pool
## has one, never one of the other cards (or the card itself) or a boon the hero owns (unless it
## stacks), weighted like the offer. "" when nothing else is left.
static func reroll(class_id: String, owned: Array, current: Array, index: int, seed_v: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var have := tags_of(owned)
	var kind := str(def(str(current[index])).get("kind", ""))
	var pool := pool_for(class_id).filter(func(id): return not current.has(id) and (not owned.has(id) or bool(def(str(id)).get("stackable", false))))
	var cands: Array = pool.filter(func(id): return str(def(str(id)).get("kind", "")) == kind)
	if cands.is_empty():
		cands = pool
	if cands.is_empty():
		return ""
	var rar_w: Array = cfg("rarity_weights")
	var tag_w := float(cfg("tag_weight"))
	var weights: Array = []
	for id in cands:
		var d := def(str(id))
		var shared := 0
		for tg in d.get("tags", []):
			shared += mini(int(have.get(tg, 0)), 3)
		weights.append(float(rar_w[clampi(int(d.get("rarity", 1)) - 1, 0, rar_w.size() - 1)]) * (1.0 + tag_w * shared))
	return str(cands[ItemGenerator._weighted_index(weights, rng)])


## The stat side of the boons in `owned` for Stats.compute_player: {mods, skill_mods, flags}.
static func stat_parts(owned: Array) -> Dictionary:
	var mods: Array = []
	var smods: Array = []
	var flags: Array = []
	for id in owned:
		var d := def(str(id))
		for m in d.get("mods", []):
			mods.append(m)
		for sm in d.get("skill_mods", []):
			smods.append(sm)
		for f in d.get("flags", []):
			flags.append(f)
	return {"mods": mods, "skill_mods": smods, "flags": flags}


## The procs of the boons in `owned`, keyed for their internal cooldowns.
static func procs_of(owned: Array) -> Array:
	var out: Array = []
	for id in owned:
		var d := def(str(id))
		for i in d.get("procs", []).size():
			out.append(d.procs[i].merged({"_key": "b:%s:%d" % [id, i], "source": id}, true))
	return out


## Host: the items an item boon hands over to `p` (made at the floor's item level).
static func give_items(d: Dictionary, p: Player, item_level: int, rng: RandomNumberGenerator) -> Array:
	var g: Dictionary = d.get("give", {})
	var out: Array = []
	match str(g.get("type", "")):
		"legendary":
			var lg := LootTable.roll_legendary([p.class_id] if str(g.get("class", "self")) == "self" else GameState.classes_in_party(), item_level, rng)
			if not lg.is_empty():
				out.append(lg)
		"equipment":
			for i in int(g.get("count", 1)):
				var base := str(g.get("base", "")) if g.has("base") else LootTable.pick_base([p.class_id], rng)
				out.append(ItemGenerator.generate_equipment(base, item_level + int(g.get("levels", 0)), int(g.get("rarity", 4)), rng))
		"consumable":
			out.append(ItemGenerator.generate_consumable(str(g.id), int(g.get("count", 1)), rng))
		"backpack":
			out.append(ItemGenerator.generate_backpack(maxi(item_level, 10), rng))
		"unique":
			var it := ItemGenerator.generate_equipment(str(g.base), item_level, int(g.get("rarity", 4)), rng)
			it.name = str(d.name)
			it["boon_unique"] = str(d.get("id", ""))
			# Its own stats grow with the item level like the item's rolled ones (kept apart so the
			# forge recomputes them too, #77).
			it["extra_stats"] = g.get("stats", {}).duplicate()
			it["extra_growth"] = float(cfg("unique_per_level"))
			ItemGenerator.apply_level(it, int(it.ilvl))
			it["procs"] = g.get("procs", []).duplicate(true)
			it["flags"] = g.get("flags", []).duplicate()
			it["mods"] = g.get("mods", []).duplicate(true)
			it["affix"] = str(d.get("text", ""))
			out.append(it)
	return out


## The card lines of a boon: its effect, and its kind / tags in a dim line.
static func card_lines(id: String) -> Array:
	var d := def(id)
	var tags: Array = d.get("tags", []).map(func(t): return Loc.t(str(GameData.boon_tags.get(str(t), {}).get("name", str(t).capitalize()))))
	return [[Loc.t(str(d.get("text", ""))), UITheme.TEXT], [" / ".join(tags), UITheme.TEXT_DIM, [Loc.t(KIND_NAMES.get(str(d.get("kind", "")), "Boon")), color(id)]]]


const KIND_NAMES := {"stat": "Power", "item": "Gift", "synergy": "Synergy"}


static func color(id: String) -> Color:
	var r := GameData.rarity(clampi(int(def(id).get("rarity", 1)), 1, 5))
	return Color.from_string(str(r.color), Color.WHITE)
