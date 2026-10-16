class_name FloorMechanic
extends RefCounted
## Base of a biome environment mechanic (scripts/dungeon/mechanics/<id>.gd), listed in a floor
## type's "floor_mechanics": [{"id": "unlit_regen_penalty", ...}]. Host-only, ticks every frame.

var game: Node
var params: Dictionary = {}


func setup(g: Node, p: Dictionary) -> void:
	game = g
	params = p
	_ready()


func _ready() -> void:
	pass


func physics(_delta: float) -> void:
	pass


## Host: a monster died (Kurgan blood pools).
func on_enemy_killed(_e: Node) -> void:
	pass


## A prop broke (grave urns, bookshelves...).
func on_prop_broken(_prop: Node) -> void:
	pass


func p(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)


## Test harness: put the party in the situation the mechanic reacts to.
func test_trigger(_suite: RefCounted) -> void:
	pass


## Test harness: "" when the mechanic did its job, else what is wrong.
func test_check(_suite: RefCounted) -> String:
	return ""
