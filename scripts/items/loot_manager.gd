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


## Host: rolls `source`'s loot and throws it out of `pos` (#75: each item flies from there to its
## spot, one after another). Returns the items.
func roll_and_drop(source: String, pos: Vector2, override: Dictionary = {}) -> Array:
	if not multiplayer.is_server():
		return []
	var ov := override.duplicate()
	ov.biome = str(game.floor_def.get("lore_origin", game.floor_def.get("id", "")))
	# #71: the floor modifier's rewards (an explicit override wins).
	var mods := FloorMods.loot_override(game.floor_def)
	for k in mods:
		if not ov.has(k):
			ov[k] = mods[k]
	var items := LootTable.roll(source, game.item_level(), game.depth, GameState.classes_in_party(), rng, ov)
	throw_items(items, pos)
	return items


## Host: `items` burst out of `pos` and land around it (the drop scatter; never in a wall or a
## doorway), each a little after the one before.
func throw_items(items: Array, pos: Vector2, first_delay: float = 0.0) -> void:
	var scatter := float(GameData.bal("loot.drop_scatter"))
	var stagger := float(GameData.bal("loot.flight.stagger"))
	var rise := Vector2(0, -float(GameData.bal("loot.flight.from_height")))
	for i in items.size():
		var off := Vector2.ZERO if items.size() == 1 else Vector2.from_angle(TAU * i / items.size()) * scatter
		# A single item still hops out a little, so it is seen to fall out.
		if items.size() == 1:
			off = Vector2.from_angle(rng.randf() * TAU) * scatter * 0.6
		drop_item(items[i], pos + off, pos + rise, first_delay + stagger * i)
		if not str(items[i].get("legendary", "")).is_empty() or str(items[i].get("classification", "")) == "legendary":
			game.announce_legendary(items[i], first_delay + stagger * i)


## Host: puts `item` on the ground at `pos`. With `from` it flies there from that point first
## (after `delay` s) and can't be picked up mid-air (#75).
func drop_item(item: Dictionary, pos: Vector2, from: Vector2 = Vector2.INF, delay: float = 0.0) -> void:
	if not multiplayer.is_server() or item.is_empty():
		return
	_counter += 1
	# Keep drops out of walls.
	var c: Vector2i = game.dungeon.cell_of(pos)
	if not DungeonGenerator.walkable(game.dungeon.cell_at(c)):
		pos = game.dungeon.cell_center(game.dungeon.cell_of(game.nearest_floor(pos)))
	# Nor in a doorway, where the door would sit on top of it (#35).
	if game.in_doorway(pos):
		pos = game.floor_beside_door(pos)
	var data := {"name": "Item_%d" % _counter, "pos": pos, "item": item}
	if from != Vector2.INF:
		data["from"] = from
		data["delay"] = delay
	spawner.spawn(data)


## Host: player asked to pick up a ground item.
func try_pickup(player: Player, g: GroundItem) -> void:
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		return
	if player.global_position.distance_to(g.global_position) > float(GameData.bal("world.pickup_range")) + 16.0:
		return
	if not game.dungeon.reach_clear(player.global_position, g.global_position):
		return  # #79: never through a wall
	if not g.is_landed():
		return  # #75: still in the air
	if g.item.get("kind", "") == "cell_key":
		game.events.host_cell_key(player)
		g.queue_free()
		return
	if g.item.get("kind", "") == "gold_key":
		game.add_party_key(1)
		game.broadcast_message.rpc("%s found a Gold Key - Archibald will trade", "#f0c850", [player.display_name])
		game.combat.fx.sound.rpc("key_unlock", g.global_position)
		g.queue_free()
		return
	if g.item.get("kind", "") == "gold":
		_picked.rpc_id(player.peer_id, g.global_position, g.item)
		split_gold(player, int(g.item.get("amount", 0)))
		game.combat.fx.sound.rpc("coin", g.global_position)
		g.queue_free()
		return
	var err := player.host_give_item(g.item)
	if not err.is_empty():
		player._notify.rpc_id(player.peer_id, err)
		return
	_picked.rpc_id(player.peer_id, g.global_position, g.item)
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
		pl._notify.rpc_id(pl.peer_id, "+%d gold", [got])


## Host -> the picker (reliable, #81): what it picked up flies from the floor to its HUD.
@rpc("authority", "call_local", "reliable")
func _picked(at: Vector2, item: Dictionary) -> void:
	var kind := "gold" if str(item.get("kind", "")) == "gold" else "item"
	var icon: Texture2D = ItemLooks.icon(item) if GameData.asset_exists(str(item.get("icon", ""))) else UITheme.icon_tex("hud_gold")
	EventBus.local_picked_up.emit(at, kind, icon)

