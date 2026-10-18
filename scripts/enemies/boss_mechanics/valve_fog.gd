extends BossMechanic
## Krazik P1: a lethal green fog builds up in the arena (a ramping party DoT, one level per `rise`
## s, up to `max`). Three exhaust valves stand at the edges; venting any valve clears the fog.
## params: valves (3), rise (1.0), max (8), chant (dict, damage per level)

var valves: Array = []
var level := 0.0
var _tick := 0.0
var vented := 0


func _ready() -> void:
	var room := boss_room()
	var g := game()
	var spots := [Vector2(room.position.x + 40, room.get_center().y), Vector2(room.end.x - 40, room.get_center().y),
		Vector2(room.get_center().x, room.end.y - 40)]
	for i in mini(int(p("valves", 3)), spots.size()):
		var nm := "Valve_%d" % i
		g.dungeon.spawn_prop.rpc(nm, "exhaust_valve", g.nearest_floor(spots[i]))
		valves.append(nm)


func physics(delta: float) -> void:
	level = minf(level + delta / float(p("rise", 1.0)) * 0.25, float(p("max", 8)))
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if level < 1.0:
		return
	var c := ctx()
	var per := Combat.instance.value_of_spec(p("chant", {"base": 1, "coef": 0.1}), c)
	for pl in living_players():
		if boss_room().grow(16).has_point(pl.global_position):
			Combat.instance.deal_damage(c, pl, per * floorf(level), {"damage_type": "nature", "dot": true})
	Combat.instance.fx.ring.rpc(boss_room().get_center(), 30.0 + level * 12.0, "#7fd94a", "")


func on_interact(player: Player, node: Node) -> bool:
	if not valves.has(str(node.get("prop_id"))):
		return false
	level = 0.0
	vented += 1
	Combat.instance.fx.ring.rpc(node.global_position, 60.0, "#c0ffc0", "")
	Combat.instance.fx.sound.rpc("acid_hiss", node.global_position)
	game().broadcast_message.rpc("%s vents the green fog!", "#c0ffc0", [player.display_name])
	return true


func stop() -> void:
	var g := game()
	for nm in valves:
		if g.dungeon.props.has(nm):
			g.dungeon.destroy_prop.rpc(nm)
	valves.clear()


func test_trigger(suite: RefCounted) -> void:
	level = 4.0
	await suite.da._wait(0.2)
	var g := game()
	if not valves.is_empty() and g.dungeon.props.has(valves[0]):
		on_interact(suite.p, g.dungeon.props[valves[0]])


func test_check(_suite: RefCounted) -> String:
	return "" if valves.size() == int(p("valves", 3)) and vented > 0 and level < 1.0 else "fog not vented"
