class_name CombatFx
extends Node
## Cosmetic combat effects. Every RPC here is called by the host (authority) on all peers and
## is unreliable unless the effect has a lifetime that must end (projectiles, zones).
## No gameplay state lives here.

const HEIGHT := Vector2(0, -16)  ## projectiles and impacts are drawn at chest height
const GROUND_Z := -8  ## ground effects (zones, traps, AoE rings, telegraphs): above the floor, under every actor

var world: Node2D  ## y-sorted world layer for sprites
var world_ui: CanvasLayer  ## follows the camera, not darkened by the ambient light
var local_focus: Callable  ## returns the local camera focus position

var _projectiles: Dictionary = {}
var _zones: Dictionary = {}
var _tethers: Dictionary = {}  ## id -> {line, a, b}
var _tex_cache: Dictionary = {}


func _tex(key: String) -> Texture2D:
	if not _tex_cache.has(key):
		_tex_cache[key] = GameData.texture(key)
	return _tex_cache[key]


func _light(color: Color, energy: float, scale_: float) -> PointLight2D:
	var l := PointLight2D.new()
	LightLayers.setup_light(l)
	l.texture = _tex("fx.light")
	l.color = color
	l.energy = energy
	l.texture_scale = scale_
	return l


## Host -> all (reliable): a projectile starts flying. Peers simulate it visually.
@rpc("authority", "call_local", "reliable")
func projectile(id: int, sprite_key: String, pos: Vector2, dir: Vector2, speed: float, life: float, light_html: String) -> void:
	if world == null:
		return
	var n := Node2D.new()
	n.position = pos
	n.z_index = 5
	var s := Sprite2D.new()
	s.texture = _tex("projectiles." + sprite_key)
	s.rotation = dir.angle()
	s.position = HEIGHT
	n.add_child(s)
	if not light_html.is_empty():
		var pl := _light(Color.from_string(light_html, Color.WHITE), 0.9, 0.35)
		# Spells light up the dark (and reveal monsters) as they fly.
		LightLayers.register(pl, float(GameData.bal("lighting.spell_projectile_radius")))
		n.add_child(pl)
		s.modulate = Color(1.6, 1.6, 1.6)
	world.add_child(n)
	_projectiles[id] = {"node": n, "vel": dir * speed, "life": life + 0.1}


## Host -> all (reliable): projectile hit something / expired.
@rpc("authority", "call_local", "reliable")
func projectile_end(id: int, pos: Vector2) -> void:
	var p: Dictionary = _projectiles.get(id, {})
	_projectiles.erase(id)
	if p.is_empty():
		return
	p.node.queue_free()
	_puff(pos, Color(1, 0.9, 0.7), 6)


## Host -> all (unreliable): melee swing arc.
@rpc("authority", "call_local", "unreliable")
func melee(pos: Vector2, dir: Vector2, reach: float, _arc: float, fx_key: String) -> void:
	if world == null:
		return
	var a := _anim_sprite("fx." + fx_key)
	if a == null:
		return
	a.position = pos + dir * reach * 0.5 + HEIGHT * 0.5
	a.rotation = dir.angle()
	a.scale = Vector2.ONE * clampf(reach / 40.0, 0.6, 2.4)
	a.z_index = 4
	world.add_child(a)
	a.play("default")
	a.animation_finished.connect(a.queue_free)


## Host -> all (unreliable): AoE impact ring (and explosion).
@rpc("authority", "call_local", "unreliable")
func ring(pos: Vector2, r: float, color_html: String, fx_key: String) -> void:
	if world == null:
		return
	var c := Color.from_string(color_html, Color.WHITE)
	var s := Sprite2D.new()
	s.texture = _tex("fx.ring")
	s.position = pos
	s.modulate = Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.9)
	s.z_index = GROUND_Z
	var base := r / 64.0
	s.scale = Vector2(base, base * 0.75) * 0.5
	world.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2(base, base * 0.75), 0.18).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.45).set_delay(0.1)
	t.chain().tween_callback(s.queue_free)
	if fx_key == "explosion":
		var a := _anim_sprite("fx.explosion")
		if a:
			a.position = pos + HEIGHT * 0.5
			a.scale = Vector2.ONE * clampf(r / 32.0, 1.0, 4.0)
			a.z_index = 4
			world.add_child(a)
			a.play("default")
			a.animation_finished.connect(a.queue_free)
		_puff(pos, c, 18)
	# Every impact flashes light over its area (magic lights up the dark for a moment).
	var l := _light(c, 2.2 if fx_key == "explosion" else 1.3, 1.0)
	LightLayers.register(l, maxf(r, 40.0))
	l.position = pos
	world.add_child(l)
	var lt := l.create_tween()
	lt.tween_property(l, "energy", 0.0, float(GameData.bal("lighting.spell_impact_light_time")))
	lt.tween_callback(l.queue_free)


