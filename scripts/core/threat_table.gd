class_name ThreatTable
extends Node
## Host-only aggro table for one enemy. Threat comes from damage, healing, buffs, taunts and
## proximity. The enemy attacks the highest-threat target, but only switches when a challenger
## exceeds the current target by `switch_ratio` (hysteresis), so it doesn't flicker between
## targets. Taunt forces the target for a duration.

var threat: Dictionary = {}  ## Actor -> float
var last_seen: Dictionary = {}  ## Actor -> seconds since the actor last added threat
var current: Node = null
var _taunt_by: Node = null
var _taunt_left := 0.0


func add(actor: Node, amount: float) -> void:
	if actor == null or not is_instance_valid(actor) or amount <= 0.0:
		return
	threat[actor] = float(threat.get(actor, 0.0)) + amount
	last_seen[actor] = 0.0


func taunt(actor: Node, duration: float) -> void:
	var top := 0.0
	for a in threat:
		top = maxf(top, threat[a])
	threat[actor] = maxf(float(threat.get(actor, 0.0)), top * float(GameData.bal("threat.taunt_bonus")) + 10.0)
	last_seen[actor] = 0.0
	_taunt_by = actor
	_taunt_left = duration
	current = actor


func has_any() -> bool:
	return not threat.is_empty()


func value_of(actor: Node) -> float:
	return float(threat.get(actor, 0.0))


func forget(actor: Variant) -> void:
	threat.erase(actor)
	last_seen.erase(actor)
	if current == actor:
		current = null
	if _taunt_by == actor:
		_taunt_by = null


func clear() -> void:
	threat.clear()
	last_seen.clear()
	current = null
	_taunt_by = null


## Picks the target. `valid` filters out dead/ghost/untargetable actors.
func update(delta: float, valid: Callable) -> Node:
	var forget_after := float(GameData.bal("threat.forget_time"))
	for a in threat.keys():
		if not is_instance_valid(a) or not valid.call(a):
			forget(a)
			continue
		last_seen[a] = float(last_seen.get(a, 0.0)) + delta
		if last_seen[a] > forget_after and a != current:
			forget(a)
	if _taunt_left > 0.0:
		_taunt_left -= delta
		if is_instance_valid(_taunt_by) and threat.has(_taunt_by):
			current = _taunt_by
			return current
	var best: Node = null
	var best_v := -1.0
	for a in threat:
		if threat[a] > best_v:
			best_v = threat[a]
			best = a
	if current == null or not threat.has(current):
		current = best
	elif best != current and best_v > threat[current] * _switch_ratio(best):
		current = best
	return current


## Classic rule: a challenger in melee range needs 110% of the current target's threat, one at
## range needs 130%, so ranged damage dealers don't rip monsters off the tank too easily.
func _switch_ratio(challenger: Node) -> float:
	var me := get_parent() as Node2D
	if me and challenger is Node2D and me.global_position.distance_to(challenger.global_position) > float(GameData.bal("threat.melee_range")):
		return float(GameData.bal("threat.switch_ratio_ranged"))
	return float(GameData.bal("threat.switch_ratio"))
