class_name TalentInfo
## Tooltip rows for a talent node (#43), generated from the node's data so they never drift from
## what it really does: skill nodes show the skill's numbers for this hero (SkillInfo); passive
## and keystone ranks show the value per rank, the current total and the next rank's total, and
## which stat or skill they change; keystone triggers show when they fire and what they do, with
## the same effect rows as skills. Rows are {"k", "v", "kind"} like SkillInfo.rows.

const Kind := SkillInfo.Kind

## Stats a talent changes, by name. Values are fractions shown as percentages unless in FLAT.
const STAT_TEXT := {
	"agility_pct": "Agility", "intellect_pct": "Intellect", "stamina_pct": "Stamina", "strength_pct": "Strength",
	"armor_pct": "Armor", "armor_pen": "Armor penetration", "armor_vs_magic": "Armor against magic and elements",
	"block_chance": "Block chance", "block_value": "Block value", "boss_damage_pct": "Damage to bosses",
	"cc_bonus": "Stuns and knockdowns you cause", "cc_duration_pct": "Control effects on you",
	"cooldown_pct": "All cooldowns", "crit_chance": "Critical chance", "crit_damage": "Critical damage",
	"damage_taken_pct": "Damage taken", "dodge": "Dodge chance", "haste": "Haste",
	"distance_bonus_per_50": "Projectile damage per 50 px to the target", "distance_bonus_max": "Distance bonus up to",
	"fire_damage_pct": "Fire damage", "frost_damage_pct": "Frost damage", "lightning_damage_pct": "Lightning damage",
	"earth_damage_pct": "Earth damage", "holy_damage_pct": "Holy damage", "shadow_damage_pct": "Shadow damage",
	"nature_damage_pct": "Nature damage", "physical_damage_pct": "Physical damage", "spell_damage_pct": "Spell damage",
	"melee_damage_pct": "Melee damage", "ranged_damage_pct": "Ranged damage",
	"healing_mult": "Healing done", "healing_taken_pct": "Healing received",
	"leech": "Leech", "leech_efficiency_pct": "Leech healing", "magic_pen": "Magic penetration",
	"magic_resist": "Magic resistance", "max_hp_pct": "Max health", "max_resource_pct": "Max %s",
	"max_traps": "Traps armed at once", "move_speed_pct": "Movement speed", "range_pct": "Range",
	"ranged_damage_taken_pct": "Ranged damage taken", "spell_damage_taken_pct": "Spell damage taken",
	"resource_gen_pct": "%s generation", "resource_regen_pct": "%s regeneration",
	"threat_mult": "Threat generated", "trap_radius_pct": "Trap radius",
}
const FLAT := ["block_value"]
const SECONDS := ["cc_bonus"]

const EVENT_TEXT := {
	"on_hit": "When you hit", "on_crit": "When you land a critical hit", "on_kill": "When you kill",
	"on_skill_cast": "When you cast a skill", "on_heal": "When you heal", "on_block": "When you block",
	"on_dodge": "When you dodge", "on_fatal": "When a blow would kill you", "on_low_hp": "When your health runs low",
	"on_status_applied": "When you apply an effect", "aura_tick": "Every second", "on_floor_start": "At the start of a floor",
}


static func rows(p: Player, node: Dictionary) -> Array:
	var out: Array = []
	if str(node.get("type", "")) == "skill":
		var sk: Dictionary = GameData.skills.get(str(node.get("skill", "")), {})
		return SkillInfo.rows(p, sk) if not sk.is_empty() else out
	var rank := p.node_rank(node)
	var max_rank := int(node.get("max_rank", 1))
	for m in node.get("mods", []):
		if m.has("skill"):
			out.append(_row(_skills_text(m.skill), _ranked(float(m.value), rank, max_rank, func(v: float): return _field_text(str(m.field), v)), Kind.TALENT))
		else:
			out.append(_row(_stat_label(p, str(m.stat)), _ranked(float(m.value), rank, max_rank, func(v: float): return _stat_value(p, str(m.stat), v)), Kind.TALENT))
	var nums := Combat.skill_numbers(p.stats, p.level, GameData.skill(str(p.skills[0])) if not p.skills.is_empty() else {})
	for pr in node.get("procs", []):
		out.append(_row(Loc.t("Trigger"), _trigger_text(pr), Kind.STATUS))
		if pr.has("hook"):
			out.append(_row(Loc.t("Effect"), Loc.t(str(node.get("description", ""))), Kind.STATUS))
		for eff in pr.get("do", []):
			SkillInfo._effect(out, eff, nums, p, "")
	if out.is_empty():
		out.append(_row(Loc.t("Effect"), Loc.t(str(node.get("description", ""))), Kind.STATUS))
	return out


