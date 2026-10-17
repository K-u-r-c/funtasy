extends SceneTree
## Cuts worn-gear layers out of "outfit" sheets: the same animation frames as the naked base body
## redrawn wearing a set of gear (PixelLab transfer_outfit on the base body's own frames, so both
## line up pixel for pixel). Writes, per layer, a sheet with only that slot's gear and a hide mask
## (the body pixels the piece covers; CharacterSprite hides them so no skin shows under gear).
##   godot --headless --path . -s tools/gear_cut.gd -- <config.json> [debug_dir | --refill]
## (--refill only runs the last step on the finished sheets: see _refill_all.)
## Body regions (head, torso, arms, hands, legs, feet) come from tools/body_regions.gd. An outfit pixel belongs to the region of the
## base pixel under it (or the nearest one). A layer keeps the outfit pixels of its "regions"
## that differ from the naked body (or lie in a "hide" region, which the piece replaces whole).
## Config: {cell, body_dir, out_root, anims: [...], palette: {class: [hex...]},
##   outfits: {name: {dir, layers: {layer: {regions: [...], hide: [...]}}}},
##   derive: {anim: {from, pick?: [...], tail?: n}}   (derived sheets, also written for the body)
##   patches: [{anim, dir, frame, from: [anim, frame]}]   (replace a bad template frame)
##   align: {anim: reference anim}   (shift each direction so its feet match the reference's)
## Patches and alignment change the body, every layer and every hide mask the same way.
## Rows are directions E, SE, S, SW, W, NW, N, NE.

const DIRS := 8
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BodyRegions := preload("res://tools/body_regions.gd")

var cfg: Dictionary
var cell := 64
var regions_tool: BodyRegions
var debug_dir := ""
var report: Dictionary = {}  ## layer -> max holes filled in a frame


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	debug_dir = args[1] if args.size() > 1 else ""
	cell = int(cfg.get("cell", 64))
	regions_tool = BodyRegions.new(cfg)
	if debug_dir == "--refill":
		_refill_all()
		quit()
		return
	for anim in cfg.anims:
		_cut_anim(str(anim))
	for patch in cfg.get("patches", []):
		_patch(patch)
	for anim in cfg.get("align", {}):
		_align(str(anim), str(cfg.align[anim]))
	for anim in cfg.get("derive", {}):
		_derive(str(anim), cfg.derive[anim])
	_refill_all()
	for layer in report:
		print("gear_cut: %s max %d body pixels hidden but not drawn over per frame" % [layer, report[layer]])
	quit()


func _cut_anim(anim: String) -> void:
	var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
	if body == null:
		push_error("gear_cut: no body sheet for " + anim)
		return
	var frames := body.get_width() / cell
	var dbg := Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8) if debug_dir != "" else null
	var outs := {}  ## layer -> [sheet, mask]
	for oname in cfg.outfits:
		var outfit: Dictionary = cfg.outfits[oname]
		var osheet := _load(str(outfit.dir).path_join(anim + ".png"))
		if osheet == null:
			push_error("gear_cut: no %s outfit sheet for %s" % [oname, anim])
			continue
		for layer in outfit.layers:
			outs[layer] = [Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8),
				Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8), oname]
	for d in DIRS:
		for f in frames:
			var at := Vector2i(f * cell, d * cell)
			var base := body.get_region(Rect2i(at, Vector2i(cell, cell)))
			var regions := regions_tool.segment(base)
			var base_cls := regions_tool.class_map(base)
			if dbg:
				for p in regions:
					dbg.set_pixelv(at + p, Color.from_string(BodyRegions.COLORS[regions[p]], Color.WHITE))
			var nearest := regions_tool.nearest_map(regions)
			for oname in cfg.outfits:
				var outfit: Dictionary = cfg.outfits[oname]
				var osheet := _load(str(outfit.dir).path_join(anim + ".png"))
				if osheet == null:
					continue
				var ofr := osheet.get_region(Rect2i(at, Vector2i(cell, cell)))
				for layer in outfit.layers:
					var spec: Dictionary = outfit.layers[layer]
					var res := cut_layer(base, ofr, regions, nearest, base_cls, spec)
					outs[layer][0].blit_rect(res[0], Rect2i(0, 0, cell, cell), at)
					outs[layer][1].blit_rect(res[1], Rect2i(0, 0, cell, cell), at)
					report[layer] = maxi(int(report.get(layer, 0)), int(res[2]))
	for layer in outs:
		_save(outs[layer][0], str(cfg.out_root).path_join(layer).path_join(anim + ".png"))
		_save(outs[layer][1], str(cfg.out_root).path_join(layer).path_join("hide").path_join(anim + ".png"))
	if dbg:
		dbg.save_png(debug_dir.path_join("regions_" + anim + ".png"))
	print("gear_cut: %s (%d frames x %d dirs, %d layers)" % [anim, frames, DIRS, outs.size()])


