extends Node2D
## #49: the mark over remains that will rise again, on every peer: a pulsing unholy glow on the
## ground, a soul wisp bobbing over the remains with motes drifting up, a ring above that empties
## as the rise comes closer with the seconds left inside it, and "Rises again" above. It sits in
## the y-sorted entities next to its remains (the bone pile, or the corpse a cultist is raising),
## follows them, shares their fog of war visibility and goes with them. Game._rise_mark /
## _rise_clear add and remove it.

const VIOLET := Color(0.72, 0.42, 1.0)
const HOT := Color(1.5, 0.8, 2.4)  ## HDR: picked up by the glow
const SICK := Color(0.55, 1.0, 0.55)

var remains: Node2D
var kind := ""  ## "reassemble" (a bone pile) or "raise" (a corpse being raised)
var total := 1.0
var _deadline := 0.0
var _born := 0.0
var _font: Font
var _ground: Node2D


func _init(on: Node2D, k: String, seconds: float) -> void:
	remains = on
	name = "RiseMark_" + str(on.name)
	kind = k
	total = maxf(seconds, 0.1)
	var now := Time.get_ticks_msec() / 1000.0
	_deadline = now + seconds
	_born = now


## Seconds until the rise, counted on this peer from what the host sent.
func left() -> float:
	return maxf(_deadline - Time.get_ticks_msec() / 1000.0, 0.0)


func _ready() -> void:
	_font = UITheme.font()
	global_position = remains.global_position
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var plain := CanvasItemMaterial.new()
	plain.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = plain
	_ground = Node2D.new()
	_ground.z_index = 0  # additive, over the floor and the remains (a corpse lies on z -1)
	_ground.material = add
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	var motes := CPUParticles2D.new()
	motes.material = add
	motes.texture = GameData.texture("fx.pixel")
	motes.amount = 16
	motes.lifetime = 1.4
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(12, 3)
	motes.direction = Vector2(0, -1)
	motes.spread = 15.0
	motes.gravity = Vector2(0, -18)
	motes.initial_velocity_min = 8.0
	motes.initial_velocity_max = 22.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	var g := Gradient.new()
	g.set_color(0, HOT)
	g.set_color(1, Color(SICK, 0.0))
	motes.color_ramp = g
	add_child(motes)
	# A faint violet light so the remains read in the dark. Not a registered gameplay light: it
	# must not reveal the pile or anything else to the darkness rules.
	var l := PointLight2D.new()
	LightLayers.setup_light(l)
	l.texture = GameData.texture("fx.light")
	l.color = VIOLET
	l.energy = 0.9
	l.texture_scale = 70.0 / LightLayers.PX_PER_SCALE
	l.position = Vector2(0, -10)
	add_child(l)


func _process(_delta: float) -> void:
	if not is_instance_valid(remains) or not remains.is_inside_tree():
		queue_free()
		return
	global_position = remains.global_position
	visible = remains.is_visible_in_tree()
	_ground.queue_redraw()
	queue_redraw()


func _pulse() -> float:
	var urgent := 1.0 - left() / total
	return 0.6 + 0.4 * sin((Time.get_ticks_msec() / 1000.0 - _born) * (4.0 + 8.0 * urgent))


## The unholy glow on the floor: a soft violet pool and a rune ring turning the other way.
func _draw_ground() -> void:
	var p := _pulse()
	_ground.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
	_ground.draw_circle(Vector2.ZERO, 32.0, Color(VIOLET, 0.45 * p))
	_ground.draw_circle(Vector2.ZERO, 18.0, Color(HOT, 0.5 * p))
	var spin := (Time.get_ticks_msec() / 1000.0) * -1.5
	for i in 6:
		var a := spin + TAU * i / 6.0
		_ground.draw_arc(Vector2.ZERO, 34.0, a, a + 0.6, 6, Color(SICK, 0.85 * p), 2.5)
	_ground.draw_set_transform(Vector2.ZERO)
	# A flickering soul flame rising from the remains.
	var t := Time.get_ticks_msec() / 1000.0
	for layer in [[15.0, 50.0, 0.5], [7.0, 38.0, 0.85]]:
		var w: float = layer[0] * (1.0 + 0.12 * sin(t * 13.0))
		var h: float = layer[1] * (0.85 + 0.15 * sin(t * 7.0 + 1.0))
		var top := Vector2(sin(t * 5.0) * 3.0, -h)
		var cols := PackedColorArray([Color(HOT, layer[2] * p), Color(HOT, layer[2] * p), Color(VIOLET, 0.0)])
		_ground.draw_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(w, 0), top]), cols)


## The wisp, the countdown ring and the line of text.
func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0 - _born
	var p := _pulse()
	var wisp := Vector2(sin(t * 2.3) * 4.0, -20.0 + sin(t * 3.1) * 3.0)
	draw_circle(wisp, 6.0, Color(VIOLET, 0.4 * p))
	draw_circle(wisp, 3.0, Color(1.0, 0.9, 1.0, 0.95))
	var c := Vector2(0, -52)
	var frac := left() / total
	draw_circle(c, 13.0, Color(0.05, 0.02, 0.08, 0.9))
	draw_arc(c, 13.0, 0.0, TAU, 32, Color(VIOLET, 0.35), 3.0)
	draw_arc(c, 13.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Color(HOT, 1.0), 3.0)
	var secs := str(ceili(left()))
	var fs := 14
	var w := _font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, c + Vector2(-w / 2.0, 4.0), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
	draw_string(_font, c + Vector2(-w / 2.0, 4.0), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.92, 1.0))
	var text := Loc.t("Rises again")
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var tp := c + Vector2(-tw / 2.0, -19.0)
	draw_string_outline(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
	draw_string(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(VIOLET.lightened(0.3), 0.75 + 0.25 * p))
