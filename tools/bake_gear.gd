extends SceneTree
## Bakes held-item layers (weapons, shields, trinkets) that line up frame by frame with the
## base body sheets (CharacterSprite draws body + one layer per slot from the same frame grid).
## Worn pieces (helmets, chests...) are cut from outfit art by tools/gear_cut.gd instead.
##   godot --headless --path . -s tools/bake_gear.gd -- <config.json> [layer ...]
## A held picture is placed at the hand: the "hands" pixels (tools/body_regions.gd) farthest
## along the direction's hand vector; it is rotated per direction and swung through the attack
## and cast frames. Rows are directions E, SE, S, SW, W, NW, N, NE. Only "held_anims" get
## sheets: without one (lying, ghost) CharacterSprite doesn't draw the layer.

const DIRS := 8

const BodyRegions := preload("res://tools/body_regions.gd")

var cfg: Dictionary
var regions_tool: BodyRegions
var cell := 64


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	cell = int(cfg.cell)
	regions_tool = BodyRegions.new(cfg)
	var only: Array = args.slice(1)
	var layers: Array = cfg.held.keys().filter(func(l): return only.is_empty() or only.has(l))
	for anim in cfg.held_anims:
		var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
		if body == null:
			push_error("bake_gear: no body sheet for " + anim)
			continue
		var outs := {}
		for layer in layers:
			outs[layer] = Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)
		var frames := body.get_width() / cell
		for d in DIRS:
			for f in frames:
				var src := body.get_region(Rect2i(f * cell, d * cell, cell, cell))
				var used := src.get_used_rect()
				if used.size.y < 4:
					continue
				var regions := regions_tool.segment(src)
				for layer in layers:
					var img := _held(cfg.held[layer], regions, used, anim, d, f, frames)
					if img:
						outs[layer].blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(f * cell, d * cell))
		for layer in layers:
			var dst := ProjectSettings.globalize_path(str(cfg.out_root).path_join(layer).path_join(anim + ".png"))
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			outs[layer].save_png(dst)
		print("bake_gear: %s (%d layers)" % [anim, layers.size()])
	quit()


func _load(path: String) -> Image:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _held(spec: Dictionary, regions: Dictionary, used: Rect2i, anim: String, d: int, f: int, frames: int) -> Image:
	var pic := _load(str(spec.picture))
	if pic == null:
		return null
	var hand_vec: Array = cfg.hand_vectors[spec.get("hand", "main")][d]
	var v := Vector2(float(hand_vec[0]), float(hand_vec[1]))
	var center := Vector2(used.get_center())
	var best := Vector2i(-1, -1)
	var bs := -INF
	for want in ["hands", "arms", "torso"]:  # a running pose can hide both arms against the body
		for p in regions:
			if regions[p] != want:
				continue
			var s := (Vector2(p) - center).dot(v)
			if s > bs:
				bs = s
				best = p
		if best.x >= 0:
			break
	if best.x < 0:
		return null
	# Pictures are drawn tip up-right. Directions whose hand is on the left of the screen use the
	# mirrored picture (tip outward). "pose" is the resting angle (degrees, clockwise):
	# "down" = tip down and a little outward (blades), "up" = upright (staves, bows), "flat" =
	# as drawn (shields, orbs); per-direction "angles" override it. Attacks/casts swing by
	# "swing" [from, to] relative to the resting angle.
	var mirror: bool = cfg.get("held_mirror", [])[d] if not cfg.get("held_mirror", []).is_empty() else false
	var poses: Dictionary = cfg.get("held_poses", {"down": 120.0, "up": -45.0, "flat": 0.0})
	var ang := float(poses.get(str(spec.get("pose", "down")), 0.0))
	if spec.has("angles"):
		ang = float(spec.angles[d])
	if anim in ["attack", "cast"] and frames > 1:
		var swing: Array = spec.get("swing", [0.0, 0.0])
		var t := float(f) / float(frames - 1)
		ang += lerpf(float(swing[0]), float(swing[1]), sin(t * PI * 0.5))
	if mirror:
		ang = -ang
	var img := pic.duplicate()
	if mirror:
		img.flip_x()
	var grip: Array = spec.get("grip", [0.25, 0.75])
	var g := Vector2(float(grip[0]) * img.get_width(), float(grip[1]) * img.get_height())
	if mirror:
		g.x = img.get_width() - g.x
	g = _nearest_opaque(img, g)
	var sc := float(spec.get("scale", 1.0))
	var out := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	_draw_rotated(out, img, g, Vector2(best) + Vector2(0.5, 0.5), deg_to_rad(ang), sc)  # pixel centre: the hand pixel maps onto the grip
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


## The grip must be on the item (a hand holds the handle, not the air next to it).
func _nearest_opaque(img: Image, g: Vector2) -> Vector2:
	var best := g
	var bd := INF
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.5:
				var d := Vector2(x + 0.5, y + 0.5).distance_squared_to(g)
				if d < bd:
					bd = d
					best = Vector2(x + 0.5, y + 0.5)
	return best
