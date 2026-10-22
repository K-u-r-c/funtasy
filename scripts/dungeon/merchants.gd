class_name Merchants
extends Node
## The merchant of every floor (GDD 5, #6): one seeded pick per floor (Game.merchant_id) in its
## own sealed room (#23) - Archibald the Gilded (his vault door opens with the floor's Gold Key,
## used up at the door, D11) or Malphas the Soul Broker (his door opens for the floor's blood
## price, paid by the hero who breaks the seal, D13). Once the door is open the merchant trades
## with the whole party. Host-authoritative: the door seal, the stock, the open shop and the
## contracts are replicated to everyone; every purchase is a host-validated intent.
##
## RPCs (all on this node, the same path on every peer):
## - request_buy(index) / request_sell(backpack index) / request_tithe(accept: pay the blood
##   price at Malphas's door) / request_contract(index) / request_pact(id): owner -> host, reliable.
## - _sync(stock, contracts, shop_open, pacts), _open_ui(kind), _ask_tithe(text), _notice(text):
##   host -> peers, reliable.
## - request_buyback(index): owner -> host, reliable (#114): buy back an item this hero sold.
## - _sync_mine(signed, pacted, buyback): host -> one peer, reliable (#94): what that hero already
##   signed and bought from Malphas this floor, so its window marks them, and (#114) what it sold to
##   Archibald this floor ([{item, price}], newest first).

signal changed

var game: Node
var stock: Array = []  ## every peer: [{item, price, left}]
var contracts: Array = []  ## every peer: indices into merchants.malphas.contracts
var pacts: Array = []  ## every peer (#95): the pact potions Malphas offers this floor
var my_signed: Array = []  ## local (#94): contract slots this hero signed this floor
var my_pacts: Array = []  ## local (#94): pact potions this hero bought this floor
var my_buyback: Array = []  ## local (#114): [{item, price}] this hero sold to Archibald this floor
var shop_open := false  ## Archibald's vault door took this floor's Gold Key: he trades
var _signed: Dictionary = {}  ## host: peer -> [contract slots signed this floor]
var _pacted: Dictionary = {}  ## host (#95): peer -> [pact ids bought this floor]
var _buyback: Dictionary = {}  ## host (#114): peer -> [{item, price}] sold this floor, newest first
var rng := RandomNumberGenerator.new()


# =========================================================================================
# Host
# =========================================================================================


func host_new_floor(floor_seed: int, item_level: int) -> void:
	rng.seed = floor_seed + 777
	_signed.clear()
	_pacted.clear()
	_buyback.clear()
	shop_open = false
	var a: Dictionary = GameData.merchants.get("archibald", {})
	var st: Array = []
	# #93: a big stock, sometimes Epic, rarely a Relic, at or a little above the floor's level,
	# mostly for the party's classes (data).
	var rw: Dictionary = a.get("rarity_weights", {"2": 1, "3": 1})
	var tiers: Array = rw.keys()
	var weights: Array = tiers.map(func(k): return float(rw[k]))
	var above: Array = a.get("ilvl_above", [0, 0])
	var cap := int(GameData.bal("progression.max_level"))
	for i in int(a.get("equipment", 3)):
		var base := LootTable.pick_base(GameState.classes_in_party(), rng, float(a.get("party_class_weight", -1.0)))
		var rarity := int(tiers[ItemGenerator._weighted_index(weights, rng)])
		var il := mini(item_level + rng.randi_range(int(above[0]), int(above[1])), cap)
		var it := ItemGenerator.generate_equipment(base, il, rarity, rng)
		st.append({"item": it, "price": buy_price(it), "left": 1})
	var cons: Dictionary = a.get("consumables", {})
	for cid in cons:
		# #80: no torches for sale when the party plays without them.
		if GameData.consumables.get(str(cid), {}).get("needs_torches", false) and not GameState.torches_on():
			continue
		var ci := ItemGenerator.generate_consumable(str(cid), 1, rng)
		st.append({"item": ci, "price": buy_price(ci), "left": int(cons[cid])})
	stock = st
	var mal: Dictionary = GameData.merchants.get("malphas", {})
	var pool: Array = mal.get("contracts", [])
	var idx: Array = range(pool.size())
	var picked: Array = []
	for i in mini(int(mal.get("contracts_per_floor", 2)), idx.size()):
		picked.append(idx.pop_at(rng.randi_range(0, idx.size() - 1)))
	contracts = picked
	# #95: a seeded pair of pact potions (sorted ids, so every peer and save agrees).
	var ids: Array = GameData.pact_consumables.keys()
	ids.sort()
	var offer: Array = []
	for i in mini(int(mal.get("pacts_per_floor", ids.size())), ids.size()):
		offer.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	pacts = offer
	_sync.rpc(stock, contracts, shop_open, pacts)
	_sync_mine.rpc([], [], [])


