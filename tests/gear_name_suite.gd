class_name GearNameSuite
extends RefCounted
## #64 Gear names (scenario "gear_names", no session): 2000 generated items carry many different
## suffixes, the quality prefixes come with the data's share and raise the stats by their
## multiplier, pair names sit on items with two primary stats, and every name reads in Polish
## with the prefix agreeing with the item's gender.

const PRIMARY := ["strength", "stamina", "agility", "intellect"]

var da: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func suffix_of(item_name: String) -> String:
	for pool in GameData.affixes.suffix_pools.values():
		for s in pool:
			if item_name.ends_with(" " + str(s)):
				return str(s)
	return ""


static func is_pair(suffix: String) -> bool:
	for k in GameData.affixes.suffix_pools:
		if str(k).contains("+") and Array(GameData.affixes.suffix_pools[k]).has(suffix):
			return true
	return false


func run() -> void:
	var bases: Array = GameData.item_bases.keys().filter(func(b): return str(GameData.item_bases[b].get("kind", "")) != "backpack")
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	var suffixes := {}
	var with_quality := 0
	var bad_prefix := ""
	var pairs := 0
	var bad_pair := ""
	var names: Array = []
	var n := 2000
	for i in n:
		var it := ItemGenerator.generate_equipment(str(bases[i % bases.size()]), rng.randi_range(1, 20), rng.randi_range(1, 4), rng)
		names.append(str(it.name))
		var suf := suffix_of(str(it.name))
		if not suf.is_empty():
			suffixes[suf] = true
		if it.has("quality"):
			with_quality += 1
			var q: Dictionary = {}
			for qq in GameData.affixes.qualities:
				if str(qq.id) == str(it.quality):
					q = qq
			if not Array(q.get("prefixes", [])).any(func(pr): return str(it.name).begins_with(str(pr) + " ")):
				bad_prefix = str(it.name)
		if is_pair(suf):
			pairs += 1
			if PRIMARY.filter(func(s): return it.stats.has(s)).size() < 2:
				bad_pair = str(it.name)
	da.check(suffixes.size() >= 40, "2000 items carry %d different suffixes (8 before)" % suffixes.size())
	var share := float(with_quality) / n
	var want := 0.0
	for q in GameData.affixes.qualities:
		want += float(q.chance)
	da.check(absf(share - want) < 0.05 and bad_prefix.is_empty(), "%.0f%% of the items are better made (data: about %.0f%%), each named with its quality's prefix%s"
			% [share * 100.0, want * 100.0, "" if bad_prefix.is_empty() else " (wrong: %s)" % bad_prefix])
	da.check(pairs > 0 and bad_pair.is_empty(), "%d items carry a pair name, each with two primary stats%s" % [pairs, "" if bad_pair.is_empty() else " (wrong: %s)" % bad_pair])
	# The quality raises the stats: Swords at one level and rarity, by quality.
	var dps := {"": [], "fine": [], "superior": [], "flawless": []}
	for i in 6000:
		var sw := ItemGenerator.generate_equipment("sword", 10, 2, rng)
		dps[str(sw.get("quality", ""))].append(float(sw.dps))
	var avg := func(a: Array) -> float: return a.reduce(func(x, y): return x + y, 0.0) / maxf(a.size(), 1.0)
	var plain: float = avg.call(dps[""])
	var ratios := []
	for q in GameData.affixes.qualities:
		ratios.append([str(q.id), float(avg.call(dps[str(q.id)])) / plain, float(q.mult)])
	da.check(ratios.all(func(r): return absf(float(r[1]) - float(r[2])) < 0.04),
			"better-made swords hit harder by their quality (%s)" % ", ".join(ratios.map(func(r): return "%s x%.2f" % [r[0], r[1]])))
	# Polish: the prefix agrees with the base's gender; every name translates.
	var was := Settings.language
	Settings.language = "pl"
	Settings.apply_language()
	var forms := [Loc.name("Mighty Sword of the Ox"), Loc.name("Mighty Shield of the Ox"), Loc.name("Mighty Boots of the Ox"), Loc.name("Sword of the Bear")]
	da.check(forms == ["Potężny Miecz Wołu", "Potężna Tarcza Wołu", "Potężne Buty Wołu", "Miecz Niedźwiedzia"], "Polish names agree with the gender: %s" % ", ".join(forms))
	var untranslated := names.filter(func(nm): return Loc.name(str(nm)).contains(" of ") or Loc.name(str(nm)) == str(nm))
	da.check(untranslated.is_empty(), "every generated name reads in Polish%s" % ("" if untranslated.is_empty() else " (not: %s)" % untranslated[0]))
	Settings.language = was
	Settings.apply_language()
