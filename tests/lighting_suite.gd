class_name LightingSuite
extends RefCounted
## #46 lighting rules (scenario "lighting_rules", headless): every door kind (plain, side, boss,
## both merchants) and every sight-blocking prop keeps its art on the lit side of each of its own
## shadow lines, so a light on any side never blacks it out; a closed door's lines cover the whole
## opening, so light still can't pass, and they go away while it is open; a prop's shadow lines
## sit on its footprint, so the shadow starts at its foot. #50: a light right next to a closed door
## on any side (inside the strip its art overlaps, too) only has lines casting for it whose shadow
## falls away from its own side, and one of them still closes the whole opening, meeting the wall
## occluders so nothing slips past the door's sides. The look is reviewed with
## --tour=lighting_sides and --tour=door_torch in every biome.

var da: Node
var g: Node

const DOOR_SCRIPT := preload("res://scripts/dungeon/door.gd")
const PROP_SCRIPT := preload("res://scripts/dungeon/prop.gd")


func _init(dev_auto: Node) -> void:
	da = dev_auto


## The one-sided lines under `n`: [[a, b], ...] in `n`'s space (LightLayers.one_sided casts for
## lights on the left of a -> b, i.e. cross(b - a, p - a) < 0, and shadows fall to the right).
static func lines(n: Node) -> Array:
	var out: Array = []
	for o in n.find_children("*", "LightOccluder2D", true, false):
		var poly: OccluderPolygon2D = o.occluder
		if poly == null:
			continue
		var pts := poly.polygon
		var xf: Transform2D = (o as Node2D).transform
		var parent := o.get_parent()
		while parent and parent != n:
			xf = (parent as Node2D).transform * xf
			parent = parent.get_parent()
		for i in pts.size() - 1:
			out.append([xf * pts[i], xf * pts[i + 1], poly.closed, poly.cull_mode])
	return out


## The lines that could put `c` in their shadow (c on their dark side).
static func shading(ls: Array, c: Vector2) -> Array:
	return ls.filter(func(l): return l[2] or l[3] != OccluderPolygon2D.CULL_CLOCKWISE or (Vector2(l[1]) - Vector2(l[0])).cross(c - Vector2(l[0])) >= 0.0)


## #50: lights right next to `door` on each of its sides, the art's overlap strip included. For each,
## every line that casts for it must throw its shadow away from the light's side, and one casting
## line must close the whole opening; in front of a horizontal door that line must sit no higher
## than the top of the wall row, where the wall tiles' occluders begin. Returns the failures.
static func side_problems(door: Node2D, ls: Array, art_top: float) -> Array:
	var w: Rect2 = door.world_rect
	var hw := w.size.x / 2.0
	var h := w.size.y
	var samples: Array = []  # [point, outward normal of the light's side, name]
	if door.vertical:
		var ex := 0.0
		for l in ls:
			ex = maxf(ex, absf(Vector2(l[0]).x))
		for sx in [1.0, -1.0]:
			for dx in [3.0, 24.0, hw + 12.0]:
				for fy in [0.2, 0.5, 0.8]:
					samples.append([Vector2(sx * (ex + dx), -h * fy), Vector2(sx, 0), "east" if sx > 0 else "west"])
	else:
		for x in [0.0, hw - 4.0, -hw + 4.0, hw + 24.0, -hw - 24.0]:
			for y in [art_top + 3.0, (art_top - h) / 2.0, -h - 3.0]:
				if y < -h:
					samples.append([Vector2(x, y), Vector2(0, -1), "north"])
			for y in [3.0, 24.0]:
				samples.append([Vector2(x, y), Vector2(0, 1), "south"])
	var out: Array = []
	for sm in samples:
		var c: Vector2 = sm[0]
		var n: Vector2 = sm[1]
		var casting := ls.filter(func(l): return (Vector2(l[1]) - Vector2(l[0])).cross(c - Vector2(l[0])) < 0.0)
		var back := casting.filter(func(l): var d := Vector2(l[1]) - Vector2(l[0]); return Vector2(-d.y, d.x).dot(n) >= 0.0)
		var closes := false
		for l in casting:
			var a: Vector2 = l[0]
			var b: Vector2 = l[1]
			if door.vertical:
				closes = closes or (minf(a.y, b.y) <= -h + 0.5 and maxf(a.y, b.y) >= -0.5)
			else:
				closes = closes or (minf(a.x, b.x) <= -hw + 0.5 and maxf(a.x, b.x) >= hw - 0.5 and a.y >= -h - 0.5 and a.y <= 0.5)
		if not back.is_empty() or not closes:
			out.append("%s light at %s: %d line(s) shadow its own side, opening closed %s" % [sm[2], c, back.size(), closes])
	return out