static func item_value(item: Dictionary) -> int:
	match str(item.get("kind", "")):
		"gold", "gold_key":
			return 0
		"consumable":
			var base := str(item.get("base", ""))
			if base.begins_with("pact_"):
				return 0
			var cp := float(GameData.bal("merchant.consumable_price", {}).get(base, 10))
			return roundi(cp * (1.0 + float(GameData.bal("merchant.consumable_per_level")) * (int(item.get("ilvl", 1)) - 1)))
		"book":
			return int(GameData.bal("merchant.book_value", {}).get(str(item.get("classification", "standard")), 5))
	var tiers: Array = GameData.bal("merchant.tier_value")
	var r := clampi(int(item.get("rarity", 1)), 1, tiers.size())
	# A better-made item (#64) is worth its quality.
	return roundi(float(tiers[r - 1]) * (1.0 + float(GameData.bal("merchant.per_item_level")) * (int(item.get("ilvl", 1)) - 1)) * float(item.get("quality_mult", 1.0)))


static func buy_price(item: Dictionary) -> int:
	return maxi(1, roundi(item_value(item) * float(GameData.bal("merchant.buy_mult"))))


static func sell_price(item: Dictionary) -> int:
	var each := roundi(item_value(item) * float(GameData.bal("merchant.sell_mult")))
	return maxi(each, 0)


## Host: a player talked to the floor's merchant (inside the room, so its door is open).
func host_interact(p: Player, node: Node) -> void:
	var d: Dictionary = node.def
	match str(d.get("npc", "")):
		"archibald":
			if shop_open:
				game.combat.fx.sound.rpc("merchant_chime", node.global_position)
				_open_ui.rpc_id(p.peer_id, "archibald")
		"malphas":
			if _paid():
				_open_ui.rpc_id(p.peer_id, "malphas")


## Host: a player used the merchant room's sealed door (#23).
func host_door(p: Player, door: Node) -> void:
	if not door.sealed:
		return
	match str(door.type_def.get("seal", "")):
		"gold_key":
			if game.party_keys <= 0:
				_notice.rpc_id(p.peer_id, "The vault is sealed: bring the floor's Gold Key (an elite or a chest carries it)")
				game.combat.fx.sound.rpc("ui_error", door.interact_pos())
				return
			game.add_party_key(-1)
			door.host_unseal()
			shop_open = true
			_sync.rpc(stock, contracts, shop_open, pacts)
			game.combat.fx.sound.rpc("key_unlock", door.interact_pos())
			game.broadcast_message.rpc("%s opens Archibald's vault with the Gold Key", "#f0c850", [p.display_name])
		"blood":
			_ask_tithe.rpc_id(p.peer_id, "Malphas's seal asks for blood: %s for the rest of the run. The door then stays open for the whole party.", [blood_price(int(game.layout.get("seed", 0)))])


## The floor's blood price at Malphas's door: one of merchants.json malphas.tithe, picked from the
## floor seed so every peer shows the same price before anyone pays it.
static func blood_price(floor_seed: int) -> Dictionary:
	var opts: Array = GameData.merchants.get("malphas", {}).get("tithe", [])
	if opts.is_empty():
		return {"stat": "max_hp", "value": -10.0}
	return opts[posmod(floor_seed * 31 + 7, opts.size())].duplicate()


## Malphas trades once his door's seal is broken (by anyone).
func _paid() -> bool:
	var door: Node = game.dungeon.leaf_door("merchant") if game else null
	return door != null and not door.sealed


func _player_near(peer: int) -> Player:
	var p: Player = game.player_by_peer(peer) if game else null
	if p == null or p.life_state != Player.Life.ALIVE or game.layout.get("merchant", {}).is_empty():
		return null
	var m: Dictionary = game.layout.merchant
	if p.global_position.distance_to(m.pos) > float(GameData.bal("merchant.interact_range")):
		return null
	return p


