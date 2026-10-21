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
	if is_instance_valid(p):
		var sp := p.get_global_transform_with_canvas().origin
		da.log_line("hero_at %s %d %d" % [name_, roundi(sp.x), roundi(sp.y)])
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


## #25: the hero crossing a room at a slowed walk, the normal running speed and hasted, one shot
## every other frame (assembled into a strip / animation for the review).
func _gait(_arg: String) -> void:
	var ctx := Combat.instance.make_ctx(p, GameData.skill("test_hit"))
	for c in [["run", []], ["haste", ["battle_cry", "haste_potion"]], ["slowed", ["slow"]]]:
		p.status.clear_all()
		for st in c[1]:
			p.status.apply(st, 30.0, 0.0, ctx)
		p.host_teleport(g.nearest_floor(g.layout.start + Vector2(-140, 0)))
		await da._wait(1.5)
		Input.action_press("move_right")
		await da._wait(0.35)
		for i in 24:
			await da.get_tree().process_frame
			await snap("gait_%s_%02d" % [c[0], i])
			da.log_line("gait_pos %s %d %s" % [c[0], i, p.get_global_transform_with_canvas().origin])
		Input.action_release("move_right")
		await da._wait(0.4)
	p.status.clear_all()


## #28: the whole floor discovered, the map with the merchant's sign and the boss mark, and the
## minimap next to the merchant door.
func _map_marks(_arg: String) -> void:
	var d: Dungeon = g.dungeon
	d.discovered.fill(1)
	var door: Node = d.leaf_door("merchant")
	p.host_teleport(g.nearest_floor(door.world_rect.get_center() + Vector2(0, 64)))
	await da._wait(1.2)
	await snap("map_marks_minimap_%s" % g.merchant_id)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.menu_panel("map"))
	await da._wait(0.6)
	await snap("map_marks_map_%s" % g.merchant_id)
	hud.close_overlay()


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


## #45: an over-spent save loads refunded (the message), a level-up (the message), then the
## character and talent screens with the new points.
func _points(_arg: String) -> void:
	var keep: Dictionary = GameState.characters.get(p.peer_id, {})
	var ch: Dictionary = p.to_character()
	ch.level = 6
	var spent := {}
	var n := 0
	for nd in p.talent_tree().nodes:
		if nd.get("type", "") == "passive" and not p.is_free_node(nd) and n < 15:
			spent[nd.id] = mini(int(nd.get("max_rank", 1)), 15 - n)
			n += int(spent[nd.id])
	ch.talents = spent
	ch.allocated = {"strength": 30, "stamina": 20}
	GameState.characters[p.peer_id] = ch
	p._host_init()
	await da._wait(2.4)
	await snap("points_refunded")
	await da._wait(3.0)
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.4)
	await snap("points_level_up")
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for t in ["character", "talents"]:
		hud.open_overlay(hud.menu_panel(t))
		await da._wait(0.6)
		await snap("points_%s" % t)
	hud.close_overlay()
	GameState.characters[p.peer_id] = keep


