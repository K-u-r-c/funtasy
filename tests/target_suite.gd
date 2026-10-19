class_name TargetSuite
extends RefCounted
## #39 friendly targeting (scenario "target_lan" on a LAN pair of priests): with a teammate picked
## as the friendly target, Flash Heal and Power Word: Shield land on them while the cursor points
## elsewhere, on the host and from the client; without a pick the cursor rule holds; out of reach
## the cast is refused with a message and costs nothing; Tab cycles through the living party and
## back to none; a click on a teammate or on their party frame picks them; a click on empty ground
## (on host and client) clears the pick and still attacks, a second click on the pick clears it (#40);
## with no enemy lock (#53), a click on an enemy is an attack and skills aim at the cursor.

var da: Node
var g: Node
var p: Player

const HEAL := "priest_heal"
const SHIELD := "priest_holy_shield"


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _slot(pl: Player, sid: String) -> int:
	return pl.skills.find(sid)


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
		pl.skills[2] = SHIELD
		pl.resource.value = pl.resource.max_value
	p.host_teleport(g.nearest_floor(p.global_position))
	c.host_teleport(p.global_position + Vector2(90, 0))
	await da._wait(0.6)
	var away := p.global_position + Vector2(-260, 0)
	# Host: no pick -> the heal follows the cursor (pointing away from the client: nobody there,
	# so it falls back to the caster).
	c.health.hp = c.health.max_hp * 0.4
	p.set_friendly_target(0)
	p.request_skill.rpc_id(1, _slot(p, HEAL), away, 0)
	await da._wait(0.8)
	da.check(c.health.hp <= c.health.max_hp * 0.41, "without a friendly target the heal follows the cursor, not the teammate")
	# Host: pick the client -> heal and shield land on them, the cursor still pointing away.
	p.cooldowns.clear()
	p.set_friendly_target(c.peer_id)
	var hp0 := c.health.hp
	p.request_skill.rpc_id(1, _slot(p, HEAL), away, p.friendly_peer)
	await da._wait(0.8)
	da.check(c.health.hp > hp0 + 5.0, "with the client picked, Flash Heal heals them while the cursor points away (%.0f -> %.0f)" % [hp0, c.health.hp])
	p.request_skill.rpc_id(1, _slot(p, SHIELD), away, p.friendly_peer)
	await da._wait(0.8)
	da.check(c.health.absorb > 0.0 and c.status.has("pw_shield"), "Power Word: Shield lands on the picked teammate")
	# Out of reach: refused with a message, no cooldown, no mana.
	p.cooldowns.clear()
	c.host_teleport(g.nearest_floor(p.global_position + Vector2(0, 0)) + Vector2(420, 0))
	await da._wait(0.5)
	var mana := p.resource.value
	var got: Array = []
	var cb := func(t: String, _col: Color): got.append(t)
	EventBus.hud_message.connect(cb)
	p.request_skill.rpc_id(1, _slot(p, HEAL), away, p.friendly_peer)
	await da._wait(0.5)
	EventBus.hud_message.disconnect(cb)
	da.check(p.cooldown_left(HEAL) <= 0.0 and p.resource.value >= mana - 0.5 and got.has(Loc.t("Target out of range")),
			"a picked teammate out of reach refuses the cast with a message (%s)" % [got])
	c.host_teleport(p.global_position + Vector2(90, 0))
	p.set_friendly_target(0)
	await da._wait(0.5)
	# The client picks the host with Tab and heals it through the real input path.
	p.health.hp = p.health.max_hp * 0.4
	c.cooldowns.clear()
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tg_tab_heal", 1])
	await da._wait(3.0)
	da.check(p.health.hp > p.health.max_hp * 0.45, "the client's Tab pick and Flash Heal heal the host while its cursor points away")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tg_click", 1])
	await da._wait(4.5)
	# #40 on the host: the pick clears with a click on empty ground, which still swings.
	p.set_friendly_target(c.peer_id)
	await click_empty(c.peer_id)
	# #53: no enemy lock (removed #41) on the host, then on the client.
	await da._wait(0.5)
	var names := await _enemy_pair(p)
	await enemy_clicks(names)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.4)
	names = await _enemy_pair(c)
	# The host runs the client's casts from its own copy of the loadout.
	var cprim: Variant = c.skills[0]
	c.skills[0] = "priest_smite"
	c.skills[3] = "priest_smite"
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tg_enemies", names])
	await da._wait(6.0)
	c.skills[0] = cprim