## Returns [layer image, hide mask, filled hole count] for one frame.
func cut_layer(base: Image, ofr: Image, regions: Dictionary, nearest: Dictionary, base_cls: Dictionary, spec: Dictionary) -> Array:
	var want: Array = spec.regions
	var hide: Array = spec.get("hide", want)
	var thr := float(spec.get("same_color", 0.004))
	var out := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var mask := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var mine := {}
	for y in cell:
		for x in cell:
			var c := ofr.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var p := Vector2i(x, y)
			var r: String = regions.get(p, nearest.get(p, ""))
			if not want.has(r):
				continue
			var b := base.get_pixel(x, y)
			var same := b.a >= 0.5 and BodyRegions.dist2(b, c) <= thr
			# The naked body showing through (e.g. legs below a robe's hem); an outfit pixel over
			# underwear or hair is always gear, even when its colour happens to match.
			if same and not hide.has(r) and not base_cls.get(p, "") in ["shirt", "shorts", "hair"]:
				continue
			out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			mine[p] = true
	# Hide mask: every body pixel of the replaced regions.
	var holes: Array = []
	for p in regions:
		var r2: String = regions[p]
		# Also hidden: underwear / hair the piece's other regions leave uncovered (a robe's hem
		# lifting off the shorts in a lying pose).
		var bare: bool = want.has(r2) and not mine.has(p) and base_cls.get(p, "") in ["shirt", "shorts", "hair"]
		if hide.has(r2) or bare:
			mask.set_pixelv(p, Color.WHITE)
			if not mine.has(p):
				holes.append(p)
	# Hair the piece doesn't cover (a ponytail under a helmet) is simply hidden; narrow gaps next to
	# the piece (up to "fill" px) are filled so the silhouette has no holes.
	if int(spec.get("fill", 3)) > 0 and not mine.is_empty():
		var pending := holes.filter(func(h): return base_cls.get(h, "") != "hair")
		var guard := 0
		while not pending.is_empty() and guard < int(spec.get("fill", 3)):
			guard += 1
			var next: Array = []
			var placed: Array = []
			for p in pending:
				var src := Vector2i(-1, -1)
				for o in N4:
					if mine.has(p + o):
						src = p + o
						break
				if src.x < 0:
					next.append(p)
				else:
					placed.append([p, out.get_pixelv(src)])
			for e in placed:
				out.set_pixelv(e[0], e[1])
				mine[e[0]] = true
			pending = next
	return [out, mask, holes.size() if not mine.is_empty() else 0]


const DIR_NAMES := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


## Every sheet of an animation that shares the body's layout: body, layers, hide masks.
func _sheet_paths(anim: String) -> Array:
	var out: Array = [str(cfg.body_dir).path_join(anim + ".png")]
	for oname in cfg.outfits:
		for layer in cfg.outfits[oname].layers:
			out.append(str(cfg.out_root).path_join(layer).path_join(anim + ".png"))
			out.append(str(cfg.out_root).path_join(layer).path_join("hide").path_join(anim + ".png"))
	return out


