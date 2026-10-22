class_name SkillInfo
## Tooltip rows for a skill, computed from the numbers the host's Combat uses
## (Combat.skill_numbers / value_of / cast_time_for, Stats.cooldown_for / cost_for), so the
## tooltip shows what the skill really does with the player's current stats and talents.
## Distances are shown in metres (one 32 px floor tile = 1 m).

enum Kind { INFO, DAMAGE, HEAL, STATUS, TALENT }

const TILE := 32.0
const POWER_NAMES := {"melee": "Melee power", "ranged": "Ranged power", "spell": "Spell power"}
## Debuff categories cleansed or dispelled, by name.
const CATEGORY_TEXT := {"movement": "slows and roots", "poison": "poisons", "enrage": "enrage", "curse": "curses",
	"disease": "diseases", "control": "stuns and control", "bleed": "bleeds", "any": "every harmful effect", "magic": "magic"}
## Where a teleport puts the caster, by its data "to".
const TELEPORT_TEXT := {"aim": "to the aimed spot", "target": "to the target", "behind_target": "behind the target", "target_front": "in front of the target"}
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
		out.append(_row(Loc.t("Type"), Loc.t("Passive: always active once learned")))
	elif skill.has("toggle"):
		out.append(_row(Loc.t("Type"), Loc.t("Toggle: switch on and off")))
	out.append(_row(Loc.t("Cooldown"), "%.1fs" % st.cooldown_for(skill)))
	if skill.has("charges"):
		out.append(_row(Loc.t("Charges"), "%d" % int(skill.charges)))
	var cost := st.cost_for(skill)
	if cost > 0.0:
		out.append(_row(Loc.t("Cost"), "%d %s" % [roundi(cost), _res_name(p)]))
	var cast := Combat.cast_time_for(st, skill)
	if skill.has("channel"):
		var ch: Dictionary = skill.channel
		var line := Loc.f("%.1fs, every %.2fs", [float(ch.get("duration", 2.0)) * float(nums.duration_mult), float(ch.get("tick", 0.5))])
		if float(ch.get("cost_per_second", 0.0)) > 0.0:
			line += ", %d %s/s" % [roundi(float(ch.cost_per_second) * st.mult("cost")), _res_name(p)]
		if ch.get("move_cancels", false):
			line += Loc.t(", moving stops it")
		out.append(_row(Loc.t("Channel"), line))
	elif skill.has("charge_time"):
		out.append(_row(Loc.t("Charge"), Loc.f("hold up to %.1fs, release to fire (weaker if early)", [float(skill.charge_time)])))
	elif not skill.get("passive", false):
		out.append(_row(Loc.t("Cast time"), "%.2fs" % cast if cast > 0.0 else Loc.t("Instant")))
	var u: Dictionary = skill.get("usable_if", {})
	if u.has("target_hp_below"):
		out.append(_row(Loc.t("Requires"), Loc.f("target below %d%% health", [roundi(float(u.target_hp_below) * 100.0)]), Kind.STATUS))
	if u.has("target_status"):
		out.append(_row(Loc.t("Requires"), Loc.f("target %s", [_status_names(u.target_status)]), Kind.STATUS))
	if u.has("target_creature"):
		out.append(_row(Loc.t("Requires"), ", ".join(Array(u.target_creature).map(func(c): return Loc.t(str(c).capitalize()))) + Loc.t(" target"), Kind.STATUS))
	if u.has("proc"):
		out.append(_row(Loc.t("Requires"), Loc.f("%s window", [_status_names(u.proc)]), Kind.STATUS))
	if skill.has("cost_hp_pct"):
		out.append(_row(Loc.t("Health cost"), Loc.f("%d%% of current health", [roundi(float(skill.cost_hp_pct) * 100.0)]), Kind.DAMAGE))
	if skill.get("consumes_all_resource", false):
		out.append(_row(Loc.t("Consumes"), Loc.f("all %s", [_res_name(p)])))
	var deals := false
	for eff in skill.get("on_cast", []):
		deals = _effect(out, eff, nums, p, "") or deals
	for eff in skill.get("effects", []):
		deals = _effect(out, eff, nums, p, Loc.t("Per tick: ") if skill.has("channel") else "") or deals
	if skill.has("toggle"):
		_status(out, "", {"status": skill.toggle, "duration": -1.0}, nums, Loc.t(", self"))
	if float(nums.resource_on_hit) > 0.0:
		out.append(_row(Loc.t("On hit"), "+%d %s" % [roundi(float(nums.resource_on_hit)), _res_name(p)]))
	if deals or _scales(skill):
		out.append(_row(Loc.t("Scaling"), "%s %d" % [Loc.t(POWER_NAMES.get(str(nums.school), "Power")), roundi(float(nums.power))]))
	if deals:
		out.append(_row(Loc.t("Critical"), Loc.f("%d%% chance, +%d%% damage", [roundi(float(nums.crit_chance) * 100.0), roundi(float(nums.crit_damage) * 100.0)])))
		var leech := Combat.leech_share(float(nums.leech), st.mult("leech_efficiency"), true)
		if leech > 0.0:
			out.append(_row(Loc.t("Leech"), Loc.f("%d%% of damage", [roundi(leech * 100.0)]), Kind.HEAL))
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
					parts.append(Loc.f("%+d projectiles", [roundi(v)]))
				"pierce_add":
					parts.append(Loc.f("%+d pierce", [roundi(v)]))
				_:
					parts.append(Loc.f(str(MOD_TEXT.get(m.field, "%+d%% " + str(m.field))), [roundi(v * 100.0)]))
		if not parts.is_empty():
			out.append(_row("%s %d/%d" % [Loc.t(str(node.get("name", node.id))), rank, int(node.get("max_rank", rank))], ", ".join(parts), Kind.TALENT))
	return out


