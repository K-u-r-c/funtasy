extends Node2D
## One run through the infinite dungeon. The host drives the flow: it picks floor seeds,
## spawns players/monsters/boss, scales difficulty, awards XP and loot, opens the exit portal
## and detects party wipes. Every peer builds the floor layout locally from the host's seed.

const PORTAL_SCRIPT := preload("res://scripts/dungeon/portal.gd")
const START_OFFSETS := [Vector2(-18, -10), Vector2(18, -10), Vector2(-18, 14), Vector2(18, 14)]

var depth := 0
var floor_def: Dictionary = {}
var layout: Dictionary = {}
var floor_time := 0.0
var run_seed := 0
var local_player: Player
var portal: Node2D
var boss_alive := false
var boss_engaged := false

var _begun := false
var _enemy_counter := 0
var _hazard_left := 0.0
var _portal_left := 0.0
var portal_ready: Dictionary = {}  ## peer id -> true: players who chose to descend (replicated)
var _descend_timer := -1.0
var _wiped := false
var _clock_sync_left := 0.0
var corpses: Dictionary = {}  ## host: corpse id -> {id, def_id, pos, t, creature} (D29)
var _corpse_counter := 0
var _aura_left := 0.0

@onready var dungeon: Dungeon = $Dungeon
@onready var entities: Node2D = $Entities
@onready var players_root: Node2D = $Entities/Players
@onready var enemies_root: Node2D = $Entities/Enemies
@onready var items_root: Node2D = $Entities/Items
@onready var corpses_root: Node2D = $Entities/Corpses
@onready var fx_root: Node2D = $FX
@onready var visibility: Visibility = $Visibility
@onready var camera: GameCamera = $Camera
@onready var world_ui: CanvasLayer = $WorldUI
@onready var hud: CanvasLayer = $HUD
@onready var combat: Combat = $Combat
@onready var fx: CombatFx = $CombatFx
@onready var loot: LootManager = $Loot
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var ambient: CanvasModulate = $Ambient


func _ready() -> void:
	combat.game = self
	combat.fx = fx
	fx.world = fx_root
	fx.world_ui = world_ui
	fx.local_focus = func() -> Vector2: return camera.global_position
	loot.game = self
	loot.spawner = item_spawner
	loot.items_root = items_root
	visibility.dungeon = dungeon
	visibility.game = self
	player_spawner.spawn_function = _spawn_player
	enemy_spawner.spawn_function = _spawn_enemy
	item_spawner.spawn_function = loot.spawn_function
	_setup_environment()
	EventBus.local_player_spawned.connect(_on_local_player)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.peer_loaded.connect(func(_id): _try_begin())
	NetworkManager.notify_loaded()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# =========================================================================================
# Host: run flow
# =========================================================================================


func _try_begin() -> void:
	if _begun or not NetworkManager.all_loaded(GameState.roster.keys()):
		return
	_begun = true
	run_seed = randi()
	start_floor(GameState.start_depth())


func start_floor(new_depth: int) -> void:
	depth = new_depth
	var ft_ids: Array = GameData.floor_types.keys()
	ft_ids.sort()
	var ft_id: String = ft_ids[(new_depth - 1) % ft_ids.size()]
	var floor_seed := hash(run_seed + new_depth * 7919)
	combat.clear_floor()
	loot.clear_floor()
	corpses.clear()
	for e in enemies_root.get_children():
		e.queue_free()
	if portal:
		portal.queue_free()
		portal = null
	_descend_timer = -1.0
	_build_floor.rpc(new_depth, floor_seed, ft_id)
	# Host-only: the spawn list depends on party size, so it is generated with that multiplier.
	var n := players_root.get_child_count() if players_root.get_child_count() > 0 else GameState.roster.size()
	var count_mult := 1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (maxi(n, 1) - 1)
	var host_layout := DungeonGenerator.new().generate(floor_seed, floor_def, count_mult, new_depth)
	_place_players()
	for group in host_layout.spawns:
		for m in group.monsters:
			spawn_monster(str(m.id), m.pos, false)
	spawn_monster(str(floor_def.boss), host_layout.boss_pos, true)
	boss_alive = true
	boss_engaged = false
	GameState.current_depth = new_depth
	GameState.save_game()


