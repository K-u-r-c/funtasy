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
	await run_walls()


## #79: walls fully stop light and hands. A wall face tile also closes its foot to lights behind
## the wall (the soft shadow edge of its top strip bled into the room in front); a wall torch can
## only be taken, seen and lit from its own side; the things behind a wall (an item, a chest) can't
## be reached through it; closed doors and spouts out of sight take light like walls; taking a
## torch from the front works as before. The pixels are measured by --tour=leak_probe (windowed).
func run_walls() -> void:
	var p: Player = da._local()
	p.iframe_left = 9999.0
	# Every face tile: the strip (both sides) and the one-sided back line, 4 px behind the face's
	# top, casting only for lights north of it (shadow south), never for lights in front.
	var lines_ok := 0
	var lines_bad := 0
	var src := (g.dungeon.wall_layer as TileMapLayer).tile_set.get_source(0) as TileSetAtlasSource
	var h: float = g.dungeon.tile / 2.0
	for i in src.get_tiles_count():
		var td := src.get_tile_data(src.get_tile_id(i), 0)
		var strip := td.get_occluder(0)
		if strip == null or strip.polygon.size() != 4 or absf(strip.polygon[2].y - strip.polygon[0].y) > 8.0:
			continue  # not a face tile
		var back := td.get_occluder(1)
		var ok := back != null and not back.closed and back.cull_mode == OccluderPolygon2D.CULL_CLOCKWISE and back.polygon.size() == 2
		if ok:
			var a := back.polygon[0]
			var b := back.polygon[1]
			var y := -h - Dungeon.BACK_LINE
			# casts for c when cross(b - a, c - a) < 0 (LightLayers.one_sided)
			ok = absf(a.y - y) < 0.1 and absf(b.y - y) < 0.1 and absf(b.x - a.x) >= g.dungeon.tile - 0.1 \
					and (b - a).cross(Vector2(0, y - 4.0) - a) < 0.0 and (b - a).cross(Vector2(0, h + 8.0) - a) > 0.0
		if ok:
			lines_ok += 1
		else:
			lines_bad += 1
	da.check(lines_ok > 0 and lines_bad == 0, "every wall face tile stops lights behind the wall before its art (%d ok, %d without)" % [lines_ok, lines_bad])
	# A floor with a wall torch on a one-cell wall (open floor behind it).
	var t: Node = null
	for depth_try in range(1, 10):
		for tt in g.dungeon.torches.values():
			var up: int = g.dungeon.cell_at(tt.cell + Vector2i(0, -1))
			if tt.is_lit() and up != DungeonGenerator.CELL_WALL and up != DungeonGenerator.CELL_CANAL:
				t = tt
				break
		if t:
			break
		g.start_floor(depth_try + 1)
		await da._wait(1.0)
	da.check(t != null, "found a wall torch on a one-cell wall")
	if t == null:
		return
	for e in g.enemies_root.get_children():
		e.queue_free()
	var d: Dungeon = g.dungeon
	var behind := d.cell_center(t.cell + Vector2i(0, -1)) + Vector2(0, d.tile * 0.5 - 7.0)
	var front := d.cell_center(t.front_cell()) + Vector2(0, -d.tile * 0.5 + 9.0)
	# From behind: right above the torch, within reach of it, but on the wrong side.
	p.torch_left = 0.0
	p.torch_sync = 0
	p.host_teleport(behind)
	p.aim_pos = t.interact_pos()
	await da._wait(0.6)
	da.check(p.global_position.distance_to(t.interact_pos()) < float(GameData.bal("world.interact_range")), "behind the wall the torch is within plain reach (%.0f px)" % p.global_position.distance_to(t.interact_pos()))
	var offered: Dictionary = g.find_interactable(p, 0)
	da.check(offered.get("node") != t, "from behind the wall the torch isn't offered (prompt '%s')" % str(offered.get("text", "")))
	g.host_interact(p, t)
	await da._wait(0.2)
	da.check(t.is_lit() and p.torch_left <= 0.0, "from behind the wall the host refuses to hand over the torch")
	await da._wait(0.5)
	da.check(not t.seen_local and not t.seen_shown() and not t.light.enabled, "from behind the wall the torch, its glow and its light aren't drawn")
	# An item and a chest on the far side of the wall: within reach, never through it.
	var item_at := d.cell_center(t.front_cell()) + Vector2(14, -6)
	g.loot.drop_item(g.gold_key_item(), item_at)
	await da._wait(0.3)
	var near_items: Array = g.items_root.get_children().filter(func(x): return x.global_position.distance_to(item_at) < 20.0)
	da.check(not near_items.is_empty(), "an item lies in front of the torch")
	if not near_items.is_empty():
		p.aim_pos = near_items[0].global_position
		da.check(g.find_interactable(p, 0).get("node") != near_items[0], "an item behind the wall isn't offered")
		var keys: int = g.party_keys
		g.loot.try_pickup(p, near_items[0])
		await da._wait(0.2)
		da.check(g.party_keys == keys, "the host refuses a pickup through the wall")
		for it in near_items:
			it.queue_free()
	da.check(not d.reach_clear(behind, front), "no reach through the wall (%s -> %s)" % [behind, front])
	# Every wall orientation, thin and thick: nothing on the far side is in reach.
	var through := []
	var cases := wall_cases(d)
	for cs in cases:
		var far_pt: Vector2 = (cs.far[0] as Rect2).get_center()
		var pr := Rect2(cs.far[1]).get_center()
		for pt in [far_pt, pr]:
			if d.reach_clear(cs.hero, pt):
				through.append(cs.name)
	da.check(cases.size() >= 4 and through.is_empty(), "no reach through a wall in %d orientations / thicknesses%s" % [cases.size(), "" if through.is_empty() else ": %s" % [through]])
	# Closed doors and spouts out of sight take light like walls.
	var hidden_doors := 0
	var lit_wrong := 0
	for door in d.doors:
		for c in door._sprites.get_children():
			if c.has_meta("self_lit"):
				var seen := false
				for dc in door.cells:
					seen = seen or g.visibility.is_cell_visible(dc)
				if not seen:
					hidden_doors += 1
					if c.light_mask != LightLayers.LIT:
						lit_wrong += 1
	da.check(lit_wrong == 0, "closed doors out of sight (%d) take light like the walls" % hidden_doors)
	# From the front: the torch shows and is taken as before.
	p.host_teleport(front)
	p.aim_pos = t.interact_pos()
	await da._wait(0.6)
	da.check(t.seen_local and t.light.enabled, "in front of the torch it is drawn with its light")
	da.check(g.find_interactable(p, 0).get("node") == t, "in front of the torch it is offered")
	g.host_interact(p, t)
	await da._wait(0.3)
	da.check(not t.is_lit() and p.torch_left > 0.0, "taken from the front the torch burns in the hero's hand")


