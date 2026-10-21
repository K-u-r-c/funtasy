class_name DeepAura
extends Node2D
## #74, every peer: the look of a deep variant. A corrupted monster is tinted (data tint), stands in
## a violet swirl of light (deep_aura shader) with motes of corruption rising off it and a dim light;
## an ascended boss stands in a golden swirl under a slowly turning halo.

const SHADER := preload("res://assets/shaders/deep_aura.gdshader")

var actor: Node2D
var ascended := false
var _t := 0.0
var _halo_h := 60.0


func setup(a: Node2D, is_ascended: bool) -> void:
	actor = a
	ascended = is_ascended
	name = "DeepAura"


func _ready() -> void:
	var cfg: Dictionary = GameData.corruption
	var col := Color.from_string(str(cfg.get("ascended", {}).get("aura", "#ffcf5c")) if ascended else str(cfg.get("aura", "#9a5cff")), Color.MEDIUM_PURPLE)
	var r: float = float(actor.def.get("collision_radius", 10)) * (3.2 if ascended else 2.6)
	var disc := Sprite2D.new()
	disc.texture = _white()
	disc.scale = Vector2(r / 32.0, r / 32.0 * 0.55)
	disc.z_index = -5
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("aura_color", col)
	mat.set_shader_parameter("strength", 1.3 if ascended else 1.0)
	mat.set_shader_parameter("speed", 0.6 if ascended else 1.0)
	disc.material = mat
	add_child(disc)
	var motes := CPUParticles2D.new()
	motes.texture = GameData.texture("fx.pixel")
	motes.amount = 12 if ascended else 8
	motes.lifetime = 1.4
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(r * 0.6, 4)
	motes.position = Vector2(0, -6)
	motes.direction = Vector2.UP
	motes.spread = 15.0
	motes.initial_velocity_min = 10.0
	motes.initial_velocity_max = 26.0
	motes.gravity = Vector2(0, -8)
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, col.lightened(0.3))
	grad.set_color(1, Color(col, 0.0))
	motes.color_ramp = grad
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = add
	add_child(motes)
	var l := PointLight2D.new()
	LightLayers.setup_light(l)
	l.texture = GameData.texture("fx.light")
	l.color = col
	l.energy = 0.8 if ascended else 0.55
	l.position = Vector2(0, -10)
	LightLayers.register(l, r * 1.6)
	add_child(l)
	_tint()
	if actor.get("sprite"):
		_halo_h = actor.sprite.visual_height() + 8.0


## The corrupted tint on every layer of the body (its own modulate stays free for hit flashes).
func _tint() -> void:
	if ascended or actor.get("sprite") == null:
		return
	var c := Color.from_string(str(GameData.corruption.get("tint", "#c9a4ff")), Color.WHITE)
	for l in actor.sprite.get_children():
		if l is CanvasItem:
			l.self_modulate = c


var _tint_t := 0.0


static var _white_tex: ImageTexture


## A plain white square for the shader to draw on.
static func _white() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


func _process(delta: float) -> void:
	_t += delta
	if ascended and _halo_h < 20.0 and actor.get("sprite"):
		_halo_h = actor.sprite.visual_height() + 8.0
	_tint_t -= delta
	if _tint_t <= 0.0:
		_tint_t = 0.5  # gear layers can be rebuilt (a look change): keep them tinted
		_tint()
	if ascended:
		queue_redraw()


func _draw() -> void:
	if not ascended:
		return
	# The halo: a broken golden ring over the head, turning.
	var c := Color.from_string(str(GameData.corruption.get("ascended", {}).get("aura", "#ffcf5c")), Color.GOLD)
	var at := Vector2(0, -_halo_h)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.35))
	for i in 6:
		var a0 := _t * 0.8 + TAU * i / 6.0
		draw_arc(Vector2.ZERO, 15.0, a0, a0 + 0.7, 6, Color(c, 0.9), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
