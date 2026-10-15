class_name Enemy
extends Actor
## Monster driven by data (data/monsters/*.json): AI type (melee / ranged / caster), preferred
## range and an ordered ability list (skill ids, same skill system as players).
## The host simulates everything; clients interpolate the replicated position.

var def_id := ""
var def: Dictionary = {}
var is_boss := false
var hp_mult := 1.0
var dmg_mult := 1.0
var threat: ThreatTable
var contributors: Dictionary = {}  ## peer id -> time of last contribution (seconds)
var aggro := false  ## replicated: shows the HP bar and drives boss music

var target: Actor = null
var _think_left := 0.0
var _path: PackedVector2Array = []
var _path_left := 0.0
var _knock := Vector2.ZERO
var _door_wait := 0.0
var _strafe := 1.0
var _abilities: Array = []
var _preferred: Array = [0, 40]
var _aggro_radius := 220.0
var lifetime := -1.0  ## host: summoned minions and decoys expire
var copy_peer := 0  ## replicated at spawn: draw this player's look instead of the monster art (D31)
var _wander := Vector2.ZERO
var _wander_left := 0.0


func setup(data: Dictionary) -> void:
	name = data.name
	position = data.pos
	net_pos = position
	def_id = data.def_id
	is_boss = bool(data.get("boss", false))
	def = (GameData.bosses if is_boss else GameData.monsters)[def_id]
	display_name = def.name
	level = int(data.level)
	hp_mult = float(data.hp_mult)
	dmg_mult = float(data.dmg_mult)
	team = int(data.get("team", Team.MONSTERS))
	lifetime = float(data.get("lifetime", -1.0))
	copy_peer = int(data.get("copy_peer", 0))
	radius = float(def.get("collision_radius", 8))
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 16 | 32 | 64 | 128
	NetSync.make(self, "StateSync", [
		"Health:hp", "Health:max_hp", "Health:absorb", "Status:shown", ".:level", ".:aggro",
	], [".:net_pos", ".:facing"], 0.05)


func _ready() -> void:
	super._ready()
	add_to_group("enemies" if team == Team.MONSTERS else "minions")
	if is_boss:
		add_to_group("boss")
	sprite.set_layer("body", str(def.sprite), Color.from_string(str(def.get("tint", "#ffffff")), Color.WHITE))
	if copy_peer > 0:
		_copy_look.call_deferred()
	if multiplayer.is_server():
		threat = ThreatTable.new()
		threat.name = "Threat"
		add_child(threat)
		_configure_ai()
		recompute_stats()
		health.hp = health.max_hp
		_strafe = 1.0 if randf() < 0.5 else -1.0


func _configure_ai() -> void:
	var ai: Dictionary = def.get("ai", {})
	_abilities = ai.get("abilities", [])
	_preferred = ai.get("preferred_range", [0, 40])
	_aggro_radius = float(ai.get("aggro_radius", def.get("aggro_radius", 220)))


## D31: decoys and shapeshifters wear a party member's body and gear, tinted.
func _copy_look() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var p: Player = game.player_by_peer(copy_peer) if game else null
	if p == null:
		return
	sprite.set_layer("body", CharacterSprite.body_key(p.gender))
	for layer in p.appearance:
		var a: Array = p.appearance[layer]
		sprite.set_layer(layer, CharacterSprite.gear_key(str(a[0]), p.gender), Color.from_string(a[1], Color.WHITE))
	sprite.self_modulate = Color.from_string(str(def.get("copy_tint", "#b9a8ff")), Color.WHITE)


func creature_type() -> String:
	return str(def.get("creature_type", "humanoid"))


func immune_to(dtype: String) -> bool:
	return Array(def.get("immune", [])).has(dtype) or super.immune_to(dtype)


func resist_to(dtype: String) -> float:
	return super.resist_to(dtype) + float(def.get("resist", {}).get(dtype, 0.0))


func recompute_stats() -> void:
	stats.compute_monster(def, level, hp_mult, dmg_mult, status.stat_mods(), monster_extra())
	health.set_max(stats.get_stat("max_hp"))


## Extra stat sources (elite modifiers, behaviours) for Stats.compute_monster.
func monster_extra() -> Dictionary:
	return {}


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		host_tick(delta)
		_host_ai(delta)
		net_pos = position
		if lifetime > 0.0:
			lifetime -= delta
			if lifetime <= 0.0:
				health.take(health.hp + health.absorb + 1.0)
	else:
		follow_net_pos(delta)


func _process(delta: float) -> void:
	update_visuals(delta)


# --- Threat / contribution (host) -----------------------------------------------------------


func add_threat(actor: Actor, amount: float) -> void:
	if threat == null or actor == null or actor.team == team:
		return
	threat.add(actor, amount)
	if not aggro:
		_become_aggro()


