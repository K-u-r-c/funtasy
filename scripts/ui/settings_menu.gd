extends Control
## Options overlay: Video / Audio / Controls tabs. Controls offers full rebinding of every game
## action for keyboard+mouse and gamepad, with conflict resolution and reset to defaults.
## Fully navigable with a gamepad (LB/RB or Q/E switch tabs, B/Esc closes).

signal closed

const CONFIRM_SECONDS := 10
const CAPTURE_TIMEOUT := 6.0

var _tabs: TabContainer
var _mode_opt: OptionButton
var _res_opt: OptionButton
var _vsync: CheckButton
var _shake: CheckButton
var _confirm_label: Label
var _confirm_box: HBoxContainer
var _apply_btn: Button
var _sizes: Array[Vector2i] = []
var _previous: Dictionary = {}
var _countdown := 0.0
var _confirming := false

var _bind_buttons: Dictionary = {}  ## "action|kind|index" -> Button
var _capturing: Button = null
var _capture_meta: Array = []
var _capture_time := 0.0
var _bind_status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var window := GlassWindow.new(true)
	center.add_child(window)
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(840, 440)
	outer.add_theme_constant_override("separation", 6)
	window.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	head.add_child(UITheme.icon("menu_options", 32))
	head.add_child(UITheme.title("Options", UITheme.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(PromptBar.new([["ui_tab_prev", "Prev tab"], ["ui_tab_next", "Next tab"], ["ui_cancel", "Back"]]))

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(840, 360)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_tabs.add_child(_build_video())
	_tabs.add_child(_build_audio())
	_tabs.add_child(_build_controls())
	_tabs.tab_changed.connect(func(_i): _focus_first())
	# Tab icons (#29): screen, speaker, keyboard + pad.
	_tabs.add_theme_constant_override("icon_max_width", 16)
	for i in _tabs.get_tab_count():
		_tabs.set_tab_icon(i, UITheme.icon_tex(["ui_video", "ui_audio", "ui_gamepad", "ui_keyboard"][mini(i, 3)]))

	var back := AnimButton.new()
	back.text = "Back"
	back.icon = UITheme.icon_tex("menu_back")
	back.add_theme_constant_override("icon_max_width", 16)
	back.pressed.connect(_close)
	outer.add_child(back)

	UIFx.pop_in(window)
	EventBus.bindings_changed.connect(_refresh_bindings)
	_focus_first.call_deferred()


func _bind_hint() -> String:
	return "Select a binding and press %s, then the new input. %s clears it." % [
		InputSettings.prompt_for("ui_accept"), InputSettings.prompt_for("ui_secondary")]


func _focus_first() -> void:
	var page := _tabs.get_current_tab_control()
	var c := _first_focusable(page)
	if c:
		c.grab_focus()


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and c.visible and c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and c.disabled):
			return c
		var deeper := _first_focusable(c)
		if deeper:
			return deeper
	return null


# --- Video ----------------------------------------------------------------------------------


func _build_video() -> Control:
	var page := VBoxContainer.new()
	page.name = "Video"
	page.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	grid.add_child(UITheme.label("Window mode"))
	_mode_opt = OptionButton.new()
	for n in Settings.MODE_NAMES:
		_mode_opt.add_item(n)
	_mode_opt.item_selected.connect(func(_i): _res_opt.disabled = _mode_opt.selected != Settings.WindowMode.WINDOWED)
	grid.add_child(_mode_opt)
	grid.add_child(UITheme.label("Window size"))
	_res_opt = OptionButton.new()
	_sizes = Settings.available_sizes()
	for s in _sizes:
		_res_opt.add_item("%d x %d" % [s.x, s.y])
	grid.add_child(_res_opt)
	grid.add_child(UITheme.label("VSync"))
	_vsync = CheckButton.new()
	grid.add_child(_vsync)
	grid.add_child(UITheme.label("Screen shake"))
	_shake = CheckButton.new()
	_shake.toggled.connect(func(on: bool):
		Settings.screen_shake = on
		Settings.save_settings())
	grid.add_child(_shake)

	_apply_btn = AnimButton.new()
	_apply_btn.text = "Apply video settings"
	_apply_btn.pressed.connect(_on_apply)
	page.add_child(_apply_btn)
	_confirm_box = HBoxContainer.new()
	_confirm_box.visible = false
	_confirm_box.add_theme_constant_override("separation", 8)
	page.add_child(_confirm_box)
	_confirm_label = UITheme.label("", UITheme.ACCENT)
	_confirm_box.add_child(_confirm_label)
	var keep := AnimButton.new()
	keep.text = "Keep"
	keep.custom_minimum_size = Vector2(110, 32)
	keep.pressed.connect(_keep)
	_confirm_box.add_child(keep)
	var revert := AnimButton.new()
	revert.text = "Revert"
	revert.custom_minimum_size = Vector2(110, 32)
	revert.pressed.connect(_revert)
	_confirm_box.add_child(revert)
	_load_video()
	return page


func _load_video() -> void:
	_mode_opt.select(Settings.window_mode)
	_res_opt.select(maxi(_sizes.find(Settings.window_size), 0))
	_res_opt.disabled = Settings.window_mode != Settings.WindowMode.WINDOWED
	_vsync.button_pressed = Settings.vsync
	_shake.set_pressed_no_signal(Settings.screen_shake)


func _on_apply() -> void:
	_previous = Settings.snapshot()
	Settings.window_mode = _mode_opt.selected
	Settings.window_size = _sizes[_res_opt.selected]
	Settings.vsync = _vsync.button_pressed
	if Settings.snapshot() == _previous:
		return
	Settings.apply()
	_confirming = true
	_countdown = CONFIRM_SECONDS
	_confirm_box.visible = true
	_apply_btn.disabled = true
	_confirm_box.get_child(1).grab_focus()


func _keep() -> void:
	_end_confirm()
	Settings.save_settings()


func _revert() -> void:
	_end_confirm()
	Settings.restore(_previous)
	_load_video()


func _end_confirm() -> void:
	_confirming = false
	_confirm_box.visible = false
	_apply_btn.disabled = false
	_apply_btn.grab_focus()


# --- Audio ----------------------------------------------------------------------------------


func _build_audio() -> Control:
	var page := GridContainer.new()
	page.name = "Audio"
	page.columns = 2
	page.add_theme_constant_override("h_separation", 24)
	page.add_theme_constant_override("v_separation", 14)
	for bus in Settings.BUSES:
		page.add_child(UITheme.label(bus + " volume"))
		var s := HSlider.new()
		s.custom_minimum_size = Vector2(320, 24)
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Settings.volumes[bus])
		s.focus_mode = Control.FOCUS_ALL
		s.value_changed.connect(func(v: float):
			Settings.volumes[bus] = v
			Settings.apply_audio()
			Settings.save_settings()
			AudioManager.play_sfx("ui_move", 0.0))
		page.add_child(s)
	return page


