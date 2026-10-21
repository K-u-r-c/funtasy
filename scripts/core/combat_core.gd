class_name CombatCore
extends Node
## Host-side combat core shared by every effect primitive: actor queries, target selection, the
## damage pipeline (miss -> dodge -> parry -> block -> immunity -> crit -> type multipliers ->
## armor / resistances -> mana shield -> redirect -> "cannot die" rules -> HP), healing, statuses
## and procs. `Combat` (combat.gd) builds on this through CombatEffects.

const ENV_TEAM := -1
const LOS_MASK := 1 | 8 | 16
const PROJECTILE_MASK := 1 | 8 | 16 | 32 | 64
## Status flags that stop an actor from attacking, casting and moving on its own.
const NO_ACT_FLAGS := ["stunned", "asleep", "feared", "disoriented", "shackled"]
## Status kinds and flags that count as crowd control (blocked by cc_immune, diminishing returns).
const CC_FLAGS := ["rooted", "stunned", "asleep", "feared", "disoriented", "shackled", "silenced", "blinded"]

var game: Node
var fx: CombatFx
var rng := RandomNumberGenerator.new()
var _proc_depth := 0


# =========================================================================================
# Queries
# =========================================================================================


func all_actors() -> Array:
	var out: Array = []
	if game:
		out.append_array(game.players_root.get_children())
		out.append_array(game.enemies_root.get_children())
	return out


func enemies_of(team: int, pos: Vector2, r: float) -> Array:
	var out: Array = []
	for a in all_actors():
		if a is Actor and a.team != team and a.is_targetable() and a.global_position.distance_to(pos) <= r + a.radius:
			out.append(a)
	return out


func allies_of(team: int, pos: Vector2, r: float) -> Array:
	var out: Array = []
	for a in all_actors():
		if a is Actor and a.team == team and a.is_alive() and a.is_targetable_by_allies() and a.global_position.distance_to(pos) <= r + a.radius:
			out.append(a)
	return out


## Targets an effect may harm: other teams always, own team only with friendly fire on (for
## projectiles, AoE, explosions and traps - `area_like`). The environment hurts everyone.
func hostile_in_radius(ctx: Dictionary, pos: Vector2, r: float, area_like: bool) -> Array:
	var out: Array = []
	var ff: bool = area_like and bool(GameState.setting("friendly_fire")) and ctx.team == Actor.Team.PLAYERS
	for a in all_actors():
		if not (a is Actor) or not a.is_targetable():
			continue
		if a.global_position.distance_to(pos) > r + a.radius:
			continue
		if ctx.team == ENV_TEAM or a.team != ctx.team or (ff and a != ctx.caster):
			out.append(a)
	return out


func has_los(from: Vector2, to: Vector2) -> bool:
	var space := get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to, LOS_MASK)
	return space.intersect_ray(q).is_empty()


## Picks the targets of an effect from its `target` key:
## self, party (radius), aim_ally / aim_enemy / aim_any (nearest the aim point within `range`,
## for a gamepad the aim point sits on the aim ray), lowest_ally, event_target (the other actor of a
## proc event), nearest_enemy / highest_hp_enemy / random_enemy (deployables, auras),
## enemies_radius / allies_radius (around the origin).
func select_targets(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2, fallback: String = "self") -> Array:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	var mode := str(eff.get("target", fallback))
	var reach := float(eff.get("range", eff.get("max_range", 300))) * float(ctx.get("range_mult", 1.0))
	match mode:
		"party", "allies_radius":
			var al: Array = allies_of(ctx.team, origin, float(eff.get("radius", 250)) * float(ctx.radius_mult))
			if eff.get("exclude_self", false):
				al.erase(caster)
			return al
		"enemies_radius":
			return enemies_of(ctx.team, origin, float(eff.get("radius", 100)) * float(ctx.radius_mult))
		"aim_ally":
			# A teammate picked as the friendly target (#39) takes the spell wherever the cursor is.
			var fr: Variant = ctx.get("friendly")
			if is_instance_valid(fr) and fr is Actor and fr.team == ctx.team and fr.is_targetable_by_allies() \
					and origin.distance_to(fr.global_position) <= reach + float(fr.radius) + 16.0 and has_los(origin, fr.global_position):
				return [fr]
			# #67: no help through walls, as no harm.
			var a := nearest_to(allies_of(ctx.team, origin, reach).filter(func(x): return x == caster or has_los(origin, x.global_position)), aim, float(eff.get("snap", 90)))
			if a == null and caster and caster.is_alive():
				a = caster
			return [a] if a else []
		"aim_enemy":
			var e := aim_enemy(ctx, origin, aim, reach, float(eff.get("snap", 80)))
			return [e] if e else []
		"aim_any":
			var e2 := aim_enemy(ctx, origin, aim, reach, float(eff.get("snap", 60)))
			var a2 := nearest_to(allies_of(ctx.team, origin, reach).filter(func(x): return x != caster and has_los(origin, x.global_position)), aim, float(eff.get("snap", 60)))
			if a2 and (e2 == null or a2.global_position.distance_to(aim) < e2.global_position.distance_to(aim)):
				return [a2]
			return [e2] if e2 else []
		"lowest_ally":
			var low: Actor = null
			var low_f := float(eff.get("below", 1.0))
			for a3 in allies_of(ctx.team, origin, reach):
				if a3.health.fraction() < low_f:
					low_f = a3.health.fraction()
					low = a3
			return [low] if low else []
		"event_target":
			var t: Variant = ctx.get("event_target")
			return [t] if is_instance_valid(t) and t is Actor and t.is_alive() else []
		"event_attacker":
			var ev: Variant = ctx.get("event", {})
			var at: Variant = ev.get("attacker") if ev is Dictionary else null
			return [at] if is_instance_valid(at) and at is Actor and at.is_alive() else []
		"nearest_enemy", "highest_hp_enemy", "random_enemy", "lowest_hp_enemy":
			var pool := enemies_of(ctx.team, origin, reach).filter(func(x): return has_los(origin, x.global_position))
			if pool.is_empty():
				return []
			match mode:
				"nearest_enemy":
					return [nearest_to(pool, origin, INF)]
				"highest_hp_enemy":
					pool.sort_custom(func(x, y): return x.health.hp > y.health.hp)
				"lowest_hp_enemy":
					pool.sort_custom(func(x, y): return x.health.fraction() < y.health.fraction())
				_:
					return [pool[rng.randi_range(0, pool.size() - 1)]]
			return [pool[0]]
	return [caster] if caster and caster.is_alive() else []


