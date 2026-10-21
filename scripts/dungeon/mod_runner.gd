class_name ModRunner
extends Node
## #71: the floor modifiers that act during the floor, on the host, with their telegraphs on every
## peer.
## - Restless: each living hero's stillness (seconds without leaving a `still_radius` circle,
##   counted only with an awake monster within `needs_monster_cells` and outside safe rooms) is
##   replicated (Player.restless); the meter under the hero shows it (RestlessMeter), turns red
##   with a sound at `warn_at`, and from `still_time` every `tick` adds a restless_curse stack
##   (damage taken up) and burns `burn_pct` of max health. Moving clears it.
## - Hunted: a hunter every `interval` s (the first after `first`), never once the boss fight
##   starts or with `max_alive` hunters up. `warn` s before, a rift opens at the spawn point on
##   every peer (HuntRift: beam, particles, the hunter's name, a countdown, a minimap ping); then
##   the hunter steps out: an elite of the floor's pool with `elite_mods` modifiers, its own name,
##   more health (per extra hero too) and a sure fine drop. The HUD counts down to the next one.

var game: Node
var _hunt_at := -1.0  ## floor_time of the next hunter (host; replicated as Game.hunt_next_at)
var _rift: Dictionary = {}  ## host: the open rift {pos, name, at}
var _hunters := 0
var _rng := RandomNumberGenerator.new()


func setup(g: Node) -> void:
	game = g


func cfg(key: String, default: Variant = null) -> Variant:
	return game.floor_def.get("mod_def", {}).get(key, default)


func mod() -> String:
	return str(game.floor_def.get("mod", ""))


## Host: a new floor (also a continued one: the timers restart, stacks start clear).
func host_new_floor(floor_seed: int) -> void:
	_rng.seed = hash([floor_seed, 713])
	_rift = {}
	_hunters = 0
	_hunt_at = -1.0
	if mod() == "hunted":
		_hunt_at = game.floor_time + float(cfg("first", 40.0))
	game.set_hunt_next.rpc(_hunt_at)


func host_tick(delta: float) -> void:
	match mod():
		"restless":
			_restless(delta)
		"hunted":
			_hunted()


# --- Restless ---------------------------------------------------------------------------------


func _restless(delta: float) -> void:
	var r := float(cfg("still_radius", 30.0))
	var limit := float(cfg("still_time", 2.2))
	var tick := float(cfg("tick", 1.0))
	for p in game.players_root.get_children():
		if p.life_state != Player.Life.ALIVE or game.dungeon.is_safe(p.global_position) or not _monster_near(p):
			_calm(p)
			continue
		var anchor: Vector2 = p.get_meta("restless_anchor", p.global_position)
		if p.global_position.distance_to(anchor) > r:
			_calm(p)
			continue
		p.set_meta("restless_anchor", anchor)
		p.restless += delta
		if p.restless >= limit:
			var acc := float(p.get_meta("restless_acc", tick)) + delta
			if acc >= tick:
				acc -= tick
				_bite(p)
			p.set_meta("restless_acc", acc)


func _calm(p: Player) -> void:
	p.set_meta("restless_anchor", p.global_position)
	p.set_meta("restless_acc", float(cfg("tick", 1.0)))
	if p.restless > 0.0:
		p.restless = 0.0
	if p.status.has("restless_curse"):
		p.status.remove("restless_curse")


## One restless tick: a stack of the curse (damage taken up) and a burn.
func _bite(p: Player) -> void:
	var stacks := 0
	for e in p.status.effects:
		if e.id == "restless_curse":
			stacks = int(e.stacks)
	if stacks < int(cfg("max_stacks", 5)):
		p.status.apply("restless_curse", 9999.0, 0.0, null)
	var ctx: Dictionary = Combat.instance.env_ctx(1.0)
	ctx.damage_type = "fire"
	ctx.school = "spell"
	Telegraph.fired("restless_%d" % p.peer_id)
	Combat.instance.deal_damage(ctx, p, p.health.max_hp * float(cfg("burn_pct", 0.02)), {"damage_type": "true", "dot": true})
	Combat.instance.fx.sound.rpc("restless_bite", p.global_position)


func _monster_near(p: Player) -> bool:
	var cells := float(cfg("needs_monster_cells", 9))
	if cells <= 0.0:
		return true
	var reach: float = cells * game.dungeon.tile
	for e in game.enemies_root.get_children():
		if e.is_alive() and e.aggro and e.global_position.distance_to(p.global_position) <= reach:
			return true
	return false


