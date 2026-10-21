class_name FloorPlan
extends RefCounted
## #70: which biome every floor of a run is, which floors are mixed, and which boss each meets.
## Everything is a pure function of the run seed and the depth, so the host, every client and a
## continued game (#55, the run seed is saved) agree without sending or saving anything extra.
##
## - Floors 1..`biomes.fixed_floors` (5) keep the fixed order (one of each biome: the onboarding).
## - Every later cycle of five floors is a seeded shuffle of the five biomes whose first floor is
##   never the biome the previous cycle ended on, so no biome comes twice in a row.
## - From `biomes.mixed_from_floor` a share of floors (`biomes.mixed_share`) is mixed: the layout,
##   art and mechanics of its biome with part of the monster pool (`biomes.monster_share`) and
##   sometimes one hazard (`biomes.hazard_chance`, `biomes.hazards`) of an invading biome picked
##   from `biomes.pairs`.
## - A boss pick avoids the boss met last time in the same biome when the other one is available.


static func cfg(key: String) -> Variant:
	return GameData.bal("biomes." + key)


## The biome ids in their fixed (onboarding) order.
static func fixed_order() -> Array:
	var ids: Array = GameData.floor_types.keys()
	ids.sort_custom(func(a, b): return int(GameData.floor_types[a].get("order", 99)) < int(GameData.floor_types[b].get("order", 99)) \
		or (int(GameData.floor_types[a].get("order", 99)) == int(GameData.floor_types[b].get("order", 99)) and str(a) < str(b)))
	return ids


## The biome of floor `depth` in a run with `run_seed`.
static func biome_at(run_seed: int, depth: int) -> String:
	var ids := fixed_order()
	var n := ids.size()
	var forced := str(GameState.get_meta("force_biome", ""))
	if forced != "" and ids.has(forced):
		# Tests and screenshots: the fixed order starting at the forced biome.
		return ids[(ids.find(forced) + depth - 1) % n]
	var fixed := int(cfg("fixed_floors"))
	if depth <= fixed:
		return ids[(depth - 1) % n]
	var cycle := (depth - fixed - 1) / n  # 0 = the first shuffled cycle
	var order := _cycle(run_seed, cycle, ids)
	return order[(depth - fixed - 1) % n]


## The shuffled order of the `cycle`-th cycle after the fixed floors.
static func _cycle(run_seed: int, cycle: int, ids: Array) -> Array:
	var last: String = ids[(int(cfg("fixed_floors")) - 1) % ids.size()]
	var order: Array = []
	for k in range(cycle + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, k, 70])
		order = ids.duplicate()
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: Variant = order[i]
			order[i] = order[j]
			order[j] = t
		if order[0] == last:
			var t2: Variant = order[0]
			order[0] = order[1]
			order[1] = t2
		last = order[-1]
	return order


## The biome invading floor `depth` ("" = not a mixed floor).
static func mix_at(run_seed: int, depth: int) -> String:
	var forced := str(GameState.get_meta("force_mix", ""))
	if forced != "":
		return forced if forced != biome_at(run_seed, depth) else ""
	if not str(GameState.get_meta("force_biome", "")).is_empty() or depth < int(cfg("mixed_from_floor")):
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, 71])
	if rng.randf() >= float(cfg("mixed_share")):
		return ""
	var pairs: Array = cfg("pairs").get(biome_at(run_seed, depth), [])
	return str(pairs[rng.randi() % pairs.size()]) if not pairs.is_empty() else ""


## The floor definition a floor is built from: its biome's, or for a mixed floor a copy with part
## of the invader's monster pool and maybe one of its hazards (`seed` picks the hazard).
static func floor_def(biome: String, mix: String, floor_seed: int) -> Dictionary:
	var base: Dictionary = GameData.floor_types[biome]
	if mix.is_empty() or not GameData.floor_types.has(mix):
		return base
	var inv: Dictionary = GameData.floor_types[mix]
	var fd := base.duplicate(true)
	fd["mix"] = mix
	var share := clampf(float(cfg("monster_share")), 0.0, 0.9)
	var own_total := 0.0
	var inv_total := 0.0
	for m in base.monsters:
		own_total += float(m.weight)
	for m in inv.monsters:
		inv_total += float(m.weight)
	var pool: Array = []
	for m in base.monsters:
		pool.append({"id": m.id, "weight": float(m.weight) / own_total * (1.0 - share) * 100.0})
	for m in inv.monsters:
		pool.append({"id": m.id, "weight": float(m.weight) / inv_total * share * 100.0, "invader": true})
	fd["monsters"] = pool
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([floor_seed, 72])
	var hz: Dictionary = cfg("hazards").get(mix, {})
	if not hz.is_empty() and rng.randf() < float(cfg("hazard_chance")):
		fd["mix_hazard"] = true
		for k in hz:
			if k == "floor_mechanics":
				var mechs: Array = fd.get("floor_mechanics", []).duplicate(true)
				mechs.append_array(hz[k].duplicate(true))
				fd["floor_mechanics"] = mechs
			else:
				fd[k] = hz[k]
	return fd


## The boss of every floor up to `depth` (index 0 = floor 1): each a seeded pick from its biome's
## list that avoids the boss met last time in that biome when another is available.
static func bosses_to(run_seed: int, depth: int) -> Array:
	var out: Array = []
	var last: Dictionary = {}
	for d in range(1, depth + 1):
		var b := biome_at(run_seed, d)
		var pick := pick_boss(GameData.floor_types[b], hash(run_seed + d * 7919), str(last.get(b, "")))
		last[b] = pick
		out.append(pick)
	return out


## A seeded pick from the floor type's boss list ("force_boss" meta on GameState pins one for
## tests and screenshots), avoiding `avoid` when the list has another.
static func pick_boss(ft: Dictionary, floor_seed: int, avoid: String = "") -> String:
	var pool: Array = ft.get("bosses", [ft.get("boss", "")])
	var forced := str(GameState.get_meta("force_boss", ""))
	if forced != "" and pool.has(forced):
		return forced
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed + 211
	var pick := str(pool[rng.randi() % pool.size()])
	if pick == avoid and pool.size() > 1:
		var rest := pool.filter(func(x): return str(x) != avoid)
		pick = str(rest[rng.randi() % rest.size()])
	return pick


## The floor's name for banners and the HUD: "Forgotten Crypt" or, mixed, "Forgotten Crypt,
## overrun from the Sewers of Heresy" (translated).
static func title(fd: Dictionary) -> String:
	var name_ := Loc.t(str(fd.get("name", "")))
	var mix := str(fd.get("mix", ""))
	if mix.is_empty():
		return name_
	return Loc.f("%s, %s", [name_, Loc.t(str(GameData.floor_types[mix].get("overrun", "")))])
