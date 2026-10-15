class_name ItemSlot
extends Button
## Inventory slot: item icon, stack count, a rarity border that pulses (rarity_pulse shader,
## stronger for higher tiers) and mouse drag-and-drop with a semi-transparent ghost preview.
## While something is being dragged, slots that accept it light up cyan and the rest dim red.
## What a drop *means* is decided by the owner through `accepts` and `item_dropped`.

signal item_dropped(data: Dictionary)

const PULSE := preload("res://assets/shaders/rarity_pulse.gdshader")
const DRAG_TYPE := "funtasy_item"
## Pulse strength / speed per rarity tier (1 = common: no glow).
const TIER_STRENGTH := [0.0, 0.0, 0.35, 0.55, 0.8, 1.1]

var item: Dictionary = {}
var slot_key := ""  ## "e:<slot>", "b:<index>", "q:<quick slot>"
var placeholder := ""  ## shown while empty ("Head", "Q")
var ghost_icon: Texture2D  ## drawn dimmed while empty (e.g. the 2H weapon in the off hand)
var accepts := Callable()  ## func(drag_data: Dictionary) -> bool
var draggable := true
## Gear the character's level is too low for: drawn darkened with a red frame and level badge.
var locked := false:
	set(v):
		if v != locked:
			locked = v
			queue_redraw()
var _overlay: ColorRect
var _mat: ShaderMaterial
var _drag_state := 0  ## 1 = valid target for the current drag, -1 = invalid, 0 = no drag
## Loaded outside _draw(): a texture loaded for the first time inside a draw call renders blank.
var _tex: Texture2D


func _init(px: int = 40) -> void:
	custom_minimum_size = Vector2(px, px)
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("normal", UITheme.glass(UITheme.GLASS_DEEP, UITheme.EDGE, 1, 0))
	add_theme_stylebox_override("hover", UITheme.glass(Color("121a2af2"), UITheme.CYAN_DIM, 1, 0))
	var pressed := UITheme.glass(Color("05070bf5"), UITheme.GOLD, 1, 0)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("focus", UITheme.glass(Color(0, 0, 0, 0), UITheme.GOLD, 1, 0))
	button_down.connect(func(): AudioManager.play_sfx("ui_press", 0.05))
	focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 0.0))


func _ready() -> void:
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = PULSE
	_overlay.material = _mat
	add_child(_overlay)
	resized.connect(func(): _mat.set_shader_parameter("rect_size", size.round()))
	_mat.set_shader_parameter("rect_size", size.round())
	mouse_entered.connect(func(): _mat.set_shader_parameter("highlight", 1.0))
	mouse_exited.connect(func(): _mat.set_shader_parameter("highlight", 0.0))
	set_item(item)


func set_item(it: Dictionary) -> void:
	item = it
	_tex = GameData.texture(str(item.icon)) if item.has("icon") else null
	if _mat == null:
		return
	var has := not item.is_empty() and item.has("uid")
	_overlay.visible = has
	if has:
		var tier := clampi(int(item.get("rarity", 1)), 1, 5)
		_mat.set_shader_parameter("rarity_color", UITheme.rarity_color(tier))
		_mat.set_shader_parameter("strength", TIER_STRENGTH[tier])
		_mat.set_shader_parameter("speed", 1.6 + tier * 0.45)
	queue_redraw()


