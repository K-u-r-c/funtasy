class_name ArenaSigil
extends Node2D
## #72, every peer: the arena's sigil on the floor of its room - a ring of runes that glows ember
## while the trial waits (the room's tell), flares red and spins while the doors seal and the waves
## come, and dims to gold once the arena is won. `phase` is set by FloorEvents.

var phase := "idle"  ## idle / sealing / fight / done
var _t := 0.0
var _light: PointLight2D


func _ready() -> void:
	z_index = -6  # on the floor, under everyone
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_light = PointLight2D.new()
	LightLayers.setup_light(_light)
	_light.texture = GameData.texture("fx.light")
	_light.color = Color("ff5a30")
	_light.energy = 0.5
	LightLayers.register(_light, 90.0)
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	var target := {"idle": 0.45, "sealing": 1.6, "fight": 1.0, "done": 0.35}.get(phase, 0.45) as float
	_light.energy = lerpf(_light.energy, target * (0.85 + 0.15 * sin(_t * 6.0)), minf(delta * 4.0, 1.0))
	_light.color = Color("f0c040") if phase == "done" else Color("ff5a30")
	queue_redraw()


func _draw() -> void:
	var col := Color("f0c040") if phase == "done" else Color("ff4d3d")
	var hot := {"idle": 0.35, "sealing": 0.95, "fight": 0.7, "done": 0.3}.get(phase, 0.35) as float
	var pulse := 0.75 + 0.25 * sin(_t * (9.0 if phase == "sealing" else 2.5))
	var spin := _t * (1.6 if phase in ["sealing", "fight"] else 0.25)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))  # flat on the floor (3/4 view)
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 64, Color(col, hot * pulse), 2.0)
	draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 64, Color(col, hot * 0.6 * pulse), 1.0)
	# Twelve runes between the rings, turning.
	for i in 12:
		var a := spin + TAU * i / 12.0
		var p := Vector2.from_angle(a) * 40.0
		var q := Vector2.from_angle(a + 0.18) * 40.0
		draw_line(p + (p.normalized() * -3.0), q + (q.normalized() * 3.0), Color(col, hot * pulse), 1.5)
	# Crossed blades in the middle.
	draw_line(Vector2(-14, -14), Vector2(14, 14), Color(col, hot * 0.8), 2.0)
	draw_line(Vector2(14, -14), Vector2(-14, 14), Color(col, hot * 0.8), 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(col, hot * 0.5 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
