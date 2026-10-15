class_name Merchants
extends Node
## The merchant chamber of every floor (GDD 5): Archibald the Gilded behind the Gilded Portal
## (needs the party's Gold Key, D11) and Malphas the Soul Broker behind the Demon Altarpiece
## (a blood tithe once per player per floor, D13). Host-authoritative: the stock, the open portal
## and the contracts are replicated to everyone; every purchase is a host-validated intent.
##
## RPCs (all on this node, the same path on every peer):
## - request_buy(index) / request_sell(backpack index) / request_tithe(accept) /
##   request_contract(index) / request_pact(id): owner -> host, reliable.
## - _sync(stock, contracts, portal_open), _open_ui(kind), _ask_tithe(text), _notice(text):
##   host -> peers, reliable.

signal changed

var game: Node
var stock: Array = []  ## every peer: [{item, price, left}]
var contracts: Array = []  ## every peer: indices into merchants.malphas.contracts
var portal_open := false
var _tithe: Dictionary = {}  ## host: peer -> {"stat", "value"} rolled, "paid": bool
var _signed: Dictionary = {}  ## host: peer -> [contract slots signed this floor]
var rng := RandomNumberGenerator.new()


# =========================================================================================
# Host
# =========================================================================================


func host_new_floor(floor_seed: int, item_level: int) -> void:
	rng.seed = floor_seed + 777
	_tithe.clear()
	_signed.clear()
	portal_open = false
	var a: Dictionary = GameData.merchants.get("archibald", {})
	var st: Array = []
	var rar: Array = a.get("rarity", [2, 3])
	for i in int(a.get("equipment", 3)):
		var base := LootTable.pick_base(GameState.classes_in_party(), rng)
		var it := ItemGenerator.generate_equipment(base, item_level, rng.randi_range(int(rar[0]), int(rar[1])), rng)
		st.append({"item": it, "price": buy_price(it), "left": 1})
	var cons: Dictionary = a.get("consumables", {})
	for cid in cons:
		var ci := ItemGenerator.generate_consumable(str(cid), 1, rng)
		st.append({"item": ci, "price": buy_price(ci), "left": int(cons[cid])})
	stock = st
	var pool: Array = GameData.merchants.get("malphas", {}).get("contracts", [])
	var idx: Array = range(pool.size())
	var picked: Array = []
	for i in mini(int(GameData.merchants.get("malphas", {}).get("contracts_per_floor", 2)), idx.size()):
		picked.append(idx.pop_at(rng.randi_range(0, idx.size() - 1)))
	contracts = picked
	_sync.rpc(stock, contracts, portal_open)


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
	return roundi(float(tiers[r - 1]) * (1.0 + float(GameData.bal("merchant.per_item_level")) * (int(item.get("ilvl", 1)) - 1)))


static func buy_price(item: Dictionary) -> int:
	return maxi(1, roundi(item_value(item) * float(GameData.bal("merchant.buy_mult"))))


static func sell_price(item: Dictionary) -> int:
	var each := roundi(item_value(item) * float(GameData.bal("merchant.sell_mult")))
	return maxi(each, 0)


## Host: a player interacted with a merchant chamber piece.
func host_interact(p: Player, node: Node) -> void:
	var d: Dictionary = node.def
	match str(d.get("gate", d.get("npc", ""))):
		"gilded":
			if portal_open:
				_notice.rpc_id(p.peer_id, "The Gilded Portal is open: trade with Archibald")
			elif game.party_keys > 0:
				game.add_party_key(-1)
				portal_open = true
				game.dungeon.open_chest.rpc(node.prop_id)
				game.combat.fx.sound.rpc("key_unlock", node.global_position)
				game.broadcast_message.rpc("%s opens the Gilded Portal with the Gold Key" % p.display_name, "#f0c850")
				_sync.rpc(stock, contracts, portal_open)
			else:
				_notice.rpc_id(p.peer_id, "The Gilded Portal needs a Gold Key (elites may carry one)")
		"archibald":
			if portal_open:
				game.combat.fx.sound.rpc("merchant_chime", node.global_position)
				_open_ui.rpc_id(p.peer_id, "archibald")
			else:
				_notice.rpc_id(p.peer_id, "Archibald waits behind the locked Gilded Portal")
		"demonic", "malphas":
			if _paid(p):
				_open_ui.rpc_id(p.peer_id, "malphas")
			else:
				var t: Dictionary = _tithe_for(p)
				_ask_tithe.rpc_id(p.peer_id, "Crossing the threshold costs a blood tithe: %s for the rest of the run." % mod_text(t))


func _paid(p: Player) -> bool:
	return bool(_tithe.get(p.peer_id, {}).get("paid", false))


