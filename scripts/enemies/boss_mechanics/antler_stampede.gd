extends BossMechanic
## Cernunnos P1 - Antler Stampede: four stone dolmens stand in the arena. Every `every` s he
## charges at a hero in a straight line, smashing dolmens in his path; slamming into the arena
## wall stuns him for `stun` s. params: every (14), speed (420), stun (3), dolmens (4), damage

var dolmens: Array = []
var _dir := Vector2.ZERO
var _left := -1.0
var charges := 0
var walls := 0


func _ready() -> void:
	var room := boss_room()
	var g := game()
	var spots := [Vector2(0.25, 0.3), Vector2(0.75, 0.3), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for i in mini(int(p("dolmens", 4)), spots.size()):
		var nm := "Dolmen_%d" % i
		g.dungeon.spawn_prop.rpc(nm, "dolmen", g.nearest_floor(room.position + room.size * spots[i]))
		dolmens.append(nm)


func busy() -> bool:
	return _left > 0.0


func trigger() -> void:
	var pool := living_players()
	if pool.is_empty() or _left > 0.0:
		return
	var t: Node = pool[randi() % pool.size()]
	_dir = (t.global_position - boss.global_position).normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	_left = 2.5
	charges += 1
	boss.play_action.rpc("dash", _dir)
	Combat.instance.fx.sound.rpc("roar", boss.global_position)
	game().broadcast_message.rpc("Antler Stampede!", "#80ff60")


func physics(delta: float) -> void:
	super.physics(delta)
	if _left <= 0.0:
		return
	_left -= delta
	var before: Vector2 = boss.global_position
	boss.velocity = _dir * float(p("speed", 420.0))
	boss.move_and_slide()
	var c := ctx()
	for pl in living_players():
		if pl.global_position.distance_to(boss.global_position) < 30.0 and not pl.has_meta("stampede_hit"):
			pl.set_meta("stampede_hit", true)
			Combat.instance.deal_damage(c, pl, Combat.instance.value_of_spec(p("damage", {"base": 8, "coef": 1.6}), c), {"area": true})
			Combat.instance.knock(pl, _dir.orthogonal() * 200.0)
	var g := game()
	for nm in dolmens.duplicate():
		var pr: Node = g.dungeon.props.get(nm)
		if pr and is_instance_valid(pr) and pr.global_position.distance_to(boss.global_position) < 34.0:
			g.dungeon.destroy_prop.rpc(nm)
	if boss.global_position.distance_to(before) < float(p("speed", 420.0)) * delta * 0.3:
		_left = -1.0
		walls += 1
		Combat.instance.apply_status(c, boss, "stun", float(p("stun", 3.0)), 0.0)
		Combat.instance.fx.ring.rpc(boss.global_position, 40.0, "#c0c0a0", "explosion")
		g.broadcast_message.rpc("Cernunnos crashes into the wall!", "#c0ffc0")
	if _left <= 0.0:
		for pl2 in g.players_root.get_children():
			pl2.remove_meta("stampede_hit")


func stop() -> void:
	_left = -1.0


func test_trigger(_suite: RefCounted) -> void:
	trigger()


func test_check(_suite: RefCounted) -> String:
	return "" if charges > 0 and _left <= 0.0 else "still charging"