func nearest_to(pool: Array, point: Vector2, max_d: float) -> Actor:
	var best: Actor = null
	var best_d := max_d
	for a in pool:
		var d: float = a.global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = a
	return best


## The enemy a single-target skill aims at: the one nearest the aim point (within `snap` of it),
## else the one closest to the aim ray, in range and in line of sight.
func aim_enemy(ctx: Dictionary, origin: Vector2, aim: Vector2, reach: float, snap: float) -> Actor:
	var pool := enemies_of(ctx.team, origin, reach).filter(func(x): return has_los(origin, x.global_position))
	var e := nearest_to(pool, aim, snap)
	if e:
		return e
	var dir := (aim - origin).normalized()
	var best: Actor = null
	var best_score := INF
	for a in pool:
		var to: Vector2 = a.global_position - origin
		var ang := absf(dir.angle_to(to))
		if ang > deg_to_rad(35.0):
			continue
		var score := ang * 200.0 + to.length() * 0.1
		if score < best_score:
			best_score = score
			best = a
	return best


func clamp_range(origin: Vector2, aim: Vector2, max_range: float) -> Vector2:
	return origin + (aim - origin).limit_length(max_range)


## Furthest point along dir (up to dist) that a body can reach without crossing walls/doors.
func walkable_point(origin: Vector2, dir: Vector2, dist: float) -> Vector2:
	var space := get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * dist, 1 | 8 | 16 | 32 | 64 | 128)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return origin + dir * dist
	return hit.position - dir * 14.0


# =========================================================================================
# Damage
# =========================================================================================


static func type_color(dtype: String) -> String:
	return str(GameData.damage_types.get("types", {}).get(dtype, {}).get("color", "#ffffff"))