func run() -> void:
	g = da._game()
	await da._wait(1.0)
	var tile: int = g.dungeon.tile
	var holder := Node2D.new()
	g.add_child(holder)
	var bad: Array = []
	var specs: Array = [
		{"name": "plain", "d": {"cells": [Vector2i(10, 10), Vector2i(11, 10)], "vertical": false, "rect": Rect2i(10, 10, 2, 1)}},
		{"name": "side", "d": {"cells": [Vector2i(10, 10), Vector2i(10, 11)], "vertical": true, "rect": Rect2i(10, 10, 1, 2)}},
	]
	for t in GameData.doors:
		if not str(t).begins_with("_"):
			specs.append({"name": str(t), "d": {"cells": [Vector2i(10, 10), Vector2i(11, 10)], "vertical": false, "rect": Rect2i(10, 10, 2, 1),
				"type": str(t), "kind": "boss" if str(t) == "boss" else "merchant", "biome": "crypt"}})
	for spec in specs:
		var door: Node2D = DOOR_SCRIPT.new()
		door.setup(spec.d, tile)
		holder.add_child(door)
		await da.get_tree().process_frame
		var ls := lines(door)
		var w: Rect2 = door.world_rect
		var hw := w.size.x / 2.0
		var sprites: Array = door._sprites.get_children().filter(func(s): return s is Sprite2D)
		var lit := sprites.all(func(s): return (s.light_mask & LightLayers.ALL) != 0 or (s.material is CanvasItemMaterial and s.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED))
		var art_c: Array = []
		var art_top := 0.0
		for s in sprites:
			art_top = minf(art_top, (s.transform * s.get_rect().position).y)
			if s.material is CanvasItemMaterial and s.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED:
				continue  # drawn at a fixed brightness (#31), lights don't change it
			if (s.light_mask & LightLayers.LIT) == 0:
				continue  # SELF_LIT (#50): lit, never shadowed
			var r: Rect2 = s.get_rect()
			art_c.append(s.transform * r.get_center())
			art_c.append(s.transform * (r.get_center() + Vector2(0, r.size.y * 0.4)))
			art_c.append(s.transform * (r.get_center() - Vector2(0, r.size.y * 0.4)))
			art_c.append(s.transform * (r.get_center() + Vector2(r.size.x * 0.45, 0)))
			art_c.append(s.transform * (r.get_center() - Vector2(r.size.x * 0.45, 0)))
		var dark := art_c.filter(func(c): return not shading(ls, c).is_empty())
		var covers := false
		for l in ls:
			var a: Vector2 = l[0]
			var b: Vector2 = l[1]
			if door.vertical:
				covers = covers or (minf(a.y, b.y) <= -w.size.y + 0.5 and maxf(a.y, b.y) >= -0.5)
			else:
				covers = covers or (minf(a.x, b.x) <= -hw + 0.5 and maxf(a.x, b.x) >= hw - 0.5)
		var sides := side_problems(door, ls, art_top)
		if not sides.is_empty():
			bad.append("%s door, lights beside it: %s" % [spec.name, sides])
		var shut: bool = door._occluder.is_visible_in_tree()
		door.is_open = true
		door._refresh()
		await da.get_tree().process_frame
		var opened: bool = not door._occluder.is_visible_in_tree()
		if ls.size() < 2 or sprites.is_empty() or not lit or not dark.is_empty() or not covers or not shut or not opened:
			bad.append("%s door: lines %d, lit %s, art in its own shadow %d, covers the opening %s, closed blocks %s, open lets through %s" % [spec.name, ls.size(), lit, dark.size(), covers, shut, opened])
		door.queue_free()
	da.check(bad.is_empty() and specs.size() >= 5, "every door kind (%d) stays lit from any side and still closes its opening to light%s" % [specs.size(), "" if bad.is_empty() else ": %s" % [bad]])
	# Props: shadow lines on the footprint, the art never on their dark side.
	var pbad: Array = []
	var n := 0
	for t in GameData.props:
		var def: Dictionary = GameData.props[t]
		if str(t).begins_with("_") or not def.get("blocks_sight", true) or def.get("flat", false):
			continue
		var pr: StaticBody2D = PROP_SCRIPT.new()
		pr.setup(str(t), Vector2.ZERO)
		holder.add_child(pr)
		n += 1
		var sz: Array = def.get("size", [20, 10])
		var ls := lines(pr)
		var off := ls.filter(func(l): return Vector2(l[0]).y < -float(sz[1]) - 0.5 or Vector2(l[1]).y < -float(sz[1]) - 0.5 or Vector2(l[0]).y > 0.5 or Vector2(l[1]).y > 0.5)
		var spr: Sprite2D = pr._sprite
		var pts: Array = []
		if spr.texture:
			var r := spr.get_rect()
			for fy in [0.1, 0.5, 0.9]:
				pts.append(spr.transform * Vector2(r.get_center().x, r.position.y + r.size.y * fy))
		var dark := pts.filter(func(c): return not shading(ls, c).is_empty())
		if ls.size() < 3 or not off.is_empty() or not dark.is_empty():
			pbad.append("%s: lines %d, off the footprint %d, art in its own shadow %d" % [t, ls.size(), off.size(), dark.size()])
		pr.queue_free()
	da.check(n > 5 and pbad.is_empty(), "every sight-blocking prop (%d) casts from its footprint and never shadows its own art%s" % [n, "" if pbad.is_empty() else ": %s" % [pbad.slice(0, 5)]])
	holder.queue_free()