func taunted_by(actor: Actor, duration: float) -> void:
	if threat == null:
		return
	threat.taunt(actor, duration)
	if actor.get("peer_id") != null:
		add_contribution(int(actor.peer_id))
	if not aggro:
		_become_aggro()


func is_engaged_with(actor: Actor) -> bool:
	return threat != null and threat.threat.has(actor)


## Smoke Screen and friends: lose `fraction` of the threat this actor built.
func drop_threat(actor: Actor, fraction: float) -> void:
	if threat == null or not threat.threat.has(actor):
		return
	threat.threat[actor] = float(threat.threat[actor]) * (1.0 - fraction)
	if fraction >= 0.99:
		threat.forget(actor)


## Channelled monster abilities keep tracking their target.
func channel_aim(aim: Vector2) -> Vector2:
	return target.global_position if _valid_target(target) else aim


func add_contribution(peer: int) -> void:
	contributors[peer] = Time.get_ticks_msec() / 1000.0


func on_damaged(attacker: Actor, _amount: float) -> void:
	if attacker and not aggro:
		_become_aggro()
		_alert_nearby(attacker)


func _become_aggro() -> void:
	aggro = true
	if is_boss:
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.on_boss_engaged(self)


func _alert_nearby(attacker: Actor) -> void:
	var r := float(GameData.bal("threat.aggro_share_radius"))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.is_alive() and not e.aggro and e.global_position.distance_to(global_position) <= r:
			e.add_threat(attacker, 1.0)


# --- AI (host) ---------------------------------------------------------------------------------


func _valid_target(a: Node) -> bool:
	return is_instance_valid(a) and a is Actor and a.is_targetable() and a.team != team \
		and not (a.status.has_flag("stealthed") and not a.status.has_flag("revealed"))


## Who this actor fights: players (and their minions) for monsters, monsters for player minions.
func _opponents(game: Node) -> Array:
	var out: Array = []
	if team == Team.MONSTERS:
		out.append_array(game.players_root.get_children())
	for e in game.enemies_root.get_children():
		if e.team != team:
			out.append(e)
	return out


func _host_ai(delta: float) -> void:
	if not is_alive():
		return
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = float(GameData.bal("ai.think_interval")) * randf_range(0.8, 1.2)
		_think(game)
	_move(game, delta)


func _think(game: Node) -> void:
	# Perception: players inside aggro range with line of sight add a little threat.
	# Blinded monsters only notice what is right next to them.
	var sense := 40.0 if status.has_flag("blinded") else _aggro_radius
	for p in _opponents(game):
		if not _valid_target(p):
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d <= sense and Combat.instance.has_los(global_position, p.global_position):
			threat.add(p, float(GameData.bal("threat.proximity_threat")))
			if not aggro:
				_become_aggro()
				_alert_nearby(p)
	target = threat.update(float(GameData.bal("ai.think_interval")), _valid_target)
	if target == null:
		aggro = aggro and threat.has_any()
		return
	if not can_act() or not casting.is_empty():
		return
	var dist := global_position.distance_to(target.global_position)
	var los := Combat.instance.has_los(global_position, target.global_position)
	for sid in _abilities:
		if cooldown_left(sid) > 0.0:
			continue
		var skill := GameData.skill(sid)
		var aim := target.global_position
		if not _ability_usable(skill, dist, los):
			continue
		if _is_heal(skill):
			var hurt := _hurt_ally(float(skill.effects[0].get("max_range", 250)))
			if hurt == null:
				continue
			aim = hurt.global_position
		if Combat.instance.try_use_skill(self, sid, aim).is_empty():
			facing = (aim - global_position).normalized() if aim != global_position else facing
			break


func _ability_usable(skill: Dictionary, dist: float, los: bool) -> bool:
	var u: Dictionary = skill.get("ai", {})
	if u.has("min_range") and dist < float(u.min_range):
		return false
	if u.has("below_hp") and health.fraction() >= float(u.below_hp):
		return false
	if u.has("max_range"):
		return dist <= float(u.max_range) and (los or u.get("ignore_los", false))
	for eff in skill.effects:
		match str(eff.type):
			"melee", "cone":
				return dist <= float(eff.range) + target.radius and los
			"projectile":
				if eff.get("arc", false):
					return dist <= float(eff.range)
				return dist <= float(eff.range) * float(GameData.bal("ai.projectile_range_use")) and los
			"aoe":
				if eff.get("at", "self") == "self":
					return dist <= float(eff.radius)
				return dist <= float(eff.get("max_range", 300)) and los
			"heal":
				return true
			"summon", "status", "taunt", "absorb", "resource":
				return dist <= _aggro_radius * 1.5
			"hit", "chain", "beam", "line", "tether", "interrupt", "resource_drain":
				return dist <= float(eff.get("range", eff.get("length", 200))) and los
			"leap", "charge", "dash", "teleport":
				return dist <= float(eff.get("distance", 200)) and dist > 40.0
			"zone", "trap", "deploy", "delayed", "terrain", "pull", "knockback":
				return dist <= float(eff.get("max_range", eff.get("radius", 160))) + 20.0 and los
	return false


