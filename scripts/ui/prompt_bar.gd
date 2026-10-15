class_name PromptBar
extends HBoxContainer
## Row of "[glyph] Label" button hints ("(A) Equip  (X) Drop  (B) Close"). The glyphs switch
## between keyboard/mouse and gamepad as soon as the player touches the other device.


func _init(prompts: Array = []) -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_prompts(prompts)


## `prompts`: Array of [action, text] or [action, text, pad_only/kbm_only flag ("pad"/"kbm")].
func set_prompts(prompts: Array) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for p in prompts:
		add(str(p[0]), str(p[1]))


func add(action: String, text: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(InputGlyph.new(action))
	var l := UITheme.label(text, UITheme.TEXT_DIM, UITheme.FONT_SMALL)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	add_child(box)
