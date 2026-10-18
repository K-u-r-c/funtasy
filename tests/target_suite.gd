class_name TargetSuite
extends RefCounted
## #39 friendly targeting (scenario "target_lan" on a LAN pair of priests): with a teammate picked
## as the friendly target, Flash Heal and Power Word: Shield land on them while the cursor points
## elsewhere, on the host and from the client; without a pick the cursor rule holds; out of reach
## the cast is refused with a message and costs nothing; Tab cycles through the living party and
## back to none; a click on a teammate or on their party frame picks them.

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
	await da._wait(2.0)


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
