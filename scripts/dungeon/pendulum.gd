extends Node2D
## Crypt pendulum scythe (GDD 1.1) swinging across a narrow corridor. The swing comes from the
## shared floor clock (deterministic on every peer); the host hits actors the blade passes, at
## most once per `hit_cooldown`, with environment damage and a shove.

var axis := Vector2.RIGHT  ## swing direction (across the corridor)
var span := 40.0  ## half the swing length in px
var phase := 0.0
var _blade: Node2D
var _chain: Line2D
var _hit: Dictionary = {}


func setup(center: Vector2, swing_axis: Vector2, half_span: float, p: float) -> void:
	position = center
	axis = swing_axis.normalized()
	span = half_span
	phase = p
	_chain = Line2D.new()
	_chain.width = 1.0
	_chain.default_color = Color(0.45, 0.42, 0.4)
	_chain.z_index = 3
	add_child(_chain)
	_blade = Node2D.new()
	_blade.z_index = 3
	add_child(_blade)
	var s := Sprite2D.new()
	s.texture = GameData.texture("props.pendulum")
	s.position = Vector2(0, -12)
	_blade.add_child(s)


func blade_offset(floor_time: float) -> Vector2:
	var period := float(GameData.bal("hazards.pendulum_period", 2.4))
	return axis * sin((floor_time / period + phase) * TAU) * span


func update_state(floor_time: float) -> void:
	_blade.position = blade_offset(floor_time)
	_chain.clear_points()
	_chain.add_point(Vector2(0, -60))
	_chain.add_point(_blade.position + Vector2(0, -14))


func host_damage(actors: Array, floor_time: float) -> void:
	var at := position + blade_offset(floor_time)
	var now := floor_time
	for a in actors:
		if not a.is_targetable() or a.global_position.distance_to(at) > 14.0 + a.radius:
			continue
		if now < float(_hit.get(a, -99.0)) + float(GameData.bal("hazards.pendulum_hit_cooldown", 0.8)):
			continue
		_hit[a] = now
		Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, float(GameData.bal("hazards.pendulum_damage", 18)))
		Combat.instance.knock(a, axis * signf(cos((floor_time / float(GameData.bal("hazards.pendulum_period", 2.4)) + phase) * TAU)) * 160.0)
