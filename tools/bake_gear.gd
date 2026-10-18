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
var track_cfg: Variant = null  ## {dir, picks: {anim: [[frame per pick] per direction]}} (--track)
var _back_ref := {}  ## direction -> [shoulder on its idle frame 0, trunk centre there] (anchor "back")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	cell = int(cfg.cell)
	regions_tool = BodyRegions.new(cfg)
	var only: Array = Array(args.slice(1)).filter(func(a): return not str(a).begins_with("--"))
	for a in args:
		if str(a).begins_with("--track="):
			track_cfg = JSON.parse_string(FileAccess.get_file_as_string(str(a).trim_prefix("--track=")))
	var layers: Array = cfg.held.keys().filter(func(l): return only.is_empty() or only.has(l))
	for anim in cfg.held_anims:
		var body := _load(str(cfg.body_dir).path_join(anim + ".png"))
		if body == null:
			push_error("bake_gear: no body sheet for " + anim)
			continue
		var outs := {}  # layer -> [front, back]
		for layer in layers:
			outs[layer] = [Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8),
				Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)]
		var frames := body.get_width() / cell
		for d in DIRS:
			var per_frame: Array = []  # [src, used, regions] or null
			for f in frames:
				var src := body.get_region(Rect2i(f * cell, d * cell, cell, cell))
				var used := src.get_used_rect()
				per_frame.append([src, used, regions_tool.segment(src)] if used.size.y >= 4 else null)
			var paths := _tracked_paths(anim, d, per_frame)
			if paths.is_empty():
				paths = _hand_paths(per_frame, anim, d)
			var track := {}  # hand ("main" / "off") -> last {pos, vec} along this direction's frames
			for f in frames:
				if per_frame[f] == null:
					continue
				var src: Image = per_frame[f][0]
				var used: Rect2i = per_frame[f][1]
				var regions: Dictionary = per_frame[f][2]
				for hand in paths:
					if track.has(hand):
						track[hand].pos = paths[hand][f]
						track[hand].grip = Vector2i(Vector2(paths[hand][f]).round())
					else:
						var pp: Vector2 = paths[hand][f]
						track[hand] = {"pos": pp, "grip": Vector2i(pp.round()), "vec": Vector2.DOWN, "rad": Vector2.DOWN, "pix": {}, "hidden": true}
				var hands := _hands(regions, used, d, track, anim in LOW_HAND_ANIMS)
				for layer in layers:
					var res := _held(cfg.held[layer], regions, hands, src, anim, d)
					if not res.is_empty():
						outs[layer][0].blit_rect(res[0], Rect2i(0, 0, cell, cell), Vector2i(f * cell, d * cell))
						outs[layer][1].blit_rect(res[1], Rect2i(0, 0, cell, cell), Vector2i(f * cell, d * cell))
		for layer in layers:
			var root := str(cfg.out_root).path_join(layer)
			_save(outs[layer][0], root.path_join(anim + ".png"))
			_save(outs[layer][1], root.path_join("back").path_join(anim + ".png"))
		print("bake_gear: %s (%d layers)" % [anim, layers.size()])
	quit()


func _save(img: Image, path: String) -> void:
	var dst := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	img.save_png(dst)


## Hand paths from the whole source clip (--track, written by build_hero_v2.py): the hands are
## told apart on the clip's first frame (the rest pose, where the direction's hand vectors work)
## and followed through every source frame, then read at the picked frames, shifted by the feet
## alignment the final sheet got. {} when there is no track data for this animation.
func _tracked_paths(anim: String, d: int, per_frame: Array) -> Dictionary:
	if track_cfg == null or not track_cfg.picks.has(anim):
		return {}
	var full := _load(str(track_cfg.dir).path_join(anim + ".png"))
	if full == null:
		return {}
	var full_frames: Array = []
	for f in full.get_width() / cell:
		var src := full.get_region(Rect2i(f * cell, d * cell, cell, cell))
		var used := src.get_used_rect()
		full_frames.append([src, used, regions_tool.segment(src)] if used.size.y >= 4 else null)
	var full_paths := _hand_paths(full_frames, anim, d, _weapon_rest(d))
	if full_paths.is_empty():
		return {}
	var picks: Array = track_cfg.picks[anim][d]
	var out := {}
	for hand in full_paths:
		var path: Array = []
		for f in per_frame.size():
			var i := mini(int(picks[mini(f, picks.size() - 1)]), full_frames.size() - 1)
			var dy := 0.0
			if per_frame[f] != null and full_frames[i] != null:
				dy = float(per_frame[f][1].end.y - full_frames[i][1].end.y)
			path.append(Vector2(full_paths[hand][i]) + Vector2(0, dy))
		out[hand] = path
	return out


