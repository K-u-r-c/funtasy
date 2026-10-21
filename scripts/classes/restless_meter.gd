class_name RestlessMeter
extends Node2D
## #71 Restless, on every peer: a ring on the floor around a hero that stands still fills toward
## the moment the floor bites (Player.restless against the modifier's still_time). It is amber
## while it builds; at warn_at it turns red, pulses faster and sounds a warning (the telegraph);
## from still_time it burns, with embers rising, until the hero moves. Unshaded and additive, so it
## reads in the dark; it shows nothing on other floors or while the hero moves.

var hero: Player
var _t := 0.0
var _warned := false
var _embers: CPUParticles2D


func _init(p: Player) -> void:
	hero = p
	name = "RestlessMeter"
	z_index = -1
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add


func _ready() -> void:
	_embers = CPUParticles2D.new()
	_embers.texture = GameData.texture("fx.pixel")
	_embers.amount = 14
	_embers.lifetime = 0.8
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_embers.emission_ring_radius = 14.0
	_embers.emission_ring_inner_radius = 10.0
	_embers.scale = Vector2(1.0, 0.5)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 15.0
	_embers.gravity = Vector2(0, -40)
	_embers.initial_velocity_min = 10.0
	_embers.initial_velocity_max = 22.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(2.0, 0.8, 0.3))
	ramp.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	_embers.color_ramp = ramp
	_embers.emitting = false
	_embers.use_parent_material = true
	add_child(_embers)


## Fraction of the way to the bite (0..1+), or -1 when the floor isn't Restless.
func charge() -> float:
	var game := get_tree().get_first_node_in_group("game")
	if game == null or str(game.floor_def.get("mod", "")) != "restless" or hero.life_state != Player.Life.ALIVE:
		return -1.0
	return hero.restless / maxf(float(FloorMods.num(game.floor_def, "still_time", 2.2)), 0.01)


func _process(delta: float) -> void:
	_t += delta
	var c := charge()
	var game := get_tree().get_first_node_in_group("game")
	var warn_frac := 0.55
	if game:
		warn_frac = float(FloorMods.num(game.floor_def, "warn_at", 1.2)) / maxf(float(FloorMods.num(game.floor_def, "still_time", 2.2)), 0.01)
	if c >= warn_frac and not _warned:
		_warned = true
		Telegraph.warned("restless_%d" % hero.peer_id)
		AudioManager.play_sfx_at("restless_warn", hero.global_position)
	elif c < warn_frac:
		_warned = false
	_embers.emitting = c >= 1.0
	visible = c > 0.12
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := charge()
	if c < 0.0:
		return
	var game := get_tree().get_first_node_in_group("game")
	var warn_frac := 0.55
	if game:
		warn_frac = float(FloorMods.num(game.floor_def, "warn_at", 1.2)) / maxf(float(FloorMods.num(game.floor_def, "still_time", 2.2)), 0.01)
	var hot := c >= warn_frac
	var col := UITheme.WARN if hot else UITheme.WARN_SOFT
	var speed := 14.0 if c >= 1.0 else (9.0 if hot else 4.0)
	var pulse := 0.5 + 0.5 * sin(_t * speed)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 40, Color(col, 0.18), 3.0)
	var u := clampf(c, 0.0, 1.0)
	draw_arc(Vector2.ZERO, 22.0, -PI / 2.0, -PI / 2.0 + TAU * u, 40, Color(col, 0.75 + 0.25 * pulse), 3.0)
	if c >= 1.0:
		draw_circle(Vector2.ZERO, 20.0, Color(UITheme.WARN, 0.18 + 0.14 * pulse))
	elif hot:
		draw_circle(Vector2.ZERO, 20.0 * u, Color(UITheme.WARN, 0.08 + 0.08 * pulse))
