class_name GameCamera
extends Camera2D
## Follows the local player (or the spectated teammate while dead), leans slightly toward the
## aim direction and applies restrained screen shake. The zoom adapts to the screen shape: the
## viewport expands with the window (stretch aspect "expand"), so ultrawide screens zoom in until
## the visible world fits camera.max_view_* and the dungeon bounds (never showing the void past
## the map), while narrow screens keep at least camera.min_view_* of the world in view.

var target: Node2D
var _shake := 0.0
var _shake_time := 0.0
var _bounds := Rect2()


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_zoom)
	_fit_zoom()
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
	_bounds = rect
	_fit_zoom()
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func _fit_zoom() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var z := float(GameData.bal("camera.zoom"))
	# Narrow / tall screens: zoom out (lower bound on the visible world).
	z = minf(z, minf(vp.x / float(GameData.bal("camera.min_view_width")), vp.y / float(GameData.bal("camera.min_view_height"))))
	# Wide screens and small floors: zoom in (upper bound wins over the lower one).
	z = maxf(z, maxf(vp.x / float(GameData.bal("camera.max_view_width")), vp.y / float(GameData.bal("camera.max_view_height"))))
	if _bounds.size.x > 0.0 and _bounds.size.y > 0.0:
		z = maxf(z, maxf(vp.x / _bounds.size.x, vp.y / _bounds.size.y))
	zoom = Vector2.ONE * z


## World-space size currently on screen (for tests and fog/vision tuning).
func visible_world_size() -> Vector2:
	return get_viewport_rect().size / zoom