## Appends the rows of one effect; true when it deals damage.
static func _effect(out: Array, eff: Dictionary, nums: Dictionary, p: Player, prefix: String) -> bool:
	var deals := false
	var rmul := float(nums.radius_mult)
	match str(eff.type):
		"melee":
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, "")
			out.append(_row(prefix + Loc.t("Reach"), Loc.f("%s, %d° arc, up to %d targets", [_m(float(eff.range) * rmul), int(eff.get("arc", 90)), int(eff.get("max_targets", 99))])))
		"projectile":
			var count := int(eff.get("count", 1)) + int(nums.count_add)
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, " x%d" % count if count > 1 else "")
			var pierce := int(eff.get("pierce", 0)) + int(nums.pierce_add)
			var line := Loc.f("%s range", [_m(float(eff.range))])
			if pierce > 0:
				line += Loc.f(", pierces %d", [pierce])
			out.append(_row(prefix + Loc.t("Projectile"), line))
			if eff.has("explode"):
				var ex: Dictionary = eff.explode
				deals = _damage(out, prefix + Loc.t("Explosion"), ex, nums, Loc.f(" in %s", [_m(float(ex.radius) * rmul)])) or deals
				_on_hit(out, ex, nums, prefix)
		"aoe":
			var where := Loc.t("around you") if eff.get("at", "self") == "self" else Loc.t("at the cursor")
			if eff.has("damage"):
				deals = _damage(out, prefix + Loc.t("Area damage"), eff, nums, "")
			if eff.has("heal"):
				out.append(_row(prefix + Loc.t("Area heal"), "%d" % _amount(eff.heal, nums, true), Kind.HEAL))
			var area := Loc.f("%s radius %s", [_m(float(eff.radius) * rmul), where])
			if float(eff.get("delay", 0.0)) > 0.0:
				area += Loc.f(", after %.1fs", [float(eff.delay)])
			out.append(_row(prefix + Loc.t("Area"), area))
		"zone":
			var tick := float(eff.get("tick", 1.0))
			if eff.has("damage"):
				deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, Loc.f(" every %.1fs", [tick]))
			if eff.has("heal"):
				out.append(_row(prefix + Loc.t("Healing"), Loc.f("%d every %.1fs", [_amount(eff.heal, nums, true), tick]), Kind.HEAL))
			out.append(_row(prefix + Loc.t("Zone"), Loc.f("%s radius for %.0fs", [_m(float(eff.get("radius", 40)) * rmul), float(eff.duration)])))
		"trap":
			out.append(_row(prefix + Loc.t("Trap"), Loc.f("arms in %.1fs, lasts %.0fs", [float(eff.get("arm_time", 0.0)), float(eff.duration)])))
			for sub in eff.get("effects", []):
				deals = _effect(out, sub, nums, p, Loc.t("Trap: ")) or deals
		"dash":
			out.append(_row(prefix + Loc.t("Dash"), _m(float(eff.distance))))
			for sub in eff.get("on_arrive", []):
				deals = _effect(out, sub, nums, p, Loc.t("On arrival: ")) or deals
		"blink":
			out.append(_row(prefix + Loc.t("Teleport"), _m(float(eff.distance)), Kind.STATUS))
			if eff.has("decoy"):
				out.append(_row(prefix + Loc.t("Decoy"), Loc.f("a mirror image draws aggro for %.1fs", [float(eff.decoy.get("duration", 2.0))]), Kind.STATUS))
		"status":
			_status(out, prefix, eff, nums, _target_text(eff))
		"heal":
			out.append(_row(prefix + Loc.t("Heal"), "%s%s" % [_amount_text(eff.amount, nums, p, true), _target_text(eff)], Kind.HEAL))
		"absorb":
			out.append(_row(prefix + Loc.t("Shield"), Loc.f("absorbs %s for %.0fs%s", [_amount_text(eff.amount, nums, p, true), float(eff.duration), _target_text(eff)]), Kind.HEAL))
		"taunt":
			out.append(_row(prefix + Loc.t("Taunt"), Loc.f("%.1fs, enemies within %s", [float(eff.duration), _m(float(eff.radius) * rmul)]), Kind.STATUS))
		"resource":
			out.append(_row(prefix + _res_name(p), "+%d" % roundi(float(eff.get("amount", 0)))))
		"cone":
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, "")
			out.append(_row(prefix + Loc.t("Cone"), Loc.f("%d° over %s", [int(eff.get("arc", 90)), _m(float(eff.range) * rmul)])))
		"hit":
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, "")
			var who := Loc.t("the enemy at the cursor")
			match str(eff.get("target", "aim_enemy")):
				"aim_any":
					who = Loc.t("the enemy or ally at the cursor")
				"random_enemy":
					who = Loc.t("a random enemy")
				"highest_hp_enemy":
					who = Loc.t("the healthiest enemy")
				"event_target":
					who = Loc.t("the same target")
			out.append(_row(prefix + Loc.t("Target"), "%s%s" % [who, ", %s" % _m(float(eff.range)) if eff.has("range") else ""]))
			for sub in eff.get("ally_effects", []):
				deals = _effect(out, sub, nums, p, prefix + Loc.t("On an ally: ")) or deals
			if eff.has("drain"):
				out.append(_row(prefix + Loc.t("Drain"), Loc.f("heals you for %d%% of the damage", [roundi(float(eff.drain) * 100.0)]), Kind.HEAL))
		"line":
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, "")
			var line := Loc.f("%s long", [_m(float(eff.get("length", 70)))])
			if eff.get("through_walls", false):
				line += Loc.f(", through walls (x%.0f damage)", [float(eff.get("wall_bonus", 1.0))])
			out.append(_row(prefix + Loc.t("Line"), line))
		"chain":
			deals = _damage(out, prefix + Loc.t("Damage"), eff, nums, "")
			out.append(_row(prefix + Loc.t("Chain"), Loc.f("%s range, %d jumps of up to %s, +%d%% per jump", [_m(float(eff.get("range", 250)) * float(nums.range_mult)),
				int(eff.get("jumps", 3)) + int(nums.count_add), _m(float(eff.get("jump_range", 130))), roundi(float(eff.get("per_jump", 0.0)) * 100.0)])))
		"beam":
			deals = _damage(out, prefix + Loc.t("Beam damage"), eff, nums, "")
			if eff.has("heal"):
				out.append(_row(prefix + Loc.t("Beam heal"), Loc.f("%d to allies in the beam", [_amount(eff.heal, nums, true)]), Kind.HEAL))
			out.append(_row(prefix + Loc.t("Beam"), _m(float(eff.get("length", 250)))))
		"leap":
			out.append(_row(prefix + Loc.t("Leap"), "%s%s" % [_m(float(eff.get("distance", 200))), Loc.t(" backwards") if str(eff.get("direction", "")) == "back" else ""]))
			for sub in eff.get("on_start", []):
				deals = _effect(out, sub, nums, p, Loc.t("On take-off: ")) or deals
			for sub2 in eff.get("on_arrive", []):
				deals = _effect(out, sub2, nums, p, Loc.t("On landing: ")) or deals
		"charge":
			out.append(_row(prefix + Loc.t("Charge"), _m(float(eff.get("distance", 240)))))
			if eff.has("path_damage"):
				deals = _damage(out, prefix + Loc.t("Path damage"), {"damage": eff.path_damage}, nums, "") or deals
			for sub3 in eff.get("on_arrive", []):
				deals = _effect(out, sub3, nums, p, Loc.t("On impact: ")) or deals
		"knockback", "pull":
			out.append(_row(prefix + (Loc.t("Knockback") if str(eff.type) == "knockback" else Loc.t("Pull")), Loc.f("%s radius, %d force", [_m(float(eff.get("radius", 100)) * rmul), int(eff.get("force", 120))]), Kind.STATUS))
			_on_hit(out, eff, nums, prefix)
		"delayed":
			for sub4 in eff.get("effects", []):
				deals = _effect(out, sub4, nums, p, Loc.f("After %.1fs: ", [float(eff.delay)])) or deals
		"deploy":
			out.append(_row(prefix + Loc.t("Deploys"), Loc.f("for %.0fs, acts every %.1fs", [float(eff.get("duration", 10)), float(eff.get("tick", 1.0))])
				+ (Loc.f(", %s radius", [_m(float(eff.radius) * rmul)]) if eff.has("radius") else "")))
			if eff.has("heal"):
				out.append(_row(prefix + Loc.t("Healing"), Loc.f("%d every %.1fs%s", [_amount(eff.heal, nums, true), float(eff.get("tick", 1.0)),
					Loc.f(" (below %d%% health)", [roundi(float(eff.heal_below) * 100.0)]) if eff.has("heal_below") else ""]), Kind.HEAL))
			for sub5 in eff.get("tick_effects", []):
				deals = _effect(out, sub5, nums, p, Loc.t("Each shot: ")) or deals
		"consume_dots":
			out.append(_row(prefix + Loc.t("Detonates"), Loc.f("every %s on the target at once (x%.1f), %s", [_status_names(eff.get("statuses", ["burn"])),
				float(eff.get("mult", 1.0)), _m(float(eff.get("range", 220)))]), Kind.DAMAGE))
			deals = true
		"cleanse":
			out.append(_row(prefix + Loc.t("Cleanses"), "%s%s%s" % [_categories(eff),
				Loc.f(", refunds %d", [int(eff.refund)]) if eff.has("refund") else "", _target_text(eff)], Kind.HEAL))
		"dispel":
			out.append(_row(prefix + Loc.t("Dispels"), _categories(eff)
				+ (", %s" % _m(float(eff.range)) if eff.has("range") else ""), Kind.STATUS))
		"destroy_projectiles":
			out.append(_row(prefix + Loc.t("Destroys"), Loc.f("hostile projectiles within %s", [_m(float(eff.get("range", 120)))])))
		"terrain":
			out.append(_row(prefix + Loc.t("Terrain"), Loc.f("%s for %.0fs", [Loc.t(str(GameData.obstacles.get(str(eff.get("kind", "")), {}).get("name", eff.get("kind", "")))), float(eff.get("lifetime", 6))])))
		"threat_drop":
			out.append(_row(prefix + Loc.t("Threat"), Loc.f("drops %d%%", [roundi(float(eff.get("fraction", 1.0)) * 100.0)]), Kind.STATUS))
		"reveal":
			out.append(_row(prefix + Loc.t("Reveals"), Loc.f("stealth and darkness within %s for %.0fs", [_m(float(eff.get("radius", 250))), float(eff.get("duration", 6))])))
		"interrupt":
			out.append(_row(prefix + Loc.t("Interrupts"), Loc.f("spellcasting%s", [(Loc.f(", locks the school for %.0fs", [float(eff.lockout)]) if eff.has("lockout") else "")])
				+ (", %s" % _m(float(eff.range)) if eff.has("range") else ""), Kind.STATUS))
		"cooldown":
			out.append(_row(prefix + Loc.t("Cooldowns"), "%s %s" % [Loc.t("reduces") if eff.has("reduce") else Loc.t("resets"), ", ".join(Array(eff.get("skills", [])).map(func(x): return Loc.t(str(GameData.skills.get(x, {}).get("name", x)))))]))
		"self_damage":
			out.append(_row(prefix + Loc.t("Costs"), Loc.f("%d%% of your health", [roundi(float(eff.get("pct_current", eff.get("pct_max", 0.0))) * 100.0)]), Kind.DAMAGE))
		"tether":
			out.append(_row(prefix + Loc.t("Tether"), "%.0fs" % float(eff.get("duration", 6))))
			for sub6 in eff.get("tick_effects", []):
				deals = _effect(out, sub6, nums, p, Loc.f("Every %.1fs: ", [float(eff.get("tick", 1.0))])) or deals
		"fetch":
			out.append(_row(prefix + Loc.t("Pulls"), Loc.t("the ally to your feet") + (", %s" % _m(float(eff.range)) if eff.has("range") else "")))
		"teleport":
			out.append(_row(prefix + Loc.t("Teleport"), Loc.t(str(TELEPORT_TEXT.get(str(eff.get("to", "aim")), TELEPORT_TEXT.aim)))))
	if str(eff.type) in ["melee", "projectile", "aoe", "zone", "cone", "hit", "line", "chain", "beam"]:
		_on_hit(out, eff, nums, prefix)
	if str(eff.type) == "zone":
		if eff.has("status_inside"):
			_status(out, prefix + Loc.t("Inside: "), {"status": eff.status_inside, "duration": float(eff.get("tick", 1.0)) + 0.3}, nums, "")
		for sub7 in eff.get("tick_effects", []):
			deals = _effect(out, sub7, nums, p, Loc.f("Every %.1fs: ", [float(eff.get("tick", 1.0))])) or deals
		for sub9 in eff.get("on_end", []):
			deals = _effect(out, sub9, nums, p, Loc.t("When it ends: ")) or deals
	if str(eff.type) == "aoe" and eff.has("ally_effects"):
		for sub8 in eff.ally_effects:
			deals = _effect(out, sub8, nums, p, prefix + Loc.t("Allies: ")) or deals
	return deals