## Returns damage dealt (0 = fully absorbed / immune) or -1 when the hit missed, was dodged or
## parried. opts: dot, area, damage_type, redirected, reflected, no_procs.
func deal_damage(ctx: Dictionary, target: Actor, amount: float, opts: Dictionary = {}) -> float:
	if not is_instance_valid(target) or not target.is_targetable() or amount <= 0.0:
		return 0.0
	if trap_spares(ctx, target):
		return 0.0
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	var dot := bool(opts.get("dot", false))
	var env := bool(ctx.get("environment", false))
	var dtype := str(opts.get("damage_type", ctx.get("damage_type", "physical")))
	var school := str(ctx.get("school", "physical"))
	var melee_hit := school == "melee" and not dot and not bool(opts.get("area", false)) or bool(ctx.get("melee_hit", false))
	var pos := target.global_position
	if target.is_invulnerable() or target.status.has_flag("invulnerable"):
		fx.number.rpc(pos, "Immune", "info")
		fx.gfx.rpc("immune", {"a": target.get_path()})
		return 0.0
	var data := {"target": target, "attacker": caster, "amount": 0.0, "crit": false, "dot": dot,
		"damage_type": dtype, "skill": ctx.get("skill", ""), "school": school, "ctx": ctx, "melee": melee_hit,
		"area": bool(opts.get("area", false))}
	target.last_hit_area = data.area
	var blocked := false
	if not dot and not env:
		# Accuracy, then the target's avoidance.
		var miss := caster.stats.get_stat("miss_chance") if caster else 0.0
		if not ctx.get("cannot_miss", false) and miss > 0.0 and rng.randf() < miss:
			fx.number.rpc(pos, "Miss", "info")
			fx.gfx.rpc("miss", {"pos": pos, "dir": (pos - (caster.global_position if caster else pos + Vector2.LEFT)).normalized()})
			return -1.0
		var dodge := target.stats.get_stat("dodge")
		if dtype == "physical":
			dodge += target.stats.get_stat("dodge_physical")
		dodge += target.stats.get_stat("dodge_uncapped")  # Dance of Shadows: past the 40% cap
		if not ctx.get("cannot_miss", false) and dodge > 0.0 and rng.randf() < dodge:
			fx.number.rpc(pos, "Dodge", "info")
			fx.gfx.rpc("avoid", {"a": target.get_path(), "dir": (pos - (caster.global_position if caster else pos + Vector2.LEFT)).normalized()})
			_avoided(target, caster, data, "on_dodge")
			return -1.0
		if melee_hit and target.status.has_flag("parry"):
			target.status.consume_flag("parry")
			fx.number.rpc(pos, "Parry", "info")
			fx.gfx.rpc("parry", {"a": target.get_path(), "dir": ((caster.global_position if caster else pos + Vector2.RIGHT) - pos).normalized()})
			if caster:
				var counter := make_ctx(target, {"id": "riposte_counter", "school": "melee"})
				counter.guaranteed_crit = true
				deal_damage(counter, caster, float(counter.power) * float(GameData.bal("combat.riposte_coef", 1.5)), {"no_procs": true})
			_avoided(target, caster, data, "on_block")
			return -1.0
		var bc := target.stats.get_stat("block_chance")
		# Crusader's Greaves: standing in your own Consecration, every block lands.
		if target.stats.has_flag("crusader_ground") and in_own_zone(target, "priest_consecration"):
			bc = 1.0
		# Surehand Bracers: the hero's shots can't be blocked by monster shields.
		if caster and caster.stats.has_flag("unblockable"):
			bc = 0.0
		if bc > 0.0 and _frontal(target, caster.global_position if caster else ctx.get("origin", pos)) and rng.randf() < bc:
			blocked = true
	# #22: no monster is fully immune to a damage type - its "immunity" is a strong reduction, so
	# every class can win every fight. (Heroes' own immunity statuses still block.)
	var resisted := target.immune_to(dtype)
	if resisted and target.team == Actor.Team.PLAYERS:
		fx.number.rpc(pos, "Immune", "info")
		fx.gfx.rpc("immune", {"a": target.get_path()})
		return 0.0
	# Granite Armor style charges swallow whole melee hits.
	if melee_hit and target.status.consume_charge("absorb_melee"):
		fx.number.rpc(pos, "Absorbed", "info")
		fx.gfx.rpc("absorb_hit", {"a": target.get_path()})
		return 0.0
	var crit := false
	if not dot or ctx.get("dot_can_crit", false):
		var cc := float(ctx.crit_chance) + target.stats.get_stat("crit_taken")
		var forced: bool = ctx.get("guaranteed_crit", false) or (caster and not dot and caster.status.has_flag("stealthed"))
		# Signet of the Iron Vow: the melee blow after a block is a critical hit.
		if caster and melee_hit and caster.status.has_flag("next_melee_crit"):
			forced = true
			caster.status.remove_flag("next_melee_crit")
		# Mitre of the Grand Inquisitor: Smite always crits above 80% HP.
		if caster and str(ctx.get("skill", "")) == "priest_smite" and caster.stats.has_flag("inquisitor_smite") and target.health.fraction() > 0.8:
			forced = true
		if caster and not dot and caster.status.consume_flag("next_hit_crit"):
			forced = true
		if forced or rng.randf() < cc:
			crit = true
			amount *= 1.0 + float(ctx.crit_damage) + target.stats.get_stat("crit_damage_taken") + (caster.stats.get_stat("crit_damage_bonus_next") if caster else 0.0)
	if caster and caster.status.has_flag("stealthed") and not dot:
		caster.status.remove_flag("stealthed")
	# Type, school and boss multipliers of the attacker; damage-taken multipliers of the target.
	if caster:
		amount *= caster.stats.mult(dtype + "_damage")
		# Eagle Eye (far targets) and Ballistic Precision (per 50 px) for ranged attacks.
		var dist := caster.global_position.distance_to(pos)
		if dist >= caster.stats.get_stat("far_distance", 180.0):
			amount *= 1.0 + caster.stats.get_stat("far_damage_bonus")
		if school == "ranged" and caster.stats.get_stat("distance_bonus_per_50") > 0.0:
			amount *= 1.0 + minf(caster.stats.get_stat("distance_bonus_per_50") * dist / 50.0, caster.stats.get_stat("distance_bonus_max", 0.6))
		if school in ["melee", "ranged", "spell"]:
			amount *= caster.stats.mult(school + "_damage")
		if target.get("is_boss"):
			amount *= caster.stats.mult("boss_damage")
	if caster:
		amount *= caster.stats.mult(dtype + "_damage")
		# Mail of the Infernal Berserker: +5% per missing 10% HP.
		if caster.stats.has_flag("berserker_wrath"):
			amount *= 1.0 + 0.05 * floorf((1.0 - caster.health.fraction()) * 10.0)
	# Band of Astral Shackles (anyone in the party): chilled / slowed / rooted foes take +20%.
	if target.team == Actor.Team.MONSTERS and target.status.has_any(["chill", "slow", "root", "freeze", "frostpath_chill"]) and party_has_flag("astral_shackles"):
		amount *= 1.2
	amount *= target.stats.mult("damage_taken") * target.stats.mult(dtype + "_damage_taken")
	if school in ["melee", "ranged", "spell"]:
		amount *= target.stats.mult(school + "_damage_taken")
	amount *= float(opts.get("mult", 1.0))
	if resisted:
		amount *= 1.0 - float(GameData.bal("combat.immunity_reduction", 0.8))
		if not dot:
			fx.number.rpc(pos + Vector2(0, -10), "Resisted", "info")
			fx.gfx.rpc("resist", {"a": target.get_path()})
	amount = target.modify_damage_taken(amount, data)
	# Mitigation: armor for physical, resistances for the rest, nothing for true damage.
	if dtype != "true":
		var reduction := target.stats.get_stat("strength_reduction")
		var k := float(GameData.bal("stats.armor_constant")) + float(GameData.bal("stats.armor_per_level")) * int(ctx.level)
		var pen := clampf(float(ctx.get("armor_pen", 0.0)), 0.0, 1.0)
		# Cowl of the Silent Stalker: from stealth or beyond 200 px, armor is ignored.
		if caster and caster.stats.has_flag("ambush_armor_pen") and (caster.status.has_flag("stealthed") or caster.global_position.distance_to(target.global_position) > 200.0):
			pen = 1.0
		var armor := target.stats.get_stat("armor") * (1.0 - pen)
		var armor_red := armor / (armor + k) if armor > 0.0 else 0.0
		if dtype == "physical":
			if not dot:
				reduction += armor_red
		else:
			var res := target.resist_to(dtype)
			if caster and caster.stats.has_flag("resist_ignore_40") and res > 0.0:
				res *= 0.6  # Eye of the Cataclysm
			reduction += res - float(ctx.get("magic_pen", 0.0))
			reduction += armor_red * target.stats.get_stat("armor_vs_magic")
		reduction = minf(reduction, float(GameData.bal("stats.max_damage_reduction")))
		amount *= 1.0 - reduction
	if blocked:
		var bv := target.stats.get_stat("block_value")
		data.blocked_amount = minf(amount, bv)
		amount = maxf(0.0, amount - bv) * float(GameData.bal("combat.block_after_value", 0.5))
		fx.number.rpc(pos + Vector2(0, -8), "Block", "info")
		fx.gfx.rpc("block", {"a": target.get_path(), "dir": ((caster.global_position if caster else pos + Vector2.RIGHT) - pos).normalized()})
	amount = maxf(1.0, roundf(amount))
	# Mana Shield: part of the hit drains mana instead.
	var ms := target.status.find_field("mana_shield")
	if not ms.is_empty() and target.resource.kind == "mana":
		var part := amount * float(ms.get("pct", 0.5))
		var cost := part * float(ms.get("ratio", 1.2))
		var paid := minf(cost, target.resource.value)
		target.resource.gain(-paid)
		amount -= paid / float(ms.get("ratio", 1.2))
	# Martyrdom / Halo: a share goes to another actor (true damage, never chained).
	if not opts.get("redirected", false):
		var rd := target.status.find_entry_with("redirect")
		if not rd.is_empty() and is_instance_valid(rd.get("src_node")) and rd.get("src_node") is Actor and rd.src_node.is_alive() and rd.src_node != target:
			var share := amount * float(rd.def.redirect)
			amount -= share
			var rctx := env_ctx(0.0)
			rctx.caster = null
			deal_damage(rctx, rd.src_node, share * float(rd.def.get("redirect_taken", 1.0)), {"damage_type": "true", "redirected": true, "dot": true})
	amount = maxf(roundf(amount), 0.0)
	# "Cannot die" rules.
	if amount >= target.health.hp + target.health.absorb and target.is_alive():
		data.amount = amount
		data.prevented = false
		if target.status.has_flag("damage_floor"):
			data.prevented = true
		if not data.prevented:
			var cd := target.status.find_entry_with("cheat_death")
			if not cd.is_empty():
				target.status.remove(cd.id)
				data.prevented = true
				var heal_to := target.health.max_hp * float(cd.def.cheat_death)
				# Tear of the Weeping Goddess: Guardian Spirit restores everything.
				if is_instance_valid(cd.get("src_node")) and cd.src_node is Actor and cd.src_node.stats.has_flag("goddess_tear"):
					heal_to = target.health.max_hp
					target.resource.value = target.resource.max_value
				_after_fatal_heal.call_deferred(target, heal_to)
				fx.number.rpc(pos, "Saved!", "heal")
				fx.gfx.rpc("saved", {"a": target.get_path()})
		if not data.prevented:
			fire(target, "on_fatal", data)
		if data.prevented:
			amount = maxf(target.health.hp + target.health.absorb - 1.0, 0.0)
	# Kill credit must be in place before the blow lands (death fires inside take()), the XP
	# contribution too: a first hit that kills still earns its dealer the kill's XP.
	if caster:
		target.last_attacker = caster
		target.last_attack_ctx = ctx
	if target.has_method("add_contribution") and int(ctx.peer) > 0:
		target.add_contribution(int(ctx.peer))
	# Wyvernscale Jerkin: poison clouds feed the ranger's mana instead of hurting.
	if dtype == "nature" and dot and target.stats.has_flag("toxic_feeder"):
		target.resource.gain(10.0)
		return 0.0
	var absorb_before := target.health.absorb
	var dealt := target.health.take(amount)
	# #81: a shield that soaks part of a hit ripples.
	if absorb_before > 0.5 and target.health.absorb < absorb_before - 0.5:
		fx.gfx.rpc("absorb_hit", {"a": target.get_path()})
	# Hellfire Mitts: burn damage heals the caster for 20%.
	if dot and dtype == "fire" and caster and caster.stats.has_flag("burn_leech") and dealt > 0.0:
		caster.health.heal(dealt * 0.2)
	# Vestment of the Merciful Mother: a broken Power Word: Shield ends (and heals) at once.
	if target.health.absorb <= 0.0 and target.status.has("pw_shield"):
		target.status.remove("pw_shield")
	# Band of the Steadfast Ward: a big hit on an ally rallies the warrior.
	if target.team == Actor.Team.PLAYERS and not dot and amount > target.health.max_hp * 0.3 and game:
		for w in game.players_root.get_children():
			if w != target and w.is_alive() and w.stats.has_flag("steadfast_ward") and w.global_position.distance_to(target.global_position) <= 150.0:
				w.resource.gain(50.0)
				target.health.absorb = maxf(target.health.absorb, target.health.max_hp * 0.2)
				target.health.absorb_time = maxf(target.health.absorb_time, 6.0)
				fx.ring.rpc(target.global_position, 24.0, "#c0c0ff", "")
	data.amount = amount
	data.dealt = dealt
	data.crit = crit
	var kind := "damage" if target.team == Actor.Team.MONSTERS else "hurt"
	if crit:
		kind = "crit"
	elif dot:
		kind = "dot"
	fx.number.rpc(pos, str(int(amount)), kind + ":" + type_color(dtype) if dtype != "physical" else kind)
	target.status.on_damage(amount, dot)
	if not dot and target.is_alive():
		# #81: the hit flash in the damage type's colour (white for physical).
		target.hit_react.rpc(type_color(dtype) if dtype != "physical" and dtype != "true" else "#ffffff")
	if crit and not dot:
		var peers := []
		for x in [caster, target]:
			if x is Player:
				peers.append(x.peer_id)
		fx.gfx.rpc("crit", {"a": target.get_path(), "dir": (pos - (caster.global_position if caster else pos + Vector2.LEFT)).normalized(), "peers": peers})
	# Resources: Fury from dealing and taking damage; on-hit restores (primary attacks).
	target.resource.mark_combat()
	if target.resource.kind == "fury" and target.health.max_hp > 0.0:
		target.resource.gain(amount / target.health.max_hp * float(GameData.bal("fury.per_damage_taken_fraction")) * target.stats.mult("resource_gen") + target.stats.get_stat("fury_on_hit_taken"))
	if caster:
		caster.resource.mark_combat()
		if not dot:
			var on_hit := float(ctx.resource_on_hit)
			if on_hit >= 0.0:
				caster.resource.gain(on_hit * (caster.stats.mult("resource_gen") if caster.resource.kind == "fury" else 1.0))
			elif caster.resource.kind == "fury":
				caster.resource.gain(float(GameData.bal("fury.per_damage_dealt_hit")) * caster.stats.mult("resource_gen"))
		# Unholy Leech Oil: the party's damage heals whoever drank it.
		if caster.team == Actor.Team.PLAYERS and game and not opts.get("reflected", false):
			for pl in game.players_root.get_children():
				if pl.is_alive() and pl.status.has_flag("party_leech"):
					pl.health.heal(amount * float(GameData.bal("combat.party_leech", 0.2)))
		var leech := float(ctx.leech) * caster.stats.mult("leech_efficiency")
		if leech > 0.0 and caster.is_alive():
			var healed := caster.health.heal(amount * leech * caster.stats.mult("healing_taken"))
			if healed >= 1.0:
				fx.number.rpc(caster.global_position, "+%d", "heal", [int(healed)])
				fx.gfx.rpc("leech", {"pos": pos, "b": caster.get_path()})
	# Threat and XP contribution.
	if target.has_method("add_threat") and caster and caster.team != target.team:
		target.add_threat(caster, amount * float(ctx.threat_mult))
	if caster and caster.has_method("add_contribution") and target.get("peer_id") != null:
		caster.add_contribution(int(target.peer_id))  # tanking counts as contributing
	if caster:
		target.last_attacker = caster
		target.last_attack_ctx = ctx
	if target.has_method("on_damaged"):
		target.on_damaged(caster, amount)
	# Reflection (Thorns of Steel, Crown of Thorns, Barrow Thorns Brew).
	if caster and caster != target and not opts.get("reflected", false) and not dot:
		var refl := target.stats.get_stat("reflect_all")
		if melee_hit:
			refl += target.stats.get_stat("reflect_melee")
		if refl > 0.0:
			var rctx2 := make_ctx(target, {"id": "reflect", "school": "physical"})
			fx.gfx.rpc("reflect", {"pos": target.global_position, "to": caster.global_position})
			deal_damage(rctx2, caster, amount * refl, {"damage_type": "true", "reflected": true, "dot": true})
	if not opts.get("no_procs", false):
		if blocked:
			fire(target, "on_block", data)
		if caster:
			# DoT ticks fire on_hit too (data.dot), for procs like Ecstasy in Torment.
			fire(caster, "on_hit", data)
			if crit:
				fire(caster, "on_crit", data)
		fire(target, "on_damaged", data)
		var frac := target.health.fraction()
		if frac > 0.0 and frac < float(GameData.bal("combat.low_hp", 0.3)) and (target.health.hp + dealt) / target.health.max_hp >= float(GameData.bal("combat.low_hp", 0.3)):
			fire(target, "on_low_hp", data)
	return dealt


