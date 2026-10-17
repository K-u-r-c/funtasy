class_name HeroPreview
extends Control
## Animated, rotatable hero preview for the lobby: the layered CharacterSprite of a gender with
## an optional look (layer -> appearance name, as Inventory.appearance gives), drawn at an
## integer scale on an Obsidian Glass plate. Drag with the mouse or call rotate_by() to turn it.

const DIRS := 8

var gender := ""
var look: Dictionary = {}  ## layer -> [appearance, tint html] (Inventory.appearance format)
var dir_index := 2  ## 0..7 = E, SE, S, SW, W, NW, N, NE (starts facing the camera)
var pixel_scale := 3
var sprite: CharacterSprite
var _drag_x := 0.0
var _feet_y := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(128, 140)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	sprite = CharacterSprite.new()
	add_child(sprite)
	resized.connect(_place)


func _ready() -> void:
	_rebuild()
	_place()


func set_look(p_gender: String, p_look: Dictionary) -> void:
	gender = CharacterSprite.valid_gender(p_gender)
	look = p_look
	if is_inside_tree():
		_rebuild()


func rotate_by(step: int) -> void:
	dir_index = wrapi(dir_index + step, 0, DIRS)
	sprite.play("idle", facing())


## Where the preview faces (direction index 0 = east, counting clockwise on screen).
func facing() -> Vector2:
	return Vector2.RIGHT.rotated(dir_index * PI / 4.0)


## Turns the hero toward the screen's right (`side` 1) or left (-1), one eighth at a time (#14):
## from facing the camera, turning right shows the hero looking right.
func turn(side: int) -> void:
	rotate_by(-side)


func _rebuild() -> void:
	sprite.set_layer("body", CharacterSprite.body_key(gender))
	for layer in ["head", "chest", "legs", "boots", "gloves", "weapon", "offhand"]:
		if look.has(layer):
			var a: Array = look[layer]
			sprite.set_layer(layer, CharacterSprite.gear_key(str(a[0]), gender), Color.from_string(str(a[1]), Color.WHITE))
		else:
			sprite.set_layer(layer, "")
	sprite.play("idle", Vector2.RIGHT.rotated(dir_index * PI / 4.0), true)
	_place()


## Feet near the bottom of the plate; the scale is the largest integer at which everything the
## hero draws in any direction (held weapons too) fits the plate (#15: a fixed height-only scale
## cut swords, shields and bows off at the plate's edges).
func _place() -> void:
	var u := sprite.used_rect("idle")
	if u.size == Vector2i.ZERO:
		u = Rect2i(16, 8, 32, 56)
	var top := sprite.frame_top()
	var half := maxf(32.0 - u.position.x, u.end.x - 32.0) + 2.0
	var above := -(top + u.position.y) + 3.0
	var below := maxf(top + u.end.y, 0.0)
	var sc_x := (size.x / 2.0 - 4.0) / half
	var sc_y := (size.y - 16.0) / (above + below)
	pixel_scale = maxi(1, int(minf(sc_x, sc_y)))
	_feet_y = roundf(size.y - 10.0 - below * pixel_scale)
	sprite.scale = Vector2.ONE * pixel_scale
	sprite.position = Vector2(roundf(size.x / 2.0), _feet_y)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_drag_x = ev.position.x
		accept_event()
	elif ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var dx: float = ev.position.x - _drag_x
		if absf(dx) >= 24.0:
			rotate_by(-1 if dx > 0.0 else 1)
			_drag_x = ev.position.x
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size.round())
	draw_style_box(UITheme.cached_glass(Color("05070bf2"), UITheme.GOLD_DIM, 1, 0), r)
	var c := Vector2(r.size.x / 2.0, _feet_y if _feet_y > 0.0 else r.size.y - 12.0)
	# Floor shadow + soft backlight in stepped rings (pixel look).
	draw_circle(Vector2(r.size.x / 2.0, r.size.y * 0.45), r.size.x * 0.42, Color(UITheme.CYAN, 0.04))
	draw_circle(Vector2(r.size.x / 2.0, r.size.y * 0.45), r.size.x * 0.28, Color(UITheme.CYAN, 0.04))
	draw_set_transform(c, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 9.0 * pixel_scale, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
