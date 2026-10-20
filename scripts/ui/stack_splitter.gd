class_name StackSplitter
extends Control
## #61: how many of a stack? A small picker over the inventory: a slider for the amount
## (left / right on the d-pad or keys, the mouse wheel, or the - / + buttons), then drop that many,
## split them off into their own backpack slot, or cancel (B / Esc). It starts at the whole
## stack, so dropping everything stays one more press.

signal chosen(action: String, amount: int)  ## "drop" / "split"; nothing is emitted on cancel

var item: Dictionary
var slider: HSlider
var drop_btn: AnimButton
var split_btn: AnimButton
var _amount_label: Label


func _init(stack: Dictionary) -> void:
	item = stack
	name = "StackSplitter"


func count() -> int:
	return int(item.get("count", 1))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var win := GlassWindow.new(false)
	center.add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	v.add_child(UITheme.title(Loc.t("Split stack"), UITheme.FONT_BODY))
	v.add_child(UITheme.label(Loc.item_name(item), Color.from_string(GameData.rarity(int(item.get("rarity", 1))).color, Color.WHITE)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var minus := _small_button("-", -1)
	row.add_child(minus)
	slider = HSlider.new()
	slider.min_value = 1
	slider.max_value = count()
	slider.step = 1
	slider.value = count()
	slider.custom_minimum_size = Vector2(200, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(_v): _refresh())
	# The theme draws no slider track: a dark groove that fills gold up to the amount.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.06, 0.09)
	track.border_color = UITheme.EDGE
	track.set_border_width_all(1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := track.duplicate()
	fill.bg_color = Color(UITheme.GOLD, 0.75)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	row.add_child(slider)
	row.add_child(_small_button("+", 1))
	_amount_label = UITheme.label("", UITheme.TEXT, UITheme.FONT_BODY)
	_amount_label.custom_minimum_size = Vector2(70, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_amount_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	drop_btn = _button(func(): _choose("drop"))
	buttons.add_child(drop_btn)
	split_btn = _button(func(): _choose("split"))
	buttons.add_child(split_btn)
	var cancel := _button(close)
	cancel.text = Loc.t("Cancel")
	buttons.add_child(cancel)
	v.add_child(PromptBar.new([["ui_left", Loc.t("Less")], ["ui_right", Loc.t("More")], ["ui_accept", Loc.t("Drop")], ["ui_cancel", Loc.t("Cancel")]]))
	slider.focus_neighbor_bottom = drop_btn.get_path()
	for b in [drop_btn, split_btn, cancel]:
		b.focus_neighbor_top = slider.get_path()
	_refresh()
	slider.grab_focus.call_deferred()


func _small_button(text: String, step: int) -> AnimButton:
	var b := AnimButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 26)
	b.pressed.connect(func(): set_amount(amount() + step))
	return b


func _button(cb: Callable) -> AnimButton:
	var b := AnimButton.new()
	b.custom_minimum_size = Vector2(130, 30)
	b.pressed.connect(cb)
	return b


func amount() -> int:
	return int(slider.value)


func set_amount(n: int) -> void:
	slider.value = clampi(n, 1, count())


func _refresh() -> void:
	_amount_label.text = Loc.f("%d of %d", [amount(), count()])
	drop_btn.text = Loc.f("Drop %d", [amount()])
	split_btn.text = Loc.f("Split off %d", [amount()])
	# Splitting the whole stack off would only move it.
	split_btn.disabled = amount() >= count()


func _choose(action: String) -> void:
	chosen.emit(action, amount())
	close()


func close() -> void:
	queue_free()


func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if ev.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("ui_accept") and slider.has_focus():
		_choose("drop")
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		set_amount(amount() + (1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
		get_viewport().set_input_as_handled()
