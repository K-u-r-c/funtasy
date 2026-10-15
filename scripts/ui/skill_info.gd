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
	out.append(_row("Cooldown", "%.1fs" % st.cooldown_for(skill)))
	var cost := st.cost_for(skill)
	if cost > 0.0:
		out.append(_row("Cost", "%d %s" % [roundi(cost), _res_name(p)]))
	var cast := Combat.cast_time_for(st, skill)
	out.append(_row("Cast time", "%.2fs" % cast if cast > 0.0 else "Instant"))
	var deals := false
	for eff in skill.get("effects", []):
		deals = _effect(out, eff, nums, p, "") or deals
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
			out.append(_row(prefix + "Teleport", _m(float(eff.distance))))
		"status":
			_status(out, prefix, eff, nums, _target_text(eff))
		"heal":
			out.append(_row(prefix + "Heal", "%d%s" % [_amount(eff.amount, nums, true), _target_text(eff)], Kind.HEAL))
		"absorb":
			out.append(_row(prefix + "Shield", "absorbs %d for %.0fs%s" % [_amount(eff.amount, nums, true), float(eff.duration), _target_text(eff)], Kind.HEAL))
		"taunt":
			out.append(_row(prefix + "Taunt", "%.1fs, enemies within %s" % [float(eff.duration), _m(float(eff.radius) * rmul)], Kind.STATUS))
		"resource":
			out.append(_row(prefix + _res_name(p), "+%d" % roundi(float(eff.amount))))
	if str(eff.type) in ["melee", "projectile", "aoe", "zone"]:
		_on_hit(out, eff, nums, prefix)
	return deals


static func _on_hit(out: Array, eff: Dictionary, nums: Dictionary, prefix: String) -> void:
	for oh in eff.get("on_hit", []):
		match str(oh.type):
			"status":
				_status(out, prefix, oh, nums, "")
			"knockback":
				out.append(_row(prefix + "Knockback", "%d force" % int(oh.force), Kind.STATUS))


## A status the skill applies: damage/healing per tick for DoTs/HoTs, otherwise its duration.
static func _status(out: Array, prefix: String, eff: Dictionary, nums: Dictionary, target: String) -> void:
	var def: Dictionary = GameData.status_effects.get(str(eff.status), {})
	var dur := float(eff.duration) * float(nums.duration_mult)
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
			out.append(_row(prefix + name, "%.1fs%s%s" % [dur, _stat_text(def), target], Kind.STATUS))


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
