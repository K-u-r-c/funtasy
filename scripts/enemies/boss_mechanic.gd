class_name BossMechanic
extends RefCounted
## Base of a boss encounter mechanic (scripts/enemies/boss_mechanics/<id>.gd), listed per phase
## in data/bosses/<id>.json: "mechanics": [{"id": "ossuary_cage", "every": 16, ...}]. Host-only.
## A mechanic fires `trigger()` every `every` s (first after `first`), may keep the boss busy
## (`busy()` skips its normal AI) and can react to interactions with arena objects.

var boss: Enemy
var params: Dictionary = {}
var left := 0.0


func setup(b: Enemy, p: Dictionary) -> void:
	boss = b
	params = p
	left = float(p.get("first", p.get("every", 10.0) * 0.5))
	_ready()


func _ready() -> void:
	pass


## Host, every physics frame while its phase is active.
func physics(delta: float) -> void:
	if not params.has("every"):
		return
	left -= delta
	if left <= 0.0:
		left = float(params.every)
		trigger()


func trigger() -> void:
	pass


## True while the mechanic drives the boss (its normal AI pauses).
func busy() -> bool:
	return false


## The phase ends (or the boss dies): clean up arena objects.
func stop() -> void:
	pass


## A player interacted with an arena object this mechanic owns. Return true when handled.
func on_interact(_player: Player, _node: Node) -> bool:
	return false


func modify_damage_taken(amount: float, _data: Dictionary) -> float:
	return amount


## Host: a direction the boss must move in (Vector2.INF = no override).
func move_override(_delta: float) -> Vector2:
	return Vector2.INF


## Test harness: force the mechanic now, then check it did its job ("" = ok).
func test_trigger(_suite: RefCounted) -> void:
	trigger()


func test_check(_suite: RefCounted) -> String:
	return ""


# --- helpers ---------------------------------------------------------------------------------


func game() -> Node:
	return boss.get_tree().get_first_node_in_group("game")


func p(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)


func living_players() -> Array:
	return game().players_root.get_children().filter(func(pl): return pl.is_targetable())


func ctx() -> Dictionary:
	return Combat.instance.make_ctx(boss, {"id": "boss_mechanic", "school": "spell", "damage_type": str(p("damage_type", "physical"))})


func boss_room() -> Rect2:
	var g := game()
	var r: Rect2i = g.layout.rooms[int(g.layout.boss_room)].rect
	return Rect2(Vector2(r.position * g.dungeon.tile), Vector2(r.size * g.dungeon.tile))
