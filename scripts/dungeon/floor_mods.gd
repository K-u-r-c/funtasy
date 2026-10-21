class_name FloorMods
extends RefCounted
## #71 floor modifiers (data/floor_modifiers.json): a trade of danger for reward on every floor
## from `from_floor`. The host offers two at each portal (seeded, sent to every peer), the party
## votes, and the host's pick is built into the next floor: its numbers are folded into the floor
## definition (FloorPlan.floor_def), so every peer and every system reads them from there
## (floor_def.mod and floor_def.mod_def). Restless and Hunted run in ModRunner.


static func defs() -> Dictionary:
	return GameData.floor_modifiers.get("modifiers", {})


static func def(id: String) -> Dictionary:
	return defs().get(id, {})


static func from_floor() -> int:
	return int(GameData.floor_modifiers.get("from_floor", 4))


## Host: the two modifiers offered at the portal leading to floor `next_depth` ([] before
## from_floor). Seeded by the run; never the pair offered for the floor before, and never the
## modifier of the floor being left.
static func offer(run_seed: int, next_depth: int, current: String) -> Array:
	if next_depth < from_floor():
		return []
	var ids: Array = defs().keys()
	ids.sort()
	var prev: Array = offer(run_seed, next_depth - 1, "") if next_depth - 1 >= from_floor() else []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, next_depth, 711])
	for attempt in 12:
		var pool := ids.duplicate()
		pool.erase(current)
		var a: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var b: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var pair := [a, b]
		pair.sort()
		if pair != prev or attempt == 11:
			return pair
	return []


## Host: the winner of `votes` (peer -> id) among `offered`: the most votes; a tie (or no vote at
## all) is broken by a seeded pick among the tied ones.
static func resolve(offered: Array, votes: Dictionary, run_seed: int, next_depth: int) -> String:
	if offered.is_empty():
		return ""
	var count := {}
	for id in offered:
		count[id] = 0
	for peer in votes:
		if count.has(votes[peer]):
			count[votes[peer]] += 1
	var best := -1
	var tied: Array = []
	for id in offered:
		if count[id] > best:
			best = count[id]
			tied = [id]
		elif count[id] == best:
			tied.append(id)
	tied.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, next_depth, 712])
	return str(tied[rng.randi_range(0, tied.size() - 1)])


## Folds modifier `id` into the floor definition `fd` (a copy is returned).
static func apply(fd: Dictionary, id: String) -> Dictionary:
	var md := def(id)
	if md.is_empty():
		return fd
	var out := fd.duplicate(true)
	out["mod"] = id
	out["mod_def"] = md
	# Dimmed: every torch (wall and carried) and the hero's own lights reach less far; spells don't.
	out["torch_radius_mult"] = float(fd.get("torch_radius_mult", 1.0)) * float(md.get("light_mult", 1.0))
	out["personal_light_mult"] = float(fd.get("personal_light_mult", 1.0)) * float(md.get("light_mult", 1.0))
	return out


## A number of the floor's modifier (1.0 / 0 when the floor has none or it doesn't set it).
static func num(fd: Dictionary, key: String, default: float = 1.0) -> float:
	return float(fd.get("mod_def", {}).get(key, default))


## The loot roll override for the floor's rewards (LootTable reads these keys).
static func loot_override(fd: Dictionary) -> Dictionary:
	if not fd.has("mod_def"):
		return {}
	return {"drop_mult": num(fd, "drop_mult"), "gold_mult": num(fd, "gold_mult"), "book_mult": num(fd, "book_mult"),
		"rarity_up_chance": num(fd, "rarity_up_chance", 0.0), "monster_book_chance": num(fd, "monster_book_chance", 0.0)}


## The card lines of modifier `id`: [[danger, colour, heading], [reward, colour, heading]].
static func card_lines(id: String) -> Array:
	var md := def(id)
	return [[Loc.t(str(md.get("danger", ""))), Color("ff9a7a"), [Loc.t("Danger"), UITheme.WARN]],
		[Loc.t(str(md.get("reward", ""))), Color("f0d27a"), [Loc.t("Reward"), UITheme.GOLD]]]


static func color(id: String) -> Color:
	return Color.from_string(str(def(id).get("color", "#e8b74a")), UITheme.GOLD)
