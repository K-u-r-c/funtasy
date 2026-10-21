class_name SpeechBubble
extends Control
## #78, local: a speech bubble over an NPC's head - an Obsidian Glass box with a gold rim and a
## tail pointing at the speaker. It pops in, types the line out, stays long enough to read
## (npc_lines.json bubble: hold + per_char), then fades. It follows the speaker on screen, stays
## inside the screen and moves aside (under the speaker, or left / right) rather than cover the
## local hero.

var speaker: Node2D
var text := ""
var head := 52.0  ## px above the speaker's feet
var _label: Label
var _t := 0.0
var _life := 4.0
var _below := false
var cfg: Dictionary = {}


func setup(who: Node2D, line: String, head_px: float) -> void:
	speaker = who
	text = line
	head = head_px
	cfg = GameData.npc_lines.get("bubble", {})
	_life = float(cfg.get("hold", 2.6)) + float(cfg.get("per_char", 0.045)) * line.length() + text.length() / float(cfg.get("type_speed", 40.0))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UITheme.label(text, UITheme.TEXT, UITheme.FONT_SMALL)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(float(cfg.get("width", 230)), 0)
	_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_label.visible_characters = 0
	_label.position = Vector2(10, 7)
	add_child(_label)
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("npc_speak", 0.06)


func _process(delta: float) -> void:
	_t += delta
	if speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree():
		queue_free()
		return
	_label.visible_characters = mini(int(_t * float(cfg.get("type_speed", 40.0))), text.length())
	# The box is sized for the whole line from the start, so it doesn't grow while it types.
	var w := float(cfg.get("width", 230))
	_label.size = Vector2(w, 0)
	size = Vector2(w + 20.0, _label.get_minimum_size().y + 14.0)
	pivot_offset = Vector2(size.x / 2.0, size.y)
	_place()
	queue_redraw()
	var fade := float(cfg.get("fade", 0.45))
	if _t > _life:
		modulate.a = clampf(1.0 - (_t - _life) / fade, 0.0, 1.0)
		if _t > _life + fade:
			queue_free()


## On screen above the speaker's head, inside the screen, never over the local hero.
func _place() -> void:
	var vp := get_viewport_rect().size
	var foot: Vector2 = speaker.get_global_transform_with_canvas().origin
	var gap := float(cfg.get("head_gap", 10))
	var pos := foot + Vector2(-size.x / 2.0, -head - gap - size.y)
	_below = false
	var game := get_tree().get_first_node_in_group("game")
	var me: Node2D = game.local_player if game and is_instance_valid(game.local_player) else null
	if me:
		var hp: Vector2 = me.get_global_transform_with_canvas().origin
		var hero := Rect2(hp + Vector2(-18, -58), Vector2(36, 62))
		if Rect2(pos, size).intersects(hero):
			# Beside the speaker, on the side away from the hero.
			var side := -1.0 if hp.x > foot.x else 1.0
			pos = foot + Vector2(side * 24.0 + (0.0 if side > 0 else -size.x), -head - size.y * 0.5)
			if Rect2(pos, size).intersects(hero):
				pos = foot + Vector2(-size.x / 2.0, gap + 6.0)
				_below = true
	pos.x = clampf(pos.x, 8.0, vp.x - size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - size.y - 8.0)
	position = pos.round()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UITheme.cached_glass(Color("0b0e16f0"), UITheme.GOLD_DIM, 1, 0), r)
	draw_line(r.position + Vector2(2, 1), Vector2(r.end.x - 2, r.position.y + 1), UITheme.RIM, 1.0)
	# The tail points at the speaker.
	var foot: Vector2 = speaker.get_global_transform_with_canvas().origin - position if speaker else Vector2(size.x / 2.0, size.y + 10)
	var tx := clampf(foot.x, 12.0, size.x - 12.0)
	var pts: PackedVector2Array
	if _below:
		pts = PackedVector2Array([Vector2(tx - 6, 0), Vector2(tx + 6, 0), Vector2(tx, -8)])
	else:
		pts = PackedVector2Array([Vector2(tx - 6, size.y - 1), Vector2(tx + 6, size.y - 1), Vector2(tx, size.y + 8)])
	draw_colored_polygon(pts, Color("0b0e16f0"))
	draw_polyline(PackedVector2Array([pts[0], pts[2], pts[1]]), UITheme.GOLD_DIM, 1.0)