static func _categories(eff: Dictionary) -> String:
	return ", ".join(Array(eff.get("categories", [])).map(func(c): return Loc.t(str(CATEGORY_TEXT.get(str(c), c)))))


static func _status_names(ids: Variant) -> String:
	var arr: Array = ids if ids is Array else [ids]
	return ", ".join(arr.map(func(x): return Loc.t(str(GameData.status_effects.get(str(x), {}).get("name", x)))))


static func _on_hit(out: Array, eff: Dictionary, nums: Dictionary, prefix: String) -> void:
	for oh in eff.get("on_hit", []):
		match str(oh.type):
			"status":
				_status(out, prefix, oh, nums, "")
			"knockback":
				out.append(_row(prefix + Loc.t("Knockback"), Loc.f("%d force", [int(oh.force)]), Kind.STATUS))
			"aoe", "hit", "heal", "self_damage", "teleport":
				_effect(out, oh, nums, null, prefix + Loc.t("On hit: "))


## A status the skill applies: damage/healing per tick for DoTs/HoTs, otherwise its duration.
static func _status(out: Array, prefix: String, eff: Dictionary, nums: Dictionary, target: String) -> void:
	var def: Dictionary = GameData.status_effects.get(str(eff.status), {})
	var dur := float(eff.duration) * float(nums.duration_mult)
	if dur < 0.0:
		dur = 9999.0
	var name := Loc.t(str(def.get("name", eff.status)))
	match str(def.get("kind", "")):
		"dot":
			var tick := float(def.get("tick", 1.0))
			var per := roundi(Combat.value_of(eff.get("magnitude", {}), nums))
			out.append(_row(prefix + name, Loc.f("%d every %.1fs for %.1fs (%d total)", [per, tick, dur, per * int(dur / tick)]), Kind.DAMAGE))
		"hot":
			var tick2 := float(def.get("tick", 1.0))
			var per2 := roundi(Combat.value_of(eff.get("magnitude", {}), nums))
			out.append(_row(prefix + name, Loc.f("%d every %.1fs for %.1fs%s", [per2, tick2, dur, target]), Kind.HEAL))
		_:
			var when := Loc.t("while active") if dur >= 9999.0 else "%.1fs" % dur
			out.append(_row(prefix + name, "%s%s%s" % [when, _stat_text(def), target], Kind.STATUS))


