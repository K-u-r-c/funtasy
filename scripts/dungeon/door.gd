extends StaticBody2D
## Door filling a 2-3 cell opening in a room wall. Closed doors block movement, projectiles and
## sight (LightOccluder2D + "doors" physics layer). Players toggle them with Interact; the host
## owns the state and broadcasts it. Simple monsters open closed doors after a short delay.
## The one door of the boss chamber and of the merchant room has a type from data/doors.json
## (#23 / #31): its own art and warning light, and a merchant door starts sealed until it is
## paid for at the door (Merchants.host_door). A sealed door can't be opened by anything.
##
## RPCs: _sync_open(open), _sync_seal(sealed): host -> all, reliable, call_local.

var cells: Array = []
var vertical := false
var is_open := false
var monster_proof := false  ## merchant chamber doors: monsters never open them
var floodgate := false  ## Sewers: rusted shut until a lever beside it is pulled
var style := ""  ## "bookshelf": an Archives revolving bookshelf door (D34)
var kind := ""  ## "boss" / "merchant": the one door of a sealed leaf chamber (#23 / #31)
var door_type := ""  ## data/doors.json entry: "boss", "archibald", "malphas" ("" = an ordinary door)
var type_def: Dictionary = {}
var sealed := false  ## locked until paid for at the door (#23)
var biome := ""
var light: PointLight2D
var _t := 0.0
var _art_top: Sprite2D  ## the part of a typed door's art above its wall row, drawn over the fog
var _room := Rect2i()  ## cells of the chamber behind a typed door
const ART_LOW := 34  ## px of a typed door's art drawn in the y-sorted world (wall row + sill)
var world_rect := Rect2()
var _shape: CollisionShape2D
var _occluder: Node2D  ## the door's one-sided shadow lines (#46), hidden while open
var _sprites: Node2D


func setup(d: Dictionary, tile: int) -> void:
	cells = d.cells
	vertical = d.vertical
	monster_proof = bool(d.get("monster_proof", false))
	floodgate = bool(d.get("floodgate", false))
	style = str(d.get("style", ""))
	kind = str(d.get("kind", ""))
	door_type = str(d.get("type", ""))
	biome = str(d.get("biome", ""))
	type_def = GameData.doors.get(door_type, {})
	sealed = type_def.has("seal")
	monster_proof = monster_proof or bool(type_def.get("monster_proof", false))
	var r: Rect2i = d.rect
	world_rect = Rect2(Vector2(r.position * tile), Vector2(r.size * tile))
	position = world_rect.position + Vector2(world_rect.size.x / 2.0, world_rect.size.y)
	collision_layer = 16
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = world_rect.size
	_shape.shape = rect
	_shape.position = Vector2(0, -world_rect.size.y / 2.0)
	add_child(_shape)
	# #46: the opening is closed to light by two one-sided lines, neither of which shadows the
	# door art: lights in front cast from a line across the top of the drawn door (the art lies
	# in front of it), lights behind cast from a line at its foot (the art lies behind it). A
	# side door, drawn edge-on, has one line down each face of the opening.
	var hw := world_rect.size.x / 2.0
	var art := GameData.texture("props.door_closed")
	var art_h := float(art.get_height()) if art else float(tile)
	_occluder = Node2D.new()
	if vertical:
		var top := -world_rect.size.y - art_h + float(tile)
		# On the faces of the edge-on art (drawn 1.6x wide in _refresh), so none of it is between them.
		var edge_tex := GameData.texture("props.door_open")
		var ex := maxf(2.0, float(edge_tex.get_width()) * 1.6 / 2.0) if edge_tex else 2.0
		_occluder.add_child(LightLayers.one_sided(PackedVector2Array([Vector2(-ex, top), Vector2(-ex, 0)])))
		_occluder.add_child(LightLayers.one_sided(PackedVector2Array([Vector2(ex, 0), Vector2(ex, top)])))
	else:
		_occluder.add_child(LightLayers.one_sided(PackedVector2Array([Vector2(-hw, 0), Vector2(hw, 0)])))
		_occluder.add_child(LightLayers.one_sided(PackedVector2Array([Vector2(hw, -art_h + 2.0), Vector2(-hw, -art_h + 2.0)])))
	add_child(_occluder)
	_sprites = Node2D.new()
	add_child(_sprites)
	if type_def.has("light"):
		_add_light(type_def.light)
	_refresh()


