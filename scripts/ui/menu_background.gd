extends Control
## Animated menu backdrop: dark gradient, drifting embers and a faint torch glow.

const COUNT := 70

var _motes: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in COUNT:
		_motes.append({
			"pos": Vector2(rng.randf_range(0, 960), rng.randf_range(0, 540)),
			"speed": rng.randf_range(6.0, 28.0),
			"size": rng.randi_range(1, 3),
			"phase": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	for m in _motes:
		m.pos.y -= m.speed * delta
		m.pos.x += sin(_time * 0.5 + m.phase) * 6.0 * delta
		if m.pos.y < -4.0:
			m.pos = Vector2(randf_range(0, size.x), size.y + 4.0)
	queue_redraw()


func _draw() -> void:
	var steps := 24
	for i in steps:
		var t := float(i) / (steps - 1)
		var c := Color(0.03, 0.025, 0.04).lerp(Color(0.13, 0.06, 0.06), t)
		draw_rect(Rect2(0, size.y * i / steps, size.x, size.y / steps + 1.0), c)
	var flicker := 0.85 + 0.15 * sin(_time * 7.0) * sin(_time * 3.3)
	for r in [260.0, 190.0, 120.0]:
		draw_circle(Vector2(size.x * 0.78, size.y * 0.95), r, Color(1.0, 0.45, 0.15, 0.035 * flicker))
	for m in _motes:
		var a := 0.3 + 0.4 * (0.5 + 0.5 * sin(_time * 2.0 + m.phase))
		draw_rect(Rect2(m.pos, Vector2.ONE * m.size), Color(1.0, 0.55, 0.25, a))
