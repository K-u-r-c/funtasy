extends SceneTree
## Generates every placeholder asset (PNG sprite sheets, tiles, props, icons, FX, WAV audio)
## into res://assets/*/placeholder/. Run once (or after changing it):
##   godot --headless --path . -s tools/gen_placeholders.gd
## Then `godot --headless --path . --import` so Godot imports the new files.
## Final art (Pixellab) / audio (Suno) goes next to these files and is wired up by editing
## data/assets.json; this script never touches anything outside the placeholder folders.

const SPR := "res://assets/sprites/placeholder/"
const SFX := "res://assets/audio/sfx/placeholder/"
const MUS := "res://assets/audio/music/placeholder/"

## Direction rows of every character sheet, clockwise from east (screen space, y down).
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const ANIMS := {
	"idle": 4, "walk": 6, "attack": 4, "cast": 4, "dash": 3, "hit": 2, "downed": 2,
	"death": 4, "ghost": 4,
}


func _init() -> void:
	# `-- --only=audio` only writes sounds that don't exist yet (e.g. newly added UI sounds).
	if OS.get_cmdline_user_args().has("--only=audio"):
		DirAccess.make_dir_recursive_absolute(SFX)
		DirAccess.make_dir_recursive_absolute(MUS)
		_gen_audio()
		quit()
		return
	for d in [SPR + "characters", SPR + "monsters", SPR + "tiles", SPR + "props", SPR + "items",
			SPR + "projectiles", SPR + "fx", SPR + "icons", SFX, MUS]:
		DirAccess.make_dir_recursive_absolute(d)
	_gen_character_layers()
	_gen_monsters()
	_gen_tiles()
	_gen_props()
	_gen_item_icons()
	_gen_projectiles()
	_gen_fx()
	_gen_skill_icons()
	_gen_audio()
	print("placeholders generated")
	quit()


# =========================================================================================
# Raster helpers
# =========================================================================================


func _img(w: int, h: int) -> Image:
	var i := Image.create(w, h, false, Image.FORMAT_RGBA8)
	i.fill(Color(0, 0, 0, 0))
	return i


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _rect(img: Image, r: Rect2, c: Color) -> void:
	for x in range(int(floor(r.position.x)), int(ceil(r.end.x))):
		for y in range(int(floor(r.position.y)), int(ceil(r.end.y))):
			_px(img, x, y, c)


