extends StaticBody2D
## Environment prop from data/props.json: tables, chairs, crates, barrels (some explosive),
## pillars and chests. Most block movement and line of sight and can be destroyed (host-side
## HP); explosive barrels blow up through the normal damage system.

var type := ""
var prop_id := ""  ## key in Dungeon.props, used by RPCs (independent of the node name)
var def: Dictionary = {}
var hp := 0.0
var opened := false
var _sprite: Sprite2D
var _broken := false
var lever_handle: Sprite2D  ## #51: the swinging arm of a lever (data "lever_art"), else null
var _lever_lamp: Node2D
var _lever_light: PointLight2D
var _lamp_color := Color.RED


func setup(new_type: String, pos: Vector2) -> void:
	type = new_type
	def = GameData.props[type]
	hp = float(def.get("hp", 0))
	position = pos
	var sz: Array = def.get("size", [20, 10])
	collision_layer = 8 if bool(def.get("blocks_sight", true)) else 32
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(sz[0]), float(sz[1]))
	shape.shape = rect
	shape.position = Vector2(0, -float(sz[1]) / 2.0)
	add_child(shape)
	_sprite = Sprite2D.new()
	# Lit and shadowed like the walls and floor (#7); its own shadow line can't fall on it (#46).
	_sprite.light_mask = LightLayers.LIT
	_sprite.texture = GameData.texture(str(def.sprite))
	if _sprite.texture:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 2.0)
	add_child(_sprite)
	if def.has("lever_art"):
		_build_lever(def.lever_art)
	if def.get("flat", false):
		# Floor-level pieces (raised platforms): no collision, drawn under everyone.
		collision_layer = 0
		_sprite.offset = Vector2.ZERO
		_sprite.z_index = -8
		_sprite.light_mask = LightLayers.LIT
	if def.has("light"):
		# Glowing props (fungal blooms) are real light sources.
		var l := PointLight2D.new()
		LightLayers.setup_light(l)
		l.texture = GameData.texture("fx.light")
		l.color = Color.from_string(str(def.light), Color.WHITE)
		l.energy = 0.8
		l.position = Vector2(0, -6)
		LightLayers.register(l, float(def.get("light_radius", 56.0)))
		add_child(l)
	if bool(def.get("blocks_sight", true)):
		# #46: the shadow starts where the prop stands: a one-sided outline of its footprint (west,
		# south and east sides, open to the north) casts for lights beside or behind it, so the
		# shadow falls away on the floor from its foot and never darkens the prop's own art.
		var hw := float(sz[0]) / 2.0
		var fh := float(sz[1])
		add_child(LightLayers.one_sided(PackedVector2Array([Vector2(-hw, -fh), Vector2(-hw, 0), Vector2(hw, 0), Vector2(hw, -fh)])))


func destructible() -> bool:
	return hp > 0.0 and not _broken


func blocks_path() -> bool:
	return type in ["pillar", "table", "chest"]


func interactable() -> bool:
	if def.has("npc") or def.has("gate"):
		return true  # merchants and their doors stay usable
	return bool(def.get("interactable", false)) and not opened


func interact_text() -> String:
	if def.has("npc") or def.has("gate"):
		return Loc.t("%s %s" % [str(def.get("verb", "Open")), str(def.name)])
	# Verb and name form one translation key (tools/i18n_extract.py builds the same).
	return Loc.t("%s %s" % [str(def.get("verb", "Open")), str(def.name).to_lower()])


func interact_pos() -> Vector2:
	return global_position


## Host only: damage from any source. `ctx` is the attacker context from Combat.
func take_damage(amount: float, ctx: Dictionary) -> void:
	if not multiplayer.is_server() or not destructible() or amount <= 0.0:
		return
	# Boss-made cages and the like: only the heroes can break them.
	if def.get("players_only", false) and int(ctx.get("team", Actor.Team.PLAYERS)) != Actor.Team.PLAYERS:
		return
	hp -= amount
	if hp > 0.0:
		return
	_broken = true
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	game.dungeon.destroy_prop.rpc(prop_id)
	game.on_prop_broken(self)
	if def.has("explode"):
		var ex: Dictionary = def.explode
		# A barrel is a hazard: the blast hurts everyone in range (players included, whoever broke
		# it). The player who broke it still gets the XP contribution for monsters it hits.
		var ectx: Dictionary = Combat.instance.env_ctx(float(ex.damage))
		ectx.peer = int(ctx.get("peer", 0))
		var eff := {"type": "aoe", "radius": float(ex.radius), "damage": {"base": 0, "coef": 1.0},
			"color": ex.get("color", "#ff7722"), "fx": ex.get("fx", "explosion"), "shake": ex.get("shake", 4),
			"damage_type": str(ex.get("damage_type", "fire"))}
		Combat.instance.apply_aoe.call_deferred(eff, ectx, global_position)
	elif randf() < float(def.get("drop_chance", 0.0)):
		game.loot.roll_and_drop(str(def.get("loot", "prop")), global_position)


## Every peer: replace the prop with debris.
func break_apart() -> void:
	_broken = true
	collision_layer = 0
	AudioManager.play_sfx_at(str(def.get("sfx", "break")), global_position)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = 18
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.spread = 180.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 180)
	p.color = Color(0.45, 0.32, 0.2)
	p.position = Vector2(0, -10)
	add_child(p)
	p.emitting = true
	for c in get_children():
		if c is LightOccluder2D or c is PointLight2D:
			c.queue_free()
	if bool(def.get("debris", false)):
		_sprite.texture = GameData.texture("props.debris")
		_sprite.offset = Vector2(0, -8)
		_sprite.z_index = -5
	else:
		_sprite.visible = false