## The warning light of a typed door (#31: the boss door glows red from across the room).
func _add_light(ld: Dictionary) -> void:
	light = PointLight2D.new()
	LightLayers.setup_light(light)
	light.texture = GameData.texture("fx.light")
	light.color = Color.from_string(str(ld.get("color", "#ffffff")), Color.WHITE)
	light.energy = float(ld.get("energy", 1.0))
	light.position = Vector2(0, -float(ld.get("height", 36)))
	LightLayers.register(light, float(ld.get("radius", 120)))
	add_child(light)
	if type_def.has("embers"):
		var em := CPUParticles2D.new()
		em.texture = GameData.texture("fx.pixel")
		em.amount = 10
		em.lifetime = 1.4
		em.position = Vector2(0, -8)
		em.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		em.emission_rect_extents = Vector2(world_rect.size.x / 2.0, 4)
		em.direction = Vector2(0, -1)
		em.spread = 20.0
		em.gravity = Vector2(0, -20)
		em.initial_velocity_min = 4.0
		em.initial_velocity_max = 12.0
		em.scale_amount_min = 0.5
		em.scale_amount_max = 1.0
		var ec := Color.from_string(str(type_def.embers), Color.RED)
		em.color = Color(ec.r * 1.6, ec.g * 1.6, ec.b * 1.6)
		add_child(em)
	set_process(true)


func _process(delta: float) -> void:
	if light:
		_t += delta
		var f := float(type_def.light.get("flicker", 0.0))
		light.energy = float(type_def.light.get("energy", 1.0)) * (1.0 + f * (sin(_t * 7.0) * 0.6 + sin(_t * 17.0) * 0.4))
	_update_art_top()


## A typed door's art rises above its wall row into the chamber's cells, which the fog hides
## until the chamber is seen: that part is drawn over the fog once the door itself has been
## seen, dimmed while the door is out of sight and faded while the local hero is inside.
func _update_art_top() -> void:
	if _art_top == null or not is_instance_valid(_art_top):
		return
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	if _room == Rect2i():
		var ri := int(game.layout.get("boss_room", -1)) if kind == "boss" else int(game.layout.get("merchant", {}).get("room", -1))
		if ri >= 0:
			_room = game.layout.rooms[ri].rect
	var seen := false
	var now := false
	for c in cells:
		seen = seen or game.dungeon.is_discovered(c)
		now = now or game.visibility.is_cell_visible(c)
	_art_top.visible = seen
	var inside := false
	if game.local_player and is_instance_valid(game.local_player):
		inside = _room.grow(1).has_point(game.dungeon.cell_of(game.local_player.global_position))
	var v := 0.82 if now else 0.5
	_art_top.modulate = Color(v, v * 0.98, v * 1.02, 0.3 if inside else 1.0)


## Asset key of this door's art for `which` ("art_closed" / "art_open"), "" when not drawn.
func type_art(which: String) -> String:
	var key := str(type_def.get(which, ""))
	if key.is_empty():
		return ""
	var with_biome := key.replace("<biome>", biome)
	if GameData.asset_exists(with_biome):
		return with_biome
	var plain := key.replace("_<biome>", "").replace("<biome>", "")
	return plain if GameData.asset_exists(plain) else ""


func interact_text() -> String:
	if sealed:
		match str(type_def.get("seal", "")):
			"gold_key":
				return Loc.t("Unlock the vault (Gold Key)")
			"blood":
				return Loc.f("Break the blood seal (%s)", [Merchants.mod_text(Merchants.blood_price(_layout_seed()))])
	if floodgate and not is_open:
		return Loc.t("Floodgate - rusted shut")
	if style == "bookshelf":
		return Loc.t("Turn the bookshelf") if not is_open else Loc.t("Close the bookshelf")
	return Loc.t("Close door") if is_open else Loc.t("Open door")


func interact_pos() -> Vector2:
	return world_rect.get_center()


func _layout_seed() -> int:
	var game := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	return int(game.layout.get("seed", 0)) if game else 0


## Host only. A sealed door stays shut whoever tries (players, swings, monsters).
func host_set_open(open: bool) -> void:
	if open == is_open or (open and sealed):
		return
	_sync_open.rpc(open)


## Host only: the seal was paid for; the door opens.
func host_unseal() -> void:
	if not sealed:
		return
	_sync_seal.rpc(false)
	host_set_open(true)


@rpc("authority", "call_local", "reliable")
func _sync_seal(now_sealed: bool) -> void:
	sealed = now_sealed
	_refresh()


## Host -> all (reliable, call_local).
@rpc("authority", "call_local", "reliable")
func _sync_open(open: bool) -> void:
	is_open = open
	_refresh()
	AudioManager.play_sfx_at("door", world_rect.get_center())
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.visibility.rebuild_opaque()


