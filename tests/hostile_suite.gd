class_name HostileSuite
extends RefCounted
## #41 enemy targeting (scenario "hostile_lan" on a LAN pair of rangers): the "Target next enemy"
## action cycles only through enemies the player can see, then back to none; with an enemy locked
## the primary attack and a damage skill hit it while the cursor points elsewhere, on the host and
## from the client; a click on an enemy locks it, a click on empty ground clears the lock, and the
## lock drops when the enemy dies; out of reach the attack is refused with a message and costs
## nothing; the host refuses an enemy out of the hero's sight or one that doesn't exist.

var da: Node
var g: Node
var p: Player

const DMG_SKILL := "ranger_poison_arrow"


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _named(n: String) -> Actor:
	return g.enemies_root.get_node_or_null(n)


## A floor point within sight range that `from` has no line of sight to (behind a wall).
func _hidden_spot(from: Vector2) -> Vector2:
	var sight := float(GameData.bal("vision.max_sight", 600))
	for d in range(220, int(sight) - 60, 40):
		for k in 24:
			var c: Vector2 = g.nearest_floor(from + Vector2.from_angle(TAU * k / 24.0) * d)
			var dist := c.distance_to(from)
			if dist > 160.0 and dist < sight - 60.0 and not Combat.instance.has_los(from, c):
				return c
	return Vector2.INF


func _press(action: String, hold: float = 0.0) -> void:
	Input.action_press(action)
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame
	if hold > 0.0:
		await da._wait(hold)
	Input.action_release(action)
	await da.get_tree().physics_frame