static func _damage(out: Array, label: String, eff: Dictionary, nums: Dictionary, suffix: String) -> bool:
	if not eff.has("damage"):
		return false
	var v := Combat.value_of(eff.damage, nums)
	var extra := _extras(eff.damage)
	if not extra.is_empty():
		var lead := "%d + " % roundi(v) if roundi(v) > 0 else ""
		out.append(_row(label, lead + ", ".join(extra) + suffix, Kind.DAMAGE))
		return true
	var crit := v * (1.0 + float(nums.crit_damage))
	out.append(_row(label, Loc.f("%d (crit %d)%s", [maxi(1, roundi(v)), maxi(1, roundi(crit)), suffix]), Kind.DAMAGE))
	return true


## Healing and shields with the parts that don't come from power: "%d (40% of your max health)",
## "+17% of the target's max health", "100% of the overhealing, up to ..." (as CombatEffects adds them).
static func _amount_text(spec: Variant, nums: Dictionary, p: Player, heal: bool) -> String:
	var v := float(_amount(spec, nums, heal))
	if spec is Dictionary and spec.has("pct_caster_max_hp"):
		v += (float(p.health.max_hp) if p else 0.0) * float(spec.pct_caster_max_hp)
	if spec is Dictionary and spec.has("armor_coef") and p:
		v += p.stats.get_stat("armor") * float(spec.armor_coef)
	var extra := _extras(spec)
	if extra.is_empty():
		return "%d" % roundi(v)
	if roundi(v) <= 0:
		return ", ".join(extra)
	return "%d (%s)" % [roundi(v), ", ".join(extra)]


