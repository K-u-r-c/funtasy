class_name Telegraph
extends Node2D
## Telegraphs (#71-#74): every threat is shown before it acts. Two parts:
## - a log every peer keeps: `warned(key)` when the warning appears and `fired(key)` when the
##   threat acts, so the tests can check the warning came first, by at least its data lead time;
## - a ground marker with a countdown (`Telegraph.ground`): a ring in the warning colours that
##   fills over the lead time, a pulsing centre, the seconds left above it and a sound, drawn over
##   the fog of war so it is never missed; it bursts when the threat lands and frees itself.

static var log: Dictionary = {}  ## key -> {"warn": s, "fire": s} (Time in seconds, per peer)

var radius := 40.0
var lead := 1.5
var label := ""
var color := Color("ff4d3d")
var fill := true  ## false: the ring and the countdown only (it mustn't hide what is waking inside)
var _t := 0.0
var _done := false


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func warned(key: String) -> void:
	log[key] = {"warn": now()}


static func fired(key: String) -> void:
	var e: Dictionary = log.get(key, {})
	e["fire"] = now()
	log[key] = e


## How long before acting the warning showed (-1 = no warning, or it hasn't acted yet).
static func lead_of(key: String) -> float:
	var e: Dictionary = log.get(key, {})
	if not e.has("warn") or not e.has("fire"):
		return -1.0
	return float(e.fire) - float(e.warn)


## A ground marker at `pos` (world) under `parent`, filling over `lead` s; logs `key` as warned.
static func ground(parent: Node, pos: Vector2, radius_px: float, lead_s: float, key: String, text: String = "", col: Color = Color("ff4d3d"), sound: String = "telegraph", filled: bool = true) -> Telegraph:
	var t := Telegraph.new()
	t.fill = filled
	t.radius = radius_px
	t.lead = lead_s
	t.label = text
	t.color = col
	t.position = pos
	t.z_index = 61  # over the fog (Visibility, z 60)
	parent.add_child(t)
	warned(key)
	if not sound.is_empty():
		AudioManager.play_sfx_at(sound, pos)
	return t


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if not _done and _t >= lead:
		_done = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.tween_callback(queue_free)


func _draw() -> void:
	var u := clampf(_t / maxf(lead, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * (6.0 + 10.0 * u))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))  # flat on the floor (3/4 view)
	if fill:
		draw_circle(Vector2.ZERO, radius * u, Color(color, 0.16 + 0.1 * pulse))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.85), 2.0)
	draw_arc(Vector2.ZERO, radius * u, 0.0, TAU, 48, Color(color.lightened(0.3), 0.9), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var left := maxf(lead - _t, 0.0)
	var f := UITheme.font()
	var txt := ("%s  " % label if not label.is_empty() else "") + ("%.1f" % left)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
	draw_string_outline(f, Vector2(-w / 2.0, -radius * 0.55 - 6.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, 3, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(-w / 2.0, -radius * 0.55 - 6.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, color.lightened(0.35))
