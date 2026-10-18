class_name FxSuite
extends RefCounted
## #33 effects on allies (scenario "fx_lan": a priest host, a warrior client): on the host and on
## the client, Flash Heal shows a heal burst on the healed teammate, Renew a glow while it runs,
## Power Word: Shield a bubble while the absorb holds and a shatter when it breaks, Blessing of
## Might a buff flash on every teammate, Purify a cleanse flash.
## #34 (scenario "fx"): every AoE / zone / delayed effect in the data resolves to an element look.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


static func loops(a: Node) -> Array:
	var f: Node = a.get_node_or_null("ActorFx")
	return f._loops.keys() if f else []


static func played(path: NodePath, role: String) -> bool:
	return Combat.instance.fx.get_meta("actor_fx_log", []).any(func(e): return e[0] == String(path) and e[1] == role)


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
	p.skills = ["priest_holy_strike", "priest_heal", "priest_holy_shield", "priest_renew", "priest_blessing_of_might", "priest_purify"]
	p.resource.value = p.resource.max_value
	c.host_teleport(p.global_position + Vector2(70, 0))
	await da._wait(0.5)
	p.set_friendly_target(c.peer_id)
	Combat.instance.fx.set_meta("actor_fx_log", [])
	# Flash Heal on the client.
	c.health.hp = c.health.max_hp * 0.5
	p.request_skill.rpc_id(1, 1, c.global_position, c.peer_id)
	await da._wait(0.6)
	da.check(played(c.get_path(), "heal") or played(c.get_path(), "big_heal"), "Flash Heal shows a heal burst on the teammate (host)")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_seen", ["heal", "big_heal"]])
	await da._wait(0.6)
	# Renew: a glow while it runs.
	p.request_skill.rpc_id(1, 3, c.global_position, c.peer_id)
	await da._wait(0.6)
	da.check(loops(c).has("hot"), "Renew shows a heal-over-time glow on the teammate (%s)" % [loops(c)])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_loop", ["hot", true]])
	await da._wait(0.6)
	c.status.remove("renew")
	await da._wait(0.4)
	da.check(not loops(c).has("hot"), "the glow ends with the heal over time")
	# Power Word: Shield: bubble while the absorb holds, shatter when it breaks.
	p.request_skill.rpc_id(1, 2, c.global_position, c.peer_id)
	await da._wait(0.6)
	da.check(c.health.absorb > 0.0 and loops(c).has("shield"), "Power Word: Shield shows a bubble while the absorb holds")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_loop", ["shield", true]])
	await da._wait(0.6)
	c.health.absorb = 0.0
	await da._wait(0.4)
	var fxn: Node = c.get_node("ActorFx")
	var shards := fxn.get_children().filter(func(n): return n is AnimatedSprite2D and not fxn._loops.values().has(n))
	da.check(not loops(c).has("shield") and shards.size() >= 1, "the bubble shatters when the shield breaks")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_loop", ["shield", false]])
	await da._wait(0.6)
	# Blessing of Might: a buff flash on every teammate.
	Combat.instance.fx.set_meta("actor_fx_log", [])
	p.request_skill.rpc_id(1, 4, p.global_position, 0)
	await da._wait(0.6)
	da.check(played(c.get_path(), "buff") and played(p.get_path(), "buff"), "Blessing of Might flashes on every teammate, the caster too")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_seen", ["buff"]])
	await da._wait(0.6)
	# Purify: a cleanse flash.
	c.status.apply("poison", 6.0, 1.0, null)
	p.request_skill.rpc_id(1, 5, c.global_position, c.peer_id)
	await da._wait(0.6)
	da.check(played(c.get_path(), "cleanse") and not c.status.has("poison"), "Purify shows a cleanse flash on the teammate")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_seen", ["cleanse"]])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"fx_seen":
			var roles: Array = arg
			da.check(roles.any(func(r): return played(p.get_path(), r)), "the client sees the %s effect on itself" % [roles[0]])
		"fx_loop":
			var role: String = arg[0]
			var want: bool = arg[1]
			da.check(loops(p).has(role) == want, "the client %s the %s loop on itself" % ["shows" if want else "no longer shows", role])
