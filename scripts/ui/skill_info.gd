class_name SkillInfo
## Tooltip rows for a skill, computed from the numbers the host's Combat uses
## (Combat.skill_numbers / value_of / cast_time_for, Stats.cooldown_for / cost_for), so the
## tooltip shows what the skill really does with the player's current stats and talents.
## Distances are shown in metres (one 32 px floor tile = 1 m).

enum Kind { INFO, DAMAGE, HEAL, STATUS, TALENT }

const TILE := 32.0
const POWER_NAMES := {"melee": "Melee power", "ranged": "Ranged power", "spell": "Spell power"}
const MOD_TEXT := {
	"damage_mult": "%+d%% effect", "heal_mult": "%+d%% healing", "cooldown_mult": "%+d%% cooldown",
	"cost_mult": "%+d%% cost", "radius_mult": "%+d%% radius", "duration_mult": "%+d%% duration",
}


## [{"k": label, "v": value, "kind": Kind}] for the skill as cast by `p` right now.
static func rows(p: Player, skill: Dictionary) -> Array:
	var st := p.stats
	var nums := Combat.skill_numbers(st, p.level, skill)
	var out: Array = []
	if skill.get("passive", false):
		out.append(_row("Type", "Passive: always active once learned"))
	elif skill.has("toggle"):
		out.append(_row("Type", "Toggle: switch on and off"))
	out.append(_row("Cooldown", "%.1fs" % st.cooldown_for(skill)))
	if skill.has("charges"):
		out.append(_row("Charges", "%d" % int(skill.charges)))
	var cost := st.cost_for(skill)
	if cost > 0.0:
		out.append(_row("Cost", "%d %s" % [roundi(cost), _res_name(p)]))
	var cast := Combat.cast_time_for(st, skill)
	if skill.has("channel"):
		var ch: Dictionary = skill.channel
		var line := "%.1fs, every %.2fs" % [float(ch.get("duration", 2.0)) * float(nums.duration_mult), float(ch.get("tick", 0.5))]
		if float(ch.get("cost_per_second", 0.0)) > 0.0:
			line += ", %d %s/s" % [roundi(float(ch.cost_per_second) * st.mult("cost")), _res_name(p)]
		if ch.get("move_cancels", false):
			line += ", moving stops it"
		out.append(_row("Channel", line))
	elif skill.has("charge_time"):
		out.append(_row("Charge", "hold up to %.1fs, release to fire (weaker if early)" % float(skill.charge_time)))
	elif not skill.get("passive", false):
		out.append(_row("Cast time", "%.2fs" % cast if cast > 0.0 else "Instant"))
	var u: Dictionary = skill.get("usable_if", {})
	if u.has("target_hp_below"):
		out.append(_row("Requires", "target below %d%% health" % roundi(float(u.target_hp_below) * 100.0), Kind.STATUS))
	if u.has("target_status"):
		out.append(_row("Requires", "target %s" % _status_names(u.target_status), Kind.STATUS))
	if u.has("target_creature"):
		out.append(_row("Requires", ", ".join(Array(u.target_creature)) + " target", Kind.STATUS))
	if u.has("proc"):
		out.append(_row("Requires", "%s window" % _status_names(u.proc), Kind.STATUS))
	if skill.has("cost_hp_pct"):
		out.append(_row("Health cost", "%d%% of current health" % roundi(float(skill.cost_hp_pct) * 100.0), Kind.DAMAGE))
	if skill.get("consumes_all_resource", false):
		out.append(_row("Consumes", "all %s" % _res_name(p)))
	var deals := false
	for eff in skill.get("on_cast", []):
		deals = _effect(out, eff, nums, p, "") or deals
	for eff in skill.get("effects", []):
		deals = _effect(out, eff, nums, p, "Per tick: " if skill.has("channel") else "") or deals
	if skill.has("toggle"):
		_status(out, "", {"status": skill.toggle, "duration": -1.0}, nums, ", self")
	if float(nums.resource_on_hit) > 0.0:
		out.append(_row("On hit", "+%d %s" % [roundi(float(nums.resource_on_hit)), _res_name(p)]))
	if deals or _scales(skill):
		out.append(_row("Scaling", "%s %d" % [POWER_NAMES.get(str(nums.school), "Power"), roundi(float(nums.power))]))
	if deals:
		out.append(_row("Critical", "%d%% chance, +%d%% damage" % [roundi(float(nums.crit_chance) * 100.0), roundi(float(nums.crit_damage) * 100.0)]))
		if float(nums.leech) > 0.0:
			out.append(_row("Leech", "%d%% of damage" % roundi(float(nums.leech) * 100.0), Kind.HEAL))
	for t in talent_rows(p, str(skill.get("id", ""))):
		out.append(t)
	return out