## Options from the pause menu (#32): the Video tab with the language choice, then Polish
## picked there (the window and, after closing, the HUD in the new language).
func _options(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(preload("res://scripts/ui/pause_menu.gd").new())
	await da._wait(0.4)
	hud._overlay._open_settings()
	await da._wait(0.6)
	await snap("options_video_%s" % Settings.language)
	var menu: Node = hud._overlay.get_child(hud._overlay.get_child_count() - 1)
	var other := "pl" if Settings.language == "en" else "en"
	for i in menu._lang_opt.item_count:
		if str(menu._lang_opt.get_item_metadata(i)) == other:
			menu._lang_opt.select(i)
			menu._lang_opt.item_selected.emit(i)
	await da._wait(0.8)
	await snap("options_video_%s" % other)
	menu._close()
	await da._wait(1.0)
	await snap("options_hud_%s" % other)


## #35: an item lying in a doorway (the prompt shows 1/2 and the switch button), then the door
## picked with "interact_next".
func _interact(_arg: String) -> void:
	var ia := InteractSuite.new(da)
	ia.g = g
	ia.p = p
	for e in g.enemies_root.get_children():
		e.queue_free()
	var door: Node = ia.plain_door()
	door.host_set_open(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	await ia.put_in_doorway(ItemGenerator.generate_equipment("sword", 1, 3, rng), door)
	p.host_teleport(g.floor_beside_door(door.world_rect.get_center()))
	p.auto_aim = door.world_rect.get_center()
	await da._wait(1.0)
	await snap("interact_item_%s" % Settings.language)
	da._action("interact_next")
	await da._wait(0.5)
	await snap("interact_door_%s" % Settings.language)
	p.auto_aim = Vector2.INF


## #37: the party frames (HUD preview: the local hero shown as three teammates) with a mix of
## buffs and debuffs, at the current window size.
func _party(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	p.iframe_left = 9999.0
	for e in g.enemies_root.get_children():
		e.queue_free()
	for s in [["poison", 8.0], ["poison", 8.0], ["burn", 4.0], ["slow", 6.0], ["renew", 9.0], ["pw_shield", 12.0], ["fortify", 10.0], ["blessing_of_might", 60.0], ["chill", 5.0], ["bleed", 7.0]]:
		p.status.apply(s[0], s[1], 1.0, p)
	await da._wait(0.3)
	hud.preview_full = true
	await da._wait(0.6)
	var vp := da.get_viewport().get_visible_rect().size
	await snap("party_%s" % Settings.language)
	hud.preview_full = false


## #39: the hero picked as the friendly target (HUD preview shows the hero as three teammates, so
## the party frames carry the mark too), with the options' Controls tab listing the new actions.
func _target(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.set_friendly_target(p.peer_id)
	hud.preview_full = true
	await da._wait(0.8)
	await snap("target_%s" % Settings.language)
	hud.preview_full = false


## #40: the hero picked as the friendly target (marker on the hero and the frame), then a click on
## empty ground: the pick and both markers are gone and the click swings.
func _target_clear(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.set_friendly_target(p.peer_id)
	hud.preview_full = true
	await da._wait(0.8)
	await snap("target_clear_before_%s" % Settings.language)
	p.auto_aim = p.global_position + Vector2(90, 30)
	await da._wait(0.2)
	Input.action_press("attack")
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame
	Input.action_release("attack")
	await da._wait(0.12)
	await snap("target_clear_after_%s" % Settings.language)
	da.check(p.friendly_peer == 0, "the click on empty ground cleared the pick")
	p.auto_aim = Vector2.INF
	hud.preview_full = false


## #53: the controls tab of the options without the removed "Target next enemy" action (#41),
## focused on "Target next ally", and the Menus group with Talents back on D-Pad Left.
func _controls(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(preload("res://scripts/ui/pause_menu.gd").new())
	await da._wait(0.4)
	hud._overlay._open_settings()
	await da._wait(0.4)
	var menu: Node = hud._overlay.get_child(hud._overlay.get_child_count() - 1)
	menu._tabs.current_tab = 2
	await da._wait(0.3)
	menu._bind_buttons["target_ally|kbm|0"].grab_focus()
	await da._wait(0.5)
	await snap("controls_combat_%s" % Settings.language)
	menu._bind_buttons["talents|pad|0"].grab_focus()
	await da._wait(0.5)
	await snap("controls_menus_%s" % Settings.language)
	hud.close_overlay()


## #42: the aim preview of a held skill for each shape (a mage hero): projectile with its blast,
## an area at the aim point, a cone, a beam, a dash, a ground zone, an aura around the hero, a
## chain; then a refused one (no mana).
func _previews(_arg: String) -> void:
	var dummies := await arena(3)
	p.host_take_torch()
	var aim: Vector2 = dummies[1].global_position + Vector2(10, -10)
	p.auto_aim = aim
	for sid in ["mage_fireball", "mage_meteor", "mage_flame_wave", "mage_luminance", "mage_blink", "mage_blizzard", "mage_frost_nova", "mage_lightning"]:
		p.skills[1] = sid
		p.resource.value = p.resource.max_value
		p.local_cd.clear()
		p._skill_hold = {1: 1.0}
		await da._wait(0.35)
		await snap("preview_%s_%s" % [sid.trim_prefix("mage_"), Settings.language])
	p.skills[1] = "mage_fireball"
	p.resource.value = 0.0
	await da._wait(0.3)
	await snap("preview_no_mana_%s" % Settings.language)
	p.resource.value = p.resource.max_value
	p._skill_hold.clear()
	p.auto_aim = Vector2.INF


## #54: Power Shot held on slot 2 at about 60 %: the gold fill along its line, the ring around the
## hero and the HUD slot filling, with no cooldown sweep; then full (pulsing) and after the release
## (the sweep starts only now).
func _charge(_arg: String) -> void:
	var dummies := await arena(3)
	p.host_take_torch()
	var lo: Array = p.skills.map(func(x): return "" if str(x) == "ranger_power_shot" else x)
	lo[2] = "ranger_power_shot"
	p.skills = lo
	p.resource.value = p.resource.max_value
	p.local_cd.clear()
	p.cooldowns.clear()
	p.auto_aim = dummies[1].global_position + Vector2(0, -12)
	await da._wait(0.4)
	Input.action_press("skill_2")
	await da._wait(0.62)
	await snap("charge_mid_%s" % Settings.language)
	await da._wait(0.6)
	await snap("charge_full_%s" % Settings.language)
	Input.action_release("skill_2")
	await da._wait(0.5)
	await snap("charge_fired_%s" % Settings.language)
	p.auto_aim = Vector2.INF


## #52: the inventory of a ranger wearing the Short Bow and a quiver, the quiver's card open.
func _quiver(_arg: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var q := ItemGenerator.generate_equipment("quiver", 1, 3, rng)
	p.host_give_item(q)
	p.request_equip.rpc_id(1, p.inv.backpack.size() - 1)
	await da._wait(0.4)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Control = hud.menu_panel("inventory")
	hud.open_overlay(panel)
	await da._wait(0.6)
	panel._slots["e:off_hand"].grab_focus()
	await da._wait(0.5)
	await snap("quiver_inventory_%s" % Settings.language)
	hud.close_overlay()


## #48: two levels at once: the column, rings and sparks on the hero and the banner, early, mid
## and late in the animation.
func _level_up(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.host_take_torch()
	await da._wait(0.6)
	p.add_xp(Player.xp_to_next(p.level) + Player.xp_to_next(p.level + 1) + 1)
	await da._wait(0.18)
	await snap("level_up_burst_%s" % Settings.language)
	await da._wait(0.45)
	await snap("level_up_mid_%s" % Settings.language)
	await da._wait(1.0)
	await snap("level_up_late_%s" % Settings.language)


## #49: a Skeletal Footman knocked into its bone pile (the mark counting down), and a cultist
## raising a fallen skeleton (the corpse's mark while the chant runs).
func _rise(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.host_take_torch()
	var start: Vector2 = g.layout.start
	p.host_teleport(start)
	var f: Enemy = g.spawn_monster("skeletal_footman", g.nearest_floor(start + Vector2(70, 0)), false)
	await da._wait(0.5)
	var ctx := Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0])))
	Combat.instance.deal_damage(ctx, f, f.health.hp + 50.0, {"damage_type": "true"})
	await da._wait(1.2)
	await snap("rise_pile_%s" % Settings.language)
	f.queue_free()
	var cu: Enemy = g.spawn_monster("cultist", g.nearest_floor(start + Vector2(110, -30)), false)
	var arch: Enemy = g.spawn_monster("skeleton_archer", g.nearest_floor(start + Vector2(70, 20)), false)
	cu.status.apply("stun", 0.5, 0.0, null)
	await da._wait(0.5)
	Combat.instance.deal_damage(ctx, arch, arch.health.hp + 50.0, {"damage_type": "true"})
	await da._wait(0.6)
	for b in cu.behaviors:
		if b.has_method("_stop_chant"):
			b._left = 0.0
	await da._wait_until(func(): return cu.behavior_state == "chanting", 3.0)
	await da._wait(0.6)
	await snap("rise_raise_%s" % Settings.language)


## #51 (with --biome=sewers): a floodgate lever off, mid-pull and on, close up, then the pulled
## lever and a second unpulled one seen from across the room.
func _lever(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var find := func() -> Node:
		for pr in g.dungeon.props.values():
			if pr.def.get("lever", false) and int(pr.get_meta("gate", -1)) >= 0:
				return pr
		return null
	var lever: Node = find.call()
	for attempt in 12:
		if lever:
			break
		g.run_seed += 1
		g.start_floor(1)
		await da._wait(2.0)
		for e in g.enemies_root.get_children():
			e.queue_free()
		lever = find.call()
	if lever == null:
		da.check(false, "no floodgate lever found")
		return
	p.host_take_torch()
	p.host_teleport(g.nearest_floor(lever.global_position + Vector2(-34, 18)))
	await da._wait(1.0)
	await snap("lever_off_%s" % Settings.language)
	g.host_interact(p, lever)
	await da._wait(0.2)
	await snap("lever_mid_%s" % Settings.language)
	await da._wait(1.0)
	await snap("lever_on_%s" % Settings.language)
	p.torch_left = 0.0
	p.host_teleport(g.nearest_floor(lever.global_position + Vector2(-200, 60)))
	await da._wait(1.2)
	await snap("lever_far_%s" % Settings.language)


## #47: the class's talent trees: untouched (level 30, nothing learned), partly learned (a path to
## tier 3 in the first branch, a little of the second), the first branch learned to its end, and
## three frames of the learn animation (a rank bought through the host).
func _talent_tree(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var tree := p.talent_tree()
	var suite := TalentSuite.new(da)
	suite.p = p
	p.level = 30
	p.talents = {}
	p.talent_points = 29
	hud.open_overlay(hud.menu_panel("talents"))
	await da._wait(0.8)
	await snap("tree_locked_%s_%s" % [p.class_id, Settings.language])
	var b0: String = tree.branches[0].id
	var b1: String = tree.branches[1].id
	var target: Dictionary = {}
	var side: Dictionary = {}
	for nd in tree.nodes:
		if nd.branch == b0 and int(nd.tier) == 3 and target.is_empty() and str(nd.get("type", "")) != "keystone":
			target = nd
		if nd.branch == b1 and int(nd.tier) == 1 and side.is_empty() and nd.has("exclusive"):
			side = nd
	var part := suite.plan_for(target)
	part[target.id] = 1
	part.merge(suite.plan_for(side))
	part[side.id] = 1
	p.talents = part
	p.talent_points = 6
	await da._wait(1.4)
	hud._overlay._buttons[str(target.id)][0].grab_focus()
	await da._wait(0.4)
	await snap("tree_partial_%s_%s" % [p.class_id, Settings.language])
	# The first branch to its end: every T5 node on the first side of each fork.
	var full := {}
	for nd in tree.nodes:
		if nd.branch == b0 and int(nd.tier) == 5:
			var pl := suite.plan_for(nd)
			var clash := false
			for k in pl:
				var other := p.fork_sibling(p.talent_node(str(k)))
				clash = clash or full.has(other.get("id", ""))
			if clash:
				continue
			for k in pl:
				full[k] = int(p.talent_node(str(k)).get("max_rank", 1))
			full[nd.id] = 1
	p.talents = full
	p.talent_points = 0
	await da._wait(1.4)
	await snap("tree_full_%s_%s" % [p.class_id, Settings.language])
	# The learn animation: a node in the second branch that can be learned now.
	p.talents = {}
	p.talent_points = 29
	await da._wait(1.0)
	var pick := ""
	for nd in tree.nodes:
		if nd.branch == b1 and int(nd.tier) == 0 and not p.is_free_node(nd) and pick == "":
			pick = nd.id
	var pre := {pick: int(p.talent_node(pick).get("max_rank", 1))}
	p.talents = pre
	await da._wait(1.2)
	var kid := ""
	for nd in tree.nodes:
		if Array(nd.get("requires", [])).has(pick) and kid == "" and not nd.has("exclusive"):
			kid = nd.id
	if kid == "":
		for nd in tree.nodes:
			if Array(nd.get("requires", [])).has(pick) and kid == "":
				kid = nd.id
	p.talents = {}
	await da._wait(0.2)
	var chain := suite.plan_for(p.talent_node(kid))
	p.talents = chain
	await da._wait(1.2)
	hud._overlay._buttons[kid][0].grab_focus()
	await da._wait(0.3)
	p.request_learn_talent.rpc_id(1, kid)
	for f in [["a", 0.06], ["b", 0.18], ["c", 0.3]]:
		await da._wait(float(f[1]))
		await snap("tree_learn_%s_%s_%s" % [f[0], p.class_id, Settings.language])
	hud.close_overlay()


## #43: the talent card of a damage skill, a heal, an area skill, a ranked passive (at rank 1) and
## a keystone of the hero's class, then a skill's numeric card from the bar.
func _talent_tips(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var tree := p.talent_tree()
	var picks := {}
	for node in tree.nodes:
		var kind := str(node.get("type", ""))
		if kind == "skill":
			var sk: Dictionary = GameData.skills.get(str(node.skill), {})
			var js := JSON.stringify(sk.get("effects", []))
			var shape := SkillShape.of(sk)
			if not picks.has("damage") and js.contains("\"damage\"") and shape.kind in ["projectile", "melee", "target"]:
				picks["damage"] = node
			elif not picks.has("heal") and (js.contains("\"heal\"") or js.contains("\"absorb\"")):
				picks["heal"] = node
			elif not picks.has("area") and shape.kind in ["area", "self_area"] and js.contains("\"damage\""):
				picks["area"] = node
		elif kind == "passive" and not picks.has("passive") and int(node.get("max_rank", 1)) >= 2:
			picks["passive"] = node
		elif kind == "keystone" and not picks.has("keystone") and not node.get("procs", []).is_empty():
			picks["keystone"] = node
	var keep := p.talents.duplicate()
	if picks.has("passive"):
		var t2 := keep.duplicate()
		t2[picks.passive.id] = 1
		p.talents = t2
	hud.open_overlay(hud.menu_panel("talents"))
	await da._wait(0.6)
	for k in ["damage", "heal", "area", "passive", "keystone"]:
		if picks.has(k):
			hud._overlay._show(picks[k])
			await da._wait(0.3)
			await snap("tips_%s_%s_%s" % [p.class_id, k, Settings.language])
	hud.close_overlay()
	p.talents = keep
	await da._wait(0.3)
	hud._slots[1].mouse_entered.emit()
	await da._wait(0.4)
	await snap("tips_%s_slot_%s" % [p.class_id, Settings.language])
	hud._slots[1].mouse_exited.emit()


## #33: a heal burst, the heal-over-time glow, the shield bubble, its shatter, a buff flash and a
## cleanse flash on the hero next to training dummies (each shot near the effect's peak).
func _allyfx(_arg: String) -> void:
	await arena(3)
	p.skills = ["priest_holy_strike", "priest_heal", "priest_holy_shield", "priest_renew", "priest_blessing_of_might", "priest_purify"]
	var fx: Node = Combat.instance.fx
	p.health.hp = p.health.max_hp * 0.4
	p.resource.value = p.resource.max_value
	var hp0 := p.health.hp
	p.request_skill.rpc_id(1, 1, p.global_position, p.peer_id)
	await da._wait_until(func(): return p.health.hp > hp0, 3.0)
	await da._wait(0.2)
	await snap("allyfx_heal")
	await da._wait(0.8)
	p.request_skill.rpc_id(1, 3, p.global_position, p.peer_id)
	await da._wait(0.9)
	await snap("allyfx_hot")
	p.request_skill.rpc_id(1, 2, p.global_position, p.peer_id)
	await da._wait(0.8)
	await snap("allyfx_shield")
	p.health.absorb = 0.0
	await da._wait(0.25)
	await snap("allyfx_shield_break")
	await da._wait(0.6)
	p.request_skill.rpc_id(1, 4, p.global_position, 0)
	await da._wait(0.35)
	await snap("allyfx_buff")
	await da._wait(0.8)
	p.status.apply("poison", 6.0, 1.0, null)
	p.request_skill.rpc_id(1, 5, p.global_position, p.peer_id)
	await da._wait(0.2)
	await snap("allyfx_cleanse")


## #34: the nine elements' AoE impacts side by side (one shot near their peak), then their
## lingering zones.
func _elements(_arg: String) -> void:
	await arena(0)
	var els: Array = GameData.fx.get("burst", {}).keys()
	var ctx := Combat.instance.make_ctx(p, GameData.skill("mage_fireball"))
	var at := func(i: int) -> Vector2: return p.global_position + Vector2(-130 + 130 * (i % 3), -110 + 100 * (i / 3))
	for i in els.size():
		Combat.instance.fx.ring.rpc(at.call(i), 40.0, "#ffffff", "", str(els[i]))
	await da._wait(0.35)
	await snap("elements_bursts")
	await da._wait(1.2)
	for i in els.size():
		Combat.instance.fx.zone.rpc(9000 + i, at.call(i), 40.0, "#ffffff", 4.0, "", str(els[i]))
	await da._wait(0.8)
	await snap("elements_zones")
	da.log_line("elements order %s" % [els])


## #36: a wall spout of the floor's biome (Sewers acid, Foundry flame), seen from across the room
## and up close, idle, warning and spraying.
func _spouts(_arg: String) -> void:
	var sp: Array = g.dungeon.spouts
	da.check(not sp.is_empty(), "the floor has wall spouts")
	if sp.is_empty():
		return
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var s: Node2D = sp[0]
	var biome := str(g.floor_def.get("id", ""))
	var period := float(s.cfg.get("period", 5.0))
	p.host_teleport(g.nearest_floor(s.global_position + Vector2(0, 150)))
	await da._wait(1.0)
	# Wait for a quiet moment, then show it idle, warning (just before) and spraying.
	await da._wait_until(func(): return not s.is_on(g.floor_time) and fposmod(g.floor_time / period + s.phase, 1.0) > 0.5, period + 1.0)
	await snap("spout_%s_far_idle" % biome)
	p.host_teleport(g.nearest_floor(s.global_position + Vector2(36, 70)))
	await da._wait_until(func(): return s.warning(g.floor_time), period + 1.0)
	await da._wait(0.3)
	await snap("spout_%s_warning" % biome)
	await da._wait_until(func(): return s.is_on(g.floor_time), period + 1.0)
	await da._wait(0.35)
	await snap("spout_%s_spray" % biome)


## #38: a book read from the inventory, then Cancel: back on the inventory with the book selected.
func _bookback(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	p.host_give_item(LootTable.make_book("lore_001", RandomNumberGenerator.new()))
	await da._wait(0.3)
	var i := p.inv.backpack.size() - 1
	hud.open_overlay(hud.menu_panel("inventory"))
	await da._wait(0.5)
	hud._overlay._slots["b:%d" % i].grab_focus()
	await da._wait(0.2)
	hud._overlay._accept_backpack(i)
	await da._wait(0.8)
	await snap("bookback_reader_%s" % Settings.language)
	da._action("ui_cancel")
	await da._wait(0.6)
	await snap("bookback_inventory_%s" % Settings.language)


## #36: a spout on each wall side (north, south, west, east), spraying, seen from the room.
func _spout_sides(_arg: String) -> void:
	var biome := str(g.floor_def.get("id", ""))
	var names := {Vector2i.DOWN: "north", Vector2i.UP: "south", Vector2i.RIGHT: "west", Vector2i.LEFT: "east"}
	for d in names:
		var found: Node2D = null
		for attempt in 16:
			for s2 in g.dungeon.spouts:
				if s2.dir == d:
					found = s2
			if found:
				break
			# force_biome pins the first floor's type and later depths cycle on; pick the pin that
			# lands the next depth on this biome.
			for ft in GameData.floor_types:
				GameState.set_meta("force_biome", ft)
				if g.floor_type_for(g.depth + 1) == biome:
					break
			g.start_floor(g.depth + 1)
			await da._wait(1.5)
			p = da._local()
		if found == null:
			da.check(false, "found a %s-wall spout" % names[d])
			continue
		for e in g.enemies_root.get_children():
			e.queue_free()
		p.iframe_left = 9999.0
		p.host_teleport(g.nearest_floor(found.global_position + Vector2(d) * 70.0 + Vector2(d.y, d.x) * 40.0))
		await da._wait_until(func(): return found.is_on(g.floor_time), float(found.cfg.get("period", 5.0)) + 1.5)
		await da._wait(0.3)
		await snap("spout_side_%s_%s" % [biome, names[d]])


## The merchant room of each merchant (#6): its sealed door seen from across the corridor and up
## close (#23), the door paid for and open, Archibald's shop, the blood price dialog and
## Malphas's bargains.
func _merchants(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for npc in ["archibald", "malphas"]:
		GameState.set_meta("force_merchant", npc)
		g.start_floor(g.depth)
		GameState.remove_meta("force_merchant")
		await da._wait(1.5)
		p = da._local()
		var m: Dictionary = g.layout.get("merchant", {})
		if m.is_empty():
			da.check(false, "floor has a merchant room")
			return
		p.iframe_left = 9999.0
		p.host_add_gold(400)
		var door: Node = g.dungeon.leaf_door("merchant")
		var room: Rect2i = g.layout.rooms[int(m.room)].rect
		var away := signf(door.world_rect.get_center().y - float(room.get_center().y) * g.dungeon.tile)
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, away * 200.0)))
		await da._wait(1.2)
		await snap("merchant_door_far_%s" % npc)
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, away * 56.0)))
		await da._wait(1.0)
		await snap("merchant_door_%s" % npc)
		if npc == "archibald":
			g.add_party_key(1)
			g.host_interact(p, door)
		else:
			g.host_interact(p, door)
			await da._wait(0.6)
			await snap("merchant_tithe")
			hud.close_overlay()
			g.merchants.request_tithe.rpc_id(1, true)
		await da._wait(1.0)
		await snap("merchant_door_open_%s" % npc)
		p.host_teleport(m.pos + Vector2(0, 40))
		await da._wait(1.0)
		await snap("merchant_room_%s" % npc)
		p.host_teleport(m.pos + Vector2(0, 18))
		await da._wait(0.3)
		g.host_interact(p, g.dungeon.props["Merchant"])
		await da._wait(0.6)
		await snap("merchant_shop_%s" % npc)
		hud.close_overlay()


## #31: the boss door of every biome seen from across the room in front of it, then up close.
func _boss_doors(_arg: String) -> void:
	for fid in ["crypt", "sewers", "foundry", "archives", "kurgan"]:
		GameState.set_meta("force_biome", fid)
		g.start_floor(1)
		await da._wait(1.5)
		p = da._local()
		p.iframe_left = 9999.0
		for e in g.enemies_root.get_children():
			if not e.is_boss:
				e.queue_free()
		var door: Node = g.dungeon.leaf_door("boss")
		var room: Rect2i = g.layout.rooms[int(g.layout.boss_room)].rect
		var away := signf(door.world_rect.get_center().y - float(room.get_center().y) * g.dungeon.tile)
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, away * 150.0)))
		await da._wait(1.4)
		await snap("boss_door_far_%s" % fid)
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, away * 60.0)))
		await da._wait(1.0)
		await snap("boss_door_%s" % fid)


