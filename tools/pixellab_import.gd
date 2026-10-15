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
