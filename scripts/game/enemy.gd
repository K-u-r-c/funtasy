extends CharacterBody2D
## Placeholder slime. Only the host runs AI and takes damage; position and hp are replicated.

const AGGRO_RANGE := 150.0
const TOUCH_RANGE := 11.0
const TOUCH_COOLDOWN := 0.9
const KNOCKBACK := 140.0

var hp: int = 3  # replicated
var max_hp: int = 3
var speed := 38.0

var _touch_cd := 0.0
var _knock := Vector2.ZERO
var _flash := 0.0
var _last_hp := -1


func _ready() -> void:
	add_to_group("enemies")
	_last_hp = hp


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if hp < _last_hp:
		_flash = 0.12
	_last_hp = hp
	queue_redraw()
	if not multiplayer.is_server():
		return
	_touch_cd = maxf(_touch_cd - delta, 0.0)
	_knock = _knock.move_toward(Vector2.ZERO, 500.0 * delta)

	var target := _nearest_player()
	var chase := Vector2.ZERO
	if target:
		chase = (target.global_position - global_position).normalized() * speed
		if _touch_cd <= 0.0 and global_position.distance_to(target.global_position) < TOUCH_RANGE:
			_touch_cd = TOUCH_COOLDOWN
			target.take_damage.rpc_id(target.get_multiplayer_authority(), 1)
	velocity = chase + _knock
	move_and_slide()


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := AGGRO_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Host only (called from Game.hit_enemy).
func take_damage(amount: int, from: Vector2) -> bool:
	hp -= amount
	_knock = (global_position - from).normalized() * KNOCKBACK
	return hp <= 0


func _draw() -> void:
	var c := Color(0.8, 0.25, 0.3) if _flash <= 0.0 else Color.WHITE
	draw_rect(Rect2(-6, -5, 12, 10), c)
	draw_rect(Rect2(-6, -5, 12, 10), Color.BLACK, false, 1.0)
	draw_rect(Rect2(-3, -2, 2, 2), Color.WHITE)
	draw_rect(Rect2(1, -2, 2, 2), Color.WHITE)
	if hp < max_hp:
		draw_rect(Rect2(-6, -9, 12, 2), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-6, -9, 12.0 * hp / max_hp, 2), Color(0.4, 1, 0.4))
