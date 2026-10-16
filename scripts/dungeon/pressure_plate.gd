extends Node2D
## Crypt pressure plate (GDD 1.1): stepping on it raises floor spikes on the plate and the cells
## around it after a short delay. Every peer shows the plate; the host detects the step, deals
## the environment damage and tells everyone to show the spikes (show_spikes RPC on Dungeon).

var cell := Vector2i.ZERO
var plate_id := ""
var _tile := 32
var _sprite: Sprite2D
var _spikes: Array = []
var _cooldown := 0.0
var _armed_left := -1.0


func setup(c: Vector2i, tile: int, id: String) -> void:
	cell = c
	_tile = tile
	plate_id = id
	position = Vector2(c * tile) + Vector2(tile, tile) / 2.0
	z_index = -9
	_sprite = Sprite2D.new()
	_sprite.texture = GameData.texture("props.pressure_plate")
	add_child(_sprite)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var s := Sprite2D.new()
			s.texture = GameData.texture("props.spikes_up")
			s.position = Vector2(dx, dy) * tile
			s.visible = false
			add_child(s)
			_spikes.append(s)


## Host, every physics frame.
func host_tick(delta: float, actors: Array, dungeon: Node) -> void:
	_cooldown -= delta
	if _armed_left >= 0.0:
		_armed_left -= delta
		if _armed_left < 0.0:
			_erupt(actors, dungeon)
		return
	if _cooldown > 0.0:
		return
	var plate := Rect2(position - Vector2(_tile, _tile) * 0.4, Vector2(_tile, _tile) * 0.8)
	for a in actors:
		if a.is_targetable() and plate.has_point(a.global_position) and not a.status.has_flag("trap_immune") \
				and not a.stats.has_flag("no_plates") and a.team == Actor.Team.PLAYERS:
			_armed_left = float(GameData.bal("hazards.plate_delay", 0.35))
			dungeon.plate_click.rpc(plate_id)
			return


func _erupt(actors: Array, dungeon: Node) -> void:
	_cooldown = float(GameData.bal("hazards.plate_cooldown", 4.0))
	dungeon.show_plate_spikes.rpc(plate_id)
	var area := Rect2(position - Vector2(_tile, _tile) * 1.5, Vector2(_tile, _tile) * 3.0)
	for a in actors:
		if a.is_targetable() and area.has_point(a.global_position):
			Combat.instance.deal_damage(Combat.instance.env_ctx(0.0), a, float(GameData.bal("hazards.spikes_damage")))


## Every peer: the plate sinks with a click.
func click() -> void:
	AudioManager.play_sfx_at("plate_click", position)
	var t := _sprite.create_tween()
	t.tween_property(_sprite, "position:y", 1.0, 0.05)
	t.tween_interval(0.6)
	t.tween_property(_sprite, "position:y", 0.0, 0.1)


## Every peer: spikes stand up around the plate for a moment.
func show_spikes() -> void:
	AudioManager.play_sfx_at("spikes", position)
	for s in _spikes:
		s.visible = true
	get_tree().create_timer(0.8).timeout.connect(func():
		for s in _spikes:
			if is_instance_valid(s):
				s.visible = false)