## #40: with `pid` picked, a click on empty ground clears the pick and is a normal attack; a click
## on the teammate picks them, a second click on them clears it again.
func click_empty(pid: int) -> void:
	await da._wait(0.3)
	var mate: Player = null
	for pl in g.players_root.get_children():
		if pl.peer_id == pid:
			mate = pl
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var f: Node = null
	for fr in hud._party_box.get_children():
		if fr.visible and fr.p == mate:
			f = fr
	da.check(p.friendly_peer == pid and (f == null or f._target_icon.visible), "%s: the teammate is picked and marked" % ["host" if p.peer_id == 1 else "client"])
	da.check(f != null and f.tooltip_text.contains(InputSettings.prompt_for("target_ally")) and f.tooltip_text.length() > 40,
			"%s: the party frame's tooltip says how to pick and clear (%s)" % ["host" if p.peer_id == 1 else "client", f.tooltip_text if f else ""])
	p.local_cd.clear()
	p._pending.clear()
	var empty := p.global_position + (p.global_position - mate.global_position).normalized() * 90.0
	await click(empty)
	await da._wait(0.2)
	da.check(p.friendly_peer == 0 and (f == null or not f._target_icon.visible), "%s: a click on empty ground clears the pick and its marker" % ["host" if p.peer_id == 1 else "client"])
	da.check(p._pending.has(0) or p.local_cd.has(0), "%s: that click still attacks" % ["host" if p.peer_id == 1 else "client"])
	await da._wait(0.5)
	await click(mate.global_position + Vector2(0, -14))
	da.check(p.friendly_peer == pid, "%s: a click on the teammate picks them" % ["host" if p.peer_id == 1 else "client"])
	await click(mate.global_position + Vector2(0, -14))
	da.check(p.friendly_peer == 0, "%s: a second click on the picked teammate clears the pick" % ["host" if p.peer_id == 1 else "client"])


## Host: two training dummies 110 px east and west of `pl`; returns their node names.
func _enemy_pair(pl: Player) -> Array:
	var out: Array = []
	for dx in [110.0, -110.0]:
		var e: Node = g.spawn_monster("training_dummy", g.nearest_floor(pl.global_position + Vector2(dx, 0)), false)
		out.append(str(e.name))
	await da._wait(0.8)
	return out