func _after_fatal_heal(target: Actor, to_hp: float) -> void:
	if is_instance_valid(target) and target.is_alive():
		target.health.hp = maxf(target.health.hp, minf(to_hp, target.health.max_hp))


func _avoided(target: Actor, attacker: Actor, data: Dictionary, event: String) -> void:
	fire(target, event, data)
	if attacker:
		fire(attacker, "on_avoided", data)


func _frontal(target: Actor, from: Vector2) -> bool:
	var to := from - target.global_position
	if to.length() < 1.0:
		return true
	return absf(target.facing.angle_to(to)) <= deg_to_rad(float(GameData.bal("combat.block_arc", 120.0)) / 2.0)


## `burst`: show the heal burst on the target (#33); ticks of drains, zones and heals over time
## don't (they have their own looks).
func heal(ctx: Dictionary, target: Actor, amount: float, burst: bool = true) -> float:
	if not is_instance_valid(target) or not target.is_alive() or amount <= 0.0:
		return 0.0
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	# Forbidden Inversion: direct heals hurt.
	if target.status.has_flag("heal_inverted") and not ctx.get("hot", false):
		return -deal_damage(ctx, target, amount, {"damage_type": "shadow", "dot": true})
	amount *= target.stats.mult("healing_taken")
	var before := target.health.hp
	var healed := target.health.heal(roundf(amount))
	if healed >= 1.0:
		fx.number.rpc(target.global_position, "+%d", "heal", [int(healed)])
		if burst and not ctx.get("hot", false):
			var big := healed >= target.health.max_hp * float(GameData.fx.get("big_heal_fraction", 0.25))
			fx.actor_fx.rpc(target.get_path(), "big_heal" if big else "heal")
	_credit_support(ctx, target, healed * float(GameData.bal("threat.heal_threat_mult")))
	if caster and not ctx.get("from_proc", false):
		fire(caster, "on_heal", {"target": target, "amount": healed, "overheal": maxf(amount - healed, 0.0),
			"before": before, "ctx": ctx, "skill": ctx.get("skill", ""), "hot": ctx.get("hot", false)})
	return healed


