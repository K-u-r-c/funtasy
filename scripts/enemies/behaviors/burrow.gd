extends MonsterBehavior
## Carrion Crawler: burrows under the flagstones (untargetable mound, fast), surfaces under its
## target's feet with a venomous burst, fights for `surface` s and burrows again.
## params: surface (6), speed_mult (1.8), burst (skill id)

var _burrowed := true
var _left := 0.0


func _ready() -> void:
	set_state("burrowed")


func is_targetable() -> bool:
	return not _burrowed


func on_think(_game: Node) -> bool:
	if not _burrowed:
		_left -= float(GameData.bal("ai.think_interval"))
		if _left <= 0.0:
			_burrowed = true
			set_state("burrowed")
			Combat.instance.fx.sound.rpc("burrow", enemy.global_position)
		return false
	var t: Actor = enemy.target
	if t == null or not enemy._valid_target(t):
		return false
	if t.global_position.distance_to(enemy.global_position) <= 18.0:
		_burrowed = false
		_left = float(p("surface", 6.0))
		set_state("")
		Combat.instance.try_use_skill(enemy, str(p("burst", "crawler_burst")), t.global_position)
	return false


func move_override(_delta: float) -> Vector2:
	if not _burrowed or enemy.target == null or not is_instance_valid(enemy.target):
		return Vector2.INF
	return (enemy.target.global_position - enemy.global_position).normalized() * float(p("speed_mult", 1.8))


func test_check(_suite: RefCounted) -> String:
	var uses: Dictionary = Combat.instance.get_meta("uses", {})
	return "" if uses.has("%s:%s" % [enemy.name, p("burst", "crawler_burst")]) else "never surfaced"
