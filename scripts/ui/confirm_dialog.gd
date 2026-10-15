extends UIModal
## Small Obsidian Glass yes / no dialog (the demonic tithe, D13). `on_answer(bool)` is called
## once; Cancel counts as "no".

var body_text := ""
var yes_text := "Accept"
var no_text := "Refuse"
var on_answer: Callable
var _answered := false


func _init() -> void:
	prompts = [["ui_accept", "Choose"], ["ui_cancel", "Refuse"]]
	max_size = Vector2(520, 260)


func _build() -> void:
	var l := UITheme.label(body_text, UITheme.TEXT, UITheme.FONT_BODY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	content.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	var yes := AnimButton.new()
	yes.text = yes_text
	yes.custom_minimum_size = Vector2(160, 30)
	yes.pressed.connect(_answer.bind(true))
	row.add_child(yes)
	var no := AnimButton.new()
	no.text = no_text
	no.custom_minimum_size = Vector2(160, 30)
	no.pressed.connect(_answer.bind(false))
	row.add_child(no)
	no.grab_focus.call_deferred()
	tree_exiting.connect(func(): _answer(false))


func _answer(ok: bool) -> void:
	if _answered:
		return
	_answered = true
	if on_answer.is_valid():
		on_answer.call(ok)
	if is_inside_tree() and not is_queued_for_deletion():
		closed.emit()
