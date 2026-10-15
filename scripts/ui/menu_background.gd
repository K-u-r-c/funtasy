extends Control
## Animated menu backdrop: the crypt gate art (data/assets.json "ui.menu_backdrop") scaled by
## whole pixels to cover the screen, flickering brazier light, drifting embers and a stepped
## vignette. Works for any aspect ratio: wide screens get dark side fades instead of stretching.

const COUNT := 90
## Brazier positions in backdrop pixels (for the flicker glow).
const BRAZIERS := [Vector2(112, 152), Vector2(288, 152)]

var _motes: Array[Dictionary] = []
var _time := 0.0
var _tex: Texture2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	var path := GameData.asset_path("ui.menu_backdrop")
	if not path.is_empty() and ResourceLoader.exists(path):
		_tex = load(path)
	resized.connect(_spawn_motes)


func _spawn_motes() -> void:
	_motes.clear()
	for i in COUNT:
		_motes.append({
			"pos": Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)),
			"speed": _rng.randf_range(6.0, 28.0),
			"size": _rng.randi_range(1, 2),
			"phase": _rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	for m in _motes:
		m.pos.y -= m.speed * delta
		m.pos.x += sin(_time * 0.5 + m.phase) * 6.0 * delta
		if m.pos.y < -4.0:
			m.pos = Vector2(randf_range(0, size.x), size.y + 4.0)
	queue_redraw()


## Backdrop rect: covers the height (and the width when that needs more), whole-pixel scale.
func _art_rect() -> Rect2:
	if _tex == null:
		return Rect2()
	var ts := _tex.get_size()
	var s := size.y / ts.y
	if ts.x * s < size.x * 0.75:
		s = maxf(s, size.x * 0.75 / ts.x)
	s = ceilf(s * 2.0) / 2.0  # half-pixel steps keep the art crisp enough at any size
	var dsize := ts * s
	return Rect2(((size - dsize) / 2.0).round(), dsize)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("05060a"))
	var ar := _art_rect()
	if _tex:
		draw_texture_rect(_tex, ar, false)
		var s := ar.size.x / _tex.get_size().x
		var flicker := 0.85 + 0.15 * sin(_time * 7.0) * sin(_time * 3.3)
		for b in BRAZIERS:
			var p: Vector2 = ar.position + b * s
			for r in [70.0, 45.0, 24.0]:
				draw_circle(p, r * s / 4.0, Color(1.0, 0.5, 0.15, 0.05 * flicker))
		# Side fades when the art doesn't reach the screen edges (ultrawide).
		var steps := 8
		var fade := 48.0
		for i in steps:
			var a := 1.0 - float(i) / steps
			var x0 := ar.position.x + i * fade / steps
			var x1 := ar.end.x - (i + 1) * fade / steps
			draw_rect(Rect2(x0, 0, fade / steps, size.y), Color(0.02, 0.025, 0.04, a))
			draw_rect(Rect2(x1, 0, fade / steps, size.y), Color(0.02, 0.025, 0.04, a))
		draw_rect(Rect2(0, 0, ar.position.x, size.y), Color("05060a"))
		draw_rect(Rect2(ar.end.x, 0, size.x - ar.end.x, size.y), Color("05060a"))
	# Left-side darkening so menu text stays readable (stepped bands, no smooth gradient).
	var bands := 10
	for i in bands:
		var w := size.x * 0.5 / bands
		draw_rect(Rect2(i * w, 0, w + 1.0, size.y), Color(0.02, 0.025, 0.04, 0.55 * (1.0 - float(i) / bands)))
	for m in _motes:
		var a2 := 0.3 + 0.4 * (0.5 + 0.5 * sin(_time * 2.0 + m.phase))
		draw_rect(Rect2(m.pos.round(), Vector2.ONE * m.size), Color(1.0, 0.55, 0.25, a2))
	# Vignette top/bottom
	for i in 6:
		var h := 6.0
		var a3 := 0.5 * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(0, i * h, size.x, h), Color(0, 0, 0, a3))
		draw_rect(Rect2(0, size.y - (i + 1) * h, size.x, h), Color(0, 0, 0, a3))
