class_name StatusEffects
extends Node
## Buffs, debuffs, damage/heal over time, crowd control, marks, reactive and transform effects
## (data/status_effects.json, see docs/DATA.md). Host-only simulation; `shown` (id, seconds left,
## stacks) is replicated for the HUD, flags and tinting.
##
## - CC (any status with a CC flag) is blocked by `cc_immune` and, on players, shortened by
##   diminishing returns per `dr_category` (balance.status).
## - `breaks_on_damage` statuses end when the actor takes damage (sleep, shackle, disorient).
## - `on_expire` effects run when a status runs out (Living Bomb, Death Brand); `record_damage`
##   keeps the damage taken while it is up (Gore Arrow) for its `stored_damage` effect.
## - `tick_effects` run every `tick` while it is up (auras, the Liquid Magma Flask).
## - `charges` + a field (e.g. absorb_melee) are spent by Combat (Granite Armor).

signal effects_changed

var effects: Array = []  ## host: [{id, def, remaining, tick_left, magnitude, stacks, source, src_node, charges, recorded}]
var shown: Array = []:  ## replicated: [[id, remaining, stacks], ...] (remaining -1 = until removed)
	set(v):
		shown = v
		effects_changed.emit()

var _show_timer := 0.0
var _dr: Dictionary = {}  ## host, players: dr category -> {count, left}


func _actor() -> Node:
	return get_parent()


static func is_cc(def: Dictionary) -> bool:
	if def.get("kind", "") == "cc":
		return true
	for f in def.get("flags", []):
		if CombatCore.CC_FLAGS.has(f):
			return true
	return false


## Returns false when the actor is immune (CC immunity, diminishing returns ran out).
## duration < 0 = until removed (toggles, auras).
func apply(id: String, duration: float, magnitude: float, source: Variant) -> bool:
	var def: Dictionary = GameData.status_effects.get(id, {})
	if def.is_empty():
		push_error("StatusEffects: unknown status '%s'" % id)
		return false
	var actor := _actor()
	# Wyvernscale Jerkin: no poison takes hold.
	if id == "poison" and actor.stats and actor.stats.has_flag("poison_immune"):
		return false
	var src_actor: Variant = source.get("caster") if source is Dictionary else null
	if is_instance_valid(src_actor) and src_actor is Actor:
		# Grip of Absolute Zero: freezes last a second longer.
		if (id == "freeze" or id == "frozen") and src_actor.stats.has_flag("deep_frost"):
			duration += 1.0
	# Whirlwind and friends: immune to slows and roots while it lasts.
	if def.get("debuff", false) and str(def.get("cleanse", "")) == "movement" and has_flag("movement_immune"):
		return false
	if is_cc(def) and def.get("debuff", false):
		if has_flag("cc_immune") or (actor.stats and actor.stats.has_flag("cc_immune")):
			return false
		if actor.get("team") == Actor.Team.PLAYERS and def.has("dr_category"):
			duration *= _dr_factor(str(def.dr_category))
			if duration <= 0.05:
				return false
		if actor.stats:
			duration *= actor.stats.mult("cc_duration")
		if duration > 0.0 and source is Dictionary:
			duration += float(source.get("cc_bonus", 0.0)) if def.has("dr_category") and str(def.dr_category) in ["stun", "knockdown"] else 0.0
	var permanent := duration < 0.0
	if actor.has_meta("test_seen_status"):
		actor.get_meta("test_seen_status").append(id)
	for e in effects:
		if e.id == id:
			if not permanent:
				e.remaining = maxf(e.remaining, duration) if not def.get("stack_refresh_only", false) else duration
			e.stacks = mini(e.stacks + 1, max_stacks(def))
			e.magnitude = maxf(e.magnitude, magnitude)
			e.source = source
			if def.has("charges"):
				e.charges = int(def.charges)
			_check_threshold(e)
			_publish()
			actor.on_stats_dirty()
			return true
	var src_node: Variant = source.get("caster") if source is Dictionary else null
	effects.append({"id": id, "def": def, "remaining": INF if permanent else duration, "tick_left": float(def.get("tick", 1.0)),
		"magnitude": magnitude, "stacks": int(def.get("start_stacks", 1)), "source": source, "src_node": src_node,
		"charges": int(def.get("charges", 0)), "recorded": 0.0})
	effects[-1].tick_left = tick_of(effects[-1])  # #111: a faster Renew ticks faster from its first tick
	_check_threshold(effects[-1])
	_publish()
	actor.on_stats_dirty()
	if def.has("on_apply") and Combat.instance and source is Dictionary:
		Combat.instance.status_callback(actor, effects[-1] if not effects.is_empty() else {}, "on_apply")
	return true


