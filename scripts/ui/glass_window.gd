class_name GlassWindow
extends PanelContainer
## Obsidian glass window: the "GlassWindow" panel style plus, when `ornate`, the gilded
## 9-slice frame (PixelLab art from data/assets.json "ui.frame_ornate") drawn over the glass.

var ornate := true


func _init(p_ornate := true) -> void:
	ornate = p_ornate
	theme_type_variation = &"GlassWindow"


func _ready() -> void:
	if ornate:
		# Keep children clear of the filigree corners.
		var sb: StyleBox = get_theme_stylebox("panel").duplicate()
		sb.content_margin_left = maxf(sb.content_margin_left, 16)
		sb.content_margin_right = maxf(sb.content_margin_right, 16)
		sb.content_margin_top = maxf(sb.content_margin_top, 14)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 14)
		add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	if not ornate:
		return
	var frame := UITheme.ornate_frame()
	if frame:
		draw_style_box(frame, Rect2(Vector2(-3, -3), size + Vector2(6, 6)))