## The hand blobs of a frame: [[centroid, {pixel: true}], ...]. Skin of the nape between the hair
## and the shirt (seen from behind) reads as "hands" to the body regions; blobs in that neck zone
## (centred on the torso, at its top edge) are left out. With "low" (an animation where the arms
## hang: idle / walk / dash) so is any blob above the chest: bare shoulders, the neck and the face
## of the tank-top body read as "hands" too, and a hand never rises that high there.
func _hand_blobs(regions: Dictionary, low := false) -> Array:
	var hand_px := {}
	var top := 999
	var xs := 0.0
	var n := 0
	var fig_top := 999
	var fig_bot := -999
	for p in regions:
		fig_top = mini(fig_top, p.y)
		fig_bot = maxi(fig_bot, p.y)
		if regions[p] == "hands":
			hand_px[p] = true
		elif regions[p] == "torso":
			top = mini(top, p.y)
			xs += p.x
			n += 1
	var cx := xs / maxi(n, 1)
	var out: Array = []
	for comp in regions_tool._components(hand_px):
		var c := Vector2.ZERO
		var px := {}
		for q in comp:
			c += Vector2(q)
			px[q] = true
		c /= comp.size()
		if n > 0 and absf(c.x - cx) <= 5.0 and absf(c.y - top) <= 4.0:
			continue
		if low and c.y < fig_top + (fig_bot - fig_top + 1) * LOW_HAND_LINE:
			continue
		out.append([c, px])
	return out


var _weapon_rest_cache := {}


## Where the weapon hand rests on the first frame of the direction's "weapon_side_clip" (config,
## e.g. slash): the hand that swings it. Every v3 clip starts on the same rotation image, so the
## other clips find their weapon hand there too and the sword never changes hands between idle
## and attack. Vector2.INF when unknown.
func _weapon_rest(d: int) -> Vector2:
	if _weapon_rest_cache.has(d):
		return _weapon_rest_cache[d]
	_weapon_rest_cache[d] = Vector2.INF
	var clip := str(cfg.get("weapon_side_clip", ""))
	var full := _load(str(track_cfg.dir).path_join(clip + ".png")) if track_cfg != null and not clip.is_empty() else null
	if full == null:
		return Vector2.INF
	var frames: Array = []
	for f in full.get_width() / cell:
		var src := full.get_region(Rect2i(f * cell, d * cell, cell, cell))
		var used := src.get_used_rect()
		frames.append([src, used, regions_tool.segment(src)] if used.size.y >= 4 else null)
	var paths := _hand_paths(frames, "slash", d)
	if paths.has("main"):
		_weapon_rest_cache[d] = paths.main[0]
	return _weapon_rest_cache[d]


