extends CorruptBehavior
## Corrupted - Blightwalker: while it hunts, every `every` s the ground under it festers: a green
## ring warns, then a pool of blight lingers there for `duration` s, hurting heroes inside.

var _left := 1.5


func on_physics(delta: float) -> void:
	if not enemy.aggro or not enemy.is_alive():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = float(p("every", 3.5))
	var at := enemy.global_position
	var c := ctx()
	warn_at(at, float(p("radius", 26)), "Blight")
	act_after(func():
		Combat.instance.add_zone({"type": "zone", "radius": float(p("radius", 26)), "duration": float(p("duration", 5.0)),
			"tick": float(p("tick", 0.5)), "damage": p("damage", {"base": 2, "coef": 0.3}), "damage_type": "nature", "fx": "nature", "color": str(p("color", "#8cff4a"))}, c, at))


func test_trigger(_suite: RefCounted) -> void:
	enemy.aggro = true
	_left = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if uses > 0 else "no blight pool"
