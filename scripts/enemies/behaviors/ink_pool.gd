extends MonsterBehavior
## Ink Horror: flows as an invulnerable pool of ink toward its target, coalesces right behind them
## and lashes out (its skill blots the hero's screen), then melts back after `surface` s.
## params: surface (4), speed_mult (1.5)

var pooled := true
var _left := 0.0
var surfaced := 0


func _ready() -> void:
	set_state("puddle")


func is_targetable() -> bool:
	return not pooled


func on_think(_g: Node) -> bool:
	if not pooled:
		_left -= float(GameData.bal("ai.think_interval"))
		if _left <= 0.0:
			pooled = true
			set_state("puddle")
		return false
	var t: Actor = enemy.target
	if t == null or not is_instance_valid(t):
		# The pool picks its prey itself (the default think is skipped while it flows).
		var best := 300.0
		for pl in _g.players_root.get_children():
			if pl.is_targetable() and pl.global_position.distance_to(enemy.global_position) < best:
				best = pl.global_position.distance_to(enemy.global_position)
				t = pl
		enemy.target = t
	if t and is_instance_valid(t) and t.global_position.distance_to(enemy.global_position) <= 28.0:
		pooled = false
		_left = float(p("surface", 4.0))
		set_state("")
		surfaced += 1
	return pooled


func move_override(_delta: float) -> Vector2:
	var t: Actor = enemy.target
	if not pooled or t == null or not is_instance_valid(t):
		return Vector2.INF
	# Aim for the spot right behind the target.
	var behind: Vector2 = t.global_position - t.facing * 22.0
	return (behind - enemy.global_position).normalized() * float(p("speed_mult", 1.5))


func test_trigger(suite: RefCounted) -> void:
	enemy.add_threat(suite.p, 10.0)


func test_check(_suite: RefCounted) -> String:
	return "" if surfaced > 0 else "never surfaced"
