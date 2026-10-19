extends MonsterBehavior
## Tomb Cultist: every `every` s it channels a dark chant over a fallen skeleton within `radius`
## and raises it again. params: every (8), radius (150), channel (2), hp (0.5), kinds ([...]).
## While the chant runs every peer sees the rise mark on that corpse (#49); it goes when the corpse
## rises, the chant is broken or the cultist dies.

var _left := 4.0
var _corpse := {}
var _chant := -1.0


func on_think(game: Node) -> bool:
	if _chant >= 0.0:
		return true
	_left -= float(GameData.bal("ai.think_interval"))
	if _left > 0.0 or not enemy.can_act():
		return false
	var kinds: Array = p("kinds", ["skeletal_footman", "skeleton_archer"])
	for c in game.corpses_near(enemy.global_position, float(p("radius", 150.0))):
		if kinds.has(c.def_id):
			_corpse = c
			_chant = float(p("channel", 2.0))
			_left = float(p("every", 8.0))
			Combat.instance.fx.cast_bar.rpc(enemy.get_path(), _chant)
			enemy.play_action.rpc("cast", (c.pos - enemy.global_position).normalized())
			Combat.instance.fx.sound.rpc("chant", enemy.global_position)
			set_state("chanting")
			game.host_rise_mark(game.corpse_node(int(c.id)), _chant, "raise")
			return true
	return false


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if _chant >= 0.0 else Vector2.INF


func on_damaged(_attacker: Actor, _amount: float) -> void:
	pass


func on_death() -> bool:
	_stop_chant()
	return false


func _stop_chant() -> void:
	if _chant >= 0.0 and not _corpse.is_empty():
		var game := enemy.get_tree().get_first_node_in_group("game")
		if game:
			game.host_rise_clear(game.corpse_node(int(_corpse.id)))
	_chant = -1.0
	set_state("")


func on_physics(delta: float) -> void:
	if _chant < 0.0:
		return
	if not enemy.can_act():
		_stop_chant()
		return
	_chant -= delta
	if _chant <= 0.0:
		_stop_chant()
		var game := enemy.get_tree().get_first_node_in_group("game")
		if game and not game.consume_corpse(int(_corpse.id)).is_empty():
			var e: Enemy = game.spawn_monster(str(_corpse.def_id), _corpse.pos, false)
			if e:
				e.set_meta("raised", true)
				e.health.hp = e.health.max_hp * float(p("hp", 0.5))
				for pl in game.players_root.get_children():
					if pl.is_targetable():
						e.add_threat(pl, 1.0)
			Combat.instance.fx.ring.rpc(_corpse.pos, 40.0, "#8040c0", "")


func test_trigger(suite: RefCounted) -> void:
	_left = 0.0
	var victim: Enemy = suite.g.spawn_monster("skeleton_archer", suite.g.nearest_floor(enemy.global_position + Vector2(40, 0)), false)
	await suite.da._wait(0.3)
	Combat.instance.deal_damage(Combat.instance.test_ctx(suite.p, GameData.skill(str(suite.p.skills[0]))), victim, victim.health.hp * 5.0, {"damage_type": "true"})
	await suite.da._wait(0.2)


func test_check(suite: RefCounted) -> String:
	for e in suite.g.enemies_root.get_children():
		if e.has_meta("raised"):
			return ""
	return "nothing raised"
