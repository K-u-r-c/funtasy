extends BossMechanic
## Vulkania P2: volcanic boulders smash the outer walkway - every `every` s another ring of the
## arena's edge turns to molten lava, until `max_rings` rings (about 30% of the arena) are gone.
## params: every (10), max_rings (2)

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
			if x == inner.position.x or y == inner.position.y or x == inner.end.x - 1 or y == inner.end.y - 1:
				if g.dungeon.cell_at(Vector2i(x, y)) != DungeonGenerator.CELL_WALL:
					cells.append(Vector2i(x, y))
	rings += 1
	Combat.instance.fx.sound.rpc("explosion", boss.global_position)
	g.broadcast_message.rpc("Boulders smash the outer walkway!", "#ff7a2a")
	g.dungeon.set_cells.rpc(cells, DungeonGenerator.CELL_LAVA)


func test_check(_suite: RefCounted) -> String:
	return "" if rings > 0 else "arena untouched"
