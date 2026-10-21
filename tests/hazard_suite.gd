class_name HazardSuite
extends RefCounted
## #101 monsters are spared by the floor's hazards (scenario "hazards" on a Foundry floor, solo;
## "hazards_lan" on a LAN pair): a monster standing in lava for several ticks keeps its health
## while a hero there burns; spikes, pressure plates, wall spouts, cauldrons and the Archives'
## traps (all trap_ctx) neither hurt nor afflict a monster but do hurt a hero, and a snare waits
## for a hero; a hero's explosive barrel still blasts the monsters around it; on LAN the client
## sees the monster in lava at full health.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


## A lava cell's centre (Vector2.INF when the floor has none).
func _lava() -> Vector2:
	var d: Node = g.dungeon
	for y in d.size.y:
		for x in d.size.x:
			var c: Vector2 = d.cell_center(Vector2i(x, y))
			if d.is_lava(c):
				return c
	return Vector2.INF


func _clear() -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	await _clear()
	p.iframe_left = 9999.0
	var lava := _lava()
	da.check(lava != Vector2.INF, "the Foundry floor has lava")
	if lava == Vector2.INF:
		return
	var m: Enemy = g.spawn_monster("ghoul", lava, false)
	await da._wait(0.2)
	m.set_physics_process(false)
	m.host_teleport(lava)
	var hp0: float = m.health.hp
	var tick := float(GameData.bal("hazards.lava_tick"))
	await da._wait(tick * 3.0 + 0.3)
	da.check(is_instance_valid(m) and m.health.hp >= hp0, "a monster standing in lava for 3 ticks keeps its health (%.0f -> %.0f)" % [hp0, m.health.hp if is_instance_valid(m) else 0.0])
	# A hero in the same lava burns.
	m.host_teleport(g.nearest_floor(g.layout.start))
	p.iframe_left = 0.0
	p.host_teleport(lava)
	var php: float = p.health.hp
	await da._wait(tick * 2.0 + 0.3)
	da.check(p.health.hp < php, "a hero in the lava burns (%.0f -> %.0f)" % [php, p.health.hp])
	p.iframe_left = 9999.0
	p.health.hp = p.health.max_hp
	p.host_teleport(g.nearest_floor(g.layout.start))
	await da._wait(0.3)
	# Every trap context: no damage, no status on a monster; damage on a hero.
	var tc: Dictionary = Combat.instance.trap_ctx()
	var mhp: float = m.health.hp
	var dealt: float = Combat.instance.deal_damage(tc, m, 50.0)
	var st: bool = Combat.instance.apply_status(tc, m, "bleed", 4.0, 2.0)
	p.iframe_left = 0.0
	var hero_dealt: float = Combat.instance.deal_damage(tc, p, 5.0)
	p.iframe_left = 9999.0
	da.check(dealt == 0.0 and not st and m.health.hp >= mhp and hero_dealt > 0.0, "spikes, plates, spouts, cauldrons and traps spare monsters (%.0f, %s) and hurt heroes (%.0f)" % [dealt, st, hero_dealt])
	# A floor snare waits for a hero: a monster walks over it.
	var snare_at: Vector2 = g.nearest_floor(m.global_position + Vector2(0, 40))
	var zid: int = Combat.instance.add_zone({"type": "trap", "trigger_radius": 16, "duration": 30.0, "color": "#6a4a1a", "sprite": "root_snare",
		"effects": [{"type": "status", "target": "event_target", "status": "root", "duration": 2.0}]}, Combat.instance.trap_ctx(), snare_at)
	m.host_teleport(snare_at)
	await da._wait(0.6)
	da.check(Combat.instance.zones.has(zid) and not m.status.has("root"), "a monster walks over a floor snare without springing it")
	Combat.instance.zones.erase(zid)
	# A hero's explosive barrel still blasts monsters.
	await _clear()
	var bpos: Vector2 = g.nearest_floor(g.layout.start + Vector2(0, 60))
	g.dungeon.spawn_prop.rpc("HazardBarrel", "barrel_explosive", bpos)
	await da._wait(0.3)
	var m2: Enemy = g.spawn_monster("ghoul", bpos + Vector2(20, 0), false)
	await da._wait(0.3)
	m2.set_physics_process(false)
	var b0: float = m2.health.hp
	var barrel: Node = g.dungeon.props.get("HazardBarrel")
	if barrel:
		barrel.take_damage(9999.0, Combat.instance.make_ctx(p, {"id": "t", "school": "melee"}))
	await da._wait(0.6)
	da.check(barrel != null and (not is_instance_valid(m2) or m2.health.hp < b0), "a hero's explosive barrel still hurts the monsters around it")
	await _clear()


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	await _clear()
	var lava := _lava()
	da.check(lava != Vector2.INF, "host: the Foundry floor has lava")
	if lava == Vector2.INF:
		return
	var m: Enemy = g.spawn_monster("ghoul", lava, false)
	await da._wait(0.2)
	m.set_physics_process(false)
	m.host_teleport(lava)
	await da._wait(float(GameData.bal("hazards.lava_tick")) * 3.0 + 0.3)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["hz_check", str(m.name)])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	match cmd:
		"hz_check":
			var m: Node = g.enemies_root.get_node_or_null(str(arg))
			da.check(m != null and m.health.hp >= m.health.max_hp - 0.5, "client: the monster in the lava is at full health")
