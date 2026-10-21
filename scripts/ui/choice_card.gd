class_name ChoiceCard
extends Button
## The large choice card of the floor systems (#71 modifiers, #72 shrine bargains, #73 boons): a
## tall dark glass card with a rim in its colour, a big icon in a glowing well, the name, its
## lines (danger in warning amber, reward in gold, plain text in white), optional tag chips and a
## row of "who picked this" name chips. It lifts and glows on hover / focus (mouse, keyboard and
## gamepad alike), shows a check when it is your pick, and plays a pick flash. Press = choose.

const SIZE := Vector2(212, 286)

var icon_key := ""
var title := ""
var lines: Array = []  ## [[text, colour], ...]
var tags: Array = []  ## [text, ...]
var rim := UITheme.GOLD
var picked := false  ## this peer's own pick
var voters: Array = []  ## [[name, colour], ...]
var _lift := 0.0
var _t := 0.0
var _flash := 0.0
var _box: VBoxContainer
var _voter_row: HBoxContainer


func _init(icon: String = "", name_: String = "", card_lines: Array = [], colour: Color = UITheme.GOLD, card_tags: Array = []) -> void:
	icon_key = icon
	title = name_
	lines = card_lines
	rim = colour
	tags = card_tags
	custom_minimum_size = SIZE
	flat = true
	focus_mode = Control.FOCUS_ALL
	text = ""
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = 14
	_box.offset_right = -14
	_box.offset_top = 92
	_box.offset_bottom = -12
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	var t := UITheme.label(title, rim.lightened(0.3), UITheme.FONT_BODY)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(t)
	var orn := TextureRect.new()
	orn.texture = UITheme.icon_tex("orn_divider")
	orn.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(orn)
	for ln in lines:
		if ln.size() > 2:
			# A small heading over the line ("Danger", "Reward"...): [text, colour].
			var hd := UITheme.label(str(ln[2][0]).to_upper(), ln[2][1], UITheme.FONT_SMALL)
			hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_box.add_child(hd)
		var l := UITheme.label(str(ln[0]), ln[1] if ln.size() > 1 else UITheme.TEXT, UITheme.FONT_SMALL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(SIZE.x - 28, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(l)
	if not tags.is_empty():
		var tr := HFlowContainer.new()
		tr.alignment = FlowContainer.ALIGNMENT_CENTER
		tr.add_theme_constant_override("h_separation", 4)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for tg in tags:
			var chip := UITheme.label(str(tg), UITheme.TEXT_DIM, UITheme.FONT_SMALL)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.add_child(chip)
		_box.add_child(tr)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(spacer)
	_voter_row = HBoxContainer.new()
	_voter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_voter_row.add_theme_constant_override("separation", 4)
	_voter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_voter_row)
	set_voters(voters)
	focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))
	mouse_entered.connect(func(): if not has_focus(): grab_focus())


func set_voters(v: Array) -> void:
	voters = v
	if _voter_row == null:
		return
	for c in _voter_row.get_children():
		c.queue_free()
	for vt in voters:
		var l := UITheme.label(str(vt[0]), vt[1], UITheme.FONT_SMALL)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_voter_row.add_child(l)


## The pick flash (this card was chosen).
func flash() -> void:
	_flash = 1.0
	pivot_offset = SIZE / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.06, 1.06), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	var want := 1.0 if (has_focus() or is_hovered()) and not disabled else 0.0
	_lift = move_toward(_lift, want, delta * 6.0)
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_box.position.y = 92 - 6.0 * _lift
	queue_redraw()


func _draw() -> void:
	var up := -6.0 * _lift
	var r := Rect2(Vector2(0, up), SIZE)
	var glow := 0.18 + 0.12 * sin(_t * 2.2) + 0.35 * _lift + 0.6 * _flash + (0.25 if picked else 0.0)
	draw_rect(r.grow(3), Color(rim, glow * 0.35))
	draw_style_box(UITheme.cached_glass(Color("080b12f2"), rim.darkened(0.3 - 0.3 * _lift), 2 if picked else 1, 0), r)
	# The icon well: a dark disc with a soft glow in the card's colour and the icon over it.
	var c := Vector2(SIZE.x / 2.0, 50.0 + up)
	draw_circle(c, 40.0, Color(rim, 0.08 + 0.08 * _lift))
	draw_circle(c, 34.0, Color(0.02, 0.02, 0.04, 0.9))
	draw_arc(c, 34.0, 0.0, TAU, 40, Color(rim, 0.6 + 0.3 * _lift), 1.5)
	var tex := UITheme.icon_tex(icon_key)
	if tex:
		draw_texture_rect(tex, Rect2(c - Vector2(28, 28), Vector2(56, 56)), false)
	if picked:
		var k := r.position + Vector2(SIZE.x - 22, 8)
		draw_circle(k + Vector2(7, 7), 9.0, Color(UITheme.GOOD, 0.9))
		draw_polyline(PackedVector2Array([k + Vector2(3, 7), k + Vector2(6, 10), k + Vector2(11, 4)]), Color.BLACK, 2.0)
	if _flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.25 * _flash))
