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
	sprite.play("idle", Vector2.RIGHT.rotated(dir_index * PI / 4.0))


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


## Feet near the bottom of the plate; the scale is the largest integer that fits the body.
func _place() -> void:
	var h := maxf(sprite.visual_height(), 1.0)
	pixel_scale = maxi(1, int((size.y - 24.0) / (h + 6.0)))
	sprite.scale = Vector2.ONE * pixel_scale
	sprite.position = Vector2(roundf(size.x / 2.0), roundf(size.y - 12.0))


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
	var c := Vector2(r.size.x / 2.0, r.size.y - 12.0)
	# Floor shadow + soft backlight in stepped rings (pixel look).
	draw_circle(Vector2(r.size.x / 2.0, r.size.y * 0.45), r.size.x * 0.42, Color(UITheme.CYAN, 0.04))
	draw_circle(Vector2(r.size.x / 2.0, r.size.y * 0.45), r.size.x * 0.28, Color(UITheme.CYAN, 0.04))
	draw_set_transform(c, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 9.0 * pixel_scale, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