## Spawns connected players that have no character in the world yet (start of a run, which can
## be a later floor when a saved game is continued) and moves everyone else to the start room.
func _place_players() -> void:
	var start: Vector2 = layout.start
	var i := 0
	var ids: Array = GameState.roster.keys()
	ids.sort()
	for id in ids:
		var pos: Vector2 = start + START_OFFSETS[i % START_OFFSETS.size()]
		var existing: Player = player_by_peer(id)
		var connected: bool = id == 1 or multiplayer.get_peers().has(id)
		if existing == null and connected:
			var r: Dictionary = GameState.roster[id]
			player_spawner.spawn({"peer": id, "pos": pos, "class_id": r.class_id, "gender": r.get("gender", ""), "name": r.name, "level": r.level})
		elif existing:
			existing.host_teleport(pos)
			if existing.life_state != Player.Life.ALIVE:
				existing.revive(float(GameData.bal("player.next_floor_hp_fraction")))
			existing.persist()
		i += 1


## extra (optional spawn data): team ("players" for player summons), lifetime, copy_peer,
## taunt (radius taunted on spawn), elite.
func spawn_monster(def_id: String, pos: Vector2, boss: bool, extra: Dictionary = {}) -> Node:
	var def: Dictionary = (GameData.bosses if boss else GameData.monsters).get(def_id, {})
	if def.is_empty():
		push_error("Game: unknown monster '%s'" % def_id)
		return null
	var n := maxi(players_root.get_child_count(), 1)
	var lvl := monster_level()
	var diff := _difficulty()
	var hp_mult := (1.0 + float(GameData.bal("scaling.hp_per_level")) * (lvl - 1)) * diff
	hp_mult *= 1.0 + float(GameData.bal("scaling.boss_hp_per_extra_player" if boss else "scaling.hp_per_extra_player")) * (n - 1)
	var dmg_mult := (1.0 + float(GameData.bal("scaling.damage_per_level")) * (lvl - 1)) * diff
	dmg_mult *= 1.0 + float(GameData.bal("scaling.damage_per_extra_player")) * (n - 1)
	_enemy_counter += 1
	var data := {"name": "E%d" % _enemy_counter, "def_id": def_id, "boss": boss, "pos": pos,
		"level": lvl, "hp_mult": hp_mult, "dmg_mult": dmg_mult}
	data.merge(extra)
	return enemy_spawner.spawn(data)


## Summons: monster reinforcements, or (opts.team = "caster") the caster's own minions and
## decoys (Blink's mirror image), optionally copying the caster's look (D31).
func summon_monsters(def_id: String, count: int, origin: Vector2, r: float, caster: Node, opts: Dictionary = {}) -> void:
	var extra := {}
	if str(opts.get("team", "")) == "caster" and caster is Actor:
		extra.team = caster.team
	if opts.has("lifetime"):
		extra.lifetime = float(opts.lifetime)
	if opts.get("copy_caster", false) and caster and caster.get("peer_id") != null:
		extra.copy_peer = int(caster.peer_id)
	for i in count:
		var pos := origin + Vector2.from_angle(TAU * i / count + randf()) * r
		if dungeon.cell_at(dungeon.cell_of(pos)) != DungeonGenerator.CELL_FLOOR:
			pos = origin
		var e: Node = spawn_monster(def_id, pos, false, extra)
		if e == null:
			continue
		if int(extra.get("team", Actor.Team.MONSTERS)) == Actor.Team.MONSTERS:
			for p in players_root.get_children():
				if p.is_targetable() and p.global_position.distance_to(origin) < 500.0:
					e.add_threat(p, 1.0)
		elif opts.has("taunt"):
			for m in combat.enemies_of(e.team, pos, float(opts.taunt)):
				if m.has_method("taunted_by"):
					m.taunted_by(e, float(opts.get("lifetime", 2.0)))


func monster_level() -> int:
	var total := 0
	var n := 0
	for p in players_root.get_children():
		total += p.level
		n += 1
	var avg := float(total) / n if n > 0 else 1.0
	var w := float(GameData.bal("scaling.level_party_weight"))
	return maxi(1, roundi(float(GameData.bal("scaling.level_per_depth")) * (depth - 1) + w * avg + (1.0 - w)))


func _difficulty() -> float:
	var d := GameData.game_setting_def("difficulty")
	var idx := int(GameState.setting("difficulty"))
	var values: Array = d.get("values", [1.0])
	return float(values[clampi(idx, 0, values.size() - 1)])


func player_by_peer(peer: int) -> Player:
	return players_root.get_node_or_null(str(peer)) as Player


