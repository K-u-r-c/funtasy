class_name InteractSuite
extends RefCounted
## #35 several things at one spot (scenario "interact" solo, "interact_lan" on a LAN pair):
## - an item lying in a doorway comes first and Interact picks it up; "interact_next" switches to
##   the door, which then opens / closes; the HUD prompt shows "1/2" with the switch button;
## - with a full backpack, and with a backpack no bigger than the hero's lying there, the door
##   comes first and the item is still selectable, its prompt saying why it can't be taken;
## - loot dropped on a doorway lands on the floor beside it.

var da: Node
var g: Node
var p: Player
var _n := 0


func _init(dev_auto: Node) -> void:
	da = dev_auto


## A plain door (not sealed, not a floodgate or bookshelf) and the floor cell beside it.
func plain_door() -> Node:
	for d in g.dungeon.doors:
		if d.kind.is_empty() and not d.sealed and not d.floodgate and d.style != "bookshelf":
			return d
	return null


## Host: an item put exactly in the doorway (no drop nudge), like one a player threw there.
func put_in_doorway(item: Dictionary, door: Node) -> Node:
	_n += 1
	var name_ := "Item_ia%d" % _n
	g.loot.spawner.spawn({"name": name_, "pos": door.world_rect.get_center(), "item": item})
	await da._wait(0.3)
	return g.items_root.get_node_or_null(name_)


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	p.iframe_left = 9999.0
	for e in g.enemies_root.get_children():
		e.queue_free()
	var door := plain_door()
	da.check(door != null, "the floor has a plain door")
	if door == null:
		return
	door.host_set_open(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var sword := ItemGenerator.generate_equipment("sword", 1, 2, rng)
	var gi: Node = await put_in_doorway(sword, door)
	p.host_teleport(g.floor_beside_door(door.world_rect.get_center()))
	p.auto_aim = door.world_rect.get_center()
	await da._wait(0.4)
	var t0: Dictionary = g.find_interactable(p, 0)
	var t1: Dictionary = g.find_interactable(p, 1)
	da.check(gi != null and t0.get("node") == gi and int(t0.get("count", 0)) >= 2 and t1.get("node") == door,
			"an item in a doorway comes first, the door is the next choice (%s / %s, %d things)" % [t0.get("kind"), t1.get("kind"), int(t0.get("count", 0))])
	# The switch action (G / left stick click) moves the choice; the HUD shows 2/2 and its button.
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da._action("interact_next")
	await da._wait(0.2)
	da.check(p._interact_pick == 1 and hud._prompt_more.visible and hud._prompt_count.text == "2/%d" % int(t0.count) and hud._prompt.text == door.interact_text(),
			"interact_next switches to the door: prompt '%s' %s" % [hud._prompt.text, hud._prompt_count.text])
	p.request_interact.rpc_id(1, door.get_path())
	await da._wait(0.4)
	da.check(door.is_open and is_instance_valid(gi), "Interact on the switched choice opens the door; the item stays")
	p.request_interact.rpc_id(1, door.get_path())
	await da._wait(0.4)
	da.check(not door.is_open, "... and closes it again")
	var bag := p.inv.backpack.size()
	p.request_interact.rpc_id(1, gi.get_path())
	await da._wait(0.4)
	da.check(not is_instance_valid(gi) and p.inv.backpack.size() == bag + 1, "Interact on the item picks it up")
	# A full backpack: the door comes first, the item says why it can't be taken.
	while p.inv.free_slots() > 0:
		p.host_give_item(ItemGenerator.generate_equipment("axe", 1, 1, rng))
	await da._wait(0.3)
	var gi2: Node = await put_in_doorway(ItemGenerator.generate_equipment("mace", 1, 2, rng), door)
	await da._wait(0.3)
	var f0: Dictionary = g.find_interactable(p, 0)
	var f1: Dictionary = g.find_interactable(p, 1)
	da.check(f0.get("node") == door and f1.get("node") == gi2 and str(f1.text).contains(Loc.t("Backpack is full")),
			"with a full backpack the door comes first and the item says why (%s)" % f1.get("text", ""))
	p.request_interact.rpc_id(1, gi2.get_path())
	await da._wait(0.4)
	da.check(is_instance_valid(gi2), "the host keeps the item on the ground when the backpack is full")
	gi2.queue_free()
	for i in range(p.inv.backpack.size() - 1, bag, -1):
		p.inv.backpack.remove_at(i)
	p._inventory_changed()
	await da._wait(0.3)
	# A backpack no bigger than the hero's own.
	var small := ItemGenerator.generate_backpack(1, rng)
	small.capacity = p.inv.capacity
	var gi3: Node = await put_in_doorway(small, door)
	await da._wait(0.3)
	var s0: Dictionary = g.find_interactable(p, 0)
	var s1: Dictionary = g.find_interactable(p, 1)
	da.check(s0.get("node") == door and s1.get("node") == gi3 and str(s1.text).contains(Loc.t("You already have a backpack this big")),
			"a backpack no bigger than the hero's doesn't hide the door and says why (%s)" % s1.get("text", ""))
	gi3.queue_free()
	await da._wait(0.2)
	# Loot dropped on a doorway lands beside it.
	g.loot.drop_item(ItemGenerator.generate_equipment("bow", 1, 1, rng), door.world_rect.get_center())
	await da._wait(0.3)
	var in_door := 0
	for it in g.items_root.get_children():
		if g.in_doorway(it.global_position):
			in_door += 1
	da.check(in_door == 0, "loot dropped on a doorway lands on the floor beside it")
	p.auto_aim = Vector2.INF


# --- LAN ------------------------------------------------------------------------------------


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	c.iframe_left = 9999.0
	var door := plain_door()
	door.host_set_open(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	await put_in_doorway(ItemGenerator.generate_equipment("sword", 1, 2, rng), door)
	c.host_teleport(g.floor_beside_door(door.world_rect.get_center()))
	await da._wait(0.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["ia_door", g.dungeon.doors.find(door)])
	await da._wait(1.5)
	da.check(door.is_open, "the client's switched choice opens the door on the host")
	await da._wait(0.5)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"ia_door":
			var door: Node = g.dungeon.doors[int(arg)]
			p.auto_aim = door.world_rect.get_center()
			await da._wait(0.3)
			var t0: Dictionary = g.find_interactable(p, 0)
			var t1: Dictionary = g.find_interactable(p, 1)
			da.check(t0.get("kind") == "item" and t1.get("node") == door, "the client sees the item first and the door as the next choice")
			p.request_interact.rpc_id(1, door.get_path())
			p.auto_aim = Vector2.INF