## Applies a status through the target's StatusEffects (CC immunity and diminishing returns are
## handled there). Returns true when it landed.
func apply_status(ctx: Dictionary, target: Actor, id: String, duration: float, magnitude: float) -> bool:
	if not is_instance_valid(target) or not target.is_alive():
		return false
	if trap_spares(ctx, target):
		return false
	var landed := target.status.apply(id, duration, magnitude, ctx)
	if not landed:
		fx.number.rpc(target.global_position, "Immune", "info")
		return false
	var def: Dictionary = GameData.status_effects.get(id, {})
	if def.get("debuff", false):
		if target.has_method("add_threat") and is_instance_valid(ctx.caster):
			target.add_threat(ctx.caster, float(GameData.bal("threat.debuff_threat")) * float(ctx.threat_mult))
		if target.has_method("add_contribution") and int(ctx.peer) > 0:
			target.add_contribution(int(ctx.peer))
	elif target != ctx.caster:
		_credit_support(ctx, target, float(GameData.bal("threat.buff_threat")))
	if is_instance_valid(ctx.caster) and not ctx.get("from_proc", false):
		fire(ctx.caster, "on_status_applied", {"target": target, "status": id, "ctx": ctx})
	return true


## Healing/buffing an ally makes enemies fighting that ally angry at the supporter and counts as
## (indirect) contribution to those kills.
func _credit_support(ctx: Dictionary, target: Actor, threat_amount: float) -> void:
	if not is_instance_valid(ctx.caster) or ctx.team != Actor.Team.PLAYERS or not game:
		return
	for e in game.enemies_root.get_children():
		if e.has_method("is_engaged_with") and e.is_engaged_with(target):
			e.add_threat(ctx.caster, threat_amount)
			if int(ctx.peer) > 0:
				e.add_contribution(int(ctx.peer))