func _patch(patch: Dictionary) -> void:
	var d := DIR_NAMES.find(str(patch.dir))
	var f := int(patch.frame)
	var src_anim := str(patch.from[0])
	var src_f := int(patch.from[1])
	for path in _sheet_paths(str(patch.anim)):
		var img := _load(path)
		var src := img if src_anim == str(patch.anim) else _load(path.get_base_dir().path_join(src_anim + ".png"))
		if img == null or src == null:
			continue
		var fr := src.get_region(Rect2i(src_f * cell, d * cell, cell, cell))
		img.fill_rect(Rect2i(f * cell, d * cell, cell, cell), Color(0, 0, 0, 0))
		img.blit_rect(fr, Rect2i(0, 0, cell, cell), Vector2i(f * cell, d * cell))
		_save(img, path)
	print("gear_cut: patched %s %s frame %d" % [patch.anim, patch.dir, f])


## Median lowest opaque row of a direction's frames (the feet), -1 when empty.
func _feet(img: Image, d: int) -> int:
	var rows: Array = []
	for f in img.get_width() / cell:
		var r := img.get_region(Rect2i(f * cell, d * cell, cell, cell)).get_used_rect()
		if r.size.y > 0:
			rows.append(r.end.y)
	if rows.is_empty():
		return -1
	rows.sort()
	return rows[rows.size() / 2]


func _align(anim: String, ref: String) -> void:
	var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
	var ref_img := _load(str(cfg.body_dir).path_join(ref + ".png"))
	if body == null or ref_img == null:
		return
	var shifts := {}
	for d in DIRS:
		var a := _feet(body, d)
		var b := _feet(ref_img, d)
		if a >= 0 and b >= 0 and a != b and absi(b - a) <= 4:
			shifts[d] = b - a
	if shifts.is_empty():
		return
	for path in _sheet_paths(anim):
		var img := _load(path)
		if img == null:
			continue
		for d in shifts:
			var row := img.get_region(Rect2i(0, d * cell, img.get_width(), cell))
			img.fill_rect(Rect2i(0, d * cell, img.get_width(), cell), Color(0, 0, 0, 0))
			for f in img.get_width() / cell:
				# Each frame moves inside its own cell (nothing spills into the next row).
				var fr := row.get_region(Rect2i(f * cell, 0, cell, cell))
				var dy := int(shifts[d])
				img.blit_rect(fr, Rect2i(0, maxi(0, -dy), cell, cell - absi(dy)), Vector2i(f * cell, d * cell + maxi(0, dy)))
		_save(img, path)
	print("gear_cut: aligned %s feet to %s %s" % [anim, ref, shifts])


