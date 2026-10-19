class_name AimPreview
extends Node2D
## #42: while a skill key is held past the tap threshold (or a channelled / charged skill is held),
## the local hero sees where the skill will go: the projectile's path to its range and the blast
## where it stops, the area at the aim point inside a range ring, a cone / swing as a sector, a
## line or dash as a band, a ground zone or aura around the hero. The shape comes from the skill's
## data (SkillShape) and follows the same aim the cast would use: the friendly pick for ally
## spells, the enemy lock for aimed attacks, else the cursor / right stick. When the cast can't
## happen (cooldown, cost, target out of reach) the preview turns red and says why. Local only.

const OK := Color(0.62, 0.88, 1.0)
const BAD := Color(1.0, 0.32, 0.26)

var _font: Font


func _ready() -> void:
	_font = UITheme.font()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var lp: Player = game.local_player if game and is_instance_valid(game.local_player) else null
	if lp == null:
		return
	var slot := lp.preview_slot()
	if slot < 0:
		return
	var info := lp.preview_info(slot)
	var col: Color = BAD if not str(info.why).is_empty() else OK
	var t := Time.get_ticks_msec() / 1000.0
	for pr in primitives(info.shape, info.origin, info.aim):
		_render(pr, col, t)
	if not str(info.why).is_empty():
		_label(Vector2(info.aim) + Vector2(0, -16), Loc.t(str(info.why)), col)


## The drawing of a skill shape aimed from `origin` at `aim`: an array of
## {t: "band" | "disc" | "ring" | "sector" | "reticle" | "arrow", ...} in world coordinates.
static func primitives(shape: Dictionary, origin: Vector2, aim: Vector2) -> Array:
	var out: Array = []
	var dir := (aim - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var rng := float(shape.get("range", 0.0))
	var radius := float(shape.get("radius", 0.0))
	var clamped := origin + (aim - origin).limit_length(rng)
	match str(shape.get("kind", "self")):
		"projectile":
			var count := maxi(int(shape.get("count", 1)), 1)
			var spread := deg_to_rad(float(shape.get("spread", 0.0)))
			for i in count:
				var a := 0.0 if count == 1 else -spread / 2.0 + spread * float(i) / float(count - 1)
				var d := dir.rotated(a)
				var end := clamped if shape.get("lob", false) else origin + d * rng
				out.append({"t": "band", "a": origin, "b": end, "w": maxf(float(shape.get("width", 8.0)), 4.0), "dash": true})
				if radius > 0.0:
					out.append({"t": "disc", "c": end, "r": radius})
				else:
					out.append({"t": "reticle", "c": end, "r": 6.0})
		"melee", "cone":
			out.append({"t": "sector", "c": origin, "dir": dir, "r": rng, "arc": deg_to_rad(float(shape.get("arc", 90.0)))})
		"target", "chain":
			out.append({"t": "ring", "c": origin, "r": rng})
			out.append({"t": "band", "a": origin, "b": clamped, "w": 2.0, "dash": true})
			out.append({"t": "reticle", "c": clamped, "r": 10.0})
			if str(shape.kind) == "chain" and radius > 0.0:
				out.append({"t": "ring", "c": clamped, "r": radius})
		"line":
			out.append({"t": "band", "a": origin, "b": origin + dir * rng, "w": maxf(float(shape.get("width", 16.0)), 4.0), "dash": false})
		"area":
			out.append({"t": "ring", "c": origin, "r": rng})
			out.append({"t": "disc", "c": clamped, "r": maxf(radius, 8.0)})
		"self_area":
			out.append({"t": "disc", "c": origin, "r": maxf(radius, 8.0)})
		"dash":
			var d2 := -dir if shape.get("back", false) else dir
			var end2 := origin + d2 * rng
			out.append({"t": "band", "a": origin, "b": end2, "w": maxf(float(shape.get("width", 18.0)), 4.0), "dash": false})
			out.append({"t": "arrow", "c": end2, "dir": d2})
		"ally":
			out.append({"t": "ring", "c": origin, "r": rng})
			out.append({"t": "reticle", "c": clamped, "r": 14.0})
		_:
			out.append({"t": "ring", "c": origin, "r": 18.0})
	return out


func _render(pr: Dictionary, col: Color, t: float) -> void:
	var fill := Color(col, 0.16)
	var line := Color(col, 0.9)
	match str(pr.t):
		"band":
			var a: Vector2 = pr.a
			var b: Vector2 = pr.b
			var n := (b - a).normalized().orthogonal() * float(pr.w) * 0.5
			var poly := PackedVector2Array([a + n, b + n, b - n, a - n])
			draw_colored_polygon(poly, fill)
			if pr.get("dash", false):
				draw_dashed_line(a, b, line, 1.5, 6.0)
			else:
				draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), line, 1.0)
		"disc":
			draw_circle(pr.c, float(pr.r), fill)
			draw_arc(pr.c, float(pr.r), 0.0, TAU, 40, line, 1.5)
		"ring":
			# A dashed range ring, turning slowly.
			var segs := 36
			for i in segs:
				if i % 2 == 0:
					var a0 := TAU * i / segs + t * 0.3
					draw_arc(pr.c, float(pr.r), a0, a0 + TAU / segs, 4, Color(col, 0.5), 1.0)
		"sector":
			var half := float(pr.arc) * 0.5
			var base := Vector2(pr.dir).angle()
			var pts := PackedVector2Array([pr.c])
			for i in 21:
				pts.append(Vector2(pr.c) + Vector2.from_angle(base - half + float(pr.arc) * i / 20.0) * float(pr.r))
			draw_colored_polygon(pts, fill)
			pts.append(pr.c)
			draw_polyline(pts, line, 1.5)
		"reticle":
			var r := float(pr.r)
			draw_arc(pr.c, r, 0.0, TAU, 20, line, 1.5)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(Vector2(pr.c) + d * (r - 3.0), Vector2(pr.c) + d * (r + 3.0), line, 1.5)
		"arrow":
			var c: Vector2 = pr.c
			var d: Vector2 = pr.dir
			draw_colored_polygon(PackedVector2Array([c + d * 8.0, c - d * 4.0 + d.orthogonal() * 6.0, c - d * 4.0 - d.orthogonal() * 6.0]), line)


func _label(center: Vector2, text: String, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var pos := center - Vector2(w / 2.0, 0)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
