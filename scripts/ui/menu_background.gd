extends Control
## Animated menu backdrop: gradient plus slowly drifting, twinkling squares.

const COUNT := 48

var _motes: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in COUNT:
		_motes.append({
			"pos": Vector2(rng.randf_range(0, 640), rng.randf_range(0, 360)),
			"speed": rng.randf_range(4.0, 22.0),
			"size": rng.randi_range(1, 3),
			"phase": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	for m in _motes:
		m.pos.y -= m.speed * delta
		m.pos.x += sin(_time * 0.4 + m.phase) * 4.0 * delta
		if m.pos.y < -4.0:
			m.pos = Vector2(randf_range(0, 640), 364.0)
	queue_redraw()


func _draw() -> void:
	var steps := 18
	for i in steps:
		var t := float(i) / (steps - 1)
		var c := Color(0.05, 0.05, 0.12).lerp(Color(0.16, 0.1, 0.26), t)
		draw_rect(Rect2(0, size.y * i / steps, size.x, size.y / steps + 1.0), c)
	for m in _motes:
		var a := 0.25 + 0.35 * (0.5 + 0.5 * sin(_time * 1.5 + m.phase))
		draw_rect(Rect2(m.pos, Vector2.ONE * m.size), Color(0.7, 0.75, 1.0, a))