## The player within reach of the merchant room's door, or null.
func _player_at_door(peer: int) -> Player:
	var p: Player = game.player_by_peer(peer) if game else null
	var door: Node = game.dungeon.leaf_door("merchant") if game else null
	if p == null or door == null or p.life_state != Player.Life.ALIVE:
		return null
	if p.global_position.distance_to(door.interact_pos()) > float(GameData.bal("world.interact_range")) + 24.0:
		return null
	return p


## Host: the floor's merchant is `npc`.
func _is(npc: String) -> bool:
	return str(game.layout.get("merchant", {}).get("npc", "")) == npc


static func stat_name(k: String) -> String:
	return Loc.t({"max_hp": "Max Health", "max_hp_pct": "Max Health", "crit_chance": "Critical Strike Chance",
		"move_speed": "Movement Speed", "max_resource": "Max Mana"}.get(k, k.replace("_", " ").capitalize()))


static func mod_text(m: Dictionary) -> String:
	var k := str(m.stat)
	var v := float(m.value)
	var name := stat_name(k)
	var num := "%d%%" % roundi(v * 100.0) if (k.ends_with("_pct") or k in ["crit_chance", "dodge", "haste", "leech"]) else "%d" % roundi(v)
	return "%s%s %s" % ["+" if v >= 0 else "", num, name]


# =========================================================================================
# Intents (owner -> host, reliable)
# =========================================================================================


