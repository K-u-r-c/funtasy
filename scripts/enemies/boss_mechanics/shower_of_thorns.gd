extends BossMechanic
## Cernunnos P2 - Shower of Thorns: every `every` s wood shards rain on the whole arena after a
## warning; heroes beneath a dolmen canopy (within `cover` px of one) are safe. Each shower cracks
## the dolmens a little; new ones rise if fewer than 2 still stand. params: every (12), warn (2), cover (36), damage

var _warn := -1.0
var showers := 0
var hit := 0


func trigger() -> void:
	if _warn >= 0.0:
		return
	_ensure_dolmens()
	_warn = float(p("warn", 2.0))
	var room := boss_room()
	Combat.instance.fx.telegraph.rpc(room.get_center(), room.size.x * 0.55, "#8a6a3a", _warn)
	game().broadcast_message.rpc("Shower of Thorns! Shelter under a dolmen!", "#c0a060")


func physics(delta: float) -> void:
	super.physics(delta)
	if _warn < 0.0:
		return
	_warn -= delta
	if _warn >= 0.0:
		return
	showers += 1
	var c := ctx()
	for pl in living_players():
		if not _covered(pl.global_position):
			Combat.instance.deal_damage(c, pl, Combat.instance.value_of_spec(p("damage", {"base": 10, "coef": 1.8}), c), {"area": true})
			hit += 1
	var room := boss_room()
	for i in 10:
		Combat.instance.fx.ring.rpc(Vector2(randf_range(room.position.x, room.end.x), randf_range(room.position.y, room.end.y)), 14.0, "#8a6a3a", "")


func _dolmens() -> Array:
	var out: Array = []
	for pr in game().dungeon.props.values():
		if is_instance_valid(pr) and str(pr.get("type")) == "dolmen" and pr.destructible() and boss_room().has_point(pr.global_position):
			out.append(pr)
	return out


func _covered(pos: Vector2) -> bool:
	for d in _dolmens():
		if d.global_position.distance_to(pos) <= float(p("cover", 36.0)):
			return true
	return false


func _ensure_dolmens() -> void:
	if _dolmens().size() >= 2:
		return
	var g := game()
	var room := boss_room()
	for i in 2:
		g.dungeon.spawn_prop.rpc("DolmenP2_%d_%d" % [showers, i], "dolmen", g.nearest_floor(room.position + room.size * Vector2(0.3 + 0.4 * i, 0.5)))


func test_trigger(suite: RefCounted) -> void:
	trigger()
	_warn = 0.1
	var room := boss_room()
	suite.p.host_teleport(game().nearest_floor(room.get_center() + Vector2(0, room.size.y * 0.35)))


func test_check(_suite: RefCounted) -> String:
	return "" if showers > 0 and hit > 0 else "no shower"
