class_name Combat
extends CombatEffects
## Host-authoritative damage + skill system. Skills are data (data/skills/*.json) built from
## effect primitives (CombatEffects, listed in EFFECT_TYPES). Every outcome (hit, crit, dodge,
## block, leech, threat, XP contribution, procs) is decided on the host (CombatCore); clients only
## receive cosmetic FX RPCs from CombatFx.
##
## A "ctx" dictionary snapshots the caster when a skill fires, so projectiles, zones, traps and
## DoTs keep working (and keep crediting the caster) even if the caster dies meanwhile.
##
## Skill-level features handled here: cast times, channels (hold, cost per second, ticks),
## charge-ups (hold, release to fire), toggles, passives (never cast), stored charges, usable_if
## conditions (target HP, proc windows, statuses), HP costs and "consume all resource".

static var instance: Combat

## Effect primitives `run_effect` understands (validated by GameData).
const EFFECT_TYPES := ["melee", "cone", "projectile", "aoe", "zone", "trap", "deploy", "dash", "leap", "charge",
	"blink", "teleport", "status", "remove_status", "heal", "absorb", "taunt", "resource", "summon", "hit",
	"line", "chain", "beam", "knockback", "pull", "delayed", "consume_dots", "cleanse", "dispel",
	"destroy_projectiles", "terrain", "threat_drop", "reveal", "interrupt", "cooldown", "self_damage",
	"resource_drain", "tether", "stored_damage", "spread", "revive", "toggle_status", "fetch", "prevent_death",
	"extinguish", "break_absorb", "free_cast", "replay_skill", "threat_bonus"]
## Extra effect types valid inside `on_hit` lists.
const ON_HIT_TYPES := ["knockback", "threat"]
## Events a proc ({"event", "do"}) can listen to.
const PROC_EVENTS := ["on_hit", "on_crit", "on_kill", "on_damaged", "on_block", "on_dodge", "on_avoided",
	"on_skill_cast", "on_heal", "on_low_hp", "on_fatal", "on_status_applied", "on_floor_start", "aura_tick",
	"on_move", "on_trap", "on_cleanse", "on_chain_jump", "on_dodge_roll", "on_combat_end"]


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	rng.randomize()


# =========================================================================================
# Skill use
# =========================================================================================


