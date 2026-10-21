class_name ForgeStage
extends Control
## #77: the forge window's anvil. The chosen piece rests on Rolf's anvil in the hearth's glow;
## `play(item)` forges it: the piece heats up, three hammer strikes (sparks, a ring of light, a
## jolt and the clang), a quench (it dips, steam, the hiss) and it comes back glowing brighter in
## its rarity colour. Emits `finished` at the end. Local only: the host already made the upgrade.
## #89: about 1.7 s (it was 3), and `finish_now` cuts it short (the next upgrade needn't wait for it).

signal finished

var phase := ""  ## "", "heat", "strike", "quench", "glow" (tests and screenshots)
var strikes := 0  ## hammer strikes shown by the last play (tests)
var last_duration := 0.0  ## seconds the last forging played (tests)
var _played := 0.0
var item: Dictionary = {}
var _anvil: Texture2D
var _hearth: Texture2D
var _glow: GradientTexture2D
var _soft: GradientTexture2D  ## white, for tinted glows
var _hammer: Texture2D
var _icon: Texture2D
var _t := 0.0
var _heat := 0.0  ## 0..1: how red-hot the piece glows
var _shine := 0.0  ## 0..1: the finished piece's rarity glow
var _ring := 0.0  ## 0..1: the expanding ring of a strike
var _hammer_angle := -70.0
var _dip := 0.0
var _jolt := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(220, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	_anvil = GameData.texture("props.forge_anvil")
	_hearth = GameData.texture("props.forge_hearth")
	_hammer = GameData.texture("items.warhammer")
	_glow = GradientTexture2D.new()
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.5, 0.15, 0.55))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	_glow.gradient = g
	_soft = _glow.duplicate()
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 0.6))
	g2.set_color(1, Color(1, 1, 1, 0.0))
	_soft.gradient = g2


func show_item(it: Dictionary) -> void:
	item = it
	_icon = ItemLooks.icon(it) if not it.is_empty() and GameData.asset_exists(str(it.get("icon", ""))) else null
	queue_redraw()


func busy() -> bool:
	return not phase.is_empty()


func _process(delta: float) -> void:
	_t += delta
	if busy():
		_played += delta
	queue_redraw()


func _anvil_top() -> Vector2:
	return Vector2(size.x / 2.0, size.y - 22.0 - 26.0 * 4.0 + 30.0)


