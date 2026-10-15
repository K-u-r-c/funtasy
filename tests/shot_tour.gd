class_name ShotTour
extends RefCounted
## Windowed screenshot tours for the visual review after each phase (scenario "tour"):
##   godot --path . -- --auto=solo --scenario=tour --tour=combat --window=1920x1080 --shot=/tmp/tour --class=mage
## Every tour saves PNGs named <tour>_<step>_<width>x<height>.png into the --shot directory.

var da: Node
var dir := ""
var g: Node
var p: Player


func _init(dev_auto: Node, out_dir: String) -> void:
	da = dev_auto
	dir = out_dir


func run(tour: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	g = da._game()
	p = da._local()
	await da._wait(1.5)
	match tour.get_slice(":", 0):
		"combat":
			await _combat()
		_:
			if has_method("_" + tour.get_slice(":", 0)):
				await call("_" + tour.get_slice(":", 0), tour.get_slice(":", 1))
			else:
				da.check(false, "unknown tour '%s'" % tour)


func snap(name_: String) -> void:
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	var img := da.get_viewport().get_texture().get_image()
	var path := dir.path_join("%s_%dx%d.png" % [name_, img.get_width(), img.get_height()])
	img.save_png(path)
	da.log_line("shot %s" % path)


## Clears the start room and puts dummies in front of the hero.
func arena(count: int = 3) -> Array:
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var start: Vector2 = g.layout.start
	p.host_teleport(start)
	p.iframe_left = 9999.0
	var out: Array = []
	for i in count:
		out.append(g.spawn_monster("training_dummy", g.nearest_floor(start + Vector2(70 + 34 * i, -20 + 22 * (i % 2))), false))
	await da._wait(0.5)
	return out


func cast(sid: String, aim: Vector2) -> void:
	p.cooldowns.erase(sid)
	p.resource.value = p.resource.max_value
	p.auto_aim = aim
	Combat.instance.try_use_skill(p, sid, aim)
	if GameData.skill(sid).has("charge_time"):
		await da._wait(float(GameData.skill(sid).charge_time))
		Combat.instance.release_charge(p, aim)


## Phase 1: the new effect primitives and statuses on training dummies.
func _combat() -> void:
	var d := await arena(4)
	var aim: Vector2 = d[0].global_position
	var steps := [["chain", "test_chain"], ["beam", "test_beam"], ["fire_wall", "test_terrain"], ["tether", "test_tether"],
		["blizzard", "test_chill_freeze"], ["turret", "test_deploy"], ["delayed", "test_delayed"]]
	for s in steps:
		await cast(s[1], aim)
		await da._wait(0.18 if s[0] in ["chain", "beam"] else 0.9)
		await snap("combat_%s" % s[0])
		await da._wait(0.4)
	var ctx := Combat.instance.make_ctx(p, GameData.skill("test_hit"))
	for st in ["stun", "poison", "burn", "chill", "armor_shred", "revealed"]:
		Combat.instance.apply_status(ctx, d[0], st, 8.0, 2.0)
	for st2 in ["fortify", "battle_cry", "haste_potion"]:
		p.status.apply(st2, 8.0, 0.0, ctx)
	await da._wait(0.6)
	await snap("combat_statuses")


## Every game menu tab (and later dialogs) with some progress to show.
func _menus(_arg: String) -> void:
	p.add_xp(Player.xp_to_next(p.level))
	p.add_xp(Player.xp_to_next(p.level))
	p.host_add_run_mod("strength", 2.0, "Ossuary Masonry")
	p.host_add_run_mod("max_hp", -10.0, "Demonic tithe")
	p.host_add_gold(125)
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for t in UIModal.MENU_TABS:
		hud.open_overlay(hud.menu_panel(t[0]))
		await da._wait(0.6)
		await snap("menu_%s" % t[0])
	hud.close_overlay()


## The merchant chamber, Archibald's shop, the tithe dialog and Malphas's bargains.
func _merchants(_arg: String) -> void:
	var m: Dictionary = g.layout.get("merchant", {})
	if m.is_empty():
		da.check(false, "floor has a merchant chamber")
		return
	p.iframe_left = 9999.0
	p.host_add_gold(400)
	p.host_teleport((m.archibald + m.malphas) / 2.0 + Vector2(0, 40))
	await da._wait(1.0)
	await snap("merchant_chamber")
	g.add_party_key(1)
	p.host_teleport(m.portal + Vector2(0, 18))
	await da._wait(0.3)
	g.host_interact(p, g.dungeon.props["Merchant_Portal"])
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_merchant("archibald")
	await da._wait(0.6)
	await snap("merchant_shop")
	hud.close_overlay()
	p.host_teleport(m.altar + Vector2(0, 18))
	await da._wait(0.3)
	g.host_interact(p, g.dungeon.props["Merchant_Altar"])
	await da._wait(0.6)
	await snap("merchant_tithe")
	hud.close_overlay()
	g.merchants.request_tithe.rpc_id(1, true)
	await da._wait(0.8)
	await snap("merchant_pacts")
	hud.close_overlay()