## Validates and starts a skill. Returns "" on success or a short reason.
## opts: primary (bool, the LMB slot: D24 lets basic weapon attacks through silence).
func try_use_skill(caster: Actor, skill_id: String, aim: Vector2, opts: Dictionary = {}) -> String:
	var skill := GameData.skill(skill_id)
	if skill.is_empty():
		return "Unknown skill"
	if skill.get("passive", false):
		return "Passive"
	if not caster.can_act() and not (skill.get("usable_while_cc", false) and caster.is_alive()):
		return "Can't act now"
	if not caster.casting.is_empty() or not caster.channel.is_empty() or not caster.charging.is_empty():
		return "Busy"
	var school := str(skill.get("school", "melee"))
	if caster.status.has_flag("silenced") and (school == "spell" or not opts.get("primary", false)):
		return "Silenced"
	if caster.status.has("school_lockout") and str(skill.get("element", school)) == caster.lockout_element:
		return "Locked out"
	var max_charges := int(skill.get("charges", 1)) + int(caster.stats.skill_mod(skill_id, "charges_add"))
	if max_charges > 1:
		if int(caster.skill_charges.get(skill_id, max_charges)) <= 0:
			return "Not ready"
	elif caster.cooldown_left(skill_id) > 0.0:
		return "Not ready"
	# A monster never leaps or charges right after it spots a hero (#2).
	if caster is Enemy and is_lunge(skill) and caster.aggro_age() < float(GameData.bal("ai.lunge_grace", 1.5)):
		return "Not ready"
	var why := _usable(caster, skill, aim)
	if not why.is_empty():
		return why
	# Toggles switch their status and cost nothing else.
	if skill.has("toggle"):
		var st := str(skill.toggle)
		if caster.status.has(st):
			caster.status.remove(st)
		else:
			caster.status.apply(st, -1.0, 0.0, make_ctx(caster, skill))
		caster.cooldowns[skill_id] = float(skill.get("cooldown", 1.0))
		fx.sound.rpc(str(skill.get("sfx", "cast")), caster.global_position)
		return ""
	var cost := caster.stats.cost_for(skill)
	if JSON.stringify(skill.get("effects", [])).contains("\"heal\""):
		cost *= caster.stats.mult("heal_cost")  # Black Iron Penitent Cross
	if caster.stats.has_flag("free_shot_chance") and str(skill.get("school", "")) == "ranged" and rng.randf() < 0.25:
		cost = 0.0  # Quiver of the Endless Abyss
	# Stormweaver Grips: the stacks cheapen this cast, then they are spent.
	for cst in caster.status.effects.duplicate():
		if cst.def.get("consume_on_cast", false) and not skill.get("passive", false):
			caster.status.remove(cst.id)
	# Spatial anomaly (Archives): the cost of every cast rolls +-30%, shown above the caster.
	if cost > 0.0 and caster is Player and game and game.dungeon.in_anomaly(caster.global_position):
		var roll := rng.randf_range(1.0 - float(GameData.bal("anomaly.cost_swing", 0.3)), 1.0 + float(GameData.bal("anomaly.cost_swing", 0.3)))
		cost *= roll
		fx.number.rpc(caster.global_position + Vector2(0, -24), "Cost x%.2f" % roll, "info")
	if skill.has("channel"):
		cost = 0.0  # channels pay per second
	if caster.resource.kind != "none" and cost > 0.0:
		if not caster.resource.can_pay(cost):
			# Bloodmage's Choker: pay the missing mana with HP.
			if caster.stats.has_flag("hp_for_mana") and caster.resource.kind == "mana":
				var missing := cost - caster.resource.value
				var hp_cost := missing * float(GameData.bal("combat.hp_per_mana", 2.0))
				if caster.health.hp <= hp_cost + 1.0:
					return "Not enough Mana"
				caster.health.hp -= hp_cost
				caster.resource.value = 0.0
			else:
				return "Not enough %s" % caster.resource.kind.capitalize()
		else:
			caster.resource.pay(cost)
	var extra := {}
	if skill.get("consumes_all_resource", false):
		extra.extra_resource = caster.resource.value
		caster.resource.value = 0.0
	if skill.has("cost_hp_pct"):
		var hc := caster.health.hp * float(skill.cost_hp_pct)
		caster.health.hp = maxf(1.0, caster.health.hp - hc)
		fx.number.rpc(caster.global_position, str(int(hc)), "hurt")
	if skill.has("generates"):
		caster.resource.gain(float(skill.generates) * (caster.stats.mult("resource_gen") if caster.resource.kind == "fury" else 1.0))
	if max_charges > 1:
		caster.skill_charges[skill_id] = int(caster.skill_charges.get(skill_id, max_charges)) - 1
		if caster.cooldown_left(skill_id) <= 0.0:
			caster.cooldowns[skill_id] = caster.stats.cooldown_for(skill) * maxf(0.1, 1.0 + caster.stats.skill_mod(skill_id, "recharge_mult"))
	else:
		caster.cooldowns[skill_id] = caster.stats.cooldown_for(skill)
	var proc_need := str(skill.get("usable_if", {}).get("proc", ""))
	if not proc_need.is_empty() and skill.get("usable_if", {}).get("consume", true):
		caster.status.remove(proc_need)
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
	fire(caster, "on_skill_cast", {"skill": skill_id, "school": school, "target": null, "ctx": {}})
	if skill.has("channel"):
		var ch: Dictionary = skill.channel
		caster.channel = {"skill": skill_id, "left": float(ch.get("duration", 2.0)) * (1.0 + caster.stats.skill_mod(skill_id, "duration_mult")),
			"tick_left": float(ch.get("first_tick", 0.0)), "aim": aim, "start": caster.global_position}
		fx.cast_bar.rpc(caster.get_path(), float(caster.channel.left))
		if skill.has("on_cast"):
			var cctx := make_ctx(caster, skill)
			for eff in skill.on_cast:
				run_effect(eff, cctx, caster.global_position, aim)
		return ""
	if skill.has("charge_time"):
		var ct := float(skill.charge_time) * (1.0 + caster.stats.skill_mod(skill_id, "charge_time_mult"))
		caster.charging = {"skill": skill_id, "t": 0.0, "max": maxf(ct, 0.05), "aim": aim}
		fx.cast_bar.rpc(caster.get_path(), ct)
		return ""
	# A wind-up ("windup", not shortened by haste) gives a cast bar plus a ground marker.
	var cast_time := maxf(cast_time_for(caster.stats, skill), float(skill.get("windup", 0.0)))
	if cast_time > 0.01:
		caster.casting = {"skill": skill_id, "aim": aim, "left": cast_time, "extra": extra}
		fx.cast_bar.rpc(caster.get_path(), cast_time)
		if skill.has("windup"):
			_windup_marker(caster, skill, aim, cast_time)
	else:
		finish_cast(caster, skill_id, aim, extra)
	return ""


