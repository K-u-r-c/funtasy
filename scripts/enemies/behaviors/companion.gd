extends MonsterBehavior
## #99 a freed prisoner fighting at the heroes' side: it follows its leader (the hero who freed it,
## else the nearest living hero) at `follow` px, fights the monsters within `assist` px of the
## leader (or of itself) with its class's abilities, comes back when the fight drifts more than
## `leash` px from the leader, and steps out beside the leader when it is left more than
## `teleport` px behind or stuck for `stuck_time` s. Only on the heroes' side.
## params: follow (60), assist (300), leash (340), teleport (560), stuck_time (2.5)

var leader: Player
var teleports := 0  ## times it caught up by stepping out beside the leader (tests)
var _stuck := 0.0
var _last_pos := Vector2.INF
var _side := 1.0


func _ready() -> void:
	_side = 1.0 if randf() < 0.5 else -1.0


func _on_side() -> bool:
	return enemy.team == Actor.Team.PLAYERS


## The leader: the hero who freed it while that one lives, else the nearest living hero.
func _leader() -> Player:
	var g := game()
	if g == null:
		return null
	var want := int(enemy.get_meta("leader_peer", 0))
	var best: Player = null
	var best_d := INF
	for pl in g.players_root.get_children():
		if not (pl is Player) or pl.life_state != Player.Life.ALIVE:
			continue
		if pl.peer_id == want:
			return pl
		var d: float = pl.global_position.distance_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = pl
	return best


## Monsters near the leader become this ally's foes: they add threat, so the default think picks
## them and uses the class's abilities on them.
func on_think(g: Node) -> bool:
	if not _on_side():
		return false
	leader = _leader()
	if leader == null:
		return false
	var assist := float(p("assist", 300.0))
	for e in g.enemies_root.get_children():
		if e == enemy or not (e is Actor) or e.team == enemy.team or not e.is_alive() or not e.is_targetable():
			continue
		var near_leader: bool = e.global_position.distance_to(leader.global_position) <= assist
		var near_me: bool = e.global_position.distance_to(enemy.global_position) <= assist * 0.6
		if (near_leader or near_me) and Combat.instance.has_los(enemy.global_position, e.global_position):
			enemy.threat.add(e, float(GameData.bal("threat.proximity_threat")))
	return false


func move_override(delta: float) -> Vector2:
	if not _on_side():
		return Vector2.INF
	if leader == null or not is_instance_valid(leader) or leader.life_state != Player.Life.ALIVE:
		leader = _leader()
	if leader == null:
		return Vector2.INF
	var g := game()
	var to_leader := leader.global_position - enemy.global_position
	var d := to_leader.length()
	# Left far behind (another room, a long corridor): step out beside the leader.
	if d > float(p("teleport", 560.0)) or _stuck > float(p("stuck_time", 2.5)):
		_catch_up(g)
		return Vector2.ZERO
	var fighting: bool = enemy.target != null and is_instance_valid(enemy.target) and enemy.target.is_alive()
	if fighting and enemy.target.global_position.distance_to(leader.global_position) <= float(p("leash", 340.0)):
		_track_stuck(delta, false)
		return Vector2.INF  # the default chase / keep-range of its class
	if d <= float(p("follow", 60.0)):
		_track_stuck(delta, false)
		return Vector2.ZERO
	# Walk to a spot at the leader's side (through doors and around corners: the path finder).
	var spot: Vector2 = leader.global_position + to_leader.normalized().orthogonal() * 28.0 * _side - to_leader.normalized() * 20.0
	_track_stuck(delta, true)
	return enemy._path_dir(g, spot, delta)


func _track_stuck(delta: float, moving: bool) -> void:
	# Casting, stunned or rooted is standing still on purpose, not being stuck.
	if not moving or not enemy.casting.is_empty() or not enemy.can_act() or enemy.status.has_flag("rooted"):
		_stuck = 0.0
		_last_pos = enemy.global_position
		return
	if _last_pos != Vector2.INF and enemy.global_position.distance_to(_last_pos) < 20.0 * delta:
		_stuck += delta
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	_last_pos = enemy.global_position


func _catch_up(g: Node) -> void:
	_stuck = 0.0
	var behind := leader.global_position - leader.facing * 34.0 + leader.facing.orthogonal() * 18.0 * _side
	var at: Vector2 = g.nearest_floor(behind)
	if not g.dungeon.reach_clear(leader.global_position, at):
		at = g.nearest_floor(leader.global_position)
	Combat.instance.fx.blink.rpc(enemy.global_position, at)
	enemy.host_teleport(at)
	enemy.velocity = Vector2.ZERO
	_last_pos = at
	teleports += 1
