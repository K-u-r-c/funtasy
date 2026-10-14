extends Node2D
## One dungeon run. The host (peer 1) owns the game: it picks floor seeds, spawns players and
## enemies, runs enemy AI and decides when the party descends or is wiped out.
## Dungeon layout is generated locally on every peer from the host's seed.

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const STAIRS_RADIUS := 26.0
const START_OFFSETS := [Vector2(-10, -10), Vector2(10, -10), Vector2(-10, 10), Vector2(10, 10)]

var depth := 0
var kills := 0
var input_blocked := false

var _begun := false
var _floor_active := false
var _game_over := false
var _enemy_counter := 0
var _last_status := Vector2i(-1, -1)

@onready var dungeon: Dungeon = $Dungeon
@onready var stairs: Node2D = $Stairs
@onready var players_root: Node2D = $Entities/Players
@onready var enemies_root: Node2D = $Entities/Enemies
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var camera: Camera2D = $Camera
@onready var hud = $HUD


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	enemy_spawner.spawn_function = _spawn_enemy
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		Net.peer_loaded.connect(func(_id): _try_begin())
	Net.notify_loaded()


func _process(_delta: float) -> void:
	var target := players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	if target == null or not target.alive:
		target = null
		for p in players_root.get_children():
			if p.alive:
				target = p
				break
	if target:
		camera.global_position = target.global_position


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or not _floor_active or _game_over:
		return
	if players_root.get_child_count() == 0:
		return
	var alive := 0
	var gathered := 0
	for p in players_root.get_children():
		if p.alive:
			alive += 1
			if p.global_position.distance_to(stairs.global_position) <= STAIRS_RADIUS:
				gathered += 1
	var status := Vector2i(gathered, alive)
	if status != _last_status:
		_last_status = status
		_sync_stairs_status.rpc(gathered, alive)
	if alive == 0:
		_game_over = true
		_show_game_over.rpc(depth, kills)
	elif gathered == alive:
		depth += 1
		_new_floor(false)


# --- Host: run flow ----------------------------------------------------------------------


func _try_begin() -> void:
	if _begun or not Net.all_loaded():
		return
	_begun = true
	depth = 1
	_new_floor(true)


func _new_floor(first: bool) -> void:
	_floor_active = false
	_last_status = Vector2i(-1, -1)
	var floor_seed := randi()
	_build_floor.rpc(floor_seed, depth)
	for e in enemies_root.get_children():
		e.queue_free()
	var start := dungeon.room_center(dungeon.start_room)
	var i := 0
	for id in Net.players:
		var pos: Vector2 = start + START_OFFSETS[i % START_OFFSETS.size()]
		if first:
			player_spawner.spawn({"id": id, "pos": pos, "color": i, "name": Net.players[id]})
		else:
			var p := players_root.get_node_or_null(str(id))
			if p:
				p.teleport.rpc(pos, true)
		i += 1
	_spawn_enemies(floor_seed)
	_floor_active = true


func _spawn_enemies(floor_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed ^ 0x5BD1E995
	for room in dungeon.rooms:
		if room == dungeon.start_room:
			continue
		var count := rng.randi_range(1, 2) + depth / 2
		for k in count:
			_enemy_counter += 1
			enemy_spawner.spawn({
				"name": "E%d" % _enemy_counter,
				"pos": dungeon.random_point_in(room, rng),
				"hp": 2 + depth,
				"speed": minf(34.0 + depth * 3.0, 70.0),
			})


func _on_peer_disconnected(id: int) -> void:
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.queue_free()


@rpc("any_peer", "call_local", "reliable")
func hit_enemy(enemy_name: String, damage: int) -> void:
	if not multiplayer.is_server():
		return
	var e := enemies_root.get_node_or_null(enemy_name)
	if e == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1
	var attacker := players_root.get_node_or_null(str(attacker_id))
	var from: Vector2 = attacker.global_position if attacker else e.global_position
	if e.take_damage(damage, from):
		kills += 1
		_sync_kills.rpc(kills)
		e.queue_free()


# --- Replicated events -------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _build_floor(floor_seed: int, new_depth: int) -> void:
	depth = new_depth
	dungeon.generate(floor_seed)
	stairs.position = dungeon.room_center(dungeon.exit_room)
	var size := dungeon.world_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	hud.set_floor(new_depth)


@rpc("authority", "call_local", "reliable")
func _sync_kills(total: int) -> void:
	kills = total
	hud.set_kills(total)


@rpc("authority", "call_local", "reliable")
func _sync_stairs_status(gathered: int, alive: int) -> void:
	hud.set_stairs_status(gathered, alive)


@rpc("authority", "call_local", "reliable")
func _show_game_over(final_depth: int, final_kills: int) -> void:
	hud.show_game_over(final_depth, final_kills)


# --- Spawn functions (run on every peer with the host's data) -----------------------------


func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data.id)
	p.position = data.pos
	p.color_index = data.color
	p.display_name = data.name
	return p


func _spawn_enemy(data: Dictionary) -> Node:
	var e := ENEMY_SCENE.instantiate()
	e.name = data.name
	e.position = data.pos
	e.hp = data.hp
	e.max_hp = data.hp
	e.speed = data.speed
	return e