## Host -> all (unreliable): warning circle for delayed AoEs (meteor, slam, curse).
@rpc("authority", "call_local", "unreliable")
func telegraph(pos: Vector2, r: float, color_html: String, delay: float) -> void:
	if world == null:
		return
	var c := Color.from_string(color_html, Color.RED)
	var s := Sprite2D.new()
	s.texture = _tex("fx.ring")
	s.position = pos
	s.scale = Vector2(r / 64.0, r / 64.0 * 0.75)
	s.modulate = Color(c.r * 1.5, c.g * 1.2, c.b, 0.25)
	s.z_index = GROUND_Z
	world.add_child(s)
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 0.85, delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(s.queue_free)
	var l := _light(c, 0.6, 1.0)
	LightLayers.register(l, r)
	l.position = pos
	world.add_child(l)
	var lt := l.create_tween()
	lt.tween_property(l, "energy", 1.4, delay)
	lt.tween_callback(l.queue_free)


## Host -> all (reliable): persistent ground zone or trap appears.
@rpc("authority", "call_local", "reliable")
func zone(id: int, pos: Vector2, r: float, color_html: String, duration: float, sprite_key: String) -> void:
	if world == null:
		return
	var c := Color.from_string(color_html, Color.WHITE)
	var n := Node2D.new()
	n.position = pos
	n.z_index = GROUND_Z
	if sprite_key.is_empty():
		var s := Sprite2D.new()
		s.texture = _tex("fx.ring")
		s.scale = Vector2(r / 64.0, r / 64.0 * 0.75)
		s.modulate = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.55)
		n.add_child(s)
		var t := s.create_tween().set_loops()
		t.tween_property(s, "modulate:a", 0.3, 0.6)
		t.tween_property(s, "modulate:a", 0.6, 0.6)
		var zl := _light(c, 0.8, 1.0)
		LightLayers.register(zl, r)
		n.add_child(zl)
	else:
		var s2 := Sprite2D.new()
		s2.texture = _tex("props." + sprite_key)
		s2.scale = Vector2(0.6, 0.6)
		s2.modulate = Color(c.r, c.g, c.b, 0.85)
		n.add_child(s2)
		n.add_child(_light(c, 0.4, 0.3))
	world.add_child(n)
	_zones[id] = n
	get_tree().create_timer(duration + 1.0).timeout.connect(func(): zone_end(id))


## Host -> all (reliable).
@rpc("authority", "call_local", "reliable")
func zone_end(id: int) -> void:
	var n: Node = _zones.get(id)
	_zones.erase(id)
	if n and is_instance_valid(n):
		n.queue_free()


## Host -> all (unreliable): floating combat text. kind: damage, crit, hurt, heal, dot, info, xp,
## optionally ":#rrggbb" for the damage type colour (fire, frost, ...).
@rpc("authority", "call_local", "unreliable")
func number(pos: Vector2, text: String, kind: String, args: Array = []) -> void:
	if world_ui == null:
		return
	var l := Label.new()
	l.text = Loc.f(text, args)
	var size := 14
	var color := Color(1, 1, 1)
	var type_color := ""
	if kind.contains(":"):
		type_color = kind.get_slice(":", 1)
		kind = kind.get_slice(":", 0)
	match kind:
		"crit":
			size = 20
			color = Color(1.0, 0.65, 0.15)
			text += "!"
			l.text = text
		"hurt":
			color = Color(1.0, 0.3, 0.25)
		"heal":
			color = Color(0.4, 1.0, 0.45)
		"dot":
			size = 12
			color = Color(0.85, 0.7, 1.0)
		"info":
			size = 12
			color = Color(0.75, 0.75, 0.8)
		"xp":
			size = 13
			color = Color(0.7, 0.5, 1.0)
	if not type_color.is_empty() and kind != "heal":
		color = color.lerp(Color.from_string(type_color, color), 0.75)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos + Vector2(randf_range(-10, 4), -46)
	world_ui.add_child(l)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 26.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.5)
	t.chain().tween_callback(l.queue_free)