## Leaps and charges: the moves that need a wind-up and a grace period on monsters (#2).
static func is_lunge(skill: Dictionary) -> bool:
	for eff in skill.get("effects", []):
		if eff is Dictionary and str(eff.get("type", "")) in ["leap", "charge"]:
			return true
	return false


## The ground marker of a wind-up: the landing circle of a leap or the path of a charge, as
## finish_cast will compute it from the same aim.
func _windup_marker(caster: Actor, skill: Dictionary, aim: Vector2, windup: float) -> void:
	var origin := caster.global_position
	var dir := (aim - origin).normalized()
	if dir == Vector2.ZERO:
		dir = caster.facing
	for eff in skill.get("effects", []):
		match str(eff.get("type", "")):
			"leap":
				var dest := walkable_point(origin, dir, minf(origin.distance_to(aim), float(eff.get("distance", 200))))
				var r := 36.0
				for sub in eff.get("on_arrive", []):
					r = maxf(r, float(sub.get("radius", 0.0)))
				fx.windup_marker.rpc("circle", origin, dest, r, windup + float(eff.get("duration", 0.45)), str(eff.get("color", "#ff3020")))
				return
			"charge":
				var end := walkable_point(origin, dir, float(eff.get("distance", 240)))
				fx.windup_marker.rpc("line", origin, end, float(eff.get("width", 18)), windup + origin.distance_to(end) / float(eff.get("speed", 760)), str(eff.get("color", "#ff3020")))
				return


## Checks `usable_if` and a required target. Returns "" or the reason.
func _usable(caster: Actor, skill: Dictionary, aim: Vector2) -> String:
	var u: Dictionary = skill.get("usable_if", {})
	if u.has("proc") and not caster.status.has(str(u.proc)):
		return "Not ready"
	if u.has("self_status") and not caster.status.has(str(u.self_status)):
		return "Not ready"
	var need_target: bool = skill.get("requires_target", false) or u.has("target_hp_below") or u.has("target_status") or u.has("target_creature")
	if not need_target:
		return ""
	var eff0: Dictionary = skill.effects[0] if not skill.effects.is_empty() else {}
	var ctx := make_ctx(caster, skill)
	var reach := float(eff0.get("range", eff0.get("max_range", 300))) * float(ctx.range_mult)
	var t := aim_enemy(ctx, caster.global_position, aim, reach, 80.0)
	if t == null:
		return "No target"
	var hp_below := float(u.get("target_hp_below", 2.0)) + caster.stats.skill_mod(str(skill.id), "hp_threshold_add")
	if t.health.fraction() >= hp_below:
		return "Target health too high"
	if u.has("target_status") and not t.status.has_any(Array(u.target_status) if u.target_status is Array else [u.target_status]):
		return "Target not affected"
	if u.has("target_creature") and not Array(u.target_creature).has(t.creature_type()):
		return "Invalid target"
	return ""


func finish_cast(caster: Actor, skill_id: String, aim: Vector2, extra: Dictionary = {}) -> void:
	var skill := GameData.skill(skill_id)
	var ctx := make_ctx(caster, skill)
	ctx.merge(extra, true)
	for eff in skill.effects:
		run_effect(eff, ctx, caster.global_position, aim)
	# Double Tap: the skill fires once more for free while the status is up.
	var rep: Dictionary = skill.get("repeat_if_status", {})
	if not rep.is_empty() and caster.status.has(str(rep.status)) and not extra.get("repeat", false):
		caster.status.remove(str(rep.status))
		var again := extra.duplicate()
		again.repeat = true
		get_tree().create_timer(float(rep.get("delay", 0.15))).timeout.connect(func():
			if is_instance_valid(caster) and caster.is_alive():
				finish_cast(caster, skill_id, caster.get("aim_pos") if caster.get("aim_pos") != null else aim, again))


