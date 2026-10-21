class_name ArenaBars
extends Node2D
## #72, every peer: the arena's bars across a sealed doorway: glowing red iron bars that slam
## down with sparks, a pulsing warning light, drawn over the fog of war so the party sees which
## ways out are shut.

var rect := Rect2()  ## the doorway (world)
var vertical := false
var _t := 0.0
var _light: PointLight2D


func setup(door_rect: Rect2, is_vertical: bool) -> void:
	rect = door_rect
	vertical = is_vertical
	z_index = 61


func _ready() -> void:
	# The door node sits at the bottom centre of its rect; draw in its local space.
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add
	_light = PointLight2D.new()
	LightLayers.setup_light(_light)
	_light.texture = GameData.texture("fx.light")
	_light.color = UITheme.WARN
	_light.energy = 0.9
	_light.position = Vector2(0, -rect.size.y / 2.0)
	LightLayers.register(_light, 60.0)
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.energy = 0.7 + 0.3 * sin(_t * 5.0)
	queue_redraw()


func _draw() -> void:
	var drop := clampf(_t / 0.18, 0.0, 1.0)  # the bars slam down
	var r := Rect2(Vector2(-rect.size.x / 2.0, -rect.size.y), rect.size)
	var pulse := 0.55 + 0.45 * sin(_t * 5.0)
	var c := Color(UITheme.WARN, 0.55 + 0.35 * pulse)
	var n := 5 if not vertical else 3
	if not vertical:
		for i in n:
			var x := r.position.x + (i + 0.5) * r.size.x / n
			draw_line(Vector2(x, r.position.y - 6.0), Vector2(x, r.position.y - 6.0 + (r.size.y + 4.0) * drop), c, 2.0)
		draw_line(Vector2(r.position.x, r.position.y + 2.0), Vector2(r.end.x, r.position.y + 2.0), c, 2.0)
	else:
		for i in n:
			var y := r.position.y + (i + 0.5) * r.size.y / n
			draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x * drop, y), c, 2.0)
	draw_rect(r, Color(UITheme.WARN, 0.08 * pulse), true)
