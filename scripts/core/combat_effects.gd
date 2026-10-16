class_name CombatEffects
extends CombatCore
## Effect primitives (data `type`s, see Combat.EFFECT_TYPES and docs/DATA.md) and the host
## simulation of the entities they create: projectiles, zones / traps / deployables, delayed
## effects, tethers, channels and dynamic terrain. Skills, monster abilities, procs and status
## callbacks are all built from these.

var projectiles: Dictionary = {}
var zones: Dictionary = {}
var delayed: Array = []
var tethers: Dictionary = {}
var last_dealt := 0.0  ## damage of the last hit_target (on_hit effects can scale with it)
var _next_id := 1


func new_id() -> int:
	_next_id += 1
	return _next_id


func clear_floor() -> void:
	for id in projectiles.keys():
		fx.projectile_end.rpc(id, projectiles[id].pos)
	projectiles.clear()
	for id in zones.keys():
		fx.zone_end.rpc(id)
	zones.clear()
	for id in tethers.keys():
		fx.tether_end.rpc(id)
	tethers.clear()
	delayed.clear()


func run_effect(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	# A status reaction that only happens for heroes wearing a legendary (Merciful Mother).
	if eff.has("if_caster_flag") and not (is_instance_valid(ctx.get("caster")) and ctx.caster.stats.has_flag(str(eff.if_caster_flag))):
		return
	if eff.has("chance") and rng.randf() > float(eff.chance):
		return
	if eff.has("if") and not proc_conditions(ctx.caster if is_instance_valid(ctx.caster) else null, eff["if"], ctx.get("event", {"target": ctx.get("event_target")})):
		return
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if eff.has("aim_at"):
		var picked := select_targets({"target": eff.aim_at, "range": eff.get("aim_range", 300)}, ctx, origin, aim)
		if picked.is_empty():
			return
		aim = picked[0].global_position
	if str(eff.get("from", "")) == "target" and is_instance_valid(ctx.get("event_target")) and ctx.get("event_target") is Actor:
		origin = ctx.event_target.global_position
	var dir := (aim - origin).normalized()
	if dir == Vector2.ZERO:
		dir = caster.facing if caster else Vector2.RIGHT
	match str(eff.type):
		"melee", "cone":
			_melee(eff, ctx, origin, dir)
		"projectile":
			var count := int(eff.get("count", 1)) + int(ctx.count_add)
			var spread := deg_to_rad(float(eff.get("spread", 0.0)))
			for i in count:
				var a := 0.0
				if count > 1:
					if spread >= TAU - 0.01:
						a = TAU * i / count
					else:
						a = lerpf(-spread / 2.0, spread / 2.0, float(i) / (count - 1))
				spawn_projectile(eff, ctx, origin, dir.rotated(a), aim)
		"aoe":
			var center := origin if eff.get("at", "self") == "self" else clamp_range(origin, aim, float(eff.get("max_range", 300)))
			var delay := float(eff.get("delay", 0.0))
			if delay > 0.0:
				fx.telegraph.rpc(center, float(eff.radius) * float(ctx.radius_mult), str(eff.get("color", "#ff4422")), delay)
				delayed.append({"left": delay, "eff": eff, "ctx": ctx, "pos": center, "aoe": true})
			else:
				apply_aoe(eff, ctx, center)
		"zone", "trap", "deploy":
			var default_at := "self" if eff.type == "zone" else "aim"
			var zpos := origin if eff.get("at", default_at) == "self" else clamp_range(origin, aim, float(eff.get("max_range", 220)))
			if str(eff.get("at", "")) == "behind":
				zpos = origin - dir * float(eff.get("offset", 30))
			add_zone(eff, ctx, zpos)
		"dash":
			_dash(eff, ctx, origin, dir)
		"leap":
			_leap(eff, ctx, origin, aim, dir)
		"charge":
			_charge(eff, ctx, origin, dir)
		"blink":
			if caster and not caster.stats.has_flag("no_teleport"):
				var dest := walkable_point(origin, dir, float(eff.distance))
				fx.blink.rpc(origin, dest)
				if eff.has("decoy"):
					_spawn_decoy(eff.decoy, ctx, origin)
				caster.host_teleport(dest)
		"teleport":
			_teleport(eff, ctx, origin, aim)
		"status":
			var st_eff := eff
			# Mandate of Victory: shouts reach the whole floor.
			if eff.get("shout", false) and caster and caster.stats.has_flag("floor_wide_shouts"):
				st_eff = eff.merged({"radius": 99999.0}, true)
			for t in select_targets(st_eff, ctx, origin, aim):
				var times := int(eff.get("stacks", 1))
				if eff.has("stacks_from"):
					var sf: Dictionary = eff.stacks_from
					times = mini(enemies_of(t.team, t.global_position, float(sf.get("enemies_within", 100))).size(), int(sf.get("max", 30)))
					t.status.remove(str(eff.status))
					if times <= 0:
						continue
				for i in times:
					apply_status(ctx, t, str(eff.status), float(eff.duration) * float(ctx.duration_mult), _magnitude(eff, ctx, t))
		"remove_status":
			for t in select_targets(eff, ctx, origin, aim):
				t.status.remove(str(eff.status))
		"heal":
			# Tome of Dire Anathema: a heal aimed at an enemy sears it for double as shadow.
			var foes: Array = enemies_of(ctx.team, aim, 32.0) if caster and caster.stats.has_flag("anathema") and str(eff.get("target", "")) == "aim_ally" and origin.distance_to(aim) <= float(eff.get("range", 240)) + 32.0 else []
			if not foes.is_empty():
				deal_damage(ctx, foes[0], _heal_amount(eff, ctx, foes[0]) * 2.0, {"damage_type": "shadow"})
			else:
				for t in select_targets(eff, ctx, origin, aim):
					heal(ctx, t, _heal_amount(eff, ctx, t))
		"absorb":
			for t in select_targets(eff, ctx, origin, aim):
				var amount2 := _heal_amount(eff, ctx, t, "amount")
				t.health.absorb = maxf(t.health.absorb, amount2)
				t.health.absorb_time = float(eff.duration)
				t.status.apply(str(eff.get("status", "holy_shield")), float(eff.duration), amount2, ctx)
				_credit_support(ctx, t, amount2)
				fx.ring.rpc(t.global_position, 24.0, "#ffe680", "")
		"taunt":
			var r := float(eff.radius) * float(ctx.radius_mult)
			var taunter: Actor = caster
			if str(eff.get("by", "")) == "event_target" and ctx.get("event_target") is Actor:
				taunter = ctx.event_target
			for e in enemies_of(ctx.team, origin, r):
				if e.has_method("taunted_by") and taunter:
					e.taunted_by(taunter, float(eff.duration))
					if eff.has("on_taunted"):
						for sub in eff.on_taunted:
							run_effect(sub, _with_target(ctx, e), e.global_position, e.global_position)
			fx.ring.rpc(origin, r, str(eff.get("color", "#ff5533")), "")
		"resource":
			for t in select_targets(eff, ctx, origin, aim):
				var amt: float = float(eff.get("amount", 0.0)) + t.resource.max_value * float(eff.get("pct", 0.0))
				var rev: Variant = ctx.get("event")
				if eff.has("amount_event_pct") and rev is Dictionary:
					amt += float(rev.get("amount", 0.0)) * float(eff.amount_event_pct)
				t.resource.gain(amt * (t.stats.mult("resource_gen") if t.resource.kind == "fury" and amt > 0.0 else 1.0))
		"summon":
			if game and game.has_method("summon_monsters"):
				game.summon_monsters(str(eff.monster), int(eff.count), origin if eff.get("at", "self") == "self" else aim, float(eff.get("radius", 80)), caster, eff)
		"hit":
			_hit(eff, ctx, origin, aim)
		"line":
			_line(eff, ctx, origin, dir)
		"chain":
			_chain(eff, ctx, origin, aim)
		"beam":
			_beam(eff, ctx, origin, dir)
		"knockback", "pull":
			_push(eff, ctx, origin, aim)
		"delayed":
			var at := clamp_range(origin, aim, float(eff.get("max_range", 300))) if eff.get("at", "aim") == "aim" else origin
			if eff.has("telegraph"):
				fx.telegraph.rpc(at, float(eff.telegraph.get("radius", 40)), str(eff.telegraph.get("color", "#ff4422")), float(eff.delay))
			delayed.append({"left": float(eff.delay), "effects": eff.effects, "ctx": ctx, "pos": at, "follow": caster if eff.get("follow", false) else null})
		"consume_dots":
			for t in select_targets(eff, ctx, origin, aim, "aim_enemy"):
				var total: float = t.status.consume_dot_damage(Array(eff.get("statuses", ["burn"])))
				if total > 0.0:
					deal_damage(ctx, t, total * float(eff.get("mult", 1.0)), {"damage_type": str(eff.get("damage_type", "fire"))})
					fx.ring.rpc(t.global_position, 30.0, str(eff.get("color", "#ff7a2a")), "explosion")
		"cleanse", "dispel":
			var n := 0
			for t in select_targets(eff, ctx, origin, aim, "self" if eff.type == "cleanse" else "aim_enemy"):
				n += t.status.cleanse(Array(eff.get("categories", [])), int(eff.get("count", 99)), eff.type == "cleanse")
			if n > 0 and caster:
				if eff.has("refund"):
					caster.resource.gain(float(eff.refund))
				fire(caster, "on_cleanse", {"count": n, "ctx": ctx, "skill": str(ctx.get("skill", ""))})
		"free_cast":
			# A skill fired for free (no cost, no cooldown) by a legendary: Viperleap, Brierheart, Vindicator.
			var fsk := GameData.skill(str(eff.skill))
			var ft: Array = select_targets(eff, ctx, origin, aim, "nearest_enemy")
			var faim: Vector2 = ft[0].global_position if not ft.is_empty() and is_instance_valid(ft[0]) else aim
			if caster and not fsk.is_empty():
				var fctx := make_ctx(caster, fsk)
				fctx.from_proc = true
				var fdir := (faim - caster.global_position).normalized()
				for fe in fsk.effects:
					run_effect(fe, fctx, caster.global_position, faim)
				fx.sound.rpc(str(fsk.get("sfx", "cast")), caster.global_position)
		"replay_skill":
			# A skill's effects again from here (Cowl of the Frozen Spire's second nova).
			var rsk := GameData.skill(str(eff.skill))
			if caster and not rsk.is_empty():
				var rctx := make_ctx(caster, rsk)
				rctx.from_proc = true
				for re in rsk.effects:
					run_effect(re, rctx, origin, aim)
		"threat_bonus":
			# Mace of Veracity: the blow's damage counts again as threat.
			var tt: Variant = ctx.get("event_target")
			var ev2: Variant = ctx.get("event")
			if is_instance_valid(tt) and tt.has_method("add_threat") and caster and ev2 is Dictionary:
				tt.add_threat(caster, float(ev2.get("amount", 0.0)) * float(eff.get("mult", 2.0)))
		"break_absorb":
			# Shatters damage-absorbing wards (Iron Punisher's forging hammer).
			for t in select_targets(eff, ctx, origin, aim, "aim_enemy"):
				if t.health.absorb > 0.0:
					t.health.absorb = 0.0
					fx.number.rpc(t.global_position, "Ward shattered", "info")
		"extinguish":
			# Snuffs wall torches and carried torches within `radius` (Banshee's shriek).
			var er := float(eff.get("radius", 200))
			if game:
				for t in game.dungeon.torches.values():
					if is_instance_valid(t) and t.is_lit() and t.global_position.distance_to(origin) <= er:
						game.dungeon.set_torch_state.rpc(t.torch_id, t.State.BROKEN)
				for pl in game.players_root.get_children():
					if pl.torch_left > 0.0 and pl.global_position.distance_to(origin) <= er:
						pl.torch_left = 0.0
						pl.torch_sync = 0
		"destroy_projectiles":
			destroy_projectiles_in(ctx, origin, dir, float(eff.get("range", 120)), float(eff.get("arc", 360)))
		"terrain":
			_terrain(eff, ctx, origin, aim, dir)
		"threat_drop":
			for t in select_targets(eff, ctx, origin, aim, "self"):
				for e in game.enemies_root.get_children():
					if e.has_method("drop_threat"):
						e.drop_threat(t, float(eff.get("fraction", 1.0)))
		"reveal":
			var rr := float(eff.get("radius", 250))
			var at2 := clamp_range(origin, aim, float(eff.get("max_range", 260))) if eff.get("at", "self") == "aim" else origin
			for e2 in all_actors():
				if e2 is Actor and e2.team != ctx.team and e2.global_position.distance_to(at2) <= rr:
					e2.status.remove_flag("stealthed")
					e2.status.apply("revealed", float(eff.get("duration", 6)), 0.0, ctx)
			if eff.has("light"):
				add_zone({"type": "zone", "radius": rr, "duration": float(eff.get("duration", 6)), "color": str(eff.get("color", "#ffe9a0")), "light_only": true}, ctx, at2)
		"interrupt":
			for t in select_targets(eff, ctx, origin, aim, "aim_enemy"):
				if not t.casting.is_empty() or not t.channel.is_empty():
					var was: Dictionary = GameData.skills.get(str(t.casting.get("skill", t.channel.get("skill", ""))), {})
					t.casting = {}
					t.channel = {}
					fx.number.rpc(t.global_position, "Interrupted", "info")
					if eff.has("lockout"):
						t.status.apply("school_lockout", float(eff.lockout), 0.0, ctx)
						t.lockout_element = str(was.get("element", was.get("school", "spell")))
				if eff.has("on_interrupt"):
					for sub2 in eff.on_interrupt:
						run_effect(sub2, _with_target(ctx, t), t.global_position, t.global_position)
		"cooldown":
			for t in select_targets(eff, ctx, origin, aim, "self"):
				for sid in eff.get("skills", []):
					if eff.has("reduce"):
						t.cooldowns[sid] = maxf(float(t.cooldowns.get(sid, 0.0)) - float(eff.reduce), 0.0)
					else:
						t.cooldowns.erase(sid)
					if t.has_method("sync_cooldown"):
						t.sync_cooldown(sid)
		"self_damage":
			if caster:
				var hp_cost := caster.health.hp * float(eff.get("pct_current", 0.0)) + caster.health.max_hp * float(eff.get("pct_max", 0.0)) + float(eff.get("amount", 0.0))
				caster.health.hp = maxf(1.0, caster.health.hp - hp_cost)
				fx.number.rpc(caster.global_position, str(int(hp_cost)), "hurt")
		"resource_drain":
			for t in select_targets(eff, ctx, origin, aim, "aim_enemy"):
				var take := minf(t.resource.value, float(eff.get("amount", t.resource.value)))
				t.resource.gain(-take)
				if eff.get("to_damage", false):
					deal_damage(ctx, t, take * float(eff.get("mult", 1.0)), {"damage_type": str(eff.get("damage_type", "physical"))})
		"tether":
			_tether(eff, ctx, origin, aim)
		"stored_damage":
			var st: Variant = ctx.get("stored")
			for t in select_targets(eff, ctx, origin, aim, "event_target"):
				if st is float and st > 0.0:
					deal_damage(ctx, t, st * float(eff.get("mult", 1.0)), {"damage_type": str(eff.get("damage_type", "physical")), "dot": true})
		"spread":
			var from_t: Variant = ctx.get("event_target")
			var near := enemies_of(ctx.team, origin, float(eff.get("radius", 120))).filter(func(x): return x != from_t and not x.status.has(str(eff.status)))
			near.sort_custom(func(x, y): return x.global_position.distance_to(origin) < y.global_position.distance_to(origin))
			for i in mini(int(eff.get("count", 1)), near.size()):
				apply_status(ctx, near[i], str(eff.status), float(eff.duration), float(ctx.get("magnitude", 0.0)))
		"revive":
			for t in select_targets(eff, ctx, origin, aim, "aim_ally"):
				if t.has_method("revive") and t.get("life_state") == 1:
					t.revive(float(eff.get("hp", 0.5)))
		"fetch":
			# Leap of Faith: pull the chosen ally to the caster's feet.
			for t in select_targets(eff, ctx, origin, aim, "aim_ally"):
				if t != caster and caster:
					var spot := walkable_point(caster.global_position, (t.global_position - caster.global_position).normalized(), 22.0)
					fx.blink.rpc(t.global_position, spot)
					t.host_teleport(spot)
		"prevent_death":
			# Inside an on_fatal proc: the blow leaves the actor at 1 HP.
			var ev: Variant = ctx.get("event")
			if ev is Dictionary:
				ev.prevented = true
		"toggle_status":
			for t in select_targets(eff, ctx, origin, aim, "self"):
				if t.status.has(str(eff.status)):
					t.status.remove(str(eff.status))
				else:
					t.status.apply(str(eff.status), -1.0, 0.0, ctx)
		_:
			push_error("Combat: unknown effect type '%s'" % eff.type)


func _with_target(ctx: Dictionary, t: Actor, amount: float = 0.0) -> Dictionary:
	var c := ctx.duplicate()
	c.event_target = t
	var ev: Dictionary = (ctx.get("event", {}) as Dictionary).duplicate() if ctx.get("event") is Dictionary else {}
	ev.target = t
	if amount > 0.0:
		ev.amount = amount
	c.event = ev
	return c


func _magnitude(eff: Dictionary, ctx: Dictionary, t: Actor = null) -> float:
	if not eff.has("magnitude"):
		return 0.0
	var m: Variant = eff.magnitude
	var v := value_of_spec(m, ctx)
	if m is Dictionary and t:
		v += t.health.max_hp * float(m.get("pct_target_max_hp", 0.0))
		if is_instance_valid(ctx.caster) and ctx.caster is Actor:
			v += ctx.caster.health.max_hp * float(m.get("pct_caster_max_hp", 0.0))
	return v


func _heal_amount(eff: Dictionary, ctx: Dictionary, t: Actor, key: String = "amount") -> float:
	var spec: Variant = eff.get(key, {})
	var v := value_of_spec(spec, ctx) * float(ctx.heal_mult)
	if spec is Dictionary:
		v += t.health.max_hp * float(spec.get("pct_target_max_hp", 0.0))
		v += float(ctx.get("magnitude", 0.0)) * float(spec.get("ctx_magnitude", 0.0))
		# Healing from the triggering event (Vampiric Embrace, Overflowing Grace, ...).
		var ev: Variant = ctx.get("event")
		if ev is Dictionary and spec.has("event_pct"):
			var ev_amount := float(ev.get(str(spec.get("event_field", "amount")), 0.0)) * float(spec.event_pct)
			if spec.get("split", false) and game:
				ev_amount /= maxf(1.0, game.players_root.get_children().filter(func(x): return x.is_alive()).size())
			v += ev_amount
		if spec.has("max_pct_target_max_hp"):
			v = minf(v, t.health.max_hp * float(spec.max_pct_target_max_hp))
		if is_instance_valid(ctx.caster) and ctx.caster is Actor:
			v += ctx.caster.health.max_hp * float(spec.get("pct_caster_max_hp", 0.0))
	if t.health.fraction() < float(ctx.get("low_hp_heal_below", 0.0)):
		v *= 1.0 + float(ctx.get("low_hp_heal_bonus", 0.0))
	return v


func value_of_spec(spec: Variant, ctx: Dictionary) -> float:
	return Combat.value_of(spec, ctx)


## Damage of a spec against one target (the extras need the target: max HP %, armor scaling).
func damage_value(spec: Variant, ctx: Dictionary, target: Actor) -> float:
	if not spec is Dictionary:
		return 0.0
	var v := value_of_spec(spec, ctx)
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if target:
		v += target.health.max_hp * float(spec.get("pct_target_max_hp", 0.0))
	if caster:
		v += caster.stats.get_stat("armor") * float(spec.get("armor_coef", 0.0)) * float(ctx.damage_mult)
		v += caster.stats.get_stat("block_value") * float(spec.get("block_coef", 0.0)) * float(ctx.damage_mult)
		v += caster.health.max_hp * float(spec.get("pct_caster_max_hp", 0.0))
	v *= 1.0 + float(ctx.get("extra_resource", 0.0)) * float(spec.get("per_extra_resource", 0.0))
	if target and spec.has("per_stack"):
		v *= 1.0 + target.status.stacks_of(str(spec.per_stack.status)) * float(spec.per_stack.get("add", 0.0))
	var ev: Variant = ctx.get("event")
	if ev is Dictionary and spec.has("event_pct"):
		v += float(ev.get(str(spec.get("event_field", "amount")), 0.0)) * float(spec.event_pct)
	if target and spec.has("below_hp") and target.health.fraction() < float(spec.below_hp):
		v *= float(spec.get("below_mult", 1.0))
	if target and spec.has("vs_creature") and Array(spec.vs_creature).has(target.creature_type()):
		v *= float(spec.get("creature_mult", 1.0))
	return v * float(ctx.get("charge", 1.0))


func hit_target(target: Actor, eff: Dictionary, ctx: Dictionary, area: bool) -> bool:
	if not is_instance_valid(target) or not target.is_targetable():
		return false
	var landed := true
	last_dealt = 0.0
	if eff.has("damage"):
		var opts := {"area": area, "damage_type": GameData.damage_type_of(GameData.skills.get(str(ctx.skill), {"school": ctx.school}), eff)}
		if eff.has("dot"):
			opts.dot = true
		var c := ctx
		if eff.get("guaranteed_crit", false) or (eff.has("crit_vs") and Array(eff.crit_vs).has(target.creature_type())):
			c = ctx.duplicate()
			c.guaranteed_crit = true
		var dealt := deal_damage(c, target, damage_value(eff.damage, c, target), opts)
		landed = dealt >= 0.0
		last_dealt = maxf(dealt, 0.0)
		# Drain Soul / Vampiric strikes: heal the caster for a share of the damage.
		if dealt > 0.0 and eff.has("drain") and is_instance_valid(ctx.caster):
			heal(ctx, ctx.caster, dealt * float(eff.drain))
	if not landed:
		return false
	for oh in eff.get("on_hit", []):
		match str(oh.type):
			"status":
				if not oh.has("if") or proc_conditions(ctx.caster if is_instance_valid(ctx.caster) else null, oh["if"], {"target": target}):
					for i in int(oh.get("stacks", 1)):
						apply_status(ctx, target, str(oh.status), float(oh.duration) * float(ctx.duration_mult), _magnitude(oh, ctx, target))
			"knockback":
				var from: Vector2 = ctx.caster.global_position if is_instance_valid(ctx.caster) else ctx.origin
				knock(target, (target.global_position - from).normalized() * float(oh.force))
			"threat":
				if target.has_method("add_threat") and is_instance_valid(ctx.caster):
					target.add_threat(ctx.caster, float(oh.amount))
			_:
				var sub: Dictionary = oh.duplicate()
				if not sub.has("target"):
					sub.target = "event_target"
				run_effect(sub, _with_target(ctx, target, last_dealt), target.global_position, target.global_position)
	return true


## Forced movement on the host. Knockback / pull immunity comes from statuses and stats.
func knock(target: Actor, push: Vector2) -> void:
	if target.status.has_flag("knockback_immune") or target.stats.has_flag("knockback_immune"):
		return
	target.host_knockback(push)


# =========================================================================================
# Area primitives
# =========================================================================================


func _melee(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var reach := float(eff.range) * float(ctx.radius_mult)
	var half_arc := deg_to_rad(float(eff.get("arc", 90))) / 2.0
	var hits: Array = []
	for a in enemies_of(ctx.team, origin, reach + 12.0):
		var to: Vector2 = a.global_position - origin
		if to.length() < 10.0 or absf(dir.angle_to(to)) <= half_arc:
			if has_los(origin, a.global_position):
				hits.append(a)
	hits.sort_custom(func(x, y): return x.global_position.distance_to(origin) < y.global_position.distance_to(origin))
	var max_targets := int(eff.get("max_targets", 99)) + int(ctx.get("count_add", 0))
	var area: bool = eff.type == "cone"
	for i in mini(hits.size(), max_targets):
		hit_target(hits[i], eff, ctx, area)
	if ctx.team != ENV_TEAM and game:
		for p in game.dungeon.props_in_radius(origin, reach):
			var tp: Vector2 = p.global_position - origin
			if tp.length() < 10.0 or absf(dir.angle_to(tp)) <= half_arc:
				p.take_damage(value_of_spec(eff.get("damage", {}), ctx), ctx)
	fx.melee.rpc(origin, dir, reach, rad_to_deg(half_arc * 2.0), str(eff.get("fx", "slash")))


func apply_aoe(eff: Dictionary, ctx: Dictionary, center: Vector2) -> void:
	var r := float(eff.radius) * float(ctx.radius_mult)
	var targets_kind: String = eff.get("targets", "enemies")
	if eff.has("damage") or targets_kind == "enemies":
		var hits := 0
		for a in hostile_in_radius(ctx, center, r, true):
			# Splash around a struck target leaves that target out; "creatures" limits the kinds hit.
			if eff.get("exclude_target", false) and a == ctx.get("event_target"):
				continue
			if eff.has("creatures") and not Array(eff.creatures).has(a.creature_type()):
				continue
			if eff.has("max_targets") and hits >= int(eff.max_targets):
				break
			if has_los(center, a.global_position):
				hit_target(a, eff, ctx, true)
				hits += 1
	if eff.has("heal") or targets_kind == "allies":
		for a in allies_of(ctx.team, center, r):
			if eff.has("heal"):
				heal(ctx, a, _heal_amount(eff, ctx, a, "heal"))
			for sub in eff.get("ally_effects", []):
				var s2: Dictionary = sub.duplicate()
				s2.target = "event_target"
				run_effect(s2, _with_target(ctx, a), a.global_position, a.global_position)
	if eff.has("damage") and game:
		for p in game.dungeon.props_in_radius(center, r):
			p.take_damage(value_of_spec(eff.damage, ctx), ctx)
	if eff.get("destroys_projectiles", false):
		destroy_projectiles_in(ctx, center, Vector2.RIGHT, r, 360.0)
	fx.ring.rpc(center, r, str(eff.get("color", "#ffffff")), str(eff.get("fx", "")))
	if eff.has("shake"):
		fx.shake.rpc(center, float(eff.shake))


## Thick segment from the origin: thrusts, piercing bolts (optionally through walls, with a
## damage bonus when a wall was crossed), beams.
func _line(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var length := float(eff.get("length", 70)) * float(ctx.get("range_mult", 1.0))
	var width := float(eff.get("width", 16))
	var through := bool(eff.get("through_walls", false))
	var end := origin + dir * length
	if not through:
		end = walkable_point(origin, dir, length) + dir * 14.0
	var hits := _actors_on_segment(ctx, origin, end, width)
	var max_targets := int(eff.get("max_targets", 99))
	for i in mini(hits.size(), max_targets):
		var t: Actor = hits[i]
		var c := ctx
		if through and not has_los(origin, t.global_position) and eff.has("wall_bonus"):
			c = ctx.duplicate()
			c.damage_mult = float(ctx.damage_mult) * float(eff.wall_bonus)
		hit_target(t, eff, c, false)
	fx.beam.rpc(origin, end, str(eff.get("color", "#ffffff")), float(eff.get("fx_time", 0.15)), str(eff.get("fx", "thrust")))


func _actors_on_segment(ctx: Dictionary, a: Vector2, b: Vector2, width: float) -> Array:
	var out: Array = []
	for t in hostile_in_radius(ctx, (a + b) / 2.0, a.distance_to(b) / 2.0 + width + 16.0, false):
		var cp := Geometry2D.get_closest_point_to_segment(t.global_position, a, b)
		if cp.distance_to(t.global_position) <= width + t.radius:
			out.append(t)
	out.sort_custom(func(x, y): return x.global_position.distance_to(a) < y.global_position.distance_to(a))
	return out


## Instant beam: damages (and on_hit) enemies on the line, heals allies on it (Luminance).
func _beam(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var length := float(eff.get("length", 250)) * float(ctx.get("range_mult", 1.0))
	var end := walkable_point(origin, dir, length) + dir * 14.0
	var width := float(eff.get("width", 14))
	if eff.has("damage") or eff.has("on_hit"):
		for t in _actors_on_segment(ctx, origin, end, width):
			hit_target(t, eff, ctx, false)
	if eff.has("heal"):
		for a in allies_of(ctx.team, (origin + end) / 2.0, origin.distance_to(end) / 2.0 + width):
			var cp := Geometry2D.get_closest_point_to_segment(a.global_position, origin, end)
			if cp.distance_to(a.global_position) <= width + a.radius:
				heal(ctx, a, _heal_amount(eff, ctx, a, "heal"))
	fx.beam.rpc(origin, end, str(eff.get("color", "#ffe680")), 0.25, "beam")


## Single-target strike on the aimed enemy (or `target`), with a beam / bolt visual.
func _hit(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var targets := select_targets(eff, ctx, origin, aim, "aim_enemy")
	# Void Needle: the beam forks to the enemies nearest the first target (within the skill's range).
	var extra_n := int(ctx.caster.stats.skill_mod(str(ctx.get("skill", "")), "beam_targets_add")) if is_instance_valid(ctx.get("caster")) else 0
	if extra_n > 0 and not targets.is_empty():
		var near: Array = enemies_of(ctx.team, origin, float(eff.get("range", 250)) * float(ctx.get("range_mult", 1.0)))
		var first_pos: Vector2 = targets[0].global_position
		near.sort_custom(func(x, y): return x.global_position.distance_to(first_pos) < y.global_position.distance_to(first_pos))
		for e in near:
			if extra_n <= 0:
				break
			if not targets.has(e):
				targets.append(e)
				extra_n -= 1
	for t in targets:
		if t.team == ctx.team and t != ctx.caster:
			# Smite on an ally: the ally part of the skill.
			for sub in eff.get("ally_effects", []):
				var s2: Dictionary = sub.duplicate()
				s2.target = "event_target"
				run_effect(s2, _with_target(ctx, t), t.global_position, t.global_position)
			fx.beam.rpc(origin, t.global_position, str(eff.get("ally_color", "#aaffaa")), 0.2, str(eff.get("fx", "bolt")))
			continue
		hit_target(t, eff, ctx, false)
		if str(eff.get("fx", "bolt")) != "none":
			fx.beam.rpc(origin, t.global_position, str(eff.get("color", "#ffffff")), 0.18, str(eff.get("fx", "bolt")))


## Chain Lightning / Trickshot: hits the aimed enemy, then jumps to the nearest un-hit enemy.
func _chain(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var first := aim_enemy(ctx, origin, aim, float(eff.get("range", 250)) * float(ctx.get("range_mult", 1.0)), 80.0)
	if first == null:
		fx.beam.rpc(origin, clamp_range(origin, aim, float(eff.get("range", 250))), str(eff.get("color", "#fff26a")), 0.15, "chain")
		return
	var hit: Array = []
	var cur: Actor = first
	var from := origin
	var jumps := int(eff.get("jumps", 3)) + int(ctx.count_add)
	for i in jumps + 1:
		if cur == null:
			break
		hit.append(cur)
		if i == 0 and eff.get("skip_first", false):
			# Stormstring Gloves: the arc starts at the struck target and jumps on from it.
			from = cur.global_position
			var nx: Actor = null
			var bd := float(eff.get("jump_range", 120))
			for e0 in enemies_of(ctx.team, from, bd):
				if not hit.has(e0) and has_los(from, e0.global_position) and e0.global_position.distance_to(from) <= bd:
					bd = e0.global_position.distance_to(from)
					nx = e0
			cur = nx
			continue
		var c := ctx.duplicate()
		c.damage_mult = float(ctx.damage_mult) * (1.0 + float(eff.get("per_jump", 0.0)) * i)
		fx.beam.rpc(from, cur.global_position, str(eff.get("color", "#fff26a")), 0.2, "chain")
		hit_target(cur, eff, c, false)
		if is_instance_valid(ctx.caster) and i > 0:
			fire(ctx.caster, "on_chain_jump", {"target": cur, "ctx": ctx, "skill": ctx.skill})
		from = cur.global_position
		var next: Actor = null
		var best := float(eff.get("jump_range", 120))
		for e in enemies_of(ctx.team, from, best):
			if hit.has(e) or not has_los(from, e.global_position):
				continue
			var d: float = e.global_position.distance_to(from)
			if d <= best:
				best = d
				next = e
		cur = next


## Knockback / pull: radial from a point (aim or self), or along the aim direction.
func _push(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var center := origin if eff.get("at", "self") == "self" else clamp_range(origin, aim, float(eff.get("max_range", 220)))
	var r := float(eff.get("radius", 100)) * float(ctx.radius_mult)
	var targets: Array = select_targets(eff, ctx, center, aim) if eff.has("target") else hostile_in_radius(ctx, center, r, true)
	var dir := (aim - origin).normalized()
	var half := deg_to_rad(float(eff.get("arc", 360))) / 2.0
	for t in targets:
		var to: Vector2 = t.global_position - center
		if half < PI and to.length() > 8.0 and absf(dir.angle_to(to)) > half:
			continue
		var force := float(eff.get("force", 120))
		if eff.type == "pull":
			var dist := maxf(to.length() - float(eff.get("stop_at", 20)), 0.0)
			knock(t, -to.normalized() * minf(force, dist * 4.0))
		else:
			knock(t, (to.normalized() if to.length() > 1.0 else dir) * force)
		for sub in eff.get("on_hit", []):
			var s2: Dictionary = sub.duplicate()
			if not s2.has("target"):
				s2.target = "event_target"
			run_effect(s2, _with_target(ctx, t), t.global_position, t.global_position)
	if eff.has("color"):
		fx.ring.rpc(center, r, str(eff.color), "")


# =========================================================================================
# Movement primitives
# =========================================================================================


func _dash(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if caster == null:
		return
	var dest := walkable_point(origin, dir, float(eff.distance))
	var duration := origin.distance_to(dest) / float(eff.get("speed", 700))
	caster.host_dash(dest, duration)
	if eff.has("on_arrive"):
		for sub in eff.on_arrive:
			delayed_effect(sub, ctx, dest, duration)


## Heroic Leap / Disengage: an arc to the aim point (or backwards) that lands with effects.
func _leap(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2, dir: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if caster == null:
		return
	var dist := minf(origin.distance_to(aim), float(eff.get("distance", 200)))
	var ldir := dir
	if str(eff.get("direction", "aim")) == "back":
		ldir = -dir
		dist = float(eff.get("distance", 140))
	var dest := walkable_point(origin, ldir, dist)
	var duration := float(eff.get("duration", 0.45))
	caster.host_dash(dest, duration)
	fx.leap.rpc(caster.get_path(), duration)
	for sub in eff.get("on_start", []):
		run_effect(sub, ctx, origin, origin)
	for sub2 in eff.get("on_arrive", []):
		delayed_effect(sub2, ctx, dest, duration)


## Deadly Charge: dash that knocks back and damages everything on its path.
func _charge(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if caster == null:
		return
	var dest := walkable_point(origin, dir, float(eff.get("distance", 240)))
	var duration := origin.distance_to(dest) / float(eff.get("speed", 760))
	var path_eff: Dictionary = {"damage": eff.get("path_damage", {}), "on_hit": eff.get("path_on_hit", [])}
	if not eff.has("path_damage"):
		path_eff.erase("damage")
	for t in _actors_on_segment(ctx, origin, dest, float(eff.get("width", 18))):
		hit_target(t, path_eff, ctx, false)
	caster.host_dash(dest, duration)
	for sub in eff.get("on_arrive", []):
		delayed_effect(sub, ctx, dest, duration)


func _teleport(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if caster == null or caster.stats.has_flag("no_teleport"):
		return
	var dest := origin
	match str(eff.get("to", "aim")):
		"aim":
			dest = walkable_point(origin, (aim - origin).normalized(), minf(origin.distance_to(aim), float(eff.get("distance", 160))))
		"target_front", "behind_target":
			var ts := select_targets({"target": "event_target"}, ctx, origin, aim)
			if ts.is_empty():
				ts = select_targets({"target": "aim_enemy", "range": eff.get("range", 260)}, ctx, origin, aim)
			if ts.is_empty():
				return
			var t: Actor = ts[0]
			var away := (origin - t.global_position).normalized()
			if str(eff.to) == "behind_target":
				away = -away
			dest = walkable_point(t.global_position, away, float(eff.get("offset", 24)))
		"away":
			var ang := rng.randf_range(0.0, TAU)
			dest = walkable_point(origin, Vector2.from_angle(ang), float(eff.get("distance", 120)))
	fx.blink.rpc(origin, dest)
	caster.host_teleport(dest)


## Runs any effect after a delay (dash arrivals).
func delayed_effect(eff: Dictionary, ctx: Dictionary, pos: Vector2, delay: float) -> void:
	delayed.append({"left": delay, "effects": [eff], "ctx": ctx, "pos": pos})


func _spawn_decoy(spec: Dictionary, ctx: Dictionary, pos: Vector2) -> void:
	if game and game.has_method("summon_monsters"):
		game.summon_monsters(str(spec.get("monster", "mirror_image")), 1, pos, 0.0, ctx.caster,
			{"team": "caster", "lifetime": float(spec.get("duration", 2.0)), "taunt": float(spec.get("taunt_radius", 220)), "copy_caster": true})


# =========================================================================================
# Projectiles
# =========================================================================================


func spawn_projectile(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2, aim: Vector2 = Vector2.INF) -> int:
	var id := new_id()
	var speed := float(eff.speed)
	if is_instance_valid(ctx.get("caster")) and ctx.caster is Actor and ctx.caster.status.has_flag("slow_projectiles"):
		speed *= float(GameData.bal("anomaly.chronostasis_projectile_mult", 0.3))
	var reach := float(eff.range) * float(ctx.get("range_mult", 1.0))
	var p := {
		"eff": eff, "ctx": ctx, "pos": origin + dir * 8.0, "dir": dir, "team": ctx.team,
		"speed": speed, "left": reach, "radius": float(eff.get("radius", 6)),
		"pierce": int(eff.get("pierce", 0)) + int(ctx.pierce_add), "hit": [], "bounces": int(eff.get("bounces", 0)),
		"tick_left": float(eff.get("tick", 0.0)), "start": origin,
	}
	if eff.get("arc", false) and aim != Vector2.INF:
		# Mortar: flies over walls to the aim point and lands there.
		var land := clamp_range(origin, aim, reach)
		p.land = land
		p.left = origin.distance_to(land)
		p.dir = (land - origin).normalized()
	projectiles[id] = p
	fx.projectile.rpc(id, str(eff.get("sprite", "magic")), p.pos, p.dir, p.speed, p.left / p.speed, str(eff.get("light", "")))
	return id


func _step_projectiles(delta: float) -> void:
	var space := get_viewport().world_2d.direct_space_state if get_viewport() else null
	for id in projectiles.keys():
		if not projectiles.has(id):
			continue
		var bounced := false
		var p: Dictionary = projectiles[id]
		var spd: float = p.speed * _field_slow(p.pos)
		var step: Vector2 = p.dir * spd * delta
		var to: Vector2 = p.pos + step
		var end_at := Vector2.INF
		var eff: Dictionary = p.eff
		if eff.has("tick_effects"):
			p.tick_left -= delta
			if p.tick_left <= 0.0:
				p.tick_left += float(eff.get("tick", 0.5))
				for sub in eff.tick_effects:
					run_effect(sub, p.ctx, p.pos, p.pos)
		if p.has("land"):
			p.left -= step.length()
			p.pos = to
			if p.left <= 0.0:
				_end_projectile(id, p.land)
			continue
		if space and not eff.get("through_walls", false):
			var q := PhysicsRayQueryParameters2D.create(p.pos, to, PROJECTILE_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				end_at = hit.position
				var col: Object = hit.collider
				if col and col.has_method("take_damage") and p.ctx.team != ENV_TEAM:
					col.take_damage(value_of_spec(eff.get("damage", {}), p.ctx), p.ctx)
		var seg_end: Vector2 = to if end_at == Vector2.INF else end_at
		for a in hostile_in_radius(p.ctx, (p.pos + seg_end) / 2.0, p.pos.distance_to(seg_end) / 2.0 + p.radius + 16.0, true):
			if p.hit.has(a):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(a.global_position, p.pos, seg_end)
			if closest.distance_to(a.global_position) > p.radius + a.radius + 2.0:
				continue
			# Reflecting targets (prism walls, reflect statuses) send it back at its owner.
			if a.status.has_flag("reflect_projectiles") and p.ctx.team != ENV_TEAM and rng.randf() < maxf(a.stats.get_stat("reflect_projectiles"), 1.0 if a.status.has_flag("reflect_projectiles") else 0.0):
				_reflect_projectile(id, a, closest)
				end_at = Vector2.INF
				bounced = true
				break
			p.hit.append(a)
			hit_target(a, eff, p.ctx, false)
			if p.bounces > 0:
				var nxt := _bounce_target(p, a)
				if nxt:
					p.bounces -= 1
					p.pos = a.global_position
					p.dir = (nxt.global_position - a.global_position).normalized()
					p.left = float(eff.get("bounce_range", 160))
					p.ctx = p.ctx.duplicate()
					p.ctx.damage_mult = float(p.ctx.damage_mult) * (1.0 + float(eff.get("per_bounce", 0.0)))
					fx.projectile_end.rpc(id, a.global_position)
					fx.projectile.rpc(id, str(eff.get("sprite", "magic")), p.pos, p.dir, p.speed, p.left / p.speed, str(eff.get("light", "")))
					end_at = Vector2.INF
					bounced = true
					break
			p.pierce -= 1
			if p.pierce < 0:
				end_at = closest
				break
		if not projectiles.has(id):
			continue
		if eff.get("destroys_projectiles", false):
			destroy_projectiles_in(p.ctx, p.pos, p.dir, p.radius + 14.0, 360.0, id)
		if bounced:
			continue
		p.left -= step.length()
		if end_at != Vector2.INF or p.left <= 0.0:
			_end_projectile(id, end_at if end_at != Vector2.INF else to)
		else:
			p.pos = to


func _bounce_target(p: Dictionary, from: Actor) -> Actor:
	var best: Actor = null
	var best_d := float(p.eff.get("bounce_range", 160))
	for e in enemies_of(p.team, from.global_position, best_d):
		if p.hit.has(e) or not has_los(from.global_position, e.global_position):
			continue
		var d: float = e.global_position.distance_to(from.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _reflect_projectile(id: int, by: Actor, at: Vector2) -> void:
	var p: Dictionary = projectiles[id]
	var nctx := make_ctx(by, {"id": "reflect", "school": str(p.ctx.school), "damage_type": str(p.ctx.get("damage_type", "physical"))})
	nctx.power = p.ctx.power
	nctx.damage_mult = p.ctx.damage_mult
	p.ctx = nctx
	p.team = by.team
	p.dir = -p.dir
	p.pos = at
	p.hit = [by]
	p.left = float(p.eff.range)
	fx.projectile_end.rpc(id, at)
	fx.projectile.rpc(id, str(p.eff.get("sprite", "magic")), p.pos, p.dir, p.speed, p.left / p.speed, str(p.eff.get("light", "")))
	fx.number.rpc(at, "Reflect", "info")


## Removes hostile projectiles inside a circle / cone (Flame Wave, Boulder Crush, Bulwark).
func destroy_projectiles_in(ctx: Dictionary, center: Vector2, dir: Vector2, r: float, arc_deg: float, except_id: int = -1) -> void:
	var half := deg_to_rad(arc_deg) / 2.0
	for id in projectiles.keys():
		if id == except_id:
			continue
		var p: Dictionary = projectiles[id]
		if p.team == ctx.team:
			continue
		var to: Vector2 = p.pos - center
		if to.length() <= r and (half >= PI or absf(dir.angle_to(to)) <= half):
			projectiles.erase(id)
			fx.projectile_end.rpc(id, p.pos)


func _field_slow(pos: Vector2) -> float:
	var f := 1.0
	for id in zones:
		var z: Dictionary = zones[id]
		if z.eff.has("projectile_slow") and z.pos.distance_to(pos) <= z.radius:
			f = minf(f, float(z.eff.projectile_slow))
	return f


func _end_projectile(id: int, at: Vector2) -> void:
	var p: Dictionary = projectiles.get(id, {})
	projectiles.erase(id)
	fx.projectile_end.rpc(id, at)
	if p.is_empty():
		return
	# Wall torches sit on the wall face, so a projectile stopped by the wall next to one puts it out.
	if game and p.eff.has("damage"):
		for t in game.dungeon.torches.values():
			if is_instance_valid(t) and t.is_lit() and t.global_position.distance_to(at) <= float(GameData.bal("lighting.torch_hit_radius")):
				t.take_damage(1.0, p.ctx)
	if p.eff.has("explode"):
		apply_aoe(p.eff.explode, p.ctx, at)
	for sub in p.eff.get("on_end", []):
		run_effect(sub, p.ctx, at, at)


# =========================================================================================
# Zones, traps, deployables, delayed effects
# =========================================================================================


## Zone keys: radius, duration, tick, damage / heal (per tick), on_hit, status_inside (a short
## status re-applied to everyone inside, `affects`: enemies | allies | all), projectile_slow,
## tick_effects (deployables: turrets, lightwell, thunderstorm), follow (stays on the caster),
## drift_to (moves toward enemy clusters), sprite.
func add_zone(eff: Dictionary, ctx: Dictionary, pos: Vector2) -> int:
	var id := new_id()
	var is_trap: bool = eff.type == "trap"
	var r := float(eff.get("trigger_radius" if is_trap else "radius", 40)) * (float(ctx.get("trap_radius_mult", 1.0)) if is_trap else float(ctx.radius_mult))
	# Heart of the North Star: Blizzard drifts toward enemy clusters.
	if str(ctx.get("skill", "")) == "mage_blizzard" and is_instance_valid(ctx.get("caster")) and ctx.caster.stats.has_flag("drifting_blizzard"):
		eff = eff.duplicate()
		eff.drift_speed = 30.0
		eff.drift_range = 320.0
	# A caster's traps are capped (Trapper's Sturdy Chaps double the cap): the oldest one goes.
	if is_trap and is_instance_valid(ctx.get("caster")) and ctx.caster is Player:
		var cap := int(GameData.bal("combat.max_traps", 3) * (1.0 + ctx.caster.stats.get_stat("max_traps")))
		var mine: Array = zones.keys().filter(func(k): return zones[k].trap and zones[k].ctx.get("caster") == ctx.caster)
		while mine.size() >= cap and not mine.is_empty():
			var old: int = mine.pop_front()
			zones.erase(old)
			fx.zone_end.rpc(old)
	zones[id] = {"eff": eff, "ctx": ctx, "pos": pos, "radius": r, "left": float(eff.get("duration", 5.0)) * (1.0 if is_trap else float(ctx.duration_mult)),
		"tick_left": float(eff.get("first_tick", 0.0)), "arm_left": float(eff.get("arm_time", 0.0)), "trap": is_trap,
		"inside": {}}
	var vis_r := r if not is_trap else 14.0
	if eff.get("light_only", false):
		vis_r = r
	fx.zone.rpc(id, pos, vis_r, str(eff.get("color", "#ffffff")), float(zones[id].left), str(eff.get("sprite", "")))
	return id


func _step_zones(delta: float) -> void:
	for id in zones.keys():
		if not zones.has(id):
			continue
		var z: Dictionary = zones[id]
		var eff: Dictionary = z.eff
		z.left -= delta
		if eff.get("follow", false) and is_instance_valid(z.ctx.caster):
			z.pos = z.ctx.caster.global_position
			fx.zone_move.rpc(id, z.pos)
		elif eff.has("drift_speed"):
			var target := nearest_to(enemies_of(z.ctx.team, z.pos, float(eff.get("drift_range", 300))), z.pos, INF)
			if target:
				z.pos = z.pos.move_toward(target.global_position, float(eff.drift_speed) * delta)
				fx.zone_move.rpc(id, z.pos)
		if z.trap:
			z.arm_left -= delta
			if z.arm_left <= 0.0 and not _trap_victims(z).is_empty():
				zones.erase(id)
				fx.zone_end.rpc(id)
				var victim: Actor = _trap_victims(z)[0]
				var c: Dictionary = _with_target(z.ctx, victim)
				for e in eff.effects:
					run_effect(e, c, z.pos, z.pos)
				if is_instance_valid(z.ctx.caster):
					fire(z.ctx.caster, "on_trap", {"target": victim, "ctx": z.ctx, "skill": z.ctx.skill, "pos": z.pos})
				continue
		else:
			z.tick_left -= delta
			if z.tick_left <= 0.0:
				z.tick_left += float(eff.get("tick", 1.0))
				_zone_tick(z)
		if z.left <= 0.0:
			zones.erase(id)
			fx.zone_end.rpc(id)
			for sub in eff.get("on_end", []):
				run_effect(sub, z.ctx, z.pos, z.pos)


func _trap_victims(z: Dictionary) -> Array:
	return hostile_in_radius(z.ctx, z.pos, z.radius, true).filter(func(a): return not a.status.has_flag("trap_immune"))


func _zone_tick(z: Dictionary) -> void:
	var eff: Dictionary = z.eff
	# Cuirass of the Radiant Dawn: Consecration heals allies inside for 3% max HP a second.
	if str(z.ctx.get("skill", "")) == "priest_consecration" and is_instance_valid(z.ctx.get("caster")) and z.ctx.caster.stats.has_flag("radiant_consecration"):
		for ra in allies_of(z.ctx.team, z.pos, z.radius):
			heal(z.ctx, ra, ra.health.max_hp * 0.03 * float(eff.get("tick", 1.0)))
	if eff.has("damage"):
		for a in hostile_in_radius(z.ctx, z.pos, z.radius, true):
			hit_target(a, eff, z.ctx, true)
	if eff.has("heal"):
		for a in allies_of(z.ctx.team, z.pos, z.radius):
			if a.health.fraction() < float(eff.get("heal_below", 1.01)):
				heal(z.ctx, a, _heal_amount(eff, z.ctx, a, "heal"))
	if eff.has("status_inside"):
		var who := str(eff.get("affects", "enemies"))
		var pool: Array = []
		if who in ["enemies", "all"]:
			pool.append_array(hostile_in_radius(z.ctx, z.pos, z.radius, true))
		if who in ["allies", "all"]:
			pool.append_array(allies_of(z.ctx.team, z.pos, z.radius))
		for a in pool:
			a.status.apply(str(eff.status_inside), float(eff.get("tick", 1.0)) + 0.3, _magnitude(eff, z.ctx, a), z.ctx)
	if eff.has("repel_enemies") and (not eff.has("repel_for") or float(eff.get("duration", 0.0)) * float(z.ctx.duration_mult) - z.left <= float(eff.repel_for)):
		for a2 in enemies_of(z.ctx.team, z.pos, z.radius):
			knock(a2, (a2.global_position - z.pos).normalized() * float(eff.repel_enemies))
	for sub in eff.get("tick_effects", []):
		run_effect(sub, z.ctx, z.pos, z.pos)


func _step_delayed(delta: float) -> void:
	for i in range(delayed.size() - 1, -1, -1):
		var d: Dictionary = delayed[i]
		d.left -= delta
		if d.left > 0.0:
			continue
		delayed.remove_at(i)
		if is_instance_valid(d.get("follow")):
			d.pos = d.follow.global_position  # fires where the caster is now (landing a leap)
		if d.get("aoe", false):
			apply_aoe(d.eff, d.ctx, d.pos)
		else:
			var c: Dictionary = d.ctx.duplicate()
			c.origin = d.pos
			for e in d.effects:
				if e.type == "aoe":
					var e2: Dictionary = e.duplicate()
					e2.delay = 0.0
					e2.at = "self"
					run_effect(e2, c, d.pos, d.pos)
				else:
					run_effect(e, c, d.pos, d.pos)


# =========================================================================================
# Tethers (Blood-Thread Bond, astral tether, Bone Harpoon reel)
# =========================================================================================


## {"type": "tether", "target": ..., "between": "caster" | "two_players", "max_distance", "duration",
##  "tick", "tick_effects", "snap_effects", "break_on_distance": true}
func _tether(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var a: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	var b: Actor = null
	if str(eff.get("between", "caster")) == "two_players" and game:
		var ps: Array = game.players_root.get_children().filter(func(x): return x.is_targetable())
		if ps.size() < 2:
			return
		ps.shuffle()
		a = ps[0]
		b = ps[1]
	else:
		var ts := select_targets(eff, ctx, origin, aim, "aim_enemy")
		if ts.is_empty() or a == null:
			return
		b = ts[0]
	var id := new_id()
	tethers[id] = {"a": a, "b": b, "eff": eff, "ctx": ctx, "left": float(eff.get("duration", 6)), "tick_left": float(eff.get("tick", 1.0))}
	fx.tether.rpc(id, a.get_path(), b.get_path(), str(eff.get("color", "#cc2233")))


func _step_tethers(delta: float) -> void:
	for id in tethers.keys():
		var t: Dictionary = tethers[id]
		var ok: bool = is_instance_valid(t.a) and is_instance_valid(t.b) and t.a.is_alive() and t.b.is_alive()
		t.left -= delta
		if ok and t.eff.has("max_distance") and t.a.global_position.distance_to(t.b.global_position) > float(t.eff.max_distance):
			for e in t.eff.get("snap_effects", []):
				for who in [t.a, t.b]:
					run_effect(e.merged({"target": "event_target"}, false), _with_target(t.ctx, who), who.global_position, who.global_position)
			ok = false
		if ok:
			t.tick_left -= delta
			if t.tick_left <= 0.0:
				t.tick_left += float(t.eff.get("tick", 1.0))
				for e2 in t.eff.get("tick_effects", []):
					for who2 in ([t.a, t.b] if str(t.eff.get("between", "")) == "two_players" else [t.b]):
						run_effect(e2.merged({"target": "event_target"}, false), _with_target(t.ctx, who2), who2.global_position, who2.global_position)
		if not ok or t.left <= 0.0:
			tethers.erase(id)
			fx.tether_end.rpc(id)


# =========================================================================================
# Dynamic terrain (D30): fire walls, thorns, stakes, ice trails
# =========================================================================================


## {"type": "terrain", "kind": "fire_wall", "shape": "line" | "ring" | "point", "length", "radius",
##  "lifetime", "blocks": "movement" | "all" | "none", "zone": {damaging zone along it}}
func _terrain(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2, dir: Vector2) -> void:
	if game == null:
		return
	var points: Array = []
	var at := clamp_range(origin, aim, float(eff.get("max_range", 200))) if eff.get("at", "aim") == "aim" else origin
	var tile := float(game.dungeon.tile)
	match str(eff.get("shape", "line")):
		"line":
			var length := float(eff.get("length", 96))
			var across := dir.orthogonal() if eff.get("across", true) else dir
			var start := at - across * length / 2.0
			if eff.get("from_origin", false):
				start = origin + dir * 20.0
				across = dir
			var n := maxi(1, int(length / tile))
			for i in n + 1:
				points.append(start + across * (length * i / n))
		"ring":
			var r := float(eff.get("radius", 80))
			var n2 := maxi(6, int(TAU * r / tile))
			for i in n2:
				points.append(at + Vector2.from_angle(TAU * i / n2) * r)
		_:
			points.append(at)
	var cells := {}
	for p in points:
		var c: Vector2i = game.dungeon.cell_of(p)
		if game.dungeon.cell_at(c) == DungeonGenerator.CELL_FLOOR:
			cells[c] = true
	if cells.is_empty():
		return
	var lifetime := float(eff.get("lifetime", 6))
	var oid := new_id()
	game.dungeon.add_obstacle.rpc(oid, str(eff.get("kind", "thorns")), cells.keys(), lifetime, str(eff.get("blocks", "movement")))
	if eff.has("zone"):
		for c2 in cells:
			var z: Dictionary = eff.zone.duplicate()
			z.type = "zone"
			z.duration = lifetime
			if not z.has("radius"):
				z.radius = tile * 0.6
			add_zone(z, ctx, game.dungeon.cell_center(c2))
