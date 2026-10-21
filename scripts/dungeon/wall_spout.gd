extends Node2D
## Wall spout: a pipe or nozzle in a wall that sprays `length` cells into the room on a timer from
## the shared floor clock (deterministic on every peer): Sewers acid spouts, Foundry flame jets.
## The kind's numbers live in balance `hazards.spouts.<kind>`. The host damages actors in the spray.

var cell := Vector2i.ZERO
var dir := Vector2i.DOWN
var phase := 0.0
var length := 3
var _tile := 32
var _pipe: Sprite2D
var _spray: CPUParticles2D
var _warn: CPUParticles2D  ## drips / embers from the mouth just before a spray (#36)
var _glow: PointLight2D
var _on := false
var _hit: Dictionary = {}
var kind := "acid"
var _seen_local := true
var cfg: Dictionary = {}


## #79 (every peer, from its own Visibility): the pipe art is lit from every side only while the
## room it sprays into is in the local hero's sight; out of sight it is shadowed like its wall.
func set_seen_local(seen: bool) -> void:
	if seen == _seen_local:
		return
	_seen_local = seen
	if _pipe:
		_pipe.light_mask = LightLayers.SELF_LIT if seen else LightLayers.LIT


func setup(c: Vector2i, d: Vector2i, tile: int, p: float, spout_kind: String = "acid") -> void:
	kind = spout_kind
	cfg = GameData.bal("hazards.spouts").get(kind, {})
	cell = c
	dir = d
	_tile = tile
	phase = p
	position = Vector2(c * tile) + Vector2(tile, tile) / 2.0
	_pipe = Sprite2D.new()
	_pipe.light_mask = LightLayers.SELF_LIT
	var sc := float(cfg.get("sprite_scale", 1.0))
	_pipe.scale = Vector2(sc, sc)
	_pipe.z_index = 2
	if dir == Vector2i.DOWN:
		# A north wall shows its face: the pipe on it, its mouth at the wall's foot (#36).
		_pipe.texture = GameData.texture(str(cfg.get("sprite", "props.acid_spout")))
		_pipe.position = Vector2(0, float(cfg.get("sprite_y", 0)))
	else:
		# East, west and south walls show their tops: the pipe lies on the wall, drawn mouth-right,
		# turned (or mirrored) so its mouth reaches the room edge.
		_pipe.texture = GameData.texture(str(cfg.get("sprite_top", cfg.get("sprite", "props.acid_spout"))))
		var ts := float(cfg.get("top_scale", sc))
		_pipe.scale = Vector2(ts, ts)
		if dir == Vector2i.LEFT:
			_pipe.flip_h = true
		elif dir == Vector2i.UP:
			_pipe.rotation = -PI / 2.0
		_pipe.position = Vector2(dir) * float(cfg.get("top_offset", 4))
	add_child(_pipe)
	_spray = CPUParticles2D.new()
	_spray.texture = GameData.texture(str(cfg.get("spray_texture", "fx.pixel")))
	_spray.amount = int(cfg.get("spray_amount", 40))
	_spray.lifetime = 0.5
	_spray.emitting = false
	_spray.direction = Vector2(dir)
	# No fall-off: the jet runs straight along its damage strip whichever wall it leaves.
	_spray.gravity = Vector2.ZERO
	_spray.spread = float(cfg.get("spray_spread", 12.0))
	_spray.initial_velocity_min = float(length * tile) * 1.6
	_spray.initial_velocity_max = float(length * tile) * 2.0
	var ss: Array = cfg.get("spray_scale", [1.0, 2.0])
	_spray.scale_amount_min = float(ss[0])
	_spray.scale_amount_max = float(ss[1])
	if str(cfg.get("spray_texture", "")) == "fx.spark":
		var am := CanvasItemMaterial.new()
		am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_spray.material = am
	_spray.color = Color.from_string(str(cfg.get("color", "#b3ff4d")), Color.GREEN) * 1.3
	_spray.position = Vector2(dir) * float(cfg.get("mouth", 10))
	add_child(_spray)
	# The telegraph (#36): in the last `warn_time` seconds before a spray the mouth drips or sparks
	# and its light swells, so players can read the timing.
	var col := Color.from_string(str(cfg.get("color", "#b3ff4d")), Color.GREEN)
	_warn = CPUParticles2D.new()
	_warn.texture = GameData.texture("fx.pixel")
	_warn.amount = 10
	_warn.lifetime = 0.6
	_warn.emitting = false
	_warn.position = _spray.position
	_warn.direction = Vector2(dir)
	_warn.spread = 25.0
	_warn.initial_velocity_min = 4.0
	_warn.initial_velocity_max = 14.0
	_warn.gravity = Vector2(0, float(cfg.get("warn_gravity", 120)))
	_warn.scale_amount_min = 1.0
	_warn.scale_amount_max = 2.0
	_warn.color = col * 1.4
	add_child(_warn)
	_glow = PointLight2D.new()
	LightLayers.setup_light(_glow)
	_glow.texture = GameData.texture("fx.light")
	_glow.color = col
	_glow.energy = 0.0
	LightLayers.register(_glow, float(cfg.get("glow_radius", 40)))
	_glow.position = _spray.position
	add_child(_glow)