## "+12% per rank - now +24%, next +36%"; a single-rank node shows just its value.
static func _ranked(per: float, rank: int, max_rank: int, fmt: Callable) -> String:
	if max_rank <= 1:
		return str(fmt.call(per))
	if rank <= 0:
		return Loc.f("%s per rank (%d ranks)", [fmt.call(per), max_rank])
	if rank >= max_rank:
		return Loc.f("%s per rank - now %s (max)", [fmt.call(per), fmt.call(per * rank)])
	return Loc.f("%s per rank - now %s, next %s", [fmt.call(per), fmt.call(per * rank), fmt.call(per * (rank + 1))])


static func _stat_label(p: Player, stat: String) -> String:
	var t := str(STAT_TEXT.get(stat, stat.replace("_", " ").capitalize()))
	if t.contains("%s"):
		return Loc.f(t, [SkillInfo._res_name(p)])
	return Loc.t(t)


static func _stat_value(_p: Player, stat: String, v: float) -> String:
	if stat in FLAT:
		return "%+d" % roundi(v)
	if stat in SECONDS:
		return Loc.f("%+.1f s", [v])
	if stat == "max_traps":
		var base := int(GameData.bal("combat.max_traps", 3))
		return Loc.f("%d -> %d", [base, int(base * (1.0 + v))])
	return "%+d%%" % roundi(v * 100.0)


static func _field_text(field: String, v: float) -> String:
	match field:
		"count_add":
			return Loc.f("%+d projectiles", [roundi(v)])
		"pierce_add":
			return Loc.f("%+d pierce", [roundi(v)])
	return Loc.f(str(SkillInfo.MOD_TEXT.get(field, "%+d%% " + field)), [roundi(v * 100.0)])


static func _skills_text(spec: Variant) -> String:
	var ids: Array = spec if spec is Array else [spec]
	if ids.has("*"):
		return Loc.t("All skills")
	return ", ".join(ids.map(func(x): return Loc.t(str(GameData.skills.get(str(x), {}).get("name", x)))))


## When a keystone fires: the event, its conditions and its internal cooldown.
static func _trigger_text(pr: Dictionary) -> String:
	var parts: Array = [Loc.t(str(EVENT_TEXT.get(str(pr.get("event", "")), str(pr.get("event", "")).replace("_", " "))))]
	var c: Dictionary = pr.get("if", {})
	for k in c:
		var v: Variant = c[k]
		match str(k):
			"damage_type":
				parts.append(Loc.f("with %s damage", [_names(v, func(x): return Loc.t(str(x).capitalize()))]))
			"element":
				parts.append(Loc.f("with a %s spell", [_names(v, func(x): return Loc.t(str(x).capitalize()))]))
			"school":
				parts.append(Loc.f("with a %s attack", [Loc.t(str(v).capitalize())]))
			"target_status":
				parts.append(Loc.f("a target with %s", [SkillInfo._status_names(v)]))
			"status":
				parts.append(Loc.f("applying %s", [SkillInfo._status_names(v)]))
			"self_status":
				parts.append(Loc.f("while you have %s", [SkillInfo._status_names(v)]))
			"self_stacks_at_least":
				parts.append(Loc.f("at %d+ stacks of %s", [int(v[1]), SkillInfo._status_names(v[0])]))
			"skill":
				parts.append(Loc.f("with %s", [_skills_text(v)]))
			"dot":
				parts.append(Loc.t("damage over time only") if v else Loc.t("direct hits only"))
			"hot":
				if not v:
					parts.append(Loc.t("direct heals only"))
			"in_combat":
				if v:
					parts.append(Loc.t("in combat"))
	var text := ", ".join(parts)
	if pr.has("icd"):
		text += Loc.f(" (at most every %.1f s)", [float(pr.icd)])
	if pr.has("chance"):
		text += Loc.f(" (%d%% chance)", [roundi(float(pr.chance) * 100.0)])
	return text


static func _names(v: Variant, f: Callable) -> String:
	var arr: Array = v if v is Array else [v]
	return " / ".join(arr.map(f))


static func _row(k: String, v: String, kind: int = Kind.INFO) -> Dictionary:
	return {"k": k, "v": v, "kind": kind}
