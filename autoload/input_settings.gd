extends Node
## Owns the InputMap. Registers every game action from data/input_defaults.json, applies the
## player's overrides from the [input] section of user://settings.cfg and handles rebinding.
## Game logic must only ever query actions (Input.is_action_*), never raw keys.
##
## Bindings are stored as short strings so they survive in a ConfigFile and stay readable:
##   key:W  key:Shift  mouse:left  button:a  button:dpad_up  axis:left_x-  axis:rt

const SECTION := "input"

const PAD_BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "guide": JOY_BUTTON_GUIDE, "start": JOY_BUTTON_START,
	"ls": JOY_BUTTON_LEFT_STICK, "rs": JOY_BUTTON_RIGHT_STICK,
	"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const PAD_AXES := {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y,
	"right_x": JOY_AXIS_RIGHT_X, "right_y": JOY_AXIS_RIGHT_Y,
	"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT,
}
const MOUSE_BUTTONS := {
	"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
	"x1": MOUSE_BUTTON_XBUTTON1, "x2": MOUSE_BUTTON_XBUTTON2,
}
const PAD_NAMES := {
	"a": "A", "b": "B", "x": "X", "y": "Y", "back": "View", "guide": "Guide", "start": "Menu",
	"ls": "L-Stick click", "rs": "R-Stick click", "lb": "LB", "rb": "RB",
	"dpad_up": "D-Pad Up", "dpad_down": "D-Pad Down", "dpad_left": "D-Pad Left",
	"dpad_right": "D-Pad Right",
}
const AXIS_NAMES := {
	"left_x-": "L-Stick Left", "left_x+": "L-Stick Right", "left_y-": "L-Stick Up",
	"left_y+": "L-Stick Down", "right_x-": "R-Stick Left", "right_x+": "R-Stick Right",
	"right_y-": "R-Stick Up", "right_y+": "R-Stick Down", "lt": "LT", "rt": "RT",
}

## action id -> {"kbm": Array[String], "pad": Array[String]}
var bindings: Dictionary = {}
var using_gamepad := false
var last_kind := "mouse"  ## "mouse", "key" or "pad": the device of the last meaningful input
var deadzone := 0.25
var aim_deadzone := 0.3
var hold_threshold := 0.25
var kbm_slots := 2
var pad_slots := 2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var d: Dictionary = GameData.input_defaults
	deadzone = float(d.get("deadzone", deadzone))
	aim_deadzone = float(d.get("aim_deadzone", aim_deadzone))
	hold_threshold = float(d.get("hold_threshold", hold_threshold))
	kbm_slots = int(d.get("kbm_slots", kbm_slots))
	pad_slots = int(d.get("pad_slots", pad_slots))
	_load_joy_mappings()
	_register_ui_extras()
	bindings = default_bindings()
	_load_overrides()
	_apply_all()


func action_defs() -> Array:
	return GameData.input_defaults.get("actions", [])


func action_label(action: String) -> String:
	for a in action_defs():
		if a.id == action:
			return Loc.t(str(a.label))
	return action


func default_bindings() -> Dictionary:
	var out := {}
	for a in action_defs():
		out[a.id] = {"kbm": Array(a.kbm).duplicate(), "pad": Array(a.pad).duplicate()}
	return out


## Binds `code` to slot `index` of `kind` ("kbm"/"pad") of `action`. Any other game action
## using the same input loses it. Returns the labels of actions that lost a binding.
func bind(action: String, kind: String, index: int, code: String) -> PackedStringArray:
	var removed: PackedStringArray = []
	for other in bindings:
		if other == action:
			continue
		var list: Array = bindings[other][kind]
		if list.has(code):
			list.erase(code)
			removed.append(action_label(other))
	var mine: Array = bindings[action][kind]
	mine.erase(code)
	while mine.size() <= index:
		mine.append("")
	mine[index] = code
	_compact(mine)
	_apply_all()
	save()
	return removed


func clear_binding(action: String, kind: String, index: int) -> void:
	var list: Array = bindings[action][kind]
	if index < list.size():
		list.remove_at(index)
	_apply_all()
	save()


