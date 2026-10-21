class_name GameplayFx
extends RefCounted
## #81: effects that show what happens in a fight, drawn on every peer from one host message
## (CombatFx.gfx) or from replicated state. Kept restrained (short, small, mostly additive and
## unshaded so they read in the dark) so a four-hero fight stays readable; the numbers live in
## data/fx.json "gameplay". `log` counts every effect a peer drew (the tests read it).

static var log: Dictionary = {}  ## kind -> count drawn on this peer
static var _last_stop := -100000


static func cfg(kind: String) -> Dictionary:
	return GameData.fx.get("gameplay", {}).get(kind, {})


static func col(kind: String, fallback: String = "#ffffff") -> Color:
	return Color.from_string(str(cfg(kind).get("color", fallback)), Color.WHITE)


static func note(kind: String) -> void:
	log[kind] = int(log.get(kind, 0)) + 1


static func _add_mat(n: CanvasItem) -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	n.material = m


## A one-shot particle burst at `pos` under `world`.
static func burst(world: Node, pos: Vector2, color: Color, amount: int, speed: float, spread: float = 180.0, dir: Vector2 = Vector2.UP, gravity: Vector2 = Vector2.ZERO, life: float = 0.4, size: float = 1.5) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	_add_mat(p)
	p.position = pos
	p.z_index = 6
	world.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A short glowing line (a slash streak, a spark arc, a beam) that fades.
static func streak(world: Node, a: Vector2, b: Vector2, color: Color, width: float, life: float) -> void:
	var l := Line2D.new()
	l.points = PackedVector2Array([a, b])
	l.width = width
	l.default_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0.2))
	wc.add_point(Vector2(0.5, 1.0))
	wc.add_point(Vector2(1, 0.2))
	l.width_curve = wc
	_add_mat(l)
	l.z_index = 7
	world.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, life)
	tw.tween_callback(l.queue_free)


## Translucent copies of an actor's current frame, fading (dodge roll, dodge-chance blur).
static func afterimage(world: Node, actor: Node2D, tint: Color, life: float, offset: Vector2 = Vector2.ZERO) -> void:
	var cs: Node = actor.get("sprite")
	if cs == null or not cs.is_visible_in_tree():
		return
	var ghost := Node2D.new()
	ghost.global_position = actor.global_position + offset
	ghost.z_index = -1
	ghost.y_sort_enabled = false
	for c in cs.get_children():
		if c is AnimatedSprite2D and c.visible and c.sprite_frames and c.sprite_frames.has_animation(c.animation):
			var s := Sprite2D.new()
			s.texture = c.sprite_frames.get_frame_texture(c.animation, c.frame)
			s.centered = c.centered
			s.offset = c.offset
			s.flip_h = c.flip_h
			s.position = c.position * cs.scale + cs.position
			s.scale = c.scale * cs.scale
			s.modulate = Color(tint, tint.a)
			ghost.add_child(s)
	if ghost.get_child_count() == 0:
		ghost.free()
		return
	_add_mat(ghost)
	world.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, life)
	tw.tween_callback(ghost.queue_free)


# --- the host's events (CombatFx.gfx) ----------------------------------------------------------