## Host -> all (unreliable).
@rpc("authority", "call_local", "unreliable")
func sound(key: String, pos: Vector2) -> void:
	AudioManager.play_sfx_at(key, pos)


## Host -> all (unreliable): screen shake for players near `pos`.
@rpc("authority", "call_local", "unreliable")
func shake(pos: Vector2, strength: float) -> void:
	if local_focus.is_valid():
		var focus: Vector2 = local_focus.call()
		if focus.distance_to(pos) < 520.0:
			EventBus.screen_shake.emit(strength, 0.3)


## Host -> all (unreliable).
@rpc("authority", "call_local", "unreliable")
func blink(from: Vector2, to: Vector2) -> void:
	_puff(from, Color(0.7, 0.5, 1.0), 14)
	_puff(to, Color(0.7, 0.5, 1.0), 14)


## Host -> all (reliable): the wind-up of a monster leap or charge (#2). kind "circle" marks the
## landing spot `b` (radius r), "line" the path a -> b (width r); it fills in over `duration` s.
## Peers count markers in the "windup_markers" meta (test harness).
@rpc("authority", "call_local", "reliable")
func windup_marker(kind: String, a: Vector2, b: Vector2, r: float, duration: float, color_html: String) -> void:
	set_meta("windup_markers", int(get_meta("windup_markers", 0)) + 1)
	if world == null:
		return
	var c := Color.from_string(color_html, Color.RED)
	var root := Node2D.new()
	root.z_index = GROUND_Z
	root.modulate = Color(1, 1, 1, 0.3)
	world.add_child(root)
	if kind == "line":
		var ln := Line2D.new()
		ln.points = PackedVector2Array([a, b])
		ln.width = r * 2.0
		ln.default_color = Color(c.r * 1.4, c.g, c.b, 0.45)
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		root.add_child(ln)
	var s := Sprite2D.new()
	s.texture = _tex("fx.ring")
	s.position = b
	s.scale = Vector2(r / 64.0, r / 64.0 * 0.75)
	s.modulate = Color(c.r * 1.5, c.g * 1.2, c.b, 1.0)
	root.add_child(s)
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 0.9, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(root.queue_free)


## Host -> all (unreliable): shows a cast bar above an actor.
@rpc("authority", "call_local", "unreliable")
func cast_bar(actor_path: NodePath, duration: float) -> void:
	var a := get_node_or_null(actor_path)
	if a:
		a.set_meta("cast_total", duration)
		a.set_meta("cast_end", Time.get_ticks_msec() / 1000.0 + duration)


func _process(delta: float) -> void:
	_update_tethers()
	for id in _projectiles.keys():
		var p: Dictionary = _projectiles[id]
		p.life -= delta
		if p.life <= 0.0 or not is_instance_valid(p.node):
			if is_instance_valid(p.node):
				p.node.queue_free()
			_projectiles.erase(id)
			continue
		p.node.position += p.vel * delta


func _puff(pos: Vector2, color: Color, amount: int) -> void:
	if world == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos + HEIGHT * 0.5
	p.texture = _tex("fx.spark")
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.45
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 60)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5)
	p.z_index = 4
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _anim_sprite(key: String) -> AnimatedSprite2D:
	return CombatFx.anim_sprite(key, false)


static var _strip_cache: Dictionary = {}


## An additive animated sprite from a one-row strip asset ({path, frames, fps, anchor}); its anchor
## (the effect's origin inside a frame) sits on the node's position.
static func anim_sprite(key: String, loop: bool) -> AnimatedSprite2D:
	var entry := GameData.asset_entry(key)
	if not _strip_cache.has(key):
		_strip_cache[key] = GameData.texture(key)
	var tex: Texture2D = _strip_cache[key]
	if tex == null:
		return null
	var frames := int(entry.get("frames", 1))
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", loop)
	sf.set_animation_speed("default", float(entry.get("fps", 12)))
	var w := tex.get_width() / frames
	for f in frames:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * w, 0, w, tex.get_height())
		sf.add_frame("default", at)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	if entry.has("anchor"):
		var an: Array = entry.anchor
		a.offset = Vector2(w / 2.0 - float(an[0]), tex.get_height() / 2.0 - float(an[1]))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	a.material = mat
	return a