func _tithe_for(p: Player) -> Dictionary:
	if not _tithe.has(p.peer_id):
		var opts: Array = GameData.merchants.get("malphas", {}).get("tithe", [])
		_tithe[p.peer_id] = opts[rng.randi_range(0, opts.size() - 1)].duplicate()
	return _tithe[p.peer_id]


func _player_near(peer: int) -> Player:
	var p: Player = game.player_by_peer(peer) if game else null
	if p == null or p.life_state != Player.Life.ALIVE or game.layout.get("merchant", {}).is_empty():
		return null
	var m: Dictionary = game.layout.merchant
	var r := float(GameData.bal("merchant.interact_range"))
	if p.global_position.distance_to(m.archibald) > r and p.global_position.distance_to(m.malphas) > r:
		return null
	return p


static func stat_name(k: String) -> String:
	return {"max_hp": "Max Health", "max_hp_pct": "Max Health", "crit_chance": "Critical Strike Chance",
		"move_speed": "Movement Speed", "max_resource": "Max Mana"}.get(k, k.replace("_", " ").capitalize())


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
	if p == null or not portal_open or index < 0 or index >= stock.size():
		return
	var e: Dictionary = stock[index]
	if int(e.left) <= 0:
		_notice.rpc_id(peer, "Sold out")
		return
	if p.gold < int(e.price):
		_notice.rpc_id(peer, "Not enough gold (%d needed)" % int(e.price))
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
	_sync.rpc(stock, contracts, portal_open)
	_notice.rpc_id(peer, "Bought %s for %d gold" % [item.get("name", "item"), int(e.price)])


@rpc("any_peer", "call_local", "reliable")
func request_sell(backpack_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not portal_open:
		return
	if backpack_index < 0 or backpack_index >= p.inv.backpack.size():
		return
	var item: Dictionary = p.inv.backpack[backpack_index]
	var price := sell_price(item)
	if price <= 0:
		_notice.rpc_id(peer, "Archibald won't buy that")
		return
	if item.get("kind", "") == "consumable" and int(item.get("count", 1)) > 1:
		p.inv.consume(str(item.base))
	else:
		p.inv.take_backpack(backpack_index)
	p.host_add_gold(price)
	p._inventory_changed()
	game.combat.fx.sound.rpc("coin", p.global_position)
	_notice.rpc_id(peer, "Sold %s for %d gold" % [item.get("name", "item"), price])


@rpc("any_peer", "call_local", "reliable")
func request_tithe(accept: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not accept or _paid(p):
		return
	var t := _tithe_for(p)
	t.paid = true
	p.host_add_run_mod(str(t.stat), float(t.value), "Demonic tithe")
	game.combat.fx.sound.rpc("tithe", p.global_position)
	_notice.rpc_id(peer, "Malphas takes his tithe: %s" % mod_text(t))
	_open_ui.rpc_id(peer, "malphas")


@rpc("any_peer", "call_local", "reliable")
func request_contract(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _paid(p) or slot < 0 or slot >= contracts.size():
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
	game.combat.fx.sound.rpc("tithe", p.global_position)
	_notice.rpc_id(peer, "Signed: %s for %s" % [mod_text(c.give), mod_text(c.get)])


@rpc("any_peer", "call_local", "reliable")
func request_pact(pact_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _player_near(peer)
	if p == null or not _paid(p) or not GameData.pact_consumables.has(pact_id):
		return
	var item := ItemGenerator.generate_consumable("pact_" + pact_id, 1, rng)
	if not p.inv.can_add(item):
		_notice.rpc_id(peer, "Backpack is full")
		return
	var def: Dictionary = GameData.pact_consumables[pact_id]
	p.host_give_item(item)
	for c in def.cost:
		p.host_add_run_mod(str(c.stat), float(c.value), def.name)
	game.combat.fx.sound.rpc("tithe", p.global_position)
	_notice.rpc_id(peer, "%s is yours. Malphas keeps %s" % [def.name, ", ".join(def.cost.map(func(c): return mod_text(c)))])


# =========================================================================================
# Host -> peers
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _sync(new_stock: Array, new_contracts: Array, open: bool) -> void:
	stock = new_stock
	contracts = new_contracts
	portal_open = open
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _open_ui(kind: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_merchant"):
		hud.open_merchant(kind)


@rpc("authority", "call_local", "reliable")
func _ask_tithe(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("ask_tithe"):
		hud.ask_tithe(text)


@rpc("authority", "call_local", "reliable")
func _notice(text: String) -> void:
	EventBus.hud_message.emit(text, Color(1, 0.85, 0.5))
