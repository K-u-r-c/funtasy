class_name BackgroundSuite
extends RefCounted
## #56 Host in the background (scenario "background_lan", host + client): the host's hero walks
## a circle while the client counts the distinct positions it receives per second, first with
## the host's window in front, then with it out of focus / hidden. A windowed host on Hyprland
## really moves its window to a hidden workspace (as alt-tab or another workspace does); a
## headless host gets the focus-out notification. The rate the client sees must not drop.

const PHASE_SECS := 4.0

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


## Host: real hiding only for a windowed instance on Hyprland.
static func can_hide() -> bool:
	return DisplayServer.get_name() != "headless" and OS.has_environment("HYPRLAND_INSTANCE_SIGNATURE")


func _hide(hidden: bool) -> void:
	var w := da.get_window()
	if can_hide():
		var pid := "pid:%d" % OS.get_process_id()
		if hidden:
			OS.execute("hyprctl", ["dispatch", "movetoworkspacesilent", "special:funtasy_bg," + pid])
		else:
			OS.execute("hyprctl", ["dispatch", "movetoworkspace", "e+0," + pid])
	else:
		w.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT if hidden else Node.NOTIFICATION_APPLICATION_FOCUS_IN)


## Host: main-loop frames and physics ticks per second while `secs` pass.
func _rates(secs: float) -> Vector2:
	var f0 := Engine.get_process_frames()
	var p0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	await da.get_tree().create_timer(secs).timeout
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	return Vector2((Engine.get_process_frames() - f0) / dt, (Engine.get_physics_frames() - p0) / dt)


func run_lan() -> void:
	g = da._game()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var p: Player = da._local()
	p.iframe_left = 9999.0
	var centre: Vector2 = p.global_position
	var walk := func() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		p.position = centre + Vector2(cos(t * 2.0), sin(t * 2.0)) * 24.0
	da.get_tree().physics_frame.connect(walk)
	await da._wait(1.0)
	da.log_line("hiding by %s" % ("hyprctl" if can_hide() else "focus-out notification"))
	NetworkManager.to_clients("DevAuto", "client_cmd", ["bg_measure", "front"])
	var front := await _rates(PHASE_SECS)
	await da._wait(0.5)
	_hide(true)
	await da._wait(1.0)
	var cap := int(GameData.bal("performance.background_fps", 60))
	da.check(Settings.in_background and Engine.max_fps == cap, "host: out of focus it drops V-Sync for a %d fps cap (max_fps %d)" % [cap, Engine.max_fps])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["bg_measure", "hidden"])
	var hidden := await _rates(PHASE_SECS)
	_hide(false)
	await da._wait(1.0)
	da.check(not Settings.in_background and Engine.max_fps == 0, "host: back in focus, the player's V-Sync setting and no cap return")
	da.log_line("host fps / physics per s: front %.0f / %.0f, hidden %.0f / %.0f" % [front.x, front.y, hidden.x, hidden.y])
	var ticks := float(Engine.physics_ticks_per_second)
	da.check(hidden.y > ticks * 0.9, "host: physics keeps its full rate in the background (%.0f of %.0f per s)" % [hidden.y, ticks])
	await da._wait(1.0)
	da.get_tree().physics_frame.disconnect(walk)
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	match cmd:
		"bg_measure":
			var host: Player = g.player_by_peer(1)
			var seen := 0
			var last: Vector2 = host.net_pos
			var until := Time.get_ticks_msec() + int(PHASE_SECS * 1000.0)
			while Time.get_ticks_msec() < until:
				await da.get_tree().process_frame
				if host.net_pos != last:
					seen += 1
					last = host.net_pos
			var rate := seen / PHASE_SECS
			da.log_line("host position updates per s (%s): %.1f" % [arg, rate])
			# OwnerSync streams every 0.05 s: about 17-20 updates per second at full rate.
			da.check(rate > 12.0, "client: the host's updates arrive at the full rate with its window %s (%.1f per s)" % [arg, rate])
			if arg == "front":
				da.set_meta("bg_front", rate)
			else:
				var front := float(da.get_meta("bg_front", 0.0))
				da.check(rate >= front * 0.85, "client: no slower than with the host's window in front (%.1f vs %.1f per s)" % [rate, front])