func conflicts_for(action: String, kind: String, code: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for other in bindings:
		if other != action and Array(bindings[other][kind]).has(code):
			out.append(action_label(other))
	return out


func reset_to_defaults() -> void:
	bindings = default_bindings()
	_apply_all()
	save()


func save() -> void:
	var values := {}
	for action in bindings:
		values[action] = bindings[action].duplicate(true)
	SaveSystem.write_section(SECTION, values)


# --- Event encoding ------------------------------------------------------------------------


## Converts a captured input event into a binding code, or "" if it can't be bound.
func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey and (not ev.pressed or ev.echo):
		return ""
	if (ev is InputEventMouseButton or ev is InputEventJoypadButton) and not ev.pressed:
		return ""
	if ev is InputEventJoypadMotion and absf(ev.axis_value) <= 0.6:
		return ""
	return _encode(ev)


## Encodes an event regardless of its pressed state (InputMap events are never "pressed").
func _encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return "key:" + OS.get_keycode_string(kc) if kc != 0 else ""
	if ev is InputEventMouseButton:
		for n in MOUSE_BUTTONS:
			if MOUSE_BUTTONS[n] == ev.button_index:
				return "mouse:" + n
	if ev is InputEventJoypadButton:
		for n in PAD_BUTTONS:
			if PAD_BUTTONS[n] == ev.button_index:
				return "button:" + n
	if ev is InputEventJoypadMotion:
		for n in PAD_AXES:
			if PAD_AXES[n] == ev.axis:
				if n == "lt" or n == "rt":
					return "axis:" + n
				return "axis:%s%s" % [n, "+" if ev.axis_value > 0.0 else "-"]
	return ""


func event_from_code(code: String) -> InputEvent:
	var kind := code.get_slice(":", 0)
	var value := code.get_slice(":", 1)
	match kind:
		"key":
			var kc := OS.find_keycode_from_string(value)
			if kc == KEY_NONE:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = kc
			return k
		"mouse":
			if not MOUSE_BUTTONS.has(value):
				return null
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTONS[value]
			return m
		"button":
			if not PAD_BUTTONS.has(value):
				return null
			var b := InputEventJoypadButton.new()
			b.button_index = PAD_BUTTONS[value]
			b.device = -1
			return b
		"axis":
			var axis_name := value.trim_suffix("+").trim_suffix("-")
			if not PAD_AXES.has(axis_name):
				return null
			var j := InputEventJoypadMotion.new()
			j.axis = PAD_AXES[axis_name]
			j.axis_value = -1.0 if value.ends_with("-") else 1.0
			j.device = -1
			return j
	return null


func code_display(code: String) -> String:
	return Loc.t(_code_display_en(code))


func _code_display_en(code: String) -> String:
	if code.is_empty():
		return "-"
	var kind := code.get_slice(":", 0)
	var value := code.get_slice(":", 1)
	match kind:
		"key":
			return value
		"mouse":
			return {"left": "LMB", "right": "RMB", "middle": "MMB"}.get(value, Loc.t("Mouse ") + value)
		"button":
			return PAD_NAMES.get(value, value)
		"axis":
			return AXIS_NAMES.get(value, value)
	return code


## First binding for the current device, for on-screen prompts ("[F] Open").
func prompt_for(action: String) -> String:
	var code := glyph_code(action)
	return code_display(code) if not code.is_empty() else Loc.t("Unbound")


## Binding code shown for `action` on the current device ("key:F", "button:a", ...). Works for
## game actions and for the built-in / extra UI actions (ui_cancel, ui_secondary, ...).
func glyph_code(action: String, pad: bool = using_gamepad) -> String:
	if bindings.has(action):
		var list: Array = bindings[action]["pad" if pad else "kbm"]
		return str(list[0]) if not list.is_empty() else ""
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var is_pad: bool = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if is_pad == pad:
			var code := _encode(ev)
			if not code.is_empty():
				return code
	return ""


## Short label for a glyph cap: "Esc", "LMB", "A", "LB", "RT", "Up" ...
func glyph_text(code: String) -> String:
	return Loc.t(_glyph_text_en(code))


func _glyph_text_en(code: String) -> String:
	var kind := code.get_slice(":", 0)
	var value := code.get_slice(":", 1)
	match kind:
		"key":
			return {"Escape": "Esc", "Enter": "Enter", "Space": "Space", "Shift": "Shift",
				"Ctrl": "Ctrl", "Alt": "Alt", "Tab": "Tab", "BackSpace": "Bksp", "Backspace": "Bksp",
				"Up": "Up", "Down": "Dn", "Left": "Lt", "Right": "Rt"}.get(value, value)
		"mouse":
			return {"left": "LMB", "right": "RMB", "middle": "MMB", "wheel_up": "Whl", "wheel_down": "Whl"}.get(value, "M")
		"button":
			return {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "back": "View",
				"start": "Menu", "guide": "Home", "ls": "LS", "rs": "RS", "dpad_up": "Up",
				"dpad_down": "Dn", "dpad_left": "Lt", "dpad_right": "Rt"}.get(value, value)
		"axis":
			return {"lt": "LT", "rt": "RT"}.get(value, "LS" if value.begins_with("left") else "RS")
	return code


## True while the UI should show keyboard/gamepad focus (the last input wasn't the mouse).
func focus_nav_active() -> bool:
	return using_gamepad or last_kind == "key"


# --- Gameplay helpers ----------------------------------------------------------------------


func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down", deadzone)


## Right-stick aim; zero when the stick is centered (callers then keep the previous aim).
func stick_aim() -> Vector2:
	var v := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.0)
	return v if v.length() >= aim_deadzone else Vector2.ZERO