## The numbers a skill uses, from its caster's stats. Host combat and the UI's skill tooltips
## both read these, so what the tooltip shows is what the host deals.
static func skill_numbers(st: Stats, level: int, skill: Dictionary) -> Dictionary:
	var sid: String = skill.get("id", "")
	var school: String = skill.get("school", "melee")
	var dmg_mult := st.get_stat("damage_mult", 1.0) * (1.0 + st.skill_mod(sid, "damage_mult"))
	var element := str(skill.get("element", ""))
	if not element.is_empty():
		dmg_mult *= st.mult(element + "_spell_damage")
	return {
		"skill": sid, "school": school, "element": element,
		"damage_type": GameData.damage_type_of(skill),
		"power": st.power_for(str(skill.get("power_school", school))),
		"damage_mult": dmg_mult,
		"heal_mult": st.get_stat("healing_mult", 1.0) * (1.0 + st.skill_mod(sid, "heal_mult")),
		"crit_chance": st.get_stat("crit_chance") + st.skill_mod(sid, "crit_add"),
		"crit_damage": st.get_stat("crit_damage", 0.5) + st.skill_mod(sid, "crit_damage_add") + float(skill.get("crit_damage_add", 0.0)),
		"cc_bonus": st.get_stat("cc_bonus"),
		"leech": st.get_stat("leech"), "level": level,
		"threat_mult": float(skill.get("threat_mult", 1.0)) * st.get_stat("threat_mult", 1.0) * (1.0 + st.skill_mod(sid, "threat_mult")),
		"resource_on_hit": float(skill.get("resource_on_hit", -1.0)),
		"radius_mult": 1.0 + st.skill_mod(sid, "radius_mult"),
		"duration_mult": 1.0 + st.skill_mod(sid, "duration_mult"),
		"range_mult": (1.0 + st.skill_mod(sid, "range_mult")) * (st.mult("range") if school == "ranged" or skill.get("ranged_skill", false) else 1.0),
		"count_add": int(st.skill_mod(sid, "count_add")),
		"pierce_add": int(st.skill_mod(sid, "pierce_add")),
		"armor_pen": st.get_stat("armor_pen") + st.skill_mod(sid, "armor_pen") + float(skill.get("armor_pen", 0.0)),
		"magic_pen": st.get_stat("magic_pen") + st.skill_mod(sid, "magic_pen"),
		"cannot_miss": bool(skill.get("cannot_miss", false)) or st.has_flag("cannot_miss") and school == "ranged",
		"trap_radius_mult": 1.0 + st.skill_mod("*traps", "radius_mult") + st.mult("trap_radius") - 1.0,
		"low_hp_heal_below": st.get_stat("low_hp_heal_below"), "low_hp_heal_bonus": st.get_stat("low_hp_heal_bonus"),
		"dot_can_crit": st.has_flag("dot_can_crit"),
	}


## Damage / healing / magnitude of a {"base", "coef"} spec for the given skill numbers.
static func value_of(spec: Variant, nums: Dictionary) -> float:
	if not spec is Dictionary or spec.is_empty():
		return 0.0
	var base := float(spec.get("base", 0))
	if spec.get("level_scaled", false):
		base *= legendary_scale(int(nums.get("level", 30)))
	return (base + float(nums.power) * float(spec.get("coef", 0))) * float(nums.damage_mult)


## D7: legendary numbers are level-30 values, scaled linearly down to `scale_floor` at level 1.
static func legendary_scale(level: int) -> float:
	var f := float(GameData.bal("legendary.scale_floor", 0.35))
	return f + (1.0 - f) * clampf(float(level) / 30.0, 0.0, 1.0)


## Cast time after haste.
static func cast_time_for(st: Stats, skill: Dictionary) -> float:
	return float(skill.get("cast_time", 0.0)) / (1.0 + st.get_stat("haste"))


## Host: the owner released a charge-up skill (or the harness / AI fires it).
func release_charge(caster: Actor, aim: Vector2) -> void:
	if caster.charging.is_empty():
		return
	var c: Dictionary = caster.charging
	caster.charging = {}
	var frac := clampf(float(c.t) / float(c.max), 0.0, 1.0)
	var lo := float(GameData.bal("combat.charge_min_mult", 0.4))
	finish_cast(caster, str(c.skill), aim, {"charge": lerpf(lo, 1.0, frac)})


## Host: the owner released a channelled skill.
func stop_channel(caster: Actor) -> void:
	if not caster.channel.is_empty():
		caster.channel = {}
		fx.cast_bar.rpc(caster.get_path(), 0.0)


