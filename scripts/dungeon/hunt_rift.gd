class_name HuntRift
extends Node2D
## #71 Hunted, on every peer: the warning before a hunter steps out. A swirling red rift opens on
## the floor with a beam of light over it (the legendary beam's shader in the warning colour),
## sparks rising, a low sound, the hunter's name and the seconds left above it, all drawn over the
## fog so it is seen from afar (and pinged on the minimap by Game). On arrival it flashes, throws
## a shockwave and closes.

const BEAM_SHADER := preload("res://assets/shaders/legendary_beam.gdshader")

var title := ""
var warn := 4.5
var _t := 0.0
var _arrived := -1.0
var _beam: Sprite2D
var _sparks: CPUParticles2D
var _light: PointLight2D


func setup(pos: Vector2, hunter_title: String, warn_s: float) -> void:
	position = pos
	title = hunter_title
	warn = warn_s
	z_index = 61  # over the fog of war


func _ready() -> void:
	Telegraph.warned("hunter")
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add
	_beam = Sprite2D.new()
	_beam.texture = GameData.texture("fx.pixel")
	_beam.scale = Vector2(34, 260) / Vector2(_beam.texture.get_size())
	_beam.position = Vector2(0, -126)
	var bm := ShaderMaterial.new()
	bm.shader = BEAM_SHADER
	bm.set_shader_parameter("beam_color", UITheme.WARN)
	bm.set_shader_parameter("fade", 0.0)
	_beam.material = bm
	add_child(_beam)
	_sparks = CPUParticles2D.new()
	_sparks.texture = GameData.texture("fx.pixel")
	_sparks.amount = 30
	_sparks.lifetime = 1.2
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 16.0
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 18.0
	_sparks.gravity = Vector2(0, -60)
	_sparks.initial_velocity_min = 16.0
	_sparks.initial_velocity_max = 40.0
	_sparks.scale_amount_min = 1.0
	_sparks.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(2.2, 0.6, 0.3))
	ramp.set_color(1, Color(1.0, 0.1, 0.05, 0.0))
	_sparks.color_ramp = ramp
	_sparks.use_parent_material = true
	add_child(_sparks)
	_light = PointLight2D.new()
	LightLayers.setup_light(_light)
	_light.texture = GameData.texture("fx.light")
	_light.color = UITheme.WARN
	_light.texture_scale = 1.1
	_light.energy = 0.0
	add_child(_light)
	AudioManager.play_sfx_at("rift_open", position)


## The hunter steps out: flash, shockwave, then the rift closes.
func arrive() -> void:
	if _arrived >= 0.0:
		return
	_arrived = 0.0
	_sparks.emitting = false
	AudioManager.play_sfx_at("hunter_arrive", position)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	var open := clampf(_t / 0.6, 0.0, 1.0)
	var f := open
	if _arrived >= 0.0:
		_arrived += delta
		f = clampf(1.0 - (_arrived - 0.3) / 0.8, 0.0, 1.0)
		if _arrived > 1.4:
			queue_free()
	(_beam.material as ShaderMaterial).set_shader_parameter("fade", f)
	_light.energy = 1.8 * f + (2.5 * clampf(1.0 - _arrived / 0.3, 0.0, 1.0) if _arrived >= 0.0 else 0.0)
	# The hunter didn't come (left the floor, the boss woke): the rift closes on its own.
	if _arrived < 0.0 and _t > warn + 3.0:
		arrive()


func _draw() -> void:
	var open := clampf(_t / 0.6, 0.0, 1.0)
	var closing := clampf(1.0 - (_arrived - 0.3) / 0.8, 0.0, 1.0) if _arrived >= 0.0 else 1.0
	var r := 26.0 * open * closing
	var u := clampf(_t / maxf(warn, 0.01), 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	# The swirl: three turning arcs and a dark heart.
	draw_circle(Vector2.ZERO, r, Color(0.35, 0.02, 0.02, 0.6))
	for i in 3:
		var a0 := _t * (2.0 + i) + i * TAU / 3.0
		draw_arc(Vector2.ZERO, r * (0.55 + 0.15 * i), a0, a0 + PI * 1.2, 24, Color(UITheme.WARN, 0.8), 2.0)
	draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 40, Color(UITheme.WARN_SOFT, 0.5), 1.5)
	# The countdown ring fills as the hunter nears.
	if _arrived < 0.0:
		draw_arc(Vector2.ZERO, r + 9.0, -PI / 2.0, -PI / 2.0 + TAU * u, 40, Color(UITheme.WARN, 0.9), 2.5)
	else:
		var w := _arrived / 0.6
		draw_arc(Vector2.ZERO, 30.0 + 90.0 * w, 0.0, TAU, 48, Color(UITheme.WARN_SOFT, clampf(1.0 - w, 0.0, 1.0)), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _arrived < 0.0:
		var font := UITheme.font()
		var left := maxf(warn - _t, 0.0)
		var lines := [title, "%.1f" % left]
		for i in lines.size():
			var w2 := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY).x
			var at := Vector2(-w2 / 2.0, -44.0 + i * 16.0)
			draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_BODY, UITheme.WARN.lightened(0.35))