func has_item() -> bool:
	return not item.is_empty() and item.has("uid")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size.round())
	var icon_rect := Rect2(((r.size - Vector2(32, 32)) / 2.0).round(), Vector2(32, 32))
	if _drag_state == 1:
		draw_rect(r.grow(-1), Color(UITheme.CYAN, 0.16))
		draw_rect(r.grow(-1), Color(UITheme.CYAN, 0.9), false, 1.0)
	if has_item() and _tex:
		var tex := _tex
		if tex:
			var lifted := Vector2(0, -1) if is_hovered() else Vector2.ZERO
			draw_texture_rect(tex, Rect2(icon_rect.position + Vector2(1, 2), icon_rect.size), false, Color(0, 0, 0, 0.45))
			draw_texture_rect(tex, Rect2(icon_rect.position + lifted, icon_rect.size), false,
					Color(0.55, 0.42, 0.42) if locked else Color.WHITE)
		if locked:
			draw_rect(r.grow(-1), Color(0.55, 0.05, 0.05, 0.25))
			draw_rect(r.grow(-1), Color(UITheme.DANGER, 0.9), false, 1.0)
			_level_badge(r)
		if item.get("kind") == "consumable":
			_corner_text(str(int(item.get("count", 1))), r, Color.WHITE)
	elif ghost_icon:
		draw_texture_rect(ghost_icon, icon_rect, false, Color(1, 1, 1, 0.25))
	elif not placeholder.is_empty():
		var f := UITheme.font()
		var fs := UITheme.FONT_SMALL
		var tw := f.get_string_size(placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(roundf((r.size.x - tw) / 2.0), roundf(r.size.y / 2.0 + 4)), placeholder,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.TEXT_DIM, 0.55))
	if _drag_state == -1:
		draw_rect(r.grow(-1), Color(0.5, 0.08, 0.08, 0.35))
	elif _drag_state == -2:
		# The right slot, but the level is too low: red frame, the drop explains why.
		draw_rect(r.grow(-1), Color(0.6, 0.08, 0.08, 0.3))
		draw_rect(r.grow(-1), UITheme.DANGER, false, 1.0)


## Red "Lv N" badge with a small padlock in the top-left corner.
func _level_badge(r: Rect2) -> void:
	var f := UITheme.font()
	var fs := UITheme.FONT_SMALL
	var t := "Lv%d" % int(item.get("req", 1))
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var badge := Rect2(Vector2(1, 1), Vector2(tw + 11, 11))
	draw_rect(badge, Color("3a0c0c"))
	draw_rect(badge, UITheme.DANGER, false, 1.0)
	var lc := Vector2(3, 3)
	draw_rect(Rect2(lc + Vector2(1, 0), Vector2(3, 1)), UITheme.TEXT)
	draw_rect(Rect2(lc + Vector2(1, 0), Vector2(1, 2)), UITheme.TEXT)
	draw_rect(Rect2(lc + Vector2(3, 0), Vector2(1, 2)), UITheme.TEXT)
	draw_rect(Rect2(lc + Vector2(0, 2), Vector2(5, 4)), UITheme.TEXT)
	draw_string(f, Vector2(9, 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffb3a8"))


func _corner_text(t: String, r: Rect2, c: Color) -> void:
	var f := UITheme.font()
	var fs := UITheme.FONT_SMALL
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(r.size.x - tw - 3, r.size.y - 3)
	draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.95))
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


# --- Drag and drop ---------------------------------------------------------------------------


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or not has_item():
		return null
	var ghost := Control.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UITheme.glass(Color("0d111ab0"), UITheme.rarity_color(int(item.get("rarity", 1))), 1, 0))
	frame.size = Vector2(36, 36)
	frame.position = Vector2(-18, -18)
	ghost.add_child(frame)
	var tr := TextureRect.new()
	tr.texture = _tex
	tr.size = Vector2(32, 32)
	tr.position = Vector2(-16, -16)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.add_child(tr)
	ghost.modulate.a = 0.75
	set_drag_preview(ghost)
	AudioManager.play_sfx("ui_press", 0.05)
	return {"type": DRAG_TYPE, "from": slot_key, "item": item, "locked": locked}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return _accepts(data)


func _drop_data(_at: Vector2, data: Variant) -> void:
	AudioManager.play_sfx("ui_drop", 0.05)
	item_dropped.emit(data)


func _accepts(data: Variant) -> bool:
	return data is Dictionary and data.get("type") == DRAG_TYPE and data.get("from") != slot_key \
			and accepts.is_valid() and bool(accepts.call(data))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var d: Variant = get_viewport().gui_get_drag_data()
		if d is Dictionary and d.get("type") == DRAG_TYPE:
			_drag_state = 1 if _accepts(d) else (0 if d.get("from") == slot_key else -1)
			if _drag_state == 1 and bool(d.get("locked", false)) and slot_key.begins_with("e:"):
				_drag_state = -2
			queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		_drag_state = 0
		queue_redraw()
