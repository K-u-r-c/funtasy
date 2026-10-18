class_name PartySuite
extends RefCounted
## #37 teammates' effects on the party frames (scenario "party_lan" on a LAN pair, data checks in
## "party"): every status effect has an icon; a buff and a debuff on a teammate show on the other
## peer's party frame as icons (debuff first, stacks, a tooltip with the name and time) and go
## away when they end.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Solo: data and the frame's own logic.
func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var missing: Array = []
	for id in GameData.status_effects:
		if not str(id).begins_with("test_") and StatusChip_icon(id).is_empty():
			missing.append(id)
	da.check(missing.is_empty(), "every status effect has an icon (missing: %s)" % [missing.slice(0, 8)])
	var order: Array = HUDScript.StatusChip.ordered([["renew", 8.0, 1], ["poison", 5.0, 2], ["bleed", 2.0, 1], ["fortify", -1.0, 1]])
	da.check(order.map(func(s): return s[0]) == ["bleed", "poison", "renew", "fortify"],
			"effects are ordered debuffs first, the soonest to end first (%s)" % [order.map(func(s): return s[0])])


const HUDScript := preload("res://scripts/ui/hud.gd")


static func StatusChip_icon(id: String) -> String:
	return HUDScript.StatusChip.icon_key(id)


## The frame showing `pl` in the local HUD.
func frame_of(pl: Player) -> Node:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for f in hud._party_box.get_children():
		if f.visible and f.p == pl:
			return f
	return null


static func shown_ids(frame: Node) -> Array:
	var out: Array = []
	for c in frame._effects.get_children():
		if c.visible and c.get("_id") != null:
			out.append(c._id)
	return out


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
	# The client gets a buff and a debuff: the host's frame for the client shows both.
	c.status.apply("renew", 6.0, 1.0, p)
	c.status.apply("poison", 4.0, 1.0, null)
	c.status.apply("poison", 4.0, 1.0, null)
	await da._wait(0.6)
	var f: Node = frame_of(c)
	var ids: Array = shown_ids(f) if f else []
	da.check(f != null and ids.size() >= 2 and ids[0] == "poison" and ids.has("renew"),
			"the host's party frame shows the client's debuff first and its buff (%s)" % [ids])
	var chip: Node = f._effects.get_child(0) if f else null
	da.check(chip != null and int(chip._stacks) == 2 and chip.tooltip_text.begins_with(Loc.t("Poison")) and chip.tooltip_text.contains("s"),
			"the debuff icon shows its stacks and a tooltip with name and time (%s)" % [chip.tooltip_text if chip else ""])
	# The host's own effects travel to the client's frame for the host.
	p.status.apply("fortify", 5.0, 1.0, p)
	p.status.apply("burn", 3.0, 1.0, null)
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["pt_has", ["burn", "fortify"]])
	await da._wait(1.0)
	c.status.remove("renew")
	c.status.remove("poison")
	await da._wait(0.5)
	da.check(f != null and shown_ids(f).is_empty(), "the effects leave the frame when they end")
	p.status.remove("fortify")
	p.status.remove("burn")
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["pt_has", []])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"pt_has":
			var host: Player = null
			for pl in g.players_root.get_children():
				if pl != p:
					host = pl
			var f: Node = frame_of(host)
			var ids: Array = shown_ids(f) if f else []
			var want: Array = arg
			da.check(f != null and want.all(func(x): return ids.has(x)) and ids.size() == want.size() and (want.is_empty() or ids[0] == "burn"),
					"the client's party frame for the host shows %s (%s)" % [want, ids])