func _cycle_seen() -> Array:
	var seen: Array = []
	p.set_hostile_target("")
	for i in 4:
		await _press("target_enemy")
		seen.append(p.hostile_name)
	return seen


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	for pl in [p, c]:
		pl.iframe_left = 9999.0
		pl.skills[1] = DMG_SKILL
		pl.host_take_torch()  # enemies are seen only where lit
		pl.resource.value = pl.resource.max_value
	# Somewhere with another room out of sight but within sight range.
	var hide := Vector2.INF
	for r in g.layout.rooms:
		var at: Vector2 = g.nearest_floor(Vector2(r.rect.get_center()) * g.dungeon.tile)
		hide = _hidden_spot(at)
		if hide != Vector2.INF:
			p.host_teleport(at)
			break
	da.check(hide != Vector2.INF, "found a spot out of sight within sight range")
	c.host_teleport(g.nearest_floor(p.global_position + Vector2(0, 50)))
	await da._wait(0.5)
	var a: Node = g.spawn_monster("training_dummy", g.nearest_floor(p.global_position + Vector2(150, 0)), false)
	var b: Node = g.spawn_monster("training_dummy", g.nearest_floor(p.global_position + Vector2(-110, 10)), false)
	var h: Node = g.spawn_monster("training_dummy", hide, false)
	await da._wait(1.2)
	var vis := p.visible_enemies().map(func(e): return str(e.name))
	da.check(vis.has(str(a.name)) and vis.has(str(b.name)) and not vis.has(str(h.name)),
			"the host sees the two dummies in its room, not the one behind the wall (%s)" % [vis])
	# Cycle: nearest first, only visible ones, then none.
	var seen := await _cycle_seen()
	da.check(seen.slice(0, 3) == [str(b.name), str(a.name), ""] and not seen.has(str(h.name)),
			"Target next enemy cycles nearest first through the visible enemies, then none (%s)" % [seen])
	# A click on A locks it; held on, the primary keeps hitting A while the cursor moves north.
	p.set_hostile_target("")
	p.auto_aim = a.global_position + Vector2(0, -a.radius)
	await da._wait(0.15)
	var hp0: float = a.health.hp
	Input.action_press("attack")
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame
	da.check(p.hostile_name == str(a.name), "host: a click on an enemy locks it")
	p.auto_aim = p.global_position + Vector2(0, -220)
	await da._wait(0.5)
	var hp_mid: float = a.health.hp
	await da._wait(1.2)
	Input.action_release("attack")
	await da._wait(0.6)
	da.check(a.health.hp < hp_mid and b.health.hp >= b.health.max_hp and p.hostile_name == str(a.name),
			"host: the held primary keeps hitting the locked A while the cursor points away (%.0f -> %.0f -> %.0f)" % [hp0, hp_mid, a.health.hp])
	p.auto_aim = p.global_position + Vector2(0, -220)
	var hp1: float = a.health.hp
	var hpb: float = b.health.hp
	await _press("skill_1", 0.1)
	await da._wait(0.8)
	da.check(a.health.hp < hp1 and b.health.hp >= hpb and p.cooldown_left(DMG_SKILL) > 0.0, "host: Viper Arrow (a damage skill) lands on the locked enemy (%.0f -> %.0f)" % [hp1, a.health.hp])
	# Out of reach: a melee skill (Cleave, 65 px) at the locked enemy 150 px away is refused with
	# a message and costs nothing.
	p.skills[2] = "warrior_cleave"
	await da._wait(0.3)
	var mana := p.resource.value
	var got: Array = []
	var cb := func(t: String, _col: Color): got.append(t)
	EventBus.hud_message.connect(cb)
	p._target_msg_at = -99.0
	await _press("skill_2", 0.1)
	await da._wait(0.5)
	EventBus.hud_message.disconnect(cb)
	da.check(got.has(Loc.t("Target out of range")) and p.cooldown_left("warrior_cleave") <= 0.0 and p.resource.value >= mana - 0.5,
			"host: a locked enemy out of reach refuses the attack with a message and costs nothing (%s)" % [got])
	# The lock drops when its enemy dies.
	p.set_hostile_target(str(a.name))
	await da._wait(0.2)
	Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, 9999999.0)
	await da._wait_until(func(): return not is_instance_valid(a) or not a.is_targetable(), 3.0)
	await da._wait(0.3)
	da.check(p.hostile_name == "", "host: the lock drops when the enemy dies")
	a = g.spawn_monster("training_dummy", g.nearest_floor(p.global_position + Vector2(150, 0)), false)
	await da._wait(0.8)
	# The client: cycle, click-lock, attack while aiming away, click on empty ground.
	NetworkManager.to_clients("DevAuto", "client_cmd", ["hs_client", [str(a.name), str(b.name), str(h.name)]])
	await da._wait(8.0)
	da.check(b.health.hp < b.health.max_hp, "the client's locked attacks hit B on the host")
	da.check(h.health.hp >= h.health.max_hp, "the enemy out of the client's sight took nothing")
	# The client's lock drops when its enemy dies on the host.
	NetworkManager.to_clients("DevAuto", "client_cmd", ["hs_lock", str(b.name)])
	await da._wait(1.0)
	Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), b, 9999999.0)
	await da._wait(1.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["hs_cleared", ""])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"hs_client":
			var a := _named(str(arg[0]))
			var b := _named(str(arg[1]))
			var hn := str(arg[2])
			var vis := p.visible_enemies().map(func(e): return str(e.name))
			var seen := await _cycle_seen()
			da.check(not seen.has(hn) and seen.has(str(b.name)) and seen.has("") and vis.size() >= 2,
					"client: Target next enemy offers only the enemies it can see (%s, visible %s)" % [seen, vis])
			# A click on B locks it; held on, the primary keeps hitting B while the cursor points away.
			p.set_hostile_target("")
			p.auto_aim = b.global_position + Vector2(0, -b.radius)
			await da._wait(0.2)
			Input.action_press("attack")
			await da.get_tree().physics_frame
			await da.get_tree().physics_frame
			da.check(p.hostile_name == str(b.name), "client: a click on an enemy locks it")
			p.auto_aim = p.global_position + Vector2(0, -220)
			await da._wait(0.6)
			var mid: float = b.health.hp
			await da._wait(1.2)
			Input.action_release("attack")
			await da._wait(0.5)
			da.check(b.health.hp < mid and p.hostile_name == str(b.name), "client: the held primary keeps hitting the locked B while the cursor points away (%.0f -> %.0f)" % [mid, b.health.hp])
			# Skill 1 too, the cursor still away.
			var before: float = b.health.hp
			await _press("skill_1", 0.1)
			await da._wait(0.9)
			da.check(b.health.hp < before, "client: Viper Arrow lands on the locked B (%.0f -> %.0f)" % [before, b.health.hp])
			# The host refuses an enemy this hero can't see, and one that doesn't exist.
			var got: Array = []
			var cb := func(t: String, _col: Color): got.append(t)
			EventBus.hud_message.connect(cb)
			p._target_msg_at = -99.0
			p.request_skill.rpc_id(1, 1, p.global_position, 0, hn)
			await da._wait(0.5)
			p._target_msg_at = -99.0
			p.request_skill.rpc_id(1, 1, p.global_position, 0, "E999999")
			await da._wait(0.5)
			EventBus.hud_message.disconnect(cb)
			da.check(got.has(Loc.t("Target not in line of sight")) and got.has(Loc.t("Invalid target")),
					"client: the host refuses an enemy out of sight and one that doesn't exist (%s)" % [got])
			# A click on empty ground clears the lock.
			p.auto_aim = p.global_position + Vector2(-60, -90)
			await da._wait(0.15)
			await _press("attack")
			da.check(p.hostile_name == "", "client: a click on empty ground clears the lock")
			p.auto_aim = Vector2.INF
		"hs_lock":
			p.set_hostile_target(str(arg))
		"hs_cleared":
			da.check(p.hostile_name == "", "client: the lock drops when the enemy dies on the host")
