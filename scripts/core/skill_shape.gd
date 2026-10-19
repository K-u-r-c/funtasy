class_name SkillShape
extends RefCounted
## The footprint of a skill, read from its effects: how far it reaches and what it covers. The
## aim preview (#42) draws the shape. Defaults match the ones
## CombatEffects uses when a field is missing.
##
## Keys: kind ("projectile", "melee", "cone", "target", "chain", "line", "area", "self_area",
## "dash", "ally", "self"), range (px from the caster to the farthest aim point), radius (the area
## at the end of the reach, or around the caster), width, arc (degrees), count / spread
## (projectiles), lob (a mortar that flies over walls), back (a leap away from the aim) and aims
## (the aim point matters).

const AIMED := ["projectile", "melee", "cone", "target", "chain", "line", "area", "dash", "ally"]


## `nums` from Combat.skill_numbers (range and radius multipliers); {} for the raw data.
static func of(skill: Dictionary, nums: Dictionary = {}) -> Dictionary:
	var rm := float(nums.get("range_mult", 1.0))
	var radm := float(nums.get("radius_mult", 1.0))
	var out := {"kind": "self", "range": 0.0, "radius": 0.0, "width": 0.0, "arc": 0.0, "count": 1, "spread": 0.0,
		"lob": false, "back": false}
	for eff in skill.get("effects", []):
		var s := _shape_of(eff, rm, radm)
		if not s.is_empty():
			out.merge(s, true)
			break
	out.aims = out.kind in AIMED
	return out


static func _shape_of(eff: Dictionary, rm: float, radm: float) -> Dictionary:
	var target := str(eff.get("target", ""))
	if target == "aim_ally":
		return {"kind": "ally", "range": float(eff.get("range", eff.get("max_range", 300))) * rm}
	match str(eff.get("type", "")):
		"projectile":
			var ex: Dictionary = eff.get("explode", {})
			return {"kind": "projectile", "range": float(eff.get("range", 300)) * rm, "width": float(eff.get("radius", 6)) * 2.0,
				"radius": float(ex.get("radius", 0)) * radm, "count": int(eff.get("count", 1)), "spread": float(eff.get("spread", 0.0)),
				"lob": bool(eff.get("arc", false))}
		"melee", "cone":
			return {"kind": str(eff.type), "range": float(eff.get("range", 40)) * radm, "arc": float(eff.get("arc", 90))}
		"hit", "dispel", "interrupt", "consume_dots", "fetch":
			return {"kind": "target", "range": float(eff.get("range", 300)) * rm}
		"chain":
			return {"kind": "chain", "range": float(eff.get("range", 250)) * rm, "radius": float(eff.get("jump_range", 0))}
		"line":
			return {"kind": "line", "range": float(eff.get("length", 70)) * rm, "width": float(eff.get("width", 16))}
		"beam":
			return {"kind": "line", "range": float(eff.get("length", 250)) * rm, "width": float(eff.get("width", 14))}
		"aoe":
			if str(eff.get("at", "self")) == "aim":
				return {"kind": "area", "range": float(eff.get("max_range", 300)), "radius": float(eff.get("radius", 60)) * radm}
			return {"kind": "self_area", "radius": float(eff.get("radius", 60)) * radm}
		"zone", "deploy", "trap":
			var at := str(eff.get("at", "self" if eff.type == "zone" else "aim"))
			var r := float(eff.get("trigger_radius" if eff.type == "trap" else "radius", 40)) * (1.0 if eff.type == "trap" else radm)
			if at == "aim":
				return {"kind": "area", "range": float(eff.get("max_range", 220)), "radius": r}
			return {"kind": "self_area", "radius": r}
		"push", "pull", "reveal", "terrain":
			var defaults := {"push": [220.0, 100.0], "pull": [220.0, 100.0], "reveal": [260.0, 250.0], "terrain": [200.0, 80.0]}
			var d: Array = defaults[str(eff.type)]
			var at2 := str(eff.get("at", "aim" if eff.type == "terrain" else "self"))
			if at2 == "aim":
				return {"kind": "area", "range": float(eff.get("max_range", d[0])), "radius": float(eff.get("radius", d[1])) * radm}
			return {"kind": "self_area", "radius": float(eff.get("radius", d[1])) * radm}
		"delayed":
			var inner: Dictionary = {}
			for sub in eff.get("effects", []):
				inner = _shape_of(sub, rm, radm)
				if not inner.is_empty():
					break
			var tr: Dictionary = eff.get("telegraph", {})
			return {"kind": "area", "range": float(eff.get("max_range", 300)),
				"radius": float(tr.get("radius", inner.get("radius", 40)))}
		"leap":
			var back := str(eff.get("direction", "aim")) == "back"
			return {"kind": "dash", "range": float(eff.get("distance", 140 if back else 200)), "width": 18.0, "back": back}
		"charge":
			return {"kind": "dash", "range": float(eff.get("distance", 240)), "width": float(eff.get("width", 18))}
		"dash", "blink":
			return {"kind": "dash", "range": float(eff.get("distance", 160)), "width": 18.0}
		"taunt", "threat_drop":
			return {"kind": "self_area", "radius": float(eff.get("radius", 120)) * radm}
		"status", "heal", "absorb", "cleanse":
			if target == "aim_enemy":
				return {"kind": "target", "range": float(eff.get("range", 300)) * rm}
			if eff.has("radius") and target in ["", "party", "allies", "enemies"]:
				return {"kind": "self_area", "radius": float(eff.radius) * radm}
	if target in ["aim_enemy", "aim_any"]:
		return {"kind": "target", "range": float(eff.get("range", 300)) * rm}
	return {}
