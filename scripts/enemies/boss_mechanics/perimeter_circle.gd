extends BossMechanic
## Krazik P1: rides around the arena's edge (`margin` cells in) swinging his censer at anyone
## close; his normal abilities still fire. params: speed (1.0 x move speed), margin (2)

var _angle := 0.0


func _ready() -> void:
	_angle = randf() * TAU


func busy() -> bool:
	return false


func physics(delta: float) -> void:
	var room := boss_room().grow(-float(p("margin", 2)) * game().dungeon.tile)
	var c := room.get_center()
	var rx := room.size.x * 0.5
	var ry := room.size.y * 0.5
	var speed := boss.move_speed() * float(p("speed", 1.0))
	_angle += speed * delta / maxf((rx + ry) * 0.5, 1.0)
	goal = c + Vector2(cos(_angle) * rx, sin(_angle) * ry)


var goal := Vector2.INF
var _start := Vector2.INF


func move_override(_delta: float) -> Vector2:
	if goal == Vector2.INF or boss.global_position.distance_to(goal) < 6.0:
		return Vector2.INF if goal == Vector2.INF else Vector2.ZERO
	return (goal - boss.global_position).normalized()


func test_trigger(_suite: RefCounted) -> void:
	_start = boss.global_position


func test_check(_suite: RefCounted) -> String:
	return "" if _start != Vector2.INF and boss.global_position.distance_to(_start) > 40.0 else "not circling"
