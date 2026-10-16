extends StaticBody2D
## Door filling a 2-3 cell opening in a room wall. Closed doors block movement, projectiles and
## sight (LightOccluder2D + "doors" physics layer). Players toggle them with Interact; the host
## owns the state and broadcasts it. Simple monsters open closed doors after a short delay.

var cells: Array = []
var vertical := false
var is_open := false
var monster_proof := false  ## merchant chamber doors: monsters never open them
var floodgate := false  ## Sewers: rusted shut until a lever beside it is pulled
var world_rect := Rect2()
var _shape: CollisionShape2D
var _occluder: LightOccluder2D
var _sprites: Node2D


func setup(d: Dictionary, tile: int) -> void:
	cells = d.cells
	vertical = d.vertical
	monster_proof = bool(d.get("monster_proof", false))
	floodgate = bool(d.get("floodgate", false))
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
	_occluder = LightOccluder2D.new()
	var occ := OccluderPolygon2D.new()
	var hw := world_rect.size.x / 2.0
	occ.polygon = PackedVector2Array([Vector2(-hw, -world_rect.size.y), Vector2(hw, -world_rect.size.y), Vector2(hw, 0), Vector2(-hw, 0)])
	_occluder.occluder = occ
	add_child(_occluder)
	_sprites = Node2D.new()
	add_child(_sprites)
	_refresh()


func interact_text() -> String:
	if floodgate and not is_open:
		return "Floodgate - rusted shut"
	return "Close door" if is_open else "Open door"


func interact_pos() -> Vector2:
	return world_rect.get_center()


## Host only.
func host_set_open(open: bool) -> void:
	if open == is_open:
		return
	_sync_open.rpc(open)


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
	if vertical:
		# Side doors: one sprite per cell, drawn edge-on.
		for i in cells.size():
			var s := Sprite2D.new()
			s.light_mask = LightLayers.SELF_LIT
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
		var s3 := Sprite2D.new()
		s3.light_mask = LightLayers.SELF_LIT
		s3.texture = dt
		s3.offset = Vector2(0, -dt.get_height() / 2.0)
		s3.scale.x = world_rect.size.x / float(dt.get_width())
		_sprites.add_child(s3)
	else:
		for i in cells.size():
			var s2 := Sprite2D.new()
			s2.light_mask = LightLayers.SELF_LIT
			s2.texture = tex
			s2.offset = Vector2(0, -tex.get_height() / 2.0)
			var cx := -world_rect.size.x / 2.0 + (i + 0.5) * world_rect.size.x / cells.size()
			s2.position = Vector2(cx if not is_open else (-world_rect.size.x / 2.0 - 4.0 if i == 0 else world_rect.size.x / 2.0 + 4.0), 0)
			if is_open and i > 1:
				s2.visible = false
			_sprites.add_child(s2)