## Last step (#15), on the finished, aligned sheets: a body pixel a piece's mask hides but the piece
## doesn't draw would show as a hole or a trimmed outline, so the piece draws it in the colour of
## its nearest own pixel. Hidden hair (and the outline around it) stays hidden unless it is an
## interior hole. Idempotent.
func _refill_all() -> void:
	var anims: Array = cfg.anims.duplicate()
	for a in cfg.get("derive", {}):
		anims.append(str(a))
	for anim in anims:
		var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
		if body == null:
			continue
		var cls_of := {}
		for oname in cfg.outfits:
			for layer in cfg.outfits[oname].layers:
				var lpath := str(cfg.out_root).path_join(layer).path_join(anim + ".png")
				var sheet := _load(lpath)
				var mask := _load(str(cfg.out_root).path_join(layer).path_join("hide").path_join(anim + ".png"))
				if sheet == null or mask == null:
					continue
				var filled := 0
				for d in DIRS:
					for f in body.get_width() / cell:
						var o := Vector2i(f * cell, d * cell)
						if not cls_of.has(o):
							cls_of[o] = regions_tool.class_map(body.get_region(Rect2i(o, Vector2i(cell, cell))))
						var cls: Dictionary = cls_of[o]
						var mine: Array = []
						var holes: Array = []
						for y in cell:
							for x in cell:
								var p := o + Vector2i(x, y)
								if sheet.get_pixelv(p).a >= 0.5:
									mine.append(p)
								elif mask.get_pixelv(p).a > 0.5 and body.get_pixelv(p).a >= 0.5:
									holes.append(p)
						if mine.is_empty():
							continue
						for h in holes:
							var q: Vector2i = h - o
							# Interior: every neighbour stays drawn (gear, or body that isn't hidden hair).
							var inner := N4.all(func(n): return sheet.get_pixelv(h + n).a >= 0.5 or (body.get_pixelv(h + n).a >= 0.5 \
									and not (mask.get_pixelv(h + n).a > 0.5 and BodyRegions.is_hairish(cls, q + n))))
							if BodyRegions.is_hairish(cls, q) and not inner:
								continue
							var best: Vector2i = mine[0]
							for m in mine:
								if (m - h).length_squared() < (best - h).length_squared():
									best = m
							sheet.set_pixelv(h, sheet.get_pixelv(best))
							filled += 1
				if filled > 0:
					_save(sheet, lpath)
					print("gear_cut: refilled %s %s (%d px)" % [layer, anim, filled])


## Derived animations from frames of cut ones, for the body, every layer and its hide mask.
func _derive(anim: String, spec: Dictionary) -> void:
	var dirs: Array = [str(cfg.body_dir)]
	for oname in cfg.outfits:
		for layer in cfg.outfits[oname].layers:
			dirs.append(str(cfg.out_root).path_join(layer))
			dirs.append(str(cfg.out_root).path_join(layer).path_join("hide"))
	# "breathe": the second frame lifts the upper half of the body 1 px (a lying hero breathing);
	# the rows come from the body sheet so every layer and mask moves the same pixels.
	var lift_rows := {}
	if spec.get("breathe", false):
		var bsrc := _load(str(cfg.body_dir).path_join(str(spec.from) + ".png"))
		var bf := mini(int(spec.get("pick", [0])[0]), bsrc.get_width() / cell - 1)
		for d in DIRS:
			var u := bsrc.get_region(Rect2i(bf * cell, d * cell, cell, cell)).get_used_rect()
			lift_rows[d] = [u.position.y, u.position.y + u.size.y / 2]
	for dir in dirs:
		var src := _load(dir.path_join(str(spec.from) + ".png"))
		if src == null:
			continue
		var n := src.get_width() / cell
		var pick: Array = spec.get("pick", range(n))
		if spec.has("tail"):
			pick = range(maxi(0, n - int(spec.tail)), n)
		var out := Image.create(cell * pick.size(), cell * DIRS, false, Image.FORMAT_RGBA8)
		for i in pick.size():
			var f := mini(int(pick[i]), n - 1)
			out.blit_rect(src, Rect2i(f * cell, 0, cell, cell * DIRS), Vector2i(i * cell, 0))
		if not lift_rows.is_empty() and pick.size() > 1:
			for d in DIRS:
				var r: Array = lift_rows[d]
				var top := maxi(int(r[0]), 1)
				var band := out.get_region(Rect2i(cell, d * cell + top, cell, int(r[1]) - top))
				out.fill_rect(Rect2i(cell, d * cell + top, cell, int(r[1]) - top), Color(0, 0, 0, 0))
				out.blit_rect(band, Rect2i(Vector2i.ZERO, band.get_size()), Vector2i(cell, d * cell + top - 1))
		_save(out, dir.path_join(anim + ".png"))
	print("gear_cut: derived %s from %s" % [anim, spec.from])


func _load(path: String) -> Image:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, path: String) -> void:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
