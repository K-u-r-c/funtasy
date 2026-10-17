extends SceneTree
## Contact sheets of the hero art (#18 audit): for each gender and look, every animation x 8
## directions x frame composed exactly as CharacterSprite draws it (body with the worn pieces'
## hide masks, gear on top in layer order). Hole pixels (masked body pixels no piece draws over)
## are painted magenta, empty layer frames get a red frame.
##   godot --headless --path . -s tools/contact_sheet.gd -- <out_dir> [scale] [--monsters]
## Writes <out_dir>/<gender>_<look>.png (or monster_<id>.png); rows = animation x direction
## (E, SE, S, SW, W, NW, N, NE), columns = frames. Also writes <out_dir>/report.txt: empty frames,
## feet that jump between consecutive frames of an animation (> 2 px for standing clips) and
## frames whose drawn width / height jumps (pieces popping), per sheet.

const LOOKS := {
	"bare": [],
	"plate": ["head_helm", "chest_armor", "legs_armor", "boots_armor", "gloves_armor"],
	"cloth": ["head_hood", "chest_robe"],
	"warrior": ["head_helm", "chest_armor", "legs_armor", "boots_armor", "gloves_armor", "weapon_sword", "offhand_shield"],
	"warrior_2h": ["head_helm", "chest_armor", "legs_armor", "boots_armor", "gloves_armor", "weapon_greatsword"],
	"sword_shield": ["weapon_sword", "offhand_shield"],
	"greatsword": ["weapon_greatsword"],
	"axe_trinket": ["weapon_axe", "offhand_trinket"],
	"greataxe": ["weapon_greataxe"],
	"mace": ["weapon_mace"],
	"warhammer": ["weapon_warhammer"],
	"bow": ["weapon_bow"],
	"crossbow": ["weapon_crossbow"],
	"sling": ["weapon_sling"],
	"wand": ["weapon_wand"],
	"staff": ["weapon_staff"],
}
const SLOT_OF := {"head": "head", "chest": "chest", "legs": "legs", "boots": "boots", "gloves": "gloves", "weapon": "weapon", "offhand": "offhand"}

var _imgs: Dictionary = {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var scale := int(args[1]) if args.size() > 1 else 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/assets.json"))
	var report: Array = []
	if args.has("--monsters"):
		for id in assets.monsters:
			_monster_sheet(out_dir, str(id), assets.monsters[id], assets.characters.anims, scale, report)
		FileAccess.open(out_dir.path_join("report_monsters.txt"), FileAccess.WRITE).store_string("\n".join(report) + "\n")
		quit()
		return
	for g in assets.characters.genders:
		var be: Dictionary = assets.characters.layers[assets.characters.genders[g].body]
		for a in assets.characters.anims:
			var img := _img(str(be.path) + a + ".png")
			if img:
				_motion_report("hero %s %s" % [g, a], img, int(assets.characters.frame_size), a, report)
	FileAccess.open(out_dir.path_join("report_heroes.txt"), FileAccess.WRITE).store_string("\n".join(report) + "\n")
	var chars: Dictionary = assets.characters
	var cell := int(chars.frame_size)
	var order: Array = chars.layer_order
	for g in chars.genders:
		var gdef: Dictionary = chars.genders[g]
		var body_entry: Dictionary = chars.layers[gdef.body]
		for look in LOOKS:
			var layers: Array = []  # [slot, entry]
			for app in LOOKS[look]:
				var key: String = str(gdef.prefix) + str(app)
				if chars.layers.has(key):
					layers.append([str(app).split("_")[0], chars.layers[key]])
			layers.sort_custom(func(a, b): return order.find(a[0]) < order.find(b[0]))
			var anims: Array = chars.anims.keys()
			var max_f := 0
			for a in anims:
				max_f = maxi(max_f, int(body_entry.get("anims", {}).get(a, chars.anims[a]).frames))
			var sheet := Image.create(max_f * cell, anims.size() * 8 * cell, false, Image.FORMAT_RGBA8)
			sheet.fill(Color("1b1d24"))
			var row := 0
			var holes := 0
			for a in anims:
				var body := _img(str(body_entry.path) + a + ".png")
				var gear: Array = []
				var backs: Array = []
				for l in layers:
					gear.append([l[0], _img(str(l[1].path) + a + ".png"), _img(str(l[1].path) + "hide/" + a + ".png") if l[1].get("hide", false) else null])
					if l[1].get("back", false):
						backs.append(_img(str(l[1].path) + "back/" + a + ".png"))
				for d in 8:
					# Checker band per animation to read the rows.
					var band := Color("22252e") if anims.find(a) % 2 == 0 else Color("1b1d24")
					sheet.fill_rect(Rect2i(0, row * cell, max_f * cell, cell), band)
					if body:
						for f in body.get_width() / cell:
							var r := Rect2i(f * cell, d * cell, cell, cell)
							var dst := Vector2i(f * cell, row * cell)
							# Held items' back parts first, under the body.
							for bk in backs:
								if bk:
									var bsrc: Image = (bk as Image).get_region(r)
									sheet.blend_rect(bsrc, Rect2i(Vector2i.ZERO, bsrc.get_size()), dst)
							for gl in gear:
								if gl[1]:
									var used := (gl[1] as Image).get_region(r).get_used_rect()
									if used.size == Vector2i.ZERO:
										sheet.fill_rect(Rect2i(dst, Vector2i(cell, 1)), Color.RED)
										sheet.fill_rect(Rect2i(dst, Vector2i(1, cell)), Color.RED)
							for y in cell:
								for x in cell:
									var p := Vector2i(x, y) + r.position
									var c := body.get_pixelv(p)
									if c.a < 0.5:
										continue
									var hidden := false
									var drawn := false
									for gl in gear:
										if gl[2] and (gl[2] as Image).get_pixelv(p).a > 0.5:
											hidden = true
										if gl[1] and (gl[1] as Image).get_pixelv(p).a > 0.5:
											drawn = true
									if hidden and not drawn:
										sheet.set_pixelv(dst + Vector2i(x, y), Color.MAGENTA)
										holes += 1
									elif not hidden:
										sheet.set_pixelv(dst + Vector2i(x, y), c)
							for gl in gear:
								if gl[1] == null:
									continue
								var src: Image = (gl[1] as Image).get_region(r)
								sheet.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), dst)
					row += 1
			if scale > 1:
				sheet.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
			var path := out_dir.path_join("%s_%s.png" % [g, look])
			sheet.save_png(path)
			print("contact_sheet: %s (%d hole px)" % [path, holes])
	quit()


