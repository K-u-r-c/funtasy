class_name LevelUpFx
extends Node2D
## #48: the level-up effect on a hero, played on every peer (Player._level_up_fx): a column of
## golden light rising from the feet, a rune circle and two rings spreading on the ground, golden
## motes rising and sparks bursting out, a warm light that makes the hero glow, and "Level 7"
## floating above the head. Drawn unshaded and additive, so it reads in the dark and blooms.

const GOLD := Color(1.0, 0.82, 0.36)
const HOT := Color(1.7, 1.15, 0.42)  ## HDR: picked up by the glow
const LIFE := 2.4

var level := 1
var _t := 0.0
var _ground: Node2D
var _column: Node2D
var _light: PointLight2D
var _mote_emitter: CPUParticles2D
var _font: Font


func _init(new_level: int) -> void:
	level = new_level
	name = "LevelUpFx"


func _ready() -> void:
	_font = UITheme.font()
	var plain := CanvasItemMaterial.new()
	plain.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = plain  # the floating level text reads in the dark
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_ground = Node2D.new()
	_ground.z_index = -1  # under the hero
	_ground.material = add
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_column = Node2D.new()
	_column.z_index = 1  # over the hero
	_column.material = add
	_column.draw.connect(_draw_column)
	add_child(_column)
	_light = PointLight2D.new()
	LightLayers.setup_light(_light)
	_light.texture = GameData.texture("fx.light")
	_light.color = Color(1.0, 0.78, 0.4)
	_light.energy = 0.0
	_light.position = Vector2(0, -20)
	LightLayers.register(_light, float(GameData.bal("lighting.level_up_light_radius", 150)))
	add_child(_light)
	var tw := create_tween()
	tw.tween_property(_light, "energy", 2.6, 0.25)
	tw.tween_property(_light, "energy", 0.0, LIFE - 0.4).set_ease(Tween.EASE_IN)
	_burst(add)
	_motes(add)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	if _t > LIFE - 1.4 and _mote_emitter.emitting:
		_mote_emitter.emitting = false
	_ground.queue_redraw()
	_column.queue_redraw()
	queue_redraw()


## Sparks flying out from the feet at the start.
func _burst(mat: Material) -> void:
	var p := CPUParticles2D.new()
	p.material = mat
	p.z_index = 1
	p.texture = GameData.texture("fx.pixel")
	p.amount = 36
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = Vector2(0, -6)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 60)
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 120.0
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color_ramp = _ramp(HOT, Color(1.0, 0.5, 0.15, 0.0))
	p.emitting = true
	add_child(p)


## Golden motes rising around the hero while the column stands.
func _motes(mat: Material) -> void:
	var p := CPUParticles2D.new()
	p.material = mat
	p.z_index = 1
	p.texture = GameData.texture("fx.pixel")
	p.amount = 40
	p.lifetime = 1.3
	p.position = Vector2(0, -4)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(16, 4)
	p.direction = Vector2(0, -1)
	p.spread = 8.0
	p.gravity = Vector2(0, -40)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	p.color_ramp = _ramp(Color(2.0, 1.6, 0.6), Color(1.0, 0.8, 0.3, 0.0))
	add_child(p)
	_mote_emitter = p


func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


## Rune circle and two spreading rings, flattened for the 3/4 view.
func _draw_ground() -> void:
	var fade := clampf(1.0 - (_t - 1.4) / (LIFE - 1.4), 0.0, 1.0) if _t > 1.4 else 1.0
	var grow := clampf(_t / 0.35, 0.0, 1.0)
	_ground.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
	_ground.draw_circle(Vector2.ZERO, 26.0 * grow, Color(GOLD, 0.18 * fade))
	_ground.draw_arc(Vector2.ZERO, 26.0 * grow, 0.0, TAU, 40, Color(HOT, 0.8 * fade), 1.5)
	_ground.draw_arc(Vector2.ZERO, 20.0 * grow, 0.0, TAU, 40, Color(GOLD, 0.5 * fade), 1.0)
	for i in 8:
		var a := TAU * i / 8.0 + _t * 1.2
		var r0 := 20.0 * grow
		_ground.draw_line(Vector2.from_angle(a) * r0, Vector2.from_angle(a) * (r0 + 6.0), Color(HOT, 0.7 * fade), 1.5)
	for k in 2:
		var u := clampf((_t - k * 0.25) / 0.9, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			_ground.draw_arc(Vector2.ZERO, 14.0 + 50.0 * u, 0.0, TAU, 48, Color(HOT, 0.9 * (1.0 - u)), 2.0)
	_ground.draw_set_transform(Vector2.ZERO)


## The column: a vertical beam, wide and bright at first, narrowing and fading.
func _draw_column() -> void:
	var rise := clampf(_t / 0.3, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - 0.5) / (LIFE - 0.7), 0.0, 1.0)
	if fade <= 0.0:
		return
	var h := 150.0 * rise
	for layer in [[22.0, 0.35], [11.0, 0.6], [4.0, 1.0]]:
		var w: float = layer[0] * (1.0 + 0.15 * sin(_t * 18.0)) * (0.6 + 0.4 * fade)
		var a: float = layer[1] * fade
		var cols := PackedColorArray([Color(HOT, a), Color(HOT, a), Color(GOLD, 0.0), Color(GOLD, 0.0)])
		_column.draw_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(w, 0), Vector2(w * 0.4, -h), Vector2(-w * 0.4, -h)]), cols)


## "Level 7" rising above the head.
func _draw() -> void:
	var a := clampf(_t / 0.3, 0.0, 1.0) * (1.0 - clampf((_t - 1.6) / (LIFE - 1.6), 0.0, 1.0))
	var text := Loc.f("Level %d", [level])
	var size := 14
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(-w / 2.0, -62.0 - 18.0 * clampf(_t / 1.2, 0.0, 1.0))
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.1, 0.05, 0.0, 0.9 * a))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.86, 0.4, a))
