extends FloorMechanic
## Crypt - Chilling Breath of the Tomb (D36): a hero standing outside every light (wall torches,
## carried torches, lava, spells - not their own faint glow) regenerates mana / fury at half rate.

var _left := 0.0


func physics(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = 0.5
	for pl in game.players_root.get_children():
		if not pl.is_targetable():
			continue
		if LightLayers.is_lit(game.get_tree(), pl.global_position, true):
			pl.status.remove("unlit_chill")
		elif not pl.status.has("unlit_chill"):
			pl.status.apply("unlit_chill", -1.0, 0.0, Combat.instance.env_ctx(0.0))


var _phase := 0


func test_trigger(suite: RefCounted) -> void:
	# Somewhere dark first (the suite starts the check without a carried torch).
	var pl: Player = suite.p
	var dark: Vector2 = suite.find_spot(func(pos: Vector2) -> bool: return not _lit_near(pos, 48.0))
	pl.host_teleport(dark)
	_phase = 0


func test_check(suite: RefCounted) -> String:
	var pl: Player = suite.p
	if _phase == 0:
		if not pl.status.has("unlit_chill"):
			return "no chill in the dark"
		# Then into a torch's light: the chill lifts.
		var lit: Vector2 = suite.find_spot(func(pos: Vector2) -> bool: return LightLayers.is_lit(game.get_tree(), pos, true) and _lit_near(pos, -48.0))
		pl.host_teleport(lit)
		_phase = 1
		return "moved into the light"
	return "" if not pl.status.has("unlit_chill") else "chill stays in the light"


## Test helper: margin > 0 - is any point within `margin` px lit; margin < 0 - is every point lit.
func _lit_near(pos: Vector2, margin: float) -> bool:
	var tree := game.get_tree()
	var all_lit := true
	for o in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var lit := LightLayers.is_lit(tree, pos + o * absf(margin), true)
		if lit and margin > 0.0:
			return true
		all_lit = all_lit and lit
	return all_lit if margin < 0.0 else false
