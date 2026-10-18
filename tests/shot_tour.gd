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

