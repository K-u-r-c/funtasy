class_name Combat
extends Node
## Host-authoritative damage + skill system. Skills are data (data/skills/*.json) built from a
## small set of effect primitives: melee, projectile, aoe, zone, trap, dash, blink, status,
## heal, absorb, taunt, resource, summon (+ on_hit: status, knockback, threat).
## Every outcome (hit, crit, dodge, leech, threat, XP contribution) is decided here on the host;
## clients only receive cosmetic FX RPCs from CombatFx.
##
## A "ctx" dictionary snapshots the caster when a skill fires, so projectiles, zones, traps and
## DoTs keep working (and keep crediting the caster) even if the caster dies meanwhile.

static var instance: Combat

const ENV_TEAM := -1
const LOS_MASK := 1 | 8 | 16
const PROJECTILE_MASK := 1 | 8 | 16 | 32

var game: Node
var fx: CombatFx
var projectiles: Dictionary = {}
var zones: Dictionary = {}
var delayed: Array = []
var rng := RandomNumberGenerator.new()
var _next_id := 1


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	rng.randomize()


func clear_floor() -> void:
	for id in projectiles.keys():
		fx.projectile_end.rpc(id, projectiles[id].pos)
	projectiles.clear()
	for id in zones.keys():
		fx.zone_end.rpc(id)
	zones.clear()
	delayed.clear()


# =========================================================================================
# Skill use
# =========================================================================================