func _refresh() -> void:
	_shape.set_deferred("disabled", is_open)
	_occluder.visible = not is_open
	for c in _sprites.get_children():
		c.queue_free()
	var key := "props.door_open" if is_open else "props.door_closed"
	var tex := GameData.texture(key)
	if tex == null:
		return
	if not door_type.is_empty() and not vertical:
		_refresh_typed(tex)
		return
	if vertical:
		# Side doors: one sprite per cell, drawn edge-on.
		for i in cells.size():
			var s := Sprite2D.new()
			s.light_mask = LightLayers.LIT
			s.texture = GameData.texture("props.door_open")
			s.offset = Vector2(0, -tex.get_height() / 2.0)
			s.position = Vector2(0, -world_rect.size.y + (i + 1) * world_rect.size.y / cells.size())
			if not is_open:
				s.modulate = Color(1, 1, 1)
				s.scale = Vector2(1.6, 1.0)
			else:
				s.modulate = Color(0.6, 0.6, 0.6, 0.5)
			_sprites.add_child(s)
	elif not is_open:
		# One door spanning the whole opening (art for 2 and 3 cells; other widths are scaled).
		var wide: bool = cells.size() >= 3 and GameData.assets.props.has("door_closed_wide")
		var dt := GameData.texture("props.door_closed_wide") if wide else tex
		if style == "bookshelf":
			dt = GameData.texture("props.bookshelf")
		var s3 := Sprite2D.new()
		s3.light_mask = LightLayers.LIT
		s3.texture = dt
		s3.offset = Vector2(0, -dt.get_height() / 2.0)
		s3.scale.x = world_rect.size.x / float(dt.get_width())
		if floodgate:
			s3.modulate = Color(0.62, 0.7, 0.66)
		_sprites.add_child(s3)
	else:
		for i in cells.size():
			var s2 := Sprite2D.new()
			s2.light_mask = LightLayers.LIT
			s2.texture = tex
			s2.offset = Vector2(0, -tex.get_height() / 2.0)
			var cx := -world_rect.size.x / 2.0 + (i + 0.5) * world_rect.size.x / cells.size()
			s2.position = Vector2(cx if not is_open else (-world_rect.size.x / 2.0 - 4.0 if i == 0 else world_rect.size.x / 2.0 + 4.0), 0)
			if is_open and i > 1:
				s2.visible = false
			_sprites.add_child(s2)



## A typed door (#23 / #31): its own art at its native size, wider than the opening so the frame
## sits in the wall; until the art exists, the ordinary door in the type's light colour.
func _refresh_typed(fallback: Texture2D) -> void:
	var art := type_art("art_open" if is_open else "art_closed")
	var s := Sprite2D.new()
	s.light_mask = LightLayers.LIT
	_art_top = null
	if not art.is_empty():
		var tex: Texture2D = GameData.texture(art)
		var h := tex.get_height()
		var low := mini(ART_LOW, h)
		# Readable from across a dark room (#31): drawn at a fixed brightness, not by the lights.
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		s.texture = tex
		s.region_enabled = true
		s.region_rect = Rect2(0, h - low, tex.get_width(), low)
		s.offset = Vector2(0, -low / 2.0)
		s.material = mat
		if h > low:
			_art_top = Sprite2D.new()
			_art_top.texture = tex
			_art_top.region_enabled = true
			_art_top.region_rect = Rect2(0, 0, tex.get_width(), h - low)
			_art_top.offset = Vector2(0, -low - (h - low) / 2.0)
			_art_top.material = mat
			_art_top.z_index = 61  # over the fog of war (Visibility, z 60)
			_art_top.visible = false
			_sprites.add_child(_art_top)
			set_process(true)
			_update_art_top.call_deferred()
	elif is_open:
		s.texture = fallback
		s.offset = Vector2(0, -fallback.get_height() / 2.0)
		s.position.x = -world_rect.size.x / 2.0 - 4.0
		var s2 := Sprite2D.new()
		s2.light_mask = LightLayers.LIT
		s2.texture = fallback
		s2.offset = s.offset
		s2.position.x = world_rect.size.x / 2.0 + 4.0
		s2.modulate = _type_tint()
		_sprites.add_child(s2)
	else:
		var wide: Texture2D = GameData.texture("props.door_closed_wide")
		s.texture = wide
		s.offset = Vector2(0, -wide.get_height() / 2.0)
		s.scale = Vector2(world_rect.size.x * 1.5 / float(wide.get_width()), 1.25)
	s.modulate = _type_tint() if art.is_empty() else Color(0.82, 0.8, 0.84)
	_sprites.add_child(s)


func _type_tint() -> Color:
	var c := Color.from_string(str(type_def.get("light", {}).get("color", "#ffffff")), Color.WHITE)
	return Color.WHITE.lerp(c, 0.55)
