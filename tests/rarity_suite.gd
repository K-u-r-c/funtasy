class_name RaritySuite
extends RefCounted
## #65 Drop rarity by depth (scenario "loot_rarity", no session): over many seeded rolls the share
## of Rare-or-better drops grows from floor 1 to 10 to 25 to 50 by small steps and stops there,
## random Relics stay at their tiny fixed share at every depth, and named legendaries drop at
## their per-source data chance, the same on floor 1 and floor 50.

var da: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 65
	var n := 40000
	var rare := {}
	var relic := {}
	for d in [1, 10, 25, 50, 80]:
		var r := 0
		var rel := 0
		for i in n:
			var tier := ItemGenerator.roll_rarity(rng, d, 1)
			r += 1 if tier >= 3 else 0
			rel += 1 if tier == 5 else 0
		rare[d] = float(r) / n
		relic[d] = float(rel) / n
	var steps: bool = rare[10] > rare[1] and rare[25] > rare[10] and rare[50] > rare[25] and rare[10] - rare[1] < 0.04 and absf(rare[80] - rare[50]) < 0.01
	da.check(steps, "Rare or better grows slowly with depth and stops at floor 50 (%s)" % ", ".join([1, 10, 25, 50, 80].map(func(d): return "floor %d %.1f%%" % [d, rare[d] * 100.0])))
	var w: Array = GameData.bal("loot.rarity_weights")
	var tot := 0.0
	for x in w:
		tot += float(x)
	var want_relic := float(w[4]) / tot
	da.check(relic.values().all(func(v): return absf(float(v) - want_relic) < 0.0015), "random Relics stay at ~%.1f%% on every floor (%s)" % [want_relic * 100.0, ", ".join(relic.values().map(func(v): return "%.2f%%" % (float(v) * 100.0)))])
	# Named legendaries per source, floor 1 and floor 50.
	var chances: Dictionary = GameData.bal("legendary.drop_chance")
	var bad := []
	var seen := []
	for src in chances:
		var p := float(chances[src])
		for d in [1, 50]:
			var m := 6000 if src != "boss" else 3000
			var hits := 0
			for i in m:
				for it in LootTable.roll(str(src), 10, d, ["warrior"], rng):
					if it.has("affix") and int(it.get("rarity", 0)) == 5:
						hits += 1
						break
			var got := float(hits) / m
			seen.append("%s@%d %.1f%%" % [src, d, got * 100.0])
			if absf(got - p) > 4.0 * sqrt(p * (1.0 - p) / m) + 0.002:
				bad.append("%s floor %d: %.2f%% (data %.2f%%)" % [src, d, got * 100.0, p * 100.0])
	da.check(bad.is_empty(), "named legendaries drop at their data chance at any depth (%s)%s" % [", ".join(seen), "" if bad.is_empty() else ": " + ", ".join(bad)])
