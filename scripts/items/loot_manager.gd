class_name LootManager
extends Node
## Host-side loot: rolls drops (LootTable), spawns/despawns ground items through the
## MultiplayerSpawner and handles pick-ups. Dropping an item and letting a teammate pick it
## up is how players trade.

var game: Node
var spawner: MultiplayerSpawner
var items_root: Node2D
var rng := RandomNumberGenerator.new()
var _counter := 0


func _ready() -> void:
	rng.randomize()


func spawn_function(data: Dictionary) -> Node:
	var g := GroundItem.new()
	g.setup(data)
	return g


func roll_and_drop(source: String, pos: Vector2, override: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	var items := LootTable.roll(source, game.monster_level(), game.depth, GameState.classes_in_party(), rng, override)
	var scatter := float(GameData.bal("loot.drop_scatter"))
	for i in items.size():
		var off := Vector2.ZERO if items.size() == 1 else Vector2.from_angle(TAU * i / items.size()) * scatter
		drop_item(items[i], pos + off)


func drop_item(item: Dictionary, pos: Vector2) -> void:
	if not multiplayer.is_server() or item.is_empty():
		return
	_counter += 1
	# Keep drops out of walls.
	var c: Vector2i = game.dungeon.cell_of(pos)
	if game.dungeon.cell_at(c) != DungeonGenerator.CELL_FLOOR:
		pos = game.dungeon.cell_center(game.dungeon.cell_of(game.nearest_floor(pos)))
	spawner.spawn({"name": "Item_%d" % _counter, "pos": pos, "item": item})


## Host: player asked to pick up a ground item.
func try_pickup(player: Player, g: GroundItem) -> void:
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		return
	if player.global_position.distance_to(g.global_position) > float(GameData.bal("world.pickup_range")) + 16.0:
		return
	var err := player.host_give_item(g.item)
	if not err.is_empty():
		player._notify.rpc_id(player.peer_id, err)
		return
	game.combat.fx.sound.rpc("pickup", g.global_position)
	g.queue_free()


func clear_floor() -> void:
	for c in items_root.get_children():
		c.queue_free()