## Context for damage that belongs to nobody (lava, spikes, monster-triggered barrels).
## Test harness: a context whose hits can't miss or be dodged (setup kills must land).
func test_ctx(caster: Actor, skill: Dictionary) -> Dictionary:
	var c := make_ctx(caster, skill)
	c.cannot_miss = true
	return c


## #101: the floor's own hazards (lava, spikes, plates, spouts, rifts, snares, runes): like
## env_ctx, marked as a trap - monsters walk through them unharmed.
func trap_ctx() -> Dictionary:
	var c := env_ctx(0.0)
	c.trap = true
	return c


## #101: a trap never hurts the monsters' side (only heroes and their allies).
static func trap_spares(ctx: Dictionary, target: Actor) -> bool:
	return bool(ctx.get("trap", false)) and target.team == Actor.Team.MONSTERS


func env_ctx(power: float) -> Dictionary:
	return {"caster": null, "team": ENV_TEAM, "skill": "", "school": "physical", "damage_type": "physical", "power": power,
		"damage_mult": 1.0, "heal_mult": 1.0, "crit_chance": 0.0, "crit_damage": 0.0, "leech": 0.0,
		"level": 1, "threat_mult": 0.0, "resource_on_hit": -1.0, "radius_mult": 1.0, "duration_mult": 1.0,
		"count_add": 0, "pierce_add": 0, "peer": 0, "origin": Vector2.ZERO, "environment": true, "range_mult": 1.0}


