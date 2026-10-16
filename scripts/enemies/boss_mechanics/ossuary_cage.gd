extends BossMechanic
## Morvath P1 - Ossuary Cage: bone spears encase a random player; teammates must break them
## (they are destructible props) before the execution strike lands after `timer` s.
## params: every, timer (6), spears (4), execute (0.6 = share of the victim's max HP)

var victim: Player = null
var spears: Array = []
var _t := -1.0
var _n := 0


func trigger() -> void:
	if _t >= 0.0:
		return
	var pool := living_players()
	if pool.is_empty():
		return
	victim = pool[randi() % pool.size()]
	_n += 1
	spears.clear()
	var g := game()
	for i in int(p("spears", 4)):
		var nm := "Cage_%d_%d_%d" % [boss.get_instance_id() % 1000, _n, i]
		var pos: Vector2 = victim.global_position + Vector2.from_angle(TAU * i / float(p("spears", 4))) * 20.0
		g.dungeon.spawn_prop.rpc(nm, "bone_spears", pos)
		spears.append(nm)
	Combat.instance.apply_status(ctx(), victim, "caged", float(p("timer", 6.0)), 0.0)
	_t = float(p("timer", 6.0))
	g.broadcast_message.rpc("Ossuary Cage! Break the bone spears around %s!" % victim.display_name, "#e8e0c8")
	Combat.instance.fx.sound.rpc("cage", victim.global_position)


func physics(delta: float) -> void:
	super.physics(delta)
	if _t < 0.0:
		return
	_t -= delta
	if remaining() == 0:
		_release()
	elif _t <= 0.0:
		if is_instance_valid(victim) and victim.is_targetable():
			Combat.instance.deal_damage(ctx(), victim, victim.health.max_hp * float(p("execute", 0.6)), {"damage_type": "true"})
			Combat.instance.fx.ring.rpc(victim.global_position, 30.0, "#ff2020", "explosion")
		_release()


func remaining() -> int:
	var g := game()
	var n := 0
	for nm in spears:
		var pr: Node = g.dungeon.props.get(nm)
		if pr and is_instance_valid(pr) and pr.destructible():
			n += 1
	return n


func _release() -> void:
	_t = -1.0
	var g := game()
	for nm in spears:
		var pr: Node = g.dungeon.props.get(nm)
		if pr and is_instance_valid(pr) and pr.destructible():
			g.dungeon.destroy_prop.rpc(nm)
	spears.clear()
	if is_instance_valid(victim):
		victim.status.remove("caged")


func stop() -> void:
	if _t >= 0.0:
		_release()


func test_check(_suite: RefCounted) -> String:
	if spears.size() == int(p("spears", 4)) and is_instance_valid(victim) and victim.status.has("caged"):
		# The test breaks the spears like teammates would.
		var g := game()
		for nm in spears:
			var pr: Node = g.dungeon.props.get(nm)
			if pr and pr.destructible():
				pr.take_damage(999.0, Combat.instance.make_ctx(victim, {"id": "t", "school": "melee"}))
		return "spears broken, waiting"
	return "" if spears.is_empty() and (victim == null or not victim.status.has("caged")) else "cage still up"
