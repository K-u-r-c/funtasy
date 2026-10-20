class_name MarkerSuite
extends RefCounted
## #59 Your own hero (scenario "marker_lan", host + 3 clients, all the same class): the four
## heroes stand close together; on every peer only its own hero has the bright ring and the pin,
## the others a faint ring; the own marker shows only while Dodge is held a moment (or while downed)
## and goes for a ghost; the setting
## turns all markers off. With --shot=<dir>/<name> (windowed instances) every peer saves a
## screenshot: <name>_host.png, <name>_<peer>.png, and <name>_off_* with the setting off.

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func marker(pl: Player) -> HeroMarker:
	return pl.get_node_or_null("HeroMarker") as HeroMarker


## On this peer: only the own hero is marked as "you", every teammate as a teammate.
func check_marks(who: String) -> void:
	HeroMarker.test_hold = false
	await da._wait(0.5)
	var lp: Player = g.local_player
	da.check(not marker(lp).visible and HeroMarker.reveal_of(lp) == 0.0, "%s: the own marker is hidden while Dodge isn't held" % who)
	HeroMarker.test_hold = true
	await da._wait(0.2)
	da.check(HeroMarker.reveal_of(lp) == 0.0, "%s: a short Dodge press doesn't show it" % who)
	await da._wait(0.5)
	var own := 0
	var mates := 0
	var wrong := []
	for pl in g.players_root.get_children():
		var m := marker(pl)
		var want := 2 if pl.is_local() else 1
		if m == null or m.mode() != want or not m.visible:
			wrong.append(pl.display_name)
		elif want == 2:
			own += 1
		else:
			mates += 1
	da.check(wrong.is_empty() and own == 1 and mates == g.players_root.get_child_count() - 1,
			"%s: holding Dodge, only its own hero carries the bright ring and pin, %d teammates a faint ring%s" % [who, mates, "" if wrong.is_empty() else " (wrong: %s)" % [wrong]])


func check_off(who: String) -> void:
	Settings.hero_marker = false
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	var shown: Array = g.players_root.get_children().filter(func(pl): return marker(pl).visible)
	da.check(shown.is_empty(), "%s: with the setting off no hero is marked" % who)


func snap(tag: String) -> void:
	if da.shot.is_empty() or DisplayServer.get_name() == "headless":
		return
	await da._snap(da.shot.get_base_dir(), "%s_%s" % [da.shot.get_file().get_basename(), tag])


func run_lan() -> void:
	g = da._game()
	await da._wait_until(func(): return g.players_root.get_child_count() >= da.wanted_players, 15.0)
	da.check(g.players_root.get_child_count() >= 4, "four heroes in the run")
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	# A tight huddle in the start room: the hard case.
	var offs := [Vector2(-18, -6), Vector2(14, -10), Vector2(-8, 14), Vector2(20, 10)]
	var i := 0
	for pl in g.players_root.get_children():
		pl.iframe_left = 9999.0
		pl.host_teleport(g.nearest_floor(g.layout.start) + offs[i % offs.size()])
		i += 1
	await da._wait(1.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["mk_check", null])
	await check_marks("host")
	await snap("host")
	await da._wait(1.5)
	# Downed: the owner still finds its hero; a ghost isn't marked.
	var c: Player = da._other_player()
	c.life_state = Player.Life.DOWNED
	c.downed_left = 30.0
	await da._wait(0.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["mk_downed", c.peer_id])
	await da._wait(1.0)
	c.life_state = Player.Life.GHOST
	await da._wait(0.6)
	da.check(not marker(c).visible, "host: a ghost carries no marker")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["mk_ghost", c.peer_id])
	await da._wait(1.0)
	c.life_state = Player.Life.ALIVE
	await da._wait(0.6)
	await check_off("host")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["mk_off", null])
	await snap("off_host")
	await da._wait(2.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var who := "client %d" % da.multiplayer.get_unique_id()
	match cmd:
		"mk_check":
			await check_marks(who)
			await snap(str(da.multiplayer.get_unique_id()))
		"mk_downed":
			HeroMarker.test_hold = false
			await da._wait(0.4)
			var pl: Player = g.player_by_peer(int(arg))
			if pl.is_local():
				da.check(pl.life_state == Player.Life.DOWNED and marker(pl).mode() == 2 and marker(pl).visible,
						"%s: its downed hero keeps its own marker" % who)
		"mk_ghost":
			var pl: Player = g.player_by_peer(int(arg))
			da.check(not marker(pl).visible, "%s: a ghost carries no marker" % who)
		"mk_off":
			await check_off(who)
			await snap("off_%d" % da.multiplayer.get_unique_id())
