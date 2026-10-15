extends SceneTree
## Bakes equipment layer sheets that line up frame by frame with the base body sheets
## (CharacterSprite draws body + one layer per slot from the same frame grid).
##   godot --headless --path . -s tools/bake_gear.gd -- <config.json> [layer ...]
## Three kinds of layers, all derived from the body's own pixels in every frame:
##   recolor  body pixels of some colour classes (shirt, trousers, skin...) inside height
##            bands are repainted with a colour ramp by brightness (armour, robes, boots).
##            Greyish ramps leave room for the per-item tint (CharacterSprite modulate).
##   attach   an 8-direction sprite (PixelLab object, e.g. a helmet) placed on the head:
##            centred on the head pixels, its top on the top of the body.
##   held     an item picture held in the hand: the hand is the skin pixel of the hand band
##            farthest in the direction's "hand" vector; the picture is rotated per direction
##            and swung through the attack frames.
## Rows are directions E, SE, S, SW, W, NW, N, NE; anims whose name is in "skip" get empty
## frames for attach/held layers (lying poses).

const DIRS := 8

var cfg: Dictionary
var classes: Array = []  ## [[Color, class name], ...]
var cell := 92


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	cell = int(cfg.cell)
	for cls in cfg.palette:
		for hexc in cfg.palette[cls]:
			classes.append([Color.from_string(hexc, Color.BLACK), cls])
	var only: Array = args.slice(1)
	for layer in cfg.layers:
		if not only.is_empty() and not only.has(layer):
			continue
		var spec: Dictionary = cfg.layers[layer]
		var n := 0
		for anim in cfg.anims:
			var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
			if body == null:
				continue
			var out := Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)
			var frames := body.get_width() / cell
			for d in DIRS:
				for f in frames:
					var src := body.get_region(Rect2i(f * cell, d * cell, cell, cell))
					var layer_img := _bake(spec, src, anim, d, f, frames)
					if layer_img:
						out.blit_rect(layer_img, Rect2i(0, 0, cell, cell), Vector2i(f * cell, d * cell))
			var dst := str(cfg.out_root).path_join(layer).path_join(anim + ".png")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst).get_base_dir())
			out.save_png(ProjectSettings.globalize_path(dst))
			n += 1
		print("bake_gear: %s (%d sheets)" % [layer, n])
	quit()


func _load(path: String) -> Image:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _class_of(c: Color) -> String:
	var best := ""
	var bd := 99.0
	for e in classes:
		var k: Color = e[0]
		var dd := (k.r - c.r) * (k.r - c.r) + (k.g - c.g) * (k.g - c.g) + (k.b - c.b) * (k.b - c.b)
		if dd < bd:
			bd = dd
			best = e[1]
	return best


func _bake(spec: Dictionary, src: Image, anim: String, d: int, f: int, frames: int) -> Image:
	var used := src.get_used_rect()
	if used.size.y < 4 or cfg.get("bare", []).has(anim):
		return null
	match str(spec.type):
		"recolor":
			return _recolor(spec, src, used)
		"attach":
			if cfg.get("skip", []).has(anim):
				return null
			return _attach(spec, src, used, d)
		"held":
			if cfg.get("skip", []).has(anim):
				return null
			return _held(spec, src, used, anim, d, f, frames)
	return null


## Height of the standing body: lying/crouching frames use the idle height so bands stay put.
func _band(used: Rect2i, a: float, b: float) -> Vector2i:
	var h := float(cfg.get("body_height", used.size.y))
	var bottom := float(used.end.y)
	return Vector2i(int(bottom - h * (1.0 - a)), int(bottom - h * (1.0 - b)))


func _recolor(spec: Dictionary, src: Image, used: Rect2i) -> Image:
	var out := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var ramp: Array = spec.ramp.map(func(h): return Color.from_string(h, Color.WHITE))
	var rules: Array = spec.rules  ## [{"class": "shirt", "band": [0, 1]}, ...]
	var outline := Color.from_string(str(spec.get("outline", "#0b0909")), Color.BLACK)
	var hit := {}
	# Rows that contain a pixel of each class (rules can require e.g. a shirt pixel on the
	# same row, which tells arms from the face when the body leans).
	var rows_with := {}
	var face_marks: Array = []  ## hair / eye pixels: skin close to them is the face
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var c0 := src.get_pixel(x, y)
			if c0.a >= 0.5:
				var k := _class_of(c0)
				rows_with[k + ":" + str(y)] = true
				if k == "hair" or k == "eyes":
					face_marks.append(Vector2i(x, y))
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var cls := _class_of(c)
			for r in rules:
				if r["class"] != cls:
					continue
				var band := _band(used, float(r.band[0]), float(r.band[1]))
				if y < band.x or y >= band.y:
					continue
				if r.has("same_row") and not rows_with.has(str(r.same_row) + ":" + str(y)):
					continue
				if r.has("not_near_face") and _near(face_marks, Vector2i(x, y), int(r.not_near_face)):
					continue
				var l := clampf(c.get_luminance() * float(spec.get("gain", 1.0)) + float(spec.get("bias", 0.0)), 0.0, 0.999)
				out.set_pixel(x, y, ramp[int(l * ramp.size())])
				hit[Vector2i(x, y)] = true
				break
	# Close the painted area with an outline where it borders transparent pixels, so the
	# armour reads as a separate piece instead of a recoloured patch.
	if bool(spec.get("edge", true)):
		for p in hit:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + o
				if q.x < 0 or q.y < 0 or q.x >= cell or q.y >= cell:
					continue
				if not hit.has(q) and src.get_pixel(q.x, q.y).a < 0.5:
					out.set_pixel(p.x, p.y, ramp[0].darkened(0.3))
	return out