func _poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var minp := pts[0]
	var maxp := pts[0]
	for p in pts:
		minp = minp.min(p)
		maxp = maxp.max(p)
	for x in range(int(floor(minp.x)), int(ceil(maxp.x)) + 1):
		for y in range(int(floor(minp.y)), int(ceil(maxp.y)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_px(img, x, y, c)


func _circle(img: Image, center: Vector2, r: float, c: Color) -> void:
	for x in range(int(center.x - r - 1), int(center.x + r + 2)):
		for y in range(int(center.y - r - 1), int(center.y + r + 2)):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				_px(img, x, y, c)


func _ring(img: Image, center: Vector2, r: float, w: float, c: Color) -> void:
	for x in range(int(center.x - r - 1), int(center.x + r + 2)):
		for y in range(int(center.y - r - 1), int(center.y + r + 2)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= r and d >= r - w:
				_px(img, x, y, c)


func _ellipse(img: Image, center: Vector2, rx: float, ry: float, c: Color) -> void:
	for x in range(int(center.x - rx - 1), int(center.x + rx + 2)):
		for y in range(int(center.y - ry - 1), int(center.y + ry + 2)):
			var d := Vector2((x + 0.5 - center.x) / rx, (y + 0.5 - center.y) / ry)
			if d.length() <= 1.0:
				_px(img, x, y, c)


## Thick line as a rotated rectangle.
func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		_circle(img, a, w / 2.0, c)
		return
	var n := Vector2(-d.y, d.x).normalized() * w / 2.0
	_poly(img, PackedVector2Array([a + n, b + n, b - n, a - n]), c)


## Dark 1px outline around opaque pixels, the classic pixel-art readability trick.
func _outline(img: Image, c: Color) -> void:
	var src := img.duplicate()
	for x in img.get_width():
		for y in img.get_height():
			if src.get_pixel(x, y).a > 0.1:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + o
				if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
					if src.get_pixel(p.x, p.y).a > 0.5:
						img.set_pixel(x, y, c)
						break


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		push_error("could not save %s" % path)


# =========================================================================================
# Characters: one sheet per (layer, animation); rows = 8 directions, columns = frames.
# =========================================================================================

const SKIN := Color(0.86, 0.68, 0.55)
const SKIN_D := Color(0.66, 0.48, 0.4)
const CLOTH := Color(0.25, 0.22, 0.24)
const HAIR := Color(0.3, 0.2, 0.14)
const G_HI := Color(0.97, 0.97, 0.97)
const G_MID := Color(0.8, 0.8, 0.8)
const G_LO := Color(0.55, 0.55, 0.58)


func _pose(anim: String, f: int, n: int) -> Dictionary:
	var t := float(f) / float(n)
	var p := {"bob": 0.0, "phase": 0.0, "walk": 0.0, "swing": -1.0, "arms_up": 0.0,
		"lying": 0.0, "alpha": 1.0, "recoil": 0.0, "lean": 0.0, "float": 0.0, "flash": 0.0}
	match anim:
		"idle":
			p.bob = [0.0, 0.0, 1.0, 1.0][f]
		"walk":
			p.walk = 1.0
			p.phase = t * TAU
			p.bob = absf(sin(t * TAU)) * -1.5
		"attack":
			p.swing = [0.0, 0.45, 1.0, 0.75][f]
			p.lean = [0.0, 1.0, 2.0, 1.0][f]
		"cast":
			p.arms_up = [0.4, 1.0, 1.0, 0.6][f]
		"dash":
			p.lean = 4.0
			p.alpha = [1.0, 0.85, 0.7][f]
			p.walk = 1.0
			p.phase = PI * 0.5
		"hit":
			p.recoil = [2.5, 1.0][f]
			p.flash = [0.6, 0.2][f]
		"downed":
			p.lying = 1.0
			p.bob = [0.0, 0.5][f]
		"death":
			p.lying = [0.25, 0.6, 0.9, 1.0][f]
			p.alpha = [1.0, 0.95, 0.85, 0.75][f]
		"ghost":
			p.alpha = 0.45
			p.float = -4.0 + sin(t * TAU) * 2.0
	return p


## Builds the figure geometry for one pose/direction in local space (feet at origin, y down).
func _figure(dir_i: int, pose: Dictionary, hunch: float = 0.0) -> Dictionary:
	var ang := dir_i * PI / 4.0
	var dir := Vector2(cos(ang), sin(ang))
	var side := absf(dir.x)
	var back := dir.y < -0.3
	var perp := Vector2(-dir.y, dir.x)
	var bob: float = pose.bob + pose.float
	var lean: Vector2 = dir * pose.lean - dir * pose.recoil
	var g := {"dir": dir, "side": side, "back": back, "perp": perp}
	var legs: Array = []
	for i in 2:
		var ph: float = pose.phase + i * PI
		var lift: float = maxf(0.0, sin(ph)) * 2.5 * pose.walk
		var stride: float = sin(ph) * 3.5 * pose.walk
		var lx: float = (-3.2 if i == 0 else 3.2) * (1.0 - side * 0.75) + dir.x * stride * side
		var ly: float = -lift + dir.y * stride * 0.4
		legs.append(Rect2(lx - 2.2, -13.0 + ly + pose.float, 4.4, 13.0))
	g.legs = legs
	var torso_w := 15.0 - 5.0 * side
	var torso_c := Vector2(lean.x * 0.5, -21.0 + bob + hunch * 2.0) + Vector2(dir.x * hunch * 2.0, 0)
	g.torso = Rect2(torso_c - Vector2(torso_w / 2.0, 8.5), Vector2(torso_w, 17.0))
	g.head = torso_c + Vector2(lean.x * 0.4 + dir.x * hunch * 3.0, -14.0 + hunch * 3.0)
	var shoulder_main := torso_c + Vector2(0, -6) + perp * (torso_w / 2.0 + 1.0) * (1.0 - side * 0.4)
	var shoulder_off := torso_c + Vector2(0, -6) - perp * (torso_w / 2.0 + 1.0) * (1.0 - side * 0.4)
	if side > 0.6:
		shoulder_main = torso_c + Vector2(0, -6)
		shoulder_off = torso_c + Vector2(-dir.x * 2.0, -6)
	var main_dir := Vector2(0, 1)
	var off_dir := Vector2(0, 1)
	if pose.swing >= 0.0:
		main_dir = dir.rotated(lerpf(-1.3, 1.1, pose.swing))
	if pose.arms_up > 0.0:
		main_dir = main_dir.lerp(dir * 0.4 + Vector2(0, -1), pose.arms_up).normalized()
		off_dir = off_dir.lerp(dir * 0.4 + Vector2(0, -1), pose.arms_up).normalized()
	if pose.walk > 0.0 and pose.swing < 0.0:
		main_dir = (main_dir + dir * sin(pose.phase) * 0.35).normalized()
		off_dir = (off_dir - dir * sin(pose.phase) * 0.35).normalized()
	g.shoulder_main = shoulder_main
	g.shoulder_off = shoulder_off
	g.hand_main = shoulder_main + main_dir * 11.0
	g.hand_off = shoulder_off + off_dir * 11.0
	g.weapon_dir = main_dir if pose.swing >= 0.0 else (dir * 0.6 + Vector2(0, 0.4)).normalized()
	if pose.arms_up > 0.0:
		g.weapon_dir = Vector2(0, -1).lerp(dir, 0.3).normalized()
	return g


## Transforms local figure space into frame pixels (lying rotation, scale, frame anchor).
func _xf(p: Vector2, pose: Dictionary, anchor: Vector2, s: float) -> Vector2:
	var lying: float = pose.lying
	if lying > 0.0:
		p = p.rotated(PI / 2.0 * lying) + Vector2(-16.0 * lying, -2.0 * lying)
	return anchor + p * s


func _xrect(img: Image, r: Rect2, c: Color, pose: Dictionary, anchor: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		_xf(r.position, pose, anchor, s), _xf(Vector2(r.end.x, r.position.y), pose, anchor, s),
		_xf(r.end, pose, anchor, s), _xf(Vector2(r.position.x, r.end.y), pose, anchor, s),
	])
	_poly(img, pts, c)


func _xline(img: Image, a: Vector2, b: Vector2, w: float, c: Color, pose: Dictionary, anchor: Vector2, s: float) -> void:
	_line(img, _xf(a, pose, anchor, s), _xf(b, pose, anchor, s), w * s, c)


func _xcircle(img: Image, p: Vector2, r: float, c: Color, pose: Dictionary, anchor: Vector2, s: float) -> void:
	_circle(img, _xf(p, pose, anchor, s), r * s, c)


## Draws one layer of a figure. `style` selects body / armor piece / weapon.
func _draw_layer(img: Image, style: Dictionary, g: Dictionary, pose: Dictionary, anchor: Vector2, s: float) -> void:
	var kind: String = style.kind
	var c1: Color = style.get("c1", G_MID)
	var c2: Color = style.get("c2", G_LO)
	var c3: Color = style.get("c3", G_HI)
	match kind:
		"body":
			for leg in g.legs:
				_xrect(img, leg, style.get("skin_d", SKIN_D), pose, anchor, s)
			var t: Rect2 = g.torso
			_xline(img, g.shoulder_off, g.hand_off, 4.0, style.get("skin_d", SKIN_D), pose, anchor, s)
			_xrect(img, t, style.get("skin", SKIN), pose, anchor, s)
			_xrect(img, Rect2(t.position.x, t.end.y - 5.0, t.size.x, 5.0), style.get("cloth", CLOTH), pose, anchor, s)
			_xline(img, g.shoulder_main, g.hand_main, 4.0, style.get("skin", SKIN), pose, anchor, s)
			_xcircle(img, g.head, 7.0, style.get("skin", SKIN), pose, anchor, s)
			if style.get("hair", true):
				var hair_c: Color = style.get("hair_c", HAIR)
				if g.back:
					_xcircle(img, g.head, 7.0, hair_c, pose, anchor, s)
				else:
					_xcircle(img, g.head + Vector2(0, -3) - g.dir * 2.0, 5.5, hair_c, pose, anchor, s)
			if not g.back:
				var eye_c: Color = style.get("eyes", Color(0.1, 0.08, 0.1))
				var fwd: Vector2 = g.dir * 3.0 + Vector2(0, 1)
				if g.side < 0.6:
					_xcircle(img, g.head + fwd + g.perp * 2.5, 1.0, eye_c, pose, anchor, s)
					_xcircle(img, g.head + fwd - g.perp * 2.5, 1.0, eye_c, pose, anchor, s)
				else:
					_xcircle(img, g.head + fwd * 1.3, 1.0, eye_c, pose, anchor, s)
		"robe":
			var t2: Rect2 = g.torso
			var hem := Rect2(t2.position.x - 2.0, t2.position.y, t2.size.x + 4.0, -t2.position.y)
			_xrect(img, hem, c1, pose, anchor, s)
			_xrect(img, Rect2(hem.position.x, -4.0, hem.size.x, 4.0), c2, pose, anchor, s)
			_xline(img, g.shoulder_main, g.hand_main, 5.0, c1, pose, anchor, s)
			_xline(img, g.shoulder_off, g.hand_off, 5.0, c2, pose, anchor, s)
		"helm":
			_xcircle(img, g.head + Vector2(0, -1.5), 8.0, c1, pose, anchor, s)
			_xrect(img, Rect2(g.head + Vector2(-8.5, 1.0), Vector2(17, 2.5)), c2, pose, anchor, s)
			if not g.back:
				_xrect(img, Rect2(g.head + g.dir * 3.0 + Vector2(-1, 0), Vector2(2, 5)), c3, pose, anchor, s)
		"hood":
			_xcircle(img, g.head + Vector2(0, -1.0), 8.5, c1, pose, anchor, s)
			if not g.back:
				_xcircle(img, g.head + g.dir * 2.5 + Vector2(0, 1.5), 5.0, Color(0.05, 0.04, 0.06), pose, anchor, s)
		"crown":
			var hc: Vector2 = g.head + Vector2(0, -6)
			_xrect(img, Rect2(hc + Vector2(-6, -1), Vector2(12, 3)), c1, pose, anchor, s)
			for k in 3:
				_xrect(img, Rect2(hc + Vector2(-6 + k * 5, -5), Vector2(2, 4)), c1, pose, anchor, s)
		"chest":
			var t3: Rect2 = g.torso
			_xrect(img, Rect2(t3.position - Vector2(1, 1), Vector2(t3.size.x + 2, t3.size.y - 3)), c1, pose, anchor, s)
			_xrect(img, Rect2(t3.position.x - 1, t3.end.y - 6, t3.size.x + 2, 2), c2, pose, anchor, s)
			_xcircle(img, g.shoulder_main, 3.2, c3, pose, anchor, s)
			_xcircle(img, g.shoulder_off, 3.2, c2, pose, anchor, s)
			_xline(img, g.shoulder_main, g.shoulder_main.lerp(g.hand_main, 0.55), 5.0, c1, pose, anchor, s)
		"legs":
			for leg in g.legs:
				var r: Rect2 = leg
				_xrect(img, Rect2(r.position.x - 0.5, r.position.y - 2.0, r.size.x + 1.0, r.size.y - 2.0), c1, pose, anchor, s)
			var t4: Rect2 = g.torso
			_xrect(img, Rect2(t4.position.x, t4.end.y - 4.0, t4.size.x, 4.0), c2, pose, anchor, s)
		"boots":
			for leg in g.legs:
				var r2: Rect2 = leg
				_xrect(img, Rect2(r2.position.x - 1.0, r2.end.y - 5.0, r2.size.x + 2.0, 5.0), c1, pose, anchor, s)
				_xrect(img, Rect2(r2.position.x - 1.0, r2.end.y - 5.0, r2.size.x + 2.0, 1.0), c3, pose, anchor, s)
		"gloves":
			_xcircle(img, g.hand_main, 2.8, c1, pose, anchor, s)
			_xcircle(img, g.hand_off, 2.8, c2, pose, anchor, s)
		"weapon":
			_draw_weapon(img, style.weapon, g, pose, anchor, s, c1, c2, c3)
		"offhand":
			if style.weapon == "shield":
				var hc2: Vector2 = g.hand_off + g.dir * 2.0
				_xrect(img, Rect2(hc2 - Vector2(5, 6), Vector2(10, 12)), c1, pose, anchor, s)
				_xrect(img, Rect2(hc2 - Vector2(5, 6), Vector2(10, 2)), c3, pose, anchor, s)
				_xrect(img, Rect2(hc2 - Vector2(1, 3), Vector2(2, 6)), c2, pose, anchor, s)
			else:
				_xcircle(img, g.hand_off + Vector2(0, -3), 3.0, c1, pose, anchor, s)
				_xcircle(img, g.hand_off + Vector2(-1, -4), 1.2, c3, pose, anchor, s)


func _draw_weapon(img: Image, w: String, g: Dictionary, pose: Dictionary, anchor: Vector2, s: float, c1: Color, c2: Color, c3: Color) -> void:
	var h: Vector2 = g.hand_main
	var d: Vector2 = g.weapon_dir
	var wood := Color(0.62, 0.62, 0.62)
	match w:
		"sword":
			_xline(img, h - d * 3.0, h + d * 2.0, 2.0, wood, pose, anchor, s)
			_xline(img, h + d * 2.0 - Vector2(-d.y, d.x) * 3.0, h + d * 2.0 + Vector2(-d.y, d.x) * 3.0, 2.0, c2, pose, anchor, s)
			_xline(img, h + d * 2.0, h + d * 16.0, 2.5, c1, pose, anchor, s)
			_xline(img, h + d * 3.0, h + d * 15.0, 1.0, c3, pose, anchor, s)
		"greatsword":
			_xline(img, h - d * 5.0, h + d * 3.0, 2.0, wood, pose, anchor, s)
			_xline(img, h + d * 3.0 - Vector2(-d.y, d.x) * 4.0, h + d * 3.0 + Vector2(-d.y, d.x) * 4.0, 2.5, c2, pose, anchor, s)
			_xline(img, h + d * 3.0, h + d * 23.0, 3.5, c1, pose, anchor, s)
			_xline(img, h + d * 4.0, h + d * 22.0, 1.0, c3, pose, anchor, s)
		"axe", "greataxe":
			var big := w == "greataxe"
			var ln := 20.0 if big else 14.0
			_xline(img, h - d * 3.0, h + d * ln, 2.0, wood, pose, anchor, s)
			var head_c := h + d * (ln - 3.0)
			var n := Vector2(-d.y, d.x)
			var hs := 6.0 if big else 4.5
			_xline(img, head_c, head_c + n * hs, 6.0 if big else 4.5, c1, pose, anchor, s)
			_xline(img, head_c + n * hs, head_c + n * hs + d * 1.0, 2.0, c3, pose, anchor, s)
		"mace", "warhammer":
			var big2 := w == "warhammer"
			var ln2 := 20.0 if big2 else 13.0
			_xline(img, h - d * 3.0, h + d * ln2, 2.0, wood, pose, anchor, s)
			if big2:
				var n2 := Vector2(-d.y, d.x)
				_xline(img, h + d * ln2 - n2 * 5.0, h + d * ln2 + n2 * 5.0, 6.0, c1, pose, anchor, s)
			else:
				_xcircle(img, h + d * ln2, 3.5, c1, pose, anchor, s)
				_xcircle(img, h + d * ln2 - Vector2(1, 1), 1.2, c3, pose, anchor, s)
		"bow":
			var n3 := Vector2(-d.y, d.x)
			var mid := h + d * 2.0
			_xline(img, mid - n3 * 10.0, mid + d * 3.0, 2.0, c1, pose, anchor, s)
			_xline(img, mid + d * 3.0, mid + n3 * 10.0, 2.0, c1, pose, anchor, s)
			_xline(img, mid - n3 * 10.0, mid + n3 * 10.0, 1.0, c3, pose, anchor, s)
		"crossbow":
			var n4 := Vector2(-d.y, d.x)
			_xline(img, h - d * 4.0, h + d * 10.0, 3.0, wood, pose, anchor, s)
			_xline(img, h + d * 8.0 - n4 * 7.0, h + d * 8.0 + n4 * 7.0, 2.0, c1, pose, anchor, s)
		"sling":
			_xline(img, h, h + d * 6.0 + Vector2(0, 4), 1.0, c1, pose, anchor, s)
			_xcircle(img, h + d * 6.0 + Vector2(0, 5), 2.0, c2, pose, anchor, s)
		"wand":
			_xline(img, h - d * 2.0, h + d * 11.0, 2.0, c1, pose, anchor, s)
			_xcircle(img, h + d * 11.0, 2.0, c3, pose, anchor, s)
		"staff":
			_xline(img, h - d * 10.0, h + d * 18.0, 2.5, c1, pose, anchor, s)
			_xcircle(img, h + d * 19.0, 3.5, c3, pose, anchor, s)
			_xcircle(img, h + d * 19.0, 2.0, c2, pose, anchor, s)
		"claws":
			var n5 := Vector2(-d.y, d.x)
			for k in [-1.5, 0.0, 1.5]:
				_xline(img, h, h + d * 6.0 + n5 * k * 1.5, 1.0, c1, pose, anchor, s)


## Renders a full sheet set (all anims) for a list of layer styles drawn on top of each other.
func _render_set(folder: String, styles: Array, frame: int, scale: float, hunch: float = 0.0, outline := true) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var anchor := Vector2(frame / 2.0, frame - 6.0 * scale)
	for anim in ANIMS:
		var n: int = ANIMS[anim]
		var sheet := _img(frame * n, frame * 8)
		for di in 8:
			for f in n:
				var pose := _pose(anim, f, n)
				var g := _figure(di, pose, hunch)
				var fr := _img(frame, frame)
				for st in styles:
					_draw_layer(fr, st, g, pose, anchor, scale)
				if outline:
					_outline(fr, Color(0.04, 0.03, 0.05, 1.0))
				if pose.flash > 0.0 or pose.alpha < 1.0:
					for x in frame:
						for y in frame:
							var c := fr.get_pixel(x, y)
							if c.a > 0.0:
								c = c.lerp(Color(1, 1, 1, c.a), pose.flash)
								c.a *= pose.alpha
								fr.set_pixel(x, y, c)
				sheet.blit_rect(fr, Rect2i(0, 0, frame, frame), Vector2i(f * frame, di * frame))
		_save(sheet, folder + anim + ".png")


func _gen_character_layers() -> void:
	var base := SPR + "characters/"
	# Unoutlined gear layers would look detached, so every layer gets its own outline.
	_render_set(base + "body_human/", [{"kind": "body"}], 64, 1.0)
	var armor := {
		"head_helm": {"kind": "helm"},
		"head_hood": {"kind": "hood", "c1": G_MID},
		"chest_armor": {"kind": "chest"},
		"chest_robe": {"kind": "robe"},
		"legs_armor": {"kind": "legs"},
		"boots_armor": {"kind": "boots"},
		"gloves_armor": {"kind": "gloves"},
	}
	for key in armor:
		_render_set(base + key + "/", [armor[key]], 64, 1.0)
	for w in ["sword", "greatsword", "axe", "greataxe", "mace", "warhammer", "bow", "crossbow", "sling", "wand", "staff"]:
		_render_set(base + "weapon_" + w + "/", [{"kind": "weapon", "weapon": w}], 64, 1.0)
	for o in ["shield", "trinket"]:
		_render_set(base + "offhand_" + o + "/", [{"kind": "offhand", "weapon": o}], 64, 1.0)


func _gen_monsters() -> void:
	var base := SPR + "monsters/"
	var bone := Color(0.85, 0.83, 0.74)
	var bone_d := Color(0.6, 0.58, 0.5)
	_render_set(base + "ghoul/", [
		{"kind": "body", "skin": Color(0.45, 0.55, 0.42), "skin_d": Color(0.32, 0.4, 0.3),
			"cloth": Color(0.25, 0.2, 0.18), "hair": false, "eyes": Color(0.9, 0.85, 0.2)},
		{"kind": "weapon", "weapon": "claws", "c1": Color(0.9, 0.88, 0.8)},
	], 64, 1.0, 2.0)
	_render_set(base + "skeleton_archer/", [
		{"kind": "body", "skin": bone, "skin_d": bone_d, "cloth": Color(0.3, 0.25, 0.2), "hair": false,
			"eyes": Color(0.3, 0.8, 1.0)},
		{"kind": "weapon", "weapon": "bow", "c1": Color(0.45, 0.3, 0.2), "c3": Color(0.85, 0.85, 0.8)},
	], 64, 1.0)
	_render_set(base + "cultist/", [
		{"kind": "body", "skin": Color(0.7, 0.6, 0.55), "skin_d": Color(0.5, 0.42, 0.4), "hair": false,
			"eyes": Color(1.0, 0.3, 0.9)},
		{"kind": "robe", "c1": Color(0.35, 0.15, 0.4), "c2": Color(0.22, 0.08, 0.26)},
		{"kind": "hood", "c1": Color(0.3, 0.12, 0.35)},
		{"kind": "weapon", "weapon": "staff", "c1": Color(0.3, 0.22, 0.15), "c2": Color(0.8, 0.2, 0.9), "c3": Color(1, 0.6, 1)},
	], 64, 1.0)
	_render_set(base + "bone_lord/", [
		{"kind": "body", "skin": bone, "skin_d": bone_d, "cloth": Color(0.4, 0.05, 0.08), "hair": false,
			"eyes": Color(1.0, 0.15, 0.1)},
		{"kind": "chest", "c1": Color(0.3, 0.3, 0.34), "c2": Color(0.5, 0.1, 0.1), "c3": Color(0.6, 0.6, 0.65)},
		{"kind": "crown", "c1": Color(0.95, 0.75, 0.2)},
		{"kind": "weapon", "weapon": "greatsword", "c1": Color(0.4, 0.4, 0.45), "c2": Color(0.6, 0.1, 0.1), "c3": Color(0.9, 0.3, 0.3)},
	], 96, 1.45)


# =========================================================================================
# Tiles (32x32): atlas row 0 = floor x4, row 1 = wall top, wall face x2, lava x2 (anim frames)
# =========================================================================================


func _noise_fill(img: Image, r: Rect2i, base: Color, var_amt: float, rng: RandomNumberGenerator) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			img.set_pixel(x, y, base.lightened(rng.randf_range(-var_amt, var_amt)) if rng.randf() < 0.5 else base.darkened(rng.randf_range(0, var_amt)))


func _gen_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var img := _img(32 * 4, 32 * 2)
	var floor_c := Color(0.2, 0.19, 0.22)
	for i in 4:
		var r := Rect2i(i * 32, 0, 32, 32)
		_noise_fill(img, r, floor_c, 0.06, rng)
		# flagstone seams
		for x in range(r.position.x, r.end.x):
			img.set_pixel(x, r.position.y + 15 + (i % 2), floor_c.darkened(0.45))
			img.set_pixel(x, r.position.y, floor_c.darkened(0.3))
		for y in range(r.position.y, r.position.y + 16):
			img.set_pixel(r.position.x + 9 + i * 3, y, floor_c.darkened(0.45))
		for y in range(r.position.y + 16, r.end.y):
			img.set_pixel(r.position.x + 22 - i * 2, y, floor_c.darkened(0.45))
		if i == 3:
			for k in 6:
				img.set_pixel(r.position.x + rng.randi_range(2, 29), r.position.y + rng.randi_range(2, 29), Color(0.35, 0.3, 0.28))
	# wall top
	var wt := Rect2i(0, 32, 32, 32)
	_noise_fill(img, wt, Color(0.07, 0.065, 0.08), 0.15, rng)
	# wall faces: bricks
	for v in 2:
		var wf := Rect2i(32 + v * 32, 32, 32, 32)
		_noise_fill(img, wf, Color(0.3, 0.27, 0.3), 0.06, rng)
		for row in 4:
			var y0 := wf.position.y + row * 8
			for x in range(wf.position.x, wf.end.x):
				img.set_pixel(x, y0, Color(0.15, 0.13, 0.15))
			var off := (row % 2) * 8 + v * 4
			for k in 3:
				var bx := wf.position.x + (off + k * 16) % 32
				for y in range(y0, y0 + 8):
					img.set_pixel(bx, y, Color(0.15, 0.13, 0.15))
		for x in range(wf.position.x, wf.end.x):
			img.set_pixel(x, wf.position.y, Color(0.45, 0.42, 0.45))
			img.set_pixel(x, wf.end.y - 1, Color(0.06, 0.05, 0.06))
	# lava (2 frames)
	for fr in 2:
		var lr := Rect2i(96, 32, 32, 32) if fr == 0 else Rect2i(96, 32, 32, 32)
		if fr == 1:
			continue
		for x in range(lr.position.x, lr.end.x):
			for y in range(lr.position.y, lr.end.y):
				var t := 0.5 + 0.5 * sin(x * 0.45 + y * 0.3) * cos(y * 0.5 - x * 0.2)
				img.set_pixel(x, y, Color(0.9, 0.25, 0.05).lerp(Color(1.0, 0.75, 0.2), t))
	_save(img, SPR + "tiles/crypt_tiles.png")


# =========================================================================================
# Props
# =========================================================================================


func _gen_props() -> void:
	var p := SPR + "props/"
	var wood := Color(0.42, 0.28, 0.17)
	var wood_d := Color(0.28, 0.18, 0.11)
	# table 40x32
	var t := _img(40, 32)
	_rect(t, Rect2(2, 8, 36, 12), wood)
	_rect(t, Rect2(2, 8, 36, 2), wood.lightened(0.2))
	_rect(t, Rect2(2, 19, 36, 3), wood_d)
	_rect(t, Rect2(4, 22, 3, 9), wood_d)
	_rect(t, Rect2(33, 22, 3, 9), wood_d)
	_outline(t, Color(0.04, 0.03, 0.03))
	_save(t, p + "table.png")
	# chair 20x28
	var c := _img(20, 28)
	_rect(c, Rect2(4, 2, 12, 12), wood_d)
	_rect(c, Rect2(3, 13, 14, 5), wood)
	_rect(c, Rect2(4, 18, 2, 9), wood_d)
	_rect(c, Rect2(14, 18, 2, 9), wood_d)
	_outline(c, Color(0.04, 0.03, 0.03))
	_save(c, p + "chair.png")
	# crate 28x28
	var cr := _img(28, 28)
	_rect(cr, Rect2(2, 4, 24, 22), wood)
	_rect(cr, Rect2(2, 4, 24, 3), wood.lightened(0.15))
	_line(cr, Vector2(3, 6), Vector2(25, 25), 2.0, wood_d)
	_line(cr, Vector2(25, 6), Vector2(3, 25), 2.0, wood_d)
	_outline(cr, Color(0.04, 0.03, 0.03))
	_save(cr, p + "crate.png")
	# barrels 22x30
	for kind in ["barrel", "barrel_explosive"]:
		var b := _img(22, 30)
		var bc := wood if kind == "barrel" else Color(0.55, 0.12, 0.08)
		_ellipse(b, Vector2(11, 17), 9, 12, bc)
		_ellipse(b, Vector2(11, 6), 8, 3.5, bc.lightened(0.2))
		_rect(b, Rect2(2, 11, 18, 2), Color(0.25, 0.25, 0.28))
		_rect(b, Rect2(2, 22, 18, 2), Color(0.25, 0.25, 0.28))
		if kind == "barrel_explosive":
			_circle(b, Vector2(11, 17), 3.0, Color(1.0, 0.85, 0.2))
			_rect(b, Rect2(10, 15, 2, 3), Color(0.1, 0.05, 0.05))
		_outline(b, Color(0.04, 0.03, 0.03))
		_save(b, p + kind + ".png")
	# pillar 28x64
	var pl := _img(28, 64)
	_rect(pl, Rect2(4, 8, 20, 50), Color(0.38, 0.36, 0.4))
	_rect(pl, Rect2(4, 8, 4, 50), Color(0.48, 0.46, 0.5))
	_rect(pl, Rect2(2, 2, 24, 7), Color(0.45, 0.43, 0.47))
	_rect(pl, Rect2(2, 56, 24, 7), Color(0.3, 0.28, 0.32))
	_outline(pl, Color(0.04, 0.03, 0.05))
	_save(pl, p + "pillar.png")
	# chest closed/open 30x26
	for open in [false, true]:
		var ch := _img(30, 26)
		_rect(ch, Rect2(2, 10, 26, 14), wood)
		_rect(ch, Rect2(2, 10, 26, 2), Color(0.75, 0.6, 0.2))
		if open:
			_rect(ch, Rect2(2, 2, 26, 6), wood_d)
			_rect(ch, Rect2(4, 9, 22, 3), Color(1.0, 0.85, 0.3))
		else:
			_rect(ch, Rect2(2, 4, 26, 7), wood.lightened(0.1))
			_rect(ch, Rect2(13, 9, 4, 5), Color(0.85, 0.7, 0.25))
		_outline(ch, Color(0.04, 0.03, 0.03))
		_save(ch, p + ("chest_open.png" if open else "chest.png"))
	# spikes down/up 32x32
	for up in [false, true]:
		var s := _img(32, 32)
		_rect(s, Rect2(2, 2, 28, 28), Color(0.16, 0.15, 0.17))
		for gx in 4:
			for gy in 4:
				var cpos := Vector2(6 + gx * 7, 6 + gy * 7)
				if up:
					_poly(s, PackedVector2Array([cpos + Vector2(-2.5, 2), cpos + Vector2(2.5, 2), cpos + Vector2(0, -5)]), Color(0.75, 0.75, 0.8))
				else:
					_circle(s, cpos, 1.5, Color(0.05, 0.05, 0.06))
		_save(s, p + ("spikes_up.png" if up else "spikes_down.png"))
	# door: closed horizontal (32 wide x 40 tall) per tile; open = thin frame
	var dh := _img(32, 40)
	_rect(dh, Rect2(0, 4, 32, 36), Color(0.36, 0.22, 0.12))
	for k in 4:
		_rect(dh, Rect2(k * 8, 4, 1, 36), Color(0.22, 0.13, 0.07))
	_rect(dh, Rect2(0, 12, 32, 3), Color(0.25, 0.25, 0.28))
	_rect(dh, Rect2(0, 30, 32, 3), Color(0.25, 0.25, 0.28))
	_outline(dh, Color(0.04, 0.03, 0.03))
	_save(dh, p + "door_closed.png")
	var dv := _img(12, 40)
	_rect(dv, Rect2(2, 0, 8, 40), Color(0.36, 0.22, 0.12))
	_rect(dv, Rect2(2, 0, 2, 40), Color(0.45, 0.3, 0.18))
	_outline(dv, Color(0.04, 0.03, 0.03))
	_save(dv, p + "door_open.png")
	# debris 32x32
	var db := _img(32, 32)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 9:
		_rect(db, Rect2(rng.randi_range(4, 24), rng.randi_range(10, 26), rng.randi_range(2, 5), rng.randi_range(2, 4)), wood_d.lerp(Color(0.3, 0.3, 0.3), rng.randf()))
	_save(db, p + "debris.png")
	# torch (wall) 12x24
	var tr := _img(12, 24)
	_rect(tr, Rect2(5, 10, 2, 12), Color(0.35, 0.22, 0.12))
	_circle(tr, Vector2(6, 7), 4.0, Color(1.0, 0.55, 0.15))
	_circle(tr, Vector2(6, 6), 2.2, Color(1.0, 0.9, 0.5))
	_save(tr, p + "torch.png")
	# portal 64x64, 4 frames
	var po := _img(64 * 4, 64)
	for f in 4:
		var cx := Vector2(32 + f * 64, 34)
		_ellipse(po, cx, 22, 26, Color(0.1, 0.02, 0.18))
		for k in 3:
			_ring(po, cx, 24.0 - k * 6.0 - f * 1.5, 2.0, Color(0.6, 0.3, 1.0, 0.85 - k * 0.2))
		_ring(po, cx, 27.0, 3.0, Color(0.35, 0.33, 0.38))
	_save(po, p + "portal.png")


# =========================================================================================
# Item icons (32x32)
# =========================================================================================


func _gen_item_icons() -> void:
	var p := SPR + "items/"
	var steel := Color(0.78, 0.8, 0.85)
	var wood := Color(0.5, 0.33, 0.2)
	var gold := Color(0.95, 0.78, 0.25)
	var icons := {}
	var i: Image
	i = _img(32, 32); _line(i, Vector2(6, 26), Vector2(24, 8), 3.0, steel); _line(i, Vector2(8, 18), Vector2(14, 24), 2.0, gold); _line(i, Vector2(4, 28), Vector2(8, 24), 2.0, wood); icons["sword"] = i
	i = _img(32, 32); _line(i, Vector2(5, 27), Vector2(27, 5), 4.0, steel); _line(i, Vector2(7, 19), Vector2(13, 25), 3.0, gold); _line(i, Vector2(3, 29), Vector2(7, 25), 2.0, wood); icons["greatsword"] = i
	i = _img(32, 32); _line(i, Vector2(8, 28), Vector2(22, 6), 2.0, wood); _circle(i, Vector2(21, 9), 6.0, steel); _circle(i, Vector2(25, 13), 4.0, Color(0, 0, 0, 0)); icons["axe"] = i
	i = _img(32, 32); _line(i, Vector2(6, 29), Vector2(22, 5), 2.5, wood); _ellipse(i, Vector2(22, 9), 8.0, 6.0, steel); icons["greataxe"] = i
	i = _img(32, 32); _line(i, Vector2(8, 28), Vector2(20, 10), 2.0, wood); _circle(i, Vector2(21, 9), 5.0, steel); icons["mace"] = i
	i = _img(32, 32); _line(i, Vector2(8, 29), Vector2(20, 8), 2.0, wood); _rect(i, Rect2(12, 3, 16, 9), steel); icons["warhammer"] = i
	i = _img(32, 32); _rect(i, Rect2(7, 5, 18, 22), Color(0.45, 0.3, 0.18)); _rect(i, Rect2(7, 5, 18, 3), steel); _rect(i, Rect2(15, 9, 2, 14), steel); icons["shield"] = i
	i = _img(32, 32); _line(i, Vector2(10, 4), Vector2(20, 16), 2.0, wood); _line(i, Vector2(20, 16), Vector2(10, 28), 2.0, wood); _line(i, Vector2(10, 4), Vector2(10, 28), 1.0, Color(0.9, 0.9, 0.85)); icons["bow"] = i
	i = _img(32, 32); _line(i, Vector2(6, 22), Vector2(26, 10), 3.0, wood); _line(i, Vector2(14, 6), Vector2(22, 24), 2.0, steel); icons["crossbow"] = i
	i = _img(32, 32); _line(i, Vector2(8, 6), Vector2(16, 20), 1.0, Color(0.7, 0.6, 0.4)); _line(i, Vector2(24, 6), Vector2(16, 20), 1.0, Color(0.7, 0.6, 0.4)); _circle(i, Vector2(16, 22), 4.0, Color(0.6, 0.6, 0.6)); icons["sling"] = i
	i = _img(32, 32); _line(i, Vector2(8, 26), Vector2(22, 10), 2.0, Color(0.55, 0.4, 0.6)); _circle(i, Vector2(23, 8), 3.0, Color(0.6, 0.9, 1.0)); icons["wand"] = i
	i = _img(32, 32); _line(i, Vector2(6, 29), Vector2(24, 7), 2.5, wood); _circle(i, Vector2(25, 6), 4.0, Color(0.5, 0.8, 1.0)); icons["staff"] = i
	i = _img(32, 32); _circle(i, Vector2(16, 16), 7.0, Color(0.6, 0.3, 0.9)); _circle(i, Vector2(14, 14), 3.0, Color(0.9, 0.7, 1.0)); _ring(i, Vector2(16, 16), 9.0, 2.0, gold); icons["trinket"] = i
	i = _img(32, 32); _ellipse(i, Vector2(16, 16), 10.0, 9.0, steel); _rect(i, Rect2(6, 17, 20, 3), steel.darkened(0.3)); _rect(i, Rect2(15, 14, 2, 10), Color(0.1, 0.1, 0.1)); icons["helm"] = i
	i = _img(32, 32); _rect(i, Rect2(8, 6, 16, 20), steel); _rect(i, Rect2(4, 6, 6, 8), steel.darkened(0.2)); _rect(i, Rect2(22, 6, 6, 8), steel.darkened(0.2)); _rect(i, Rect2(8, 22, 16, 3), steel.darkened(0.35)); icons["chest"] = i
	i = _img(32, 32); _rect(i, Rect2(8, 5, 16, 6), steel.darkened(0.2)); _rect(i, Rect2(8, 10, 7, 18), steel); _rect(i, Rect2(17, 10, 7, 18), steel); icons["legs"] = i
	i = _img(32, 32); _rect(i, Rect2(6, 8, 7, 16), wood); _rect(i, Rect2(6, 20, 11, 6), wood); _rect(i, Rect2(18, 8, 7, 16), wood.darkened(0.2)); _rect(i, Rect2(18, 20, 11, 6), wood.darkened(0.2)); icons["boots"] = i
	i = _img(32, 32); _rect(i, Rect2(8, 10, 10, 14), wood); _rect(i, Rect2(8, 6, 3, 6), wood); _rect(i, Rect2(12, 5, 3, 6), wood); _rect(i, Rect2(16, 6, 3, 6), wood); _rect(i, Rect2(18, 14, 5, 4), wood); icons["gloves"] = i
	i = _img(32, 32); _ring(i, Vector2(16, 17), 8.0, 3.0, gold); _circle(i, Vector2(16, 9), 3.0, Color(0.3, 0.8, 1.0)); icons["ring"] = i
	i = _img(32, 32); _ring(i, Vector2(16, 12), 9.0, 1.5, gold); _circle(i, Vector2(16, 22), 4.0, Color(0.9, 0.2, 0.3)); icons["necklace"] = i
	for pot in [["potion_health", Color(0.85, 0.1, 0.15)], ["potion_mana", Color(0.15, 0.35, 0.95)], ["potion_haste", Color(0.95, 0.8, 0.2)]]:
		i = _img(32, 32)
		_circle(i, Vector2(16, 20), 8.0, Color(0.8, 0.85, 0.9, 0.6))
		_circle(i, Vector2(16, 21), 6.5, pot[1])
		_rect(i, Rect2(13, 6, 6, 7), Color(0.8, 0.85, 0.9, 0.6))
		_rect(i, Rect2(12, 4, 8, 3), Color(0.5, 0.35, 0.2))
		_circle(i, Vector2(13, 18), 1.5, Color(1, 1, 1, 0.7))
		icons[pot[0]] = i
	i = _img(32, 32); _ellipse(i, Vector2(16, 18), 11.0, 7.0, Color(0.75, 0.5, 0.25)); _ellipse(i, Vector2(16, 15), 9.0, 4.0, Color(0.9, 0.7, 0.4)); icons["food"] = i
	i = _img(32, 32); _rect(i, Rect2(7, 9, 18, 18), Color(0.45, 0.3, 0.15)); _rect(i, Rect2(7, 9, 18, 5), Color(0.55, 0.38, 0.2)); _ring(i, Vector2(16, 9), 5.0, 2.0, Color(0.35, 0.22, 0.1)); _rect(i, Rect2(14, 15, 4, 3), gold); icons["backpack"] = i
	for k in icons:
		_outline(icons[k], Color(0.03, 0.02, 0.03))
		_save(icons[k], p + k + ".png")


# =========================================================================================
# Projectiles (16x16, pointing east) and FX
# =========================================================================================


func _gen_projectiles() -> void:
	var p := SPR + "projectiles/"
	var defs := {
		"arrow": func(i: Image): _line(i, Vector2(1, 8), Vector2(13, 8), 1.0, Color(0.7, 0.55, 0.35)); _poly(i, PackedVector2Array([Vector2(12, 5), Vector2(16, 8), Vector2(12, 11)]), Color(0.85, 0.85, 0.9)); _line(i, Vector2(1, 6), Vector2(3, 8), 1.0, Color(0.9, 0.9, 0.9)); _line(i, Vector2(1, 10), Vector2(3, 8), 1.0, Color(0.9, 0.9, 0.9)),
		"bolt": func(i: Image): _line(i, Vector2(3, 8), Vector2(13, 8), 2.0, Color(0.5, 0.4, 0.3)); _poly(i, PackedVector2Array([Vector2(12, 5), Vector2(16, 8), Vector2(12, 11)]), Color(0.7, 0.7, 0.75)),
		"stone": func(i: Image): _circle(i, Vector2(8, 8), 3.5, Color(0.55, 0.52, 0.5)); _circle(i, Vector2(7, 7), 1.2, Color(0.75, 0.72, 0.7)),
		"magic": func(i: Image): _circle(i, Vector2(9, 8), 4.5, Color(0.5, 0.6, 1.0, 0.6)); _circle(i, Vector2(9, 8), 2.5, Color(0.9, 0.95, 1.0)),
		"fire": func(i: Image): _circle(i, Vector2(9, 8), 5.5, Color(1.0, 0.4, 0.05, 0.75)); _circle(i, Vector2(10, 8), 3.5, Color(1.0, 0.8, 0.3)); _circle(i, Vector2(4, 8), 2.0, Color(1, 0.3, 0.05, 0.5)),
		"frost": func(i: Image): _poly(i, PackedVector2Array([Vector2(2, 8), Vector2(9, 3), Vector2(16, 8), Vector2(9, 13)]), Color(0.55, 0.85, 1.0)); _line(i, Vector2(5, 8), Vector2(13, 8), 1.0, Color(1, 1, 1)),
		"lightning": func(i: Image): _line(i, Vector2(0, 8), Vector2(5, 5), 2.0, Color(0.8, 0.9, 1.0)); _line(i, Vector2(5, 5), Vector2(9, 11), 2.0, Color(0.8, 0.9, 1.0)); _line(i, Vector2(9, 11), Vector2(16, 7), 2.0, Color(1, 1, 1)),
		"holy": func(i: Image): _circle(i, Vector2(9, 8), 5.0, Color(1.0, 0.9, 0.4, 0.6)); _circle(i, Vector2(9, 8), 3.0, Color(1, 1, 0.85)),
		"shadow": func(i: Image): _circle(i, Vector2(9, 8), 5.0, Color(0.5, 0.1, 0.6, 0.7)); _circle(i, Vector2(9, 8), 2.5, Color(0.9, 0.4, 1.0)),
		"poison": func(i: Image): _line(i, Vector2(1, 8), Vector2(13, 8), 1.0, Color(0.5, 0.6, 0.3)); _poly(i, PackedVector2Array([Vector2(12, 5), Vector2(16, 8), Vector2(12, 11)]), Color(0.4, 0.95, 0.3)); _circle(i, Vector2(5, 8), 2.0, Color(0.4, 1.0, 0.3, 0.5)),
		"bone": func(i: Image): _line(i, Vector2(3, 8), Vector2(13, 8), 2.0, Color(0.9, 0.88, 0.8)); _circle(i, Vector2(3, 7), 1.5, Color(0.9, 0.88, 0.8)); _circle(i, Vector2(13, 9), 1.5, Color(0.9, 0.88, 0.8)),
	}
	for k in defs:
		var i := _img(16, 16)
		defs[k].call(i)
		_save(i, p + k + ".png")


func _gen_fx() -> void:
	var p := SPR + "fx/"
	# Soft radial light (also used as particle/glow texture).
	var light := _img(256, 256)
	for x in 256:
		for y in 256:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(128, 128)) / 128.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			light.set_pixel(x, y, Color(1, 1, 1, a * a))
	_save(light, p + "light_soft.png")
	var spark := _img(8, 8)
	_circle(spark, Vector2(4, 4), 3.0, Color(1, 1, 1, 0.6))
	_circle(spark, Vector2(4, 4), 1.5, Color(1, 1, 1, 1))
	_save(spark, p + "spark.png")
	var px := _img(2, 2)
	px.fill(Color.WHITE)
	_save(px, p + "pixel.png")
	var sh := _img(32, 12)
	_ellipse(sh, Vector2(16, 6), 14, 5, Color(0, 0, 0, 0.45))
	_save(sh, p + "shadow.png")
	var ring := _img(128, 128)
	_ring(ring, Vector2(64, 64), 63.0, 3.0, Color(1, 1, 1, 0.9))
	for x in 128:
		for y in 128:
			var d2 := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(64, 64))
			if d2 < 60.0:
				_px(ring, x, y, Color(1, 1, 1, 0.12 + 0.12 * d2 / 60.0))
	_save(ring, p + "aoe_ring.png")
	# Slash arc 64x64, 3 frames
	var sl := _img(64 * 3, 64)
	for f in 3:
		var c := Vector2(32 + f * 64, 32)
		for k in 40:
			var a := lerpf(-1.1, 1.1, k / 39.0)
			if k / 39.0 > (f + 1) / 3.0:
				continue
			var pos := c + Vector2(cos(a), sin(a)) * 22.0
			_circle(sl, pos, 3.0 - absf(a) * 1.5, Color(1, 1, 1, 0.9 - f * 0.25))
	_save(sl, p + "slash.png")
	# Explosion 64x64, 5 frames
	var ex := _img(64 * 5, 64)
	for f in 5:
		var c2 := Vector2(32 + f * 64, 32)
		var r := 8.0 + f * 6.0
		_circle(ex, c2, r, Color(1.0, 0.5, 0.1, 0.9 - f * 0.17))
		_circle(ex, c2, r * 0.6, Color(1.0, 0.85, 0.4, 0.9 - f * 0.2))
	_save(ex, p + "explosion.png")


