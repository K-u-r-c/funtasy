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
var _descend_timer := -1.0
var _wiped := false
var _clock_sync_left := 0.0

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
	start_floor(1)


func start_floor(new_depth: int) -> void:
	depth = new_depth
	var ft_ids: Array = GameData.floor_types.keys()
	ft_ids.sort()
	var ft_id: String = ft_ids[(new_depth - 1) % ft_ids.size()]
	var floor_seed := hash(run_seed + new_depth * 7919)
	combat.clear_floor()
	loot.clear_floor()
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
	var host_layout := DungeonGenerator.new().generate(floor_seed, floor_def, count_mult)
	_place_players(new_depth == 1 and players_root.get_child_count() == 0)
	for group in host_layout.spawns:
		for m in group.monsters:
			spawn_monster(str(m.id), m.pos, false)
	spawn_monster(str(floor_def.boss), host_layout.boss_pos, true)
	boss_alive = true
	boss_engaged = false


func _place_players(first: bool) -> void:
	var start: Vector2 = layout.start
	var i := 0
	var ids: Array = GameState.roster.keys()
	ids.sort()
	for id in ids:
		var pos: Vector2 = start + START_OFFSETS[i % START_OFFSETS.size()]
		var existing: Player = player_by_peer(id)
		if first and existing == null:
			var r: Dictionary = GameState.roster[id]
			player_spawner.spawn({"peer": id, "pos": pos, "class_id": r.class_id, "name": r.name, "level": r.level})
		elif existing:
			existing.host_teleport(pos)
			if existing.life_state != Player.Life.ALIVE:
				existing.revive(float(GameData.bal("player.next_floor_hp_fraction")))
			existing.persist()
		i += 1


func spawn_monster(def_id: String, pos: Vector2, boss: bool) -> Node:
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
	return enemy_spawner.spawn({"name": "E%d" % _enemy_counter, "def_id": def_id, "boss": boss, "pos": pos,
		"level": lvl, "hp_mult": hp_mult, "dmg_mult": dmg_mult})


func summon_monsters(def_id: String, count: int, origin: Vector2, r: float, _caster: Node) -> void:
	for i in count:
		var pos := origin + Vector2.from_angle(TAU * i / count + randf()) * r
		if dungeon.cell_at(dungeon.cell_of(pos)) != DungeonGenerator.CELL_FLOOR:
			pos = origin
		var e: Node = spawn_monster(def_id, pos, false)
		if e:
			for p in players_root.get_children():
				if p.is_targetable() and p.global_position.distance_to(origin) < 500.0:
					e.add_threat(p, 1.0)


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
	_enemy_death_fx.rpc(str(e.def.sprite), e.global_position, e.facing)
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
	elif node.has_method("host_set_open"):
		# Don't let a door close on someone standing in the doorway.
		if node.is_open:
			for a in combat.all_actors():
				if node.world_rect.grow(4).has_point(a.global_position):
					return
		node.host_set_open(not node.is_open)
	elif node.has_method("interactable") and node.interactable():
		dungeon.open_chest.rpc(node.name)
		loot.roll_and_drop("chest", node.global_position + Vector2(0, 18))
	elif node == portal:
		_try_descend(true)


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
			_try_descend(false)
	if _descend_timer >= 0.0:
		_descend_timer -= delta
		if _descend_timer < 0.0:
			start_floor(depth + 1)
	_check_wipe()


func _try_descend(interacted: bool) -> void:
	if portal == null or _descend_timer >= 0.0:
		return
	var alive := 0
	var inside := 0
	for p in players_root.get_children():
		if p.life_state == Player.Life.ALIVE:
			alive += 1
			if p.global_position.distance_to(portal.global_position) <= portal.radius:
				inside += 1
	_portal_status.rpc(inside, alive)
	if alive > 0 and (inside == alive or (interacted and inside > 0 and inside * 2 >= alive)):
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
	var rules: Dictionary = GameData.bal("wipe", {})
	for p in players_root.get_children():
		var ch: Dictionary = p.to_character()
		if bool(rules.get("lose_equipment", true)):
			ch.equipment = {}
		if bool(rules.get("lose_backpack", true)):
			ch.backpack = []
		if bool(rules.get("lose_level_progress", false)):
			ch.xp = 0
		GameState.characters[p.peer_id] = ch
		GameState.push_character_to_owner(p.peer_id)
	_show_wipe.rpc(depth)
	get_tree().create_timer(6.0).timeout.connect(_end_run)


