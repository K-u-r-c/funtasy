class_name PrisonerNpc
extends Node2D
## #72, every peer: the captive in the cage - a hero of the prisoner's class and gender in rags,
## seen through the bars (the cage's art drawn again over it, half transparent), shifting now and
## then. Freed, it disappears as the ally steps out, or (a reward) turns to the rescuer, bows and
## fades away.

var who: Dictionary = {}
var sprite: CharacterSprite
var _bars: Sprite2D
var _t := 0.0
var _gone := false


func setup(pd: Dictionary, cage: Node2D) -> void:
	who = pd
	name = "PrisonerNpc"
	position = Vector2(0, -2)  # a child of the cage: drawn over its floor, under the bars below
	sprite = CharacterSprite.new()
	add_child(sprite)
	var look := FloorEvents.prisoner_look(pd, false)
	var g := str(look.gender)
	sprite.set_layer("body", CharacterSprite.body_key(g))
	for layer in look.appearance:
		sprite.set_look_layer(layer, look.appearance[layer], g)
	sprite.play("idle", Vector2.DOWN)
	sprite.modulate = Color(0.8, 0.8, 0.86)
	# The bars in front of the prisoner.
	var cage_spr: Sprite2D = cage.get("_sprite")
	if cage_spr:
		_bars = Sprite2D.new()
		_bars.texture = cage_spr.texture
		_bars.offset = cage_spr.offset + Vector2(0, -1)
		_bars.modulate = Color(1, 1, 1, 0.62)
		_bars.z_index = 1
		_bars.light_mask = cage_spr.light_mask
		add_child(_bars)


func _process(delta: float) -> void:
	_t += delta
	var game := get_tree().get_first_node_in_group("game")
	var fe: FloorEvents = game.events if game else null
	if fe == null or _gone:
		return
	var ps := fe.st("prisoner")
	if str(ps.get("state", "")) == "freed":
		_gone = true
		if _bars:
			_bars.visible = false
		if str(ps.get("outcome", "")) == "ally":
			visible = false
			return
		sprite.play("cast", Vector2.DOWN, true)
		var tw := create_tween()
		tw.tween_interval(1.6)
		tw.tween_property(self, "modulate:a", 0.0, 1.0)
		tw.tween_callback(func(): visible = false)
		return
	# Now and then the captive shifts and looks around.
	if fmod(_t, 7.0) < delta:
		sprite.play("hit", Vector2.DOWN if randf() < 0.5 else Vector2(0.6, 1.0), true)