func make_ctx(caster: Actor, skill: Dictionary) -> Dictionary:
	var ctx := Combat.skill_numbers(caster.stats, caster.level, skill)
	ctx.merge({
		"caster": caster, "team": caster.team,
		"peer": int(caster.get("peer_id")) if caster.get("peer_id") != null else 0,
		"origin": caster.global_position,
	})
	if is_instance_valid(caster.friendly_target):
		ctx.friendly = caster.friendly_target
	return ctx


# =========================================================================================
# Procs: {event, chance, icd, if, do | hook} from talents, passives, legendaries, statuses, elites
# =========================================================================================


func fire(actor: Actor, event: String, data: Dictionary) -> void:
	if not is_instance_valid(actor) or _proc_depth > 2:
		return
	var src_ctx: Variant = data.get("ctx")
	if src_ctx is Dictionary and src_ctx.get("from_proc", false) and event in ["on_hit", "on_crit", "on_heal", "on_status_applied"]:
		return
	var list := actor.all_procs()
	if list.is_empty():
		return
	_proc_depth += 1
	for pr in list:
		if str(pr.get("event", "")) != event:
			continue
		if not _proc_ready(actor, pr, data):
			continue
		run_proc(actor, pr, data)
	_proc_depth -= 1


func _proc_ready(actor: Actor, pr: Dictionary, data: Dictionary) -> bool:
	var key := str(pr.get("_key", ""))
	var now := Time.get_ticks_msec() / 1000.0
	if pr.has("icd") and now < float(actor.proc_cd.get(key, 0.0)):
		return false
	if not proc_conditions(actor, pr.get("if", {}), data):
		return false
	if rng.randf() > float(pr.get("chance", 1.0)):
		return false
	if pr.has("icd"):
		actor.proc_cd[key] = now + float(pr.icd)
	return true


