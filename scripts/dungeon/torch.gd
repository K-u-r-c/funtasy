extends Node2D
## Wall torch: sprite + flickering shadow-casting light + embers.

var color := Color(1.0, 0.6, 0.27)
var light: PointLight2D
var _t := 0.0
var _base_energy := 1.15


func _ready() -> void:
	_t = randf() * 10.0
	var s := Sprite2D.new()
	s.texture = GameData.texture("props.torch")
	s.offset = Vector2(0, -14)
	add_child(s)
	light = PointLight2D.new()
	light.texture = GameData.texture("fx.light")
	light.color = color
	light.energy = _base_energy
	light.texture_scale = 2.4
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	light.position = Vector2(0, 8)
	add_child(light)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = 6
	p.lifetime = 0.9
	p.position = Vector2(0, -22)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = Color(1.6, 0.8, 0.3)
	add_child(p)


func _process(delta: float) -> void:
	if not light.enabled:
		return
	_t += delta
	light.energy = _base_energy + sin(_t * 9.0) * 0.06 + sin(_t * 23.0) * 0.04
