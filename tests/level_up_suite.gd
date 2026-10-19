class_name LevelUpSuite
extends RefCounted
## #48 level-up feedback (scenario "levelup_lan" on a LAN pair): a big XP gain that brings the
## client three levels plays the effect on the client's hero once, on the host and on the client,
## and shows the banner only on the client's screen, with the final level and all the points
## gained; a level-up of the host's hero plays on both peers and shows the banner only on the host.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func xp_for(from_level: int, levels: int) -> int:
	var total := 0
	for i in levels:
		total += Player.xp_to_next(from_level + i)
	return total + 1


static func fx_count(pl: Player) -> int:
	return int(pl.get_meta("level_up_fx_count", 0))


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var tp := int(GameData.bal("progression.talent_points_per_level"))
	var sp := int(GameData.bal("progression.stat_points_per_level"))
	# Three levels at once for the client.
	var target := c.level + 3
	c.add_xp(xp_for(c.level, 3))
	await da._wait(0.5)
	da.check(c.level == target and fx_count(c) == 1 and c.has_node("LevelUpFx"),
			"host: three levels at once play the effect on the client's hero once (level %d, %d effects)" % [c.level, fx_count(c)])
	da.check(not hud.level_banner.visible, "host: no banner for the client's level-up")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["lv_mine", [target, 3 * tp, 3 * sp]])
	await da._wait(5.0)
	# The host's own hero.
	var mine := p.level + 1
	p.add_xp(xp_for(p.level, 1))
	await da._wait(0.5)
	da.check(fx_count(p) == 1 and p.has_node("LevelUpFx"), "host: its own level-up plays the effect on its hero")
	da.check(hud.level_banner.visible and hud.level_banner.shown_level == mine and hud.level_banner.shown_talent == tp and hud.level_banner.shown_stat == sp,
			"host: the banner shows level %d, +%d talent and +%d stat points" % [mine, tp, sp])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["lv_other", [mine]])
	await da._wait(2.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	match cmd:
		"lv_mine":
			var b: LevelBanner = hud.level_banner
			da.check(p.level == int(arg[0]) and fx_count(p) == 1 and p.has_node("LevelUpFx"),
					"client: the effect plays once on its own hero (level %d, %d effects)" % [p.level, fx_count(p)])
			da.check(b.visible and b.shown_level == int(arg[0]) and b.shown_talent == int(arg[1]) and b.shown_stat == int(arg[2]),
					"client: one banner with the final level %d, +%d talent and +%d stat points (shows %d, +%d, +%d)" % [arg[0], arg[1], arg[2], b.shown_level, b.shown_talent, b.shown_stat])
			da.check(b.mouse_filter == Control.MOUSE_FILTER_IGNORE and da.get_viewport().gui_get_focus_owner() == null, "client: the banner takes no input or focus")
		"lv_other":
			var host: Player = null
			for pl in g.players_root.get_children():
				if pl.peer_id == 1:
					host = pl
			da.check(host != null and fx_count(host) == 1 and host.has_node("LevelUpFx"), "client: the host's level-up plays on the host's hero (%s, %d effects)" % [host.display_name if host else "none", fx_count(host) if host else -1])
			da.check(not hud.level_banner.visible, "client: no banner for the host's level-up")