# --- Hunted -----------------------------------------------------------------------------------


func _hunted() -> void:
	if _hunt_at < 0.0:
		return
	var t: float = game.floor_time
	if not _rift.is_empty():
		if t >= float(_rift.at):
			_spawn_hunter()
		return
	if t < _hunt_at - float(cfg("warn", 4.5)):
		return
	# No hunter once the boss fight has begun or the boss is dead, nor beyond the cap.
	if game.boss_engaged or not game.boss_alive:
		_hunt_at = -1.0
		game.set_hunt_next.rpc(-1.0)
		return
	if _hunters_alive() >= int(cfg("max_alive", 2)):
		_hunt_at = t + 10.0
		game.set_hunt_next.rpc(_hunt_at)
		return
	var spot: Vector2 = _spawn_spot()
	if spot == Vector2.INF:
		_hunt_at = t + 5.0
		game.set_hunt_next.rpc(_hunt_at)
		return
	var names: Array = cfg("names", ["Hroth"])
	var hname := str(names[_rng.randi_range(0, names.size() - 1)])
	_rift = {"pos": spot, "name": hname, "at": t + float(cfg("warn", 4.5))}
	game.set_hunt_next.rpc(float(_rift.at))
	game.open_hunt_rift.rpc(spot, hname, float(cfg("warn", 4.5)))


func _hunters_alive() -> int:
	var n := 0
	for e in game.enemies_root.get_children():
		if e.get("hunter") and not str(e.hunter).is_empty() and e.is_alive():
			n += 1
	return n


## A reachable floor spot `spawn_cells` from a living hero, outside safe rooms and the boss room.
func _spawn_spot() -> Vector2:
	var living: Array = game.players_root.get_children().filter(func(pl): return pl.life_state == Player.Life.ALIVE)
	if living.is_empty():
		return Vector2.INF
	var hero: Player = living[_rng.randi_range(0, living.size() - 1)]
	var d: Dungeon = game.dungeon
	var band: Array = cfg("spawn_cells", [6, 10])
	var boss_room := Rect2i()
	for room in game.layout.rooms:
		if room.role == "boss":
			boss_room = room.rect
	for attempt in 40:
		var cells := _rng.randf_range(float(band[0]), float(band[1]))
		var c := d.cell_of(hero.global_position + Vector2.from_angle(_rng.randf() * TAU) * cells * d.tile)
		if not DungeonGenerator.walkable(d.cell_at(c)) or d.blocks_sight(c) or boss_room.grow(1).has_point(c):
			continue
		var pos := d.cell_center(c)
		if d.is_safe(pos) or game.in_doorway(pos) or game.events.in_arena(pos) or d.find_path(hero.global_position, pos).is_empty():
			continue
		return pos
	return Vector2.INF


func _spawn_hunter() -> void:
	var pool: Array = []
	for m in game.floor_def.monsters:
		if DungeonGenerator.spawnable(str(m.id), game.depth):
			pool.append(str(m.id))
	if pool.is_empty():
		pool = [str(game.floor_def.monsters[0].id)]
	var mods: Array = GameData.elite_modifiers.keys()
	mods.sort()
	var mr: Array = cfg("elite_mods", [2, 3])
	# Distinct modifiers: a seeded shuffle, the first few.
	for i in range(mods.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = mods[i]
		mods[i] = mods[j]
		mods[j] = t
	var picked: Array = mods.slice(0, _rng.randi_range(int(mr[0]), int(mr[1])))
	var n: int = maxi(game.players_root.get_child_count(), 1)
	var hp := float(cfg("hp_mult", 2.0)) + float(cfg("hp_mult_per_extra", 0.35)) * (n - 1)
	var e: Node = game.spawn_monster(str(pool[_rng.randi_range(0, pool.size() - 1)]), _rift.pos, false,
		{"elite": picked, "hunter": _rift.name, "hunter_hp": hp, "hunter_dmg": float(cfg("damage_mult", 1.2))})
	Telegraph.fired("hunter")
	game.hunter_arrived.rpc(_rift.pos)
	_hunters += 1
	_rift = {}
	_hunt_at = game.floor_time + float(cfg("interval", 60.0))
	game.set_hunt_next.rpc(_hunt_at)
	if e:
		e.aggro = true