func on_enemy_killed(e: Enemy) -> void:
	if e.team != Actor.Team.MONSTERS:
		_enemy_death_fx.rpc(str(e.def.sprite), e.global_position, e.facing, -1)
		return
	_corpse_counter += 1
	var cid := _corpse_counter
	if not e.is_boss and not e.def.get("no_corpse", false):
		corpses[cid] = {"id": cid, "def_id": e.def_id, "pos": e.global_position, "t": floor_time,
			"creature": e.creature_type(), "bones": e.def.get("corpse", "flesh") == "bones"}
	_enemy_death_fx.rpc(str(e.def.sprite), e.global_position, e.facing, cid if corpses.has(cid) else -1)
	for other in enemies_root.get_children():
		if other != e and other.is_alive() and not other.behaviors.is_empty() and other.global_position.distance_to(e.global_position) < 320.0:
			for b in other.behaviors:
				b.on_ally_death(e, corpses.get(cid, {}))
	# Kill procs (Victory Rush, legendaries) for whoever landed the last hit.
	if is_instance_valid(e.last_attacker):
		combat.fire(e.last_attacker, "on_kill", {"target": e, "ctx": e.last_attack_ctx, "skill": str(e.last_attack_ctx.get("skill", "")),
			"school": str(e.last_attack_ctx.get("school", "")), "xp": int(e.def.get("xp", 0)) > 0, "damage_type": str(e.last_attack_ctx.get("damage_type", ""))})
		var ks: Dictionary = GameData.skills.get(str(e.last_attack_ctx.get("skill", "")), {})
		if ks.get("cooldown_on_kill_reset", false) or e.last_attacker.stats.skill_mod(str(ks.get("id", "")), "reset_on_kill") > 0.0:
			e.last_attacker.cooldowns.erase(str(ks.id))
			if e.last_attacker.has_method("sync_cooldown"):
				e.last_attacker.sync_cooldown(str(ks.id))
	# Shared XP: everyone who directly or indirectly contributed inside the time window.
	var now := Time.get_ticks_msec() / 1000.0
	var window := float(GameData.bal("progression.contribution_window"))
	var xp := roundi(float(e.def.xp) * (1.0 + float(GameData.bal("progression.monster_xp_per_level")) * (e.level - 1)))
	for peer in e.contributors:
		if now - float(e.contributors[peer]) > window:
			continue
		var p := player_by_peer(peer)
		if p:
			p.add_xp(xp)
			fx.number.rpc_id(peer, p.global_position + Vector2(0, -12), "+%d XP" % xp, "xp")
	if e.is_boss:
		boss_alive = false
		loot.roll_and_drop("boss", e.global_position, e.def.get("loot", {}))
		_boss_defeated.rpc(layout.portal_pos)
		for p in players_root.get_children():
			p.persist()
	else:
		loot.roll_and_drop("monster", e.global_position)