## Host: despawn every replicated node first so clients get the despawns while they still have
## the game scene, then send everyone back to the lobby.
func _end_run() -> void:
	_stop_owner_sync.rpc()
	await get_tree().create_timer(0.3).timeout
	combat.clear_floor()
	for root in [items_root, enemies_root, players_root]:
		for c in root.get_children():
			c.queue_free()
	await get_tree().create_timer(0.3).timeout
	NetworkManager.return_to_lobby()


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
	layout = DungeonGenerator.new().generate(floor_seed, floor_def, 1.0)
	dungeon.build(layout, floor_def, entities)
	visibility.reset_floor()
	camera.set_bounds(dungeon.world_rect().grow(64))
	ambient.color = Color.from_string(str(floor_def.get("ambient_color", "#101018")), Color(0.06, 0.05, 0.08))
	for c in corpses_root.get_children():
		c.queue_free()
	if portal and not multiplayer.is_server():
		portal.queue_free()
		portal = null
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


@rpc("authority", "call_local", "unreliable")
func _portal_status(inside: int, alive: int) -> void:
	if hud and hud.has_method("set_portal_status"):
		hud.set_portal_status(inside, alive)


@rpc("authority", "call_local", "reliable")
func broadcast_message(text: String, color_html: String) -> void:
	EventBus.hud_message.emit(text, Color.from_string(color_html, Color.WHITE))


@rpc("authority", "call_local", "reliable")
func _show_wipe(final_depth: int) -> void:
	EventBus.party_wiped.emit()
	if hud and hud.has_method("show_wipe"):
		hud.show_wipe(final_depth)


@rpc("authority", "call_local", "reliable")
func _enemy_death_fx(sprite_key: String, pos: Vector2, dir: Vector2) -> void:
	var corpse := CharacterSprite.new()
	corpse.position = pos
	corpses_root.add_child(corpse)
	corpse.set_layer("body", sprite_key)
	corpse.play("death", dir, true)
	corpse.visible = visibility.is_cell_visible(dungeon.cell_of(pos))
	var t := corpse.create_tween()
	t.tween_interval(3.0)
	t.tween_property(corpse, "modulate:a", 0.0, 1.2)
	t.tween_callback(corpse.queue_free)
	AudioManager.play_sfx_at("death", pos)


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
func find_interactable(p: Player) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var reach := float(GameData.bal("world.interact_range"))
	var pos := p.global_position
	for g in items_root.get_children():
		var d := pos.distance_to(g.global_position)
		if d < float(GameData.bal("world.pickup_range")) and d < best_d:
			best_d = d
			best = {"node": g, "kind": "item", "text": g.interact_text()}
	for o in players_root.get_children():
		if o != p and o.life_state == Player.Life.DOWNED:
			var d2 := pos.distance_to(o.global_position)
			if d2 < float(GameData.bal("world.revive_range")) and d2 < best_d + 20.0:
				best_d = d2
				best = {"node": o, "kind": "revive", "text": "Hold to revive %s" % o.display_name}
	if best.is_empty():
		for door in dungeon.doors:
			var d3 := pos.distance_to(door.interact_pos())
			if d3 < reach + door.world_rect.size.length() * 0.35 and d3 < best_d:
				best_d = d3
				best = {"node": door, "kind": "door", "text": door.interact_text()}
		for prop in dungeon.props.values():
			if is_instance_valid(prop) and prop.interactable():
				var d4 := pos.distance_to(prop.global_position)
				if d4 < reach and d4 < best_d:
					best_d = d4
					best = {"node": prop, "kind": "chest", "text": prop.interact_text()}
		if portal and pos.distance_to(portal.global_position) < portal.radius + 10.0:
			best = {"node": portal, "kind": "portal", "text": portal.interact_text()}
	if not best.is_empty():
		best.text = "[%s] %s" % [InputSettings.prompt_for("interact"), best.text]
	return best


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