## What an amount adds besides base + power: health shares, armor, a share of the event.
static func _extras(spec: Variant) -> Array:
	var out: Array = []
	if not spec is Dictionary:
		return out
	if spec.has("pct_caster_max_hp"):
		out.append(Loc.f("%d%% of your max health", [roundi(float(spec.pct_caster_max_hp) * 100.0)]))
	if spec.has("armor_coef"):
		out.append(Loc.f("%d%% of your armor", [roundi(float(spec.armor_coef) * 100.0)]))
	if spec.has("pct_target_max_hp"):
		out.append(Loc.f("%d%% of the target's max health", [roundi(float(spec.pct_target_max_hp) * 100.0)]))
	if spec.has("event_pct"):
		var field := str(spec.get("event_field", "amount"))
		var what: String = {"amount": "%d%% of the hit or heal that triggered it", "overheal": "%d%% of the overhealing",
			"blocked_amount": "%d%% of the blocked damage"}.get(field, "%d%% of the triggering amount")
		out.append(Loc.f(what, [roundi(float(spec.event_pct) * 100.0)]))
	if spec.has("max_pct_target_max_hp"):
		out.append(Loc.f("up to %d%% of the target's max health", [roundi(float(spec.max_pct_target_max_hp) * 100.0)]))
	return out


