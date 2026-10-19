extends Node2D
## World-space overlay drawn above the darkness: enemy health bars, teammate names/health,
## downed timers and revive progress, cast bars and names of nearby ground items.

var _font: Font


func _ready() -> void:
	_font = UITheme.font()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var lp: Player = game.local_player if is_instance_valid(game.local_player) else null
	for e in game.enemies_root.get_children():
		if not e.visible or not is_instance_valid(e) or e.is_boss:
			continue
		var top: Vector2 = e.global_position + Vector2(0, -e.sprite.visual_height() - 7.0)
		if e.get_meta("hide_bar", false):
			continue
		if e.is_elite():
			_text(top + Vector2(0, -4), Loc.name(e.display_name), Color(0.95, 0.78, 0.3), 11)
		if e.aggro or e.health.hp < e.health.max_hp:
			_bar(top, 28.0, e.health.fraction(), Color(0.95, 0.7, 0.2) if e.is_elite() else Color(0.85, 0.2, 0.18))
		_cast(e, top + Vector2(0, -6), now)
	for p in game.players_root.get_children():
		var head: Vector2 = p.global_position + Vector2(0, -p.sprite.visual_height() - 11.0)
		if p.life_state == Player.Life.GHOST:
			continue
		if not p.is_local():
			var cdef: Dictionary = p.class_def
			_text(head + Vector2(0, -8), p.display_name, Color.from_string(str(cdef.get("color", "#ffffff")), Color.WHITE), 12)
			_bar(head, 30.0, p.health.fraction(), Color(0.3, 0.85, 0.35))
		if p.life_state == Player.Life.DOWNED:
			_text(p.global_position + Vector2(0, -36), Loc.f("DOWNED %d", [ceili(p.downed_left)]), Color(1, 0.4, 0.35), 12)
			if p.revive_progress > 0.0:
				draw_arc(p.global_position + Vector2(0, -20), 16.0, -PI / 2.0, -PI / 2.0 + TAU * p.revive_progress, 24, Color(0.5, 1.0, 0.6), 3.0)
		_cast(p, head + Vector2(0, -16), now)
	if is_instance_valid(game.local_player):
		_ally_target_marker(game, game.local_player)
	if lp:
		for g in game.items_root.get_children():
			if g.global_position.distance_to(lp.global_position) < 110.0:
				var rar := GameData.rarity(int(g.item.get("rarity", 1)))
				_text(g.global_position + Vector2(0, -30), Loc.item_name(g.item), Color.from_string(rar.color, Color.WHITE), 12)
				if ItemGenerator.too_high_level(g.item, lp.level):
					_text(g.global_position + Vector2(0, -20), Loc.f("Requires level %d", [int(g.item.req)]), Color(1.0, 0.4, 0.35), 12)


func _bar(center: Vector2, width: float, frac: float, color: Color) -> void:
	var r := Rect2(center - Vector2(width / 2.0, 0), Vector2(width, 4))
	draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(r.position, Vector2(width * clampf(frac, 0.0, 1.0), 4)), color)


func _cast(a: Node, pos: Vector2, now: float) -> void:
	if not a.has_meta("cast_end"):
		return
	var end_t: float = a.get_meta("cast_end")
	var total: float = a.get_meta("cast_total")
	if now >= end_t or total <= 0.0:
		return
	_bar(pos, 26.0, 1.0 - (end_t - now) / total, Color(0.95, 0.8, 0.3))


func _text(center: Vector2, text: String, color: Color, size: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := center - Vector2(w / 2.0, 0)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Ally-targeted skills (3.4): mark the teammate an ally skill on the bar would pick right now
## (the one nearest the aim point, within reach); nothing when it would fall back to yourself.
func _ally_target_marker(game: Node, lp: Player) -> void:
	if lp.life_state != Player.Life.ALIVE:
		return
	# A teammate picked with Tab / a click (#39) takes the ally spells: a gold ring under their feet
	# and a bobbing gold chevron over their head, instead of the cursor's suggestion.
	var picked := lp.friendly_target_node()
	if picked:
		var pc := picked.global_position
		var gold := Color(1.0, 0.82, 0.3, 0.95)
		var t := Time.get_ticks_msec() / 1000.0
		draw_arc(pc + Vector2(0, 2), 14.0, 0.0, TAU, 28, Color(gold, 0.35), 4.0)
		draw_arc(pc + Vector2(0, 2), 14.0, 0.0, TAU, 28, gold, 1.5)
		var top := pc + Vector2(0, -picked.sprite.visual_height() - 26.0 + sin(t * 4.0) * 2.0)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-6, -5), top + Vector2(6, -5), top + Vector2(0, 3)]), gold)
		draw_polyline(PackedVector2Array([top + Vector2(-6, -5), top + Vector2(6, -5), top + Vector2(0, 3), top + Vector2(-6, -5)]), Color(0.25, 0.15, 0.0), 1.0)
		return
	var reach := 0.0
	for sid in lp.skills:
		for eff in GameData.skills.get(str(sid), {}).get("effects", []):
			if str(eff.get("target", "")) in ["aim_ally", "aim_any"]:
				reach = maxf(reach, float(eff.get("range", eff.get("max_range", 300))))
	if reach <= 0.0:
		return
	var best: Player = null
	var best_d := 90.0
	for other in game.players_root.get_children():
		if other == lp or other.life_state != Player.Life.ALIVE or other.global_position.distance_to(lp.global_position) > reach:
			continue
		var d: float = other.global_position.distance_to(lp.aim_pos)
		if d <= best_d:
			best_d = d
			best = other
	if best == null:
		return
	var c := best.global_position
	var col := Color(0.45, 1.0, 0.55, 0.85)
	draw_arc(c, 13.0, 0.0, TAU, 24, col, 1.5)
	for i in 4:
		var a := TAU * i / 4.0 + Time.get_ticks_msec() / 600.0
		draw_line(c + Vector2.from_angle(a) * 15.0, c + Vector2.from_angle(a) * 19.0, col, 1.5)