static func play(world: Node, kind: String, d: Dictionary) -> void:
	if world == null:
		return
	note(kind)
	var a: Node2D = world.get_node_or_null(NodePath(str(d.get("a", "")))) as Node2D if d.has("a") else null
	var pos: Vector2 = d.get("pos", a.global_position if a else Vector2.ZERO)
	var dir: Vector2 = d.get("dir", Vector2.RIGHT)
	var c := col(kind)
	match kind:
		"avoid":
			# The target blurs sideways with an afterimage; the hit passes through.
			if a:
				var side := dir.orthogonal().normalized() * float(cfg(kind).get("shift", 7.0))
				afterimage(world, a, Color(c, 0.55), 0.3)
				var cs: Node2D = a.get("sprite")
				if cs:
					var tw := cs.create_tween()
					tw.tween_property(cs, "position:x", side.x, 0.06)
					tw.tween_property(cs, "position:x", 0.0, 0.16)
				burst(world, pos + Vector2(0, -14), c, 6, 40.0, 30.0, -dir)
		"parry", "block":
			# A spark flash and a bright arc at the contact point; a block glints on the shield.
			var at: Vector2 = pos + Vector2(0, -14) + dir.normalized() * 10.0
			burst(world, at, c, 12 if kind == "parry" else 8, 90.0, 70.0, -dir, Vector2(0, 120), 0.3)
			var n := dir.orthogonal().normalized() * 9.0
			streak(world, at - n, at + n - dir.normalized() * 4.0, c, 3.0, 0.18)
			if kind == "block" and a:
				streak(world, at + Vector2(-5, -6), at + Vector2(5, 6), Color(1, 1, 1), 1.5, 0.12)
		"crit":
			var t: Node2D = a
			var s := dir.normalized().rotated(0.5) * float(cfg(kind).get("streak", 18.0))
			var hp := pos + Vector2(0, -16)
			streak(world, hp - s, hp + s, c, 4.0, 0.16)
			burst(world, hp, Color(1, 1, 1), 8, 70.0, 180.0)
			if t and bool(d.get("local", false)):
				hit_stop(world, float(cfg(kind).get("hit_stop", 0.05)))
		"leech":
			# Red motes flow from the target into the hero.
			var to: Node2D = world.get_node_or_null(NodePath(str(d.get("b", "")))) as Node2D
			if to:
				_motes(world, pos + Vector2(0, -14), to, c, int(cfg(kind).get("motes", 5)), 0.45)
		"absorb_hit":
			if a:
				_hex_ripple(world, a, c)
		"reflect":
			var to2: Vector2 = d.get("to", pos)
			var dv := (to2 - pos).normalized()
			for i in 3:
				var off := dv.orthogonal() * (i - 1) * 6.0
				streak(world, pos + Vector2(0, -14) + off, pos + Vector2(0, -14) + off + dv * 22.0, c, 2.0, 0.2)
		"interrupt":
			# The cast bar shatters into shards.
			if a:
				for i in 8:
					var v := Vector2.from_angle(randf() * TAU) * randf_range(30, 70)
					burst(world, a.global_position + Vector2(randf_range(-14, 14), -52), c, 2, 60.0, 180.0, v.normalized(), Vector2(0, 160), 0.45, 2.0)
		"knock":
			# A dust trail along the push and a puff where it ends.
			if a:
				_trail(world, a, Color("b8a890"), float(d.get("time", 0.35)))
		"taunt":
			var to3: Node2D = world.get_node_or_null(NodePath(str(d.get("b", "")))) as Node2D
			if a and to3:
				streak(world, a.global_position + Vector2(0, -16), to3.global_position + Vector2(0, -16), c, 3.0, 0.35)
				burst(world, to3.global_position + Vector2(0, -20), c, 10, 50.0)
		"xp":
			# Motes fly from the killed monster to each hero who earned the experience.
			for path in d.get("to", []):
				var h: Node2D = world.get_node_or_null(NodePath(str(path))) as Node2D
				if h:
					_motes(world, pos + Vector2(0, -14), h, c, int(cfg(kind).get("motes", 4)), 0.7)
		"miss":
			# The blow whiffs past: a pale streak beside the target.
			var side := dir.orthogonal().normalized() * 10.0
			streak(world, pos + Vector2(0, -14) + side - dir * 14.0, pos + Vector2(0, -14) + side + dir * 14.0, c, 1.5, 0.16)
		"immune", "resist":
			# A brief ward ring on the target: this hit didn't (fully) land.
			if a:
				var n := Node2D.new()
				n.position = a.global_position + Vector2(0, -16)
				n.z_index = 7
				_add_mat(n)
				world.add_child(n)
				n.draw.connect(func(): n.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(c, 0.85), 2.0))
				var tw2 := n.create_tween()
				tw2.tween_property(n, "scale", Vector2(1.4, 1.4), 0.25)
				tw2.parallel().tween_property(n, "modulate:a", 0.0, 0.25)
				tw2.tween_callback(n.queue_free)
		"saved":
			# A killing blow turned aside: a golden burst on the hero.
			if a:
				burst(world, a.global_position + Vector2(0, -16), c, 24, 80.0)
		"knock_land":
			burst(world, pos, Color("b8a890"), 10, 40.0, 70.0, Vector2.UP, Vector2(0, 40), 0.45, 2.0)


