class_name CharacterPortrait
extends Control
## Live portrait of an actor: its layered character sprite (gear included) drawn front-facing
## at an integer scale. `crop` = true shows the head-and-shoulders region from
## data/assets.json characters.portrait_crop, otherwise the whole 64x64 frame.

var actor: Node  ## Actor with a `sprite: CharacterSprite`
var crop := true
var pixel_scale := 2
var frame_color := UITheme.GOLD_DIM
var tint := Color.WHITE  ## e.g. grey for downed / ghost players
var _layers: Array = []
var _refresh_left := 0.0


func _init(p_crop := true, p_scale := 2) -> void:
	crop = p_crop
	pixel_scale = p_scale
	var r := _src_rect()
	custom_minimum_size = r.size * pixel_scale + Vector2(4, 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _src_rect() -> Rect2:
	# The body's asset entry may override the global frame size / portrait crop (final art).
	var chars: Dictionary = GameData.assets.get("characters", {})
	var body: Dictionary = chars.get("layers", {}).get("body_human", {})
	if crop:
		var c: Array = body.get("portrait_crop", chars.get("portrait_crop", [16, 8, 32, 32]))
		return Rect2(c[0], c[1], c[2], c[3])
	var fs := float(body.get("frame_size", chars.get("frame_size", 64)))
	if body.has("full_crop"):
		var fc: Array = body.full_crop
		return Rect2(fc[0], fc[1], fc[2], fc[3])
	return Rect2(0, 0, fs, fs)


func _process(delta: float) -> void:
	# Gear changes are rare; re-reading the layers a few times a second is plenty.
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		var next: Array = []
		if is_instance_valid(actor) and actor.get("sprite") != null:
			next = actor.sprite.portrait_layers()
		if next != _layers:
			_layers = next
			queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size.round())
	draw_style_box(UITheme.cached_glass(Color("05070bf2"), frame_color, 1, 0, UITheme.CYAN if crop else Color(0, 0, 0, 0)), r)
	# Soft radial backlight in two stepped rings (pixel look, no gradients).
	var c := r.get_center()
	draw_circle(c, minf(r.size.x, r.size.y) * 0.42, Color(UITheme.CYAN, 0.05))
	draw_circle(c, minf(r.size.x, r.size.y) * 0.3, Color(UITheme.CYAN, 0.05))
	var src := _src_rect()
	var dest_size := src.size * pixel_scale
	var dest := Rect2(((r.size - dest_size) / 2.0).round(), dest_size)
	for l in _layers:
		var tex: Texture2D = l[0]
		if tex == null:
			continue
		draw_texture_rect_region(tex, dest, src, Color(l[1]) * tint)