# =========================================================================================
# Skill icons (32x32): background color + simple glyph
# =========================================================================================


func _gen_skill_icons() -> void:
	var p := SPR + "icons/"
	var glyphs := {
		"slash": [Color(0.55, 0.15, 0.1), func(i: Image): _line(i, Vector2(6, 26), Vector2(26, 6), 3.0, Color.WHITE)],
		"bash": [Color(0.4, 0.3, 0.2), func(i: Image): _rect(i, Rect2(9, 7, 14, 18), Color(0.85, 0.85, 0.9)); _circle(i, Vector2(16, 16), 3.0, Color(1, 0.8, 0.3))],
		"shout": [Color(0.6, 0.2, 0.1), func(i: Image): _ring(i, Vector2(16, 16), 6.0, 2.0, Color.WHITE); _ring(i, Vector2(16, 16), 11.0, 2.0, Color(1, 1, 1, 0.7))],
		"charge": [Color(0.5, 0.2, 0.15), func(i: Image): _poly(i, PackedVector2Array([Vector2(5, 10), Vector2(18, 10), Vector2(18, 5), Vector2(28, 16), Vector2(18, 27), Vector2(18, 22), Vector2(5, 22)]), Color.WHITE)],
		"whirl": [Color(0.5, 0.15, 0.15), func(i: Image): _ring(i, Vector2(16, 16), 10.0, 3.0, Color.WHITE); _line(i, Vector2(16, 6), Vector2(24, 4), 2.0, Color.WHITE)],
		"guard": [Color(0.3, 0.3, 0.4), func(i: Image): _poly(i, PackedVector2Array([Vector2(8, 6), Vector2(24, 6), Vector2(24, 16), Vector2(16, 27), Vector2(8, 16)]), Color(0.85, 0.85, 0.95))],
		"arrow": [Color(0.2, 0.4, 0.2), func(i: Image): _line(i, Vector2(5, 27), Vector2(25, 7), 2.0, Color.WHITE); _poly(i, PackedVector2Array([Vector2(20, 6), Vector2(27, 5), Vector2(26, 12)]), Color.WHITE)],
		"multishot": [Color(0.2, 0.4, 0.25), func(i: Image): for k in 3: _line(i, Vector2(5, 16), Vector2(27, 6 + k * 10), 2.0, Color.WHITE)],
		"trap": [Color(0.35, 0.3, 0.15), func(i: Image): _ring(i, Vector2(16, 18), 9.0, 2.0, Color(0.85, 0.85, 0.9)); for k in 5: _line(i, Vector2(9 + k * 3.5, 12), Vector2(9 + k * 3.5, 20), 1.0, Color.WHITE)],
		"poison": [Color(0.15, 0.35, 0.1), func(i: Image): _circle(i, Vector2(16, 19), 7.0, Color(0.45, 1.0, 0.3)); _poly(i, PackedVector2Array([Vector2(16, 5), Vector2(21, 15), Vector2(11, 15)]), Color(0.45, 1.0, 0.3))],
		"dash": [Color(0.25, 0.3, 0.4), func(i: Image): for k in 3: _line(i, Vector2(5 + k * 4, 10 + k * 6), Vector2(27, 10 + k * 6), 2.0, Color(1, 1, 1, 0.5 + k * 0.25))],
		"fire": [Color(0.6, 0.2, 0.05), func(i: Image): _circle(i, Vector2(16, 19), 7.0, Color(1.0, 0.55, 0.1)); _poly(i, PackedVector2Array([Vector2(16, 3), Vector2(23, 17), Vector2(9, 17)]), Color(1.0, 0.75, 0.2))],
		"frost": [Color(0.15, 0.3, 0.55), func(i: Image): for k in 3: _line(i, Vector2(16, 16) + Vector2.from_angle(k * PI / 3.0) * 11.0, Vector2(16, 16) - Vector2.from_angle(k * PI / 3.0) * 11.0, 2.0, Color(0.8, 0.95, 1.0))],
		"lightning": [Color(0.2, 0.2, 0.5), func(i: Image): _line(i, Vector2(20, 3), Vector2(12, 16), 2.5, Color(1, 1, 0.7)); _line(i, Vector2(12, 16), Vector2(20, 16), 2.5, Color(1, 1, 0.7)); _line(i, Vector2(20, 16), Vector2(11, 29), 2.5, Color(1, 1, 0.7))],
		"blink": [Color(0.3, 0.15, 0.5), func(i: Image): _ring(i, Vector2(10, 16), 5.0, 1.5, Color(1, 1, 1, 0.5)); _circle(i, Vector2(22, 16), 5.0, Color(0.85, 0.7, 1.0))],
		"meteor": [Color(0.45, 0.1, 0.05), func(i: Image): _circle(i, Vector2(20, 20), 7.0, Color(1.0, 0.45, 0.1)); _line(i, Vector2(4, 4), Vector2(16, 16), 4.0, Color(1.0, 0.8, 0.3, 0.6))],
		"holy": [Color(0.55, 0.45, 0.15), func(i: Image): _rect(i, Rect2(14, 5, 4, 22), Color(1, 0.95, 0.7)); _rect(i, Rect2(8, 11, 16, 4), Color(1, 0.95, 0.7))],
		"heal": [Color(0.15, 0.45, 0.2), func(i: Image): _rect(i, Rect2(13, 6, 6, 20), Color(0.6, 1.0, 0.6)); _rect(i, Rect2(6, 13, 20, 6), Color(0.6, 1.0, 0.6))],
		"bubble": [Color(0.4, 0.4, 0.15), func(i: Image): _ring(i, Vector2(16, 16), 11.0, 3.0, Color(1.0, 0.95, 0.6)); _circle(i, Vector2(16, 16), 4.0, Color(1, 1, 1, 0.6))],
		"consecrate": [Color(0.45, 0.35, 0.1), func(i: Image): _ellipse(i, Vector2(16, 20), 12.0, 6.0, Color(1.0, 0.85, 0.3, 0.8)); _rect(i, Rect2(15, 5, 2, 14), Color.WHITE)],
		"renew": [Color(0.15, 0.4, 0.35), func(i: Image): _ring(i, Vector2(16, 16), 9.0, 2.5, Color(0.6, 1.0, 0.85)); _poly(i, PackedVector2Array([Vector2(23, 4), Vector2(28, 10), Vector2(21, 11)]), Color(0.6, 1.0, 0.85))],
		"attack": [Color(0.3, 0.3, 0.3), func(i: Image): _line(i, Vector2(8, 24), Vector2(24, 8), 3.0, Color.WHITE)],
	}
	for k in glyphs:
		var i := _img(32, 32)
		_rect(i, Rect2(0, 0, 32, 32), glyphs[k][0])
		_rect(i, Rect2(0, 0, 32, 2), glyphs[k][0].lightened(0.3))
		_rect(i, Rect2(0, 30, 32, 2), glyphs[k][0].darkened(0.4))
		glyphs[k][1].call(i)
		_save(i, p + k + ".png")


