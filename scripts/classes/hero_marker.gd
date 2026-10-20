class_name HeroMarker
extends Node2D
## #59: finding your own hero in a crowd. On each peer its own hero gets a bright ring on the
## ground with a soft glow (pulsing slowly); teammates get a faint ring in their class colour.
## Drawn under the hero, unshaded and additive, so it reads in the dark on every biome. The
## "you" pin over the head is drawn by the Overhead layer. Settings.hero_marker turns both off.
## The own hero's ring and pin show only while the player holds Dodge for a moment
## (`ui.hero_marker_hold` s) or while the hero is downed, and fade in and out.

static var test_hold := false  ## tests: act as if Dodge were held

var hero: Player
var reveal := 0.0  ## own hero: 0 hidden .. 1 fully shown
var _t := 0.0
var _held := 0.0


func _init(p: Player) -> void:
	hero = p
	name = "HeroMarker"
	z_index = -1  # under the hero, over the floor
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add


static func you_color() -> Color:
	return Color.from_string(str(GameData.bal("ui.hero_marker_color", "#6fe8ff")), Color(0.45, 0.9, 1.0))


## Is the ring drawn on this peer, and how (0 = none, 1 = teammate, 2 = own hero)?
func mode() -> int:
	if not Settings.hero_marker or hero.life_state == Player.Life.GHOST:
		return 0
	return 2 if hero.is_local() else 1


func _process(delta: float) -> void:
	_t += delta
	var m := mode()
	if m == 2:
		var holding := test_hold or Input.is_action_pressed("dodge")
		_held = _held + delta if holding else 0.0
		var want := _held >= float(GameData.bal("ui.hero_marker_hold", 0.35)) or hero.life_state == Player.Life.DOWNED
		var fade := maxf(float(GameData.bal("ui.hero_marker_fade", 0.15)), 0.01)
		reveal = move_toward(reveal, 1.0 if want else 0.0, delta / fade)
	else:
		_held = 0.0
		reveal = 0.0
	visible = m == 1 or (m == 2 and reveal > 0.0)
	if visible:
		queue_redraw()


## How much of the own-hero marker (ring and pin) `p` shows on this peer (0 = none).
static func reveal_of(p: Player) -> float:
	var m := p.get_node_or_null("HeroMarker") as HeroMarker
	return m.reveal if m and m.mode() == 2 else 0.0


func _draw() -> void:
	var m := mode()
	# The ring lies flat on the floor (light 3/4 view): an ellipse half as tall as wide.
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
	if m == 2:
		var c := you_color()
		var k := reveal
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(Vector2.ZERO, 19.0, Color(c, (0.14 + 0.08 * pulse) * k))
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 40, Color(c, 0.4 * k), 6.0)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 40, Color(c, (0.85 + 0.15 * pulse) * k), 2.5)
		# Four short ticks around the ring, turning slowly: reads as "selected" even at a glance.
		for i in 4:
			var a := _t * 0.8 + i * TAU / 4.0
			var dir := Vector2.RIGHT.rotated(a)
			draw_line(dir * 21.0, dir * 27.0, Color(c, 0.9 * k), 2.5)
	else:
		var cc := Color.from_string(str(hero.class_def.get("color", "#ffffff")), Color.WHITE)
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(cc, 0.35), 1.5)
