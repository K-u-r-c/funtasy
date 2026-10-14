extends Node2D
## Cyclic floor spikes. Every peer animates them from the shared floor clock; the host deals
## environment damage (once per raise) to any actor standing on the cell while they are up.

var cell := Vector2i.ZERO
var phase := 0.0
var is_up := false
var _sprite: Sprite2D
var _tile := 32
var _hit: Array = []


func setup(c: Vector2i, tile: int, p: float) -> void:
	cell = c
	phase = p
	_tile = tile
	position = Vector2(c * tile) + Vector2(tile, tile) / 2.0
	z_index = -9
	_sprite = Sprite2D.new()
	_sprite.texture = GameData.texture("props.spikes_down")
	add_child(_sprite)


func update_state(floor_time: float) -> void:
	var up_t := float(GameData.bal("hazards.spikes_up_time"))
	var down_t := float(GameData.bal("hazards.spikes_down_time"))
	var cycle := up_t + down_t
	var t := fposmod(floor_time + phase * cycle, cycle)
	var up := t < up_t
	if up != is_up:
		is_up = up
		_sprite.texture = GameData.texture("props.spikes_up" if up else "props.spikes_down")
		_hit.clear()
		if up:
			AudioManager.play_sfx_at("spikes", position)


## Host: actors standing on raised spikes take damage once per raise.
func host_damage(actors: Array) -> void:
	if not is_up:
		return
	var rect := Rect2(position - Vector2(_tile, _tile) / 2.0, Vector2(_tile, _tile))
	for a in actors:
		if _hit.has(a) or not a.is_targetable():
			continue
		if rect.has_point(a.global_position):
			_hit.append(a)
			Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, float(GameData.bal("hazards.spikes_damage")))
