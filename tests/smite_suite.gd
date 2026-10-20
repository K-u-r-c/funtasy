class_name SmiteSuite
extends RefCounted
## #67 Priest Smite (scenario "smite_lan", priest host + a client): no damage and no heal through
## a wall; in the open it hurts an enemy (+1.5 Mana per hit) and heals an ally by the nerfed
## amount (2 + 30% power); a left click on the ally with Smite as the primary attack picks the
## ally and heals them in the same click.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _smite(at: Vector2) -> void:
	p.local_cd.clear()
	p.cooldowns.clear()
	var err := Combat.instance.try_use_skill(p, "priest_smite", at, {"primary": true})
	if not err.is_empty():
		da.log_line("smite refused: %s" % err)
	await da._wait(0.45)


## Two floor cells in a row with a wall between them, close enough for Smite (or []).
func _wall_pair() -> Array:
	var d: Node = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 6):
			var a := Vector2i(x, y)
			if d.cell_at(a) != DungeonGenerator.CELL_FLOOR or d.cell_at(a + Vector2i(1, 0)) != DungeonGenerator.CELL_WALL:
				continue
			for k in range(2, 5):
				var b := a + Vector2i(k, 0)
				if d.cell_at(b) == DungeonGenerator.CELL_FLOOR:
					var pa: Vector2 = d.cell_center(a)
					var pb: Vector2 = d.cell_center(b)
					if not Combat.instance.has_los(pa, pb):
						return [pa, pb]
					break
				if d.cell_at(b) != DungeonGenerator.CELL_WALL:
					break
	return []


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	# Smite on the left mouse button, as a player slots it in the Skill Book.
	var lo: Array = p.skills.duplicate()
	lo[lo.find("priest_smite")] = lo[0] if lo.has("priest_smite") else ""
	lo[0] = "priest_smite"
	p.skills = lo
	da.check(p.skills[0] == "priest_smite", "Smite is the priest's primary attack")
	for pl in [p, c]:
		pl.iframe_left = 9999.0
	var pair := _wall_pair()
	da.check(not pair.is_empty(), "a wall with floor on both sides within reach")
	if pair.is_empty():
		return
	# Through the wall: neither an enemy nor the ally.
	p.host_teleport(pair[0])
	var dummy: Node = g.spawn_monster(str(g.floor_def.monsters[0].id), pair[1], false)
	await da._wait(0.5)
	dummy.global_position = pair[1]
	dummy.process_mode = Node.PROCESS_MODE_DISABLED  # a dummy: it must not walk round the wall
	var hp0: float = dummy.health.hp
	da.log_line("wall pair %s -> %s, caster %s, dummy %s, los %s" % [pair[0], pair[1], p.global_position, dummy.global_position, Combat.instance.has_los(p.global_position, dummy.global_position)])
	await _smite(pair[1])
	da.log_line("after: dummy %s hp %.0f" % [dummy.global_position, dummy.health.hp])
	da.check(dummy.health.hp >= hp0, "Smite doesn't hurt an enemy behind a wall (%.0f -> %.0f)" % [hp0, dummy.health.hp])
	dummy.queue_free()
	c.host_teleport(pair[1])
	await da._wait(0.6)
	c.health.hp = c.health.max_hp * 0.5
	var chp := c.health.hp
	await _smite(c.global_position)
	da.check(c.health.hp <= chp, "Smite doesn't heal an ally behind a wall (%.0f -> %.0f)" % [chp, c.health.hp])
	# In the open: damage, the mana it gives back, and the nerfed heal.
	var open: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(open)
	c.host_teleport(g.nearest_floor(open + Vector2(70, 0)))
	await da._wait(0.6)
	var foe: Node = g.spawn_monster(str(g.floor_def.monsters[0].id), g.nearest_floor(open + Vector2(-70, 0)), false)
	await da._wait(0.4)
	foe.process_mode = Node.PROCESS_MODE_DISABLED
	p.resource.value = 10.0
	var fhp: float = foe.health.hp
	await _smite(foe.global_position)
	da.check(foe.health.hp < fhp, "Smite hurts an enemy in the open")
	da.check(absf(p.resource.value - 11.5) < 0.6, "a hit gives back 1.5 Mana (10 -> %.1f)" % p.resource.value)
	foe.queue_free()
	await da._wait(0.3)
	c.health.hp = c.health.max_hp * 0.5
	chp = c.health.hp
	await _smite(c.global_position)
	var healed: float = c.health.hp - chp
	# What the card says Smite heals now (crits aside), and what it healed before the nerf.
	var nums := Combat.skill_numbers(p.stats, p.level, GameData.skill("priest_smite"))
	var want := Combat.value_of({"base": 2, "coef": 0.3}, nums) * float(nums.heal_mult)
	var before := Combat.value_of({"base": 4, "coef": 0.6}, nums) * float(nums.heal_mult)
	da.check(healed > 0.0 and healed <= want * 2.2 + 1.0 and healed < before,
			"Smite heals the ally by the nerfed amount (+%.0f; now %.0f, before %.0f)" % [healed, want, before])
	# The click: aim at the ally, press the primary attack once.
	p.set_friendly_target(0)
	c.health.hp = c.health.max_hp * 0.5
	chp = c.health.hp
	p.local_cd.clear()
	p.cooldowns.clear()
	p.auto_aim = c.global_position
	await da.get_tree().physics_frame
	Input.action_press("attack")
	await da._wait(0.4)
	Input.action_release("attack")
	p.auto_aim = Vector2.INF
	await da._wait(0.3)
	da.check(p.friendly_peer == c.peer_id and c.health.hp > chp, "a click on the ally picks them and Smite heals them in the same click (picked %s, %.0f -> %.0f)" % [p.friendly_peer == c.peer_id, chp, c.health.hp])
	if not da.shot.is_empty() and DisplayServer.get_name() != "headless":
		await _review(c)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


## Review shots (windowed host with --shot): the effect at a few moments, on an enemy and an ally.
func _review(c: Player) -> void:
	var foe: Node = g.spawn_monster(str(g.floor_def.monsters[0].id), g.nearest_floor(p.global_position + Vector2(-80, 10)), false)
	await da._wait(0.5)
	for target in [foe, c]:
		for t in [0.18, 0.26, 0.36]:
			p.local_cd.clear()
			p.cooldowns.clear()
			p.casting = {}
			Combat.instance.try_use_skill(p, "priest_smite", target.global_position, {"primary": true})
			await da._wait(t)
			await da._snap(da.shot.get_base_dir(), "smite_%s_%d" % ["enemy" if target == foe else "ally", int(t * 100)])
			await da._wait(1.0)