## Empty frames, feet jumps and popping silhouettes of one sheet (rows = 8 directions).
func _motion_report(what: String, img: Image, cell: int, anim: String, report: Array) -> void:
	var standing := anim in ["idle", "walk", "attack", "cast", "hit", "dash"]
	for d in img.get_height() / cell:
		var prev := Rect2i()
		for f in img.get_width() / cell:
			var u := img.get_region(Rect2i(f * cell, d * cell, cell, cell)).get_used_rect()
			if u.size == Vector2i.ZERO:
				report.append("%s dir %d frame %d: empty" % [what, d, f])
				continue
			if f > 0 and prev.size != Vector2i.ZERO:
				if standing and absi(u.end.y - prev.end.y) > 2:
					report.append("%s dir %d frame %d: feet jump %+d px" % [what, d, f, u.end.y - prev.end.y])
				if standing and anim != "attack" and anim != "cast" and absi(u.size.y - prev.size.y) > 4:
					report.append("%s dir %d frame %d: height pops %+d px" % [what, d, f, u.size.y - prev.size.y])
			prev = u


func _monster_sheet(out_dir: String, id: String, entry: Dictionary, anims: Dictionary, scale: int, report: Array) -> void:
	var cell := int(entry.get("frame_size", 64))
	var rows: Array = []
	var max_f := 0
	for a in anims:
		var img := _img(str(entry.get("path", "")) + a + ".png")
		if img == null:
			report.append("monster %s: no %s sheet" % [id, a])
			continue
		_motion_report("monster %s %s" % [id, a], img, cell, a, report)
		rows.append(img)
		max_f = maxi(max_f, img.get_width() / cell)
	if rows.is_empty():
		return
	var sheet := Image.create(max_f * cell, rows.size() * 8 * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1b1d24"))
	var y := 0
	for i in rows.size():
		var img: Image = rows[i]
		sheet.fill_rect(Rect2i(0, y, max_f * cell, img.get_height()), Color("22252e") if i % 2 == 0 else Color("1b1d24"))
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height()
	if scale > 1:
		sheet.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out_dir.path_join("monster_%s.png" % id))


func _img(path: String) -> Image:
	if _imgs.has(path):
		return _imgs[path]
	var img: Image = null
	if ResourceLoader.exists(path):
		img = (load(path) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
	_imgs[path] = img
	return img
