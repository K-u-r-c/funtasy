extends BossMechanic
## Vespera P2 - wings unfold: she flies out of melee reach for `duration` s while the Chant of
## the Damned ramps on the whole party. Two consecrated shrines rise at the arena edges;
## activating both grounds her (stunned). params: every, duration (20), stun (3)

var _left := -1.0
var shrines: Array = []
var lit := {}
var _n := 0


func _ready() -> void:
	left = 0.5  # take off right after the phase starts


func trigger() -> void:
	if _left > 0.0:
		return
	_left = float(p("duration", 20.0))
	_n += 1
	var c := ctx()
	Combat.instance.apply_status(c, boss, "airborne", _left, 0.0)
	for pl in living_players():
		Combat.instance.apply_status(c, pl, "chant_of_the_damned", _left, Combat.instance.value_of_spec(p("chant", {"base": 1, "coef": 0.1}), c))
	var room := boss_room()
	var g := game()
	shrines.clear()
	lit.clear()
	for i in 2:
		var nm := "Shrine_%d_%d" % [_n, i]
		var x := room.position.x + 48.0 if i == 0 else room.end.x - 48.0
		g.dungeon.spawn_prop.rpc(nm, "consecrated_shrine", g.nearest_floor(Vector2(x, room.get_center().y)))
		shrines.append(nm)
	g.broadcast_message.rpc("Vespera takes wing! Light both consecrated shrines to bring her down!", "#e0d0ff")


func busy() -> bool:
	return _left > 0.0


func physics(delta: float) -> void:
	super.physics(delta)
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_land(false)


func on_interact(player: Player, node: Node) -> bool:
	if _left <= 0.0 or not shrines.has(str(node.get("prop_id"))):
		return false
	if lit.has(node.prop_id):
		return true
	lit[node.prop_id] = true
	game().dungeon.open_chest.rpc(node.prop_id)
	Combat.instance.fx.ring.rpc(node.global_position, 40.0, "#fff6c0", "")
	game().broadcast_message.rpc("%s lights a shrine (%d / 2)" % [player.display_name, lit.size()], "#fff6c0")
	if lit.size() >= shrines.size():
		_land(true)
	return true


func _land(grounded: bool) -> void:
	_left = -1.0
	boss.status.remove("airborne")
	for pl in living_players():
		pl.status.remove("chant_of_the_damned")
	var g := game()
	for nm in shrines:
		if g.dungeon.props.has(nm):
			g.dungeon.destroy_prop.rpc(nm)
	shrines.clear()
	if grounded:
		Combat.instance.apply_status(ctx(), boss, "stun", float(p("stun", 3.0)), 0.0)
		g.broadcast_message.rpc("Vespera crashes to the ground!", "#fff6c0")


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	# Out of melee reach while airborne.
	return 0.0 if _left > 0.0 and data.get("melee", false) else amount


func stop() -> void:
	if _left > 0.0:
		_land(false)


func test_check(suite: RefCounted) -> String:
	if _left > 0.0 and shrines.size() == 2:
		var g := game()
		for nm in shrines.duplicate():
			on_interact(suite.p, g.dungeon.props[nm])
		return "lighting shrines"
	return "" if not boss.status.has("airborne") and boss.status.has("stun") else "still airborne"
