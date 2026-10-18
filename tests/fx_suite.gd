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


## #34 solo: every area effect in the data (skills, monster and boss skills, legendary and status
## procs, nested delayed effects) resolves to an element with a burst and a zone look; then a fire,
## a frost and a holy area are cast and show their own look.
func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var bad: Array = []
	var seen := {}
	var sources: Array = []
	for sid in GameData.skills:
		sources.append([str(sid), GameData.skills[sid], GameData.damage_type_of(GameData.skills[sid])])
	for lg in GameData.legendaries.values() if GameData.legendaries is Dictionary else GameData.legendaries:
		sources.append([str(lg.get("id", "")), lg, "physical"])
	for st in GameData.status_effects:
		sources.append([str(st), GameData.status_effects[st], str(GameData.status_effects[st].get("damage_type", "physical"))])
	for src in sources:
		_scan(src[1], {"damage_type": src[2]}, src[0], bad, seen)
	da.check(bad.is_empty() and seen.size() >= 6, "every area effect resolves to an element look (%d elements; missing: %s)" % [seen.size(), bad.slice(0, 6)])
	for kind in ["burst", "zone"]:
		for el in GameData.fx.get(kind, {}):
			da.check(GameData.asset_exists(str(GameData.fx[kind][el].key)), "%s look of %s has its art" % [kind, el])
	# Cast a few: each area plays its own element (no plain circle).
	p.iframe_left = 9999.0
	var fx: Node = Combat.instance.fx
	fx.set_meta("element_fx_log", [])
	var ctx := Combat.instance.make_ctx(p, GameData.skill("mage_fireball"))
	Combat.instance.run_effect({"type": "aoe", "radius": 50, "damage": {"base": 1, "coef": 0}, "damage_type": "fire", "at": "self"}, ctx, p.global_position + Vector2(80, 0), p.global_position)
	Combat.instance.run_effect({"type": "aoe", "radius": 50, "damage": {"base": 1, "coef": 0}, "damage_type": "frost", "at": "self"}, ctx, p.global_position + Vector2(-80, 0), p.global_position)
	Combat.instance.run_effect({"type": "zone", "radius": 50, "duration": 2.0, "tick": 1.0, "heal": {"base": 1, "coef": 0}, "targets": "allies", "at": "self"}, ctx, p.global_position, p.global_position)
	await da._wait(0.4)
	var log: Array = fx.get_meta("element_fx_log", [])
	da.check(log.has(["burst", "fire"]) and log.has(["burst", "frost"]) and log.has(["zone", "holy"]), "cast areas show their element's look (%s)" % [log])


func _scan(o: Variant, ctx: Dictionary, src: String, bad: Array, seen: Dictionary) -> void:
	if o is Dictionary:
		var t := str(o.get("type", ""))
		if t in ["aoe", "zone"]:
			var el := CombatEffects_fx_element(o, ctx)
			seen[el] = true
			for kind in ["burst", "zone"]:
				var spec: Dictionary = GameData.fx.get(kind, {}).get(el, {})
				if spec.is_empty() or not GameData.asset_exists(str(spec.get("key", ""))):
					bad.append("%s %s -> %s" % [src, t, el])
		for v in o.values():
			_scan(v, ctx, src, bad, seen)
	elif o is Array:
		for v in o:
			_scan(v, ctx, src, bad, seen)


static func CombatEffects_fx_element(eff: Dictionary, ctx: Dictionary) -> String:
	return CombatEffects.fx_element(eff, ctx)


## #36 (scenario "spouts", run with --biome=sewers / foundry): every wall spout shows its pipe or
## vent art on the wall, its spray leaves the mouth, and a warning runs right before each spray.
func run_spouts() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var sp: Array = g.dungeon.spouts
	da.check(not sp.is_empty(), "the floor has wall spouts (%d)" % sp.size())
	for s in sp:
		var key := str(s.cfg.get("sprite", ""))
		var tex: Texture2D = s._pipe.texture
		if key in ["props.acid_spout", "props.flame_jet"] or tex == null or tex.get_height() < 32 or s._spray.position.y < 12.0:
			da.check(false, "spout at %s has a visible pipe / vent (%s)" % [s.cell, key])
			return
	da.check(true, "every spout has its pipe / vent art and sprays from its mouth")
	var s0: Node = sp[0]
	var period := float(s0.cfg.get("period", 5.0))
	var warned := false
	var t := 0.0
	var ok := true
	while t < period * 2.0:
		var on: bool = s0.is_on(t)
		var before: bool = s0.warning(t)
		if before:
			warned = true
		if on and not s0.is_on(t - 0.05):
			ok = ok and warned
			warned = false
		t += 0.05
	da.check(ok, "a warning runs right before every spray")
	# Every wall side a spout can face: over many floors of this biome, the generator only puts
	# spouts in north walls facing down, the side the pipe / vent art is drawn for.
	var fd: Dictionary = g.floor_def
	var sides := {}
	var count := 0
	for i in 40:
		var lay: Dictionary = DungeonGenerator.new().generate(9100 + i, fd, 1.0, 1 + i % 8)
		for spd in lay.get("spouts", []):
			sides[spd.dir] = true
			count += 1
	da.check(count > 0 and sides.keys() == [Vector2i.DOWN], "over 40 %s floors every one of %d spouts faces down from a north wall (%s)" % [str(fd.get("id", "")), count, sides.keys()])


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
	# #34: Holy Nova's burst and Consecration's ground look on both peers.
	p.skills[1] = "priest_holy_nova"
	p.skills[2] = "priest_consecration"
	p.cooldowns.clear()
	p.resource.value = p.resource.max_value
	Combat.instance.fx.set_meta("element_fx_log", [])
	p.request_skill.rpc_id(1, 1, p.global_position, 0)
	await da._wait(0.8)
	p.request_skill.rpc_id(1, 2, p.global_position, 0)
	await da._wait(0.8)
	var log: Array = Combat.instance.fx.get_meta("element_fx_log", [])
	da.check(log.has(["burst", "holy"]) and log.has(["zone", "holy"]), "Holy Nova and Consecration show the holy burst and ground on the host (%s)" % [log])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["fx_elements", [["burst", "holy"], ["zone", "holy"]]])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"fx_seen":
			var roles: Array = arg
			da.check(roles.any(func(r): return played(p.get_path(), r)), "the client sees the %s effect on itself" % [roles[0]])
		"fx_elements":
			var log: Array = Combat.instance.fx.get_meta("element_fx_log", [])
			da.check(Array(arg).all(func(x): return log.has(x)), "the client shows the same area looks %s (%s)" % [arg, log])
		"fx_loop":
			var role: String = arg[0]
			var want: bool = arg[1]
			da.check(loops(p).has(role) == want, "the client %s the %s loop on itself" % ["shows" if want else "no longer shows", role])
