class_name TeleportSuite
extends RefCounted
## #57 Next floor (scenario "teleport_lan", host + 2 clients): the heroes stand far apart on
## floor 1, the party descends, and every peer samples every hero (and its own camera) each
## frame for the first moments of floor 2 (the clients get their teleport late, as over a slow
## link). No copy of any hero may be seen between its old spot
## and its new one at the start, and the camera may not pan across the map.

const WATCH_SECS := 1.5
const NEAR := 40.0  ## px: a sample this close to the old or the new spot isn't "in between"

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Waits for the next floor, then fills `out` with {heroes: {peer: [old, samples]}, cam: [old,
## samples]} and sets out.done.
func watch_into(out: Dictionary) -> void:
	await EventBus.floor_started
	var heroes := {}
	for pl in g.players_root.get_children():
		heroes[pl.peer_id] = [pl.global_position, []]
	var cam_old: Vector2 = g.camera.get_screen_center_position()
	var cam: Array = []
	var until := Time.get_ticks_msec() + int(WATCH_SECS * 1000.0)
	while Time.get_ticks_msec() < until:
		await da.get_tree().process_frame
		for pl in g.players_root.get_children():
			if heroes.has(pl.peer_id):
				heroes[pl.peer_id][1].append(pl.global_position)
		cam.append(g.camera.get_screen_center_position())
	out["heroes"] = heroes
	out["cam"] = [cam_old, cam]
	out["done"] = true


## Samples farther than NEAR from both the old and the final spot.
static func between(old: Vector2, samples: Array) -> int:
	if samples.is_empty():
		return 0
	var final: Vector2 = samples[-1]
	return samples.filter(func(s): return s.distance_to(old) > NEAR and s.distance_to(final) > NEAR).size()


func judge(who: String, out: Dictionary) -> void:
	for peer in out.heroes:
		var h: Array = out.heroes[peer]
		var final: Vector2 = h[1][-1] if not h[1].is_empty() else h[0]
		var n := between(h[0], h[1])
		da.check(n == 0, "%s: hero %d appears at the start without flying across the map (%d of %d frames in between, moved %.0f px)"
				% [who, peer, n, h[1].size(), h[0].distance_to(final)])
		da.check(final.distance_to(g.layout.start) < 80.0, "%s: hero %d ends in the start room" % [who, peer])
	var n_cam := between(out.cam[0], out.cam[1])
	da.check(n_cam == 0, "%s: the camera snaps to the start room (%d of %d frames panning)" % [who, n_cam, out.cam[1].size()])


func run_lan() -> void:
	g = da._game()
	await da._wait_until(func(): return g.players_root.get_child_count() >= da.wanted_players, 15.0)
	da.check(g.players_root.get_child_count() >= 3, "three heroes in the run")
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	# Spread the heroes over the rooms farthest from the start, so the next floor's start is far
	# from where each of them stands.
	var rooms: Array = g.layout.rooms.duplicate()
	rooms.sort_custom(func(a, b): return _room_center(a).distance_to(g.layout.start) > _room_center(b).distance_to(g.layout.start))
	var i := 0
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
		pl.host_teleport(g.nearest_floor(_room_center(rooms[i % rooms.size()])))
		i += 1
	await da._wait(2.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tp_watch", null])
	await da._wait(0.5)
	var out := {}
	watch_into(out)
	g.start_floor(2)
	await da._wait_until(func(): return out.has("done"), 5.0)
	judge("host", out)
	# #58: floor 2 is already a little bigger, and every peer builds the same layout.
	da.check(g.layout.size != Vector2i(g.floor_def.grid[0], g.floor_def.grid[1]),
			"host: floor 2 is a little bigger than floor 1's grid (%s)" % g.layout.size)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tp_layout", [g.layout.size, g.layout.rooms.size(), g.layout.start]])
	# The clients judge on their own and finish when the host closes the session.
	await da._wait(2.0)


func _room_center(room: Dictionary) -> Vector2:
	return g.dungeon.cell_center(Rect2i(room.rect).get_center())


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	match cmd:
		"tp_watch":
			# The teleport reaches this owner late (as over Wi-Fi or a Steam relay) while it keeps
			# streaming its old position: the stale stream must not move any copy of the hero.
			GameState.set_meta("test_teleport_lag", 0.3)
			var out := {}
			watch_into(out)
			await da._wait_until(func(): return out.has("done"), 8.0)
			da.check(out.has("done"), "client: floor 2 started")
			if out.has("done"):
				judge("client %d" % da.multiplayer.get_unique_id(), out)
		"tp_layout":
			var lay: Array = arg
			da.check(g.layout.size == lay[0] and g.layout.rooms.size() == lay[1] and g.layout.start == lay[2],
					"client: the same floor 2 layout as the host (%s, %d rooms)" % [g.layout.size, g.layout.rooms.size()])