@rpc("any_peer", "call_local", "reliable")
func request_buy(index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _is("archibald") or not shop_open or index < 0 or index >= stock.size():
		return
	var e: Dictionary = stock[index]
	if int(e.left) <= 0:
		_notice.rpc_id(peer, "Sold out")
		return
	if p.gold < int(e.price):
		_notice.rpc_id(peer, "Not enough gold (%d needed)", [int(e.price)])
		return
	var item: Dictionary = e.item.duplicate(true)
	item.uid = ItemGenerator.new_uid(rng)
	var err := p.host_give_item(item)
	if not err.is_empty():
		_notice.rpc_id(peer, err)
		return
	p.host_add_gold(-int(e.price))
	e.left = int(e.left) - 1
	game.combat.fx.sound.rpc("coin", p.global_position)
	_sync.rpc(stock, contracts, shop_open, pacts)
	_notice.rpc_id(peer, "Bought %s for %d gold", [item.get("name", "item"), int(e.price)])


@rpc("any_peer", "call_local", "reliable")
func request_sell(backpack_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _is("archibald") or not shop_open:
		return
	if backpack_index < 0 or backpack_index >= p.inv.backpack.size():
		return
	var item: Dictionary = p.inv.backpack[backpack_index]
	var price := sell_price(item)
	if price <= 0:
		_notice.rpc_id(peer, "Archibald won't buy that")
		return
	var sold: Dictionary = item.duplicate(true)
	if item.get("kind", "") == "consumable" and int(item.get("count", 1)) > 1:
		p.inv.consume(str(item.base))
		sold.count = 1
	else:
		p.inv.take_backpack(backpack_index)
	p.host_add_gold(price)
	p._inventory_changed()
	# #114: Archibald keeps what this hero sold him this floor, to buy back at the same price.
	var list: Array = _buyback.get(peer, [])
	list.push_front({"item": sold, "price": price})
	_buyback[peer] = list.slice(0, int(GameData.merchants.get("archibald", {}).get("buyback_max", 10)))
	_sync_mine.rpc_id(peer, _signed.get(peer, []), _pacted.get(peer, []), _buyback[peer])
	game.combat.fx.sound.rpc("coin", p.global_position)
	_notice.rpc_id(peer, "Sold %s for %d gold", [item.get("name", "item"), price])


## #114: buy back entry `index` of what this hero sold to Archibald this floor, for its sell price.
@rpc("any_peer", "call_local", "reliable")
func request_buyback(index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	var list: Array = _buyback.get(peer, [])
	if p == null or not _is("archibald") or not shop_open or index < 0 or index >= list.size():
		return
	var e: Dictionary = list[index]
	if p.gold < int(e.price):
		_notice.rpc_id(peer, "Not enough gold (%d needed)", [int(e.price)])
		return
	var item: Dictionary = e.item.duplicate(true)
	var err := p.host_give_item(item)
	if not err.is_empty():
		_notice.rpc_id(peer, err)
		return
	p.host_add_gold(-int(e.price))
	list.remove_at(index)
	_buyback[peer] = list
	_sync_mine.rpc_id(peer, _signed.get(peer, []), _pacted.get(peer, []), list)
	game.combat.fx.sound.rpc("coin", p.global_position)
	_notice.rpc_id(peer, "Bought back %s for %d gold", [item.get("name", "item"), int(e.price)])


@rpc("any_peer", "call_local", "reliable")
func request_tithe(accept: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_at_door(peer)
	if p == null or not _is("malphas") or not accept or _paid():
		return
	var t := blood_price(int(game.layout.get("seed", 0)))
	p.host_add_run_mod(str(t.stat), float(t.value), "Demonic tithe")
	game.dungeon.leaf_door("merchant").host_unseal()
	game.combat.fx.sound.rpc("tithe", p.global_position)
	game.broadcast_message.rpc("%s breaks Malphas's blood seal (%s)", "#e04050", [p.display_name, t])


@rpc("any_peer", "call_local", "reliable")
func request_contract(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _paid() or slot < 0 or slot >= contracts.size():
		return
	var signed: Array = _signed.get(peer, [])
	if signed.has(slot):
		_notice.rpc_id(peer, "You already signed that contract")
		return
	var c: Dictionary = GameData.merchants.malphas.contracts[int(contracts[slot])]
	p.host_add_run_mod(str(c.give.stat), float(c.give.value), "Contract with Malphas")
	p.host_add_run_mod(str(c.get.stat), float(c.get.value), "Contract with Malphas")
	signed.append(slot)
	_signed[peer] = signed
	_sync_mine.rpc_id(peer, signed, _pacted.get(peer, []))
	game.combat.fx.sound.rpc("tithe", p.global_position)
	_notice.rpc_id(peer, "Signed: %s for %s", [c.give, c.get])


@rpc("any_peer", "call_local", "reliable")
func request_pact(pact_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _paid() or not GameData.pact_consumables.has(pact_id) or not pacts.has(pact_id):
		return
	var bought: Array = _pacted.get(peer, [])
	if bought.has(pact_id):
		_notice.rpc_id(peer, "You already bought that potion")
		return
	var item := ItemGenerator.generate_consumable("pact_" + pact_id, 1, rng)
	if not p.inv.can_add(item):
		_notice.rpc_id(peer, "Backpack is full")
		return
	var def: Dictionary = GameData.pact_consumables[pact_id]
	p.host_give_item(item)
	bought.append(pact_id)
	_pacted[peer] = bought
	_sync_mine.rpc_id(peer, _signed.get(peer, []), bought)
	for c in def.cost:
		p.host_add_run_mod(str(c.stat), float(c.value), def.name)
	game.combat.fx.sound.rpc("tithe", p.global_position)
	_notice.rpc_id(peer, "%s is yours. Malphas keeps %s", [def.name, def.cost])


# =========================================================================================
# Host -> peers
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _sync(new_stock: Array, new_contracts: Array, open: bool, new_pacts: Array = []) -> void:
	stock = new_stock
	contracts = new_contracts
	pacts = new_pacts
	shop_open = open
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _sync_mine(signed: Array, pacted: Array, buyback: Array = []) -> void:
	my_signed = signed
	my_pacts = pacted
	my_buyback = buyback
	changed.emit()


## Host: every hero's own Malphas record again (a restored floor, #55).
func host_sync_mine() -> void:
	for p in game.players_root.get_children():
		_sync_mine.rpc_id(p.peer_id, _signed.get(p.peer_id, []), _pacted.get(p.peer_id, []), _buyback.get(p.peer_id, []))


@rpc("authority", "call_local", "reliable")
func _open_ui(kind: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_merchant"):
		hud.open_merchant(kind)


@rpc("authority", "call_local", "reliable")
func _ask_tithe(text: String, args: Array = []) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("ask_tithe"):
		hud.ask_tithe(Loc.f(text, args))


@rpc("authority", "call_local", "reliable")
func _notice(text: String, args: Array = []) -> void:
	EventBus.hud_message.emit(Loc.f(text, args), Color(1, 0.85, 0.5))
