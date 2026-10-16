extends MonsterBehavior
## Carrion Crawler: burrows under the flagstones (an untargetable mound, never faster than it
## walks) and hunts its target. Next to it - or after `under` s underground at the latest - its
## surfacing spot is telegraphed for `warn` s (part of the `under` s), then it bursts out with a
## venomous burst and fights for `surface` s (at least 4) before burrowing again (#4).
## A crawler without a target lies dormant underground; the clock only runs while it hunts.
## params: under (2.5), warn (0.6), surface (5), speed_mult (1.0, capped at 1), burst (skill id)

enum Phase { BURROWED, SURFACING, UP }

var phase := Phase.BURROWED
var _left := 0.0  ## seconds left surfacing / up
var _under := 0.0  ## seconds underground while hunting, this dive
# Test bookkeeping (host): the longest dive, the shortest stay on the surface, the fastest
# burrowed speed, and whether every surfacing was telegraphed first.
var surfacings := 0
var dives := 0
var longest_under := 0.0
var shortest_up := INF
var fastest_burrowed := 0.0
var telegraphed := true
var _up_time := 0.0


func _ready() -> void:
	set_state("burrowed")


func is_targetable() -> bool:
	return phase == Phase.UP


func on_physics(delta: float) -> void:
	match phase:
		Phase.UP:
			_up_time += delta
			_left -= delta
			if _left <= 0.0 and _hunting():
				phase = Phase.BURROWED
				_under = 0.0
				dives += 1
				shortest_up = minf(shortest_up, _up_time)
				set_state("burrowed")
				Combat.instance.fx.sound.rpc("burrow", enemy.global_position)
		Phase.BURROWED:
			if not _hunting():
				return
			_under += delta
			fastest_burrowed = maxf(fastest_burrowed, enemy.velocity.length())
			var near: bool = enemy.target.global_position.distance_to(enemy.global_position) <= 18.0
			if near or _under + _warn() >= _max_under():
				_begin_surfacing()
		Phase.SURFACING:
			_under += delta
			_left -= delta
			if _left <= 0.0:
				_surface()


func on_think(_game: Node) -> bool:
	return phase == Phase.SURFACING


func move_override(_delta: float) -> Vector2:
	match phase:
		Phase.SURFACING:
			return Vector2.ZERO
		Phase.BURROWED:
			if _hunting():
				return (enemy.target.global_position - enemy.global_position).normalized() * minf(float(p("speed_mult", 1.0)), 1.0)
	return Vector2.INF


func _hunting() -> bool:
	return enemy.target != null and is_instance_valid(enemy.target) and enemy._valid_target(enemy.target)


func _max_under() -> float:
	return float(p("under", 2.5))


func _warn() -> float:
	return float(p("warn", 0.6))


func _begin_surfacing() -> void:
	phase = Phase.SURFACING
	_left = _warn()
	var r := 40.0
	for eff in GameData.skills.get(str(p("burst", "crawler_burst")), {}).get("effects", []):
		r = maxf(r, float(eff.get("radius", 0.0)))
	Combat.instance.fx.windup_marker.rpc("circle", enemy.global_position, enemy.global_position, r, _left, "#88aa33")
	Combat.instance.fx.sound.rpc("burrow", enemy.global_position)


func _surface() -> void:
	telegraphed = telegraphed and phase == Phase.SURFACING
	phase = Phase.UP
	longest_under = maxf(longest_under, _under)
	_left = maxf(float(p("surface", 5.0)), 4.0)
	_up_time = 0.0
	surfacings += 1
	set_state("")
	var burst := str(p("burst", "crawler_burst"))
	enemy.cooldowns.erase(burst)
	Combat.instance.try_use_skill(enemy, burst, enemy.global_position)


func test_check(_suite: RefCounted) -> String:
	if surfacings == 0 or dives == 0:
		return "never surfaced and burrowed again (%d / %d)" % [surfacings, dives]
	if longest_under > _max_under() + 0.05:
		return "%.2f s underground" % longest_under
	if shortest_up < 4.0:
		return "only %.2f s on the surface" % shortest_up
	if fastest_burrowed > enemy.move_speed() + 1.0:
		return "%.0f px/s underground (walks at %.0f)" % [fastest_burrowed, enemy.move_speed()]
	return "" if telegraphed else "surfaced without a telegraph"
