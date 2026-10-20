class_name StackSuite
extends RefCounted
## #61 Splitting stacks (scenario "stacks" solo, "stacks_lan" on a LAN pair - there the client
## does it through its own inventory screen and the host checks its authoritative copy): from
## 7 Health Potions the player drops 3 (3 on the ground, 4 in the bag, other uids), splits 2 off
## into a new slot (2 + 2), and a full backpack refuses a split with a message. The picker opens
## on Drop for a stack and not for a single item, and keeps its amount within 1..count.

var da: Node
var g: Node
var p: Player
var _messages: Array = []


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func potions(pl: Player) -> Array:
	return pl.inv.backpack.filter(func(it): return str(it.get("base", "")) == "potion_health")


static func ground_potions(gm: Node) -> Array:
	return gm.items_root.get_children().filter(func(gi): return str(gi.item.get("base", "")) == "potion_health")


## Host: a clean bag holding 7 Health Potions (and a single Mana Potion).
static func give_stack(pl: Player) -> void:
	var rng := RandomNumberGenerator.new()
	pl.inv.backpack.clear()
	pl.inv.capacity = 12
	pl.inv.add(ItemGenerator.generate_consumable("potion_health", 7, rng))
	pl.inv.add(ItemGenerator.generate_consumable("potion_mana", 1, rng))
	pl._inventory_changed()


## Owner, through the real inventory screen: the Drop key on backpack slot `i`.
func press_drop(i: int) -> Node:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	if hud._overlay == null or not hud._overlay.has_method("_open_splitter"):
		hud.open_overlay(hud.menu_panel("inventory"))
		await da._wait(0.5)
	var panel: Node = hud._overlay
	var ev := InputEventAction.new()
	ev.action = "ui_secondary"
	ev.pressed = true
	panel._slot_input(ev, panel._slots["b:%d" % i])
	await da._wait(0.2)
	return panel.get_node_or_null("StackSplitter")


func _index_of(pl: Player, base: String) -> int:
	for i in pl.inv.backpack.size():
		if str(pl.inv.backpack[i].get("base", "")) == base:
			return i
	return -1


## Owner: the whole flow on this peer; `who` names it in the checks.
func owner_flow(who: String) -> void:
	p = da._local()
	g = da._game()
	EventBus.hud_message.connect(func(t: String, _c: Color): _messages.append(t))
	var sp: Node = await press_drop(_index_of(p, "potion_health"))
	da.check(sp != null, "%s: Drop on a stack of 7 opens the amount picker" % who)
	if sp == null:
		return
	sp.set_amount(0)
	var lo: int = sp.amount()
	sp.set_amount(99)
	da.check(lo == 1 and sp.amount() == 7 and sp.split_btn.disabled, "%s: the amount stays within 1..7 (whole stack: no split)" % who)
	sp.set_amount(3)
	if not da.shot.is_empty() and DisplayServer.get_name() != "headless":
		await da._snap(da.shot.get_base_dir(), da.shot.get_file().get_basename())
	sp._choose("drop")
	await da._wait(0.8)
	var mine := potions(p)
	da.check(mine.size() == 1 and int(mine[0].count) == 4, "%s: 4 potions stay in the bag after dropping 3" % who)
	sp = await press_drop(_index_of(p, "potion_health"))
	sp.set_amount(2)
	sp._choose("split")
	await da._wait(0.8)
	mine = potions(p)
	da.check(mine.size() == 2 and int(mine[0].count) == 2 and int(mine[1].count) == 2 and mine[0].uid != mine[1].uid,
			"%s: splitting 2 off leaves two stacks of 2 with their own uids" % who)
	var single: Node = await press_drop(_index_of(p, "potion_mana"))
	await da._wait(0.6)
	da.check(single == null and _index_of(p, "potion_mana") < 0, "%s: a single potion drops at once, without the picker" % who)


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	give_stack(p)
	await da._wait(0.3)
	await owner_flow("solo")
	var ground := ground_potions(g)
	da.check(ground.size() == 1 and int(ground[0].item.count) == 3 and str(ground[0].item.uid) != str(potions(p)[0].uid),
			"3 potions lie on the ground as their own stack")
	await full_bag_refuses(p)
	da.get_tree().get_first_node_in_group("hud").close_overlay()


## Host: a full backpack refuses the split, with a message to its owner.
func full_bag_refuses(pl: Player) -> void:
	while pl.inv.free_slots() > 0:
		pl.inv.backpack.append(ItemGenerator.generate_equipment("gloves", 1, 1, RandomNumberGenerator.new()))
	pl._inventory_changed()
	await da._wait(0.3)
	var before := potions(pl).map(func(it): return int(it.count))
	if pl.is_local():
		_messages.clear()
		pl.request_split.rpc_id(1, _index_of(pl, "potion_health"), 1)
		await da._wait(0.5)
		da.check(potions(pl).map(func(it): return int(it.count)) == before and _messages.has(Loc.t("Backpack is full")),
				"a full backpack refuses the split and says so")
	else:
		NetworkManager.to_clients("DevAuto", "client_cmd", ["st_full", null])
		await da._wait(1.0)
		da.check(potions(pl).map(func(it): return int(it.count)) == before, "host: the client's full backpack refused the split")


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	give_stack(c)
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["st_flow", null])
	await da._wait(6.0)
	var mine := potions(c)
	da.check(mine.size() == 2 and int(mine[0].count) == 2 and int(mine[1].count) == 2, "host: the client's bag holds two stacks of 2")
	var ground := ground_potions(g)
	da.check(ground.size() == 1 and int(ground[0].item.count) == 3, "host: the client's 3 potions lie on the ground")
	await full_bag_refuses(c)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, _arg: Variant) -> void:
	p = da._local()
	g = da._game()
	match cmd:
		"st_flow":
			await owner_flow("client")
		"st_full":
			_messages.clear()
			EventBus.hud_message.connect(func(t: String, _c: Color): _messages.append(t))
			p.request_split.rpc_id(1, _index_of(p, "potion_health"), 1)
			await da._wait(0.6)
			da.check(_messages.has(Loc.t("Backpack is full")), "client: told its backpack is full")
