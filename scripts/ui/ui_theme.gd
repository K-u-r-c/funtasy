class_name UITheme
extends RefCounted
## "Obsidian Glass" UI theme, built in code and installed on the root window so every Control
## inherits it: translucent dark slate panels, crisp 1-2 px gold / cyan borders, chamfered
## pixel corners and a 1 px rim light. Nothing is blurred or antialiased. Focus styles are loud
## on purpose: the whole UI must be readable while navigating with a gamepad.
##
## The pixel font is a 16 px design: 16 (body), 32 (titles) and 48 (logo) are pixel-exact;
## smaller sizes are only used for dense numbers (cooldowns, counters).

# Palette -----------------------------------------------------------------------------------
const GLASS := Color("0d111af0")
const GLASS_DEEP := Color("070a10f2")
const SLATE := Color("161c2be6")
const SLATE_HI := Color("222c44f0")
const EDGE := Color("2e3a58")
const EDGE_HI := Color("44557e")
const GOLD := Color("e8b74a")
const GOLD_DIM := Color("8c6a2c")
const CYAN := Color("6ee3f0")
const CYAN_DIM := Color("2b7480")
const RIM := Color(1, 1, 1, 0.09)
const SHADOW := Color(0, 0, 0, 0.55)

# Names kept from the first theme (used all over the UI code).
const BG := Color("06080d")
const PANEL := GLASS
const BORDER := EDGE
const ACCENT := GOLD
const TEXT := Color("f0ece1")
const TEXT_DIM := Color("8e93a6")
const DANGER := Color("f25050")
const GOOD := Color("6fe08a")

const FONT_SMALL := 12
const FONT_BODY := 16
const FONT_TITLE := 32
const FONT_LOGO := 48

static var _font: Font
static var _frame: StyleBoxTexture
static var _glass_cache: Dictionary = {}


static func install(root: Window) -> void:
	var t := build()
	root.theme = t
	# Controls under a CanvasLayer (HUD, overlays) don't inherit the root window's theme; they
	# fall back to the engine default theme, so the same styles go there too.
	var d := ThemeDB.get_default_theme()
	d.merge_with(t)
	d.default_font = t.default_font
	d.default_font_size = t.default_font_size


static func font() -> Font:
	if _font == null:
		var path := GameData.asset_path("ui.font")
		if not path.is_empty() and ResourceLoader.exists(path):
			var f: FontFile = load(path)
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.hinting = TextServer.HINTING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			# The pixel font has no brackets, '#', '&', '<', '>', '|' ... fall back for those.
			f.fallbacks = [ThemeDB.fallback_font]
			_font = f
		else:
			_font = ThemeDB.fallback_font
	return _font


