class_name UITheme
extends RefCounted
## Builds the dark-fantasy UI theme in code and installs it on the root window, so every
## Control in the game inherits it. Focus styles are loud on purpose: the whole UI must be
## readable while navigating with a gamepad.

const BG := Color(0.07, 0.06, 0.09, 0.96)
const PANEL := Color(0.11, 0.09, 0.13, 0.97)
const BORDER := Color(0.36, 0.28, 0.22)
const ACCENT := Color(0.95, 0.72, 0.32)
const TEXT := Color(0.9, 0.86, 0.8)
const TEXT_DIM := Color(0.6, 0.56, 0.52)
const DANGER := Color(0.95, 0.4, 0.35)
const GOOD := Color(0.5, 0.9, 0.5)


static func install(root: Window) -> void:
	root.theme = build()


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 0)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 2, 4, 10))
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 2, 4, 0))

	for type in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, box(Color(0.16, 0.13, 0.16), Color(0.3, 0.24, 0.2), 1, 3, 6))
		t.set_stylebox("hover", type, box(Color(0.24, 0.18, 0.18), Color(0.55, 0.4, 0.28), 1, 3, 6))
		t.set_stylebox("pressed", type, box(Color(0.32, 0.22, 0.16), ACCENT, 1, 3, 6))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 2, 3, 6))
		t.set_stylebox("disabled", type, box(Color(0.1, 0.09, 0.1), Color(0.18, 0.16, 0.16), 1, 3, 6))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 0.95, 0.85))
		t.set_color("font_focus_color", type, Color(1, 0.92, 0.7))
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_disabled_color", type, Color(0.4, 0.38, 0.36))

	t.set_stylebox("normal", "LineEdit", box(Color(0.05, 0.04, 0.06), Color(0.3, 0.24, 0.2), 1, 3, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.04, 0.06), ACCENT, 2, 3, 6))
	t.set_color("font_color", "LineEdit", TEXT)

	t.set_stylebox("panel", "TabContainer", box(PANEL, BORDER, 2, 4, 10))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.24, 0.18, 0.16), ACCENT, 1, 3, 6))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.12, 0.1, 0.12), BORDER, 1, 3, 6))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.2, 0.15, 0.15), BORDER, 1, 3, 6))
	t.set_stylebox("tab_focus", "TabContainer", box(Color(0, 0, 0, 0), ACCENT, 2, 3, 6))

	t.set_stylebox("background", "ProgressBar", box(Color(0.05, 0.04, 0.05), Color(0.2, 0.16, 0.14), 1, 2, 0))
	t.set_stylebox("fill", "ProgressBar", box(Color(0.7, 0.2, 0.18), Color(0, 0, 0, 0), 0, 2, 0))

	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.04, 0.06, 0.97), BORDER, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.3), Color(0, 0, 0, 0), 0, 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 0, 2, 0))
	t.set_stylebox("slider", "HSlider", box(Color(0.15, 0.12, 0.12), Color(0, 0, 0, 0), 0, 2, 0))
	return t


static func box(bg: Color, border: Color, border_w: int, radius: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


static func title(text: String, size: int = 32) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func label(text: String, color: Color = TEXT, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size != 16:
		l.add_theme_font_size_override("font_size", size)
	return l


static func hex(s: String, fallback: Color = Color.WHITE) -> Color:
	return Color.from_string(s, fallback)
