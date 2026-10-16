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
	var ov := override.duplicate()
	ov.biome = str(game.floor_def.get("lore_origin", game.floor_def.get("id", "")))
	var items := LootTable.roll(source, game.monster_level(), game.depth, GameState.classes_in_party(), rng, ov)
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
	if not DungeonGenerator.walkable(game.dungeon.cell_at(c)):
		pos = game.dungeon.cell_center(game.dungeon.cell_of(game.nearest_floor(pos)))
	spawner.spawn({"name": "Item_%d" % _counter, "pos": pos, "item": item})


## Host: player asked to pick up a ground item.
func try_pickup(player: Player, g: GroundItem) -> void:
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		return
	if player.global_position.distance_to(g.global_position) > float(GameData.bal("world.pickup_range")) + 16.0:
		return
	if g.item.get("kind", "") == "gold_key":
		game.add_party_key(1)
		game.broadcast_message.rpc("%s found a Gold Key - Archibald will trade" % player.display_name, "#f0c850")
		game.combat.fx.sound.rpc("key_unlock", g.global_position)
		g.queue_free()
		return
	if g.item.get("kind", "") == "gold":
		split_gold(player, int(g.item.get("amount", 0)))
		game.combat.fx.sound.rpc("coin", g.global_position)
		g.queue_free()
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


## D12: a gold pile is shared equally by every living party member (the picker gets the rest).
func split_gold(picker: Player, amount: int) -> void:
	var living: Array = game.players_root.get_children().filter(func(pl): return pl.life_state == Player.Life.ALIVE)
	if living.is_empty():
		living = [picker]
	var share := amount / living.size()
	var rest := amount - share * living.size()
	for pl in living:
		var got: int = share + (rest if pl == picker else 0)
		pl.host_add_gold(got)
		pl._notify.rpc_id(pl.peer_id, "+%d gold" % got)
