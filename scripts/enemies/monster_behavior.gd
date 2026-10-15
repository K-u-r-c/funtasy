class_name MonsterBehavior
extends RefCounted
## Base of a monster behaviour module (scripts/enemies/behaviors/<id>.gd), attached from data:
## "behaviors": [{"id": "burrow", ...params}]. Host-only logic; the Enemy replicates
## `behavior_state` (a short string) so every peer can draw the right look (bone pile, mound,
## puddle, statue...). Every hook has a harmless default.

var enemy: Enemy
var params: Dictionary = {}


func setup(e: Enemy, p: Dictionary) -> void:
	enemy = e
	params = p
	_ready()


func _ready() -> void:
	pass


## Host, every AI think (~0.2 s). Return true to skip the default think (target + abilities).
func on_think(_game: Node) -> bool:
	return false


## Host, every physics frame.
func on_physics(_delta: float) -> void:
	pass


## Host: a direction to move instead of the default chase (Vector2.INF = no override).
func move_override(_delta: float) -> Vector2:
	return Vector2.INF


## Host: the monster was damaged.
func on_damaged(_attacker: Actor, _amount: float) -> void:
	pass


## Host: scales damage this monster takes (frontal shields, shells, incorporeal bodies).
func modify_damage_taken(amount: float, _data: Dictionary) -> float:
	return amount


## Host: the monster's HP hit zero. Return true to cancel the death (reassemble, split...).
func on_death() -> bool:
	return false


## Host: another monster died nearby (`corpse` is its corpse record or {}).
func on_ally_death(_other: Enemy, _corpse: Dictionary) -> void:
	pass


## False while the monster can't be hit (burrowed, ink puddle, perched statue...).
func is_targetable() -> bool:
	return true


## Host: a target that ignores threat (bleeding prey, casters), or null.
func target_override() -> Actor:
	return null


## Test harness: put the monster in the situation that triggers this behaviour.
func test_trigger(_suite: RefCounted) -> void:
	pass


## Test harness: "" when the behaviour did its job, else what is wrong.
func test_check(_suite: RefCounted) -> String:
	return ""


# --- helpers ---------------------------------------------------------------------------------


func set_state(s: String) -> void:
	enemy.behavior_state = s


func game() -> Node:
	return enemy.get_tree().get_first_node_in_group("game")


func p(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)