func _input(ev: InputEvent) -> void:
	var pad: bool = ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.4)
	var kbm: bool = ev is InputEventKey or ev is InputEventMouseButton or (ev is InputEventMouseMotion and ev.relative.length() > 2.0)
	if pad:
		last_kind = "pad"
	elif ev is InputEventKey:
		last_kind = "key"
	elif kbm:
		last_kind = "mouse"
	if pad and not using_gamepad:
		using_gamepad = true
		EventBus.input_device_changed.emit(true)
	elif kbm and using_gamepad:
		using_gamepad = false
		EventBus.input_device_changed.emit(false)


# --- Internals -----------------------------------------------------------------------------


func _load_overrides() -> void:
	var saved := SaveSystem.read_section(SECTION)
	for action in saved:
		if not bindings.has(action) or not saved[action] is Dictionary:
			continue
		for kind in ["kbm", "pad"]:
			if saved[action].has(kind):
				var list: Array = []
				for code in saved[action][kind]:
					if event_from_code(str(code)) != null:
						list.append(str(code))
				bindings[action][kind] = list
	_migrate_enemy_lock(saved)


## #53: settings saved while the enemy lock (#41) existed carry its "target_enemy" action, and
## Talents had lost D-Pad Left to it. The action is gone; Talents gets its pad button back unless
## the player rebound Talents or gave D-Pad Left to something else. Saving drops the stale key.
func _migrate_enemy_lock(saved: Dictionary) -> void:
	if not saved.has("target_enemy"):
		return
	var dpad := "button:dpad_left"
	var lock: Dictionary = saved.target_enemy if saved.target_enemy is Dictionary else {}
	var taken := false
	for action in bindings:
		taken = taken or Array(bindings[action].pad).has(dpad)
	if bindings.has("talents") and Array(bindings.talents.pad).is_empty() and Array(lock.get("pad", [])).has(dpad) and not taken:
		bindings.talents.pad = [dpad]
	save()


func _apply_all() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
		InputMap.action_erase_events(action)
		for kind in ["kbm", "pad"]:
			for code in bindings[action][kind]:
				var ev := event_from_code(code)
				if ev:
					InputMap.action_add_event(action, ev)
	EventBus.bindings_changed.emit()


## Extra SDL controller mappings from data/joy_mappings.txt (fixes pads whose layout differs from
## the engine's built-in database).
func _load_joy_mappings() -> void:
	var path := "res://data/joy_mappings.txt"
	if not FileAccess.file_exists(path):
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		Input.add_joy_mapping(line, true)


func _register_ui_extras() -> void:
	var extras: Dictionary = GameData.input_defaults.get("ui_extra", {})
	for action in extras:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		for code in extras[action]:
			var ev := event_from_code(code)
			if ev and not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)


func _compact(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		if str(list[i]).is_empty():
			list.remove_at(i)