# =========================================================================================
# Host simulation
# =========================================================================================


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_step_projectiles(delta)
	_step_zones(delta)
	_step_delayed(delta)
	_step_tethers(delta)
	for a in all_actors():
		if not a is Actor:
			continue
		if not a.channel.is_empty():
			_step_channel(a, delta)
		if not a.charging.is_empty():
			a.charging.t += delta
			if a.charging.t >= float(a.charging.max) + float(GameData.bal("combat.charge_hold_max", 2.0)) or not a.can_act():
				release_charge(a, a.get("aim_pos") if a.get("aim_pos") != null else a.charging.aim)


func _step_channel(a: Actor, delta: float) -> void:
	var ch: Dictionary = a.channel
	var skill := GameData.skill(str(ch.skill))
	var spec: Dictionary = skill.get("channel", {})
	if not a.can_act() or a.status.has_flag("silenced") and str(skill.get("school", "")) == "spell":
		stop_channel(a)
		return
	# Slippers of Grace: healing channels survive moving.
	var mobile := a.stats.has_flag("mobile_caster") and JSON.stringify(skill.get("effects", [])).contains("\"heal\"")
	if spec.get("move_cancels", false) and not mobile and a.global_position.distance_to(ch.start) > 6.0:
		stop_channel(a)
		return
	var cps := float(spec.get("cost_per_second", 0.0)) * a.stats.mult("cost")
	if cps > 0.0 and a.resource.kind != "none" and not a.resource.pay(cps * delta):
		stop_channel(a)
		return
	ch.left -= delta
	ch.tick_left -= delta
	var aim: Vector2 = a.get("aim_pos") if a.get("aim_pos") != null else ch.aim
	if a.has_method("channel_aim"):
		aim = a.channel_aim(aim)
	if ch.tick_left <= 0.0:
		ch.tick_left += float(spec.get("tick", 0.5))
		var ctx := make_ctx(a, skill)
		for eff in spec.get("tick_effects", skill.effects):
			run_effect(eff, ctx, a.global_position, aim)
	if ch.left <= 0.0:
		stop_channel(a)


## Called by StatusEffects on the host for DoT / HoT ticks and status auras (`tick_effects`).
func status_tick(actor: Actor, e: Dictionary) -> void:
	var ctx: Dictionary = e.source if e.source is Dictionary else env_ctx(0.0)
	var kind := str(e.def.get("kind", ""))
	if kind == "dot":
		var amount := float(e.magnitude) * int(e.stacks)
		# Arterial Shot: a moving target bleeds harder.
		if e.def.has("moving_mult") and actor.get("_last_visual_pos") != null and actor.velocity.length() > 5.0:
			amount *= float(e.def.moving_mult)
		var c := ctx
		if e.def.get("ramp", 0.0) > 0.0:
			c = ctx.duplicate()
			c.damage_mult = 1.0
			amount *= 1.0 + float(e.def.ramp) * float(e.get("ticks", 0))
		e.ticks = int(e.get("ticks", 0)) + 1
		deal_damage(c, actor, amount, {"dot": true, "damage_type": str(e.def.get("damage_type", "physical"))})
	elif kind == "hot":
		var hc := ctx.duplicate()
		hc.hot = true
		heal(hc, actor, float(e.magnitude) * int(e.stacks))
	for eff in e.def.get("tick_effects", []):
		var tc: Dictionary = (ctx if e.source is Dictionary and is_instance_valid(ctx.get("caster")) else make_ctx(actor, {"id": e.id, "school": "spell"})).duplicate()
		tc.event_target = actor
		tc.magnitude = e.magnitude
		if e.def.get("scale_damage_by_magnitude", false):
			tc.damage_mult = float(e.magnitude)
		run_effect(eff, tc, actor.global_position, actor.global_position)


## Runs a status's `on_apply` / `on_expire` effects at the actor, crediting the status's source.
func status_callback(actor: Actor, e: Dictionary, which: String) -> void:
	if e.is_empty() or not is_instance_valid(actor):
		return
	var ctx: Dictionary = (e.source if e.source is Dictionary else env_ctx(0.0)).duplicate()
	ctx.event_target = actor
	ctx.stored = float(e.get("recorded", 0.0))
	ctx.magnitude = float(e.magnitude)
	ctx.stacks = int(e.stacks)
	for eff in e.def.get(which, []):
		run_effect(eff, ctx, actor.global_position, actor.global_position)
