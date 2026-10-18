extends BossMechanic
## Isolde P1 - Blood-Thread Bond: links two heroes with a red thread for `duration` s; if they
## drift more than `max_dist` px apart it snaps, dealing `snap` of max health to both.
## params: every (18), duration (10), max_dist (150), snap (0.9)

var pair: Array = []
var _left := -1.0
var _tid := -1
var bonds := 0
var snaps := 0


func trigger() -> void:
	var pool := living_players()
	if pool.size() < 2 or _left > 0.0:
		return
	pool.shuffle()
	pair = pool.slice(0, 2)
	_left = float(p("duration", 10.0))
	_tid = Combat.instance.new_id()
	Combat.instance.fx.tether.rpc(_tid, pair[0].get_path(), pair[1].get_path(), "#ff2030")
	game().broadcast_message.rpc("%s and %s are bound by a Blood Thread - stay together!", "#ff4050", [pair[0].display_name, pair[1].display_name])
	bonds += 1


func physics(delta: float) -> void:
	super.physics(delta)
	if _left <= 0.0:
		return
	_left -= delta
	var ok: bool = pair.size() == 2 and is_instance_valid(pair[0]) and is_instance_valid(pair[1]) and pair[0].is_targetable() and pair[1].is_targetable()
	if not ok:
		_end()
		return
	if pair[0].global_position.distance_to(pair[1].global_position) > float(p("max_dist", 150.0)):
		var c := ctx()
		for pl in pair:
			Combat.instance.deal_damage(c, pl, pl.health.max_hp * float(p("snap", 0.9)), {"damage_type": "true"})
		snaps += 1
		game().broadcast_message.rpc("The Blood Thread snaps!", "#ff2030")
		_end()
	elif _left <= 0.0:
		_end()


func _end() -> void:
	_left = -1.0
	if _tid >= 0:
		Combat.instance.fx.tether_end.rpc(_tid)
		_tid = -1
	pair.clear()


func stop() -> void:
	_end()


func test_check(_suite: RefCounted) -> String:
	# A solo test party can't be bound; the mechanic must then simply wait.
	return "" if bonds > 0 or living_players().size() < 2 else "no bond"
