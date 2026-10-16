extends BossMechanic
## Murk Amalgam P1 - Tidal Flush: raised platforms stand in the arena; every `every` s the
## boss slams the channel and, after a `telegraph` warning, a wall of sewage sweeps the room:
## everyone not standing on a platform takes `damage` and is shoved.
## params: every, telegraph (2.5), platforms (3), damage (dict)

var platforms: Array = []
var _left := -1.0
var swept := 0


func _ready() -> void:
	var room := boss_room()
	var g := game()
	var n := int(p("platforms", 3))
	for i in n:
		var x := lerpf(room.position.x + 64.0, room.end.x - 64.0, (i + 0.5) / n)
		var y := room.position.y + room.size.y * (0.3 if i % 2 == 0 else 0.7)
		var nm := "Platform_%d" % i
		g.dungeon.spawn_prop.rpc(nm, "sewer_platform", g.nearest_floor(Vector2(x, y)))
		platforms.append(nm)


func trigger() -> void:
	if _left >= 0.0:
		return
	_left = float(p("telegraph", 2.5))
	var room := boss_room()
	Combat.instance.fx.telegraph.rpc(room.get_center(), room.size.x * 0.6, "#4a7a3a", _left)
	game().broadcast_message.rpc("Tidal Flush! Climb a raised platform!", "#7fd94a")
	boss.play_action.rpc("attack", boss.facing)


func physics(delta: float) -> void:
	super.physics(delta)
	if _left < 0.0:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = -1.0
	var g := game()
	var c := ctx()
	var room := boss_room()
	Combat.instance.fx.sound.rpc("wave", room.get_center())
	Combat.instance.fx.ring.rpc(room.get_center(), room.size.x * 0.6, "#4a7a3a", "")
	for pl in living_players():
		if on_platform(pl.global_position) or not room.grow(32).has_point(pl.global_position):
			continue
		Combat.instance.deal_damage(c, pl, Combat.instance.value_of_spec(p("damage", {"base": 14, "coef": 2.0}), c), {"damage_type": "nature", "area": true})
		Combat.instance.knock(pl, Vector2.RIGHT * 220.0)
		swept += 1


func on_platform(pos: Vector2) -> bool:
	var g := game()
	for nm in platforms:
		var pr: Node = g.dungeon.props.get(nm)
		if pr and pr.global_position.distance_to(pos) <= 34.0:
			return true
	return false


func stop() -> void:
	_left = -1.0


func test_trigger(suite: RefCounted) -> void:
	trigger()
	_left = 0.3


func test_check(_suite: RefCounted) -> String:
	return "" if swept > 0 and platforms.size() == int(p("platforms", 3)) else "nobody swept"
