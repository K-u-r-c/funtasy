extends SceneTree
## Turns downloaded PixelLab output into the sheets the game loads (data/assets.json layout).
##   godot --headless --path . -s tools/pixellab_import.gd -- <manifest.json>
## The manifest is a list of operations; source paths are absolute (downloads live outside
## the project), destinations are res:// paths under assets/sprites/pixellab/.
##   {"op": "trim", "src": ..., "dst": ..., "pad": 1}            crop to the used pixels
##   {"op": "copy", "src": ..., "dst": ...}
##   {"op": "grid", "srcs": [[...row0...], [...row1...]], "cell": [w, h], "dst": ...}
##       paste images into a grid (tile sheets, frame strips); each centered in its cell,
##       bottom aligned when "bottom": true
##   {"op": "sheet", "rows": [[frames of E], [SE], [S], [SW], [W], [NW], [N], [NE]],
##       "frames": n, "cell": size, "dst": ...}
##       character sheet: rows = 8 directions, every row resampled to n frames, frames pasted
##       at the same position so the animation keeps its alignment
##   {"op": "mirror_rows", "src": sheet, "cell": size, "rows": {"4": 0, "5": 7, "3": 1}, "dst": ...}
##       character sheet: rebuild rows as horizontal mirrors of other rows (W from E, NW from
##       NE, SW from SE) for directions drawn once
##   {"op": "align_feet", "src": sheet, "ref": sheet, "cell": size, "max": 6}
##       shift each direction row so its median feet row matches the reference sheet's
##   {"op": "strip_glow", "src": sheet}
##       remove bright yellow / white spell glow (the fireball template's flame) in place
##   {"op": "replace_color", "src": sheet, "colors": ["#rrggbb", ...]}
##       stray pixels of these colours take the most common colour of their opaque neighbours
##   {"op": "ghost", "src": res://...idle.png, "dst": ...}   pale translucent copy (ghost anim)
##   {"op": "tint", "src": ..., "dst": ..., "color": "#rrggbb", "amount": 0.4}
##   {"op": "face", "src": ..., "dst": ..., "dark": 0.75, "flip": false}
##       wall face tile: darkened, 2 px lit ledge on top, 1 px shadow at the bottom
##   {"op": "crop", "src": ..., "dst": ..., "rect": [x, y, w, h]}
##   {"op": "strip", "src": sheet, "cell": [w, h], "count": n, "dst": ...}
##       grid spritesheet (row-major, e.g. a vfx_workbench export) -> one horizontal strip


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <manifest.json>")
		quit(1)
		return
	var ops: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var done := 0
	for op in ops:
		var ok: bool = call("_op_" + str(op.op), op)
		if ok:
			done += 1
		else:
			push_error("pixellab_import: failed %s" % JSON.stringify(op))
	print("pixellab_import: %d / %d operations" % [done, ops.size()])
	quit(0 if done == ops.size() else 1)


func _load(path: String) -> Image:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var img := Image.load_from_file(p)
	if img and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, dst: String) -> bool:
	var p := ProjectSettings.globalize_path(dst)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	return img.save_png(p) == OK


func _op_copy(op: Dictionary) -> bool:
	var img := _load(op.src)
	return img != null and _save(img, op.dst)


func _op_trim(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var r := img.get_used_rect()
	var pad := int(op.get("pad", 1))
	var out := Image.create(r.size.x + pad * 2, r.size.y + pad, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, r, Vector2i(pad, pad))
	return _save(out, op.dst)


func _op_grid(op: Dictionary) -> bool:
	var cell := Vector2i(int(op.cell[0]), int(op.cell[1]))
	var rows: Array = op.srcs
	var cols := 0
	for row in rows:
		cols = maxi(cols, row.size())
	var out := Image.create(cell.x * cols, cell.y * rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].size():
			var src := str(rows[y][x])
			if src.is_empty():
				continue
			var img := _load(src)
			if img == null:
				return false
			var r := img.get_used_rect() if bool(op.get("trim", false)) else Rect2i(Vector2i.ZERO, img.get_size())
			var px := (cell.x - r.size.x) / 2
			var py := cell.y - r.size.y if bool(op.get("bottom", false)) else (cell.y - r.size.y) / 2
			out.blit_rect(img, r, Vector2i(x * cell.x + px, y * cell.y + py))
	return _save(out, op.dst)


func _op_sheet(op: Dictionary) -> bool:
	var n := int(op.frames)
	var cell := int(op.cell)
	var rows: Array = op.rows
	var out := Image.create(cell * n, cell * 8, false, Image.FORMAT_RGBA8)
	for d in 8:
		var src: Array = rows[d]
		if src.is_empty():
			continue
		for f in n:
			var i := mini(int(roundf(float(f) * src.size() / n)), src.size() - 1)
			var img := _load(str(src[i]))
			if img == null:
				return false
			var off := Vector2i((cell - img.get_width()) / 2, (cell - img.get_height()) / 2)
			out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(f * cell, d * cell) + off)
	return _save(out, op.dst)