## Validates and starts a skill. Returns "" on success or a short reason.
func try_use_skill(caster: Actor, skill_id: String, aim: Vector2) -> String:
	var skill := GameData.skill(skill_id)
	if skill.is_empty():
		return "Unknown skill"
	if not caster.can_act():
		return "Can't act now"
	if not caster.casting.is_empty():
		return "Busy"
	if caster.cooldown_left(skill_id) > 0.0:
		return "Not ready"
	var cost := caster.stats.cost_for(skill)
	if caster.resource.kind != "none" and cost > 0.0:
		if not caster.resource.pay(cost):
			return "Not enough %s" % caster.resource.kind.capitalize()
	caster.cooldowns[skill_id] = caster.stats.cooldown_for(skill)
	# Usage counter (read by the test harness and handy when balancing).
	var uses: Dictionary = get_meta("uses", {})
	var key := "%s:%s" % [caster.name, skill_id]
	uses[key] = int(uses.get(key, 0)) + 1
	set_meta("uses", uses)
	var dir := (aim - caster.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = caster.facing
	caster.facing = dir
	caster.play_action.rpc(str(skill.get("anim", "attack")), dir)
	if skill.has("sfx"):
		fx.sound.rpc(skill.sfx, caster.global_position)
	var cast_time := cast_time_for(caster.stats, skill)
	if cast_time > 0.01:
		caster.casting = {"skill": skill_id, "aim": aim, "left": cast_time}
		fx.cast_bar.rpc(caster.get_path(), cast_time)
	else:
		finish_cast(caster, skill_id, aim)
	return ""


func finish_cast(caster: Actor, skill_id: String, aim: Vector2) -> void:
	var skill := GameData.skill(skill_id)
	var ctx := make_ctx(caster, skill)
	for eff in skill.effects:
		run_effect(eff, ctx, caster.global_position, aim)


func make_ctx(caster: Actor, skill: Dictionary) -> Dictionary:
	var ctx := skill_numbers(caster.stats, caster.level, skill)
	ctx.merge({
		"caster": caster, "team": caster.team,
		"peer": int(caster.get("peer_id")) if caster.get("peer_id") != null else 0,
		"origin": caster.global_position,
	})
	return ctx


## The numbers a skill uses, from its caster's stats. Host combat and the UI's skill tooltips
## both read these, so what the tooltip shows is what the host deals.
static func skill_numbers(st: Stats, level: int, skill: Dictionary) -> Dictionary:
	var sid: String = skill.get("id", "")
	var school: String = skill.get("school", "melee")
	return {
		"skill": sid, "school": school,
		"power": st.power_for(school),
		"damage_mult": st.get_stat("damage_mult", 1.0) * (1.0 + st.skill_mod(sid, "damage_mult")),
		"heal_mult": st.get_stat("healing_mult", 1.0) * (1.0 + st.skill_mod(sid, "heal_mult")),
		"crit_chance": st.get_stat("crit_chance"), "crit_damage": st.get_stat("crit_damage", 0.5),
		"leech": st.get_stat("leech"), "level": level,
		"threat_mult": float(skill.get("threat_mult", 1.0)) * st.get_stat("threat_mult", 1.0),
		"resource_on_hit": float(skill.get("resource_on_hit", -1.0)),
		"radius_mult": 1.0 + st.skill_mod(sid, "radius_mult"),
		"duration_mult": 1.0 + st.skill_mod(sid, "duration_mult"),
		"count_add": int(st.skill_mod(sid, "count_add")),
		"pierce_add": int(st.skill_mod(sid, "pierce_add")),
	}


## Damage / healing / magnitude of a {"base", "coef"} spec for the given skill numbers.
static func value_of(spec: Variant, nums: Dictionary) -> float:
	if not spec is Dictionary or spec.is_empty():
		return 0.0
	return (float(spec.get("base", 0)) + float(nums.power) * float(spec.get("coef", 0))) * float(nums.damage_mult)


## Cast time after haste.
static func cast_time_for(st: Stats, skill: Dictionary) -> float:
	return float(skill.get("cast_time", 0.0)) / (1.0 + st.get_stat("haste"))


## Context for damage that belongs to nobody (lava, spikes, monster-triggered barrels).
func env_ctx(power: float) -> Dictionary:
	return {"caster": null, "team": ENV_TEAM, "skill": "", "school": "physical", "power": power,
		"damage_mult": 1.0, "heal_mult": 1.0, "crit_chance": 0.0, "crit_damage": 0.0, "leech": 0.0,
		"level": 1, "threat_mult": 0.0, "resource_on_hit": -1.0, "radius_mult": 1.0, "duration_mult": 1.0,
		"count_add": 0, "pierce_add": 0, "peer": 0, "origin": Vector2.ZERO, "environment": true}


# =========================================================================================
# Effect primitives
# =========================================================================================


func run_effect(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	var dir := (aim - origin).normalized()
	if dir == Vector2.ZERO:
		dir = caster.facing if caster else Vector2.RIGHT
	match str(eff.type):
		"melee":
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
				spawn_projectile(eff, ctx, origin, dir.rotated(a))
		"aoe":
			var center := origin if eff.get("at", "self") == "self" else _clamp_range(origin, aim, float(eff.get("max_range", 300)))
			var delay := float(eff.get("delay", 0.0))
			if delay > 0.0:
				fx.telegraph.rpc(center, float(eff.radius) * float(ctx.radius_mult), str(eff.get("color", "#ff4422")), delay)
				delayed.append({"left": delay, "eff": eff, "ctx": ctx, "pos": center})
			else:
				apply_aoe(eff, ctx, center)
		"zone", "trap":
			var zpos := origin if eff.get("at", "aim" if eff.type == "trap" else "self") == "self" else _clamp_range(origin, aim, float(eff.get("max_range", 220)))
			_add_zone(eff, ctx, zpos)
		"dash":
			_dash(eff, ctx, origin, dir)
		"blink":
			if caster:
				var dest := _walkable_point(origin, dir, float(eff.distance))
				fx.blink.rpc(origin, dest)
				caster.host_teleport(dest)
		"status":
			for t in _effect_targets(eff, ctx, origin):
				var mag := _magnitude(eff, ctx)
				apply_status(ctx, t, str(eff.status), float(eff.duration) * float(ctx.duration_mult), mag)
		"heal":
			var amount := _value(eff.amount, ctx) * float(ctx.heal_mult)
			for t in _heal_targets(eff, ctx, origin, aim):
				heal(ctx, t, amount)
		"absorb":
			var amount2 := _value(eff.amount, ctx) * float(ctx.heal_mult)
			for t in _effect_targets(eff, ctx, origin):
				t.health.absorb = maxf(t.health.absorb, amount2)
				t.health.absorb_time = float(eff.duration)
				t.status.apply("holy_shield", float(eff.duration), amount2, ctx)
				_credit_support(ctx, t, amount2)
			fx.ring.rpc(origin, float(eff.get("radius", 40)), "#ffe680", "")
		"taunt":
			var r := float(eff.radius) * float(ctx.radius_mult)
			for e in enemies_of(ctx.team, origin, r):
				if e.has_method("taunted_by") and caster:
					e.taunted_by(caster, float(eff.duration))
			fx.ring.rpc(origin, r, str(eff.get("color", "#ff5533")), "")
		"resource":
			if caster:
				caster.resource.gain(float(eff.amount))
		"summon":
			if game and game.has_method("summon_monsters"):
				game.summon_monsters(str(eff.monster), int(eff.count), origin, float(eff.get("radius", 80)), caster)
		_:
			push_error("Combat: unknown effect type '%s'" % eff.type)


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
	var max_targets := int(eff.get("max_targets", 99))
	for i in mini(hits.size(), max_targets):
		hit_target(hits[i], eff, ctx, false)
	if ctx.team != ENV_TEAM and game:
		for p in game.dungeon.props_in_radius(origin, reach):
			var tp: Vector2 = p.global_position - origin
			if tp.length() < 10.0 or absf(dir.angle_to(tp)) <= half_arc:
				p.take_damage(_value(eff.get("damage", {}), ctx), ctx)
	fx.melee.rpc(origin, dir, reach, rad_to_deg(half_arc * 2.0), str(eff.get("fx", "slash")))


func apply_aoe(eff: Dictionary, ctx: Dictionary, center: Vector2) -> void:
	var r := float(eff.radius) * float(ctx.radius_mult)
	var targets_kind: String = eff.get("targets", "enemies")
	if eff.has("damage") or targets_kind == "enemies":
		for a in hostile_in_radius(ctx, center, r, true):
			if has_los(center, a.global_position):
				hit_target(a, eff, ctx, true)
	if eff.has("heal"):
		for a in allies_of(ctx.team, center, r):
			heal(ctx, a, _value(eff.heal, ctx) * float(ctx.heal_mult))
	if eff.has("damage") and game:
		for p in game.dungeon.props_in_radius(center, r):
			p.take_damage(_value(eff.damage, ctx), ctx)
	fx.ring.rpc(center, r, str(eff.get("color", "#ffffff")), str(eff.get("fx", "")))
	if eff.has("shake"):
		fx.shake.rpc(center, float(eff.shake))


func hit_target(target: Actor, eff: Dictionary, ctx: Dictionary, area: bool) -> void:
	if not is_instance_valid(target) or not target.is_targetable():
		return
	var landed := true
	if eff.has("damage"):
		landed = deal_damage(ctx, target, _value(eff.damage, ctx), {"area": area}) >= 0.0
	if not landed:
		return
	for oh in eff.get("on_hit", []):
		match str(oh.type):
			"status":
				apply_status(ctx, target, str(oh.status), float(oh.duration) * float(ctx.duration_mult), _magnitude(oh, ctx))
			"knockback":
				var from: Vector2 = ctx.caster.global_position if is_instance_valid(ctx.caster) else ctx.origin
				var push := (target.global_position - from).normalized() * float(oh.force)
				target.host_knockback(push)
			"threat":
				if target.has_method("add_threat") and is_instance_valid(ctx.caster):
					target.add_threat(ctx.caster, float(oh.amount))


# =========================================================================================
# Damage / healing / statuses
# =========================================================================================


## Returns damage dealt (0 = fully absorbed / immune) or -1 when the hit was dodged.
func deal_damage(ctx: Dictionary, target: Actor, amount: float, opts: Dictionary = {}) -> float:
	if not is_instance_valid(target) or not target.is_targetable() or amount <= 0.0:
		return 0.0
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	var dot := bool(opts.get("dot", false))
	if target.has_method("is_invulnerable") and target.is_invulnerable():
		fx.number.rpc(target.global_position, "Immune", "info")
		return 0.0
	if not dot and not ctx.get("environment", false) and rng.randf() < target.stats.get_stat("dodge"):
		fx.number.rpc(target.global_position, "Dodge", "info")
		return -1.0
	var kind := "damage" if target.team == Actor.Team.MONSTERS else "hurt"
	if not dot and rng.randf() < float(ctx.crit_chance):
		amount *= 1.0 + float(ctx.crit_damage)
		kind = "crit"
	var reduction := target.stats.get_stat("strength_reduction")
	if ctx.school in ["melee", "ranged", "physical"] and not dot:
		var armor := target.stats.get_stat("armor")
		var k := float(GameData.bal("stats.armor_constant")) + float(GameData.bal("stats.armor_per_level")) * int(ctx.level)
		reduction += armor / (armor + k)
	reduction = minf(reduction, float(GameData.bal("stats.max_damage_reduction")))
	amount *= (1.0 - reduction) * target.stats.get_stat("damage_taken_mult", 1.0)
	amount = maxf(1.0, roundf(amount))
	var dealt := target.health.take(amount)
	fx.number.rpc(target.global_position, str(int(amount)), "dot" if dot else kind)
	# No RPC to an enemy that is about to be despawned (the despawn could arrive first).
	if not dot and target.is_alive():
		target.play_action.rpc("hit", Vector2.ZERO)
	# Resources: Fury from dealing and taking damage; on-hit restores (primary attacks).
	target.resource.mark_combat()
	if target.resource.kind == "fury" and target.health.max_hp > 0.0:
		target.resource.gain(amount / target.health.max_hp * float(GameData.bal("fury.per_damage_taken_fraction")))
	if caster:
		caster.resource.mark_combat()
		if not dot:
			var on_hit := float(ctx.resource_on_hit)
			if on_hit >= 0.0:
				caster.resource.gain(on_hit)
			elif caster.resource.kind == "fury":
				caster.resource.gain(float(GameData.bal("fury.per_damage_dealt_hit")))
		if float(ctx.leech) > 0.0 and caster.is_alive():
			var healed := caster.health.heal(amount * float(ctx.leech))
			if healed >= 1.0:
				fx.number.rpc(caster.global_position, "+%d" % int(healed), "heal")
	# Threat and XP contribution.
	if target.has_method("add_threat") and caster and caster.team != target.team:
		target.add_threat(caster, amount * float(ctx.threat_mult))
	if target.has_method("add_contribution") and int(ctx.peer) > 0:
		target.add_contribution(int(ctx.peer))
	if caster and caster.has_method("add_contribution") and target.get("peer_id") != null:
		caster.add_contribution(int(target.peer_id))  # tanking counts as contributing
	if target.has_method("on_damaged"):
		target.on_damaged(caster, amount)
	return dealt


func heal(ctx: Dictionary, target: Actor, amount: float) -> float:
	if not is_instance_valid(target) or not target.is_alive() or amount <= 0.0:
		return 0.0
	var healed := target.health.heal(roundf(amount))
	if healed >= 1.0:
		fx.number.rpc(target.global_position, "+%d" % int(healed), "heal")
	_credit_support(ctx, target, healed * float(GameData.bal("threat.heal_threat_mult")))
	return healed


func apply_status(ctx: Dictionary, target: Actor, id: String, duration: float, magnitude: float) -> void:
	if not is_instance_valid(target) or not target.is_alive():
		return
	target.status.apply(id, duration, magnitude, ctx)
	var def: Dictionary = GameData.status_effects.get(id, {})
	if def.get("debuff", false):
		if target.has_method("add_threat") and is_instance_valid(ctx.caster):
			target.add_threat(ctx.caster, float(GameData.bal("threat.debuff_threat")) * float(ctx.threat_mult))
		if target.has_method("add_contribution") and int(ctx.peer) > 0:
			target.add_contribution(int(ctx.peer))
	elif target != ctx.caster:
		_credit_support(ctx, target, float(GameData.bal("threat.buff_threat")))


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


## Called by StatusEffects on the host for DoT/HoT ticks.
func status_tick(actor: Actor, e: Dictionary) -> void:
	var ctx: Dictionary = e.source if e.source is Dictionary else env_ctx(0.0)
	var amount := float(e.magnitude) * int(e.stacks)
	if e.def.kind == "dot":
		deal_damage(ctx, actor, amount, {"dot": true})
	else:
		heal(ctx, actor, amount)


# =========================================================================================
# Projectiles, zones, traps, delayed AoE (host simulation)
# =========================================================================================


func spawn_projectile(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var id := _next_id
	_next_id += 1
	var p := {
		"eff": eff, "ctx": ctx, "pos": origin + dir * 8.0, "dir": dir,
		"speed": float(eff.speed), "left": float(eff.range), "radius": float(eff.get("radius", 6)),
		"pierce": int(eff.get("pierce", 0)) + int(ctx.pierce_add), "hit": [],
	}
	projectiles[id] = p
	fx.projectile.rpc(id, str(eff.get("sprite", "magic")), p.pos, dir, p.speed, p.left / p.speed, str(eff.get("light", "")))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_step_projectiles(delta)
	_step_zones(delta)
	for i in range(delayed.size() - 1, -1, -1):
		var d: Dictionary = delayed[i]
		d.left -= delta
		if d.left <= 0.0:
			delayed.remove_at(i)
			apply_aoe(d.eff, d.ctx, d.pos)


func _step_projectiles(delta: float) -> void:
	var space := get_viewport().world_2d.direct_space_state if get_viewport() else null
	for id in projectiles.keys():
		var p: Dictionary = projectiles[id]
		var step: Vector2 = p.dir * p.speed * delta
		var to: Vector2 = p.pos + step
		var end_at := Vector2.INF
		if space:
			var q := PhysicsRayQueryParameters2D.create(p.pos, to, PROJECTILE_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				end_at = hit.position
				var col: Object = hit.collider
				if col and col.has_method("take_damage") and p.ctx.team != ENV_TEAM:
					col.take_damage(_value(p.eff.get("damage", {}), p.ctx), p.ctx)
		var seg_end: Vector2 = to if end_at == Vector2.INF else end_at
		for a in hostile_in_radius(p.ctx, (p.pos + seg_end) / 2.0, p.pos.distance_to(seg_end) / 2.0 + p.radius + 16.0, true):
			if p.hit.has(a):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(a.global_position, p.pos, seg_end)
			if closest.distance_to(a.global_position) <= p.radius + a.radius + 2.0:
				p.hit.append(a)
				hit_target(a, p.eff, p.ctx, false)
				p.pierce -= 1
				if p.pierce < 0:
					end_at = closest
					break
		p.left -= step.length()
		if end_at != Vector2.INF or p.left <= 0.0:
			_end_projectile(id, end_at if end_at != Vector2.INF else to)
		else:
			p.pos = to


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


func _add_zone(eff: Dictionary, ctx: Dictionary, pos: Vector2) -> void:
	var id := _next_id
	_next_id += 1
	var is_trap: bool = eff.type == "trap"
	var r := float(eff.get("trigger_radius" if is_trap else "radius", 40)) * (1.0 if is_trap else float(ctx.radius_mult))
	zones[id] = {"eff": eff, "ctx": ctx, "pos": pos, "radius": r, "left": float(eff.duration),
		"tick_left": 0.0, "arm_left": float(eff.get("arm_time", 0.0)), "trap": is_trap}
	fx.zone.rpc(id, pos, r if not is_trap else 14.0, str(eff.get("color", "#ffffff")), float(eff.duration), str(eff.get("sprite", "")))


func _step_zones(delta: float) -> void:
	for id in zones.keys():
		var z: Dictionary = zones[id]
		z.left -= delta
		if z.trap:
			z.arm_left -= delta
			if z.arm_left <= 0.0 and not hostile_in_radius(z.ctx, z.pos, z.radius, true).is_empty():
				zones.erase(id)
				fx.zone_end.rpc(id)
				for e in z.eff.effects:
					run_effect(e, z.ctx, z.pos, z.pos)
				continue
		else:
			z.tick_left -= delta
			if z.tick_left <= 0.0:
				z.tick_left += float(z.eff.get("tick", 1.0))
				if z.eff.has("damage"):
					for a in hostile_in_radius(z.ctx, z.pos, z.radius, true):
						hit_target(a, z.eff, z.ctx, true)
				if z.eff.has("heal"):
					for a in allies_of(z.ctx.team, z.pos, z.radius):
						heal(z.ctx, a, _value(z.eff.heal, z.ctx) * float(z.ctx.heal_mult))
		if z.left <= 0.0:
			zones.erase(id)
			fx.zone_end.rpc(id)


func _dash(eff: Dictionary, ctx: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	if caster == null:
		return
	var dest := _walkable_point(origin, dir, float(eff.distance))
	var duration := origin.distance_to(dest) / float(eff.get("speed", 700))
	caster.host_dash(dest, duration)
	if eff.has("on_arrive"):
		for sub in eff.on_arrive:
			delayed_effect(sub, ctx, dest, duration)


## Runs any effect after a delay (used for dash arrivals).
func delayed_effect(eff: Dictionary, ctx: Dictionary, pos: Vector2, delay: float) -> void:
	if eff.type == "aoe":
		var e2: Dictionary = eff.duplicate()
		e2.delay = 0.0
		delayed.append({"left": delay, "eff": e2, "ctx": ctx, "pos": pos})
	else:
		get_tree().create_timer(delay).timeout.connect(func():
			ctx.origin = pos
			run_effect(eff, ctx, pos, pos))


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
		if a is Actor and a.team == team and a.is_alive() and a.global_position.distance_to(pos) <= r + a.radius:
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


func _effect_targets(eff: Dictionary, ctx: Dictionary, origin: Vector2) -> Array:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	match str(eff.get("target", "self")):
		"party":
			return allies_of(ctx.team, origin, float(eff.get("radius", 200)))
		_:
			return [caster] if caster and caster.is_alive() else []


func _heal_targets(eff: Dictionary, ctx: Dictionary, origin: Vector2, aim: Vector2) -> Array:
	var caster: Actor = ctx.caster if is_instance_valid(ctx.caster) else null
	match str(eff.get("target", "self")):
		"aim_ally":
			var best: Actor = caster
			var best_d := INF
			for a in allies_of(ctx.team, origin, float(eff.get("max_range", 300))):
				var d: float = a.global_position.distance_to(aim)
				if d < best_d:
					best_d = d
					best = a
			return [best] if best else []
		"lowest_ally":
			var low: Actor = null
			var low_f := 1.0
			for a in allies_of(ctx.team, origin, float(eff.get("max_range", 300))):
				var f: float = a.health.fraction()
				if f < low_f:
					low_f = f
					low = a
			return [low] if low else []
		"party":
			return allies_of(ctx.team, origin, float(eff.get("radius", 200)))
	return [caster] if caster else []


func _value(spec: Variant, ctx: Dictionary) -> float:
	return value_of(spec, ctx)


func _magnitude(eff: Dictionary, ctx: Dictionary) -> float:
	return _value(eff.magnitude, ctx) if eff.has("magnitude") else 0.0


func _clamp_range(origin: Vector2, aim: Vector2, max_range: float) -> Vector2:
	var d := aim - origin
	return origin + d.limit_length(max_range)


## Furthest point along dir (up to dist) that a body can reach without crossing walls/doors.
func _walkable_point(origin: Vector2, dir: Vector2, dist: float) -> Vector2:
	var space := get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * dist, 1 | 8 | 16 | 32)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return origin + dir * dist
	return hit.position - dir * 14.0
