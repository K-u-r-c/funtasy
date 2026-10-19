class_name LeverSuite
extends RefCounted
## #51 Sewers lever (scenario "lever_lan" on a LAN pair, --biome=sewers): the lever has its housing,
## an arm at the "off" angle and a red lamp; pulling it (by the client, through the interact RPC)
## swings the arm over to "on" on host and client, with in-between angles seen on both (the pull
## animation), turns the lamp green and opens its floodgate; pulling again changes nothing.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func art(lever: Node) -> Dictionary:
	return lever.def.get("lever_art", {})


## Every frame for `secs`: the arm angles of `lever` seen on this peer.
func watch(lever: Node, secs: float) -> Array:
	var seen: Array = []
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		seen.append(lever.lever_handle.rotation_degrees)
		await da.get_tree().process_frame
	return seen


static func swung(seen: Array, a: Dictionary) -> bool:
	var off := float(a.get("off", -30))
	var on := float(a.get("on", 60))
	var mid := seen.filter(func(r): return r > off + 10.0 and r < on - 10.0)
	return not mid.is_empty() and absf(float(seen[-1]) - on) < 1.0


func _find_lever() -> Node:
	for pr in g.dungeon.props.values():
		if pr.def.get("lever", false) and int(pr.get_meta("gate", -1)) >= 0:
			return pr
	return null


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	var lever: Node = _find_lever()
	# Not every Sewers floor has a floodgate (30% per door): rebuild the floor with the next seeds.
	for attempt in 12:
		if lever:
			break
		g.run_seed += 1
		g.start_floor(1)
		await da._wait(2.0)
		lever = _find_lever()
	da.check(lever != null, "a Sewers floor with a floodgate lever")
	if lever == null:
		NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
		return
	var a := art(lever)
	var door: Node = g.dungeon.doors[int(lever.get_meta("gate"))]
	da.check(lever.lever_handle != null and lever._sprite.texture == GameData.texture(str(a.base)) and absf(lever.lever_handle.rotation_degrees - float(a.off)) < 0.5
			and lever._lamp_color.r > lever._lamp_color.g and not door.is_open,
			"host: an unpulled lever shows its housing, the arm at off and a red lamp; the floodgate is shut")
	for pl in [p, c]:
		pl.iframe_left = 9999.0
	c.host_teleport(lever.global_position + Vector2(0, 16))
	p.host_teleport(g.nearest_floor(lever.global_position + Vector2(-40, 20)))
	await da._wait(0.8)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["lr_pull", str(lever.name)])
	var seen := await watch(lever, 2.0)
	da.check(swung(seen, a), "host: the client's pull swings the arm over to on (%d frames, ends at %.0f)" % [seen.size(), seen[-1]])
	da.check(lever.opened and int(lever.get_meta("lever_pulls", 0)) == 1 and lever._lamp_color.g > lever._lamp_color.r and door.is_open,
			"host: the lamp turns green and the floodgate opens")
	g.host_interact(c, lever)
	await da._wait(0.6)
	da.check(int(lever.get_meta("lever_pulls", 0)) == 1 and door.is_open and absf(lever.lever_handle.rotation_degrees - float(a.on)) < 1.0,
			"host: pulling again changes nothing; the lever stays on")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["lr_state", str(lever.name)])
	await da._wait(1.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	var lever: Node = g.dungeon.props.get(str(arg)) if arg is String else null
	match cmd:
		"lr_pull":
			var a := art(lever)
			da.check(absf(lever.lever_handle.rotation_degrees - float(a.off)) < 0.5 and lever._lamp_color.r > lever._lamp_color.g,
					"client: before the pull the arm is at off and the lamp red")
			# The real path: the interact request to the host.
			p.request_interact.rpc_id(1, lever.get_path())
			var seen := await watch(lever, 1.6)
			da.check(swung(seen, a), "client: the pull animation swings the arm over to on (%d frames)" % seen.size())
			da.check(lever.opened and lever._lamp_color.g > lever._lamp_color.r, "client: the lamp turns green")
		"lr_state":
			var door: Node = g.dungeon.doors[int(lever.get_meta("gate"))]
			da.check(int(lever.get_meta("lever_pulls", 0)) == 1 and door.is_open and absf(lever.lever_handle.rotation_degrees - float(art(lever).on)) < 1.0,
					"client: one pull, the lever stays on and the floodgate open")