func is_on(floor_time: float) -> bool:
	var period := float(cfg.get("period", 5.0))
	var t := fposmod(floor_time / period + phase, 1.0)
	return t < float(cfg.get("on_fraction", 0.35))


## In the last `warn_time` seconds before a spray (deterministic like the spray itself).
func warning(floor_time: float) -> bool:
	var period := float(cfg.get("period", 5.0))
	var t := fposmod(floor_time / period + phase, 1.0)
	return t > 1.0 - float(cfg.get("warn_time", 0.9)) / period


func update_state(floor_time: float) -> void:
	var warn := warning(floor_time)
	_warn.emitting = warn
	var period := float(cfg.get("period", 5.0))
	var t := fposmod(floor_time / period + phase, 1.0)
	var lead := clampf((t - (1.0 - float(cfg.get("warn_time", 0.9)) / period)) / (float(cfg.get("warn_time", 0.9)) / period), 0.0, 1.0) if warn else 0.0
	_glow.energy = 1.6 if is_on(floor_time) else lead * 1.2
	_pipe.modulate = Color(1, 1, 1).lerp(_warn.color, lead * 0.5) if warn else Color.WHITE
	var on := is_on(floor_time)
	if on != _on:
		_on = on
		_spray.emitting = on
		if on:
			AudioManager.play_sfx_at(str(cfg.get("sfx", "acid_hiss")), position)


## The spray covers `length` cells in front of the pipe.
func spray_rect() -> Rect2:
	var start := position + Vector2(dir) * _tile * 0.5
	var end := position + Vector2(dir) * _tile * (length + 0.5)
	var r := Rect2(start, Vector2.ZERO).expand(end)
	return r.grow_individual(_tile * 0.4 if dir.y != 0 else 0.0, _tile * 0.4 if dir.x != 0 else 0.0,
		_tile * 0.4 if dir.y != 0 else 0.0, _tile * 0.4 if dir.x != 0 else 0.0)


func host_damage(actors: Array, floor_time: float) -> void:
	if not is_on(floor_time):
		return
	var r := spray_rect()
	for a in actors:
		if not a.is_targetable() or not r.has_point(a.global_position):
			continue
		if floor_time < float(_hit.get(a, -99.0)) + 0.5:
			continue
		_hit[a] = floor_time
		Combat.instance.deal_damage(Combat.instance.trap_ctx(), a, float(cfg.get("damage", 8)), {"damage_type": str(cfg.get("damage_type", "nature"))})
		if a.status and cfg.has("status"):
			Combat.instance.apply_status(Combat.instance.trap_ctx(), a, str(cfg.status), float(cfg.get("status_time", 4.0)), float(cfg.get("magnitude", 0.0)))