func _op_mirror_rows(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var cell := int(op.cell)
	var n := img.get_width() / cell
	for dst_row in op.rows:
		var src_row := int(op.rows[dst_row])
		for f in n:
			var fr := img.get_region(Rect2i(f * cell, src_row * cell, cell, cell))
			fr.flip_x()
			img.blit_rect(fr, Rect2i(0, 0, cell, cell), Vector2i(f * cell, int(dst_row) * cell))
	return _save(img, op.get("dst", op.src))


func _op_align_feet(op: Dictionary) -> bool:
	var img := _load(op.src)
	var ref := _load(op.ref)
	if img == null or ref == null:
		return false
	var cell := int(op.cell)
	for d in 8:
		var a := _feet_row(img, d, cell)
		var b := _feet_row(ref, d, cell)
		var dy := b - a
		if a < 0 or b < 0 or dy == 0 or absi(dy) > int(op.get("max", 6)):
			continue
		var row := img.get_region(Rect2i(0, d * cell, img.get_width(), cell))
		img.fill_rect(Rect2i(0, d * cell, img.get_width(), cell), Color(0, 0, 0, 0))
		for f in img.get_width() / cell:
			var fr := row.get_region(Rect2i(f * cell, 0, cell, cell))
			img.blit_rect(fr, Rect2i(0, maxi(0, -dy), cell, cell - absi(dy)), Vector2i(f * cell, d * cell + maxi(0, dy)))
	return _save(img, op.get("dst", op.src))


func _feet_row(img: Image, d: int, cell: int) -> int:
	var rows: Array = []
	for f in img.get_width() / cell:
		var r := img.get_region(Rect2i(f * cell, d * cell, cell, cell)).get_used_rect()
		if r.size.y > 0:
			rows.append(r.end.y)
	if rows.is_empty():
		return -1
	rows.sort()
	return rows[rows.size() / 2]


func _op_strip_glow(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var w := img.get_width()
	var h := img.get_height()
	var glow := {}
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			# Flame: saturated yellow-orange that is brighter than any skin tone, or a near-white core.
			if (c.h >= 0.085 and c.h <= 0.2 and c.s > 0.4 and c.v > 0.75) or (c.s < 0.2 and c.v > 0.97):
				glow[Vector2i(x, y)] = true
	# Its fringe: pixels mostly surrounded by glow.
	var fringe: Array = []
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if glow.has(p) or img.get_pixel(x, y).a < 0.5:
				continue
			var n := 0
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				if glow.has(p + o):
					n += 1
			if n >= 4:
				fringe.append(p)
	for p in glow:
		img.set_pixelv(p, Color(0, 0, 0, 0))
	for p in fringe:
		img.set_pixelv(p, Color(0, 0, 0, 0))
	_drop_specks(img, int(op.get("cell", 64)), int(op.get("specks", 12)))
	return _save(img, op.get("dst", op.src))


func _op_replace_color(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var bad := {}
	for c in op.colors:
		bad[Color.from_string(str(c), Color.BLACK).to_html(false)] = true
	var fixed := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 0.5 or not bad.has(img.get_pixel(x, y).to_html(false)):
				continue
			var votes := {}
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
					continue
				var n := img.get_pixelv(q)
				if n.a >= 0.5 and not bad.has(n.to_html(false)):
					votes[n] = int(votes.get(n, 0)) + 1
			if votes.is_empty():
				continue
			var best: Color = votes.keys()[0]
			for k in votes:
				if votes[k] > votes[best]:
					best = k
			img.set_pixel(x, y, best)
			fixed += 1
	print("pixellab_import: replace_color fixed %d pixels in %s" % [fixed, op.src])
	return _save(img, op.get("dst", op.src))


## Removes small pixel islands (left-over glow sparks) that aren't part of a figure, per cell.
func _drop_specks(img: Image, cell: int, max_size: int) -> void:
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			var start := Vector2i(x, y)
			if seen.has(start) or img.get_pixelv(start).a < 0.5:
				continue
			var comp: Array = [start]
			seen[start] = true
			var i := 0
			while i < comp.size():
				var q: Vector2i = comp[i]
				i += 1
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var n: Vector2i = q + o
					# Islands never cross a cell border.
					if n.x < 0 or n.y < 0 or n.x >= img.get_width() or n.y >= img.get_height() or n.x / cell != q.x / cell or n.y / cell != q.y / cell:
						continue
					if not seen.has(n) and img.get_pixelv(n).a >= 0.5:
						seen[n] = true
						comp.append(n)
			if comp.size() <= max_size:
				for q in comp:
					img.set_pixelv(q, Color(0, 0, 0, 0))


func _op_ghost(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := c.get_luminance()
			img.set_pixel(x, y, Color(0.55 + l * 0.4, 0.75 + l * 0.25, 1.0, c.a * 0.7))
	return _save(img, op.dst)


func _op_tint(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var t := Color.from_string(str(op.color), Color.WHITE)
	var k := float(op.get("amount", 0.4))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				var m := c.lerp(Color(t.r * c.get_luminance() * 2.0, t.g * c.get_luminance() * 2.0, t.b * c.get_luminance() * 2.0, c.a), k)
				img.set_pixel(x, y, m)
	return _save(img, op.dst)


func _op_face(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	if bool(op.get("flip", false)):
		img.flip_x()
	var k := float(op.get("dark", 0.75))
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			c = Color(c.r * k, c.g * k, c.b * k * 1.05, c.a)
			if y < 2:
				c = c.lightened(0.35 if y == 0 else 0.18)
			elif y == h - 1:
				c = c.darkened(0.5)
			img.set_pixel(x, y, c)
	return _save(img, op.dst)


func _op_crop(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var r := Rect2i(int(op.rect[0]), int(op.rect[1]), int(op.rect[2]), int(op.rect[3]))
	return _save(img.get_region(r), op.dst)


func _op_strip(op: Dictionary) -> bool:
	var img := _load(op.src)
	if img == null:
		return false
	var cell := Vector2i(int(op.cell[0]), int(op.cell[1]))
	var cols := img.get_width() / cell.x
	var n := int(op.count)
	var out := Image.create(cell.x * n, cell.y, false, Image.FORMAT_RGBA8)
	for i in n:
		var src := Rect2i(Vector2i(i % cols, i / cols) * cell, cell)
		out.blit_rect(img, src, Vector2i(i * cell.x, 0))
	return _save(out, op.dst)
