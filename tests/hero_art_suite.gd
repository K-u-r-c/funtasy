class_name HeroArtSuite
extends RefCounted
## #15: the layered hero never loses pixels or keeps a stale tint.
## - The lobby preview switched between classes and genders many times composes exactly like a
##   freshly built preview with the same look (CharacterSprite.compose, every layer on the body's
##   frame).
## - A piece put on mid-animation starts on the body's frame (the hide masks match it).
## - Audit: every layer x animation x direction x frame that is drawn has pixels, and no hide mask
##   removes body pixels that its own piece doesn't draw over.

var da: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	await switch_test()
	await equip_midanim_test()
	audit()
	legendary_looks()


## Pixels by which a hero's sprite differs from a fresh CharacterSprite built from its replicated
## gender and appearance (both held on the same frame); -1 if it can't be compared.
static func vs_fresh(hero: Node, tree: SceneTree) -> int:
	var cs: CharacterSprite = hero.sprite
	var fresh := CharacterSprite.new()
	tree.root.add_child(fresh)
	fresh.set_layer("body", CharacterSprite.body_key(hero.gender))
	for layer in hero.appearance:
		var a: Array = hero.appearance[layer]
		fresh.set_look_layer(layer, a, hero.gender)
	fresh.play(cs.anim, Vector2.RIGHT.rotated(cs.dir_index * PI / 4.0), true)
	var body: AnimatedSprite2D = cs.get_node_or_null("body")
	if body == null:
		fresh.free()
		return -1
	var f := body.frame
	var saved: Color = cs.modulate
	cs.modulate = Color.WHITE
	_hold(cs, f)
	_hold(fresh, f)
	var n := diff(cs.compose(), fresh.compose())
	cs.modulate = saved
	for c in cs.get_children():
		if c is AnimatedSprite2D and c.sprite_frames and c.sprite_frames.has_animation(c.animation):
			c.play()
	fresh.free()
	return n


func _looks() -> Array:
	var out: Array = []
	for cid in ["warrior", "ranger", "mage", "priest"]:
		for g in CharacterSprite.genders():
			for gear in [true, false]:
				out.append([cid, g, gear])
	return out


## Every visible layer plays the body's animation on the body's frame.
static func in_sync(cs: CharacterSprite) -> String:
	var body: AnimatedSprite2D = cs.get_node_or_null("body")
	if body == null:
		return "no body"
	for c in cs.get_children():
		var spr := c as AnimatedSprite2D
		if spr == null or not spr.visible or spr == body:
			continue
		if spr.animation != body.animation or spr.frame != body.frame:
			return "%s on %s:%d, body on %s:%d" % [spr.name, spr.animation, spr.frame, body.animation, body.frame]
	return ""


## Number of differing pixels between two composites.
static func diff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return a.get_width() * a.get_height()
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.a - q.a) > 0.01 or (p.a > 0.0 and (absf(p.r - q.r) > 0.01 or absf(p.g - q.g) > 0.01 or absf(p.b - q.b) > 0.01)):
				n += 1
	return n


func _preview(cid: String, g: String, gear: bool, dir: int) -> HeroPreview:
	var hp := HeroPreview.new()
	hp.size = Vector2(230, 170)
	hp.dir_index = dir
	hp.set_look(g, preload("res://scripts/ui/lobby.gd").class_look(cid) if gear else {})
	da.get_tree().root.add_child(hp)
	return hp


## Puts every layer of `cs` on `frame` of its current animation (so two sprites compare equal
## whatever time they were built at).
static func _hold(cs: CharacterSprite, frame: int) -> void:
	for c in cs.get_children():
		var spr := c as AnimatedSprite2D
		if spr and spr.sprite_frames and spr.sprite_frames.has_animation(spr.animation):
			spr.pause()
			spr.frame = mini(frame, spr.sprite_frames.get_frame_count(spr.animation) - 1)


