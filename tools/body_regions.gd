extends RefCounted
## Body regions of a naked base-body frame for the gear tools (tools/gear_cut.gd,
## tools/bake_gear.gd), found from the body's colours and topology:
##   head  = hair + skin within head_reach px (geodesic) of the hair     torso = shirt
##   arms  = other skin touching the shirt    hands = the far end of each arm
##   legs  = shorts + skin touching shorts    feet  = the far end of each leg
## Colour classes come from the config "palette" (exact) and "rules" (HSV fallback).

const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
const COLORS := {"head": "#ff5050", "torso": "#50a0ff", "arms": "#50ff90", "hands": "#ffe050",
	"legs": "#c070ff", "feet": "#ff9a30"}

var cfg: Dictionary
var cell := 64
var classes: Array = []  ## [[Color, class], ...]


func _init(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	cell = int(cfg.get("cell", 64))
	for k in cfg.get("palette", {}):
		for hexc in cfg.palette[k]:
			classes.append([Color.from_string(hexc, Color.BLACK), k])


## Body regions of one naked frame: {Vector2i: region}.
## Colour class of every body pixel of a frame ({Vector2i: class}), cleaned up: only the main
## hair / shirt / shorts blobs (and bits right next to them) keep their class; stray dark
## shading reads as outline, stray light highlights as skin.
func class_map(img: Image) -> Dictionary:
	var cls := {}
	for y in cell:
		for x in cell:
			var c := img.get_pixel(x, y)
			if c.a >= 0.5:
				cls[Vector2i(x, y)] = _class_of(c)
	_keep_main(cls, "hair", "outline", false, true)
	_keep_main(cls, "shirt", "skin", true)
	_keep_main(cls, "shorts", "outline", true)
	return cls


## Hair, or the dark outline / shading right around it (a ponytail's edge): the pixels a helmet
## or hood may hide without drawing over them (#15).
static func is_hairish(cls: Dictionary, p: Vector2i) -> bool:
	var c := str(cls.get(p, ""))
	if c == "hair":
		return true
	if c != "outline":
		return false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if str(cls.get(p + Vector2i(dx, dy), "")) == "hair":
				return true
	return false


## Keeps the biggest blob of class `k`, blobs touching it and (with `keep_big`) any blob of at
## least min_blob px; the rest becomes `other`. With `top` (the hair), when the biggest blob lies
## below the top HEAD_ZONE of an upright figure, the blobs centred in that zone are kept instead:
## dark hair falls apart into small blobs between outline pixels, while shading on a raised arm's
## shirt can make one bigger brown blob - kept as the hair, it turned the real hair into outline
## and cut the helmet onto the arms.
const HEAD_ZONE := 0.28


func _keep_main(cls: Dictionary, k: String, other: String, keep_big: bool, top := false) -> void:
	var pix := {}
	for p in cls:
		if cls[p] == k:
			pix[p] = true
	var comps := _components(pix)
	comps.sort_custom(func(x, y): return x.size() > y.size())
	if top and not comps.is_empty():
		var y0 := 999
		var y1 := -999
		var x0 := 999
		var x1 := -999
		for p in cls:
			y0 = mini(y0, p.y)
			y1 = maxi(y1, p.y)
			x0 = mini(x0, p.x)
			x1 = maxi(x1, p.x)
		# Upright figures only: lying down (downed, death) the head isn't on top.
		var line := y0 + (y1 - y0 + 1) * HEAD_ZONE if y1 - y0 > (x1 - x0) * 1.2 else -INF
		var head: Array = []
		var rest: Array = []
		for c in comps:
			var cy := 0.0
			for q in c:
				cy += q.y
			(head if cy / c.size() < line else rest).append(c)
		if not head.is_empty() and not rest.is_empty() and rest[0] == comps[0]:
			var merged: Array = []
			for c in head:
				merged.append_array(c)
			comps = [merged] + rest
	var keep := {}
	if not comps.is_empty():
		for q in comps[0]:
			keep[q] = true
	for i in range(1, comps.size()):
		var close: bool = keep_big and comps[i].size() >= int(cfg.get("min_blob", 6))
		if not close:
			for q in comps[i]:
				if _near_set(q, keep, 2):
					close = true
					break
		if not close:
			for q in comps[i]:
				cls[q] = other


func segment(img: Image) -> Dictionary:
	var cls := class_map(img)
	var reg := {}
	for p in cls:
		match cls[p]:
			"hair":
				reg[p] = "head"
			"shirt":
				reg[p] = "torso"
			"shorts":
				reg[p] = "legs"
	# Face and neck: skin close to the hair (geodesic, so a raised arm isn't taken for the face).
	var skin := {}
	for p in cls:
		if cls[p] == "skin":
			skin[p] = true
	var hair_seeds: Array = []
	for p in skin:
		if _near_class(p, cls, "hair", 1):
			hair_seeds.append(p)
	var from_hair := _geodesic(skin, hair_seeds)
	var head_reach := int(cfg.get("head_reach", 7))
	for p in from_hair:
		if int(from_hair[p]) <= head_reach:
			reg[p] = "head"
			skin.erase(p)
	# Arms: skin touching the shirt; legs: skin touching the shorts. The far end of each limb
	# (from its root at the body) is the hand / foot.
	var arms := {}
	var legs := {}
	var shirt_c := _centroid(cls, "shirt")
	var shorts_c := _centroid(cls, "shorts")
	for comp in _components(skin):
		var near := _touching(comp, cls)
		var c := Vector2.ZERO
		for q in comp:
			c += Vector2(q)
		c /= comp.size()
		# A limb touching only the shorts is a leg, only the shirt an arm; otherwise (an arm by
		# the hips, a shin cut off by an outline) the part whose centre is closer wins.
		var is_leg: bool = c.distance_to(shorts_c) < c.distance_to(shirt_c)
		if near.has("shorts") != near.has("shirt"):
			is_leg = near.has("shorts")
		var target: Dictionary = legs if is_leg else arms
		for q in comp:
			target[q] = true
	_limbs(arms, cls, ["hair", "shirt"], "arms", "hands", int(cfg.get("hand_len", 3)), reg)
	_limbs(legs, cls, ["shorts"], "legs", "feet", int(cfg.get("foot_len", 4)), reg)
	# Everything else (outline, eyes) joins the nearest region.
	var frontier: Array = reg.keys()
	while not frontier.is_empty():
		var next: Array = []
		for q in frontier:
			for o in N8:
				var n: Vector2i = q + o
				if cls.has(n) and not reg.has(n):
					reg[n] = reg[q]
					next.append(n)
		frontier = next
	return reg


## Limb pixels: geodesic distance from the root (pixels next to `root_classes` or the head);
## the outer half of each component is split per limb and its last `tip_len` px are the tip.
func _limbs(pixels: Dictionary, cls: Dictionary, root_classes: Array, limb: String, tip: String, tip_len: int, reg: Dictionary) -> void:
	for comp in _components(pixels):
		var inside := {}
		for q in comp:
			inside[q] = true
		var roots: Array = []
		for q in comp:
			for rc in root_classes:
				if _near_class(q, cls, rc, 1) or _near_region(q, reg, "head", 1):
					roots.append(q)
					break
		if roots.is_empty():
			roots = [comp[0]]
		var dist := _geodesic(inside, roots)
		var maxd := 0
		for q in dist:
			maxd = maxi(maxd, int(dist[q]))
		for q in comp:
			reg[q] = limb
		var far := {}
		for q in comp:
			if int(dist.get(q, 0)) * 2 >= maxd:
				far[q] = true
		for part in _components(far):
			var local := 0
			for q in part:
				local = maxi(local, int(dist[q]))
			for q in part:
				if int(dist[q]) >= local - tip_len + 1:
					reg[q] = tip


func _centroid(cls: Dictionary, k: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for p in cls:
		if cls[p] == k:
			c += Vector2(p)
			n += 1
	return c / n if n > 0 else Vector2(cell / 2.0, cell / 2.0)


func _components(pixels: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for p in pixels:
		if seen.has(p):
			continue
		var comp: Array = []
		var stack: Array = [p]
		seen[p] = true
		while not stack.is_empty():
			var q: Vector2i = stack.pop_back()
			comp.append(q)
			for o in N8:
				var n: Vector2i = q + o
				if pixels.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append(comp)
	return out


func _geodesic(pixels: Dictionary, seeds: Array) -> Dictionary:
	var dist := {}
	var frontier: Array = []
	for s0 in seeds:
		if pixels.has(s0) and not dist.has(s0):
			dist[s0] = 0
			frontier.append(s0)
	while not frontier.is_empty():
		var next: Array = []
		for q in frontier:
			for o in N8:
				var n: Vector2i = q + o
				if pixels.has(n) and not dist.has(n):
					dist[n] = int(dist[q]) + 1
					next.append(n)
		frontier = next
	return dist


func _near_set(p: Vector2i, set_: Dictionary, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if set_.has(p + Vector2i(dx, dy)):
				return true
	return false


func _near_class(p: Vector2i, cls: Dictionary, k: String, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if cls.get(p + Vector2i(dx, dy), "") == k:
				return true
	return false


func _near_region(p: Vector2i, reg: Dictionary, k: String, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if reg.get(p + Vector2i(dx, dy), "") == k:
				return true
	return false


func _touching(comp: Array, cls: Dictionary) -> Dictionary:
	var out := {}
	for q in comp:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var k: String = cls.get(q + Vector2i(dx, dy), "")
				if k != "" and k != "skin" and k != "outline":
					out[k] = true
	return out


## Region of the closest body pixel for every canvas pixel (outfit pixels outside the body).
func nearest_map(reg: Dictionary) -> Dictionary:
	var out := {}
	var frontier: Array = reg.keys()
	for p in frontier:
		out[p] = reg[p]
	while not frontier.is_empty():
		var next: Array = []
		for q in frontier:
			for o in N8:
				var n: Vector2i = q + o
				if n.x >= 0 and n.y >= 0 and n.x < cell and n.y < cell and not out.has(n):
					out[n] = out[q]
					next.append(n)
		frontier = next
	return out


## Body colour class. Exact palette entries win; other colours (template animations shade a
## little differently) fall back to hue/saturation/value rules from the config ("rules").
func _class_of(c: Color) -> String:
	for e in classes:
		if dist2(e[0], c) < 0.0004:
			return e[1]
	var r: Dictionary = cfg.get("rules", {})
	if c.v < float(r.get("outline_v", 0.18)):
		return "outline"
	var warm := c.h < 0.12 or c.h > 0.95
	if warm and c.s > float(r.get("skin_s", 0.35)) and c.v > float(r.get("skin_v", 0.45)):
		return "skin"
	if warm and c.s > float(r.get("hair_s", 0.3)):
		return "hair"
	if c.s < float(r.get("cloth_s", 0.33)):
		return "shirt" if c.v > float(r.get("shirt_v", 0.5)) else "shorts"
	var best := ""
	var bd := 99.0
	for e in classes:
		var dd := dist2(e[0], c)
		if dd < bd:
			bd = dd
			best = e[1]
	return best


static func dist2(a: Color, b: Color) -> float:
	return (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