# --- Controls -------------------------------------------------------------------------------


func _build_controls() -> Control:
	var page := VBoxContainer.new()
	page.name = "Controls"
	page.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	page.add_child(top)
	var reset := AnimButton.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(200, 30)
	reset.pressed.connect(func():
		InputSettings.reset_to_defaults()
		_bind_status.text = "All bindings reset to defaults.")
	top.add_child(reset)
	_bind_status = UITheme.label(_bind_hint(), UITheme.TEXT_DIM, 13)
	# The hint names the buttons of the device in use; refresh it when the player switches.
	EventBus.input_device_changed.connect(func(_g):
		if _capturing == null and is_instance_valid(_bind_status):
			_bind_status.text = _bind_hint())
	_bind_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bind_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_bind_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1 + InputSettings.kbm_slots + InputSettings.pad_slots
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	grid.add_child(UITheme.label("Action", UITheme.ACCENT))
	for i in InputSettings.kbm_slots:
		grid.add_child(UITheme.label("Keyboard/Mouse %d" % (i + 1), UITheme.ACCENT, 13))
	for i in InputSettings.pad_slots:
		grid.add_child(UITheme.label("Gamepad %d" % (i + 1), UITheme.ACCENT, 13))
	var group := ""
	for a in InputSettings.action_defs():
		if a.group != group:
			group = a.group
			grid.add_child(UITheme.label("— %s —" % group, UITheme.TEXT_DIM, 13))
			for i in grid.columns - 1:
				grid.add_child(Control.new())
		var l := UITheme.label(a.label)
		l.custom_minimum_size = Vector2(250, 0)
		grid.add_child(l)
		for kind in ["kbm", "pad"]:
			var slots: int = InputSettings.kbm_slots if kind == "kbm" else InputSettings.pad_slots
			for i in slots:
				var b := Button.new()
				b.custom_minimum_size = Vector2(130, 28)
				b.focus_mode = Control.FOCUS_ALL
				b.clip_text = true
				b.pressed.connect(_start_capture.bind(b, a.id, kind, i))
				b.gui_input.connect(_on_bind_gui_input.bind(a.id, kind, i))
				grid.add_child(b)
				_bind_buttons["%s|%s|%d" % [a.id, kind, i]] = b
	_refresh_bindings()
	return page


