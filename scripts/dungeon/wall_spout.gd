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
var _on := false
var _hit: Dictionary = {}
var kind := "acid"
var cfg: Dictionary = {}


func setup(c: Vector2i, d: Vector2i, tile: int, p: float, spout_kind: String = "acid") -> void:
	kind = spout_kind
	cfg = GameData.bal("hazards.spouts").get(kind, {})
	cell = c
	dir = d
	_tile = tile
	phase = p
	position = Vector2(c * tile) + Vector2(tile, tile) / 2.0
	_pipe = Sprite2D.new()
	_pipe.texture = GameData.texture(str(cfg.get("sprite", "props.acid_spout")))
	_pipe.light_mask = LightLayers.SELF_LIT
	add_child(_pipe)
	_spray = CPUParticles2D.new()
	_spray.texture = GameData.texture("fx.pixel")
	_spray.amount = 40
	_spray.lifetime = 0.5
	_spray.emitting = false
	_spray.direction = Vector2(dir)
	_spray.spread = 12.0
	_spray.initial_velocity_min = float(length * tile) * 1.6
	_spray.initial_velocity_max = float(length * tile) * 2.0
	_spray.scale_amount_min = 1.0
	_spray.scale_amount_max = 2.0
	_spray.color = Color.from_string(str(cfg.get("color", "#b3ff4d")), Color.GREEN) * 1.3
	add_child(_spray)


func is_on(floor_time: float) -> bool:
	var period := float(cfg.get("period", 5.0))
	var t := fposmod(floor_time / period + phase, 1.0)
	return t < float(cfg.get("on_fraction", 0.35))


func update_state(floor_time: float) -> void:
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
		Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, float(cfg.get("damage", 8)), {"damage_type": str(cfg.get("damage_type", "nature"))})
		if a.status and cfg.has("status"):
			Combat.instance.apply_status(Combat.instance.env_ctx(0.0), a, str(cfg.status), float(cfg.get("status_time", 4.0)), float(cfg.get("magnitude", 0.0)))