## The talents the player has learned that change this skill.
static func talent_rows(p: Player, skill_id: String) -> Array:
	var out: Array = []
	var tree: Dictionary = GameData.talents.get(p.class_id, {})
	for node in tree.get("nodes", []):
		var rank := int(p.talents.get(node.id, 0))
		if rank <= 0:
			continue
		var parts: Array = []
		for m in node.get("mods", []):
			if not m.has("skill"):
				continue
			var targets: Array = m.skill if m.skill is Array else [m.skill]
			if not targets.has(skill_id) and not targets.has("*"):
				continue
			var v := float(m.value) * rank
			match str(m.field):
				"count_add":
					parts.append("%+d projectiles" % roundi(v))
				"pierce_add":
					parts.append("%+d pierce" % roundi(v))
				_:
					parts.append(str(MOD_TEXT.get(m.field, "%+d%% " + str(m.field))) % roundi(v * 100.0))
		if not parts.is_empty():
			out.append(_row("%s %d/%d" % [node.get("name", node.id), rank, int(node.get("max_rank", rank))], ", ".join(parts), Kind.TALENT))
	return out


## Appends the rows of one effect; true when it deals damage.
static func _effect(out: Array, eff: Dictionary, nums: Dictionary, p: Player, prefix: String) -> bool:
	var deals := false
	var rmul := float(nums.radius_mult)
	match str(eff.type):
		"melee":
			deals = _damage(out, prefix + "Damage", eff, nums, "")
			out.append(_row(prefix + "Reach", "%s, %d° arc, up to %d targets" % [_m(float(eff.range) * rmul), int(eff.get("arc", 90)), int(eff.get("max_targets", 99))]))
		"projectile":
			var count := int(eff.get("count", 1)) + int(nums.count_add)
			deals = _damage(out, prefix + "Damage", eff, nums, " x%d" % count if count > 1 else "")
			var pierce := int(eff.get("pierce", 0)) + int(nums.pierce_add)
			var line := "%s range" % _m(float(eff.range))
			if pierce > 0:
				line += ", pierces %d" % pierce
			out.append(_row(prefix + "Projectile", line))
			if eff.has("explode"):
				var ex: Dictionary = eff.explode
				deals = _damage(out, prefix + "Explosion", ex, nums, " in %s" % _m(float(ex.radius) * rmul)) or deals
				_on_hit(out, ex, nums, prefix)
		"aoe":
			var where := "around you" if eff.get("at", "self") == "self" else "at the cursor"
			if eff.has("damage"):
				deals = _damage(out, prefix + "Area damage", eff, nums, "")
			if eff.has("heal"):
				out.append(_row(prefix + "Area heal", "%d" % _amount(eff.heal, nums, true), Kind.HEAL))
			var area := "%s radius %s" % [_m(float(eff.radius) * rmul), where]
			if float(eff.get("delay", 0.0)) > 0.0:
				area += ", after %.1fs" % float(eff.delay)
			out.append(_row(prefix + "Area", area))
		"zone":
			var tick := float(eff.get("tick", 1.0))
			if eff.has("damage"):
				deals = _damage(out, prefix + "Damage", eff, nums, " every %.1fs" % tick)
			if eff.has("heal"):
				out.append(_row(prefix + "Healing", "%d every %.1fs" % [_amount(eff.heal, nums, true), tick], Kind.HEAL))
			out.append(_row(prefix + "Zone", "%s radius for %.0fs" % [_m(float(eff.get("radius", 40)) * rmul), float(eff.duration)]))
		"trap":
			out.append(_row(prefix + "Trap", "arms in %.1fs, lasts %.0fs" % [float(eff.get("arm_time", 0.0)), float(eff.duration)]))
			for sub in eff.get("effects", []):
				deals = _effect(out, sub, nums, p, "Trap: ") or deals
		"dash":
			out.append(_row(prefix + "Dash", _m(float(eff.distance))))
			for sub in eff.get("on_arrive", []):
				deals = _effect(out, sub, nums, p, "On arrival: ") or deals
		"blink":
			out.append(_row(prefix + "Teleport", _m(float(eff.distance)), Kind.STATUS))
			if eff.has("decoy"):
				out.append(_row(prefix + "Decoy", "a mirror image draws aggro for %.1fs" % float(eff.decoy.get("duration", 2.0)), Kind.STATUS))
		"status":
			_status(out, prefix, eff, nums, _target_text(eff))
		"heal":
			out.append(_row(prefix + "Heal", "%d%s" % [_amount(eff.amount, nums, true), _target_text(eff)], Kind.HEAL))
		"absorb":
			out.append(_row(prefix + "Shield", "absorbs %d for %.0fs%s" % [_amount(eff.amount, nums, true), float(eff.duration), _target_text(eff)], Kind.HEAL))
		"taunt":
			out.append(_row(prefix + "Taunt", "%.1fs, enemies within %s" % [float(eff.duration), _m(float(eff.radius) * rmul)], Kind.STATUS))
		"resource":
			out.append(_row(prefix + _res_name(p), "+%d" % roundi(float(eff.get("amount", 0)))))
		"cone":
			deals = _damage(out, prefix + "Damage", eff, nums, "")
			out.append(_row(prefix + "Cone", "%d° over %s" % [int(eff.get("arc", 90)), _m(float(eff.range) * rmul)]))
		"hit":
			deals = _damage(out, prefix + "Damage", eff, nums, "")
			var who := "the enemy at the cursor"
			match str(eff.get("target", "aim_enemy")):
				"aim_any":
					who = "the enemy or ally at the cursor"
				"random_enemy":
					who = "a random enemy"
				"highest_hp_enemy":
					who = "the healthiest enemy"
				"event_target":
					who = "the same target"
			out.append(_row(prefix + "Target", "%s%s" % [who, ", %s" % _m(float(eff.range)) if eff.has("range") else ""]))
			for sub in eff.get("ally_effects", []):
				deals = _effect(out, sub, nums, p, prefix + "On an ally: ") or deals
			if eff.has("drain"):
				out.append(_row(prefix + "Drain", "heals you for %d%% of the damage" % roundi(float(eff.drain) * 100.0), Kind.HEAL))
		"line":
			deals = _damage(out, prefix + "Damage", eff, nums, "")
			var line := "%s long" % _m(float(eff.get("length", 70)))
			if eff.get("through_walls", false):
				line += ", through walls (x%.0f damage)" % float(eff.get("wall_bonus", 1.0))
			out.append(_row(prefix + "Line", line))
		"chain":
			deals = _damage(out, prefix + "Damage", eff, nums, "")
			out.append(_row(prefix + "Chain", "%d jumps, +%d%% per jump" % [int(eff.get("jumps", 3)) + int(nums.count_add), roundi(float(eff.get("per_jump", 0.0)) * 100.0)]))
		"beam":
			deals = _damage(out, prefix + "Beam damage", eff, nums, "")
			if eff.has("heal"):
				out.append(_row(prefix + "Beam heal", "%d to allies in the beam" % _amount(eff.heal, nums, true), Kind.HEAL))
			out.append(_row(prefix + "Beam", _m(float(eff.get("length", 250)))))
		"leap":
			out.append(_row(prefix + "Leap", "%s%s" % [_m(float(eff.get("distance", 200))), " backwards" if str(eff.get("direction", "")) == "back" else ""]))
			for sub in eff.get("on_start", []):
				deals = _effect(out, sub, nums, p, "On take-off: ") or deals
			for sub2 in eff.get("on_arrive", []):
				deals = _effect(out, sub2, nums, p, "On landing: ") or deals
		"charge":
			out.append(_row(prefix + "Charge", _m(float(eff.get("distance", 240)))))
			if eff.has("path_damage"):
				deals = _damage(out, prefix + "Path damage", {"damage": eff.path_damage}, nums, "") or deals
			for sub3 in eff.get("on_arrive", []):
				deals = _effect(out, sub3, nums, p, "On impact: ") or deals
		"knockback", "pull":
			out.append(_row(prefix + str(eff.type).capitalize(), "%s radius, %d force" % [_m(float(eff.get("radius", 100)) * rmul), int(eff.get("force", 120))], Kind.STATUS))
			_on_hit(out, eff, nums, prefix)
		"delayed":
			for sub4 in eff.get("effects", []):
				deals = _effect(out, sub4, nums, p, "After %.1fs: " % float(eff.delay)) or deals
		"deploy":
			out.append(_row(prefix + "Deploys", "for %.0fs, acts every %.1fs" % [float(eff.get("duration", 10)), float(eff.get("tick", 1.0))]))
			if eff.has("heal"):
				out.append(_row(prefix + "Healing", "%d every %.1fs%s" % [_amount(eff.heal, nums, true), float(eff.get("tick", 1.0)),
					" (below %d%% health)" % roundi(float(eff.heal_below) * 100.0) if eff.has("heal_below") else ""], Kind.HEAL))
			for sub5 in eff.get("tick_effects", []):
				deals = _effect(out, sub5, nums, p, "Each shot: ") or deals
		"consume_dots":
			out.append(_row(prefix + "Detonates", "every %s on the target at once" % _status_names(eff.get("statuses", ["burn"])), Kind.DAMAGE))
			deals = true
		"cleanse":
			out.append(_row(prefix + "Cleanses", "%s%s" % [", ".join(Array(eff.get("categories", []))), ", refunds %d" % int(eff.refund) if eff.has("refund") else ""], Kind.HEAL))
		"dispel":
			out.append(_row(prefix + "Dispels", ", ".join(Array(eff.get("categories", []))), Kind.STATUS))
		"destroy_projectiles":
			out.append(_row(prefix + "Destroys", "hostile projectiles within %s" % _m(float(eff.get("range", 120)))))
		"terrain":
			out.append(_row(prefix + "Terrain", "%s for %.0fs" % [str(GameData.obstacles.get(str(eff.get("kind", "")), {}).get("name", eff.get("kind", ""))), float(eff.get("lifetime", 6))]))
		"threat_drop":
			out.append(_row(prefix + "Threat", "drops %d%%" % roundi(float(eff.get("fraction", 1.0)) * 100.0), Kind.STATUS))
		"reveal":
			out.append(_row(prefix + "Reveals", "stealth and darkness within %s for %.0fs" % [_m(float(eff.get("radius", 250))), float(eff.get("duration", 6))]))
		"interrupt":
			out.append(_row(prefix + "Interrupts", "spellcasting%s" % (", locks the school for %.0fs" % float(eff.lockout) if eff.has("lockout") else ""), Kind.STATUS))
		"cooldown":
			out.append(_row(prefix + "Cooldowns", "%s %s" % ["reduces" if eff.has("reduce") else "resets", ", ".join(Array(eff.get("skills", [])).map(func(x): return str(GameData.skills.get(x, {}).get("name", x))))]))
		"self_damage":
			out.append(_row(prefix + "Costs", "%d%% of your health" % roundi(float(eff.get("pct_current", eff.get("pct_max", 0.0))) * 100.0), Kind.DAMAGE))
		"tether":
			out.append(_row(prefix + "Tether", "%.0fs" % float(eff.get("duration", 6))))
			for sub6 in eff.get("tick_effects", []):
				deals = _effect(out, sub6, nums, p, "Every %.1fs: " % float(eff.get("tick", 1.0))) or deals
		"fetch":
			out.append(_row(prefix + "Pulls", "the ally to your feet"))
		"teleport":
			out.append(_row(prefix + "Teleport", str(eff.get("to", "aim")).replace("_", " ")))
	if str(eff.type) in ["melee", "projectile", "aoe", "zone", "cone", "hit", "line", "chain", "beam"]:
		_on_hit(out, eff, nums, prefix)
	if str(eff.type) == "zone":
		if eff.has("status_inside"):
			_status(out, prefix + "Inside: ", {"status": eff.status_inside, "duration": float(eff.get("tick", 1.0)) + 0.3}, nums, "")
		for sub7 in eff.get("tick_effects", []):
			deals = _effect(out, sub7, nums, p, "Every %.1fs: " % float(eff.get("tick", 1.0))) or deals
	if str(eff.type) == "aoe" and eff.has("ally_effects"):
		for sub8 in eff.ally_effects:
			deals = _effect(out, sub8, nums, p, prefix + "Allies: ") or deals
	return deals