## The lore reader on a tome and the codex tab.
func _lore(_arg: String) -> void:
	var rng := RandomNumberGenerator.new()
	for id in ["lore_001", "lore_002", "lore_005", "lore_021"]:
		p.host_give_item(LootTable.make_book(id, rng))
	await da._wait(0.3)
	for i in p.inv.backpack.size():
		if str(p.inv.backpack[i].get("book", "")) == "lore_001":
			p.request_read_book.rpc_id(1, i)
	await da._wait(0.8)
	await snap("lore_reader")
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.close_overlay()
	for i in range(p.inv.backpack.size() - 1, -1, -1):
		if str(p.inv.backpack[i].get("book", "")) == "lore_002":
			p.request_read_book.rpc_id(1, i)
	await da._wait(0.6)
	await snap("lore_tome")
	hud.close_overlay()
	hud.open_overlay(hud.menu_panel("codex"))
	await da._wait(0.6)
	await snap("lore_codex")
	hud.close_overlay()


## A class's new skills in action, then its full talent tree and Skill Book.
func _skills(_arg: String) -> void:
	var picks := {
		"warrior": ["warrior_whirlwind", "warrior_earthshaker", "warrior_heroic_leap", "warrior_avatar", "warrior_intimidating_roar", "warrior_armor_sunder"],
		"ranger": ["ranger_rain_of_arrows", "ranger_trickshot", "ranger_shadow_ballista", "ranger_venomous_vapors", "ranger_shadow_flare", "ranger_bone_harpoon"],
		"mage": ["mage_blizzard", "mage_thunderstorm", "mage_singularity", "mage_luminance", "mage_lightning_orb", "mage_grasp_of_the_void"],
		"priest": ["priest_bastion_sigil", "priest_penance", "priest_holy_nova", "priest_lightwell", "priest_chastise", "priest_apotheosis"],
	}
	var t := {}
	for nd in p.talent_tree().get("nodes", []):
		if nd.get("type", "") == "skill" and not nd.get("starter", false):
			t[nd.id] = 1
	p.talents = t
	p.recompute_stats()
	var d := await arena(4)
	for sid in picks.get(p.class_id, []):
		for x in d:
			x.health.hp = x.health.max_hp
			x.status.clear_all()
		p.host_teleport(g.layout.start)
		await da._wait(0.2)
		await cast(str(sid), d[0].global_position)
		await da._wait(0.8 if GameData.skill(str(sid)).has("channel") or str(sid).ends_with("leap") else 0.5)
		await snap("skills_%s" % sid)
		await da._wait(0.6)
		Combat.instance.clear_floor()
		p.channel = {}
	p.talent_points = 6
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for tab in ["talents", "skillbook", "character"]:
		hud.open_overlay(hud.menu_panel(tab))
		await da._wait(0.6)
		await snap("skills_%s_%s" % [p.class_id, tab])
	hud.close_overlay()


