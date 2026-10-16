extends Node2D
## Foundry collapsing grate (GDD 1.3): an iron grate over molten rock. A hero standing on it for
## `hold` s makes it collapse - the cell turns to lava for `down` s, then a new grate swings in.
## The host decides; Dungeon.set_cells replicates the cell change.

var cell := Vector2i.ZERO
var grate_id := ""
var _stand := 0.0
var _down := -1.0
var _sprite: Sprite2D


func setup(c: Vector2i, tile: int, id: String) -> void:
	cell = c
	grate_id = id
	position = Vector2(c * tile) + Vector2(tile, tile) / 2.0
	z_index = -9
	_sprite = Sprite2D.new()
	_sprite.texture = GameData.texture("props.grate")
	add_child(_sprite)


func host_tick(delta: float, actors: Array, dungeon: Node) -> void:
	if _down >= 0.0:
		_down -= delta
		if _down < 0.0:
			dungeon.set_cells.rpc([cell], DungeonGenerator.CELL_GRATE)
			dungeon.grate_state.rpc(grate_id, true)
		return
	var on := false
	for a in actors:
		if a is Player and a.is_targetable() and dungeon.cell_of(a.global_position) == cell:
			on = true
	_stand = _stand + delta if on else 0.0
	if _stand >= float(GameData.bal("hazards.grate_hold", 0.8)):
		_stand = 0.0
		_down = float(GameData.bal("hazards.grate_down", 6.0))
		dungeon.set_cells.rpc([cell], DungeonGenerator.CELL_LAVA)
		dungeon.grate_state.rpc(grate_id, false)


## Every peer.
func show_state(up: bool) -> void:
	_sprite.visible = up
	AudioManager.play_sfx_at("break" if not up else "door", position)