## Motes that home onto `to` (follow it as it moves) and vanish into it.
static func _motes(world: Node, from: Vector2, to: Node2D, c: Color, n: int, life: float) -> void:
	for i in n:
		var m := Sprite2D.new()
		m.texture = GameData.texture("fx.light")
		m.scale = Vector2(0.035, 0.035)
		m.modulate = Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 0.95)
		_add_mat(m)
		m.z_index = 8
		m.global_position = from + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		world.add_child(m)
		var start := m.global_position
		var bend := Vector2(randf_range(-30, 30), randf_range(-40, -10))
		var delay := i * 0.05
		var tw := m.create_tween()
		tw.tween_interval(delay)
		tw.tween_method(func(u: float):
			if not is_instance_valid(to):
				return
			var end := to.global_position + Vector2(0, -16)
			var mid := (start + end) / 2.0 + bend
			m.global_position = start.lerp(mid, u).lerp(mid.lerp(end, u), u)
			m.scale = Vector2(0.035, 0.035) * (1.0 - 0.5 * u), 0.0, 1.0, life)
		tw.tween_callback(m.queue_free)


## A hexagon ripple over an actor's shield bubble.
static func _hex_ripple(world: Node, a: Node2D, c: Color) -> void:
	var n := Node2D.new()
	n.global_position = a.global_position + Vector2(0, -16)
	n.z_index = 7
	_add_mat(n)
	world.add_child(n)
	var tw := n.create_tween()
	var draw := func(u: float):
		n.queue_redraw()
		n.set_meta("u", u)
	n.draw.connect(func():
		var u := float(n.get_meta("u", 0.0))
		var r := 10.0 + 14.0 * u
		for k in 2:
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(TAU * i / 6.0 + k * 0.5) * r * (1.0 - 0.25 * k) * Vector2(1.0, 0.9))
			n.draw_polyline(pts, Color(c, (1.0 - u) * 0.9), 1.5))
	tw.tween_method(draw, 0.0, 1.0, 0.35)
	tw.tween_callback(n.queue_free)


## Dust kicked up behind a pushed actor for `t` seconds, then a landing puff.
static func _trail(world: Node, a: Node2D, c: Color, t: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.local_coords = false
	p.amount = 16
	p.lifetime = 0.45
	p.direction = Vector2.UP
	p.spread = 60.0
	p.gravity = Vector2(0, 30)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 18.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c, 0.8))
	ramp.set_color(1, Color(c, 0.0))
	p.color_ramp = ramp
	a.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		p.emitting = false
		if is_instance_valid(a):
			burst(world, a.global_position, c, 10, 40.0, 70.0, Vector2.UP, Vector2(0, 40), 0.45, 2.0))
	tw.tween_interval(0.5)
	tw.tween_callback(p.queue_free)


## A very short hit-stop on this peer (a crit by or on the local hero), off with Settings.
## Never on a host with clients (time_scale would slow the authoritative world for everyone)
## and at most once per `crit.hit_stop_every` so a crit build doesn't stutter.
static func hit_stop(world: Node, seconds: float) -> void:
	if not Settings.screen_shake or seconds <= 0.0 or Engine.time_scale < 1.0:
		return
	var mp := world.get_tree().get_multiplayer()
	if mp.has_multiplayer_peer() and mp.is_server() and not mp.get_peers().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_stop < int(float(cfg("crit").get("hit_stop_every", 0.4)) * 1000.0):
		return
	_last_stop = now
	note("hit_stop")
	Engine.time_scale = 0.05
	world.get_tree().create_timer(seconds, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


## #81 16: a short-lived mark on the floor where an elemental hit or area landed.
static func decal(world: Node, pos: Vector2, element: String, r: float) -> void:
	var spec: Dictionary = GameData.fx.get("gameplay", {}).get("decals", {}).get(element, {})
	if spec.is_empty() or world == null:
		return
	note("decal_" + element)
	var n := Node2D.new()
	n.position = pos
	n.z_index = -3
	var c := Color.from_string(str(spec.get("color", "#000000")), Color.BLACK)
	var rr := clampf(r * float(spec.get("size", 0.6)), 10.0, 60.0)
	var seed_v := randi()
	n.draw.connect(func():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		n.draw_circle(Vector2.ZERO, rr, Color(c, float(spec.get("alpha", 0.35))))
		for i in 7:
			var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rr * 0.4, rr)
			n.draw_circle(v, rng.randf_range(2.0, rr * 0.35), Color(c, float(spec.get("alpha", 0.35)) * 0.8)))
	if bool(spec.get("glow", false)):
		_add_mat(n)
	world.add_child(n)
	var tw := n.create_tween()
	tw.tween_interval(float(spec.get("time", 5.0)))
	tw.tween_property(n, "modulate:a", 0.0, 1.5)
	tw.tween_callback(n.queue_free)
