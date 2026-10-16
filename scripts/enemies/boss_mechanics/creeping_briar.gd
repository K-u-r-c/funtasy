extends BossMechanic
## Cernunnos P1 - Creeping Briar: every `every` s the perimeter roots close in by one ring of the
## arena (living thorns that block movement and shots), up to `max_rings`.
## params: every (60), max_rings (2)

var rings := 0


func trigger() -> void:
	if rings >= int(p("max_rings", 2)):
		return
	var g := game()
	var r: Rect2i = g.layout.rooms[int(g.layout.boss_room)].rect
	var inner := r.grow(-rings)
	var cells: Array = []
	for x in range(inner.position.x, inner.end.x):
		for y in range(inner.position.y, inner.end.y):
			if (x == inner.position.x or y == inner.position.y or x == inner.end.x - 1 or y == inner.end.y - 1) and g.dungeon.cell_at(Vector2i(x, y)) == DungeonGenerator.CELL_FLOOR:
				cells.append(Vector2i(x, y))
	rings += 1
	g.dungeon.add_obstacle.rpc(Combat.instance.new_id(), "briar", cells, 9999.0, "all")
	g.broadcast_message.rpc("The briar creeps inward!", "#5a8a3a")


func test_check(_suite: RefCounted) -> String:
	return "" if rings > 0 else "no briar"
