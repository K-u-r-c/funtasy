extends MonsterBehavior
## Gutter Stalker (submerged), Bramble Warden (camouflaged): hidden under a stealth status. While
## it hunts a hero it stays hidden for at most `under` s; next to its target (or when the time is
## up) its spot is telegraphed for `warn` s (part of the `under` s), then it surfaces with its
## first ability - still a critical strike from stealth (stealth rule in Combat). Being hit
## reveals it at once. It hides again only after at least `surface` s (4 or more) above, and
## `rest` s without a hero within 120 px (#4). It moves no faster than it walks while hidden.
## params: status (submerged), under (2.5), warn (0.6), surface (4), rest (6), strike (48)

var _calm := 0.0
var _hidden_t := 0.0  ## seconds hidden while hunting, this dive
var _warn_left := -1.0
var _reveal_left := -1.0
var _up_t := 0.0
# Test bookkeeping (host).
var surfacings := 0
var longest_hidden := 0.0
var telegraphed := true
var _was_warned := false


func _ready() -> void:
	enemy.status.apply(_status(), -1.0, 0.0, Combat.instance.env_ctx(0.0))


func _status() -> String:
	return str(p("status", "submerged"))


func _hidden() -> bool:
	return enemy.status.has(_status())


func _hunting() -> bool:
	return enemy.target != null and is_instance_valid(enemy.target) and enemy._valid_target(enemy.target)


func on_damaged(_attacker: Actor, _amount: float) -> void:
	if _hidden() or _warn_left >= 0.0:
		_end_dive()
	enemy.status.remove(_status())
	_warn_left = -1.0
	_calm = 0.0


func on_think(_game: Node) -> bool:
	# While hidden and hunting (or surfacing) it neither attacks nor switches targets: the only
	# way out of hiding is the telegraphed surfacing.
	return _warn_left >= 0.0 or (_hidden() and _hunting())


func move_override(_delta: float) -> Vector2:
	return Vector2.ZERO if _warn_left >= 0.0 else Vector2.INF


func on_physics(delta: float) -> void:
	if _warn_left >= 0.0:
		_hidden_t += delta
		_warn_left -= delta
		if _warn_left < 0.0:
			_surface()
		return
	if _reveal_left >= 0.0:
		_reveal_left -= delta
		if _reveal_left < 0.0:
			enemy.status.remove(_status())
	if _hidden():
		if _reveal_left >= 0.0 or not _hunting():
			return
		_hidden_t += delta
		var d: float = enemy.target.global_position.distance_to(enemy.global_position)
		if d <= float(p("strike", 48.0)) or _hidden_t + float(p("warn", 0.6)) >= float(p("under", 2.5)):
			_begin_warning()
		return
	_up_t += delta
	_calm += delta
	var t: Actor = enemy.target
	if t and is_instance_valid(t) and t.global_position.distance_to(enemy.global_position) < 120.0:
		_calm = 0.0
	if _calm >= float(p("rest", 6.0)) and _up_t >= maxf(float(p("surface", 4.0)), 4.0):
		_calm = 0.0
		_hidden_t = 0.0
		enemy.status.apply(_status(), -1.0, 0.0, Combat.instance.env_ctx(0.0))
		Combat.instance.fx.sound.rpc("splash", enemy.global_position)


func _begin_warning() -> void:
	_warn_left = float(p("warn", 0.6))
	_was_warned = true
	Combat.instance.fx.windup_marker.rpc("circle", enemy.global_position, enemy.global_position, 26.0, _warn_left, "#7a9a5a")
	Combat.instance.fx.sound.rpc("splash", enemy.global_position)


## The warning is over: strike from hiding if the target is in reach, then show itself.
func _surface() -> void:
	_warn_left = -1.0
	telegraphed = telegraphed and _was_warned
	_end_dive()
	_reveal_left = 0.5
	if _hunting() and not enemy._abilities.is_empty():
		var sid := str(enemy._abilities[0])
		var sk := GameData.skill(sid)
		var dist: float = enemy.target.global_position.distance_to(enemy.global_position)
		if enemy._ability_usable(sk, dist, Combat.instance.has_los(enemy.global_position, enemy.target.global_position)):
			Combat.instance.try_use_skill(enemy, sid, enemy.target.global_position)


func _end_dive() -> void:
	longest_hidden = maxf(longest_hidden, _hidden_t)
	_hidden_t = 0.0
	_up_t = 0.0
	_was_warned = false
	surfacings += 1


func test_check(_suite: RefCounted) -> String:
	if surfacings == 0:
		return "never surfaced"
	if longest_hidden > float(p("under", 2.5)) + 0.05:
		return "%.2f s hidden" % longest_hidden
	return "" if telegraphed else "surfaced without a telegraph"
