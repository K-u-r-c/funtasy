extends MonsterBehavior
## Crypt Ghoul: when a monster dies nearby it runs to the corpse and devours it, healing 50% and
## frenzying (+40% attack speed). params: radius (150), heal (0.5), channel (1.2)

var _corpse := {}
var _eat_left := -1.0
var _walk := 0.0


func on_ally_death(_other: Enemy, corpse: Dictionary) -> void:
	if corpse.is_empty() or not _corpse.is_empty() or corpse.get("bones", false):
		return
	if corpse.pos.distance_to(enemy.global_position) <= float(p("radius", 150.0)):
		_corpse = corpse


func on_think(game: Node) -> bool:
	if _corpse.is_empty():
		return false
	if not game.corpses.has(int(_corpse.id)):
		_corpse = {}
		_eat_left = -1.0
		set_state("")
		return false
	_walk += float(GameData.bal("ai.think_interval"))
	# Close enough to feed (a prop or a wall can keep it a few pixels off the exact spot).
	if enemy.global_position.distance_to(_corpse.pos) > 22.0 and not (_walk > 3.0 and enemy.global_position.distance_to(_corpse.pos) < 48.0):
		return true
	if _eat_left < 0.0:
		_eat_left = float(p("channel", 1.2))
		set_state("eating")
		enemy.play_action.rpc("attack", (_corpse.pos - enemy.global_position).normalized())
	return true


func move_override(_delta: float) -> Vector2:
	if _corpse.is_empty() or _eat_left >= 0.0:
		return Vector2.ZERO if _eat_left >= 0.0 else Vector2.INF
	return (_corpse.pos - enemy.global_position).normalized()


func on_physics(delta: float) -> void:
	if _eat_left < 0.0:
		return
	_eat_left -= delta
	if _eat_left <= 0.0:
		var game := enemy.get_tree().get_first_node_in_group("game")
		if game and not game.consume_corpse(int(_corpse.id)).is_empty():
			var ctx := Combat.instance.make_ctx(enemy, {"id": "devour", "school": "melee"})
			Combat.instance.heal(ctx, enemy, enemy.health.max_hp * float(p("heal", 0.5)))
			enemy.status.apply("ghoul_frenzy", 12.0, 0.0, ctx)
			Combat.instance.fx.sound.rpc("devour", enemy.global_position)
		_corpse = {}
		_eat_left = -1.0
		_walk = 0.0
		set_state("")


func test_trigger(suite: RefCounted) -> void:
	enemy.health.hp = enemy.health.max_hp * 0.4
	var victim: Enemy = suite.g.spawn_monster("skeleton_archer", suite.g.nearest_floor(enemy.global_position + Vector2(30, 0)), false)
	await suite.da._wait(0.3)
	victim.def = victim.def.merged({"corpse": "flesh"}, true)
	Combat.instance.deal_damage(Combat.instance.test_ctx(suite.p, GameData.skill(str(suite.p.skills[0]))), victim, victim.health.hp * 5.0, {"damage_type": "true"})


func test_check(_suite: RefCounted) -> String:
	return "" if enemy.status.has("ghoul_frenzy") and enemy.health.fraction() > 0.6 else "no devour"