func _refresh_bindings() -> void:
	for key in _bind_buttons:
		var parts: PackedStringArray = key.split("|")
		var list: Array = InputSettings.bindings[parts[0]][parts[1]]
		var idx := int(parts[2])
		var b: Button = _bind_buttons[key]
		if b == _capturing:
			continue
		b.text = InputSettings.code_display(list[idx]) if idx < list.size() else "-"


func _on_bind_gui_input(ev: InputEvent, action: String, kind: String, index: int) -> void:
	if _capturing != null:
		return
	if ev.is_action_pressed("ui_secondary"):
		InputSettings.clear_binding(action, kind, index)
		_bind_status.text = "Cleared %s binding of '%s'." % ["keyboard/mouse" if kind == "kbm" else "gamepad", InputSettings.action_label(action)]
		get_viewport().set_input_as_handled()


func _start_capture(b: Button, action: String, kind: String, index: int) -> void:
	if _capturing != null:
		return
	_capturing = b
	_capture_meta = [action, kind, index]
	_capture_time = 0.0
	b.text = "Press %s..." % ("key / mouse" if kind == "kbm" else "pad input")
	_bind_status.text = "Waiting for input for '%s' (Esc cancels)." % InputSettings.action_label(action)


func _input(ev: InputEvent) -> void:
	if _capturing == null:
		return
	# Ignore the press that started the capture.
	if _capture_time < 0.15:
		if ev is InputEventKey or ev is InputEventMouseButton or ev is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		_end_capture("Cancelled.")
		get_viewport().set_input_as_handled()
		return
	var code := InputSettings.code_from_event(ev)
	if code.is_empty():
		return
	get_viewport().set_input_as_handled()
	var kind: String = _capture_meta[1]
	var is_pad := code.begins_with("button:") or code.begins_with("axis:")
	if (kind == "pad") != is_pad:
		_bind_status.text = "That slot only accepts %s input." % ("gamepad" if kind == "pad" else "keyboard/mouse")
		return
	var removed := InputSettings.bind(_capture_meta[0], kind, _capture_meta[2], code)
	var msg := "'%s' bound to %s." % [InputSettings.action_label(_capture_meta[0]), InputSettings.code_display(code)]
	if not removed.is_empty():
		msg += " Conflict resolved: removed from %s." % ", ".join(removed)
	_end_capture(msg)


func _end_capture(msg: String) -> void:
	var b := _capturing
	_capturing = null
	_bind_status.text = msg
	_refresh_bindings()
	if b:
		b.grab_focus.call_deferred()


# --- Shared ---------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if _capturing != null:
		_capture_time += delta
		if _capture_time > CAPTURE_TIMEOUT:
			_end_capture("Timed out.")
	if _confirming:
		_countdown -= delta
		_confirm_label.text = "Keep these settings? Reverting in %d s" % ceili(maxf(_countdown, 0.0))
		if _countdown <= 0.0:
			_revert()


func _unhandled_input(ev: InputEvent) -> void:
	if _capturing != null:
		return
	if ev.is_action_pressed("ui_tab_prev") or ev.is_action_pressed("ui_tab_next"):
		var dir := -1 if ev.is_action_pressed("ui_tab_prev") else 1
		_tabs.current_tab = wrapi(_tabs.current_tab + dir, 0, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _confirming:
			_revert()
		else:
			_close()


func _close() -> void:
	if _confirming:
		_revert()
	set_process_unhandled_input(false)
	closed.emit()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	await t.finished
	queue_free()