## #79: places where a hero can stand pressed against a wall, one per wall orientation, for thin
## (one cell, open floor on both sides) and thick walls. Each: {name, hero (position, feet just
## off the wall), wall (the wall cells between), far (floor / wall-face cells on the far side that
## the hero's light must not reach)}.
static func wall_cases(d: Dungeon) -> Array:
	var out: Array = []
	var open := func(c: Vector2i) -> bool: return d.cell_at(c) != DungeonGenerator.CELL_WALL and d.cell_at(c) != DungeonGenerator.CELL_CANAL
	var solid := func(c: Vector2i) -> bool: return d.cell_at(c) == DungeonGenerator.CELL_WALL
	var hs := d.tile * 0.5
	var dirs := {"south": Vector2i(0, 1), "north": Vector2i(0, -1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
	var found := {}
	for y in range(3, d.size.y - 3):
		for x in range(3, d.size.x - 3):
			var c := Vector2i(x, y)
			if not open.call(c):
				continue
			for dn in dirs:
				var dv: Vector2i = dirs[dn]
				var side := Vector2i(dv.y, dv.x)
				# The hero stands on c; the wall starts at c + dv; three floor cells along it on the
				# hero's side and three wall cells along it, so the case is a straight run of wall.
				if not (open.call(c - side) and open.call(c + side) and solid.call(c + dv) and solid.call(c + dv - side) and solid.call(c + dv + side)):
					continue
				var thick := 1
				while thick < 4 and solid.call(c + dv * (thick + 1)) and solid.call(c + dv * (thick + 1) - side) and solid.call(c + dv * (thick + 1) + side):
					thick += 1
				var beyond := c + dv * (thick + 1)
				if thick >= 4 or not (open.call(beyond) and open.call(beyond - side) and open.call(beyond + side)):
					continue
				var key := "%s_%s" % ["thin" if thick == 1 else "thick", dn]
				if found.has(key):
					continue
				# Doors are lit from both sides on purpose (#50): keep them out of the frame.
				var near_door := false
				for door in d.doors:
					near_door = near_door or door.world_rect.grow(d.tile * 3.0).has_point(d.cell_center(c))
				if near_door:
					continue
				var far: Array = []  # world rects
				for along in range(-1, 2):
					for depth in range(0, 2):
						far.append(Rect2(Vector2((beyond + side * along + dv * depth) * d.tile), Vector2(d.tile, d.tile)))
				# A face tile (wall with floor below) belongs to the room south of it: seen from
				# the north it is the far side too, its top strip included.
				if dn == "south":
					for along in range(-1, 2):
						var fc := c + dv * thick + side * along
						far.append(Rect2(Vector2(fc * d.tile), Vector2(d.tile, d.tile)))
				var hero := d.cell_center(c) + Vector2(dv) * (hs - 7.0)
				found[key] = {"name": key, "hero": hero, "far": far, "wall": c + dv}
	for k in ["thin_south", "thin_north", "thin_east", "thin_west", "thick_south", "thick_north", "thick_east", "thick_west"]:
		if found.has(k):
			out.append(found[k])
	return out