## #53 (on the peer running it): the enemy lock is gone. No "Target next enemy" action exists; a
## click on enemy A is just an attack; the held primary then follows the cursor to B and leaves A
## alone; a damage skill tapped at A lands on A, not on B.
func enemy_clicks(names: Array) -> void:
	var who := "host" if p.peer_id == 1 else "client"
	var a: Actor = g.enemies_root.get_node_or_null(str(names[0]))
	var b: Actor = g.enemies_root.get_node_or_null(str(names[1]))
	da.check(not InputMap.has_action("target_enemy") and not InputSettings.bindings.has("target_enemy")
			and not p.has_method("set_hostile_target"), "%s: no enemy lock action or state (#53)" % who)
	if a == null or b == null:
		da.check(false, "%s: the two dummies exist" % who)
		return
	var prim: Variant = p.skills[0]
	p.skills[0] = "priest_smite"
	p.skills[3] = "priest_smite"
	p.local_cd.clear()
	p._pending.clear()
	p.set_friendly_target(0)
	await da._wait(0.3)
	var a0: float = a.health.hp
	await click(a.global_position + Vector2(0, -a.radius))
	await da._wait(0.9)
	da.check(a.health.hp < a0, "%s: a click on an enemy is an attack on it (%.0f -> %.0f)" % [who, a0, a.health.hp])
	var a1: float = a.health.hp
	var b1: float = b.health.hp
	p.auto_aim = b.global_position + Vector2(0, -b.radius)
	await da._wait(0.2)
	Input.action_press("attack")
	await da._wait(1.6)
	Input.action_release("attack")
	await da._wait(0.6)
	da.check(b.health.hp < b1 and a.health.hp >= a1, "%s: after clicking A the held primary hits B at the cursor, not A (A %.0f -> %.0f, B %.0f -> %.0f)" % [who, a1, a.health.hp, b1, b.health.hp])
	p.auto_aim = a.global_position + Vector2(0, -a.radius)
	await da._wait(0.6)
	var a2: float = a.health.hp
	var b2: float = b.health.hp
	Input.action_press(Player.SLOT_ACTIONS[3])
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame
	Input.action_release(Player.SLOT_ACTIONS[3])
	await da._wait(0.9)
	da.check(a.health.hp < a2 and b.health.hp >= b2, "%s: a skill tapped at the cursor lands there (A %.0f -> %.0f, B %.0f -> %.0f)" % [who, a2, a.health.hp, b2, b.health.hp])
	p.auto_aim = Vector2.INF
	p.skills[0] = prim


func click(at: Vector2) -> void:
	p.auto_aim = at
	await da._wait(0.15)
	Input.action_press("attack")
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame
	Input.action_release("attack")
	await da._wait(0.15)
	p.auto_aim = Vector2.INF


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"tg_tab_heal":
			var seen: Array = []
			p.set_friendly_target(0)
			for i in 3:
				Input.action_press("target_ally")
				await da.get_tree().physics_frame
				await da.get_tree().physics_frame
				Input.action_release("target_ally")
				await da.get_tree().physics_frame
				seen.append(p.friendly_peer)
			da.check(seen.has(int(arg)) and seen.has(p.peer_id) and seen.has(0), "Tab cycles through the party and back to none (%s)" % [seen])
			while p.friendly_peer != int(arg):
				p.cycle_friendly_target()
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			var f: Node = null
			for fr in hud._party_box.get_children():
				if fr.visible and fr.p and fr.p.peer_id == int(arg):
					f = fr
			await da._wait(0.2)
			da.check(f != null and f._target_icon.visible, "the picked teammate's party frame is marked")
			p.auto_aim = p.global_position + Vector2(0, 260)
			await da._wait(0.2)
			var slot := p.skills.find(HEAL)
			Input.action_press(Player.SLOT_ACTIONS[slot])
			await da._wait(0.4)
			Input.action_release(Player.SLOT_ACTIONS[slot])
			p.auto_aim = Vector2.INF
		"tg_click":
			p.set_friendly_target(0)
			var host: Player = null
			for pl in g.players_root.get_children():
				if pl.peer_id == int(arg):
					host = pl
			# A click on the teammate's body picks them (and doesn't swing).
			p.auto_aim = host.global_position + Vector2(0, -14)
			await da._wait(0.2)
			Input.action_press("attack")
			await da._wait(0.2)
			Input.action_release("attack")
			await da._wait(0.2)
			da.check(p.friendly_peer == int(arg), "a click on a teammate picks them")
			p.auto_aim = Vector2.INF
			# A click on their party frame clears it again, a second click picks.
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			for fr in hud._party_box.get_children():
				if fr.visible and fr.p == host:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = true
					fr.gui_input.emit(ev)
			await da._wait(0.2)
			da.check(p.friendly_peer == 0, "a click on the picked teammate's party frame clears the pick")
			# #40 on the client.
			p.set_friendly_target(int(arg))
			await click_empty(int(arg))
		"tg_enemies":
			await da._wait(0.3)
			await enemy_clicks(arg)
