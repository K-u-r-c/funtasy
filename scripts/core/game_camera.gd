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
var _look := Vector2.ZERO  ## current lean toward the aim (world px)
var _last_target: Node2D
var _last_pos := Vector2.ZERO


var _base_zoom := 1.0

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
		var want := Vector2.ZERO
		if target is Player and target.is_local():
			want = _look_target(target)
		# The lean eases toward its target on its own (frame-rate independent), so moving the
		# mouse never jerks the view.
		_look = _look.lerp(want, 1.0 - exp(-float(GameData.bal("camera.look_smoothing")) * delta))
		global_position = target.global_position + Vector2(0, -16) + _look
		# A teleport (next floor, continued game) snaps the view instead of panning across the map.
		if target == _last_target and target.global_position.distance_to(_last_pos) > float(GameData.bal("camera.snap_distance", 160.0)):
			reset_smoothing()
		_last_target = target
		_last_pos = target.global_position
		# Eagle Eye: the hero's own view widens by 30%.
		var eagle: bool = target is Player and target.is_local() and target.status.has_flag("eagle_eye")
		var want_z := _base_zoom / (float(GameData.bal("camera.eagle_eye_view", 1.3)) if eagle else 1.0)
		zoom = zoom.lerp(Vector2.ONE * want_z, minf(1.0, delta * 4.0))
	if _shake_time > 0.0:
		_shake_time -= delta
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, float(GameData.bal("camera.shake_decay")) * delta)
	else:
		offset = Vector2.ZERO


## Lean toward the aim. With the mouse it comes from the cursor's place on the screen (not its
## world position, which moves with the camera and would feed back into the lean), with a dead
## zone around the centre and an eased curve; with a pad it follows the aim stick.
func _look_target(p: Player) -> Vector2:
	var reach := float(GameData.bal("camera.aim_lookahead"))
	var dead := float(GameData.bal("camera.look_deadzone"))
	var v := Vector2.ZERO
	if InputSettings.last_kind == "pad" or p.auto_aim != Vector2.INF:
		v = (p.aim_pos - p.global_position) / 160.0
	else:
		var vp := get_viewport().get_visible_rect().size
		v = (get_viewport().get_mouse_position() - vp / 2.0) / (vp / 2.0)
	var l := minf(v.length(), 1.0)
	if l <= dead:
		return Vector2.ZERO
	var t := (l - dead) / (1.0 - dead)
	return v.normalized() * reach * t * t * (3.0 - 2.0 * t)


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
	_base_zoom = z


## World-space size currently on screen (for tests and fog/vision tuning).
func visible_world_size() -> Vector2:
	return get_viewport_rect().size / zoom