## The gilded 9-slice frame (PixelLab art) drawn on top of important windows.
static func ornate_frame() -> StyleBoxTexture:
	if _frame == null:
		var entry := GameData.asset_entry("ui.frame_ornate")
		var path := str(entry.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return null
		var m := float(entry.get("margin", 24))
		_frame = StyleBoxTexture.new()
		_frame.texture = load(path)
		_frame.texture_margin_left = m
		_frame.texture_margin_right = m
		_frame.texture_margin_top = m
		_frame.texture_margin_bottom = m
		_frame.draw_center = false
		_frame.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		_frame.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return _frame


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_BODY

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", SHADOW)
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("panel", "PanelContainer", glass(GLASS, EDGE, 1, 10))
	t.set_stylebox("panel", "Panel", glass(GLASS, EDGE, 1, 0))
	# Variations: windows get a gold border with cyan corner accents; insets are darker wells.
	t.set_type_variation("GlassWindow", "PanelContainer")
	t.set_stylebox("panel", "GlassWindow", glass(GLASS, GOLD_DIM, 1, 14, CYAN))
	t.set_type_variation("GlassInset", "PanelContainer")
	t.set_stylebox("panel", "GlassInset", glass(GLASS_DEEP, EDGE, 1, 8))
	t.set_type_variation("GlassHud", "PanelContainer")
	t.set_stylebox("panel", "GlassHud", glass(Color("0d111ad0"), EDGE, 1, 4))
	t.set_type_variation("HeaderLabel", "Label")
	t.set_color("font_color", "HeaderLabel", GOLD)
	t.set_font_size("font_size", "HeaderLabel", FONT_BODY)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	for type in ["Button", "OptionButton", "CheckButton", "CheckBox", "MenuButton"]:
		_button_styles(t, type)
	t.set_constant("h_separation", "Button", 6)
	t.set_constant("icon_max_width", "Button", 32)

	t.set_stylebox("normal", "LineEdit", glass(GLASS_DEEP, EDGE, 1, 6))
	t.set_stylebox("focus", "LineEdit", glass(Color(0, 0, 0, 0), GOLD, 1, 6))
	t.set_stylebox("read_only", "LineEdit", glass(GLASS_DEEP, EDGE, 1, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_color("selection_color", "LineEdit", Color(CYAN, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	t.set_stylebox("panel", "TabContainer", glass(GLASS_DEEP, EDGE, 1, 10))
	t.set_stylebox("tab_selected", "TabContainer", glass(SLATE_HI, GOLD, 1, 8, Color(0, 0, 0, 0), true))
	t.set_stylebox("tab_unselected", "TabContainer", glass(SLATE, EDGE, 1, 8))
	t.set_stylebox("tab_hovered", "TabContainer", glass(SLATE_HI, CYAN_DIM, 1, 8))
	t.set_stylebox("tab_focus", "TabContainer", glass(Color(0, 0, 0, 0), CYAN, 1, 8))
	t.set_stylebox("tab_disabled", "TabContainer", glass(SLATE, EDGE, 1, 8))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 0)

	t.set_stylebox("background", "ProgressBar", glass(GLASS_DEEP, EDGE, 1, 0))
	t.set_stylebox("fill", "ProgressBar", glass(Color("b8333a"), Color(0, 0, 0, 0), 0, 0))

	t.set_stylebox("panel", "TooltipPanel", glass(Color("080b12f5"), CYAN_DIM, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "PopupMenu", glass(Color("080b12f8"), GOLD_DIM, 1, 6))
	t.set_stylebox("hover", "PopupMenu", glass(SLATE_HI, CYAN_DIM, 1, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "PopupPanel", glass(Color("080b12f8"), GOLD_DIM, 1, 6))

	t.set_stylebox("slider", "HSlider", glass(GLASS_DEEP, EDGE, 1, 0))
	t.set_stylebox("grabber_area", "HSlider", glass(GOLD_DIM, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", glass(GOLD, Color(0, 0, 0, 0), 0, 0))
	t.set_icon("grabber", "HSlider", _square_icon(10, GOLD, Color("3a2a0c")))
	t.set_icon("grabber_highlight", "HSlider", _square_icon(10, Color("ffd97a"), Color("3a2a0c")))

	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, glass(GLASS_DEEP, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber", sb, glass(EDGE_HI, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_highlight", sb, glass(CYAN_DIM, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_pressed", sb, glass(CYAN, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_constant("separation", "HSeparator", 6)
	t.set_stylebox("separator", "HSeparator", _line(EDGE))
	return t


static func _button_styles(t: Theme, type: String) -> void:
	t.set_stylebox("normal", type, glass(SLATE, EDGE, 1, 8))
	t.set_stylebox("hover", type, glass(SLATE_HI, CYAN_DIM, 1, 8))
	# Tactile press: the content drops by one pixel.
	var pressed := glass(Color("0a0e18f0"), GOLD, 1, 8)
	pressed.content_margin_top += 1
	pressed.content_margin_bottom -= 1
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("focus", type, glass(Color(0, 0, 0, 0), GOLD, 1, 8, CYAN))
	t.set_stylebox("disabled", type, glass(Color("0d111a99"), Color("1c2333"), 1, 8))
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_focus_color", type, Color("ffe7ad"))
	t.set_color("font_pressed_color", type, GOLD)
	t.set_color("font_hover_pressed_color", type, GOLD)
	t.set_color("font_disabled_color", type, Color("4a5066"))
	t.set_color("font_shadow_color", type, SHADOW)
	t.set_constant("shadow_offset_x", type, 1)
	t.set_constant("shadow_offset_y", type, 1)


## Glass panel style. `accent` (alpha > 0) draws 4 px corner brackets in that color;
## `top_glow` lights the top edge (selected tabs).
static func glass(bg: Color, border: Color, border_w: int = 1, margin: float = 8.0,
		accent: Color = Color(0, 0, 0, 0), top_glow := false) -> GlassBox:
	var sb := GlassBox.new()
	sb.bg = bg
	sb.border = border
	sb.border_w = border_w
	sb.accent = accent
	sb.top_glow = top_glow
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = roundf(margin * 0.6)
	sb.content_margin_bottom = roundf(margin * 0.6)
	return sb


## Shared (read-only!) glass style for widgets that draw every frame: no allocation per draw.
static func cached_glass(bg: Color, border: Color, border_w: int = 1, margin: float = 0.0,
		accent: Color = Color(0, 0, 0, 0)) -> GlassBox:
	var key := [bg, border, border_w, margin, accent]
	var sb: GlassBox = _glass_cache.get(key)
	if sb == null:
		if _glass_cache.size() > 512:
			_glass_cache.clear()  # safety net against callers animating colors
		sb = glass(bg, border, border_w, margin, accent)
		_glass_cache[key] = sb
	return sb


## Kept for older call sites: a glass box with the given colors.
static func box(bg: Color, border: Color, border_w: int, _radius: int, margin: float) -> GlassBox:
	return glass(bg, border, border_w, margin)


static func title(text: String, size: int = FONT_TITLE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _crisp(size))
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", Color("1a0f04"))
	l.add_theme_constant_override("outline_size", 4 if size >= 24 else 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func label(text: String, color: Color = TEXT, size: int = FONT_BODY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	var s := _crisp(size)
	if s != FONT_BODY:
		l.add_theme_font_size_override("font_size", s)
	return l


## Snaps a requested size to one the pixel font renders cleanly.
static func _crisp(size: int) -> int:
	if size >= 40:
		return FONT_LOGO
	if size >= 22:
		return FONT_TITLE
	if size >= 15:
		return FONT_BODY
	return FONT_SMALL


# Icons and ornaments (#29: explain with icons, colour and shape) ------------------------------

## Icon key (data/assets.json icons) of a stat, "" when it has none.
const STAT_ICONS := {"strength": "stat_strength", "stamina": "stat_stamina", "agility": "stat_agility",
	"intellect": "stat_intellect", "armor": "stat_armor", "weapon_dps": "stat_weapon_dps",
	"crit_chance": "stat_crit_chance", "crit_damage": "stat_crit_damage", "haste": "stat_haste",
	"dodge": "stat_dodge", "leech": "stat_leech", "max_hp": "hud_health", "max_resource": "stat_mana",
	"mana": "stat_mana", "fury": "stat_fury", "gold": "hud_gold", "xp": "hud_xp", "level": "hud_level",
	"move_speed": "nav_inventory", "power_melee": "class_warrior", "power_ranged": "class_ranger",
	"power_spell": "class_mage", "strength_reduction": "stat_armor", "resource_regen": "stat_mana"}

static var _tex_cache: Dictionary = {}


## A texture from the icons registry (cached; "" or a missing key -> null).
static func icon_tex(key: String) -> Texture2D:
	if key.is_empty():
		return null
	if not _tex_cache.has(key):
		_tex_cache[key] = GameData.texture("icons." + key) if GameData.asset_exists("icons." + key) else null
	return _tex_cache[key]


## A pixel-exact icon of `px` (16 = half size of the 32 px art) with an optional tint.
static func icon(key: String, px: int = 16, tint: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_tex(key)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.modulate = tint
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t


## Icon + text on one row.
static func icon_label(key: String, text: String, color: Color = TEXT, size: int = FONT_BODY, px: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(icon(key, px))
	var l := label(text, color, size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


## A section header: icon, gold title and the gilded divider running to the right.
static func section(text: String, icon_key: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	if not icon_key.is_empty():
		h.add_child(icon(icon_key, 16))
	var l := label(text, GOLD, FONT_BODY)
	l.add_theme_color_override("font_outline_color", Color("1a0f04"))
	l.add_theme_constant_override("outline_size", 2)
	h.add_child(l)
	var d := divider()
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(d)
	return h


## The gilded filigree divider (PixelLab ornament), stretched along its middle.
static func divider() -> Control:
	var tex := icon_tex("orn_divider")
	if tex == null:
		var sep := HSeparator.new()
		return sep
	var np := NinePatchRect.new()
	np.texture = tex
	np.region_rect = Rect2(Vector2.ZERO, tex.get_size())
	# The left curl and the right half (gem, knot, fading tip) stay as drawn; only the thin
	# line between them stretches.
	np.patch_margin_left = 60
	np.patch_margin_right = 100
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A NinePatchRect's minimum width is its patch margins: held in a plain Control so the
	# divider never widens a layout, and hidden while too short to show both ends.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(24, 12)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	holder.add_child(np)
	holder.resized.connect(func(): np.visible = holder.size.x >= 160.0)
	return holder


static var _slot_styles: Dictionary = {}


## The bronze-rimmed item well (PixelLab ornament) as a 9-slice style, tinted; null without art.
static func slot_style(tint: Color) -> StyleBoxTexture:
	if _slot_styles.has(tint):
		return _slot_styles[tint]
	var tex := icon_tex("orn_slot")
	var sb: StyleBoxTexture = null
	if tex:
		sb = StyleBoxTexture.new()
		sb.texture = tex
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 8)
		sb.modulate_color = tint
		sb.draw_center = false  # the art's centre is a glass lens; the slot draws its own well
	_slot_styles[tint] = sb
	return sb


## One item-card line ([text, color] or [text, color, icon key]): the stat's icon before the
## wrapped text (#29).
static func card_line(line: Array, width: float) -> Control:
	var l := label(str(line[0]), line[1], FONT_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if line.size() < 3 or str(line[2]).is_empty():
		l.custom_minimum_size = Vector2(width, 0)
		return l
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var ic := icon(str(line[2]), 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	l.custom_minimum_size = Vector2(width - 20, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


## A small glass pill with an icon and a value (gold, points, keys...).
static func chip(icon_key: String, text: String, color: Color = TEXT, border: Color = EDGE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass(Color("070a10e0"), border, 1, 6))
	var row := icon_label(icon_key, text, color, FONT_BODY, 16)
	p.add_child(row)
	p.set_meta("label", row.get_child(1))
	return p


static func hex(s: String, fallback: Color = Color.WHITE) -> Color:
	return Color.from_string(s, fallback)


static func rarity_color(tier: int) -> Color:
	return Color.from_string(str(GameData.rarity(tier).get("color", "#ffffff")), Color.WHITE)


static func _line(c: Color) -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = c
	l.thickness = 1
	return l


static func _square_icon(s: int, fill: Color, edge: Color) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(edge)
	img.fill_rect(Rect2i(1, 1, s - 2, s - 2), fill)
	img.fill_rect(Rect2i(1, 1, s - 2, 1), fill.lightened(0.35))
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(s - 1, 0, Color(0, 0, 0, 0))
	img.set_pixel(0, s - 1, Color(0, 0, 0, 0))
	img.set_pixel(s - 1, s - 1, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Pixel-exact glass panel: fill, 1-2 px border with chamfered (1 px cut) corners, a 1 px rim
## light along the inside of the top edge and optional corner accents. Drawn with plain
## rectangles, so it never blurs at any scale.
class GlassBox:
	extends StyleBox
	var bg := Color("0d111af0")
	var border := Color("2e3a58")
	var border_w := 1
	var accent := Color(0, 0, 0, 0)
	var top_glow := false
	var rim := Color(1, 1, 1, 0.09)

	func _draw(ci: RID, rect: Rect2) -> void:
		var r := Rect2(rect.position.round(), rect.size.round())
		if r.size.x < 3.0 or r.size.y < 3.0:
			return
		var x := r.position.x
		var y := r.position.y
		var w := r.size.x
		var h := r.size.y
		var bw := float(border_w)
		var rs := RenderingServer
		if bg.a > 0.0:
			rs.canvas_item_add_rect(ci, Rect2(x + 1, y, w - 2, h), bg)
			rs.canvas_item_add_rect(ci, Rect2(x, y + 1, 1, h - 2), bg)
			rs.canvas_item_add_rect(ci, Rect2(x + w - 1, y + 1, 1, h - 2), bg)
		if bw > 0.0 and border.a > 0.0:
			rs.canvas_item_add_rect(ci, Rect2(x + 1, y, w - 2, bw), border)
			rs.canvas_item_add_rect(ci, Rect2(x + 1, y + h - bw, w - 2, bw), border)
			rs.canvas_item_add_rect(ci, Rect2(x, y + 1, bw, h - 2), border)
			rs.canvas_item_add_rect(ci, Rect2(x + w - bw, y + 1, bw, h - 2), border)
		if bg.a > 0.0 and w > 2.0 * bw + 2.0:
			rs.canvas_item_add_rect(ci, Rect2(x + bw + 1, y + bw, w - 2.0 * bw - 2, 1), rim)
		if top_glow:
			rs.canvas_item_add_rect(ci, Rect2(x + 2, y + bw, w - 4, 1), Color(border, 0.6))
		if accent.a > 0.0 and w >= 12.0 and h >= 12.0:
			var l := 4.0
			for c: Vector2 in [Vector2(x, y), Vector2(x + w, y), Vector2(x, y + h), Vector2(x + w, y + h)]:
				var sx := 1.0 if c.x == x else -1.0
				var sy := 1.0 if c.y == y else -1.0
				var ox := c.x if sx > 0.0 else c.x - 1.0
				var oy := c.y if sy > 0.0 else c.y - 1.0
				rs.canvas_item_add_rect(ci, Rect2(ox + (0.0 if sx > 0.0 else -(l - 1.0)), oy, l, 1), accent)
				rs.canvas_item_add_rect(ci, Rect2(ox, oy + (0.0 if sy > 0.0 else -(l - 1.0)), 1, l), accent)
