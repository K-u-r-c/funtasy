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
	# Lit and shadowed like the walls and floor (#7); its own occluder sits at the top of the
	# sprite (below), so it never shadows the prop itself.
	_sprite.light_mask = LightLayers.LIT
	_sprite.texture = GameData.texture(str(def.sprite))
	if _sprite.texture:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 2.0)
	add_child(_sprite)
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
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var hw := float(sz[0]) / 2.0
		# A thin band across the top of the drawn sprite (the footprint when there is no art):
		# light from the front reaches the whole prop, light from behind is blocked by it.
		var top := -float(_sprite.texture.get_height()) + 2.0 if _sprite.texture else -float(sz[1])
		poly.polygon = PackedVector2Array([Vector2(-hw, top), Vector2(hw, top), Vector2(hw, top + 4.0), Vector2(-hw, top + 4.0)])
		occ.occluder = poly
		add_child(occ)


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