## Where each hand is along a direction's frames: {hand: [Vector2 per frame]}. Hand blobs are
## linked frame to frame into two tracks; in an animation with an "active_hand" (config: the hand
## that performs it, e.g. main for a slash, off for a shield bash) the track that gets furthest from
## its rest place is that hand, otherwise the first frame decides along the direction's hand vectors.
func _hand_paths(per_frame: Array, anim: String, d: int, weapon_rest := Vector2.INF) -> Dictionary:
	var tracks: Array = []  # [[Vector2 per frame], path length]
	for f in per_frame.size():
		var blobs: Array = []
		if per_frame[f] != null:
			for b in _hand_blobs(per_frame[f][2], anim in LOW_HAND_ANIMS):
				blobs.append(b[0])
		# Greedy by distance: each track takes its nearest free blob; a track left over may share a
		# blob (both fists together on a two-handed grip).
		var used := {}
		var pairs: Array = []
		for ti in tracks.size():
			for i in blobs.size():
				pairs.append([Vector2(tracks[ti][0][f - 1]).distance_to(blobs[i]), ti, i])
		pairs.sort_custom(func(a, b): return a[0] < b[0])
		var got := {}
		for pr in pairs:
			if pr[0] > 22.0:
				break
			if not got.has(pr[1]) and not used.has(pr[2]):
				got[pr[1]] = pr[2]
				used[pr[2]] = true
		for pr in pairs:
			if pr[0] <= 14.0 and not got.has(pr[1]):
				got[pr[1]] = pr[2]
		for ti in tracks.size():
			var t: Array = tracks[ti]
			var last: Vector2 = t[0][f - 1]
			if got.has(ti):
				var b: Vector2 = blobs[got[ti]]
				t[1] = maxf(t[1], b.distance_to(t[0][0]))  # furthest from its rest place
				t[0].append(b)
			else:
				# No hand blob: a hand read as arm (a whipping throw) - the nearest arm pixel.
				var near_arm := last
				var nd := 16.0
				if per_frame[f] != null:
					var regions: Dictionary = per_frame[f][2]
					for q in regions:
						if regions[q] == "arms" and Vector2(q).distance_to(last) < nd:
							nd = Vector2(q).distance_to(last)
							near_arm = Vector2(q)
				t[0].append(near_arm)
		for i in blobs.size():
			if not used.has(i) and tracks.size() < 2:
				var path: Array = []
				for k in f + 1:
					path.append(blobs[i])
				tracks.append([path, 0.0])
	if tracks.is_empty():
		return {}
	var out := {}
	var active := str(cfg.get("active_hand", {}).get(anim, ""))
	if tracks.size() == 1:
		out["main"] = tracks[0][0]
		return out
	if not active.is_empty():
		var mover := 0 if tracks[0][1] >= tracks[1][1] else 1
		out[active] = tracks[mover][0]
		out["off" if active == "main" else "main"] = tracks[1 - mover][0]
		return out
	var f0 := 0
	while f0 < per_frame.size() and per_frame[f0] == null:
		f0 += 1
	if weapon_rest != Vector2.INF and f0 < per_frame.size():
		var mw := 0 if tracks[0][0][f0].distance_to(weapon_rest) <= tracks[1][0][f0].distance_to(weapon_rest) else 1
		out["main"] = tracks[mw][0]
		out["off"] = tracks[1 - mw][0]
		return out
	var center := Vector2(per_frame[f0][1].get_center()) if f0 < per_frame.size() else Vector2(32, 32)
	var hv: Array = cfg.hand_vectors.main[d]
	var v := Vector2(float(hv[0]), float(hv[1]))
	var m := 0 if (tracks[0][0][f0] - center).dot(v) >= (tracks[1][0][f0] - center).dot(v) else 1
	out["main"] = tracks[m][0]
	out["off"] = tracks[1 - m][0]
	return out


## The main and off hand of a frame: {hand: {pos: Vector2i grip pixel, vec: forearm vector,
## pix: {Vector2i: true} the hand's pixels}}. Hand blobs are the "hands" regions; the first frame
## of a direction assigns them along the direction's hand vectors, later frames follow the nearest
## blob (a swinging hand keeps its role). A hand hidden behind the body keeps its last place.
func _hands(regions: Dictionary, used: Rect2i, d: int, track: Dictionary, low := false) -> Dictionary:
	var arm_px: Array = []
	for p in regions:
		if regions[p] == "arms":
			arm_px.append(p)
	var blobs: Array = _hand_blobs(regions, low)  # [centroid, pixels]
	var center := Vector2(used.get_center())
	var torso: Array = regions.keys().filter(func(q): return regions[q] == "torso")
	var shoulder := center
	if not torso.is_empty():
		var top := 999
		var bot := -999
		for q in torso:
			top = mini(top, q.y)
			bot = maxi(bot, q.y)
		var acc := Vector2.ZERO
		var cnt := 0
		for q in torso:
			if q.y <= top + maxi(1, (bot - top) / 3):
				acc += Vector2(q)
				cnt += 1
		shoulder = acc / cnt
	var out := {}
	var taken := {}
	for hand in ["main", "off"]:
		var best := -1
		if track.has(hand):
			var bd := INF
			for i in blobs.size():
				var dd: float = blobs[i][0].distance_to(track[hand].pos)
				if not taken.has(i) and dd < bd and dd < 16.0:
					bd = dd
					best = i
		else:
			var hv: Array = cfg.hand_vectors[hand][d]
			var v := Vector2(float(hv[0]), float(hv[1]))
			var bs := -INF
			for i in blobs.size():
				var sc: float = (blobs[i][0] - center).dot(v)
				if not taken.has(i) and sc > bs:
					bs = sc
					best = i
		if best < 0 and track.has(hand):
			# No hand blob there: a hand read as arm (a whipping throw) - the arm pixel nearest the
			# tracked place, when close; else hidden behind the body at its last place.
			var near_arm := Vector2(-999, -999)
			for q in arm_px:
				if Vector2(q).distance_to(track[hand].pos) < near_arm.distance_to(track[hand].pos):
					near_arm = Vector2(q)
			if near_arm.distance_to(track[hand].pos) <= 20.0:
				var tip := near_arm
				var vec2: Vector2 = (tip - center).normalized()
				out[hand] = {"pos": tip, "grip": Vector2i(tip), "vec": vec2, "rad": vec2, "pix": {Vector2i(tip): true}, "hidden": false}
				track[hand] = out[hand]
				continue
		if best < 0:
			if track.has(hand):
				# Hidden behind the body: held against the nearest body edge (torso / arm) there.
				out[hand] = track[hand].duplicate()
				out[hand].hidden = true
				var anchor := Vector2(track[hand].pos)
				var bestq := Vector2(-999, -999)
				for q in regions:
					if regions[q] in ["torso", "arms"] and Vector2(q).distance_to(anchor) < bestq.distance_to(anchor):
						bestq = Vector2(q)
				if bestq.x > -999.0:
					out[hand].grip = Vector2i(bestq)
			continue
		taken[best] = true
		var hc: Vector2 = blobs[best][0]
		# Forearm: the arm pixels nearest this hand (the limb it ends), arm centre -> hand centre.
		var ac := Vector2.ZERO
		var n := 0
		for q in arm_px:
			if Vector2(q).distance_to(hc) <= 9.0:
				ac += Vector2(q)
				n += 1
		var vec: Vector2 = (hc - ac / n) if n > 0 else (hc - center)
		if vec.length() < 0.5:
			vec = track[hand].vec if track.has(hand) else Vector2.DOWN
		# Radial: from the shoulder line (top third of the torso) through the fist - the line
		# of arm + weapon in a swing, steadier than the short forearm.
		var rad := hc - shoulder
		if rad.length() < 0.5:
			rad = vec
		var grip := Vector2i(hc.round())
		if not blobs[best][1].has(grip):
			var gd := INF
			for q in blobs[best][1]:
				if Vector2(q).distance_squared_to(hc) < gd:
					gd = Vector2(q).distance_squared_to(hc)
					grip = q
		out[hand] = {"pos": hc, "grip": grip, "vec": vec.normalized(), "rad": rad.normalized(), "pix": blobs[best][1], "hidden": false}
		track[hand] = out[hand]
	for hand in ["main", "off"]:
		var other := "off" if hand == "main" else "main"
		if not out.has(hand) and out.has(other):
			out[hand] = out[other].duplicate()
			out[hand].pix = {}
			out[hand].hidden = true
	return out


