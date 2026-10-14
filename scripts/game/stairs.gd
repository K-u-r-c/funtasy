extends Node2D
## Placeholder exit stairs, drawn procedurally.

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for i in 4:
		var c := Color(0.9, 0.8, 0.3).darkened(i * 0.18)
		draw_rect(Rect2(-12 + i * 3, -12 + i * 6, 24 - i * 6, 6), c)
	var pulse := 14.0 + sin(_time * 3.0) * 2.0
	draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 24, Color(1, 0.95, 0.5, 0.6), 1.5)