func max_stacks(def: Dictionary) -> int:
	var n := int(def.get("max_stacks", 1))
	# Blessed Touch Gloves: Renew stacks up to 3 times from a priest wearing them.
	if def == GameData.status_effects.get("renew", {}):
		for e0 in effects:
			if e0.def == def and is_instance_valid(e0.src_node) and e0.src_node is Actor and e0.src_node.stats.has_flag("renew_mastery"):
				return 3
	var actor := _actor()
	if def.has("stack_bonus_flag"):
		# e.g. Venomtouch Grips: poisons stack to 6 when the poisoner has the flag.
		for e in effects:
			if e.def == def and is_instance_valid(e.src_node) and e.src_node is Actor and e.src_node.stats.has_flag(str(def.stack_bonus_flag)):
				return int(def.get("bonus_max_stacks", n))
	return n if actor else n


## Seconds between the ticks of `e`; #111: a Renew from a priest with Blessed Touch Gloves ticks
## 25% faster.
func tick_of(e: Dictionary) -> float:
	var t := float(e.def.get("tick", 1.0))
	if e.def == GameData.status_effects.get("renew", {}) and is_instance_valid(e.get("src_node")) and e.src_node is Actor and e.src_node.stats.has_flag("renew_mastery"):
		t *= 0.75
	return t


## Chill x5 -> freeze, King's Curse x5 -> explode.
func _check_threshold(e: Dictionary) -> void:
	var th: Dictionary = e.def.get("threshold", {})
	if th.is_empty() or e.stacks < int(th.get("stacks", 99)):
		return
	var actor := _actor()
	remove(e.id)
	if th.has("apply"):
		apply(str(th.apply), float(th.get("duration", 2.0)), 0.0, e.source)
	if th.has("effects") and Combat.instance and e.source is Dictionary:
		var ctx: Dictionary = e.source.duplicate()
		ctx.event_target = actor
		for eff in th.effects:
			Combat.instance.run_effect(eff, ctx, actor.global_position, actor.global_position)


func _dr_factor(category: String) -> float:
	var factors: Array = GameData.bal("status.dr_factors", [1.0, 0.5, 0.25, 0.0])
	var entry: Dictionary = _dr.get(category, {"count": 0, "left": 0.0})
	var f := float(factors[mini(int(entry.count), factors.size() - 1)])
	entry.count = int(entry.count) + 1
	entry.left = float(GameData.bal("status.dr_reset", 15.0))
	_dr[category] = entry
	return f


func remove(id: String) -> void:
	var gone: Array = []
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].id == id:
			gone.append(effects[i])
			effects.remove_at(i)
	if not gone.is_empty():
		_publish()
		_actor().on_stats_dirty()
		for e in gone:
			if e.def.has("on_end") and Combat.instance:
				Combat.instance.status_callback(_actor(), e, "on_end")


func remove_flag(flag: String) -> void:
	for e in effects.duplicate():
		if Array(e.def.get("flags", [])).has(flag):
			remove(e.id)


## Spends one use of a flag status (Riposte's parry window). Returns true if there was one.
func consume_flag(flag: String) -> bool:
	for e in effects:
		if Array(e.def.get("flags", [])).has(flag):
			remove(e.id)
			return true
	return false


## Spends one charge of a status that has `field` (e.g. absorb_melee). Returns true if spent.
func consume_charge(field: String) -> bool:
	for e in effects:
		if e.def.get(field, false) and int(e.charges) > 0:
			e.charges -= 1
			if e.charges <= 0:
				remove(e.id)
			return true
	return false


func clear_all() -> void:
	effects.clear()
	_publish()
	_actor().on_stats_dirty()


## Removes up to `count` statuses per category (poison, curse, disease, magic, bleed, enrage,
## movement, any). debuffs_only: cleanse (allies) vs dispel (enemy buffs). Returns how many.
func cleanse(categories: Array, count: int, debuffs_only: bool) -> int:
	var removed := 0
	var per := {}
	for e in effects.duplicate():
		var cat := str(e.def.get("cleanse", ""))
		if cat.is_empty() or bool(e.def.get("debuff", false)) != debuffs_only:
			continue
		if not (categories.has(cat) or categories.has("any")):
			continue
		if int(per.get(cat, 0)) >= count:
			continue
		per[cat] = int(per.get(cat, 0)) + 1
		remove(e.id)
		removed += 1
	return removed


## Host: the actor took damage.
func on_damage(amount: float, _dot: bool) -> void:
	var broke := false
	for e in effects.duplicate():
		if e.def.get("record_damage", false):
			e.recorded += amount
		if e.def.get("breaks_on_damage", false) and float(e.def.get("tick", 0.0)) >= 0.0:
			# A status applied this very frame isn't broken by the hit that applied it.
			if e.get("age", 1.0) > 0.05:
				remove(e.id)
				broke = true
	if broke:
		_publish()


## Total damage left on DoTs with these ids, removing them (Combustion).
func consume_dot_damage(ids: Array) -> float:
	var total := 0.0
	for e in effects.duplicate():
		if ids.has(e.id) and e.def.get("kind") == "dot":
			var ticks := ceilf(maxf(e.remaining, 0.0) / float(e.def.get("tick", 1.0)))
			total += float(e.magnitude) * int(e.stacks) * ticks
			remove(e.id)
	return total