func _draw() -> void:
	var c := size / 2.0
	# The hearth at the back, its glow flickering over the anvil.
	var fl := 0.85 + 0.15 * sin(_t * 7.0) * sin(_t * 3.1)
	if _hearth:
		var hs := Vector2(_hearth.get_width(), _hearth.get_height()) * 3.0
		draw_texture_rect(_hearth, Rect2(Vector2(c.x - hs.x / 2.0, 14.0), hs), false, Color(0.55, 0.5, 0.5))
		# Its fire mouth breathes.
		var mouth := Vector2(c.x - hs.x * 0.16, 14.0 + hs.y * 0.62)
		draw_texture_rect(_glow, Rect2(mouth - Vector2(60, 60), Vector2(120, 120)), false, Color(1, 1, 1, 0.55 * fl))
	var gr := 150.0 + 12.0 * fl + _heat * 30.0
	draw_texture_rect(_glow, Rect2(Vector2(c.x, size.y - 70.0) - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1, 1, 1, fl))
	draw_rect(Rect2(0, size.y - 26.0, size.x, 26.0), Color(0.05, 0.04, 0.05, 0.85))
	var top := _anvil_top() + _jolt
	if _anvil:
		var s := 4.0
		var asz := Vector2(_anvil.get_width(), _anvil.get_height()) * s
		draw_texture_rect(_anvil, Rect2(Vector2(c.x - asz.x / 2.0, size.y - 22.0 - asz.y) + _jolt, asz), false)
	if _ring > 0.0:
		var rr := 18.0 + (1.0 - _ring) * 70.0
		draw_arc(top + Vector2(0, -12), rr, 0, TAU, 40, Color(1.0, 0.8, 0.45, _ring * 0.8), 2.0)
	if _icon:
		var pos := top + Vector2(-24, -44 + _dip)
		var rar := UITheme.rarity_color(int(item.get("rarity", 1)))
		if _shine > 0.0:
			var sr := 46.0 + 10.0 * _shine
			var white := Color(rar.r * 1.4, rar.g * 1.4, rar.b * 1.4, _shine)
			draw_texture_rect(_soft, Rect2(pos + Vector2(24, 24) - Vector2(sr, sr), Vector2(sr, sr) * 2.0), false, white)
		var tint := Color.WHITE.lerp(Color(2.2, 0.9, 0.5), _heat)
		tint = tint.lerp(Color(1.6, 1.6, 1.6), _shine * 0.4)
		draw_texture_rect(_icon, Rect2(pos, Vector2(48, 48)), false, tint)
	if _hammer and phase == "strike":
		# The hammer swings around a pivot above-right of the anvil.
		var pivot := top + Vector2(54, -86)
		draw_set_transform(pivot, deg_to_rad(_hammer_angle), Vector2(2, 2))
		draw_texture_rect(_hammer, Rect2(Vector2(-30, -4), Vector2(32, 32)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## #89: ends a forging at once, as if it had played out (the piece back at rest, `finished` sent).
func finish_now() -> void:
	if not busy():
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_heat = 0.0
	_dip = 0.0
	_ring = 0.0
	_jolt = Vector2.ZERO
	_hammer_angle = -70.0
	_shine = 0.35
	phase = ""
	finished.emit()


## Forges `it` (the piece before the upgrade): about 1.7 s.
func play(it: Dictionary) -> void:
	show_item(it)
	if _tween and _tween.is_valid():
		_tween.kill()
	strikes = 0
	_shine = 0.0
	_played = 0.0
	phase = "heat"
	_tween = create_tween()
	_tween.tween_property(self, "_heat", 1.0, 0.18)
	_tween.tween_callback(func(): phase = "strike")
	for i in 3:
		_tween.tween_property(self, "_hammer_angle", -70.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_hammer_angle", 8.0, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_strike)
		_tween.tween_interval(0.06)
	_tween.tween_callback(func(): phase = "quench")
	_tween.tween_property(self, "_dip", 14.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_quench)
	_tween.parallel().tween_property(self, "_heat", 0.0, 0.2)
	_tween.tween_property(self, "_dip", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func():
		phase = "glow"
		AudioManager.play_sfx("forge_done", 0.0))
	_tween.tween_property(self, "_shine", 1.0, 0.08)
	_tween.tween_property(self, "_shine", 0.35, 0.3)
	_tween.tween_callback(func():
		phase = ""
		last_duration = _played
		finished.emit())


func _strike() -> void:
	strikes += 1
	AudioManager.play_sfx("forge_strike", 0.06)
	_ring = 1.0
	create_tween().tween_property(self, "_ring", 0.0, 0.35)
	_jolt = Vector2(0, 2)
	create_tween().tween_property(self, "_jolt", Vector2.ZERO, 0.12)
	_burst(_anvil_top() + Vector2(0, -28), 16, Color("ffb040"), 160.0, 420.0, 0.5, true)


func _quench() -> void:
	AudioManager.play_sfx("forge_quench", 0.0)
	_burst(_anvil_top() + Vector2(0, -30), 44, Color(0.88, 0.9, 0.94, 0.5), 40.0, -40.0, 1.3, false)


func _burst(at: Vector2, amount: int, c: Color, speed: float, gravity: float, life: float, glow: bool) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = life
	p.direction = Vector2(0, -1)
	p.spread = 70.0 if glow else 30.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.0
	if not glow:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(22, 4)
		p.explosiveness = 0.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.95, 0.75) if glow else c)
	grad.set_color(1, Color(c, 0.0))
	p.color_ramp = grad
	if glow:
		p.material = CanvasItemMaterial.new()
		p.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