## Healing and shields: same base + power x coef, times the heal multiplier (as Combat does).
static func _amount(spec: Variant, nums: Dictionary, heal: bool) -> int:
	return roundi(Combat.value_of(spec, nums) * (float(nums.heal_mult) if heal else 1.0))


static func _stat_text(def: Dictionary) -> String:
	var parts: Array = []
	for k in def.get("stats", {}):
		var v := float(def.stats[k])
		match str(k):
			"move_speed_mult":
				parts.append(Loc.f("%+d%% speed", [roundi((v - 1.0) * 100.0)]))
			"damage_mult":
				parts.append(Loc.f("%+d%% damage", [roundi((v - 1.0) * 100.0)]))
			"damage_taken_mult":
				parts.append(Loc.f("%+d%% damage taken", [roundi((v - 1.0) * 100.0)]))
			"haste":
				parts.append(Loc.f("%+d%% haste", [roundi(v * 100.0)]))
			"crit_chance":
				parts.append(Loc.f("%+d%% crit", [roundi(v * 100.0)]))
	for f in def.get("flags", []):
		parts.append(Loc.t(str(f).capitalize()))
	return "" if parts.is_empty() else ", " + ", ".join(parts)


static func _target_text(eff: Dictionary) -> String:
	match str(eff.get("target", "")):
		"party":
			return Loc.f(", party within %s", [_m(float(eff.get("radius", 200)))])
		"self":
			return Loc.t(", self")
		"aim_ally":
			return Loc.t(", ally at the cursor") + (", %s" % _m(float(eff.range)) if eff.has("range") else "")
	return ""


static func _scales(skill: Dictionary) -> bool:
	return JSON.stringify(skill.get("effects", [])).contains("\"coef\"")


static func _res_name(p: Player) -> String:
	return Loc.t(str(p.class_def.get("resource", "mana")).capitalize())


static func _m(px: float) -> String:
	return "%.1fm" % (px / TILE)


static func _row(k: String, v: String, kind: int = Kind.INFO) -> Dictionary:
	return {"k": k, "v": v, "kind": kind}