func host_interact(p: Player, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var reach := float(GameData.bal("world.interact_range")) + 24.0
	if node.has_method("interact_pos") and p.global_position.distance_to(node.interact_pos()) > reach:
		return
	if node is GroundItem:
		loot.try_pickup(p, node)
	elif node.has_method("is_lit") and node.has_method("set_state"):
		if node.is_lit():
			p.host_take_torch()
			dungeon.set_torch_state.rpc(node.torch_id, node.State.TAKEN)
	elif node.has_method("host_set_open"):
		# Don't let a door close on someone standing in the doorway.
		if node.is_open:
			for a in combat.all_actors():
				if node.world_rect.grow(4).has_point(a.global_position):
					return
		node.host_set_open(not node.is_open)
	elif node.has_method("interactable") and node.interactable():
		dungeon.open_chest.rpc(node.prop_id)
		loot.roll_and_drop("chest", node.global_position + Vector2(0, 18))
	elif node == portal:
		# The portal never pulls anyone in: every living player opts in with Interact.
		# Once the countdown runs the choice is locked, so extra presses can't toggle it.
		if _descend_timer >= 0.0:
			return
		if portal_ready.has(p.peer_id):
			portal_ready.erase(p.peer_id)
		else:
			portal_ready[p.peer_id] = true
		_try_descend()


func _physics_process(delta: float) -> void:
	floor_time += delta
	for s in dungeon.spikes:
		s.update_state(floor_time)
	if not multiplayer.is_server() or depth == 0:
		return
	_clock_sync_left -= delta
	if _clock_sync_left <= 0.0:
		_clock_sync_left = 5.0
		_sync_clock.rpc(floor_time)
	var actors := combat.all_actors()
	for s in dungeon.spikes:
		s.host_damage(actors)
	var life := float(GameData.bal("corpses.lifetime", 20.0))
	for cid in corpses.keys():
		if floor_time - float(corpses[cid].t) > life:
			corpses.erase(cid)
	_aura_left -= delta
	if _aura_left <= 0.0:
		_aura_left = 1.0
		for a in actors:
			if a is Actor and a.is_alive():
				combat.fire(a, "aura_tick", {"target": null})
	_hazard_left -= delta
	if _hazard_left <= 0.0:
		_hazard_left = float(GameData.bal("hazards.lava_tick"))
		for a in actors:
			if a.is_targetable() and dungeon.is_lava(a.global_position):
				combat.deal_damage(combat.env_ctx(0.0), a, float(GameData.bal("hazards.lava_damage")), {"dot": true})
	if portal:
		_portal_left -= delta
		if _portal_left <= 0.0:
			_portal_left = 0.25
			_try_descend()
	if _descend_timer >= 0.0:
		_descend_timer -= delta
		# A wipe while the portal counts down ends the run instead of descending.
		if _wiped:
			_descend_timer = -1.0
		elif _descend_timer < 0.0:
			start_floor(depth + 1)
	_check_wipe()


## Host: descend once every living player is ready (downed players and ghosts come along).
func _try_descend() -> void:
	if portal == null or _descend_timer >= 0.0 or _wiped:
		return
	for id in portal_ready.keys():
		var pl := player_by_peer(id)
		if pl == null or pl.life_state != Player.Life.ALIVE:
			portal_ready.erase(id)
	var alive := _alive_count()
	_portal_status.rpc(portal_ready.keys(), alive)
	if alive > 0 and portal_ready.size() >= alive:
		_descend_timer = 1.5
		broadcast_message.rpc("Descending...", "#c08cff")


func on_boss_engaged(_boss: Node) -> void:
	if boss_engaged:
		return
	boss_engaged = true
	_boss_music.rpc(true)


func on_player_ghosted(_p: Player) -> void:
	_check_wipe()


func _check_wipe() -> void:
	if _wiped or players_root.get_child_count() == 0:
		return
	for p in players_root.get_children():
		if p.life_state == Player.Life.ALIVE:
			return
	# Nobody is left standing, so nobody can revive anyone: the party is wiped.
	_wiped = true
	print("[game] party wiped on floor %d" % depth)
	# A wipe ends this game for good: its save (and the heroes in it) is deleted.
	GameState.end_game()
	_show_wipe.rpc(depth)
	get_tree().create_timer(6.0).timeout.connect(_end_run)


## Host: despawn every replicated node first so clients get the despawns while they still have
## the game scene, then send everyone back to the lobby.
func _end_run() -> void:
	NetworkManager.return_to_lobby()


## Host: despawns every replicated node (players stop streaming first) so clients receive the
## despawns while they still have the game scene. Awaited before leaving the run.
func teardown_run() -> void:
	_stop_owner_sync.rpc()
	await get_tree().create_timer(0.3).timeout
	combat.clear_floor()
	for root in [items_root, enemies_root, players_root]:
		for c in root.get_children():
			c.queue_free()
	await get_tree().create_timer(0.3).timeout


func _on_peer_disconnected(id: int) -> void:
	var p := player_by_peer(id)
	if p:
		p.queue_free()


# =========================================================================================
# Replicated events (host -> all, reliable unless noted)
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _build_floor(new_depth: int, floor_seed: int, ft_id: String) -> void:
	depth = new_depth
	floor_time = 0.0
	floor_def = GameData.floor_types[ft_id]
	layout = DungeonGenerator.new().generate(floor_seed, floor_def, 1.0, new_depth)
	dungeon.build(layout, floor_def, entities)
	visibility.reset_floor()
	camera.set_bounds(dungeon.world_rect().grow(64))
	# Darkness deepens with every floor.
	var base := Color.from_string(str(floor_def.get("ambient_color", "#07060a")), Color(0.03, 0.02, 0.04))
	var factor := maxf(float(GameData.bal("lighting.ambient_min_factor")), 1.0 - float(GameData.bal("lighting.ambient_darken_per_depth")) * (new_depth - 1))
	ambient.color = Color(base.r * factor, base.g * factor, base.b * factor)
	for c in corpses_root.get_children():
		c.queue_free()
	if portal and not multiplayer.is_server():
		portal.queue_free()
		portal = null
	# Readiness belongs to one portal; carried over, it would descend the next floor's party at once.
	portal_ready.clear()
	boss_engaged = false
	_wiped = false
	AudioManager.play_music(str(floor_def.music))
	EventBus.floor_started.emit(new_depth)
	EventBus.hud_message.emit("%s - Floor %d" % [floor_def.name, new_depth], Color(0.95, 0.75, 0.4))


## Host -> all (reliable): owners stop streaming their position before the run is torn down,
## so no packet arrives for an already freed player node.
@rpc("authority", "call_local", "reliable")
func _stop_owner_sync() -> void:
	for p in players_root.get_children():
		var s: MultiplayerSynchronizer = p.get_node_or_null("OwnerSync")
		if s:
			s.public_visibility = false


@rpc("authority", "call_local", "reliable")
func _sync_clock(t: float) -> void:
	floor_time = t


@rpc("authority", "call_local", "reliable")
func _boss_music(on: bool) -> void:
	AudioManager.play_music(str(floor_def.boss_music if on else floor_def.music))
	if on:
		var b := get_tree().get_first_node_in_group("boss")
		EventBus.boss_engaged.emit(b)


@rpc("authority", "call_local", "reliable")
func _boss_defeated(portal_pos: Vector2) -> void:
	AudioManager.play_music(str(floor_def.music))
	EventBus.boss_defeated.emit(null)
	EventBus.hud_message.emit("The boss is defeated! A portal opens...", Color(0.75, 0.55, 1.0))
	portal = PORTAL_SCRIPT.new()
	portal.name = "Portal"
	portal.position = portal_pos
	entities.add_child(portal)


## Host -> all (reliable): who is ready to descend.
@rpc("authority", "call_local", "reliable")
func _portal_status(ready_ids: Array, alive: int) -> void:
	portal_ready.clear()
	for id in ready_ids:
		portal_ready[int(id)] = true
	if hud and hud.has_method("set_portal_status"):
		hud.set_portal_status(ready_ids.size(), alive)


@rpc("authority", "call_local", "reliable")
func broadcast_message(text: String, color_html: String) -> void:
	EventBus.hud_message.emit(text, Color.from_string(color_html, Color.WHITE))


@rpc("authority", "call_local", "reliable")
func _show_wipe(final_depth: int) -> void:
	EventBus.party_wiped.emit()
	if hud and hud.has_method("show_wipe"):
		hud.show_wipe(final_depth)


## Host -> all (reliable): death animation; a corpse with an id stays on the floor (D29) until it
## rots (balance.corpses.lifetime) or an ability consumes it.
@rpc("authority", "call_local", "reliable")
func _enemy_death_fx(sprite_key: String, pos: Vector2, dir: Vector2, corpse_id: int) -> void:
	var corpse := CharacterSprite.new()
	corpse.position = pos
	if corpse_id >= 0:
		corpse.name = "Corpse_%d" % corpse_id
	corpses_root.add_child(corpse)
	corpse.set_layer("body", sprite_key)
	corpse.play("death", dir, true)
	corpse.visible = visibility.is_cell_visible(dungeon.cell_of(pos))
	var t := corpse.create_tween()
	t.tween_interval(float(GameData.bal("corpses.lifetime", 20.0)) if corpse_id >= 0 else 3.0)
	t.tween_property(corpse, "modulate:a", 0.0, 1.2)
	t.tween_callback(corpse.queue_free)
	AudioManager.play_sfx_at("death", pos)


## Host -> all (reliable): a corpse was consumed (devoured, raised, absorbed).
@rpc("authority", "call_local", "reliable")
func _corpse_gone(corpse_id: int) -> void:
	var c := corpses_root.get_node_or_null("Corpse_%d" % corpse_id)
	if c:
		c.queue_free()


## Host: corpses within r of pos (optionally only bone piles / one creature type).
func corpses_near(pos: Vector2, r: float, filter: Dictionary = {}) -> Array:
	var out: Array = []
	for c in corpses.values():
		if c.pos.distance_to(pos) > r:
			continue
		if filter.has("bones") and bool(c.bones) != bool(filter.bones):
			continue
		if filter.has("creature") and c.creature != filter.creature:
			continue
		out.append(c)
	out.sort_custom(func(a, b): return a.pos.distance_to(pos) < b.pos.distance_to(pos))
	return out


func consume_corpse(corpse_id: int) -> Dictionary:
	var c: Dictionary = corpses.get(corpse_id, {})
	corpses.erase(corpse_id)
	if not c.is_empty():
		_corpse_gone.rpc(corpse_id)
	return c


# =========================================================================================
# Local
# =========================================================================================


func _on_local_player(p: Node) -> void:
	local_player = p
	camera.target = p
	visibility.viewer = p


func _process(_delta: float) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	# Dead players spectate a living teammate (cycle with the attack button).
	if local_player.life_state == Player.Life.GHOST:
		var living: Array = []
		for p in players_root.get_children():
			if p.life_state == Player.Life.ALIVE:
				living.append(p)
		if not living.is_empty():
			var idx := living.find(camera.target)
			if idx < 0 or Input.is_action_just_pressed("attack"):
				camera.target = living[(idx + 1) % living.size()]
				visibility.viewer = camera.target
	elif camera.target != local_player:
		camera.target = local_player
		visibility.viewer = local_player


## Nearest thing the local player can interact with: {node, kind, text} or {}.
## The single thing the local player would interact with: {node, kind, text} or {}.
## Everything within reach is a candidate; the player chooses by pointing at it:
## - mouse: the candidate closest to the cursor,
## - gamepad: the candidate the character faces (aim direction), nearer ones first on ties.
func find_interactable(p: Player) -> Dictionary:
	var pos := p.global_position
	var reach := float(GameData.bal("world.interact_range"))
	var candidates: Array = []  ## [point to aim at, node, kind, text]
	for g in items_root.get_children():
		if pos.distance_to(g.global_position) < float(GameData.bal("world.pickup_range")):
			candidates.append([g.global_position, g, "item", g.interact_text(p.level)])
	for o in players_root.get_children():
		if o != p and o.life_state == Player.Life.DOWNED and pos.distance_to(o.global_position) < float(GameData.bal("world.revive_range")):
			candidates.append([o.global_position, o, "revive", "Hold to revive %s" % o.display_name])
	for door in dungeon.doors:
		# Doors are wide: in reach when the nearest point of the doorway is.
		if _distance_to_rect(pos, door.world_rect) < reach * 0.6:
			candidates.append([door.world_rect.get_center(), door, "door", door.interact_text()])
	for prop in dungeon.props.values():
		if is_instance_valid(prop) and prop.interactable() and pos.distance_to(prop.global_position) < reach:
			candidates.append([prop.global_position, prop, "chest", prop.interact_text()])
	for t in dungeon.torches.values():
		if is_instance_valid(t) and t.is_lit() and pos.distance_to(t.interact_pos()) < reach:
			candidates.append([t.global_position, t, "torch", t.interact_text()])
	if portal and pos.distance_to(portal.global_position) < portal.radius:
		var ready := portal_ready.has(p.peer_id)
		var text := "Cancel - stay on this floor" if ready else "Enter the portal"
		candidates.append([portal.global_position, portal, "portal", "%s (%d/%d ready)" % [text, portal_ready.size(), _alive_count()]])
	var best: Array = []
	var best_score := INF
	for c in candidates:
		var point: Vector2 = c[0]
		if c[1].has_method("host_set_open"):
			point = _closest_on_rect(p.aim_pos if not InputSettings.using_gamepad else pos, c[1].world_rect)
		var score: float
		if InputSettings.using_gamepad:
			var to := point - pos
			var dot := p.facing.dot(to.normalized()) if to.length() > 12.0 else 1.0
			score = (1.0 - dot) * 100.0 + to.length() * 0.25
		else:
			score = point.distance_to(p.aim_pos)
		if score < best_score:
			best_score = score
			best = c
	if best.is_empty():
		return {}
	# The HUD draws the interact button glyph in front of the text.
	return {"node": best[1], "kind": best[2], "text": best[3]}


func _closest_on_rect(pos: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))


func _distance_to_rect(pos: Vector2, r: Rect2) -> float:
	return pos.distance_to(Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y)))


func _alive_count() -> int:
	var n := 0
	for pl in players_root.get_children():
		if pl.life_state == Player.Life.ALIVE:
			n += 1
	return n


func nearest_floor(pos: Vector2) -> Vector2:
	var c := dungeon.cell_of(pos)
	for r in range(0, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var cc := c + Vector2i(dx, dy)
				if dungeon.cell_at(cc) == DungeonGenerator.CELL_FLOOR:
					return dungeon.cell_center(cc)
	return pos


# --- Spawn functions (run on every peer with the host's data) ---------------------------------


func _spawn_player(data: Dictionary) -> Node:
	var p := Player.new()
	p.setup(data)
	return p


func _spawn_enemy(data: Dictionary) -> Node:
	var e: Enemy = Boss.new() if bool(data.get("boss", false)) else Enemy.new()
	e.setup(data)
	return e
