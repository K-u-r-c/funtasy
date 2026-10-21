class_name GroundItem
extends Node2D
## An item lying on the floor, shared by everyone (first come, first served). Spawned by the
## host's MultiplayerSpawner; glows in its rarity color (outline shader + real light +
## sparkles for Rare and above) so it can be spotted from afar.
## #75: loot from a monster, chest or prop flies out of it first: from `from` to where the loot
## rules put it, in a short spinning arc with a trail in its rarity colour (after `delay`, so a
## handful bursts out one after another), bounces once and settles with a puff; its glow and light
## come up as it lands, with a sound per rarity. It can't be picked up until it has landed (the
## host checks is_landed(), the prompt hides it). A named legendary raises a tall orange beam.

const GLOW_SHADER := preload("res://assets/shaders/item_glow.gdshader")
const BEAM_SHADER := preload("res://assets/shaders/legendary_beam.gdshader")

var item: Dictionary = {}
var from := Vector2.INF  ## world point the item flies out of (INF = it was just put down)
var delay := 0.0
var _icon: Sprite2D
var _body: Node2D  ## the icon, light and sparkles (offset along the flight)
var _shadow: Sprite2D
var _light: PointLight2D
var _sparkles: CPUParticles2D
var _trail: CPUParticles2D
var _color := Color.WHITE
var _t := 0.0
var _fly := -1.0  ## seconds since the spawn while flying (-1 = landed)
var _dur := 0.5
var _beam: Sprite2D
var _beam_light: PointLight2D
var _beam_t := -1.0


func setup(data: Dictionary) -> void:
	name = data.name
	position = data.pos
	item = data.item
	from = data.get("from", Vector2.INF)
	delay = float(data.get("delay", 0.0))


static func cfg(key: String) -> Variant:
	return GameData.bal("loot.flight." + key)


## Can it be picked up (it isn't still in the air)?
func is_landed() -> bool:
	return _fly < 0.0


func is_named_legendary() -> bool:
	return not str(item.get("legendary", "")).is_empty()


## Is the legendary beam up (tests)?
func beam_up() -> bool:
	return _beam_t >= 0.0


func _ready() -> void:
	add_to_group("ground_items")
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	_color = Color.from_string(rar.color, Color.WHITE)
	_shadow = Sprite2D.new()
	_shadow.texture = GameData.texture("fx.shadow")
	_shadow.scale = Vector2(0.6, 0.6)
	add_child(_shadow)
	_body = Node2D.new()
	add_child(_body)
	_icon = Sprite2D.new()
	_icon.texture = ItemLooks.icon(item) if GameData.asset_exists(str(item.get("icon", ""))) else GameData.texture("items.backpack")
	_icon.scale = Vector2(0.75, 0.75)
	_icon.position = Vector2(0, -12)
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", _color)
	mat.set_shader_parameter("intensity", 0.5 + 0.25 * int(item.get("rarity", 1)))
	_icon.material = mat
	_body.add_child(_icon)
	_light = PointLight2D.new()
	LightLayers.setup_light(_light)
	_light.texture = GameData.texture("fx.light")
	_light.color = _color
	_light.energy = float(rar.get("light_energy", 0.6))
	_light.texture_scale = 0.45 + 0.08 * int(item.get("rarity", 1))
	_light.position = Vector2(0, -8)
	_light.set_meta("energy", _light.energy)
	_body.add_child(_light)
	if int(item.get("rarity", 1)) >= 3:
		var p := CPUParticles2D.new()
		p.texture = GameData.texture("fx.spark")
		p.amount = 4 + 2 * int(item.rarity)
		p.lifetime = 1.2
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 8.0
		p.direction = Vector2(0, -1)
		p.spread = 20.0
		p.gravity = Vector2(0, -20)
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 12.0
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.7
		p.color = Color(_color.r * 1.6, _color.g * 1.6, _color.b * 1.6)
		p.position = Vector2(0, -8)
		var pm := CanvasItemMaterial.new()
		pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = pm
		_body.add_child(p)
		_sparkles = p
	_t = randf() * TAU
	if from != Vector2.INF and from.distance_to(global_position) > 2.0:
		_start_flight()


func _start_flight() -> void:
	_fly = 0.0
	_dur = float(cfg("time")) + float(cfg("time_per_px")) * from.distance_to(global_position)
	_light.energy = 0.0
	if _sparkles:
		_sparkles.emitting = false
	_trail = CPUParticles2D.new()
	_trail.texture = GameData.texture("fx.pixel")
	_trail.local_coords = false
	_trail.amount = 18
	_trail.lifetime = 0.35
	_trail.scale_amount_min = 1.0
	_trail.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(_color.r * 1.8, _color.g * 1.8, _color.b * 1.8, 0.9))
	ramp.set_color(1, Color(_color, 0.0))
	_trail.color_ramp = ramp
	_trail.position = Vector2(0, -12)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_trail.material = add
	_trail.emitting = false
	_body.add_child(_trail)
	_body.visible = false
	_shadow.visible = false
	_flight_pose(0.0)


