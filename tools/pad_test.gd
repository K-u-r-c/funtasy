extends SceneTree
## Physical gamepad check (windowed). Lists connected pads, then asks for each control used by
## the game. For every step it records the first clear raw joypad event (button index or axis +
## value) and the game actions bound to it, so mapping problems and user mix-ups can be told apart.
##   godot --path . -s tools/pad_test.gd

const STEPS := [
	["Press A (south button)", "skill_1"],
	["Press B (east button)", "skill_2"],
	["Press X (west button)", "skill_3"],
	["Press Y (north button)", "skill_4"],
	["Press RB (right bumper, the button above the trigger)", "skill_5"],
	["Press LB (left bumper, the button above the trigger)", "quick_q"],
	["Pull RT (right trigger)", "attack"],
	["Pull LT (left trigger)", "dodge"],
	["Press D-pad Down", "interact"],
	["Press D-pad Right", "quick_e"],
	["Press D-pad Left", "talents"],
	["Press D-pad Up", "map"],
	["Press View (two squares, left of the Xbox button)", "inventory"],
	["Press Menu (three lines, right of the Xbox button)", "pause"],
	["Push the LEFT stick to the left", "move_left"],
	["Push the LEFT stick up", "move_up"],
	["Push the RIGHT stick to the right", "aim_right"],
	["Push the RIGHT stick down", "aim_down"],
]

var _label: Label
var _step := -1
var _ok := 0
var _wait := 0.0
var _cooldown := 0.0
var _rest: Dictionary = {}  ## axis -> resting value (triggers may rest at -1 on some drivers)


func _initialize() -> void:
	get_root().size = Vector2i(1000, 320)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 30)
	_label.position = Vector2(30, 30)
	_label.size = Vector2(940, 260)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_root().add_child(_label)
	_label.text = "Waiting for a gamepad..."
	get_root().window_input.connect(_on_input)


func _process(delta: float) -> bool:
	if _step == -1:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return false
		for d in pads:
			print("[pad] #%d %s (known mapping: %s)" % [d, Input.get_joy_name(d), Input.is_joy_known(d)])
			for ax in 6:
				_rest[ax] = Input.get_joy_axis(d, ax)
		print("[pad] resting axes: %s" % _rest)
		_step = 0
		_show()
		return false
	if _step >= STEPS.size():
		_wait += delta
		return _wait > 3.0
	_cooldown -= delta
	_wait += delta
	if _wait > 20.0:
		print("[pad] SKIP  %s (nothing in 20 s)" % STEPS[_step][0])
		_next()
	return false


func _on_input(ev: InputEvent) -> void:
	if _step < 0 or _step >= STEPS.size() or _cooldown > 0.0:
		return
	var raw := ""
	if ev is InputEventJoypadButton and ev.pressed:
		raw = "button %d" % ev.button_index
	elif ev is InputEventJoypadMotion and absf(ev.axis_value - float(_rest.get(ev.axis, 0.0))) > 0.7:
		raw = "axis %d = %.2f" % [ev.axis, ev.axis_value]
	if raw.is_empty():
		return
	var actions: Array = []
	for a in InputMap.get_actions():
		if not str(a).begins_with("ui_") and InputMap.event_is_action(ev, a, true):
			actions.append(str(a))
	var expected: String = STEPS[_step][1]
	if actions.has(expected):
		_ok += 1
		print("[pad] OK    %s: %s -> %s" % [STEPS[_step][0], raw, actions])
	else:
		print("[pad] DIFF  %s: %s -> %s (expected %s)" % [STEPS[_step][0], raw, actions, expected])
	_next()


func _next() -> void:
	_step += 1
	_wait = 0.0
	_cooldown = 0.8  # ignore the release / bounce of the previous input
	_show()


func _show() -> void:
	if _step >= STEPS.size():
		_label.text = "Done: %d / %d controls OK. This window closes by itself." % [_ok, STEPS.size()]
		print("[pad] RESULT %d / %d" % [_ok, STEPS.size()])
	else:
		_label.text = "%d / %d\n%s\n(then let go)" % [_step + 1, STEPS.size(), STEPS[_step][0]]