## A biome (default: the current floor): a furnished room, its hazards, every monster of the
## biome in a frozen line-up (with their behaviour looks) and both bosses in each phase.
func _biome(_arg: String) -> void:
	p.iframe_left = 9999.0
	var fid := str(g.floor_def.id)
	# The most furnished normal room.
	var best := -1
	var best_n := -1
	for i in g.layout.rooms.size():
		var room: Dictionary = g.layout.rooms[i]
		if room.role != "normal":
			continue
		var rect := Rect2(Vector2(room.rect.position * g.dungeon.tile), Vector2(room.rect.size * g.dungeon.tile))
		var n := 0
		for pr in g.layout.props:
			if rect.has_point(pr.pos):
				n += 1
		if n > best_n:
			best_n = n
			best = i
	for e in g.enemies_root.get_children():
		e.queue_free()
	if best >= 0:
		p.host_teleport(g.nearest_floor(g.dungeon.cell_center(Vector2i(g.layout.rooms[best].rect.get_center()))))
		await da._wait(1.2)
		await snap("%s_room" % fid)
	if not g.dungeon.plates.is_empty():
		var plate: Node2D = g.dungeon.plates[0]
		p.host_teleport(plate.global_position + Vector2(0, -4))
		await da._wait(0.55)
		await snap("%s_plate" % fid)
	# Monster line-up in the start room, frozen so the shot is calm.
	var start: Vector2 = g.layout.start
	p.host_teleport(start + Vector2(0, 60))
	var ids: Array = []
	for m in g.floor_def.monsters:
		ids.append(str(m.id))
	var row: Array = []
	for i in ids.size():
		var e: Enemy = g.spawn_monster(ids[i], g.nearest_floor(start + Vector2(-165 + 55 * i, -20)), false)
		if e:
			e.set_physics_process(false)
			e.facing = Vector2.DOWN
			row.append(e)
	await da._wait(1.0)
	p.status.clear_all()
	await snap("%s_monsters" % fid)
	# Behaviour looks: the footman's bone pile, the crawler's mound...
	for e in row:
		var vis: Dictionary = e.def.get("behavior_visuals", {})
		if not vis.is_empty():
			e.behavior_state = str(vis.keys()[0])
	await da._wait(0.4)
	await snap("%s_monster_states" % fid)
	for e in row:
		e.queue_free()
	await da._wait(0.3)
	# Bosses: each phase with its mechanics running.
	for bid in g.floor_def.get("bosses", []):
		await _boss_shots(str(bid))


