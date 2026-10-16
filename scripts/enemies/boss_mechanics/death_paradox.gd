extends BossMechanic
## Memory Devourer P2 - Death Paradox: a hero who goes down crystallises into a temporal prism
## that explodes on the whole party after `fuse` s unless the allies shatter it. Cosmic laser
## grids sweep the arena every `grid_every` s. params: fuse (6), grid_every (9), damage, grid_damage

var _prisms: Dictionary = {}  ## prop name -> seconds left
var _known_down: Dictionary = {}
var _grid := 3.0
var made := 0
var grids := 0


func physics(delta: float) -> void:
	var g := game()
	for pl in g.players_root.get_children():
		var down: bool = pl.life_state == Player.Life.DOWNED
		if down and not _known_down.has(pl):
			_known_down[pl] = true
			crystallize(pl)
		elif not down:
			_known_down.erase(pl)
	for nm in _prisms.keys():
		var pr: Node = g.dungeon.props.get(nm)
		if pr == null or not is_instance_valid(pr) or not pr.destructible():
			_prisms.erase(nm)
			continue
		_prisms[nm] = float(_prisms[nm]) - delta
		if float(_prisms[nm]) <= 0.0:
			var c := ctx()
			for pl2 in living_players():
				Combat.instance.deal_damage(c, pl2, Combat.instance.value_of_spec(p("damage", {"base": 20, "coef": 2.0}), c), {"damage_type": "arcane", "area": true})
			Combat.instance.fx.ring.rpc(pr.global_position, 200.0, "#c0e0ff", "explosion")
			g.dungeon.destroy_prop.rpc(nm)
			_prisms.erase(nm)
	_grid -= delta
	if _grid <= 0.0:
		_grid = float(p("grid_every", 9.0))
		_laser_grid()


## A fallen hero becomes a temporal prism that blasts the party unless shattered in time.
func crystallize(pl: Node) -> void:
	var nm := "Prism_%d_%d" % [pl.peer_id, made]
	game().dungeon.spawn_prop.rpc(nm, "temporal_prism", pl.global_position + Vector2(0, 4))
	_prisms[nm] = float(p("fuse", 6.0))
	made += 1


func _laser_grid() -> void:
	var room := boss_room()
	var c := ctx()
	c.damage_type = "arcane"
	var horizontal := randf() < 0.5
	for i in 3:
		var f := (i + 0.5 + randf_range(-0.3, 0.3)) / 3.0
		var a := Vector2(room.position.x, room.position.y + room.size.y * f) if horizontal else Vector2(room.position.x + room.size.x * f, room.position.y)
		var dir := Vector2.RIGHT if horizontal else Vector2.DOWN
		var length := room.size.x if horizontal else room.size.y
		for k in 6:
			Combat.instance.fx.telegraph.rpc(a + dir * length * (k + 0.5) / 6.0, 14.0, "#c0e0ff", 1.2)
		Combat.instance.run_effect({"type": "delayed", "delay": 1.2, "at": "self", "effects": [
			{"type": "line", "length": length, "width": 18, "damage": p("grid_damage", {"base": 6, "coef": 1.0}), "damage_type": "arcane", "color": "#c0e0ff"}]},
			c, a, a + dir * length)
	grids += 1


func stop() -> void:
	var g := game()
	for nm in _prisms.keys():
		if g.dungeon.props.has(nm):
			g.dungeon.destroy_prop.rpc(nm)
	_prisms.clear()


func test_trigger(suite: RefCounted) -> void:
	_grid = 0.0
	# A fallen hero crystallises (simulated: a solo test party can't lose its only hero), then the
	# party shatters the prism.
	crystallize(suite.p)
	await suite.da._wait(0.3)
	var g := game()
	for nm in _prisms.keys():
		g.dungeon.props[nm].take_damage(9999.0, Combat.instance.test_ctx(suite.p, {"id": "t", "school": "melee"}))


func test_check(_suite: RefCounted) -> String:
	return "" if made > 0 and grids > 0 and _prisms.is_empty() else "prisms %d grids %d" % [made, grids]
