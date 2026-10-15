class_name Visibility
extends Node2D
## Local (per peer) fog of war and darkness:
## - a cell is seen when it is in the viewer's line of sight (walls and closed doors block it)
##   AND lit: by the viewer's own small light, a torch (on a wall or carried), lava or a spell.
##   Cells ever seen stay "discovered" (dimmed, without enemies) for the map/minimap;
## - monsters are shown only while in line of sight (physics raycast, so destructible props hide
##   them too) AND lit. Optional shared vision also uses every teammate's sight;
## - the viewer's own light sits at its feet: collisions keep the feet out of every occluder,
##   so standing right against a door or table never puts the light inside its shadow caster;
## - far-away torches/lava lights are switched off to keep lighting cheap.

const FOG_UNSEEN := 1.0
const FOG_REMEMBERED := 0.55

var dungeon: Dungeon
var game: Node
var viewer: Node2D
var vision_light: PointLight2D
var fov_radius := 16
var max_sight := 600.0
var personal_radius := 75.0  ## all three overwritten from data/balance.json in _ready

var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_sprite: Sprite2D
var _visible_now: Dictionary = {}
var _fov_left := 0.0
var _enemy_left := 0.0
var _opaque := PackedByteArray()


func _ready() -> void:
	fov_radius = int(GameData.bal("vision.fov_radius"))
	max_sight = float(GameData.bal("vision.max_sight"))
	personal_radius = float(GameData.bal("lighting.personal_light_radius"))
	vision_light = PointLight2D.new()
	LightLayers.setup_light(vision_light)
	vision_light.texture = GameData.texture("fx.light")
	LightLayers.register(vision_light, personal_radius)
	vision_light.energy = float(GameData.bal("lighting.personal_light_energy"))
	vision_light.color = Color(0.85, 0.8, 0.95)
	vision_light.shadow_enabled = true
	vision_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	vision_light.shadow_filter_smooth = 1.5
	add_child(vision_light)
	_fog_sprite = Sprite2D.new()
	_fog_sprite.centered = false
	_fog_sprite.z_index = 60
	_fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_fog_sprite)


func reset_floor() -> void:
	_visible_now.clear()
	var s := dungeon.size
	_fog_img = Image.create(s.x, s.y, false, Image.FORMAT_RGBA8)
	_fog_img.fill(Color(0, 0, 0, FOG_UNSEEN))
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_sprite.texture = _fog_tex
	_fog_sprite.scale = Vector2(dungeon.tile, dungeon.tile)
	rebuild_opaque()
	_fov_left = 0.0


func rebuild_opaque() -> void:
	var s := dungeon.size
	_opaque.resize(s.x * s.y)
	for y in s.y:
		for x in s.x:
			_opaque[y * s.x + x] = 1 if dungeon.cell_at(Vector2i(x, y)) == DungeonGenerator.CELL_WALL else 0
	for d in dungeon.doors:
		if not d.is_open:
			for c in d.cells:
				_opaque[c.y * s.x + c.x] = 1


func _process(delta: float) -> void:
	if dungeon == null or _fog_img == null or viewer == null or not is_instance_valid(viewer):
		return
	vision_light.global_position = viewer.global_position
	_fov_left -= delta
	if _fov_left <= 0.0:
		_fov_left = 0.12
		_update_fov()
	_enemy_left -= delta
	if _enemy_left <= 0.0:
		_enemy_left = 0.08
		_update_enemies()
		_cull_lights()


func _is_opaque(c: Vector2i) -> bool:
	var s := dungeon.size
	if c.x < 0 or c.y < 0 or c.x >= s.x or c.y >= s.y:
		return true
	return _opaque[c.y * s.x + c.x] == 1


func _update_fov() -> void:
	var origin := dungeon.cell_of(viewer.global_position)
	var now := {}
	var r := fov_radius
	var lights := _lights_near(viewer.global_position, r * dungeon.tile)
	var half := dungeon.tile * 0.5
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var target := origin + Vector2i(dx, dy)
			if _cell_lit(dungeon.cell_center(target), lights, half) and _line_clear(origin, target):
				now[target] = true
	var changed := false
	for c in _visible_now:
		if not now.has(c):
			_set_fog(c, FOG_REMEMBERED)
			changed = true
	for c in now:
		if not _visible_now.has(c):
			_set_fog(c, 0.0)
			dungeon.mark_discovered(c)
			changed = true
	_visible_now = now
	if changed:
		_fog_tex.update(_fog_img)


func _set_fog(c: Vector2i, a: float) -> void:
	if c.x < 0 or c.y < 0 or c.x >= _fog_img.get_width() or c.y >= _fog_img.get_height():
		return
	_fog_img.set_pixel(c.x, c.y, Color(0, 0, 0, a))


## Grid ray: the target cell itself may be opaque (so walls get revealed), cells before it not.
func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	if n <= 1:
		return true
	for i in range(1, n):
		var t := float(i) / n
		var c := Vector2i(roundi(a.x + d.x * t), roundi(a.y + d.y * t))
		if c != b and _is_opaque(c):
			return false
	return true


func is_cell_visible(c: Vector2i) -> bool:
	return _visible_now.has(c)


func _viewers() -> Array:
	var out: Array = [viewer]
	if bool(GameState.setting("shared_vision")) and game:
		for p in game.players_root.get_children():
			if p != viewer and p.is_targetable():
				out.append(p)
	return out


## Registered gameplay lights (see LightLayers) that can reach `range` px around `pos`.
func _lights_near(pos: Vector2, range_px: float) -> Array:
	var out: Array = []
	for l in get_tree().get_nodes_in_group(LightLayers.GROUP):
		if not l.is_visible_in_tree():
			continue
		var rad := float(l.get_meta("radius", 0.0))
		if rad > 0.0 and l.global_position.distance_to(pos) <= range_px + rad:
			out.append([l.global_position, rad])
	return out


func _cell_lit(p: Vector2, lights: Array, margin: float) -> bool:
	for l in lights:
		if p.distance_to(l[0]) <= float(l[1]) + margin:
			return true
	return false


func _update_enemies() -> void:
	if game == null:
		return
	var space := get_world_2d().direct_space_state
	var viewers := _viewers()
	var lights := _lights_near(viewer.global_position, max_sight)
	for e in game.enemies_root.get_children():
		var seen := false
		var lit := _cell_lit(e.global_position, lights, 6.0)
		for v in viewers:
			var from: Vector2 = v.global_position
			var d := from.distance_to(e.global_position)
			if d > max_sight or (not lit and d > personal_radius):
				continue
			var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), e.global_position + Vector2(0, -6), Combat.LOS_MASK)
			if space.intersect_ray(q).is_empty():
				seen = true
				break
		e.visible = seen


func _cull_lights() -> void:
	var focus := viewer.global_position
	for l in dungeon.lights:
		if is_instance_valid(l):
			l.enabled = l.global_position.distance_to(focus) < 1000.0
