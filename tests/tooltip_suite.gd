class_name TooltipSuite
extends RefCounted
## #43 exact talent and skill tooltips (scenario "tooltips", a solo hero): every node of the four
## talent trees produces rows that carry the numbers in its data (damage / healing, cooldown, cost,
## reach, durations; per-rank value, current and next totals; keystone triggers), never the flavour
## text alone and never an unformatted placeholder; the talent card shows those rows; hovering a
## skill on the bar opens the same numeric card as the Skill Book.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func _has(o: Variant, key: String) -> bool:
	if o is Dictionary:
		if o.has(key):
			return true
		for v in o.values():
			if _has(v, key):
				return true
	elif o is Array:
		for v in o:
			if _has(v, key):
				return true
	return false


static func _text(rows: Array) -> String:
	return "\n".join(rows.map(func(r): return "%s: %s" % [r.k, r.v]))


## What is missing from the rows of `node` (empty when all its numbers are there).
func _missing(node: Dictionary, rows: Array) -> Array:
	var out: Array = []
	var all := _text(rows)
	var digits := RegEx.create_from_string("\\d")
	if rows.is_empty():
		return ["no rows"]
	if all.contains("%d") or all.contains("%s") or all.contains("%.") or all.contains("{"):
		out.append("placeholder")
	if not digits.search(all):
		out.append("no number")
	if str(node.get("type", "")) == "skill":
		var sk: Dictionary = GameData.skills.get(str(node.skill), {})
		if not sk.get("passive", false) and not all.contains(Loc.t("Cooldown")):
			out.append("cooldown")
		if float(sk.get("cost", 0)) > 0.0 and not all.contains(Loc.t("Cost")):
			out.append("cost")
		var effs: Array = sk.get("effects", [])
		if _has(effs, "damage") and not rows.any(func(r): return int(r.kind) == SkillInfo.Kind.DAMAGE and digits.search(str(r.v))):
			out.append("damage")
		var heals := _has(effs, "heal") or JSON.stringify(effs).contains("\"type\":\"heal\"") or JSON.stringify(effs).contains("\"type\":\"absorb\"")
		var zero := RegEx.create_from_string("(^| )0( |$|,)")
		if rows.any(func(r): return int(r.kind) == SkillInfo.Kind.HEAL and zero.search(str(r.v)) != null):
			out.append("zero healing / shield")
		if heals and not rows.any(func(r): return int(r.kind) == SkillInfo.Kind.HEAL and digits.search(str(r.v))):
			out.append("healing")
		if (_has(effs, "range") or _has(effs, "radius") or _has(effs, "length") or _has(effs, "distance")) and not RegEx.create_from_string("\\d+\\.\\dm").search(all):
			out.append("reach")
		if _has(effs, "duration") and not RegEx.create_from_string("\\d(\\.\\d+)?s").search(all):
			out.append("duration")
		return out
	var rank_txt := []
	for m in node.get("mods", []):
		var label := TalentInfo._skills_text(m.skill) if m.has("skill") else TalentInfo._stat_label(p, str(m.stat))
		var v := TalentInfo._field_text(str(m.field), float(m.value)) if m.has("skill") else TalentInfo._stat_value(p, str(m.stat), float(m.value))
		if not rows.any(func(r): return str(r.k) == label and str(r.v).contains(v)):
			out.append("mod %s %s" % [label, v])
		rank_txt.append(v)
	var zero2 := RegEx.create_from_string("(^| )0( |$|,)")
	if rows.any(func(r): return int(r.kind) in [SkillInfo.Kind.HEAL, SkillInfo.Kind.DAMAGE] and zero2.search(str(r.v)) != null):
		out.append("zero amount")
	for pr in node.get("procs", []):
		if not all.contains(Loc.t("Trigger")):
			out.append("trigger")
		if pr.has("icd") and not all.contains("%.1f" % float(pr.icd)):
			out.append("trigger cooldown")
		if _has(pr.get("do", []), "damage") and not rows.any(func(r): return int(r.kind) == SkillInfo.Kind.DAMAGE):
			out.append("trigger damage")
	return out


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var bad: Array = []
	var count := 0
	for cid in GameData.talents:
		for node in GameData.talents[cid].get("nodes", []):
			count += 1
			var miss := _missing(node, TalentInfo.rows(p, node))
			if not miss.is_empty():
				bad.append("%s: %s" % [node.id, miss])
	for b in bad:
		da.log_line("SHORT " + b)
	da.check(count > 250 and bad.is_empty(), "all %d talent nodes of the four classes state their numbers (%d short: %s)" % [count, bad.size(), bad.slice(0, 6)])
	# Ranks: per rank, now and next for a ranked passive the hero has partly learned.
	var ranked: Dictionary = {}
	for node in p.talent_tree().nodes:
		if str(node.get("type", "")) == "passive" and int(node.get("max_rank", 1)) >= 3 and not node.get("mods", []).is_empty() and not node.mods[0].has("skill"):
			ranked = node
			break
	var keep := p.talents.duplicate()
	var t2 := keep.duplicate()
	t2[ranked.id] = 1
	p.talents = t2
	var r0: Dictionary = TalentInfo.rows(p, ranked)[0]
	var per := float(ranked.mods[0].value)
	var want_now := TalentInfo._stat_value(p, str(ranked.mods[0].stat), per)
	var want_next := TalentInfo._stat_value(p, str(ranked.mods[0].stat), per * 2.0)
	da.check(str(r0.v).contains(want_now) and str(r0.v).contains(want_next) and str(r0.v) == Loc.f("%s per rank - now %s, next %s", [want_now, want_now, want_next]),
			"a ranked passive at rank 1 shows the value per rank, now and next (%s: %s)" % [r0.k, r0.v])
	p.talents = keep
	# The talent card shows the rows.
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.menu_panel("talents"))
	await da._wait(0.6)
	var panel: Node = hud._overlay
	var skill_node: Dictionary = {}
	for node in p.talent_tree().nodes:
		if str(node.get("type", "")) == "skill" and _has(GameData.skills.get(str(node.skill), {}).get("effects", []), "damage"):
			skill_node = node
			break
	panel._show(skill_node)
	await da._wait(0.2)
	var shown: Array = []
	for c in panel._card.get_children():
		for l in c.find_children("*", "Label", true, false) + ([c] if c is Label else []):
			shown.append(str(l.text))
	var cd_row := Loc.t("Cooldown")
	da.check(shown.has(cd_row) and shown.any(func(t): return t.ends_with("s") and RegEx.create_from_string("^\\d+\\.\\ds$").search(t) != null),
			"the talent card lists the skill's numbers (%s)" % [shown.slice(0, 8)])
	hud.close_overlay()
	await da._wait(0.3)
	# Hovering a bar slot opens the numeric card.
	var slot: Node = hud._slots[1] if p.skills.size() > 1 and not str(p.skills[1]).is_empty() else hud._slots[0]
	var idx: int = hud._slots.find(slot)
	slot.mouse_entered.emit()
	await da._wait(0.3)
	var tip: SkillTooltip = hud._slot_tip
	da.check(tip.visible and tip.skill_id == str(p.skills[idx]) and tip._grid.get_child_count() >= 4,
			"hovering skill slot %d shows its numeric card (%s, %d cells)" % [idx, tip.skill_id, tip._grid.get_child_count()])
	slot.mouse_exited.emit()
	await da._wait(0.2)
	da.check(not tip.visible, "leaving the slot hides the card")