func has_flag(flag: String) -> bool:
	if not is_inside_tree():
		return false  # the session is closing (visibility can still ask in its last frame)
	if multiplayer.is_server():
		for e in effects:
			if Array(e.def.get("flags", [])).has(flag):
				return true
		return false
	for s in shown:
		if Array(GameData.status_effects.get(s[0], {}).get("flags", [])).has(flag):
			return true
	return false


func has_any_flag(flags: Array) -> bool:
	for f in flags:
		if has_flag(f):
			return true
	return false


func has(id: String) -> bool:
	if multiplayer.is_server():
		for e in effects:
			if e.id == id:
				return true
		return false
	for s in shown:
		if s[0] == id:
			return true
	return false


func has_any(ids: Array) -> bool:
	for id in ids:
		if has(str(id)):
			return true
	return false


func stacks_of(id: String) -> int:
	for e in effects:
		if e.id == id:
			return int(e.stacks)
	for s in shown:
		if s[0] == id:
			return int(s[2])
	return 0


## The def value of the first active status that has `field` (a dictionary), or {}.
func find_field(field: String) -> Dictionary:
	for e in effects:
		var v: Variant = e.def.get(field)
		if v is Dictionary:
			return v
	return {}


## The first active entry whose def has `field`, or {}.
func find_entry_with(field: String) -> Dictionary:
	for e in effects:
		if e.def.has(field):
			return e
	return {}


## Aggregated stat modifiers ({key: value}, `_mult` multiply) plus "flags" from every status.
func stat_mods() -> Dictionary:
	var out := {}
	var flags := []
	for e in effects:
		_merge(out, e.def.get("stats", {}), 1.0)
		if e.def.has("stack_stats"):
			_merge(out, e.def.stack_stats, float(e.stacks))
		if e.def.has("scaled_stats"):
			# Pact potions: level-30 numbers scaled by the drinker's level (the magnitude).
			for k in e.def.scaled_stats:
				out[k] = float(out.get(k, 0.0)) + float(e.def.scaled_stats[k]) * float(e.magnitude)
		for f in e.def.get("stat_flags", []):
			flags.append(f)
	if not flags.is_empty():
		out.flags = flags
	return out


static func _merge(out: Dictionary, st: Dictionary, times: float) -> void:
	for k in st:
		if str(k).ends_with("_mult"):
			out[k] = float(out.get(k, 1.0)) * pow(float(st[k]), times)
		else:
			out[k] = float(out.get(k, 0.0)) + float(st[k]) * times


## Procs granted by active statuses (Ice Barrier chilling attackers, Static Charge, ...).
func procs() -> Array:
	var out: Array = []
	for e in effects:
		for i in e.def.get("procs", []).size():
			var pr: Dictionary = e.def.procs[i].duplicate()
			pr._key = "st:%s:%d" % [e.id, i]
			pr.source = e.id
			if e.def.get("debuff", false) and e.source is Dictionary:
				pr._src_ctx = e.source
			out.append(pr)
	return out


## Visual modifiers (scale, tint, alpha) from statuses, readable on every peer.
func visual() -> Dictionary:
	var out := {"scale": 1.0, "tint": Color.WHITE, "alpha": 1.0, "lift": 0.0}
	for s in shown:
		var def: Dictionary = GameData.status_effects.get(s[0], {})
		var v: Dictionary = def.get("visual", {})
		out.scale *= float(v.get("scale", 1.0))
		out.lift = maxf(out.lift, float(v.get("lift", 0.0)))
		out.alpha = minf(out.alpha, float(v.get("alpha", 1.0)))
		if v.has("tint"):
			out.tint = out.tint.lerp(Color.from_string(str(v.tint), Color.WHITE), 0.5)
	return out


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for k in _dr.keys():
		_dr[k].left -= delta
		if _dr[k].left <= 0.0:
			_dr.erase(k)
	if effects.is_empty():
		return
	var actor := _actor()
	var expired: Array = []
	for i in range(effects.size() - 1, -1, -1):
		if i >= effects.size():
			continue
		var e: Dictionary = effects[i]
		e.remaining -= delta
		e.age = float(e.get("age", 0.0)) + delta
		var kind: String = e.def.get("kind", "stat")
		if kind == "dot" or kind == "hot" or e.def.has("tick_effects"):
			e.tick_left -= delta
			if e.tick_left <= 0.0:
				e.tick_left += tick_of(e)
				if Combat.instance and is_instance_valid(actor):
					Combat.instance.status_tick(actor, e)
		if e.remaining <= 0.0:
			effects.remove_at(i)
			expired.append(e)
	_show_timer -= delta
	if not expired.is_empty() or _show_timer <= 0.0:
		_publish()
	if not expired.is_empty() and is_instance_valid(actor):
		actor.on_stats_dirty()
		for e in expired:
			if Combat.instance:
				if e.def.has("on_expire"):
					Combat.instance.status_callback(actor, e, "on_expire")
				if e.def.has("on_end"):
					Combat.instance.status_callback(actor, e, "on_end")


func _publish() -> void:
	_show_timer = 0.5
	var out: Array = []
	for e in effects:
		out.append([e.id, -1.0 if e.remaining == INF else snappedf(maxf(e.remaining, 0.0), 0.1), e.stacks])
	shown = out