func switch_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1515
	var looks := _looks()
	var hp := _preview("warrior", "male", true, 2)
	await da.get_tree().process_frame
	var worst := 0
	var worst_at := ""
	var unsync := ""
	var n := 40
	for i in n:
		var lk: Array = looks[rng.randi_range(0, looks.size() - 1)]
		hp.set_look(lk[1], preload("res://scripts/ui/lobby.gd").class_look(lk[0]) if lk[2] else {})
		if rng.randf() < 0.4:
			hp.rotate_by(rng.randi_range(-3, 3))
		# Switch again within the same frame now and then (lobby buttons pressed quickly).
		if rng.randf() < 0.3:
			var lk2: Array = looks[rng.randi_range(0, looks.size() - 1)]
			hp.set_look(lk2[1], preload("res://scripts/ui/lobby.gd").class_look(lk2[0]) if lk2[2] else {})
			lk = lk2
		for k in rng.randi_range(0, 12):
			await da.get_tree().process_frame
		var s := in_sync(hp.sprite)
		if not s.is_empty() and unsync.is_empty():
			unsync = "switch %d (%s): %s" % [i, lk, s]
		var fresh := _preview(lk[0], lk[1], lk[2], hp.dir_index)
		await da.get_tree().process_frame
		var body: AnimatedSprite2D = hp.sprite.get_node("body")
		var f := body.frame
		_hold(hp.sprite, f)
		_hold(fresh.sprite, f)
		var dn := diff(hp.sprite.compose(), fresh.sprite.compose())
		var stale := hp.sprite.get_children().filter(func(c): return not c is AnimatedSprite2D or not c.name in ["body", "head", "chest", "legs", "boots", "gloves", "weapon", "offhand", "weapon_back", "offhand_back"])
		if not stale.is_empty():
			dn += 1000
		if dn > worst:
			worst = dn
			worst_at = "switch %d %s dir %d frame %d" % [i, lk, hp.dir_index, f]
		fresh.queue_free()
		for c in hp.sprite.get_children():
			if c is AnimatedSprite2D and c.sprite_frames and c.sprite_frames.has_animation(c.animation):
				c.play()
	da.check(unsync.is_empty(), "every layer of the switched preview stays on the body's frame (%s)" % unsync)
	da.check(worst == 0, "%d class / gender switches always compose like a fresh preview (worst %d px, %s)" % [n, worst, worst_at])
	hp.queue_free()


func equip_midanim_test() -> void:
	var g := "male"
	var cs := CharacterSprite.new()
	da.get_tree().root.add_child(cs)
	cs.set_layer("body", CharacterSprite.body_key(g))
	cs.play("walk", Vector2.DOWN, true)
	for k in 7:
		await da.get_tree().process_frame
	var body: AnimatedSprite2D = cs.get_node("body")
	body.set_frame_and_progress(2, 0.5)
	cs.set_layer("chest", CharacterSprite.gear_key("chest_armor", g))
	cs.set_layer("legs", CharacterSprite.gear_key("legs_armor", g))
	cs.set_layer("legs", "")
	cs.set_layer("legs", CharacterSprite.gear_key("legs_armor", g))
	var s := in_sync(cs)
	da.check(s.is_empty(), "pieces put on mid-walk start on the body's frame (%s)" % s)
	var named := cs.get_children().map(func(c): return str(c.name))
	da.check(named.count("legs") == 1 and named.size() == 3, "a piece taken off and put back in one frame leaves one node (%s)" % [named])
	cs.queue_free()


## Every drawn layer frame has pixels (a worn piece may be empty only where its hide mask is too,
## i.e. the body part it covers isn't visible, like hands behind a running body). For the worn sets
## the composite has no interior holes (a masked body pixel no piece draws, with all 4 neighbours
## drawn) and trims the body's outline only where hair is hidden under a hood or helmet (the
## "No body under gear" decision).
const SETS := {"plate": ["head_helm", "chest_armor", "legs_armor", "boots_armor", "gloves_armor"], "cloth": ["head_hood", "chest_robe"],
	"leather": ["head_leather", "chest_leather", "legs_leather", "boots_leather", "gloves_leather"],
	"mail": ["head_mail", "chest_mail", "legs_mail", "boots_mail", "gloves_mail"]}