func _is_heal(skill: Dictionary) -> bool:
	return not skill.effects.is_empty() and skill.effects[0].type == "heal"


func _hurt_ally(r: float) -> Actor:
	var best: Actor = null
	var best_f := float(GameData.bal("ai.heal_ally_below"))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_alive() and e.global_position.distance_to(global_position) <= r and e.health.fraction() < best_f:
			best_f = e.health.fraction()
			best = e
	return best


func _move(game: Node, delta: float) -> void:
	var desired := Vector2.ZERO
	var speed := move_speed()
	if status.has_flag("feared"):
		desired = _fear_dir()
	elif status.has_flag("disoriented"):
		_wander_left -= delta
		if _wander_left <= 0.0:
			_wander_left = randf_range(0.5, 1.0)
			_wander = Vector2.from_angle(randf() * TAU)
		desired = _wander * 0.6
	elif target != null and _valid_target(target) and casting.is_empty() and can_act():
		var to_t := target.global_position - global_position
		var dist := to_t.length()
		var los := dist < 600.0 and Combat.instance.has_los(global_position, target.global_position)
		var lo := float(_preferred[0])
		var hi := float(_preferred[1]) + target.radius
		if dist > hi or not los:
			desired = _path_dir(game, target.global_position, delta)
		elif dist < lo:
			desired = -to_t.normalized()
			if _blocked(desired):
				desired = to_t.normalized().orthogonal() * _strafe
		elif lo > 0.0:
			desired = to_t.normalized().orthogonal() * _strafe * 0.4
			if randf() < 0.01:
				_strafe = -_strafe
		facing = to_t.normalized() if dist > 1.0 else facing
	# Soft separation so packs don't stack into one blob.
	var sep := Vector2.ZERO
	var sr := float(GameData.bal("ai.separation_radius")) + radius
	for e in game.enemies_root.get_children():
		if e == self:
			continue
		var off: Vector2 = global_position - e.global_position
		var l := off.length()
		if l < sr and l > 0.01:
			sep += off / l * (1.0 - l / sr)
	velocity = desired * speed + sep * float(GameData.bal("ai.separation_force")) + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 700.0 * delta)
	if status.has_flag("rooted"):
		velocity = _knock
	move_and_slide()
	if desired != Vector2.ZERO and velocity.length() > 1.0 and casting.is_empty():
		facing = desired


## Away from whoever applied the fear (or the nearest player).
func _fear_dir() -> Vector2:
	var src := global_position + Vector2.from_angle(randf() * TAU)
	for e in status.effects:
		if Array(e.def.get("flags", [])).has("feared") and e.source is Dictionary:
			var c: Variant = e.source.get("caster")
			src = c.global_position if c is Node2D and is_instance_valid(c) else e.source.get("origin", src)
	var d := global_position - src
	return d.normalized() if d.length() > 1.0 else Vector2.RIGHT


func _blocked(dir: Vector2) -> bool:
	return not Combat.instance.has_los(global_position, global_position + dir * 40.0)


func _path_dir(game: Node, goal: Vector2, delta: float) -> Vector2:
	_path_left -= delta
	if _path_left <= 0.0 or _path.is_empty():
		_path_left = float(GameData.bal("ai.path_interval")) * randf_range(0.8, 1.2)
		_path = game.dungeon.find_path(global_position, goal)
	while _path.size() > 1 and global_position.distance_to(_path[0]) < 10.0:
		_path.remove_at(0)
	if _path.is_empty():
		return (goal - global_position).normalized()
	var next := _path[0]
	# Closed doors: simple monsters open them after a short delay.
	var door: Node = game.dungeon.closed_door_near(global_position, next)
	if door:
		_door_wait += delta
		if _door_wait >= float(GameData.bal("world.door_enemy_open_delay")):
			_door_wait = 0.0
			door.host_set_open(true)
		return Vector2.ZERO
	_door_wait = 0.0
	return (next - global_position).normalized()


func host_teleport(pos: Vector2) -> void:
	position = pos
	net_pos = pos


func host_dash(dest: Vector2, duration: float) -> void:
	var t := create_tween()
	t.tween_property(self, "position", dest, duration)


func host_knockback(push: Vector2) -> void:
	var resist := float(GameData.bal("ai.boss_knockback_taken")) if is_boss else 1.0
	_knock += push * resist


func on_death() -> void:
	died_signal.emit(self)
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.on_enemy_killed(self)
	queue_free.call_deferred()