func set_opened() -> void:
	opened = true
	if lever_handle:
		_pull_lever()
		return
	if def.has("sprite_open"):
		_sprite.texture = GameData.texture(str(def.sprite_open))
	if def.has("light_open"):
		# A lit shrine / brazier becomes a real light source.
		var l := PointLight2D.new()
		LightLayers.setup_light(l)
		l.texture = GameData.texture("fx.light")
		l.color = Color.from_string(str(def.light_open), Color.WHITE)
		l.energy = 1.0
		l.position = Vector2(0, -16)
		LightLayers.register(l, 72.0)
		add_child(l)
	AudioManager.play_sfx_at("pickup", global_position)


# --- Levers (#51) ------------------------------------------------------------------------------


## A lever from data "lever_art": the housing (the prop's sprite), an arm that swings about a
## pivot on top and a signal lamp on the front, red while off and green once pulled. Pivot and
## lamp are pixels of the housing's art; angles are degrees from upright.
func _build_lever(art: Dictionary) -> void:
	var sc := float(art.get("scale", 1.0))
	_sprite.texture = GameData.texture(str(art.base))
	_sprite.scale = Vector2(sc, sc)
	var tex_size := _sprite.texture.get_size() if _sprite.texture else Vector2(48, 48)
	_sprite.offset = Vector2(0, -tex_size.y / 2.0 + 2.0)
	var to_node := func(px: Array) -> Vector2:
		return (Vector2(float(px[0]), float(px[1])) - Vector2(tex_size.x / 2.0, tex_size.y - 2.0)) * sc
	lever_handle = Sprite2D.new()
	lever_handle.light_mask = LightLayers.LIT
	lever_handle.texture = GameData.texture(str(art.handle))
	lever_handle.centered = false
	var hp: Array = art.get("handle_pivot", [16, 61])
	lever_handle.offset = -Vector2(float(hp[0]), float(hp[1]))
	var hs: Variant = art.get("handle_scale", 0.5)  # a number, or [x, y] to thicken a thin arm
	lever_handle.scale = Vector2(float(hs[0]), float(hs[1])) if hs is Array else Vector2(float(hs), float(hs))
	lever_handle.position = to_node.call(art.get("pivot", [24, 8]))
	lever_handle.rotation_degrees = float(art.get("off", -30))
	add_child(lever_handle)
	_lamp_color = Color.from_string(str(art.get("off_color", "#ff3a2a")), Color.RED)
	_lever_lamp = Node2D.new()
	_lever_lamp.position = to_node.call(art.get("lamp", [16, 19]))
	var unshaded := CanvasItemMaterial.new()
	unshaded.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_lever_lamp.material = unshaded
	_lever_lamp.draw.connect(_draw_lamp)
	add_child(_lever_lamp)
	# Readable from across the room, but not a gameplay light (it doesn't light up monsters).
	_lever_light = PointLight2D.new()
	LightLayers.setup_light(_lever_light)
	_lever_light.texture = GameData.texture("fx.light")
	_lever_light.color = _lamp_color
	_lever_light.energy = 0.9
	_lever_light.texture_scale = 48.0 / LightLayers.PX_PER_SCALE
	_lever_light.position = _lever_lamp.position
	add_child(_lever_light)


func _ready() -> void:
	set_process(lever_handle != null)  # only a lever's lamp pulses


func _process(_delta: float) -> void:
	_lever_lamp.queue_redraw()


func _draw_lamp() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var p := 0.75 + 0.25 * sin(t * (2.0 if opened else 5.0))
	_lever_lamp.draw_circle(Vector2.ZERO, 6.0, Color(_lamp_color, 0.25 * p))
	_lever_lamp.draw_circle(Vector2.ZERO, 2.5, Color(_lamp_color * 1.8, p))


## The pull, on every peer: the arm is hauled back a little, then thrown over to "on" with a clunk,
## dust and sparks fly from the pivot and the lamp flashes from red to green.
func _pull_lever() -> void:
	var art: Dictionary = def.lever_art
	set_meta("lever_pulls", int(get_meta("lever_pulls", 0)) + 1)  # read by the tests
	var on := float(art.get("on", 60))
	var tw := create_tween()
	tw.tween_property(lever_handle, "rotation_degrees", float(art.get("off", -30)) - 12.0, 0.12)
	tw.tween_property(lever_handle, "rotation_degrees", on, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_lamp_color = Color.from_string(str(art.get("on_color", "#4dff6a")), Color.GREEN)
		_lever_light.color = _lamp_color
		_lever_light.energy = 2.4
		create_tween().tween_property(_lever_light, "energy", 1.1, 0.6)
		_lever_puff(lever_handle.position, Color(0.5, 0.42, 0.32), 14, 30.0, 0.7)
		_lever_puff(lever_handle.position, Color(2.0, 1.2, 0.4), 10, 80.0, 0.35)
		AudioManager.play_sfx_at("lever", global_position))


func _lever_puff(at: Vector2, color: Color, amount: int, speed: float, life: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 60)
	p.color = color
	p.position = at
	p.z_index = 1
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