const REST_ANIMS := ["idle", "walk", "dash", "hit", "downed"]
const LOW_HAND_ANIMS := ["idle", "walk", "dash"]  ## the arms hang: no hand above LOW_HAND_LINE
const LOW_HAND_LINE := 0.32  ## of the figure's height from its top (head, neck and shoulders)


## [front image, back image] of one held item for one frame, or [] when its hand is unknown.
## The picture is drawn tip up-right. Its tip angle comes from spec "angles": per animation (or
## "rest" for idle / walk / dash / hit, "attack" for the rest) either ["follow", offset] = the
## forearm's direction plus offset degrees (mirrored directions negate it) or ["fixed", deg] =
## an absolute screen angle (0 = right, 90 = down; mirrored directions reflect it). A pixel over
## the body goes to the back sheet when its hand is the far hand in this direction ("near_hand")
## or when it covers the gripping hand (fingers close over the grip); the rest is drawn in front.
func _held(spec: Dictionary, regions: Dictionary, hands: Dictionary, body: Image, anim: String, d: int) -> Array:
	var hand := str(spec.get("hand", "main"))
	# "hand_anim": {anim: hand, or [hand per direction]} - the bow sits in the extended hand of the
	# draw, which isn't the same tracked hand in every direction.
	var per_anim: Variant = spec.get("hand_anim", {}).get(anim)
	if per_anim is Array:
		hand = str(per_anim[d])
	elif per_anim != null:
		hand = str(per_anim)
	var h: Dictionary
	if str(spec.get("anchor", "")) == "back":
		# Worn on the back (quiver): hung from the shoulder line, behind the body unless the hero
		# faces away ("near_hand" back row). The shoulder line is found on this direction's idle
		# frame and moved with the body (arms left out): in attacks the arms cover the chest and
		# the torso region shrinks or vanishes.
		if not _back_ref.has(d):
			var idle := _load(str(cfg.body_dir).path_join("idle.png"))
			var ref_regions := regions_tool.segment(idle.get_region(Rect2i(0, d * cell, cell, cell))) if idle != null else {}
			var shoulder := _shoulder(ref_regions)
			_back_ref[d] = [shoulder, _trunk_centre(ref_regions)] if shoulder.x >= 0.0 else []
		var ref: Array = _back_ref[d]
		var centre := _trunk_centre(regions)
		if ref.is_empty() or centre.x < 0.0:
			return []
		var off: Array = spec.get("offset", [[0, 0]])[d] if spec.has("offset") else [0, 0]
		var at := Vector2i((Vector2(ref[0]) + centre - Vector2(ref[1])).round()) + Vector2i(int(off[0]), int(off[1]))
		h = {"grip": at, "vec": Vector2.DOWN, "rad": Vector2.DOWN, "pix": {}, "hidden": false}
		hand = "back"
	elif hand == "extended":
		# The arm point reaching furthest sideways above the hips: the bow fist of a draw, which the
		# hand tracker can lose when the arm crosses the body (the drawing hand goes up, not out).
		var centre := _trunk_centre(regions)
		var best := Vector2i(-1, -1)
		var far := -1.0
		for q in regions:
			if regions[q] in ["arms", "hands"] and q.y <= centre.y and absf(q.x - centre.x) > far:
				far = absf(q.x - centre.x)
				best = q
		var rest_hand := str(spec.get("hand", "main"))
		if (best.x < 0 or far < 11.0) and hands.has(rest_hand):
			# No arm reaches out (rest frames): the item stays in its usual hand.
			h = hands[rest_hand]
			hand = rest_hand
		elif best.x < 0 or centre.x < 0.0:
			return []
		else:
			var v := (Vector2(best) - centre).normalized()
			h = {"grip": best, "vec": v, "rad": v, "pix": {}, "hidden": false}
	else:
		if not hands.has(hand):
			return []
		h = hands[hand]
	var pic := _load(str(spec.picture))
	if pic == null:
		return []
	var mirror: bool = cfg.get("held_mirror", [])[d] if not cfg.get("held_mirror", []).is_empty() else false
	var angles: Dictionary = spec.get("angles", {})
	var key := anim if angles.has(anim) else ("rest" if anim in REST_ANIMS else "attack")
	var rule: Array = angles.get(key, angles.get("rest", ["follow", 0]))
	var tip: float
	if str(rule[0]) == "fixed":
		tip = float(rule[1])
		if mirror:
			tip = 180.0 - tip
	elif str(rule[0]) == "radial":
		tip = rad_to_deg(Vector2(h.get("rad", h.vec)).angle()) + (-float(rule[1]) if mirror else float(rule[1]))
	else:
		tip = rad_to_deg(Vector2(h.vec).angle()) + (-float(rule[1]) if mirror else float(rule[1]))
	var img := pic.duplicate()
	var tip0 := -45.0
	if mirror:
		img.flip_x()
		tip0 = -135.0
	var grip: Array = spec.get("grip", [0.25, 0.75])
	var g := Vector2(float(grip[0]) * img.get_width(), float(grip[1]) * img.get_height())
	if mirror:
		g.x = img.get_width() - g.x
	g = _nearest_opaque(img, g)
	var sc := float(spec.get("scale", 1.0))
	var drawn := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	_draw_rotated(drawn, img, g, Vector2(h.grip) + Vector2(0.5, 0.5), deg_to_rad(tip - tip0), sc)
	var near: bool = bool(cfg.get("near_hand", {}).get(hand, [1, 1, 1, 1, 1, 1, 1, 1])[d]) and not h.get("hidden", false)
	var front := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var back := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	for y in cell:
		for x in cell:
			var c := drawn.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var q := Vector2i(x, y)
			var over_body := body.get_pixel(x, y).a >= 0.5
			if over_body and (not near or h.pix.has(q)):
				back.set_pixel(x, y, c)
			else:
				front.set_pixel(x, y, c)
	return [front, back]


## Middle of the torso's top rows, (-1, -1) without a torso.
func _shoulder(regions: Dictionary) -> Vector2:
	var torso: Array = regions.keys().filter(func(q): return regions[q] == "torso")
	if torso.is_empty():
		return Vector2(-1, -1)
	var top := 999
	for q in torso:
		top = mini(top, q.y)
	var acc := Vector2.ZERO
	var n := 0
	for q in torso:
		if q.y <= top + 3:
			acc += Vector2(q)
			n += 1
	return acc / n


## Centroid of the body without arms and hands, (-1, -1) when empty.
func _trunk_centre(regions: Dictionary) -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for q in regions:
		if regions[q] in ["head", "torso", "legs", "feet"]:
			acc += Vector2(q)
			n += 1
	return acc / n if n > 0 else Vector2(-1, -1)


func _load(path: String) -> Image:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	return img


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
