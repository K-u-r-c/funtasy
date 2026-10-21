class_name FloorBanner
extends Control
## #70: the arrival on a floor across the upper middle of the screen, in the language of the level
## banner (#48): a dark band with gilded edges that opens from the centre, the biome's crest with a
## glow in the biome's torch colour, its name, "Floor N", and one line per thing that makes this
## floor different (an invasion, a floor modifier #71...), each led by its badge. Embers rise in the
## biome's colour; it holds, then rises and fades. It never takes input or focus.

const HOLD := 3.4
const BAND := Vector2(460, 132)

var shown_title := ""  ## read by the tests
var shown_lines: Array = []
var _t := 99.0
var _box: VBoxContainer
var _crest: TextureRect
var _title: Label
var _floor: Label
var _rows: VBoxContainer
var _embers: CPUParticles2D
var _tint := Color("ff9944")
var _tween: Tween


func _init() -> void:
	name = "FloorBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.24
	anchor_bottom = 0.24
	offset_left = -BAND.x / 2.0
	offset_right = BAND.x / 2.0
	offset_top = -BAND.y / 2.0
	offset_bottom = BAND.y / 2.0
	visible = false
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 1)
	add_child(_box)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(top)
	_crest = TextureRect.new()
	_crest.custom_minimum_size = Vector2(48, 48)
	_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_crest)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	_title = UITheme.label("", UITheme.GOLD, UITheme.FONT_TITLE)
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0))
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_title)
	_floor = UITheme.label("", UITheme.TEXT, UITheme.FONT_BODY)
	_floor.add_theme_color_override("font_outline_color", Color.BLACK)
	_floor.add_theme_constant_override("outline_size", 4)
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_floor)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_rows)
	_embers = CPUParticles2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add
	_embers.texture = GameData.texture("fx.pixel")
	_embers.amount = 36
	_embers.lifetime = 1.8
	_embers.position = Vector2(BAND.x / 2.0, BAND.y - 14)
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(BAND.x * 0.42, 6)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 20.0
	_embers.gravity = Vector2(0, -20)
	_embers.initial_velocity_min = 12.0
	_embers.initial_velocity_max = 34.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 2.0
	_embers.emitting = false
	add_child(_embers)


func _ready() -> void:
	# A new language mid-banner: its words would be the old language's, so it just goes.
	EventBus.locale_changed.connect(func(): visible = false)


## Shows the banner for floor `depth` built from `fd`; `extra` adds lines [icon, text, colour] (a
## mixed floor's invasion is added here from `fd`).
func show_floor(fd: Dictionary, depth: int, extra: Array = []) -> void:
	var biome := str(fd.get("id", ""))
	_crest.texture = UITheme.icon_tex("biome_" + biome)
	_tint = Color.from_string(str(fd.get("torch_color", "#ff9944")), Color(1.0, 0.6, 0.27))
	shown_title = Loc.t(str(fd.get("name", "")))
	_title.text = shown_title
	_floor.text = Loc.f("Floor %d", [depth])
	for c in _rows.get_children():
		c.queue_free()
	shown_lines.clear()
	var all: Array = []
	var mix := str(fd.get("mix", ""))
	if not mix.is_empty():
		var ov := Loc.t(str(GameData.floor_types[mix].get("overrun", "")))
		all.append(["mod_overrun", ov.substr(0, 1).to_upper() + ov.substr(1), UITheme.BADGE_INVASION])
	all.append_array(extra)
	for ln in all:
		shown_lines.append(str(ln[1]))
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := Badge.new(str(ln[0]), str(ln[1]), [], ln[2], 20)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(b)
		var l := UITheme.label(str(ln[1]), Color(ln[2]).lightened(0.3), UITheme.FONT_SMALL)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		_rows.add_child(h)
	var g := Gradient.new()
	g.set_color(0, Color(_tint.r * 2.0, _tint.g * 2.0, _tint.b * 2.0))
	g.set_color(1, Color(_tint, 0.0))
	_embers.color_ramp = g
	_t = 0.0
	visible = true
	modulate = Color(1, 1, 1, 0)
	offset_top = -BAND.y / 2.0
	offset_bottom = BAND.y / 2.0
	_crest.pivot_offset = Vector2(24, 24)
	_crest.scale = Vector2(0.3, 0.3)
	_embers.restart()
	_embers.emitting = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.parallel().tween_property(_crest, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD + 0.8 * all.size())
	_tween.tween_callback(func(): _embers.emitting = false)
	_tween.tween_property(self, "modulate:a", 0.0, 0.8)
	_tween.parallel().tween_property(self, "offset_top", -BAND.y / 2.0 - 16.0, 0.8)
	_tween.parallel().tween_property(self, "offset_bottom", BAND.y / 2.0 - 16.0, 0.8)
	_tween.tween_callback(func(): visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var open := clampf(_t / 0.4, 0.0, 1.0)
	var c := BAND / 2.0
	var hw := BAND.x / 2.0 * open
	var bg := Color(0.02, 0.02, 0.05)
	for s in [-1.0, 1.0]:
		draw_polygon(PackedVector2Array([Vector2(c.x, 4), Vector2(c.x + s * hw * 0.6, 4), Vector2(c.x + s * hw * 0.6, BAND.y - 4), Vector2(c.x, BAND.y - 4)]),
				PackedColorArray([Color(bg, 0.9), Color(bg, 0.75), Color(bg, 0.75), Color(bg, 0.9)]))
		draw_polygon(PackedVector2Array([Vector2(c.x + s * hw * 0.6, 4), Vector2(c.x + s * hw, 4), Vector2(c.x + s * hw, BAND.y - 4), Vector2(c.x + s * hw * 0.6, BAND.y - 4)]),
				PackedColorArray([Color(bg, 0.75), Color(bg, 0.0), Color(bg, 0.0), Color(bg, 0.75)]))
	for y in [4.0, BAND.y - 4.0]:
		for s in [-1.0, 1.0]:
			draw_polygon(PackedVector2Array([Vector2(c.x, y - 1), Vector2(c.x + s * hw, y - 1), Vector2(c.x + s * hw, y + 1), Vector2(c.x, y + 1)]),
					PackedColorArray([UITheme.GOLD, Color(UITheme.GOLD, 0.0), Color(UITheme.GOLD, 0.0), UITheme.GOLD]))
	# The biome's glow behind the crest and title.
	var glow := 0.3 + 0.1 * sin(_t * 3.0)
	draw_circle(Vector2(c.x - 40, 40), 70.0 * open, Color(_tint, glow * 0.3))