func _boss_shots(bid: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	Combat.instance.clear_floor()
	await da._wait(0.4)
	var bpos: Vector2 = g.layout.boss_pos
	p.host_teleport(g.nearest_floor(bpos + Vector2(0, 90)))
	var boss: Enemy = g.spawn_monster(bid, bpos, true)
	await da._wait(0.3)
	boss.add_threat(p, 10.0)
	await da._wait(2.0)
	await snap("boss_%s_p1" % bid)
	for i in boss.def.phases.size():
		if i > 0:
			boss.health.absorb = 0.0
			boss.health.hp = boss.health.max_hp * maxf(float(boss.def.phases[i - 1].hp_above) - 0.03, 0.02)
			var t := 0.0
			while boss.phase < i and t < 6.0:
				await da._wait(0.2)
				t += 0.2
			await da._wait(1.0)
			await snap("boss_%s_p%d" % [bid, i + 1])
		for m in boss.mechanics.duplicate():
			p.iframe_left = 9999.0
			m.trigger()
			await da._wait(1.0)
			await snap("boss_%s_p%d_%s" % [bid, i + 1, m.params.get("id", "mech")])
			await da._wait(0.5)
	boss.stop_mechanics()
	boss.queue_free()
	p.status.clear_all()
	await da._wait(0.3)


## Every status icon on the hero's buff bar, a dozen at a time.
func _statuses(_arg: String) -> void:
	p.iframe_left = 9999.0
	var ids: Array = GameData.status_effects.keys().filter(func(k): return not str(k).begins_with("test_") and not str(k).begins_with("_"))
	ids.sort()
	var ctx := Combat.instance.env_ctx(0.0)
	var page := 0
	while page * 12 < ids.size():
		p.status.clear_all()
		for id in ids.slice(page * 12, page * 12 + 12):
			p.status.effects.append({"id": id, "def": GameData.status_effects[id], "remaining": 30.0, "tick_left": 99.0,
				"magnitude": 0.0, "stacks": 1, "source": ctx, "src_node": null, "charges": 0, "recorded": 0.0})
		p.status._publish()
		await da._wait(0.4)
		await snap("statuses_%02d" % page)
		page += 1
	p.status.clear_all()


## Legendaries: a few of the class's legendaries in the backpack, one worn, and the item card of each.
func _legendaries(_arg: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids: Array = GameData.legendaries.keys().filter(func(id): return str(GameData.legendaries[id]["class"]) == p.class_id)
	ids.sort()
	for i in 8:
		p.host_give_item(ItemGenerator.make_legendary(str(ids[(i * 5) % ids.size()]), 14, rng))
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var panel: Node = hud.menu_panel("inventory")
	hud.open_overlay(panel)
	await da._wait(0.6)
	for k in ["b:0", "b:3", "b:6"]:
		var slot: Control = panel._slots.get(k)
		if slot:
			slot.grab_focus()
			await da._wait(0.4)
			await snap("legendary_%s" % k.replace(":", ""))
	hud.close_overlay()


## Lighting review (#7): a closed door and props beside a wall torch, then beside the carried
## torch far from wall torches. Run once per biome (--biome=<id>).
func _lighting(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var fid: String = g.floor_type_for(g.depth)
	var lit_door: Node = null
	var dark_door: Node = null
	for d in g.dungeon.doors:
		if d.is_open or d.vertical or d.floodgate:
			continue
		var near := 9999.0
		for t in g.dungeon.torches.values():
			near = minf(near, t.global_position.distance_to(d.global_position))
		if near < 150.0 and lit_door == null:
			lit_door = d
		elif near > 320.0 and dark_door == null:
			dark_door = d
	if lit_door == null:
		lit_door = g.dungeon.doors[0]
	if dark_door == null:
		dark_door = g.dungeon.doors[-1]
	p.torch_left = 0.0
	p.host_teleport(g.nearest_floor(lit_door.global_position + Vector2(0, 70)))
	await da._wait(1.2)
	await snap("lighting_%s_wall_torch" % fid)
	p.host_take_torch()
	p.host_teleport(g.nearest_floor(dark_door.global_position + Vector2(20, 46)))
	await da._wait(1.2)
	await snap("lighting_%s_carried_torch" % fid)
	# A loose prop beside the carried torch.
	var best: Node = null
	for k in g.dungeon.props:
		var pr: Node = g.dungeon.props[k]
		if pr.destructible() and (best == null or pr.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = pr
	if best:
		p.host_teleport(g.nearest_floor(best.global_position + Vector2(24, 30)))
		await da._wait(1.2)
		await snap("lighting_%s_prop" % fid)


## #46: a closed door lit from each side by a lone test torch (a horizontal door from the south and
## from the north, a side door from the west and the east) and a sight-blocking prop with the light
## on each side, in this floor's biome. The hero stands aside with no torch.
func _lighting_sides(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.torch_left = 0.0
	var fid: String = g.floor_type_for(g.depth)
	var lamp := PointLight2D.new()
	LightLayers.setup_light(lamp)
	lamp.texture = GameData.texture("fx.light")
	lamp.color = Color("ffb060")
	lamp.energy = float(GameData.bal("lighting.wall_torch_energy"))
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	lamp.shadow_filter_smooth = 2.0
	LightLayers.register(lamp, float(GameData.bal("lighting.wall_torch_radius")))
	g.dungeon.add_child(lamp)
	var hdoor: Node = null
	var vdoor: Node = null
	for d in g.dungeon.doors:
		if d.is_open or d.floodgate or d.light != null:
			continue
		if d.vertical and vdoor == null:
			vdoor = d
		elif not d.vertical and hdoor == null:
			hdoor = d
	if hdoor:
		da.log_line("door %s type '%s' kind '%s' open %s sealed %s" % [hdoor.name, hdoor.door_type, hdoor.kind, hdoor.is_open, hdoor.sealed])
	var shots := []
	if hdoor:
		shots.append([hdoor, Vector2(0, 56), "door_lit_south", Vector2(80, 70)])
		shots.append([hdoor, Vector2(0, -90), "door_lit_north", Vector2(80, 70)])
	if vdoor:
		shots.append([vdoor, Vector2(-56, -16), "side_door_lit_west", Vector2(0, 80)])
		shots.append([vdoor, Vector2(56, -16), "side_door_lit_east", Vector2(0, 80)])
	var prop: Node = null
	for k in g.dungeon.props:
		var pr: Node = g.dungeon.props[k]
		if pr.def.get("blocks_sight", true) and pr.destructible() and (prop == null or str(pr.type) in ["table", "pillar", "chest"]):
			prop = pr
	if prop:
		for side in [["south", Vector2(0, 60)], ["north", Vector2(0, -70)], ["west", Vector2(-60, -10)], ["east", Vector2(60, -10)]]:
			shots.append([prop, side[1], "prop_lit_%s" % side[0], Vector2(70, 60)])
	for sh in shots:
		var at: Node2D = sh[0]
		# Only the test lamp lights the subject.
		for t in g.dungeon.torches.values():
			t.visible = t.global_position.distance_to(at.global_position) > 300.0
		lamp.global_position = g.nearest_floor(at.global_position + sh[1])
		p.host_teleport(g.nearest_floor(at.global_position + sh[3]))
		await da._wait(1.0)
		if at.get("is_open") != null:
			da.log_line("%s open %s" % [sh[2], at.is_open])
		await snap("lighting_sides_%s_%s" % [fid, sh[2]])
	lamp.queue_free()
	for t in g.dungeon.torches.values():
		t.visible = true


## #50: the hero with a carried torch pressed against a closed door from the north and the south,
## and against a side door from the west and the east; only the hero's own lights light it.
func _door_torch(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.host_take_torch()
	var fid: String = g.floor_type_for(g.depth)
	var hdoor: Node = null
	var vdoor: Node = null
	for d in g.dungeon.doors:
		if d.is_open or d.floodgate or d.light != null:
			continue
		if d.vertical and vdoor == null:
			vdoor = d
		elif not d.vertical and hdoor == null:
			hdoor = d
	var shots := []
	if hdoor:
		var h: float = hdoor.world_rect.size.y
		shots.append([hdoor, Vector2(0, -h - 13.0), "north"])
		shots.append([hdoor, Vector2(0, 13.0), "south"])
	if vdoor:
		var w: float = vdoor.world_rect.size.x
		var mid: float = -vdoor.world_rect.size.y / 2.0
		shots.append([vdoor, Vector2(-w / 2.0 - 13.0, mid), "west"])
		shots.append([vdoor, Vector2(w / 2.0 + 13.0, mid), "east"])
	for sh in shots:
		var at: Node2D = sh[0]
		for t in g.dungeon.torches.values():
			t.visible = t.global_position.distance_to(at.global_position) > 360.0
		p.host_teleport(at.global_position + sh[1])
		p.torch_left = 99.0
		await da._wait(1.0)
		await snap("door_torch_%s_%s_%s" % [fid, sh[2], Settings.language])
	for t in g.dungeon.torches.values():
		t.visible = true


## The Murk Amalgam's grab (#12): the held hero, the Engulfed icon and the Burst it down bar.
func _grab(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	p.iframe_left = 9999.0
	p.host_take_torch()
	var boss: Enemy = g.spawn_monster("murk_amalgam", g.nearest_floor(p.global_position + Vector2(50, 0)), true)
	await da._wait(0.5)
	boss.add_threat(p, 50.0)
	boss.target = p
	await da._wait(0.3)
	for m in boss.mechanics:
		if str(m.get_script().resource_path).ends_with("engulf.gd"):
			m.trigger()
	await da._wait(1.0)
	await snap("boss_grab")



## #79: light and torches at walls. A wall torch seen from the far side of a one-cell wall, the
## hero's carried torch and personal light pressed against a wall from every side (thin walls
## between two open spaces and thick ones), only the hero's own lights lighting the scene.
func _wall_leaks(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	# A floor with a wall torch on a one-cell wall (floor on its far side) shows the torch case.
	for depth_try in range(1, 9):
		var found := false
		for t in g.dungeon.torches.values():
			var c0: Vector2i = g.dungeon.cell_of(t.global_position - Vector2(0, g.dungeon.tile * 0.5 + 2.0))
			var up: int = g.dungeon.cell_at(c0 + Vector2i(0, -1))
			found = found or (up != DungeonGenerator.CELL_WALL and up != DungeonGenerator.CELL_CANAL)
		if found:
			break
		g.start_floor(depth_try + 1)
		await da._wait(1.5)
		for e in g.enemies_root.get_children():
			e.queue_free()
	# Everything already explored (remembered fog) so light leaking into the next room shows.
	var all := PackedByteArray()
	all.resize(g.dungeon.size.x * g.dungeon.size.y)
	all.fill(1)
	g.visibility.restore_discovered(all)
	var fid: String = g.floor_type_for(g.depth)
	var d: Dungeon = g.dungeon
	var floorish := func(c: Vector2i) -> bool: return d.cell_at(c) != DungeonGenerator.CELL_WALL and d.cell_at(c) != DungeonGenerator.CELL_CANAL
	var wall := func(c: Vector2i) -> bool: return d.cell_at(c) == DungeonGenerator.CELL_WALL
	# A wall torch with open floor on the far (north) side of its wall cell.
	var back_torch: Node = null
	for t in d.torches.values():
		var tc := d.cell_of(t.global_position - Vector2(0, d.tile * 0.5 + 2.0))
		if floorish.call(tc + Vector2i(0, -1)):
			back_torch = t
			break
	var shots := []  # [hero pos, name, light origin for the torch filter]
	if back_torch:
		var tc2 := d.cell_of(back_torch.global_position - Vector2(0, d.tile * 0.5 + 2.0))
		shots.append([d.cell_center(tc2 + Vector2i(0, -1)) + Vector2(0, -2), "torch_from_behind", false, back_torch])
	else:
		da.log_line("no wall torch with floor behind it on this floor")
	# One-cell walls between open floor, both orientations, and a thick wall per side.
	var thin_h := Vector2i(-1, -1)
	var thin_v := Vector2i(-1, -1)
	var thick := {}
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			var c := Vector2i(x, y)
			if not wall.call(c):
				continue
			var n: bool = floorish.call(c + Vector2i(0, -1))
			var s: bool = floorish.call(c + Vector2i(0, 1))
			var w: bool = floorish.call(c + Vector2i(-1, 0))
			var e2: bool = floorish.call(c + Vector2i(1, 0))
			if n and s and wall.call(c + Vector2i(-1, 0)) and wall.call(c + Vector2i(1, 0)) and thin_h.x < 0:
				thin_h = c
			if w and e2 and wall.call(c + Vector2i(0, -1)) and wall.call(c + Vector2i(0, 1)) and thin_v.x < 0:
				thin_v = c
			if n and not s and wall.call(c + Vector2i(0, 2)) and floorish.call(c + Vector2i(0, 3)) and not thick.has("n"):
				thick["n"] = c  # hero north of a 3-thick wall, facing south
			if s and not n and not thick.has("s") and wall.call(c + Vector2i(0, -2)):
				thick["s"] = c
			if w and not e2 and not thick.has("w") and wall.call(c + Vector2i(2, 0)):
				thick["w"] = c
			if e2 and not w and not thick.has("e") and wall.call(c + Vector2i(-2, 0)):
				thick["e"] = c
	var hs := d.tile * 0.5
	if thin_h.x >= 0:
		shots.append([d.cell_center(thin_h) + Vector2(0, -hs - 7), "thin_wall_from_north", true, null])
		shots.append([d.cell_center(thin_h) + Vector2(0, hs + 7), "thin_wall_from_south", true, null])
	if thin_v.x >= 0:
		shots.append([d.cell_center(thin_v) + Vector2(-hs - 7, 0), "thin_wall_from_west", true, null])
		shots.append([d.cell_center(thin_v) + Vector2(hs + 7, 0), "thin_wall_from_east", true, null])
	if thick.has("n"):
		shots.append([d.cell_center(thick.n) + Vector2(0, -hs - 7), "thick_wall_south_of_hero", true, null])
	if thick.has("s"):
		shots.append([d.cell_center(thick.s) + Vector2(0, hs + 7), "thick_wall_north_of_hero", true, null])
	if thick.has("w"):
		shots.append([d.cell_center(thick.w) + Vector2(-hs - 7, 0), "thick_wall_east_of_hero", true, null])
	if thick.has("e"):
		shots.append([d.cell_center(thick.e) + Vector2(hs + 7, 0), "thick_wall_west_of_hero", true, null])
	da.log_line("wall_leaks: thin_h %s thin_v %s thick %s torch %s" % [thin_h, thin_v, thick, back_torch != null])
	for sh in shots:
		var own_light: bool = sh[2]
		for t in d.torches.values():
			t.visible = not own_light or t.global_position.distance_to(sh[0]) > 420.0
		if own_light:
			p.host_take_torch()
			p.torch_left = 99.0
		else:
			p.torch_left = 0.0
			p.torch_sync = 0
		p.host_teleport(sh[0])
		await da._wait(1.0)
		if sh[3] != null:
			var target: Dictionary = g.find_interactable(p, 0)
			da.log_line("torch_from_behind: prompt '%s' torch shown %s" % [str(target.get("text", "")), sh[3].is_visible_in_tree()])
		await snap("wall_leaks_%s_%s_%s" % [fid, sh[1], Settings.language])
	for t in d.torches.values():
		t.visible = true


## #79 (windowed): how much the hero's own lights (personal light and carried torch) brighten the
## far side of a wall it is pressed against, in every wall orientation, thin and thick walls. Two
## frames per case, with and without the hero's lights (no other light, no fog, the hero sprite
## hidden); the brightest pixel difference behind the wall must stay under `leak_max`.
func _leak_probe(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var d: Dungeon = g.dungeon
	for t in d.torches.values():
		t.visible = false
	for l in d.lights:
		if is_instance_valid(l):
			l.visible = false
	g.visibility._fog_sprite.visible = false
	p.modulate.a = 0.0  # the hero's sprites (its lights still shine)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.visible = false
	var leak_max := 6.0
	if not _arg.is_empty():
		for l in [g.visibility.vision_light, p._torch_light]:
			l.shadow_filter_smooth = float(_arg)
	var cases := LightingSuite.wall_cases(d)
	da.log_line("leak_probe: %d cases" % cases.size())
	for cs in cases:
		p.host_take_torch()
		p.torch_left = 99.0
		p.host_teleport(cs.hero)
		await da._wait(0.8)
		var lights: Array = [g.visibility.vision_light, p._torch_light]
		var a := await _frame()
		for l in lights:
			l.enabled = false
		var b := await _frame()
		for l in lights:
			l.enabled = true
		var worst := 0.0
		var sum := 0.0
		var n := 0
		var vp := da.get_viewport()
		var k := Vector2(a.get_width(), a.get_height()) / vp.get_visible_rect().size
		var xf := vp.get_canvas_transform()
		for r: Rect2 in cs.far:
			var p0 := (xf * r.position) * k
			var p1 := (xf * r.end) * k
			for y in range(maxi(0, int(p0.y)), mini(a.get_height(), int(p1.y))):
				for x in range(maxi(0, int(p0.x)), mini(a.get_width(), int(p1.x))):
					var diff := (a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) * 255.0
					worst = maxf(worst, diff)
					sum += maxf(diff, 0.0)
					n += 1
		da.log_line("leak %s: worst %.1f mean %.2f over %d px" % [cs.name, worst, sum / maxf(n, 1), n])
		if worst > leak_max:
			var rows := []
			for yy in range(-3, 4):
				var row := ""
				for xx in range(-10, 11):
					var cc: Vector2i = cs.wall + Vector2i(xx, yy)
					var v := d.cell_at(cc)
					var ch := "#" if v == DungeonGenerator.CELL_WALL else "."
					if d.cell_at(cc + Vector2i(0, 1)) != DungeonGenerator.CELL_WALL and v == DungeonGenerator.CELL_WALL:
						ch = "F"
					for door in d.doors:
						if door.cells.has(cc):
							ch = "D"
					if cc == d.cell_of(cs.hero):
						ch = "@"
					row += ch
				rows.append(row)
			da.log_line("map around %s (F = face):\n%s" % [cs.name, "\n".join(rows)])
			a.save_png(dir.path_join("leak_%s_lit.png" % cs.name))
			b.save_png(dir.path_join("leak_%s_dark.png" % cs.name))
		da.check(n > 0 and worst <= leak_max, "%s: the hero's light doesn't reach behind the wall (worst %.1f / 255)" % [cs.name, worst])
	p.modulate.a = 1.0
	if hud:
		hud.visible = true
	g.visibility._fog_sprite.visible = true


func _frame() -> Image:
	await da.get_tree().process_frame
	await da.get_tree().process_frame
	await RenderingServer.frame_post_draw
	return da.get_viewport().get_texture().get_image()


## #82: the ghost as its owner sees it (roaming with its own blue light) in a dark room and next
## to a closed door. Solo: the hero is turned into a ghost directly (a real death would wipe a
## party of one); the living teammate's view is reviewed with the ghost-lan pair (--shot).
func _ghost(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	p.torch_left = 0.0
	p.torch_sync = 0
	p.life_state = Player.Life.GHOST
	p.apply_ghost_body()
	await da._wait(1.0)
	var fid: String = g.floor_type_for(g.depth)
	await snap("ghost_%s_start_%s" % [fid, Settings.language])
	# A dark spot away from torches.
	var spot := Vector2.ZERO
	var best := 0.0
	for room in g.layout.rooms:
		var c: Vector2 = g.dungeon.cell_center(room.rect.get_center())
		var far := INF
		for t in g.dungeon.torches.values():
			far = minf(far, t.global_position.distance_to(c))
		if far > best:
			best = far
			spot = c
	p.host_teleport(g.nearest_floor(spot))
	await da._wait(1.2)
	await snap("ghost_%s_dark_%s" % [fid, Settings.language])
	for i in 6:
		await da._wait(0.25)
		await snap("ghost_%s_dark_frame%d_%s" % [fid, i, Settings.language])


## #75: a boss's hoard bursting out (frames of the arc, the trail, the landing puff) and the
## legendary beam over the named legendary among it.
func _drops(_arg: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(40, 10))
	p.host_teleport(spot + Vector2(-70, 30))
	await da._wait(0.8)
	GameState.set_meta("test_force_legendary", true)
	g.loot.roll_and_drop("boss", spot, {"drops": [4, 4]})
	GameState.set_meta("test_force_legendary", false)
	for i in 8:
		await snap("drops_arc_%d_%s" % [i, Settings.language])
		await da._wait(0.09)
	await da._wait(0.6)
	await snap("drops_landed_%s" % Settings.language)
	await da._wait(1.2)
	await snap("drops_beam_%s" % Settings.language)


## #71: the portal's vote cards, the Restless meter (building, warning, burning), a Hunted rift
## counting down and the hunter's arrival, the HUD badges and the map panel's badge card.
func _mods(_arg: String) -> void:
	var lang: String = Settings.language
	p.iframe_left = 9999.0
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	GameState.set_meta("force_mod", "")
	g.start_floor(3)
	await da._wait(1.5)
	for e in g.enemies_root.get_children():
		e.queue_free()
	g._boss_defeated.rpc(g.layout.portal_pos)
	await da._wait(5.0)
	p.host_teleport(g.portal.global_position + Vector2(0, 20))
	await da._wait(0.5)
	g.host_interact(p, g.portal)
	await da._wait(0.8)
	await snap("mods_vote_%s" % lang)
	var cards: Array = hud._overlay._cards.values()
	cards[1].grab_focus()
	await da._wait(0.4)
	g.request_mod_vote(str(hud._overlay._cards.keys()[1]))
	await da._wait(0.5)
	await snap("mods_vote_picked_%s" % lang)
	hud.close_overlay()
	g.request_mod_vote("")
	# Restless.
	GameState.set_meta("force_mod", "restless")
	g.start_floor(5)
	GameState.set_meta("force_mod", "")
	await da._wait(5.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var spot: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(spot)
	var m: Node = g.spawn_monster("ghoul", spot + Vector2(110, 10), false)
	await da._wait(0.2)
	m.set_physics_process(false)
	m.aggro = true
	await da._wait(0.8)
	await snap("mods_restless_building_%s" % lang)
	await da._wait(0.8)
	await snap("mods_restless_warning_%s" % lang)
	await da._wait(1.4)
	await snap("mods_restless_burning_%s" % lang)
	m.queue_free()
	# Hunted.
	GameState.set_meta("force_mod", "hunted")
	g.start_floor(6)
	GameState.set_meta("force_mod", "")
	await da._wait(5.0)
	for e in g.enemies_root.get_children():
		if not e.is_boss:
			e.queue_free()
	var md := FloorMods.def("hunted")
	g.mod_runner._hunt_at = g.floor_time + float(md.warn) + 0.2
	await da._wait(1.4)
	await snap("mods_hunted_rift_%s" % lang)
	await da._wait(float(md.warn) - 1.6)
	await snap("mods_hunted_rift_late_%s" % lang)
	await da._wait(0.6)
	await snap("mods_hunted_arrival_%s" % lang)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		if not str(e.hunter).is_empty():
			e.set_physics_process(false)
	await snap("mods_hunted_hunter_%s" % lang)
	hud.open_overlay(hud.menu_panel("map"))
	await da._wait(0.6)
	await snap("mods_map_badge_%s" % lang)
	hud.close_overlay()


## #73: the boon choice after a boss, the pick's flight to the portrait and the flare on the
## hero, the boon icons beside the portrait and the Character panel's boons.
func _boons(_arg: String) -> void:
	var lang: String = Settings.language
	p.iframe_left = 9999.0
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	for e in g.enemies_root.get_children():
		e.queue_free()
	# A few boons already, so the portrait row and the panel have something to show.
	p.boons = BalanceSuite.average_boons(p.class_id, 9)
	p.recompute_stats()
	g._boss_defeated.rpc(g.layout.portal_pos)
	await da._wait(float(GameData.bal("boons.choose_delay")) + 1.2)
	await snap("boons_choice_%s" % lang)
	if hud._overlay and hud._overlay.get("_cards") is Array:
		hud._overlay._cards[1].grab_focus()
		await da._wait(0.3)
		await snap("boons_choice_focus_%s" % lang)
		hud._overlay._choose(1)
		await da._wait(0.45)
		await snap("boons_pick_flight_%s" % lang)
		await da._wait(0.5)
		await snap("boons_pick_flare_%s" % lang)
	await da._wait(1.0)
	await snap("boons_hud_%s" % lang)
	hud.open_overlay(hud.menu_panel("character"))
	await da._wait(0.6)
	await snap("boons_character_%s" % lang)
	hud.close_overlay()


## #81: the gameplay effects in a small fight: statuses on a row of dummies, a crit, a leech, an
## avoid, a block, the aggro "!", an elite's target line and signature, XP motes, a dodge roll, a
## knockback, floor marks, the low-health vignette.
func _gfx(_arg: String) -> void:
	var lang: String = Settings.language
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 0.0
	var start: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(start)
	await da._wait(5.0)  # the floor banner has gone
	var ctx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	ctx.cannot_miss = true
	var sts := [["burn", "poison", "bleed"], ["freeze", "stun", "root"], ["silence", "fear", "blind"], ["haste_potion", "enrage", "hunters_mark"], ["chill", "shackle", "sunder"]]
	var dummies := []
	for i in sts.size():
		var d: Enemy = g.spawn_monster("training_dummy", g.nearest_floor(start + Vector2(-100 + i * 50, 40)), false)
		dummies.append(d)
	await da._wait(0.6)
	for i in sts.size():
		for st in sts[i]:
			dummies[i].status.apply(str(st), 30.0, 1.0, ctx)
	await da._wait(0.8)
	await snap("gfx_statuses_%s" % lang)
	for d in dummies:
		d.status.clear_all()
	var elite: Enemy = g.spawn_monster("ghoul", g.nearest_floor(start + Vector2(80, 40)), false, {"elite": ["molten", "shielded"]})
	await da._wait(0.3)
	elite.set_physics_process(false)
	elite.aggro = true
	elite.target = p
	await da._wait(0.25)
	await snap("gfx_aggro_target_%s" % lang)
	var cctx := ctx.duplicate()
	cctx.guaranteed_crit = true
	p.run_mods = [{"stat": "leech", "value": 0.5, "source": "t"}]
	p.recompute_stats()
	p.health.hp = p.health.max_hp * 0.6
	Combat.instance.deal_damage(cctx, dummies[2], 40.0)
	await da._wait(0.12)
	await snap("gfx_crit_leech_%s" % lang)
	p.run_mods = []
	p.recompute_stats()
	Combat.instance.fx.ring(start + Vector2(-60, 60), 50.0, "#ff6a20", "explosion", "fire")
	Combat.instance.fx.ring(start + Vector2(30, 70), 40.0, "#a8e4ff", "", "frost")
	p._dodge_left = 0.25
	await da._wait(0.12)
	await snap("gfx_dash_marks_%s" % lang)
	elite.contributors[p.peer_id] = Time.get_ticks_msec() / 1000.0
	Combat.instance.knock(dummies[4], Vector2(-500, 0))
	Combat.instance.deal_damage(ctx, elite, 999999.0, {"damage_type": "true"})
	await da._wait(0.25)
	await snap("gfx_xp_knock_%s" % lang)
	p.health.hp = p.health.max_hp * 0.15
	await da._wait(0.6)
	await snap("gfx_low_health_%s" % lang)
	p.health.hp = p.health.max_hp


## #77: the forge's door from the corridor, the chamber with Rolf at work (a strike and a rest),
## the forge window with a legendary chosen, three frames of the forging and the raised numbers.
func _forge(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	GameState.set_meta("force_forge", "on")
	g.start_floor(maxi(g.depth, 2))
	await da._wait(2.0)
	p = da._local()
	var fg: Dictionary = g.layout.get("forge", {})
	if fg.is_empty():
		da.check(false, "floor has a forge")
		return
	p.iframe_left = 9999.0
	p.host_add_gold(600)
	p.level = 8
	p.recompute_stats()
	for e in g.enemies_root.get_children():
		e.queue_free()
	var door: Node = g.dungeon.leaf_door("forge")
	p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 90)))
	await da._wait(4.0)
	await snap("forge_door")
	g.host_interact(p, door)
	await da._wait(0.8)
	await snap("forge_door_open")
	p.host_teleport(fg.npc + Vector2(0, 60))
	await da._wait(1.2)
	var anim: Node = g.dungeon.props["Forge_npc"].get_node("NpcAnim")
	await da._wait_until(func(): return anim._queue.size() > 0 and anim._queue[0][0] == "strike" and int(anim._queue[0][1]) == 4, 12.0)
	await snap("forge_room_strike")
	await da._wait(2.5)
	await snap("forge_room")
	p.host_give_item(ItemGenerator.make_legendary("crown_blood_chieftain", 3, RandomNumberGenerator.new()))
	await da._wait(0.3)
	p.host_teleport(fg.npc + Vector2(0, 30))
	await da._wait(0.3)
	g.host_interact(p, g.dungeon.props["Forge_npc"])
	await da._wait(0.8)
	var panel: Node = hud._overlay if hud.get("_overlay") else null
	if panel and panel.get("rows"):
		for r in panel.rows:
			if r.item.has("legendary"):
				r.button.grab_focus()
	await da._wait(0.4)
	await snap("forge_window")
	if panel:
		panel._forge_selected()
		await da._wait_until(func(): return panel.stage.phase == "strike", 3.0)
		await da._wait(0.2)
		await snap("forge_anim_strike")
		await da._wait_until(func(): return panel.stage.phase == "quench", 3.0)
		await da._wait(0.15)
		await snap("forge_anim_quench")
		await da._wait_until(func(): return panel.stage.phase == "glow", 3.0)
		await da._wait(0.1)
		await snap("forge_anim_glow")
		await da._wait_until(func(): return panel.stage.phase == "", 3.0)
		await da._wait(0.15)
		await snap("forge_done")
		hud.close_overlay()
	GameState.remove_meta("force_forge")


## #72: every event on one floor: the arena (its sigil and braziers, the doors sealing, a wave's
## rifts, the HUD counter, the reward chest), the vault (its door, the lever with the map link,
## the open vault), the shrine and its cards, the cursed chest waking as a mimic, the prisoner in
## the cage, the guard with the key and the freed ally.
func _events(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	GameState.set_meta("force_events", "arena,vault,shrine,cursed_chest,prisoner")
	GameState.set_meta("test_mimic", true)
	GameState.set_meta("test_prisoner", "ally")
	g.start_floor(4)
	await da._wait(5.0)
	p = da._local()
	p.iframe_left = 9999.0
	var fe: FloorEvents = g.events
	var ent: Dictionary = fe.entries
	da.check(ent.size() == 5, "all five events placed (%s)" % [ent.keys()])
	# The shrine.
	if ent.has("shrine"):
		_clear_monsters(true)
		p.host_teleport(g.nearest_floor(ent.shrine.pos + Vector2(0, 40)))
		await da._wait(1.2)
		await snap("ev_shrine_room")
		g.host_interact(p, g.dungeon.props["Event_shrine"])
		await da._wait(0.8)
		await snap("ev_shrine_cards")
		hud.close_overlay()
	# The prisoner.
	if ent.has("prisoner"):
		_clear_monsters(true)
		p.host_teleport(g.nearest_floor(ent.prisoner.pos + Vector2(0, 36)))
		await da._wait(1.2)
		da.log_line("prisoner npc: %s" % [g.dungeon.props["Event_prisoner"].get_node_or_null("PrisonerNpc")])
		await snap("ev_prisoner")
	# The cursed chest waking.
	if ent.has("cursed_chest"):
		_clear_monsters(false)
		p.host_teleport(g.nearest_floor(ent.cursed_chest.pos + Vector2(0, 26)))
		await da._wait(1.5)
		await snap("ev_cursed_chest")
		g.host_interact(p, g.dungeon.props["Event_cursed_chest"])
		await da._wait(0.7)
		await snap("ev_mimic_waking")
		await da._wait(1.0)
		await snap("ev_mimic")
		for e in g.enemies_root.get_children():
			if e.get_meta("event_mimic", false):
				e.queue_free()
	# The vault.
	if ent.has("vault"):
		var door: Node = g.dungeon.leaf_door("vault")
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 70)))
		await da._wait(1.2)
		await snap("ev_vault_door")
		p.host_teleport(g.nearest_floor(ent.vault.lever + Vector2(0, 40)))
		await da._wait(1.2)
		await snap("ev_vault_lever")
		g.host_interact(p, g.dungeon.props["Event_vault_lever"])
		await da._wait(1.0)
		p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, 60)))
		await da._wait(1.2)
		await snap("ev_vault_open")
	# The arena.
	if ent.has("arena"):
		for e in g.enemies_root.get_children():
			e.queue_free()
		var c: Vector2 = ent.arena.center
		p.host_teleport(g.nearest_floor(c + Vector2(0, 90)))
		await da._wait(1.0)
		await snap("ev_arena_idle")
		p.host_teleport(g.nearest_floor(c + Vector2(0, 40)))
		await da._wait(1.2)
		await snap("ev_arena_sealing")
		await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "fight" and fe.st("arena").get("warned", false), 8.0)
		await da._wait(0.6)
		await snap("ev_arena_wave_warn")
		await da._wait(2.0)
		await snap("ev_arena_wave")
		for k in 3:
			await da._wait_until(func(): return fe._wave_names.size() > 0 or str(fe.st("arena").get("state", "")) == "done", 12.0)
			for n in fe._wave_names.duplicate():
				var e2: Node = g.enemies_root.get_node_or_null(NodePath(n))
				if e2:
					Combat.instance.deal_damage(Combat.instance.make_ctx(p, {"id": "t", "school": "physical"}), e2, 99999.0, {"damage_type": "true"})
			await da._wait(0.5)
		await da._wait_until(func(): return str(fe.st("arena").get("state", "")) == "done", 20.0)
		await da._wait(1.2)
		await snap("ev_arena_won")
	GameState.remove_meta("force_events")
	GameState.remove_meta("test_mimic")
	GameState.remove_meta("test_prisoner")


func _clear_monsters(keep_guard: bool) -> void:
	for e in g.enemies_root.get_children():
		if not (keep_guard and e.get("guard")) and not e.is_boss:
			e.queue_free()


## #72: the cursed chest waking, frame by frame (debug / review).
func _mimic(_arg: String) -> void:
	GameState.set_meta("force_events", "cursed_chest")
	GameState.set_meta("test_mimic", true)
	g.start_floor(3)
	await da._wait(5.0)
	p = da._local()
	p.iframe_left = 9999.0
	_clear_monsters(false)
	var ch: Node2D = g.dungeon.props["Event_cursed_chest"]
	p.host_teleport(g.nearest_floor(ch.global_position + Vector2(0, 50)))
	await da._wait(1.5)
	await snap("mimic_0")
	g.host_interact(p, ch)
	for i in 5:
		await da._wait(0.3)
		await snap("mimic_%d" % (i + 1))
	GameState.remove_meta("force_events")
	GameState.remove_meta("test_mimic")


## #78: the speech bubbles of Archibald, Malphas, the smith and the prisoner.
func _npc(_arg: String) -> void:
	NpcTalk.met.clear()
	for setup in [["archibald", "off", "none"], ["malphas", "on", "prisoner"]]:
		GameState.set_meta("force_merchant", setup[0])
		GameState.set_meta("force_forge", setup[1])
		GameState.set_meta("force_events", setup[2])
		g.start_floor(4)
		await da._wait(5.0)
		p = da._local()
		p.iframe_left = 9999.0
		_clear_monsters(false)
		var door: Node = g.dungeon.leaf_door("merchant")
		door.host_unseal()
		var m: Node = g.dungeon.props["Merchant"]
		p.host_teleport(m.global_position + Vector2(0, 80))
		await da._wait(1.6)
		await snap("npc_%s" % setup[0])
		if setup[1] == "on":
			g.dungeon.leaf_door("forge").host_set_open(true)
			p.host_teleport(g.dungeon.props["Forge_npc"].global_position + Vector2(-30, 80))
			await da._wait(1.6)
			await snap("npc_blacksmith")
		if setup[2] == "prisoner":
			_clear_monsters(false)
			p.host_teleport(g.nearest_floor(g.dungeon.props["Event_prisoner"].global_position + Vector2(20, 64)))
			await da._wait(1.6)
			await snap("npc_prisoner")
	for k in ["force_merchant", "force_forge", "force_events"]:
		GameState.remove_meta(k)


## #76: a chapter of the Ownerless Book falling with its beam, open in the reader, and the codex
## with the story's chapters grouped on top.
func _cycle(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	p.iframe_left = 9999.0
	_clear_monsters(false)
	var ids := LoreCycle.chapters()
	for i in 2:
		Codex.mark_read(ids[i])
	var rng := RandomNumberGenerator.new()
	g.loot.drop_item(LootTable.make_book(ids[1], rng), g.nearest_floor(p.global_position + Vector2(50, 10)), p.global_position, 0.0)
	await da._wait(1.6)
	await snap("cycle_fall")
	hud.open_book(ids[1], "")
	await da._wait(0.8)
	await snap("cycle_reader")
	hud.close_overlay()
	hud.open_overlay(load("res://scripts/ui/codex_panel.gd").new())
	await da._wait(0.8)
	await snap("cycle_codex")
	hud.close_overlay()


## #74: every corrupted ability while it warns, and every ascended boss's mechanic while it warns.
func _deep(_arg: String) -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	await da._wait(3.5)
	p.iframe_left = 9999.0
	_clear_monsters(false)
	var spot: Vector2 = g.nearest_floor(g.layout.start + Vector2(60, 0))
	for ab in GameData.corruption.abilities:
		_clear_monsters(false)
		Combat.instance.clear_floor()
		await da._wait(0.3)
		p.host_teleport(g.nearest_floor(spot + Vector2(-60, 30)))
		var m: Enemy = g.spawn_monster("ghoul", spot, false, {"corrupt": str(ab)})
		if str(ab) == "shield":
			var bud: Enemy = g.spawn_monster("ghoul", spot + Vector2(34, 0), false)
			await da._wait(0.2)
			bud.health.hp *= 0.5
		await da._wait(0.4)
		m.set_physics_process(false)
		for b in m.behaviors:
			if b is CorruptBehavior:
				b.test_trigger(self)
		m.set_physics_process(true)
		await da._wait(float(GameData.corruption.abilities[ab].warn) * 0.5)
		await snap("deep_corrupt_%s" % ab)
		await da._wait(1.5)
	var ids: Array = GameData.bosses.keys()
	ids.sort()
	var boss_pos: Vector2 = g.layout.boss_pos
	for id in ids:
		_clear_monsters(false)
		for e in g.enemies_root.get_children():
			e.queue_free()
		Combat.instance.clear_floor()
		await da._wait(0.4)
		p.host_teleport(g.nearest_floor(boss_pos + Vector2(0, 80)))
		var boss: Enemy = g.spawn_monster(str(id), boss_pos, true, {"ascended": true})
		await da._wait(0.6)
		boss.add_threat(p, 10.0)
		for mm in boss.mechanics:
			if str(mm.params.get("id", "")) == "ascension":
				if str(mm.params.get("pattern", "")) == "echo":
					mm._t += 4.0
				mm.trigger()
		await da._wait(0.8)
		await snap("deep_ascended_%s" % id)
		await da._wait(2.0)
	_clear_monsters(false)