func audit() -> void:
	var chars: Dictionary = GameData.assets.characters
	var empty: Array = []
	var missing: Array = []
	var checked := 0
	for g in CharacterSprite.genders():
		var body_entry := GameData.asset_entry(CharacterSprite.body_key(g))
		var cell := int(body_entry.get("frame_size", chars.frame_size))
		for key in chars.layers:
			var entry: Dictionary = chars.layers[key]
			var is_body := str(key) == str(chars.genders[g].body)
			if not is_body and not str(key).begins_with(str(chars.genders[g].prefix)):
				continue
			for anim in chars.anims:
				var sheet := _img(str(entry.path) + anim + ".png")
				var adef: Dictionary = chars.anims[anim]
				if sheet == null and (adef.has("from") or adef.has("fallback")):
					continue  # derived from another sheet (spin, revive) or drawn as its fallback
				if sheet == null:
					# Gear isn't drawn on ghosts; held items aren't drawn lying down.
					var held := str(key).contains("weapon") or str(key).contains("offhand")
					if is_body or not (anim == "ghost" or (held and anim in ["downed", "death"])):
						missing.append("%s %s" % [key, anim])
					continue
				var mask := _img(str(entry.path) + "hide/" + anim + ".png") if entry.get("hide", false) else null
				var back := _img(str(entry.path) + "back/" + anim + ".png") if entry.get("back", false) else null
				for d in sheet.get_height() / cell:
					for f in sheet.get_width() / cell:
						checked += 1
						var r := Rect2i(f * cell, d * cell, cell, cell)
						if sheet.get_region(r).get_used_rect().size == Vector2i.ZERO and (back == null or back.get_region(r).get_used_rect().size == Vector2i.ZERO):
							if mask == null or mask.get_region(r).get_used_rect().size != Vector2i.ZERO:
								empty.append("%s %s dir %d frame %d" % [key, anim, d, f])
	da.check(missing.is_empty(), "every layer has a sheet for every animation it is drawn in (%s)" % [missing.slice(0, 6)])
	da.check(checked > 0 and empty.is_empty(), "all %d layer frames have pixels where the body part shows (%d empty: %s)" % [checked, empty.size(), empty.slice(0, 6)])
	for g in CharacterSprite.genders():
		for set_name in SETS:
			if not SETS[set_name].any(func(app): return not CharacterSprite.gear_key(app, g).is_empty()):
				continue  # this family isn't drawn for this gender yet (ItemLooks falls back)
			var res := set_holes(g, SETS[set_name])
			da.check(res.interior == 0 and res.trim == 0,
					"%s %s set: no interior holes (%d) and no trimmed body outline except hidden hair (%d px trimmed, %d hair; worst %s)" % [g, set_name, res.interior, res.trim, res.hair, res.at])