# =========================================================================================
# Audio: silent music loops + tiny synthesized SFX (16-bit mono WAV)
# =========================================================================================


func _wav(samples: PackedFloat32Array, path: String, rate: int = 22050) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for k in samples.size():
		data.encode_s16(k * 2, int(clampf(samples[k], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.save_to_wav(path)


func _synth(dur: float, f0: float, f1: float, wave: String, noise: float, decay: float, vol: float = 0.5) -> PackedFloat32Array:
	var rate := 22050
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 13.0 + f1)
	for k in n:
		var t := float(k) / n
		var f := lerpf(f0, f1, t)
		ph += f / rate
		var v := 0.0
		match wave:
			"sine": v = sin(ph * TAU)
			"square": v = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw": v = fmod(ph, 1.0) * 2.0 - 1.0
			"tri": v = absf(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0
		v = lerpf(v, rng.randf_range(-1.0, 1.0), noise)
		var env := pow(1.0 - t, decay) * minf(1.0, t * 200.0)
		out[k] = v * env * vol
	return out


func _gen_audio() -> void:
	var sfx := {
		"swing": [0.15, 900.0, 300.0, "saw", 0.7, 2.0],
		"hit": [0.12, 220.0, 90.0, "square", 0.5, 2.5],
		"crit": [0.2, 600.0, 150.0, "square", 0.4, 1.5],
		"shoot": [0.12, 700.0, 1200.0, "tri", 0.3, 2.0],
		"cast": [0.35, 300.0, 900.0, "sine", 0.1, 1.2],
		"fire": [0.4, 160.0, 60.0, "saw", 0.8, 1.2],
		"frost": [0.35, 1400.0, 700.0, "tri", 0.4, 1.5],
		"lightning": [0.3, 2000.0, 300.0, "square", 0.7, 1.8],
		"explosion": [0.6, 120.0, 30.0, "square", 0.85, 1.5],
		"heal": [0.45, 500.0, 1000.0, "sine", 0.0, 1.0],
		"buff": [0.35, 400.0, 800.0, "tri", 0.0, 1.0],
		"pickup": [0.12, 900.0, 1500.0, "square", 0.0, 1.5],
		"equip": [0.15, 300.0, 200.0, "square", 0.3, 2.0],
		"door": [0.3, 90.0, 70.0, "saw", 0.6, 1.0],
		"dash": [0.18, 400.0, 1000.0, "saw", 0.9, 2.0],
		"level_up": [0.7, 400.0, 1200.0, "square", 0.0, 0.8],
		"ui_move": [0.04, 1200.0, 1200.0, "square", 0.0, 3.0],
		"ui_accept": [0.08, 800.0, 1300.0, "square", 0.0, 2.0],
		"ui_press": [0.03, 520.0, 380.0, "tri", 0.15, 3.0],
		"ui_back": [0.07, 900.0, 520.0, "tri", 0.0, 2.0],
		"ui_open": [0.12, 480.0, 960.0, "sine", 0.0, 1.5],
		"ui_error": [0.14, 140.0, 95.0, "sine", 0.2, 2.0],
		"ui_drop": [0.08, 320.0, 190.0, "tri", 0.25, 2.0],
		"death": [0.8, 300.0, 50.0, "saw", 0.4, 1.0],
		"revive": [0.6, 300.0, 900.0, "sine", 0.1, 0.8],
		"spikes": [0.15, 1500.0, 500.0, "saw", 0.8, 3.0],
		"break": [0.3, 200.0, 80.0, "square", 0.9, 1.8],
		"enemy_hit": [0.1, 300.0, 120.0, "square", 0.6, 2.5],
		"roar": [0.9, 110.0, 70.0, "saw", 0.5, 0.8],
		"portal": [1.0, 200.0, 600.0, "sine", 0.2, 0.6],
		"potion": [0.25, 500.0, 300.0, "sine", 0.3, 1.0],
	}
	var only_missing := OS.get_cmdline_user_args().has("--only=audio")
	for k in sfx:
		if only_missing and FileAccess.file_exists(SFX + k + ".wav"):
			continue
		var d: Array = sfx[k]
		_wav(_synth(d[0], d[1], d[2], d[3], d[4], d[5]), SFX + k + ".wav")
	# Silent music placeholders (4 s loops) — replace with Suno tracks via data/assets.json.
	var silence := PackedFloat32Array()
	silence.resize(22050 * 4)
	for k in ["menu", "crypt", "boss_bone_lord"]:
		if only_missing and FileAccess.file_exists(MUS + k + ".wav"):
			continue
		_wav(silence, MUS + k + ".wav")
