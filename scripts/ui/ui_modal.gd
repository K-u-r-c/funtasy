class_name UIModal
extends Control
## Base for full-screen overlays (character, inventory, talents, map, pause): a dim backdrop,
## a centered glass window clamped to `max_size` (so ultrawide screens get a centered window,
## not a stretched one), a header with the title and a footer of live button prompts.
## Subclasses fill `content` in `_build()` and set `title_text` / `prompts`.
## Game menu panels set `menu_tab`: they share one window size and a header with the title,
## a subtitle and a tab strip (LB/RB or a panel's own key switches panels; the HUD does that).

signal closed
signal switch_tab(id: String)

## The game menu panels, in tab order: [id (= input action), title].
const MENU_TABS := [["character", "Character"], ["inventory", "Inventory"], ["talents", "Talents"], ["skillbook", "Skill Book"], ["map", "Map"], ["codex", "Codex"]]
## Tab icons (data/assets.json icons, #29).
const TAB_ICONS := {"character": "nav_character", "inventory": "nav_inventory", "talents": "nav_talents",
	"skillbook": "nav_skillbook", "map": "nav_map", "codex": "nav_codex"}
var title_icon := ""  ## icon key shown before the title (the tab's icon for menu panels)

var player: Player
var title_text := ""
var max_size := Vector2.ZERO  ## 0 = data default (ui.modal_max_width/height)
var fill_height := false  ## stretch the window to max height (map) instead of fitting content
var ornate := true
var prompts: Array = []  ## [[action, text], ...] for the footer
var menu_tab := ""  ## id from MENU_TABS for the game menu panels, "" for other dialogs
var subtitle_text := ""
var subtitle: Label
var from_tab := false  ## opened by switching tabs: crossfade instead of the pop-in
var restore: Dictionary = {}  ## state from save_state() to bring back (returning from a book, #38)

var dim: ColorRect
var window: GlassWindow
var header: HBoxContainer
var content: VBoxContainer
var footer: PromptBar
var _notice: Label
var _notice_tween: Tween
var _center: CenterContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	window = GlassWindow.new(ornate)
	_center.add_child(window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	window.add_child(v)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	v.add_child(header)
	if title_icon.is_empty():
		title_icon = TAB_ICONS.get(menu_tab, "")
	if not title_icon.is_empty():
		var ti := UITheme.icon(title_icon, 32)
		header.add_child(ti)
	if not title_text.is_empty():
		header.add_child(UITheme.title(title_text, UITheme.FONT_TITLE))
	subtitle = UITheme.label(subtitle_text, UITheme.TEXT_DIM, UITheme.FONT_BODY)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	# A long subtitle (or a longer language, #32) is cut at a word instead of widening the window.
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	subtitle.ellipsis_char = "..."  # the pixel font has no "\u2026"
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.size_flags_stretch_ratio = 4.0
	header.add_child(subtitle)
	if not menu_tab.is_empty():
		header_spacer()
		header.add_child(_tab_strip())
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	_build()
	footer = PromptBar.new(prompts)
	footer.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_notice = UITheme.label("", UITheme.DANGER, UITheme.FONT_BODY)
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A long notice is cut at a word instead of widening the window (#85).
	_notice.clip_text = true
	_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	_notice.ellipsis_char = "..."
	_notice.modulate.a = 0.0
	foot.add_child(_notice)
	foot.add_child(footer)
	get_viewport().size_changed.connect(_fit)
	_fit()
	if from_tab:
		# Same window size and place as the previous tab: only the contents fade in.
		content.modulate.a = 0.0
		content.create_tween().tween_property(content, "modulate:a", 1.0, 0.12)
		AudioManager.play_sfx("ui_move", 0.0)
	else:
		UIFx.pop_in(window)


## Shows a short message in the window footer (refusals, results). The HUD forwards its
## messages here while the overlay is open, because the backdrop dims the HUD feed.
func notice(text: String, color: Color = UITheme.DANGER) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.0)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


## Override: what to bring back when the player returns to this panel (a selection...).
func save_state() -> Dictionary:
	return {}


## Override: build the window body into `content`.
func _build() -> void:
	pass


func _tab_strip() -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(InputGlyph.new("ui_tab_prev"))
	for t in MENU_TABS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = t[0] == menu_tab
		b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		b.custom_minimum_size = Vector2(0, 22)
		if t[0] == menu_tab:
			b.add_theme_stylebox_override("normal", UITheme.glass(UITheme.SLATE_HI, UITheme.GOLD, 1, 6, Color(0, 0, 0, 0), true))
			b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("normal"))
			b.add_theme_color_override("font_color", UITheme.GOLD)
			b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
		# Icons tell the tabs apart; only the open tab spells out its name.
		b.text = Loc.t(t[1]) if t[0] == menu_tab else ""
		b.icon = UITheme.icon_tex(TAB_ICONS.get(t[0], ""))
		b.add_theme_constant_override("icon_max_width", 16)
		b.custom_minimum_size.x = 0 if t[0] == menu_tab else 30
		b.tooltip_text = "%s [%s]" % [Loc.t(t[1]), InputSettings.prompt_for(t[0])]
		var id: String = t[0]
		b.pressed.connect(func():
			if id != menu_tab:
				switch_tab.emit(id))
		strip.add_child(b)
	strip.add_child(InputGlyph.new("ui_tab_next"))
	return strip


## The tab id `step` places away from this panel (wraps around).
func neighbor_tab(step: int) -> String:
	for i in MENU_TABS.size():
		if MENU_TABS[i][0] == menu_tab:
			return MENU_TABS[wrapi(i + step, 0, MENU_TABS.size())][0]
	return ""


## Header filler that pushes later header children to the right.
func header_spacer() -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(s)


func _fit() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var margin := float(GameData.bal("ui.safe_margin", 10)) * 2.0
	var cap := max_size
	if cap == Vector2.ZERO:
		cap = Vector2(float(GameData.bal("ui.modal_max_width", 920)), float(GameData.bal("ui.modal_max_height", 520)))
	var avail := (vp - Vector2(margin, margin)).min(cap)
	# Game menu panels all use the full size, so switching tabs never resizes the window.
	var fill := fill_height or not menu_tab.is_empty()
	window.custom_minimum_size = Vector2(avail.x if fill else 0.0, avail.y if fill else 0.0)
	window.set_meta("avail", avail)


## Space the window may use (for subclasses that size scroll areas / maps).
func available_size() -> Vector2:
	return window.get_meta("avail", Vector2(900, 500))