## Host -> all (unreliable): a one-shot effect of `role` (data/fx.json "actor": heal, buff,
## cleanse...) on an actor (#33). Peers that don't have the actor ignore it.
@rpc("authority", "call_local", "unreliable")
func actor_fx(actor_path: NodePath, role: String) -> void:
	var a := get_node_or_null(actor_path)
	if a == null or not a.has_node("ActorFx"):
		return
	a.get_node("ActorFx").play(role)
	var log: Array = get_meta("actor_fx_log", [])
	log.append([String(actor_path), role])
	set_meta("actor_fx_log", log.slice(-50))  # read by the test harness


## Host -> all (unreliable): a line effect (thrust, beam, chain lightning, bolt) from a to b.
@rpc("authority", "call_local", "unreliable")
func beam(a: Vector2, b: Vector2, color_html: String, duration: float, kind: String) -> void:
	if world == null:
		return
	var c := Color.from_string(color_html, Color.WHITE)
	var line := Line2D.new()
	line.width = 5.0 if kind == "beam" else (2.5 if kind in ["chain", "bolt"] else 4.0)
	line.default_color = Color(c.r * 2.4, c.g * 2.4, c.b * 2.4, 1.0)
	if kind == "chain":
		# A white-hot core inside the coloured arc.
		var core := Line2D.new()
		core.width = 1.0
		core.default_color = Color(3, 3, 3)
		line.add_child(core)
		line.set_meta("core", core)
	line.z_index = 5
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat
	if kind == "chain":
		var n := maxi(3, int(a.distance_to(b) / 14.0))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			if i > 0 and i < n:
				p += (b - a).orthogonal().normalized() * randf_range(-6.0, 6.0)
			line.add_point(p + HEIGHT)
		line.get_meta("core").points = line.points
	else:
		line.add_point(a + HEIGHT)
		line.add_point(b + HEIGHT)
	world.add_child(line)
	var l := _light(c, 1.2, 0.6)
	LightLayers.register(l, maxf(40.0, a.distance_to(b) * 0.5))
	l.position = (a + b) / 2.0
	world.add_child(l)
	var t := line.create_tween().set_parallel(true)
	t.tween_property(line, "modulate:a", 0.0, maxf(duration, 0.08)).set_delay(0.05)
	t.tween_property(l, "energy", 0.0, maxf(duration, 0.08) + 0.05)
	t.chain().tween_callback(func():
		line.queue_free()
		l.queue_free())
	_puff(b, c, 5)


## Host -> all (unreliable): an actor leaps (the sprite arcs up and lands).
@rpc("authority", "call_local", "unreliable")
func leap(actor_path: NodePath, duration: float) -> void:
	var a := get_node_or_null(actor_path) as Actor
	if a == null or a.sprite == null:
		return
	var t := a.sprite.create_tween()
	t.tween_property(a.sprite, "position:y", -22.0, duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(a.sprite, "position:y", 0.0, duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Host -> all (reliable): a tether line between two actors appears.
@rpc("authority", "call_local", "reliable")
func tether(id: int, a_path: NodePath, b_path: NodePath, color_html: String) -> void:
	if world == null:
		return
	var line := Line2D.new()
	line.width = 2.0
	var c := Color.from_string(color_html, Color.RED)
	line.default_color = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, 0.85)
	line.z_index = 5
	world.add_child(line)
	_tethers[id] = {"line": line, "a": a_path, "b": b_path}


## Host -> all (reliable).
@rpc("authority", "call_local", "reliable")
func tether_end(id: int) -> void:
	var t: Dictionary = _tethers.get(id, {})
	_tethers.erase(id)
	if not t.is_empty() and is_instance_valid(t.line):
		t.line.queue_free()


## Host -> all (unreliable): a zone that follows its caster or drifts moved.
@rpc("authority", "call_local", "unreliable")
func zone_move(id: int, pos: Vector2) -> void:
	var n: Node = _zones.get(id)
	if n and is_instance_valid(n):
		n.position = pos


func _update_tethers() -> void:
	for id in _tethers.keys():
		var t: Dictionary = _tethers[id]
		var a := get_node_or_null(t.a) as Node2D
		var b := get_node_or_null(t.b) as Node2D
		if a == null or b == null or not is_instance_valid(t.line):
			continue
		t.line.clear_points()
		t.line.add_point(a.global_position + HEIGHT)
		t.line.add_point(b.global_position + HEIGHT)
