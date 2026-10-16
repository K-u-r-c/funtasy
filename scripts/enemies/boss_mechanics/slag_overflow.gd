extends BossMechanic
## Ignis P1 - Slag Overflow: one half of the arena (left or right) is telegraphed, then floods
## with molten slag for `duration` s. A hero standing right beside a fallen ingot (on its high
## ground) is safe. params: every, warn (2.5), duration (6), damage (dict per 0.5 s)

var _warn := -1.0
var _left := -1.0
var _tick := 0.0
var _half := Rect2()
var burned := 0


func trigger() -> void:
	if _warn >= 0.0 or _left > 0.0:
		return
	var room := boss_room()
	var left := randf() < 0.5
	_half = Rect2(room.position, Vector2(room.size.x * 0.5, room.size.y)) if left else Rect2(room.position + Vector2(room.size.x * 0.5, 0), Vector2(room.size.x * 0.5, room.size.y))
	_warn = float(p("warn", 2.5))
	Combat.instance.fx.telegraph.rpc(_half.get_center(), minf(_half.size.x, _half.size.y) * 0.6, "#ff5511", _warn)
	game().broadcast_message.rpc("Slag Overflow! Get behind an ingot!", "#ff7a2a")


func physics(delta: float) -> void:
	super.physics(delta)
	if _warn >= 0.0:
		_warn -= delta
		if _warn < 0.0:
			_left = float(p("duration", 6.0))
			var c := ctx()
			c.damage_type = "fire"
			Combat.instance.add_zone({"type": "zone", "radius": minf(_half.size.x, _half.size.y) * 0.5, "duration": _left, "tick": 9.0, "color": "#ff5511", "light_only": true}, c, _half.get_center())
		return
	if _left <= 0.0:
		return
	_left -= delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var c2 := ctx()
	for pl in living_players():
		if _half.has_point(pl.global_position) and not _on_high_ground(pl.global_position):
			Combat.instance.deal_damage(c2, pl, Combat.instance.value_of_spec(p("damage", {"base": 3, "coef": 0.5}), c2), {"damage_type": "fire", "dot": true})
			burned += 1


func _on_high_ground(pos: Vector2) -> bool:
	var d: Node = game().dungeon
	for id in d.obstacles:
		var o: Dictionary = d.obstacles[id]
		if str(o.get("kind", "")) != "ingot":
			continue
		for cell in o.cells:
			if d.cell_center(cell).distance_to(pos) <= 30.0:
				return true
	return false


func stop() -> void:
	_warn = -1.0
	_left = -1.0


func test_trigger(suite: RefCounted) -> void:
	trigger()
	_warn = 0.1
	suite.p.host_teleport(game().nearest_floor(_half.get_center()))


func test_check(_suite: RefCounted) -> String:
	return "" if burned > 0 else "slag burned nobody"
