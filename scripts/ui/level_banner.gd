class_name LevelBanner
extends Control
## #48: the local player's level-up banner across the upper middle of the screen: "LEVEL UP!" over
## a dark band with gilded edges, the new level and the talent and stat points gained, golden
## sparks and a light sweep. It swells in, holds, then rises and fades. Several levels at once
## show one banner with the final level and all the points. It never takes input or focus.

const HOLD := 3.0
const BAND := Vector2(380, 104)

var shown_level := 0  ## read by the tests
var shown_talent := 0
var shown_stat := 0
var _t := 99.0
var _box: Control
var _title: Label
var _level: Label
var _points: HBoxContainer
var _sparks: CPUParticles2D
var _tween: Tween


func _init() -> void:
	name = "LevelBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.3
	anchor_bottom = 0.3
	offset_left = -BAND.x / 2.0
	offset_right = BAND.x / 2.0
	offset_top = -BAND.y / 2.0
	offset_bottom = BAND.y / 2.0
	visible = false
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_title = UITheme.label("", UITheme.GOLD, UITheme.FONT_TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0))
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_title)
	var orn := TextureRect.new()
	orn.texture = UITheme.icon_tex("orn_divider")
	orn.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(orn)
	_level = UITheme.label("", UITheme.TEXT, UITheme.FONT_BODY)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.add_theme_color_override("font_outline_color", Color.BLACK)
	_level.add_theme_constant_override("outline_size", 4)
	_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_level)
	_points = HBoxContainer.new()
	_points.alignment = BoxContainer.ALIGNMENT_CENTER
	_points.add_theme_constant_override("separation", 12)
	_points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_points)
	_sparks = CPUParticles2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = add
	_sparks.texture = GameData.texture("fx.pixel")
	_sparks.amount = 40
	_sparks.lifetime = 1.6
	_sparks.position = BAND / 2.0
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.emission_rect_extents = Vector2(BAND.x * 0.4, 20)
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 30.0
	_sparks.gravity = Vector2(0, -30)
	_sparks.initial_velocity_min = 20.0
	_sparks.initial_velocity_max = 60.0
	_sparks.scale_amount_min = 1.0
	_sparks.scale_amount_max = 2.0
	var g := Gradient.new()
	g.set_color(0, Color(2.0, 1.6, 0.6))
	g.set_color(1, Color(1.0, 0.7, 0.2, 0.0))
	_sparks.color_ramp = g
	_sparks.emitting = false
	add_child(_sparks)


## Shows the banner for reaching `lvl` with `talent` and `stat` points gained (restarts it if it is
## already up).
func show_level(lvl: int, talent: int, stat: int) -> void:
	shown_level = lvl
	shown_talent = talent
	shown_stat = stat
	_title.text = Loc.t("Level up!").to_upper()
	_level.text = Loc.f("Level %d", [lvl])
	for c in _points.get_children():
		c.queue_free()
	if talent > 0:
		_points.add_child(_chip("nav_talents", Loc.f("Talent points +%d", [talent])))
	if stat > 0:
		_points.add_child(_chip("act_plus", Loc.f("Stat points +%d", [stat])))
	_t = 0.0
	visible = true
	modulate = Color(1, 1, 1, 0)
	offset_top = -BAND.y / 2.0
	offset_bottom = BAND.y / 2.0
	_title.pivot_offset = Vector2(BAND.x / 2.0, 20)
	_title.scale = Vector2(1.7, 1.7)
	_sparks.restart()
	_sparks.emitting = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.parallel().tween_property(_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD)
	_tween.tween_callback(func(): _sparks.emitting = false)
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_tween.parallel().tween_property(self, "offset_top", -BAND.y / 2.0 - 14.0, 0.6)
	_tween.parallel().tween_property(self, "offset_bottom", BAND.y / 2.0 - 14.0, 0.6)
	_tween.tween_callback(_finish)


func _finish() -> void:
	visible = false
	offset_top = -BAND.y / 2.0
	offset_bottom = BAND.y / 2.0


func _chip(icon_key: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UITheme.icon(icon_key, 16))
	var l := UITheme.label(text, UITheme.GOOD, UITheme.FONT_SMALL)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	h.add_child(l)
	for c in h.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


## The band: dark in the middle fading out to both sides, gilded lines above and below that grow
## from the centre, a warm glow behind the title and a light sweep crossing once.
func _draw() -> void:
	var open := clampf(_t / 0.35, 0.0, 1.0)
	var c := BAND / 2.0
	var hw := BAND.x / 2.0 * open
	var bands := [[0.0, 0.9], [0.6, 0.7], [1.0, 0.0]]
	for i in bands.size() - 1:
		var x0: float = hw * float(bands[i][0])
		var x1: float = hw * float(bands[i + 1][0])
		var a0: float = bands[i][1]
		var a1: float = bands[i + 1][1]
		for s in [-1.0, 1.0]:
			var pts := PackedVector2Array([Vector2(c.x + s * x0, 6), Vector2(c.x + s * x1, 6), Vector2(c.x + s * x1, BAND.y - 6), Vector2(c.x + s * x0, BAND.y - 6)])
			var bg := Color(0.02, 0.02, 0.05)
			draw_polygon(pts, PackedColorArray([Color(bg, a0), Color(bg, a1), Color(bg, a1), Color(bg, a0)]))
	for y in [6.0, BAND.y - 6.0]:
		for s in [-1.0, 1.0]:
			draw_polygon(PackedVector2Array([Vector2(c.x, y - 1), Vector2(c.x + s * hw, y - 1), Vector2(c.x + s * hw, y + 1), Vector2(c.x, y + 1)]),
					PackedColorArray([UITheme.GOLD, Color(UITheme.GOLD, 0.0), Color(UITheme.GOLD, 0.0), UITheme.GOLD]))
	var glow := 0.25 + 0.1 * sin(_t * 4.0)
	draw_circle(Vector2(c.x, 30), 60.0 * open, Color(1.0, 0.7, 0.25, glow * 0.35))
	var u := clampf((_t - 0.25) / 0.8, 0.0, 1.0)
	if u > 0.0 and u < 1.0:
		var x := lerpf(c.x - hw, c.x + hw, u)
		draw_polygon(PackedVector2Array([Vector2(x - 6, 6), Vector2(x + 18, 6), Vector2(x + 6, BAND.y - 6), Vector2(x - 18, BAND.y - 6)]),
				PackedColorArray([Color(1, 0.95, 0.7, 0.0), Color(1, 0.95, 0.7, 0.35), Color(1, 0.95, 0.7, 0.35), Color(1, 0.95, 0.7, 0.0)]))
