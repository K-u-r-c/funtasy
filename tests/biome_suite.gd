class_name BiomeSuite
extends RefCounted
## Headless biome checks (scenario "biomes", solo host). For every floor type (or --biome=<id>):
## generated layouts over several seeds are connected and carry the biome's hazards, the boss
## pick covers the whole boss list, and the floor's monsters / props come from the biome's data.
## On the live floor (the run's first floor type) the hazards hurt and every floor mechanic runs
## its own test_trigger / test_check.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run(biome: String = "") -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var ids: Array = GameData.floor_types.keys()
	ids.sort()
	for id in ids:
		if biome.is_empty() or id == biome:
			check_layouts(str(id))
	await check_live_floor()


func check_layouts(fid: String) -> void:
	var fd: Dictionary = GameData.floor_types[fid]
	var monsters := {}
	for m in fd.monsters:
		monsters[str(m.id)] = true
	var allowed_props := {"pillar": true, "bookshelf": true, str(fd.get("secret_container", "secret_sarcophagus")): true}
	for k in fd.get("prop_weights", {}):
		allowed_props[k] = true
	var plates := 0
	var pendulums := 0
	var bad := ""
	for i in 6:
		var seed_value := 1000 + i * 7919
		var lay: Dictionary = DungeonGenerator.new().generate(seed_value, fd, 1.0, 1 + i)
		var reach := _flood(lay, lay.start)
		for room in lay.rooms:
			if not reach.has(Vector2i(room.rect.get_center())):
				bad = "room %s unreachable (seed %d)" % [room.role, seed_value]
		for grp in lay.spawns:
			for m in grp.monsters:
				if not monsters.has(str(m.id)):
					bad = "foreign monster %s" % m.id
		for pr in lay.props:
			if not allowed_props.has(str(pr.type)):
				bad = "foreign prop %s" % pr.type
		if lay.get("merchant", {}).is_empty():
			bad = "no merchant chamber (seed %d)" % seed_value
		plates += lay.get("plates", []).size()
		pendulums += lay.get("pendulums", []).size()
	da.check(bad.is_empty(), "%s layouts are connected and use the biome's monsters and props%s" % [fid, "" if bad.is_empty() else ": " + bad])
	if fd.has("plates_per_room"):
		da.check(plates > 0, "%s layouts have pressure plates (%d over 6 floors)" % [fid, plates])
	if fd.has("pendulums"):
		da.check(pendulums > 0, "%s layouts have pendulums (%d over 6 floors)" % [fid, pendulums])
	var picked := {}
	for s in 60:
		picked[g.pick_boss(fd, s * 31 + 7)] = true
	var pool: Array = fd.get("bosses", [fd.get("boss", "")])
	da.check(picked.size() == pool.size(), "%s boss pick covers %s" % [fid, ", ".join(pool)])


func check_live_floor() -> void:
	var fid := str(g.floor_def.id)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	da.check(g.floor_mechanics.size() == g.floor_def.get("floor_mechanics", []).size(), "%s floor mechanics are running (%d)" % [fid, g.floor_mechanics.size()])
	if not g.dungeon.plates.is_empty():
		var plate: Node2D = g.dungeon.plates[0]
		_ready_hero()
		p.host_teleport(plate.global_position + Vector2(0, -6))
		var hp := p.health.hp
		await da._wait(1.2)
		da.check(p.health.hp < hp, "a pressure plate raises spikes under the hero (%.0f -> %.0f)" % [hp, p.health.hp])
	if not g.dungeon.pendulums.is_empty():
		var pend: Node2D = g.dungeon.pendulums[0]
		_ready_hero()
		var hp2 := p.health.hp
		var t := 0.0
		while t < 3.0 and p.health.hp >= hp2:
			p.host_teleport(pend.global_position + pend.blade_offset(g.floor_time))
			await da.get_tree().physics_frame
			t += 1.0 / 60.0
		da.check(p.health.hp < hp2, "the pendulum blade cuts the hero")
	for fm in g.floor_mechanics:
		_ready_hero()
		p.iframe_left = 9999.0
		await fm.test_trigger(self)
		var mt := 0.0
		var err := "not checked"
		while mt < float(fm.params.get("test_wait", 4.0)):
			p.health.hp = p.health.max_hp
			err = fm.test_check(self)
			if err.is_empty():
				break
			await da._wait(0.25)
			mt += 0.25
		da.check(err.is_empty(), "%s mechanic %s%s" % [fid, fm.params.get("id", "?"), "" if err.is_empty() else ": " + err])
	_ready_hero()
	p.iframe_left = 9999.0


## A floor position (away from the merchant chamber) that satisfies `pred`.
func find_spot(pred: Callable) -> Vector2:
	var d: Node = g.dungeon
	for y in range(2, d.size.y - 2):
		for x in range(2, d.size.x - 2):
			var c := Vector2i(x, y)
			if d.cell_at(c) != DungeonGenerator.CELL_FLOOR or d.safe_rect.has_point(c):
				continue
			var pos: Vector2 = d.cell_center(c)
			if pred.call(pos):
				return pos
	return p.global_position


func _ready_hero() -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.iframe_left = 0.0
	p.status.clear_all()
	p.stats.final.dodge = 0.0
	p.health.hp = p.health.max_hp


func _flood(lay: Dictionary, from: Vector2) -> Dictionary:
	var tile := int(GameData.bal("world.tile_size"))
	var size: Vector2i = lay.size
	var cells: PackedByteArray = lay.cells
	var start := Vector2i(from / tile)
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y or seen.has(n):
				continue
			if cells[n.y * size.x + n.x] == DungeonGenerator.CELL_WALL:
				continue
			seen[n] = true
			queue.append(n)
	return seen