## Holes of a worn set over every animation, direction and frame of a gender's body:
## {interior, trim, hair, at}.
func set_holes(g: String, apps: Array) -> Dictionary:
	var chars: Dictionary = GameData.assets.characters
	var body_entry := GameData.asset_entry(CharacterSprite.body_key(g))
	var cell := int(body_entry.get("frame_size", chars.frame_size))
	var cfg_path := "res://tools/hero_%s.json" % g
	var br: RefCounted = load("res://tools/body_regions.gd").new(JSON.parse_string(FileAccess.get_file_as_string(cfg_path)))
	var out := {"interior": 0, "trim": 0, "hair": 0, "at": ""}
	var worst := 0
	for anim in chars.anims:
		if anim == "ghost":
			continue
		var body := _img(str(body_entry.path) + anim + ".png")
		if body == null:
			continue
		var pieces: Array = []
		for app in apps:
			var key := CharacterSprite.gear_key(app, g)
			if key.is_empty():
				continue
			var e := GameData.asset_entry(key)
			pieces.append([_img(str(e.path) + anim + ".png"), _img(str(e.path) + "hide/" + anim + ".png")])
		for d in body.get_height() / cell:
			for f in body.get_width() / cell:
				var o := Vector2i(f * cell, d * cell)
				var shown := {}  # composite opaque
				var cut: Array = []
				for y in cell:
					for x in cell:
						var p := o + Vector2i(x, y)
						var drawn := pieces.any(func(pc): return pc[0] and pc[0].get_pixelv(p).a > 0.5)
						var masked := pieces.any(func(pc): return pc[1] and pc[1].get_pixelv(p).a > 0.5)
						var b := body.get_pixelv(p).a > 0.5
						if drawn or (b and not masked):
							shown[Vector2i(x, y)] = true
						elif b and masked:
							cut.append(Vector2i(x, y))
				if cut.is_empty():
					continue
				var cls: Dictionary = br.class_map(body.get_region(Rect2i(o, Vector2i(cell, cell))))
				var bad := 0
				for q in cut:
					var inner := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)].all(func(n): return shown.has(q + n))
					if inner:
						out.interior += 1
						bad += 1
					elif br.is_hairish(cls, q):
						out.hair += 1
					else:
						out.trim += 1
						bad += 1
				if bad > worst:
					worst = bad
					out.at = "%s dir %d frame %d (%d px)" % [anim, d, f, bad]
	return out


## Every worn legendary gets its own colours from its icon (#20): the looks differ from each
## other. With FUNTASY_REVIEW_DIR set, writes legendary_looks.png there (each legendary worn on
## the male hero, facing south, next to its icon) for a visual review.
func legendary_looks() -> void:
	var rng := RandomNumberGenerator.new()
	var sigs := {}
	var worn := 0
	var missing: Array = []
	var ids: Array = GameData.legendaries.keys()
	var review := OS.get_environment("FUNTASY_REVIEW_DIR")
	var sheet := Image.create(12 * 72, ceili(ids.size() / 12.0) * 70, false, Image.FORMAT_RGBA8) if not review.is_empty() else null
	if sheet:
		sheet.fill(Color(0.16, 0.16, 0.17))
	var body := _img("res://assets/sprites/pixellab/characters/male/body/idle.png")
	for i in ids.size():
		var item: Dictionary = ItemGenerator.make_legendary(str(ids[i]), 20, rng)
		if str(item.get("appearance", "")).is_empty():
			continue
		worn += 1
		if not item.has("look"):
			missing.append(ids[i])
			continue
		var v: Dictionary = item.look.variant
		sigs["%s|%.2f" % [str(v.get("ramp", [])), float(v.get("hue_shift", 0.0))]] = true
		if sheet == null:
			continue
		var at := Vector2i((i % 12) * 72, (i / 12) * 70)
		var fr := body.get_region(Rect2i(0, 128, 64, 64))
		var key := CharacterSprite.gear_key(ItemLooks.drawn_appearance(str(item.appearance), "male"), "male")
		if not key.is_empty():
			var layer := _img(str(GameData.asset_entry(key).path) + "idle.png")
			if layer:
				fr.blend_rect(ItemLooks.recolor_image(layer.get_region(Rect2i(0, 128, 64, 64)), ItemLooks.params(v)), Rect2i(0, 0, 64, 64), Vector2i.ZERO)
		sheet.blend_rect(fr, Rect2i(0, 0, 64, 64), at + Vector2i(0, 6))
		var ic := ItemLooks.icon(item)
		if ic:
			var im := ic.get_image()
			im.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), at + Vector2i(40, 0))
	if sheet:
		sheet.save_png(review.path_join("legendary_looks.png"))
	da.check(missing.is_empty() and sigs.size() >= int(worn * 0.9),
			"worn legendaries have their own colours (%d looks for %d legendaries, none without: %s)" % [sigs.size(), worn, missing.slice(0, 4)])


static var _imgs: Dictionary = {}


func _img(path: String) -> Image:
	if _imgs.has(path):
		return _imgs[path]
	var img: Image = null
	if ResourceLoader.exists(path):
		img = (load(path) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
	_imgs[path] = img
	return img
