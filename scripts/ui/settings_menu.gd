extends Control
## Video settings overlay with Apply + timed confirm (auto-reverts if not confirmed).

signal closed

const CONFIRM_SECONDS := 10

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _vsync: CheckButton
var _panel: PanelContainer
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _apply_btn: AnimButton
var _scales: Array[int] = []
var _previous: Dictionary = {}
var _countdown := 0.0
var _confirming := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.18, 0.98)
	sb.border_color = Color(0.45, 0.5, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	grid.add_child(_label("Window mode"))
	_mode_opt = OptionButton.new()
	for n in Settings.MODE_NAMES:
		_mode_opt.add_item(n)
	_mode_opt.item_selected.connect(func(_i): _refresh_state())
	grid.add_child(_mode_opt)

	grid.add_child(_label("Resolution"))
	_res_opt = OptionButton.new()
	_scales = Settings.available_scales()
	for s in _scales:
		var r := Settings.resolution_for(s)
		_res_opt.add_item("%d x %d  (%dx)" % [r.x, r.y, s])
	grid.add_child(_res_opt)

	grid.add_child(_label("VSync"))
	_vsync = CheckButton.new()
	grid.add_child(_vsync)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_apply_btn = AnimButton.new()
	_apply_btn.text = "Apply"
	_apply_btn.custom_minimum_size = Vector2(100, 28)
	_apply_btn.pressed.connect(_on_apply)
	buttons.add_child(_apply_btn)
	var back := AnimButton.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(100, 28)
	back.pressed.connect(_close)
	buttons.add_child(back)

	_confirm_box = VBoxContainer.new()
	_confirm_box.visible = false
	box.add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_confirm_box.add_child(_confirm_label)
	var confirm_buttons := HBoxContainer.new()
	confirm_buttons.add_theme_constant_override("separation", 8)
	_confirm_box.add_child(confirm_buttons)
	var keep := AnimButton.new()
	keep.text = "Keep"
	keep.custom_minimum_size = Vector2(100, 28)
	keep.pressed.connect(_keep)
	confirm_buttons.add_child(keep)
	var revert := AnimButton.new()
	revert.text = "Revert"
	revert.custom_minimum_size = Vector2(100, 28)
	revert.pressed.connect(_revert)
	confirm_buttons.add_child(revert)

	_load_from_settings()
	_refresh_state()

	# Pop-in animation.
	_panel.reset_size()
	_panel.position = (Vector2(640, 360) - _panel.size) / 2.0
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.85, 0.85)
	modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.15)
	t.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_apply_btn.grab_focus()


func _process(delta: float) -> void:
	if not _confirming:
		return
	_countdown -= delta
	_confirm_label.text = "Keep these settings? Reverting in %d s" % ceili(maxf(_countdown, 0.0))
	if _countdown <= 0.0:
		_revert()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirming:
			_revert()
		else:
			_close()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _load_from_settings() -> void:
	_mode_opt.select(Settings.window_mode)
	var idx := _scales.find(Settings.scale_factor)
	_res_opt.select(maxi(idx, 0))
	_vsync.button_pressed = Settings.vsync


## Resolution only matters in windowed mode.
func _refresh_state() -> void:
	_res_opt.disabled = _mode_opt.selected != Settings.WindowMode.WINDOWED


func _on_apply() -> void:
	_previous = Settings.snapshot()
	Settings.window_mode = _mode_opt.selected
	Settings.scale_factor = _scales[_res_opt.selected]
	Settings.vsync = _vsync.button_pressed
	if Settings.snapshot() == _previous:
		return
	Settings.apply()
	_confirming = true
	_countdown = CONFIRM_SECONDS
	_confirm_box.visible = true
	_apply_btn.disabled = true


func _keep() -> void:
	_end_confirm()
	Settings.save_settings()


func _revert() -> void:
	_end_confirm()
	Settings.restore(_previous)
	_load_from_settings()
	_refresh_state()


func _end_confirm() -> void:
	_confirming = false
	_confirm_box.visible = false
	_apply_btn.disabled = false
	_apply_btn.grab_focus()


func _close() -> void:
	if _confirming:
		_revert()
	closed.emit()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	await t.finished
	queue_free()