static func _status_names(ids: Variant) -> String:
	var arr: Array = ids if ids is Array else [ids]
	return ", ".join(arr.map(func(x): return str(GameData.status_effects.get(str(x), {}).get("name", x))))


static func _on_hit(out: Array, eff: Dictionary, nums: Dictionary, prefix: String) -> void:
	for oh in eff.get("on_hit", []):
		match str(oh.type):
			"status":
				_status(out, prefix, oh, nums, "")
			"knockback":
				out.append(_row(prefix + "Knockback", "%d force" % int(oh.force), Kind.STATUS))
			"aoe", "hit", "heal", "self_damage", "teleport":
				_effect(out, oh, nums, null, prefix + "On hit: ")


## A status the skill applies: damage/healing per tick for DoTs/HoTs, otherwise its duration.
static func _status(out: Array, prefix: String, eff: Dictionary, nums: Dictionary, target: String) -> void:
	var def: Dictionary = GameData.status_effects.get(str(eff.status), {})
	var dur := float(eff.duration) * float(nums.duration_mult)
	if dur < 0.0:
		dur = 9999.0
	var name := str(def.get("name", eff.status))
	match str(def.get("kind", "")):
		"dot":
			var tick := float(def.get("tick", 1.0))
			var per := roundi(Combat.value_of(eff.get("magnitude", {}), nums))
			out.append(_row(prefix + name, "%d every %.1fs for %.1fs (%d total)" % [per, tick, dur, per * int(dur / tick)], Kind.DAMAGE))
		"hot":
			var tick2 := float(def.get("tick", 1.0))
			var per2 := roundi(Combat.value_of(eff.get("magnitude", {}), nums))
			out.append(_row(prefix + name, "%d every %.1fs for %.1fs%s" % [per2, tick2, dur, target], Kind.HEAL))
		_:
			var when := "while active" if dur >= 9999.0 else "%.1fs" % dur
			out.append(_row(prefix + name, "%s%s%s" % [when, _stat_text(def), target], Kind.STATUS))


