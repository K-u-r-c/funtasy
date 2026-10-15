extends Node2D
## Wall torch: sprite + flickering shadow-casting light + embers. Players can take it (it then
## burns in their hand for a while) or break it with an attack; either way the wall goes dark.
## The host decides, then Dungeon.set_torch_state broadcasts the new state by torch id.

enum State { LIT, TAKEN, BROKEN }

var torch_id := ""
var state: int = State.LIT
var color := Color(1.0, 0.6, 0.27)
var light: PointLight2D
var _sprite: Sprite2D
var _embers: CPUParticles2D
var _t := 0.0
var _base_energy := 1.15


func _ready() -> void:
	_t = randf() * 10.0
	_base_energy = float(GameData.bal("lighting.wall_torch_energy"))
	_sprite = Sprite2D.new()
	_sprite.texture = GameData.texture("props.torch")
	_sprite.offset = Vector2(0, -14)
	_sprite.light_mask = LightLayers.SELF_LIT
	add_child(_sprite)
	light = PointLight2D.new()
	LightLayers.setup_light(light)
	light.texture = GameData.texture("fx.light")
	light.color = color
	light.energy = _base_energy
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	light.position = Vector2(0, 8)
	LightLayers.register(light, float(GameData.bal("lighting.wall_torch_radius")))
	add_child(light)
	_embers = CPUParticles2D.new()
	_embers.texture = GameData.texture("fx.pixel")
	_embers.amount = 6
	_embers.lifetime = 0.9
	_embers.position = Vector2(0, -22)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 25.0
	_embers.gravity = Vector2(0, -30)
	_embers.initial_velocity_min = 6.0
	_embers.initial_velocity_max = 16.0
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.0
	_embers.color = Color(1.6, 0.8, 0.3)
	add_child(_embers)
	_apply_state()


func is_lit() -> bool:
	return state == State.LIT


func interactable() -> bool:
	return is_lit()


func interact_text() -> String:
	return "Take the torch"


func interact_pos() -> Vector2:
	return global_position + Vector2(0, 10)


func destructible() -> bool:
	return is_lit()


## Host only: any hit puts the torch out for good.
func take_damage(amount: float, _ctx: Dictionary) -> void:
	if not multiplayer.is_server() or not is_lit() or amount <= 0.0:
		return
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.dungeon.set_torch_state.rpc(torch_id, State.BROKEN)


## Every peer.
func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	_apply_state()
	AudioManager.play_sfx_at("break" if state == State.BROKEN else "pickup", global_position)


func _apply_state() -> void:
	var lit := is_lit()
	light.visible = lit
	_embers.emitting = lit
	if lit:
		_sprite.modulate = Color.WHITE
		_sprite.visible = true
	elif state == State.TAKEN:
		_sprite.visible = false
	else:
		_sprite.modulate = Color(0.25, 0.22, 0.22)


func _process(delta: float) -> void:
	if not is_lit() or not light.enabled:
		return
	_t += delta
	light.energy = _base_energy + sin(_t * 9.0) * 0.06 + sin(_t * 23.0) * 0.04
