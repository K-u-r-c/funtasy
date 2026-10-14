class_name GameCamera
extends Camera2D
## Follows the local player (or the spectated teammate while dead), leans slightly toward the
## aim direction and applies restrained screen shake.

var target: Node2D
var _shake := 0.0
var _shake_time := 0.0


func _ready() -> void:
	zoom = Vector2.ONE * float(GameData.bal("camera.zoom"))
	position_smoothing_enabled = true
	position_smoothing_speed = float(GameData.bal("camera.smoothing"))
	EventBus.screen_shake.connect(_on_shake)


func _on_shake(strength: float, duration: float) -> void:
	if not Settings.screen_shake:
		return
	_shake = maxf(_shake, strength)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	if is_instance_valid(target) and target.is_inside_tree():
		var look := Vector2.ZERO
		if target is Player and target.is_local():
			look = (target.aim_pos - target.global_position).limit_length(float(GameData.bal("camera.aim_lookahead")))
		global_position = target.global_position + Vector2(0, -16) + look
	if _shake_time > 0.0:
		_shake_time -= delta
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, float(GameData.bal("camera.shake_decay")) * delta)
	else:
		offset = Vector2.ZERO


func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
