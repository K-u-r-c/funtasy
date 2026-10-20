class_name AltarSuite
extends RefCounted
## #63 Elite altars never block the way (scenario "altars", solo): an elite killed in a doorway
## and one killed in a corridor raise their altars on open floor (all eight neighbouring cells
## open, clear of every door), and a saved altar in a doorway is moved off it on restore.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _altars() -> Array:
	return g.dungeon.props.values().filter(func(pr): return is_instance_valid(pr) and pr.type == "elite_altar")


## "" when an altar at `at` leaves the way open, else why not.
func blocks(at: Vector2) -> String:
	var c: Vector2i = g.dungeon.cell_of(at)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if g.dungeon.cell_at(c + Vector2i(dx, dy)) != DungeonGenerator.CELL_FLOOR:
				return "a neighbouring cell is not open floor"
	for d in g.dungeon.doors:
		if Rect2(d.world_rect).grow(float(g.dungeon.tile)).has_point(at):
			return "right by %s" % d.name
	return ""


## Kills an elite standing at `at` and returns where its altar rose.
func elite_dies_at(at: Vector2) -> Vector2:
	var before := _altars().size()
	var mod: String = GameData.elite_modifiers.keys()[0]
	var e: Node = g.spawn_monster(str(g.floor_def.monsters[0].id), at, false, {"elite": [mod]})
	await da._wait(0.3)
	e.global_position = at
	# Some monsters cheat death once (Skeletal Footman stands up at 1 HP): strike until it falls.
	for i in 5:
		if not is_instance_valid(e) or not e.is_alive():
			break
		Combat.instance.deal_damage(Combat.instance.test_ctx(p, GameData.skill(str(p.skills[0]))), e, e.health.hp + 50.0, {"damage_type": "true"})
		await da._wait(0.2)
	await da._wait_until(func(): return _altars().size() > before, 3.0)
	var all := _altars()
	return all[-1].global_position if all.size() > before else Vector2.INF


func _corridor_cell() -> Vector2:
	var rooms: Array = g.layout.rooms.map(func(r): return Rect2i(r.rect).grow(1))
	var d: Node = g.dungeon
	for y in d.size.y:
		for x in d.size.x:
			var c := Vector2i(x, y)
			if d.cell_at(c) != DungeonGenerator.CELL_FLOOR or rooms.any(func(r): return r.has_point(c)):
				continue
			var at: Vector2 = d.cell_center(c)
			if not g.in_doorway(at):
				return at
	return Vector2.INF


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	var door: Node = null
	for d in g.dungeon.doors:
		if not d.sealed and d.kind.is_empty():
			door = d
			break
	da.check(door != null, "an ordinary door on the floor")
	if door == null:
		return
	door.host_set_open(true)
	await da._wait(0.3)
	var in_door: Vector2 = Rect2(door.world_rect).get_center()
	var at := await elite_dies_at(in_door)
	da.check(at != Vector2.INF and blocks(at).is_empty(), "an elite killed in a doorway raises its altar on open floor (%s)" % (blocks(at) if at != Vector2.INF else "no altar"))
	var corridor := _corridor_cell()
	da.check(corridor != Vector2.INF, "a corridor cell on the floor")
	if corridor != Vector2.INF:
		var at2 := await elite_dies_at(corridor)
		da.check(at2 != Vector2.INF and blocks(at2).is_empty(), "an elite killed in a corridor raises its altar out of the corridor (%s)" % (blocks(at2) if at2 != Vector2.INF else "no altar"))
	# #55 save from before the fix: the altar stood in the doorway; restoring moves it.
	var v := FloorState.view_of({"altars": [{"name": "Altar_saved", "type": "elite_altar", "pos": [in_door.x, in_door.y], "opened": false}]}, Vector2.ZERO, g)
	var restored := FloorState.vec(v.altars[0].pos)
	da.check(blocks(restored).is_empty(), "a saved altar in a doorway is restored on open floor (%.0f px away)" % restored.distance_to(in_door))
