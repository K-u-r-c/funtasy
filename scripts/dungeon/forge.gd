class_name Forge
extends Node
## The blacksmith's forge (#77): on about half of the floors (a seeded pick, Game.pick_forge) Rolf
## Hult works an anvil in his own sealed leaf chamber. A hero pays gold to raise one of its own
## items (worn or in the backpack) by one item level, up to the forge's cap; the item is
## recomputed as if it had dropped at the new level (ItemGenerator.at_level). Host-authoritative:
## every upgrade is a validated intent, and the result reaches the owner with its inventory.
##
## RPCs (all on this node, the same path on every peer):
## - request_upgrade(where, key, uid): owner -> host, reliable. where "equip" (key = slot) or
##   "bag" (key = backpack index); uid guards against a stale list.
## - _open_ui(): host -> one peer, reliable: opens the forge window.
## - _forged(peer, before, after): host -> all, reliable: the smith works the piece on every peer,
##   the owner's window plays the forging and shows the new numbers.
## - _notice(text, args): host -> one peer, reliable.

signal forged(before: Dictionary, after: Dictionary)  ## local: the owner's piece came back

var game: Node
var upgrades := 0  ## host: upgrades done on this floor (tests)


static func cfg(key: String, fallback: Variant = null) -> Variant:
	return GameData.merchants.get("blacksmith", {}).get("upgrade", {}).get(key, fallback)


## Can the forge work this kind of item at all?
static func workable(item: Dictionary) -> bool:
	return str(item.get("kind", "")) in ["weapon", "offhand", "armor", "jewelry"]


## The highest item level the forge raises gear to: the hero's level, and no more than
## `cap_above_floor` above the floor's item level (so a hero far ahead of the floor doesn't
## out-forge what the floor drops).
static func cap_for(hero_level: int, floor_ilvl: int) -> int:
	return clampi(mini(hero_level, floor_ilvl + int(cfg("cap_above_floor", 0))), 1, int(GameData.bal("progression.max_level")))


## Gold for one step of `item` (at its current item level) for a hero in a party of `party`:
## base x the rarity's factor x (1 + per_level x (ilvl - 1))^level_exponent x its quality x
## party_price[party - 1] (gold piles are split between the heroes, so a hero of a big party
## earns less of a floor's gold; the forge takes the same share of it).
static func cost(item: Dictionary, party: int = 1) -> int:
	var rm: Array = cfg("rarity_mult", [1, 1, 1, 1, 1])
	var r := clampi(int(item.get("rarity", 1)), 1, rm.size())
	var lvl := maxi(int(item.get("ilvl", 1)), 1)
	var c := float(cfg("base", 10)) * float(rm[r - 1]) * pow(1.0 + float(cfg("per_level", 0.2)) * (lvl - 1), float(cfg("level_exponent", 1.0)))
	var pp: Array = cfg("party_price", [1.0])
	c *= float(pp[clampi(party, 1, pp.size()) - 1])
	return maxi(1, roundi(c * float(item.get("quality_mult", 1.0))))


## The party size the forge prices for (the heroes on the floor).
static func party(tree: SceneTree) -> int:
	var game := tree.get_first_node_in_group("game") if tree else null
	return maxi(game.players_root.get_child_count(), 1) if game else 1


## Why `item` can't be raised now for a hero of `hero_level` with `gold` ("" when it can), as an
## English source text with its format arguments: [text, args].
static func refusal(item: Dictionary, hero_level: int, floor_ilvl: int, gold: int, party_n: int = 1) -> Array:
	if not workable(item):
		return ["Rolf can't work that", []]
	var cap := cap_for(hero_level, floor_ilvl)
	if int(item.get("ilvl", 1)) >= cap:
		if cap < hero_level:
			return ["At the forge's limit for this floor (item level %d)", [cap]]
		return ["At your level already (item level %d)", [cap]]
	var c := cost(item, party_n)
	if gold < c:
		return ["Not enough gold (%d needed)", [c]]
	return ["", []]


## Host: the hero `p` within reach of the smith, alive; null otherwise.
func _hero_near(peer: int) -> Player:
	var p: Player = game.player_by_peer(peer) if game else null
	var fg: Dictionary = game.layout.get("forge", {}) if game else {}
	if p == null or fg.is_empty() or p.life_state != Player.Life.ALIVE:
		return null
	if p.global_position.distance_to(fg.npc) > float(GameData.bal("merchant.interact_range")):
		return null
	return p


## Host: a hero talked to the smith.
func host_interact(p: Player, node: Node) -> void:
	game.combat.fx.sound.rpc("forge_strike", node.global_position)
	_open_ui.rpc_id(p.peer_id)


## Host: the item a request points at, or {}.
static func item_at(p: Player, where: String, key: String) -> Dictionary:
	if where == "equip":
		return p.inv.equipment.get(key, {})
	if where == "bag" and key.is_valid_int() and int(key) >= 0 and int(key) < p.inv.backpack.size():
		return p.inv.backpack[int(key)]
	return {}


# =========================================================================================
# Intents (owner -> host, reliable)
# =========================================================================================


@rpc("any_peer", "call_local", "reliable")
func request_upgrade(where: String, key: String, uid: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _hero_near(peer)
	if p == null:
		return
	var item := item_at(p, where, key)
	if item.is_empty() or str(item.get("uid", "")) != uid:
		return
	var n := party(get_tree())
	var why := refusal(item, p.level, game.item_level(), p.gold, n)
	if not str(why[0]).is_empty():
		_notice.rpc_id(peer, str(why[0]), why[1])
		game.combat.fx.sound.rpc_id(peer, "ui_error", p.global_position)
		return
	var price := cost(item, n)
	var after := ItemGenerator.at_level(item, int(item.get("ilvl", 1)) + int(cfg("step", 1)))
	after.forged = int(item.get("forged", 0)) + 1
	p.host_add_gold(-price)
	if where == "equip":
		p.inv.equipment[key] = after
	else:
		p.inv.backpack[int(key)] = after
	p._inventory_changed()
	p.persist()
	upgrades += 1
	_forged.rpc(peer, item, after, price)


# =========================================================================================
# Host -> peers
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _open_ui() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_forge"):
		hud.open_forge()


@rpc("authority", "call_local", "reliable")
func _forged(peer: int, before: Dictionary, after: Dictionary, _price: int) -> void:
	var smith: Node = game.dungeon.props.get("Forge_npc") if game and game.dungeon else null
	if smith and is_instance_valid(smith):
		var anim: Node = smith.get_node_or_null("NpcAnim")
		if anim and anim.has_method("work_piece"):
			anim.work_piece()
	if peer == multiplayer.get_unique_id():
		# #91: no message - the window's card shows the result with its light.
		forged.emit(before, after)


@rpc("authority", "call_local", "reliable")
func _notice(text: String, args: Array = []) -> void:
	EventBus.hud_message.emit(Loc.f(text, args), Color(1, 0.85, 0.5))