func proc_conditions(actor: Actor, cond: Dictionary, data: Dictionary) -> bool:
	var target: Variant = data.get("target")
	for k in cond:
		var v: Variant = cond[k]
		match str(k):
			"skill":
				if not (Array(v) if v is Array else [v]).has(str(data.get("skill", ""))):
					return false
			"school":
				if str(data.get("school", "")) != str(v):
					return false
			"fx":
				# #73: an area of this look (on_aoe: "explosion"...).
				if str(data.get("fx", "")) != str(v):
					return false
			"damage_type":
				if not (Array(v) if v is Array else [v]).has(str(data.get("damage_type", ""))):
					return false
			"element":
				var sk := GameData.skills.get(str(data.get("skill", "")), {}) as Dictionary
				if not (Array(v) if v is Array else [v]).has(str(sk.get("element", ""))):
					return false
			"melee":
				if bool(data.get("melee", false)) != bool(v):
					return false
			"crit":
				if bool(data.get("crit", false)) != bool(v):
					return false
			"dot":
				if bool(data.get("dot", false)) != bool(v):
					return false
			"target_status":
				if not (is_instance_valid(target) and target is Actor and target.status.has_any(Array(v) if v is Array else [v])):
					return false
			"target_flag":
				if not (is_instance_valid(target) and target is Actor and target.status.has_flag(str(v))):
					return false
			"target_creature":
				if not (is_instance_valid(target) and target is Actor and (Array(v) if v is Array else [v]).has(target.creature_type())):
					return false
			"target_hp_below":
				if not (is_instance_valid(target) and target is Actor and target.health.fraction() < float(v)):
					return false
			"target_hp_above":
				if not (is_instance_valid(target) and target is Actor and target.health.fraction() > float(v)):
					return false
			"self_hp_below":
				if actor.health.fraction() >= float(v):
					return false
			"self_status":
				if not actor.status.has_any(Array(v) if v is Array else [v]):
					return false
			"self_flag":
				if not actor.status.has_flag(str(v)):
					return false
			"target_team":
				if not (is_instance_valid(target) and target is Actor and (target.team == actor.team) == (str(v) == "ally")):
					return false
			"amount_above_max_hp_pct":
				if not (is_instance_valid(target) and target is Actor and float(data.get("amount", 0.0)) > target.health.max_hp * float(v)):
					return false
			"xp":
				if bool(data.get("xp", false)) != bool(v):
					return false
			"target_boss":
				if not (is_instance_valid(target) and target is Actor and bool(target.get("is_boss")) == bool(v)):
					return false
			"target_alive":
				if not (is_instance_valid(target) and target is Actor and target.is_alive() == bool(v)):
					return false
			"in_combat":
				if (actor.resource.since_combat() < float(GameData.bal("stats.out_of_combat_delay", 5.0))) != bool(v):
					return false
			"self_stat_flag":
				if not actor.stats.has_flag(str(v)):
					return false
			"self_stacks_at_least":
				if actor.status.stacks_of(str(v[0])) < int(v[1]):
					return false
			"hot":
				if bool(data.get("hot", false)) != bool(v):
					return false
			"status":
				if not (Array(v) if v is Array else [v]).has(str(data.get("status", ""))):
					return false
			"self_resource_at_least":
				if actor.resource.value < float(v):
					return false
			"self_still":
				if float(actor.get("still_time") if actor.get("still_time") != null else 0.0) < float(v):
					return false
			"self_unlit":
				if LightLayers.is_lit(get_tree(), actor.global_position, true) == bool(v):
					return false
			"target_not_self":
				if (is_instance_valid(target) and target == actor) == bool(v):
					return false
			"self_in_own_zone":
				if not in_own_zone(actor, str(v)):
					return false
	return true


## Is the actor standing inside a zone it cast with this skill (Crusader's Greaves)?
func in_own_zone(actor: Actor, skill_id: String) -> bool:
	var zs: Dictionary = get("zones")  # the zone table lives in CombatEffects
	for z in zs.values():
		if z.ctx.get("caster") == actor and str(z.ctx.get("skill", "")) == skill_id and z.pos.distance_to(actor.global_position) <= float(z.radius):
			return true
	return false


## Does any living hero of the party carry this stat flag (party-wide legendary auras)?
func party_has_flag(flag: String) -> bool:
	if game == null:
		return false
	for p in game.players_root.get_children():
		if p.is_alive() and p.stats.has_flag(flag):
			return true
	return false


## Runs one proc: a code hook or its `do` effects, from the actor's position (or the event
## target's with "at": "target").
func run_proc(actor: Actor, pr: Dictionary, data: Dictionary) -> void:
	if pr.has("hook"):
		var h := LegendaryAffixes.new()
		h.call("hook_" + str(pr.hook), self, actor, pr, data)
		return
	var ctx: Dictionary
	var src: Variant = pr.get("_src_ctx")
	if src is Dictionary and is_instance_valid(src.get("caster")):
		# A debuff's proc (Static Charge) acts for whoever applied it.
		ctx = src.duplicate()
	else:
		ctx = make_ctx(actor, {"id": str(pr.get("source", "")), "school": str(pr.get("school", data.get("school", "melee"))),
			"damage_type": str(pr.get("damage_type", data.get("damage_type", "physical")))})
	ctx.from_proc = true
	ctx.event_target = data.get("target")
	ctx.event = data
	var target: Variant = data.get("target")
	var tpos: Vector2 = target.global_position if is_instance_valid(target) and target is Actor else actor.global_position
	var origin := tpos if str(pr.get("at", "self")) == "target" else actor.global_position
	# #73 on_aoe: "at": "point" acts where the area landed.
	if str(pr.get("at", "self")) == "point" and data.get("point") is Vector2:
		origin = data.point
		tpos = data.point
	for eff in pr.get("do", []):
		call("run_effect", eff, ctx, origin, tpos)
