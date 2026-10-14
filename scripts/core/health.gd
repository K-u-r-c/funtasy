class_name Health
extends Node
## Hit points + absorb shield. Only the host changes these values; they reach clients through
## the actor's state synchronizer.

signal died
signal changed

var hp: float = 1.0:
	set(v):
		hp = v
		changed.emit()
var max_hp: float = 1.0:
	set(v):
		max_hp = v
		changed.emit()
var absorb: float = 0.0:
	set(v):
		absorb = v
		changed.emit()
var absorb_time := 0.0


func is_dead() -> bool:
	return hp <= 0.0


## Returns damage actually taken from hp (after absorb).
func take(amount: float) -> float:
	if hp <= 0.0 or amount <= 0.0:
		return 0.0
	if absorb > 0.0:
		var soaked := minf(absorb, amount)
		absorb -= soaked
		amount -= soaked
	var before := hp
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0 and before > 0.0:
		died.emit()
	return before - hp


## Returns amount actually healed.
func heal(amount: float) -> float:
	if hp <= 0.0 or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(hp + amount, max_hp)
	return hp - before


func set_max(new_max: float, keep_ratio := true) -> void:
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = maxf(new_max, 1.0)
	if keep_ratio and hp > 0.0:
		hp = clampf(ratio * max_hp, 1.0, max_hp)
	else:
		hp = minf(hp, max_hp)


func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


func _process(delta: float) -> void:
	if absorb_time > 0.0:
		absorb_time -= delta
		if absorb_time <= 0.0 and multiplayer.is_server():
			absorb = 0.0