static func _damage(out: Array, label: String, eff: Dictionary, nums: Dictionary, suffix: String) -> bool:
	if not eff.has("damage"):
		return false
	var v := Combat.value_of(eff.damage, nums)
	var crit := v * (1.0 + float(nums.crit_damage))
	out.append(_row(label, "%d (crit %d)%s" % [maxi(1, roundi(v)), maxi(1, roundi(crit)), suffix], Kind.DAMAGE))
	return true


## Healing and shields: same base + power x coef, times the heal multiplier (as Combat does).
static func _amount(spec: Variant, nums: Dictionary, heal: bool) -> int:
	return roundi(Combat.value_of(spec, nums) * (float(nums.heal_mult) if heal else 1.0))


static func _stat_text(def: Dictionary) -> String:
	var parts: Array = []
	for k in def.get("stats", {}):
		var v := float(def.stats[k])
		match str(k):
			"move_speed_mult":
				parts.append("%+d%% speed" % roundi((v - 1.0) * 100.0))
			"damage_mult":
				parts.append("%+d%% damage" % roundi((v - 1.0) * 100.0))
			"damage_taken_mult":
				parts.append("%+d%% damage taken" % roundi((v - 1.0) * 100.0))
			"haste":
				parts.append("%+d%% haste" % roundi(v * 100.0))
			"crit_chance":
				parts.append("%+d%% crit" % roundi(v * 100.0))
	for f in def.get("flags", []):
		parts.append(str(f).capitalize())
	return "" if parts.is_empty() else ", " + ", ".join(parts)


static func _target_text(eff: Dictionary) -> String:
	match str(eff.get("target", "")):
		"party":
			return ", party within %s" % _m(float(eff.get("radius", 200)))
		"self":
			return ", self"
		"aim_ally":
			return ", ally at the cursor"
	return ""


static func _scales(skill: Dictionary) -> bool:
	return JSON.stringify(skill.get("effects", [])).contains("\"coef\"")


static func _res_name(p: Player) -> String:
	return str(p.class_def.get("resource", "mana")).capitalize()


static func _m(px: float) -> String:
	return "%.1fm" % (px / TILE)


static func _row(k: String, v: String, kind: int = Kind.INFO) -> Dictionary:
	return {"k": k, "v": v, "kind": kind}
