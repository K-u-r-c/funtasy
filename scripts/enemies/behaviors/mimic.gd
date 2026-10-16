extends MonsterBehavior
## Tomebound Mimic: sits disguised as a lectern (untargetable, no health bar) until a hero comes
## within `reach` px or hits it, then snaps open with its bite. params: reach (40), skill

var revealed := false


func _ready() -> void:
	set_state("disguised")


func is_targetable() -> bool:
	return revealed


func on_think(g: Node) -> bool:
	if revealed:
		return false
	for pl in g.players_root.get_children():
		if pl.is_targetable() and pl.global_position.distance_to(enemy.global_position) <= float(p("reach", 40.0)):
			_reveal(pl)
			return false
	return true


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if not revealed else Vector2.INF


func _reveal(pl: Actor) -> void:
	revealed = true
	set_state("")
	enemy.add_threat(pl, 30.0)
	enemy.target = pl
	Combat.instance.fx.sound.rpc("roar", enemy.global_position)
	enemy.cooldowns.erase(str(p("skill", "mimic_bite")))
	Combat.instance.try_use_skill(enemy, str(p("skill", "mimic_bite")), pl.global_position)


func test_trigger(suite: RefCounted) -> void:
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(24, 0)))


func test_check(_suite: RefCounted) -> String:
	return "" if revealed else "still disguised"