func _attach(spec: Dictionary, src: Image, used: Rect2i, d: int) -> Image:
	var spr := _load(str(spec.sprites[d]))
	if spr == null:
		return null
	var gain := float(spec.get("gain", 1.0))
	if gain != 1.0:
		# Dark source art is lifted so the per-item tint (a multiply) can still colour it.
		spr = spr.duplicate()
		for y in spr.get_height():
			for x in spr.get_width():
				var c := spr.get_pixel(x, y)
				if c.a > 0.0:
					spr.set_pixel(x, y, Color(minf(c.r * gain, 1.0), minf(c.g * gain, 1.0), minf(c.b * gain, 1.0), c.a))
	var su := spr.get_used_rect()
	# Head centre: mean x of the body pixels in the head band.
	var band := _band(used, 0.0, float(spec.get("head_band", 0.22)))
	var sx := 0.0
	var cnt := 0
	for y in range(band.x, band.y):
		for x in range(used.position.x, used.end.x):
			if src.get_pixel(x, y).a >= 0.5:
				sx += x
				cnt += 1
	if cnt == 0:
		return null
	var cx := int(roundf(sx / cnt))
	var off: Array = spec.get("offset", [0, 0])
	var out := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var pos := Vector2i(cx - su.size.x / 2 + int(off[0]), used.position.y + int(off[1]))
	out.blend_rect(spr, su, pos)
	return out


func _held(spec: Dictionary, src: Image, used: Rect2i, anim: String, d: int, f: int, frames: int) -> Image:
	var pic := _load(str(spec.picture))
	if pic == null:
		return null
	var hand_vec: Array = cfg.hand_vectors[spec.get("hand", "main")][d]
	var v := Vector2(float(hand_vec[0]), float(hand_vec[1]))
	var band := _band(used, float(cfg.hand_band[0]), float(cfg.hand_band[1]))
	var center := Vector2(used.get_center())
	var best := Vector2i(-1, -1)
	var bs := -INF
	for y in range(band.x, band.y):
		for x in range(used.position.x, used.end.x):
			var c := src.get_pixel(x, y)
			if c.a < 0.5 or _class_of(c) != "skin":
				continue
			var s := (Vector2(x, y) - center).dot(v)
			if s > bs:
				bs = s
				best = Vector2i(x, y)
	if best.x < 0:
		return null
	# Angle of the picture per direction (degrees, 0 = as drawn), plus the attack swing.
	var angles: Array = spec.get("angles", cfg.get("held_angles", [0, 0, 0, 0, 0, 0, 0, 0]))
	var ang := float(angles[d])
	var mirror: bool = cfg.get("held_mirror", [])[d] if not cfg.get("held_mirror", []).is_empty() else false
	if anim in ["attack", "cast"] and frames > 1:
		var swing: Array = spec.get("swing", [-50.0, 70.0])
		var t := float(f) / float(frames - 1)
		var s2 := lerpf(float(swing[0]), float(swing[1]), sin(t * PI * 0.5))
		ang += -s2 if mirror else s2
	var img := pic.duplicate()
	if mirror:
		img.flip_x()
	var grip: Array = spec.get("grip", [0.25, 0.75])
	var g := Vector2(float(grip[0]) * img.get_width(), float(grip[1]) * img.get_height())
	if mirror:
		g.x = img.get_width() - g.x
	var sc := float(spec.get("scale", 1.0))
	var out := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	_draw_rotated(out, img, g, Vector2(best), deg_to_rad(ang), sc)
	return out


## Nearest-neighbour rotate+scale of `img` around its point `pivot`, placed at `at`.
func _draw_rotated(dst: Image, img: Image, pivot: Vector2, at: Vector2, ang: float, sc: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var r := ceili(Vector2(w, h).length() * sc)
	var ca := cos(-ang)
	var sa := sin(-ang)
	for y in range(int(at.y) - r, int(at.y) + r):
		for x in range(int(at.x) - r, int(at.x) + r):
			if x < 0 or y < 0 or x >= dst.get_width() or y >= dst.get_height():
				continue
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - at) / sc
			var q := Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) + pivot
			var ix := int(floorf(q.x))
			var iy := int(floorf(q.y))
			if ix < 0 or iy < 0 or ix >= w or iy >= h:
				continue
			var c := img.get_pixel(ix, iy)
			if c.a >= 0.5:
				dst.set_pixel(x, y, c)


func _near(points: Array, p: Vector2i, radius: int) -> bool:
	for q: Vector2i in points:
		if absi(q.x - p.x) <= radius and absi(q.y - p.y) <= radius:
			return true
	return false
