extends MonsterBehavior
## Archive Gargoyle: perches as a stone statue (untargetable) until a hero casts a spell (or
## channels) within `range` px - or simply comes close - then dives onto them, interrupting the
## cast. It fights on, and perches again after `rest` s without a target in reach.
## params: range (300), wake (90), skill (gargoyle_dive)

var perched := true
var dives := 0


func _ready() -> void:
	set_state("statue")


func is_targetable() -> bool:
	return not perched


func on_think(g: Node) -> bool:
	if not perched:
		return false
	for pl in g.players_root.get_children():
		if not pl.is_targetable():
			continue
		var d: float = pl.global_position.distance_to(enemy.global_position)
		var casting: bool = not pl.casting.is_empty() or not pl.channel.is_empty()
		if (casting and d <= float(p("range", 300.0))) or d <= float(p("wake", 90.0)):
			perched = false
			set_state("")
			enemy.add_threat(pl, 30.0)
			enemy.target = pl
			enemy.cooldowns.erase(str(p("skill", "gargoyle_dive")))
			Combat.instance.try_use_skill(enemy, str(p("skill", "gargoyle_dive")), pl.global_position)
			dives += 1
			return false
	return true


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if perched else Vector2.INF


func test_trigger(suite: RefCounted) -> void:
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(60, 0)))


func test_check(_suite: RefCounted) -> String:
	return "" if dives > 0 else "never dove"