## Places the flying item at `ft` (0..1) of its arc.
func _flight_pose(ft: float) -> void:
	var off := from - global_position
	var u := clampf(ft, 0.0, 1.0)
	var ground := off.lerp(Vector2.ZERO, u)
	var h := float(cfg("arc_height")) * 4.0 * u * (1.0 - u)
	_body.position = ground + Vector2(0, -h)
	_icon.rotation = (1.0 - u) * TAU * float(cfg("spins"))
	_shadow.position = ground
	_shadow.scale = Vector2(0.6, 0.6) * (0.5 + 0.5 * u)


func _land() -> void:
	_fly = -1.0
	_body.position = Vector2.ZERO
	_icon.rotation = 0.0
	_shadow.position = Vector2.ZERO
	_shadow.scale = Vector2(0.6, 0.6)
	if _trail:
		_trail.emitting = false
	if _sparkles:
		_sparkles.emitting = true
	# The bounce, then the glow and light come up.
	var tw := create_tween()
	var bh := float(cfg("bounce_px"))
	var bt := float(cfg("bounce_time"))
	tw.tween_property(_body, "position:y", -bh, bt * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y", 0.0, bt * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_light, "energy", float(_light.get_meta("energy")), 0.35)
	_puff()
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	var key := str(rar.get("drop_sfx", "loot_drop_common"))
	if is_named_legendary():
		key = "loot_drop_legendary"
	elif str(item.get("kind", "")) == "gold":
		key = "coin"
	AudioManager.play_sfx_at(key, global_position)
	if is_named_legendary():
		_raise_beam()


## A small puff of dust and sparks where it lands, tinted by its rarity.
func _puff() -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 10 + 2 * int(item.get("rarity", 1))
	p.lifetime = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.gravity = Vector2(0, 40)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.68, 0.58, 0.8).lerp(_color, 0.35))
	ramp.set_color(1, Color(0.4, 0.36, 0.3, 0.0))
	p.color_ramp = ramp
	p.position = Vector2(0, -2)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## #75: the legendary beam: a tall column of orange light over the drop for a few seconds, drawn
## over the fog of war so the whole party sees where it fell, with a strong real light.
func _raise_beam() -> void:
	var h := float(GameData.bal("loot.legendary_beam.height"))
	var w := float(GameData.bal("loot.legendary_beam.width"))
	var col := Color.from_string(str(GameData.bal("loot.legendary_beam.color")), Color(1.0, 0.62, 0.18))
	_beam = Sprite2D.new()
	_beam.texture = GameData.texture("fx.pixel")
	_beam.scale = Vector2(w, h) / Vector2(_beam.texture.get_size())
	_beam.position = Vector2(0, -h / 2.0 + 4.0)
	_beam.z_index = 61  # over the fog (Visibility, z 60)
	var bm := ShaderMaterial.new()
	bm.shader = BEAM_SHADER
	bm.set_shader_parameter("beam_color", col)
	bm.set_shader_parameter("fade", 0.0)
	_beam.material = bm
	add_child(_beam)
	_beam_light = PointLight2D.new()
	LightLayers.setup_light(_beam_light)
	_beam_light.texture = GameData.texture("fx.light")
	_beam_light.color = col
	_beam_light.texture_scale = 1.4
	_beam_light.energy = 0.0
	_beam_light.position = Vector2(0, -10)
	add_child(_beam_light)
	_beam_t = 0.0


func _process(delta: float) -> void:
	if _fly >= 0.0:
		_fly += delta
		var ft := (_fly - delay) / maxf(_dur, 0.01)
		if ft >= 0.0 and not _body.visible:
			_body.visible = true
			_shadow.visible = true
			if _trail:
				_trail.emitting = true
		if ft >= 1.0:
			_land()
		elif ft >= 0.0:
			_flight_pose(ft)
		return
	_t += delta * 2.5
	_icon.position = Vector2(0, -12 + sin(_t) * 2.0)
	if _beam_t >= 0.0:
		_beam_t += delta
		var life := float(GameData.bal("loot.legendary_beam.time"))
		var f := clampf(minf(_beam_t / 0.4, (life - _beam_t) / 1.0), 0.0, 1.0)
		(_beam.material as ShaderMaterial).set_shader_parameter("fade", f)
		_beam_light.energy = 2.2 * f
		if _beam_t >= life:
			_beam.queue_free()
			_beam_light.queue_free()
			_beam_t = -1.0


## `viewer_level` > 0 adds a warning when the viewer is too low level to wear the item.
func interact_text(viewer_level: int = 0) -> String:
	var t := Loc.f("Pick up %s", [Loc.item_name(item)])
	if viewer_level > 0 and ItemGenerator.too_high_level(item, viewer_level):
		t += Loc.f(" (requires level %d)", [int(item.get("req", 1))])
	return t


func interact_pos() -> Vector2:
	return global_position
