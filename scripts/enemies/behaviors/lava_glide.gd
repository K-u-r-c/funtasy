extends MonsterBehavior
## Flame Revenant: glides straight through walls and over lava (no wall collision, no path) and
## leaves a burning wall behind it every `every` s. params: every (2.5), lifetime (4)

var _left := 1.0
var walls := 0


func _ready() -> void:
	enemy.set_collision_mask_value(1, false)  # walls
	enemy.set_meta("ignores_hazards", true)


func move_override(_delta: float) -> Vector2:
	var t: Actor = enemy.target
	if t == null or not is_instance_valid(t) or enemy.global_position.distance_to(t.global_position) < 26.0:
		return Vector2.INF
	return (t.global_position - enemy.global_position).normalized()


func on_physics(delta: float) -> void:
	if enemy.target == null:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = float(p("every", 2.5))
	var ctx := Combat.instance.make_ctx(enemy, {"id": "fire_trail", "school": "spell", "damage_type": "fire"})
	var dir: Vector2 = enemy.facing if enemy.facing != Vector2.ZERO else Vector2.RIGHT
	Combat.instance.run_effect({"type": "terrain", "kind": "fire_wall", "shape": "line", "at": "self", "length": 64, "across": true,
		"lifetime": float(p("lifetime", 4.0)), "blocks": "movement",
		"zone": {"tick": 0.5, "damage": {"base": 2, "coef": 0.4}, "damage_type": "fire", "color": "#ff6a1a"}}, ctx, enemy.global_position - dir * 20.0, enemy.global_position + dir * 40.0)
	walls += 1


func test_check(_suite: RefCounted) -> String:
	return "" if walls > 0 else "no fire wall"
