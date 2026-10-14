class_name StatusEffects
extends Node
## Buffs, debuffs, damage/heal over time and crowd control (data/status_effects.json).
## Host-only simulation; `shown` (id, seconds left, stacks) is replicated for HUD and tinting.

signal effects_changed

var effects: Array = []  ## host: [{id, def, remaining, tick_left, magnitude, stacks, source}]
var shown: Array = []:  ## replicated: [[id, remaining, stacks], ...]
	set(v):
		shown = v
		effects_changed.emit()

var _show_timer := 0.0


func apply(id: String, duration: float, magnitude: float, source: Variant) -> void:
	var def: Dictionary = GameData.status_effects.get(id, {})
	if def.is_empty():
		push_error("StatusEffects: unknown status '%s'" % id)
		return
	for e in effects:
		if e.id == id:
			e.remaining = maxf(e.remaining, duration)
			e.stacks = mini(e.stacks + 1, int(def.get("max_stacks", 1)))
			e.magnitude = maxf(e.magnitude, magnitude)
			e.source = source
			_publish()
			return
	effects.append({"id": id, "def": def, "remaining": duration, "tick_left": float(def.get("tick", 1.0)),
		"magnitude": magnitude, "stacks": 1, "source": source})
	_publish()
	get_parent().on_stats_dirty()


func remove(id: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].id == id:
			effects.remove_at(i)
	_publish()
	get_parent().on_stats_dirty()


func clear_all() -> void:
	effects.clear()
	_publish()
	get_parent().on_stats_dirty()


func has_flag(flag: String) -> bool:
	if multiplayer.is_server():
		for e in effects:
			if Array(e.def.get("flags", [])).has(flag):
				return true
		return false
	for s in shown:
		if Array(GameData.status_effects.get(s[0], {}).get("flags", [])).has(flag):
			return true
	return false


func has(id: String) -> bool:
	for s in shown:
		if s[0] == id:
			return true
	return false


## Aggregated stat modifiers: *_mult keys multiply, everything else adds.
func stat_mods() -> Dictionary:
	var out := {}
	for e in effects:
		var st: Dictionary = e.def.get("stats", {})
		for k in st:
			if str(k).ends_with("_mult"):
				out[k] = float(out.get(k, 1.0)) * float(st[k])
			else:
				out[k] = float(out.get(k, 0.0)) + float(st[k])
	return out


func _process(delta: float) -> void:
	if not multiplayer.is_server() or effects.is_empty():
		return
	var actor := get_parent()
	var expired := false
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		e.remaining -= delta
		var kind: String = e.def.kind
		if kind == "dot" or kind == "hot":
			e.tick_left -= delta
			if e.tick_left <= 0.0:
				e.tick_left += float(e.def.get("tick", 1.0))
				if Combat.instance and is_instance_valid(actor):
					Combat.instance.status_tick(actor, e)
		if e.remaining <= 0.0:
			effects.remove_at(i)
			expired = true
	_show_timer -= delta
	if expired or _show_timer <= 0.0:
		_publish()
	if expired and is_instance_valid(actor):
		actor.on_stats_dirty()


func _publish() -> void:
	_show_timer = 0.5
	var out: Array = []
	for e in effects:
		out.append([e.id, snappedf(maxf(e.remaining, 0.0), 0.1), e.stacks])
	shown = out
