extends Node2D
## One run through the infinite dungeon. The host drives the flow: it picks floor seeds,
## spawns players/monsters/boss, scales difficulty, awards XP and loot, opens the exit portal
## and detects party wipes. Every peer builds the floor layout locally from the host's seed.

const PORTAL_SCRIPT := preload("res://scripts/dungeon/portal.gd")
const RISE_MARK := preload("res://scripts/enemies/rise_mark.gd")
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
var _rise_marks: Dictionary = {}  ## host (#49): remains that will rise: node name -> {kind, seconds, at}
var _aura_left := 0.0
var party_keys := 0  ## Gold Keys the party carries (D11), replicated by _sync_keys
var key_chest := ""  ## host: the chest prop holding the floor's Gold Key when no elite carries it (#21)
var next_mod := ""  ## host (#71): the modifier the party voted for the next floor
var mod_offer: Array = []  ## #71: the two modifiers offered at this floor's portal (every peer)
var mod_votes: Dictionary = {}  ## #71: peer -> voted modifier id (every peer)
var hunt_next_at := -1.0  ## #71 Hunted: floor_time of the next hunter (every peer, -1 = none)
var mod_runner: ModRunner
var boon_pending: Dictionary = {}  ## host (#73): peer -> the three boon ids it still chooses from
var boon_waiting: Array = []  ## #73 every peer: heroes still choosing their boon (the portal waits)
var my_boon_offer: Array = []  ## #73 local: this hero's three boons to choose from
var map_pings: Array = []  ## local: [{pos, color, until}] pulsing marks on the minimap / map
var legendary_from_enemies := false  ## host (#75): a named legendary has dropped from a monster, elite or boss on this floor
var merchant_id := ""  ## every peer: this floor's merchant (archibald / malphas, #6)
var _dyn_counter := 0
var boss_id := ""  ## this floor's boss, picked from the floor type's list by the floor seed
var floor_mechanics: Array = []  ## host: FloorMechanic modules of the floor type
var _prox_left := 0.0
var reported_maps: Dictionary = {}  ## host (#55): peer -> that client's discovered cells (raw)
var _resume: Dictionary = {}  ## host (#55): the saved floor to lay over the continued game's first floor
var _building := false  ## host: start_floor is half way (no snapshot of a half-built floor)
var _autosave_left := 0.0
var _map_report_left := 0.0
var _map_reported := 0  ## client: hash of the discovered cells last sent to the host

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
var screen_fx: ScreenFx
@onready var combat: Combat = $Combat
@onready var fx: CombatFx = $CombatFx
@onready var loot: LootManager = $Loot
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var ambient: CanvasModulate = $Ambient
var merchants: Merchants


func _ready() -> void:
	merchants = Merchants.new()
	merchants.name = "Merchants"
	merchants.game = self
	add_child(merchants)
	mod_runner = ModRunner.new()
	mod_runner.name = "ModRunner"
	mod_runner.setup(self)
	add_child(mod_runner)
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
	screen_fx = ScreenFx.new()
	add_child(screen_fx)
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
	# #55: the run seed is part of the saved game, so a continued floor is the same floor.
	if GameState.game.has("run_seed"):
		run_seed = int(GameState.game.run_seed)
	else:
		run_seed = randi()
		GameState.game.run_seed = run_seed
	_resume = GameState.game.get("floor", {}) if GameState.is_continuing() else {}
	start_floor(GameState.start_depth())


func start_floor(new_depth: int) -> void:
	_building = true
	depth = new_depth
	# Floor-bound buffs (Eater of Battles) and once-per-floor legendaries reset.
	for p in players_root.get_children():
		for st in p.status.effects.duplicate():
			if st.def.get("floor_bound", false):
				p.status.remove(st.id)
		p.remove_meta("crosier_used")
	var ft_id := floor_type_for(new_depth)
	var floor_seed := hash(run_seed + new_depth * 7919)
	var mix := FloorPlan.mix_at(run_seed, new_depth)
	# #55: the first floor of a continued game, if it is the floor the game was saved on.
	var resume: Dictionary = _resume if int(_resume.get("depth", -1)) == new_depth and int(_resume.get("seed", 0)) == floor_seed else {}
	# #71: the party's vote at the last portal (or the saved floor's modifier).
	var mod := next_mod if resume.is_empty() else str(resume.get("mod", ""))
	if not str(GameState.get_meta("force_mod", "")).is_empty():
		mod = str(GameState.get_meta("force_mod", ""))
	next_mod = ""
	_resume = {}
	reported_maps.clear()
	combat.clear_floor()
	loot.clear_floor()
	corpses.clear()
	_rise_marks.clear()
	for e in enemies_root.get_children():
		e.queue_free()
	if portal:
		portal.queue_free()
		portal = null
	_descend_timer = -1.0
	# A Gold Key belongs to its floor (D11): an unused one doesn't carry over.
	if party_keys > 0:
		add_party_key(-party_keys)
	legendary_from_enemies = false
	_build_floor.rpc(new_depth, floor_seed, ft_id, FloorPlan.bosses_to(run_seed, new_depth)[-1], pick_merchant(floor_seed), mix, mod)
	# Host-only: the spawn list depends on party size, so it is generated with that multiplier.
	var n := players_root.get_child_count() if players_root.get_child_count() > 0 else GameState.roster.size()
	var count_mult := 1.0 + float(GameData.bal("scaling.count_per_extra_player")) * (maxi(n, 1) - 1)
	count_mult *= FloorMods.num(floor_def, "count_mult")  # #71 Swarm
	var host_layout := DungeonGenerator.new().generate(floor_seed, floor_def, count_mult, new_depth, merchant_id)
	_place_players(resume)
	merchants.host_new_floor(floor_seed, item_level())
	var carrier := {}
	boss_alive = true
	boss_engaged = false
	if resume.is_empty():
		var elites := _pick_elites(host_layout, floor_seed, merchant_id == "archibald")
		carrier = pick_key_carrier(host_layout, floor_seed, merchant_id == "archibald", elites.keys())
		key_chest = "Chest_%d" % int(carrier.index) if carrier.get("kind", "") == "chest" else ""
		for gi in host_layout.spawns.size():
			var group: Dictionary = host_layout.spawns[gi]
			for mi in group.monsters.size():
				var m: Dictionary = group.monsters[mi]
				spawn_monster(str(m.id), m.pos, false, elites.get(Vector2i(gi, mi), {}))
	else:
		FloorState.restore_host(self, resume, host_layout.boss_pos)
	floor_mechanics.clear()
	for md in floor_def.get("floor_mechanics", []):
		var scr: Script = load(GameData.FLOOR_MECHANIC_DIR + str(md.id) + ".gd")
		var fm: FloorMechanic = scr.new()
		fm.setup(self, md)
		floor_mechanics.append(fm)
	if resume.is_empty():
		spawn_monster(boss_id, host_layout.boss_pos, true, {"key": true} if carrier.get("kind", "") == "boss" else {})
	_spawn_floor_hazards(host_layout)
	mod_runner.host_new_floor(floor_seed)
	_set_mod_offer.rpc([], {})
	boon_pending.clear()
	_sync_boon_wait.rpc([])
	if not resume.is_empty():
		_restore_floor_view.rpc(FloorState.view_of(resume, layout.portal_pos, self))
		_sync_clock.rpc(floor_time)
		if portal:
			host_offer_mods()
			host_offer_boons()
		for peer in GameState.roster:
			var cells := FloorState.map_bytes(resume, int(GameState.roster[peer].get("slot", -1)))
			if cells.size() != dungeon.discovered.size():
				continue
			if int(peer) == 1:
				visibility.restore_discovered(cells)
			else:
				reported_maps[int(peer)] = cells
				_restore_map.rpc_id(int(peer), cells)
	_building = false
	_autosave_left = float(GameData.bal("save.autosave_interval", 20.0))
	GameState.current_depth = new_depth
	GameState.save_game()


## Host: the saved game catches up with the world (every hero, then the floor as it stands).
func host_save() -> void:
	if not multiplayer.is_server():
		return
	for p in players_root.get_children():
		if not p.is_queued_for_deletion():
			GameState.characters[p.peer_id] = p.to_character()
	GameState.save_game()


## Host (#55): the snapshot of this floor for the saved game, or `prev` while there is no whole
## floor to describe (before the run, while a floor is being built, after a wipe).
func floor_snapshot(prev: Dictionary) -> Dictionary:
	if not _begun or _building or _wiped or depth <= 0 or layout.is_empty() or not is_inside_tree():
		return prev
	return FloorState.capture(self, prev)


## Spawns connected players that have no character in the world yet (start of a run, which can
## be a later floor when a saved game is continued) and moves everyone else to the start room.
## `resume` (#55): a continued floor puts every hero back where it stood, as it was.
func _place_players(resume: Dictionary = {}) -> void:
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
			var saved := FloorState.hero_of(resume, id)
			if not saved.is_empty():
				pos = FloorState.vec(saved.pos)
			var spawned: Node = player_spawner.spawn({"peer": id, "pos": pos, "class_id": r.class_id, "gender": r.get("gender", ""), "name": r.name, "level": r.level})
			if spawned is Player:
				FloorState.restore_hero(spawned, saved)
		elif existing:
			existing.host_teleport(pos)
			if existing.life_state != Player.Life.ALIVE:
				existing.revive(float(GameData.bal("player.next_floor_hp_fraction")))
			existing.persist()
		i += 1


## Host: D10 / D11 - 1-3 spawn groups get an elite (1-2 modifiers); when the floor's key roll
## passes (pick_key_carrier) one elite carries the Gold Key - only on Archibald floors (#6, #21).
## Returns {Vector2i(group, monster): spawn extra}.
func _pick_elites(host_layout: Dictionary, floor_seed: int, key_floor: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed + 101
	var groups: Array = []
	for gi in host_layout.spawns.size():
		if not host_layout.spawns[gi].monsters.is_empty():
			groups.append(gi)
	var out := {}
	var packs: Array = GameData.bal("elite.packs")
	var n := mini(roundi(rng.randi_range(int(packs[0]), int(packs[1])) * FloorMods.num(floor_def, "elite_mult")), groups.size())
	var mods: Array = GameData.elite_modifiers.keys()
	mods.sort()
	for i in n:
		var gi2: int = groups.pop_at(rng.randi_range(0, groups.size() - 1))
		var mi := rng.randi_range(0, host_layout.spawns[gi2].monsters.size() - 1)
		var picked: Array = []
		var mr: Array = GameData.bal("elite.modifiers")
		for k in rng.randi_range(int(mr[0]), int(mr[1])):
			var m: String = mods[rng.randi_range(0, mods.size() - 1)]
			if not picked.has(m):
				picked.append(m)
		out[Vector2i(gi2, mi)] = {"elite": picked}
	var carrier := pick_key_carrier(host_layout, floor_seed, key_floor, out.keys())
	if carrier.get("kind", "") == "elite":
		out[carrier.at].key = true
	return out


## D11 / #21: the floor's Gold Key roll, seeded and independent of how many elites the floor got.
## On a key floor (Archibald) it passes with elite.key_chance; the key then goes to one elite, or a
## chest when the floor has no elite, or the boss when it has neither.
## Returns {} (no key), {kind: "elite", at: Vector2i}, {kind: "chest", index} or {kind: "boss"}.
static func pick_key_carrier(host_layout: Dictionary, floor_seed: int, key_floor: bool, elites: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed + 211
	if not key_floor or rng.randf() >= float(GameData.bal("elite.key_chance")):
		return {}
	if not elites.is_empty():
		var sorted := elites.duplicate()
		sorted.sort()
		return {"kind": "elite", "at": sorted[rng.randi_range(0, sorted.size() - 1)]}
	var chests: Array = host_layout.get("chests", [])
	if not chests.is_empty():
		return {"kind": "chest", "index": rng.randi_range(0, chests.size() - 1)}
	return {"kind": "boss"}


## extra (optional spawn data): team ("players" for player summons), lifetime, copy_peer,
## taunt (radius taunted on spawn), elite (modifier ids), key (carries the Gold Key).
func spawn_monster(def_id: String, pos: Vector2, boss: bool, extra: Dictionary = {}) -> Node:
	var def: Dictionary = (GameData.bosses if boss else GameData.monsters).get(def_id, {})
	if def.is_empty():
		push_error("Game: unknown monster '%s'" % def_id)
		return null
	var n := maxi(players_root.get_child_count(), 1)
	var lvl := monster_level()
	var mults := spawn_mults(depth, lvl, boss, n, _difficulty())
	var hp_mult := mults.x
	var dmg_mult := mults.y
	if not extra.get("elite", []).is_empty():
		hp_mult *= float(GameData.bal("elite.hp_mult"))
		dmg_mult *= float(GameData.bal("elite.damage_mult"))
	# #71 Hunted: a hunter is an elite with more health and bite.
	hp_mult *= float(extra.get("hunter_hp", 1.0))
	dmg_mult *= float(extra.get("hunter_dmg", 1.0))
	_enemy_counter += 1
	var data := {"name": "E%d" % _enemy_counter, "def_id": def_id, "boss": boss, "pos": pos,
		"level": lvl, "hp_mult": hp_mult, "dmg_mult": dmg_mult}
	# Echo of the Unwritten: wears a random hero's look (D31).
	if def.get("copy_random_player", false) and players_root.get_child_count() > 0:
		var heroes := players_root.get_children()
		data.copy_peer = int(heroes[randi() % heroes.size()].peer_id)
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
		if not DungeonGenerator.walkable(dungeon.cell_at(dungeon.cell_of(pos))):
			pos = origin
		var e: Node = spawn_monster(def_id, pos, false, extra)
		if e == null:
			continue
		e.set_meta("summoned", true)
		if int(extra.get("team", Actor.Team.MONSTERS)) == Actor.Team.MONSTERS:
			for p in players_root.get_children():
				if p.is_targetable() and p.global_position.distance_to(origin) < 500.0:
					e.add_threat(p, 1.0)
		elif opts.has("taunt"):
			for m in combat.enemies_of(e.team, pos, float(opts.taunt)):
				if m.has_method("taunted_by"):
					m.taunted_by(e, float(opts.get("lifetime", 2.0)))


func monster_level() -> int:
	return monster_level_at(depth, party_level())


## The party's average level (1 with nobody in the world yet).
func party_level() -> float:
	var total := 0
	var n := 0
	for p in players_root.get_children():
		total += p.level
		n += 1
	return float(total) / n if n > 0 else 1.0


## Spawn HP / damage multipliers (x, y) of a monster of level `lvl` on `at_depth` for `n`
## heroes at difficulty `diff` (the balance probe runs the same function).
static func spawn_mults(at_depth: int, lvl: int, boss: bool, n: int, diff: float = 1.0) -> Vector2:
	var hp_mult := (1.0 + float(GameData.bal("scaling.hp_per_level")) * (lvl - 1)) * diff
	hp_mult *= 1.0 + float(GameData.bal("scaling.boss_hp_per_extra_player" if boss else "scaling.hp_per_extra_player")) * (n - 1)
	var dmg_mult := (1.0 + float(GameData.bal("scaling.damage_per_level")) * (lvl - 1)) * diff
	dmg_mult *= 1.0 + float(GameData.bal("scaling.damage_per_extra_player")) * (n - 1)
	# The first floors are easier (a simple start, #1): one {hp, damage, boss_hp} factor per depth.
	var early: Array = GameData.bal("scaling.early_depths", [])
	if at_depth >= 1 and at_depth <= early.size():
		hp_mult *= float(early[at_depth - 1].get("boss_hp" if boss else "hp", early[at_depth - 1].get("hp", 1.0)))
		dmg_mult *= float(early[at_depth - 1].get("damage", 1.0))
	return Vector2(hp_mult, dmg_mult)


## Monster level on `at_depth` for a party of average level `avg` (D-table "Item level"; the
## balance probe runs the same function).
static func monster_level_at(at_depth: int, avg: float) -> int:
	var w := float(GameData.bal("scaling.level_party_weight"))
	return maxi(1, roundi(float(GameData.bal("scaling.level_per_depth")) * (at_depth - 1) + w * avg + (1.0 - w)))


## Item level of drops, chests, gold and merchant stock (#8): the monster level, never above the
## level cap (an item nobody could ever wear would be useless).
func item_level() -> int:
	return item_level_at(monster_level())


static func item_level_at(mon_level: int) -> int:
	return clampi(mon_level, 1, int(GameData.bal("progression.max_level")))


## XP every contributor gets for a kill (#8): base XP x xp_mult x level^monster_xp_exponent (it
## grows like the XP a level needs, so a floor is worth about the same number of levels at any
## depth), x the elite multiplier, divided over the extra monsters a bigger party faces.
static func kill_xp(def: Dictionary, mon_level: int, elite: bool, party_size: int) -> int:
	var xp := float(def.get("xp", 0)) * float(GameData.bal("progression.xp_mult", 1.0))
	xp *= pow(float(maxi(mon_level, 1)), float(GameData.bal("progression.monster_xp_exponent", 1.0)))
	if elite:
		xp *= float(GameData.bal("elite.xp_mult"))
	xp /= 1.0 + float(GameData.bal("scaling.count_per_extra_player")) * float(GameData.bal("progression.party_xp_share", 1.0)) * (maxi(party_size, 1) - 1)
	return roundi(xp)


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
	for fm in floor_mechanics:
		fm.on_enemy_killed(e)
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
	var xp := roundi(kill_xp(e.def, e.level, e.is_elite(), maxi(players_root.get_child_count(), 1)) * FloorMods.num(floor_def, "xp_mult"))
	if e.is_elite():
		_dyn_counter += 1
		dungeon.spawn_prop.rpc("Altar_%d" % _dyn_counter, "elite_altar", altar_spot(e.global_position))
		broadcast_message.rpc("%s falls - an elite altar rises", "#e8c040", [e.display_name])
	if e.key_carrier:
		loot.drop_item(gold_key_item(), e.global_position + Vector2(-12, 6))
	var earned: Array = []
	for peer in e.contributors:
		if now - float(e.contributors[peer]) > window:
			continue
		var p := player_by_peer(peer)
		if p:
			p.add_xp(xp)
			fx.number.rpc_id(peer, p.global_position + Vector2(0, -12), "+%d XP", "xp", [xp])
			earned.append(p.get_path())
	# #81: experience motes fly from the monster to the heroes who earned it.
	if xp > 0 and not earned.is_empty():
		fx.gfx.rpc("xp", {"pos": e.global_position, "to": earned})
	if e.is_boss:
		boss_alive = false
		var drops := loot.roll_and_drop("boss", e.global_position, e.def.get("loot", {}))
		_note_enemy_legendary(drops)
		# #75: every floor gives the party at least one named legendary from its enemies; if none
		# has fallen by now, the boss drops one more (weighted to the party's classes as usual).
		if not legendary_from_enemies and not GameState.get_meta("test_no_guarantee", false):
			var lg := LootTable.roll_legendary(GameState.classes_in_party(), item_level(), loot.rng)
			if not lg.is_empty():
				loot.throw_items([lg], e.global_position, float(GameData.bal("loot.flight.stagger")) * drops.size())
				legendary_from_enemies = true
		_boss_defeated.rpc(layout.portal_pos)
		for p in players_root.get_children():
			p.persist()
	else:
		_note_enemy_legendary(loot.roll_and_drop("monster", e.global_position))
		# #71 Hunted: a hunter always drops a fine item.
		if not str(e.hunter).is_empty():
			loot.roll_and_drop("hunter", e.global_position, {"min_rarity": int(FloorMods.num(floor_def, "loot_min_rarity", 4))})
		# Elites also throw their gold pile and roll their own legendary chance
		# (legendary.drop_chance.elite).
		if e.is_elite():
			_note_enemy_legendary(loot.roll_and_drop("elite", e.global_position))


## Host (#75): a named legendary among an enemy's drops counts for the floor's guarantee.
func _note_enemy_legendary(items: Array) -> void:
	for it in items:
		if not str(it.get("legendary", "")).is_empty():
			legendary_from_enemies = true


## Host (#75): the party hears of a named legendary as it lands.
func announce_legendary(item: Dictionary, delay: float) -> void:
	var at := delay + float(GameData.bal("loot.flight.time")) + 0.2
	get_tree().create_timer(at).timeout.connect(func():
		if is_inside_tree():
			_legendary_fell.rpc(item))


## Host -> all (reliable, #75): the message in each peer's own language.
@rpc("authority", "call_local", "reliable")
func _legendary_fell(item: Dictionary) -> void:
	EventBus.hud_message.emit(Loc.f("A legendary falls: %s", [Loc.item_name(item)]), Color("ff9a2e"))


func host_interact(p: Player, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var reach := float(GameData.bal("world.interact_range")) + 24.0
	if node.has_method("interact_pos") and p.global_position.distance_to(node.interact_pos()) > reach:
		return
	# #79: never through a wall or a closed door (a door itself is reached from either side).
	if not node.has_method("host_set_open") and node is Node2D:
		var at: Vector2 = node.interact_pos() if node.has_method("interact_pos") else node.global_position
		if not dungeon.reach_clear(p.global_position, at):
			return
	# #82: a ghost only works doors that open by hand.
	if p.life_state == Player.Life.GHOST:
		if not p.ghost_can_use(node) or (node.floodgate and not node.is_open):
			return
	for b in get_tree().get_nodes_in_group("boss"):
		if b.has_method("on_mechanic_interact") and b.on_mechanic_interact(p, node):
			return
	if node is GroundItem:
		loot.try_pickup(p, node)
	elif node.get("def") is Dictionary and (node.def.has("npc") or node.def.has("gate")):
		merchants.host_interact(p, node)
	elif node.has_method("is_lit") and node.has_method("set_state"):
		if node.interactable():
			p.host_take_torch()
			dungeon.set_torch_state.rpc(node.torch_id, node.State.TAKEN)
	elif node.get("def") is Dictionary and node.def.get("lever", false):
		# A rusty lever opens its floodgate for good.
		if node.interactable():
			dungeon.open_chest.rpc(node.prop_id)
			var gi := int(node.get_meta("gate", -1))
			if gi >= 0 and gi < dungeon.doors.size():
				dungeon.doors[gi].floodgate = false
				dungeon.doors[gi].host_set_open(true)
			combat.fx.sound.rpc("floodgate", node.global_position)
	elif node.has_method("host_set_open") and node.sealed:
		if node.kind == "merchant":
			merchants.host_door(p, node)
	elif node.has_method("host_set_open") and node.floodgate and not node.is_open:
		combat.fx.number.rpc(node.interact_pos(), "Rusted shut - find a lever", "info")
	elif node.has_method("host_set_open"):
		# Don't let a door close on someone standing in the doorway.
		if node.is_open:
			for a in combat.all_actors():
				if node.world_rect.grow(4).has_point(a.global_position):
					return
		node.host_set_open(not node.is_open)
	elif node.has_method("interactable") and node.interactable():
		dungeon.open_chest.rpc(node.prop_id)
		loot.roll_and_drop(str(node.def.get("loot", "chest")), node.global_position + Vector2(0, 18))
		if not key_chest.is_empty() and node.prop_id == key_chest:
			key_chest = ""
			loot.drop_item(gold_key_item(), node.global_position + Vector2(-12, 18))
	elif node == portal:
		# The portal never pulls anyone in: every living player opts in with Interact.
		# Once the countdown runs the choice is locked, so extra presses can't toggle it.
		if _descend_timer >= 0.0:
			return
		# #73: a hero still choosing its boon gets the boon cards first.
		if boon_pending.has(p.peer_id):
			_boon_offer.rpc_id(p.peer_id, boon_pending[p.peer_id])
			return
		# #71: with modifiers on offer, the portal opens the vote; a card is the vote and "ready".
		if not mod_offer.is_empty() and not portal_ready.has(p.peer_id):
			_open_mod_vote.rpc_id(p.peer_id)
			return
		if portal_ready.has(p.peer_id):
			mod_votes.erase(p.peer_id)
			_set_mod_offer.rpc(mod_offer, mod_votes)
			portal_ready.erase(p.peer_id)
		else:
			portal_ready[p.peer_id] = true
		_try_descend()


func _physics_process(delta: float) -> void:
	floor_time += delta
	for s in dungeon.spikes:
		s.update_state(floor_time)
	for sp in dungeon.spouts:
		sp.update_state(floor_time)
	if not multiplayer.is_server() and depth > 0:
		_report_map_tick(delta)
	if not multiplayer.is_server() or depth == 0:
		return
	# #55: the saved game follows the floor, so a crash or a killed process loses little.
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = float(GameData.bal("save.autosave_interval", 20.0))
		host_save()
	_clock_sync_left -= delta
	if _clock_sync_left <= 0.0:
		_clock_sync_left = 5.0
		_sync_clock.rpc(floor_time)
	mod_runner.host_tick(delta)
	var actors := combat.all_actors()
	for s in dungeon.spikes:
		s.host_damage(actors)
	for pl in dungeon.plates:
		pl.host_tick(delta, actors, dungeon)
	for sp in dungeon.spouts:
		sp.host_damage(actors, floor_time)
	for gr in dungeon.grates:
		gr.host_tick(delta, actors, dungeon)
	for pp in dungeon.pulse_props.duplicate():
		_pulse_prop(pp, delta)
	_prox_left -= delta
	if _prox_left <= 0.0:
		_prox_left = 0.2
		_check_proximity_props()
	for fm in floor_mechanics:
		fm.physics(delta)
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
			if a.is_targetable() and dungeon.is_lava(a.global_position) and not a.has_meta("ignores_hazards"):
				if a.stats.has_flag("lava_walker"):
					# Magma Tectonic Slacks: lava mends and empowers.
					combat.heal(combat.env_ctx(0.0), a, float(GameData.bal("hazards.lava_damage")))
					a.status.apply("magma_surge", float(GameData.bal("hazards.lava_tick")) + 0.6, 0.0, combat.env_ctx(0.0))
					continue
				var lava := float(GameData.bal("hazards.lava_damage")) * (0.2 if a.stats.has_flag("lava_resist") else 1.0)
				combat.deal_damage(combat.env_ctx(0.0), a, lava, {"dot": true, "damage_type": "fire"})
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
	if alive > 0 and portal_ready.size() >= alive and _portal_gates_open():
		_descend_timer = 1.5
		# #71: the party's choice for the next floor (majority, ties by a seeded pick).
		next_mod = FloorMods.resolve(mod_offer, mod_votes, run_seed, depth + 1)
		if next_mod.is_empty():
			broadcast_message.rpc("Descending...", "#c08cff")
		else:
			broadcast_message.rpc("Descending... next floor: %s", "#c08cff", [str(FloorMods.def(next_mod).name)])
		_set_mod_offer.rpc(mod_offer, mod_votes, true)


## Host: everything else the portal waits for besides every living hero: #73 every hero's boon.
func _portal_gates_open() -> bool:
	for peer in boon_pending.keys():
		if player_by_peer(int(peer)) == null:
			boon_pending.erase(peer)
	return boon_pending.is_empty()


## Host (#73): after the boss, every hero who hasn't chosen this floor's boon gets three of its
## own (seeded by the run, the floor and the hero's slot).
func host_offer_boons() -> void:
	for p in players_root.get_children():
		if p.boon_floor >= depth:
			continue
		var slot := int(GameState.roster.get(p.peer_id, {}).get("slot", p.peer_id))
		var ids := Boons.offer(p.class_id, p.boons, hash([run_seed, depth, slot, 73]))
		if ids.is_empty():
			continue
		boon_pending[p.peer_id] = ids
		_boon_offer.rpc_id(p.peer_id, ids)
	_sync_boon_wait.rpc(boon_pending.keys())


## Host -> one hero (reliable, #73): its three boons; the choice screen opens.
@rpc("authority", "call_local", "reliable")
func _boon_offer(ids: Array) -> void:
	my_boon_offer = ids
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("offer_boons"):
		hud.offer_boons()


## Host -> all (reliable, #73): who is still choosing.
@rpc("authority", "call_local", "reliable")
func _sync_boon_wait(peers: Array) -> void:
	boon_waiting = peers
	EventBus.boon_wait_changed.emit()


## Owner -> host (reliable, #73): the hero takes boon `index` of its offer (-1 skips).
@rpc("any_peer", "call_local", "reliable")
func request_boon(index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var p := player_by_peer(peer)
	if p == null or not boon_pending.has(peer):
		return
	var ids: Array = boon_pending[peer]
	boon_pending.erase(peer)
	p.boon_floor = depth
	if index >= 0 and index < ids.size():
		p.host_add_boon(str(ids[index]), item_level(), loot.rng)
		_boon_taken.rpc(peer, str(ids[index]))
	else:
		p.persist()
	_sync_boon_wait.rpc(boon_pending.keys())
	_try_descend()


## Host -> all (reliable, #73): `peer`'s hero took boon `id`: it flares on the hero once.
@rpc("authority", "call_local", "reliable")
func _boon_taken(peer: int, id: String) -> void:
	var p := player_by_peer(peer)
	if p == null:
		return
	var col := Boons.color(id)
	fx.ring(p.global_position, 46.0, col.to_html(false), "")
	fx.boon_flare(p.global_position, col)
	AudioManager.play_sfx_at("boon_pick", p.global_position)
	if p.is_local():
		my_boon_offer = []


## Owner -> host (reliable, #71): `id` is this hero's vote at the portal ("" takes it back).
@rpc("any_peer", "call_local", "reliable")
func request_mod_vote(id: String) -> void:
	if not multiplayer.is_server() or _descend_timer >= 0.0 or portal == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var pl := player_by_peer(peer)
	if pl == null or pl.life_state != Player.Life.ALIVE:
		return
	if id.is_empty():
		mod_votes.erase(peer)
		portal_ready.erase(peer)
	elif mod_offer.has(id):
		mod_votes[peer] = id
		portal_ready[peer] = true
	_set_mod_offer.rpc(mod_offer, mod_votes)
	_try_descend()


## Host -> all (reliable, #71): the offer and the votes so far (`locked` once the party descends).
@rpc("authority", "call_local", "reliable")
func _set_mod_offer(offer: Array, votes: Dictionary, locked: bool = false) -> void:
	mod_offer = offer
	mod_votes = votes
	EventBus.mod_vote_changed.emit(locked)


## Host -> one hero (reliable, #71): it stepped into the portal; show it the cards.
@rpc("authority", "call_local", "reliable")
func _open_mod_vote() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_mod_vote"):
		hud.open_mod_vote()


## Host -> all (reliable, #71 Hunted): when the next hunter comes (floor_time, -1 = none).
@rpc("authority", "call_local", "reliable")
func set_hunt_next(at: float) -> void:
	hunt_next_at = at


## Host -> all (reliable, #71 Hunted): the rift opens `warn` s before the hunter steps out.
@rpc("authority", "call_local", "reliable")
func open_hunt_rift(pos: Vector2, hunter_name: String, warn: float) -> void:
	var rift := HuntRift.new()
	rift.setup(pos, Loc.f("%s the Hunter", [hunter_name]), warn)
	entities.add_child(rift)
	add_map_ping(pos, UITheme.WARN, warn + 2.0)
	EventBus.hud_message.emit(Loc.f("A rift opens: %s is coming", [Loc.f("%s the Hunter", [hunter_name])]), UITheme.WARN)


## Host -> all (reliable, #71 Hunted): the hunter stepped out of its rift.
@rpc("authority", "call_local", "reliable")
func hunter_arrived(pos: Vector2) -> void:
	Telegraph.fired("hunter")
	for r in entities.get_children():
		if r is HuntRift and r.position.distance_to(pos) < 4.0:
			r.arrive()


## Local: a pulsing mark on the minimap and the map for `seconds`.
func add_map_ping(pos: Vector2, color: Color, seconds: float) -> void:
	map_pings.append({"pos": pos, "color": color, "until": floor_time + seconds})


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
func _build_floor(new_depth: int, floor_seed: int, ft_id: String, floor_boss: String, floor_merchant: String, mix: String = "", mod: String = "") -> void:
	depth = new_depth
	floor_time = 0.0
	# #70: a mixed floor is built from its biome's definition with part of the invader's pool;
	# #71: the floor modifier's numbers are folded in too.
	floor_def = FloorPlan.floor_def(ft_id, mix, floor_seed, mod)
	map_pings.clear()
	boss_id = floor_boss
	merchant_id = floor_merchant
	layout = DungeonGenerator.new().generate(floor_seed, floor_def, 1.0, new_depth, floor_merchant)
	dungeon.build(layout, floor_def, entities)
	visibility.reset_floor()
	# Ground fog (Kurgan) shrinks carried torches too.
	for p in players_root.get_children():
		if p.get("_torch_light"):
			LightLayers.register(p._torch_light, float(GameData.bal("lighting.carried_torch_radius")) * float(floor_def.get("torch_radius_mult", 1.0)))
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
	# The HUD's floor banner announces it (#70).
	EventBus.floor_started.emit(new_depth)


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


## D21: depth cycles through the floor types by their "order" (Crypt, Sewers, Foundry, Archives,
## Kurgan). Tests and tours can pin the first floor's type ("force_biome" meta on GameState).
## The biome of floor `new_depth` in this run (#70: fixed for the first cycle, then shuffled).
func floor_type_for(new_depth: int) -> String:
	return FloorPlan.biome_at(run_seed, new_depth)


## Host: the floor's boss, a seeded pick from the floor type's list ("force_boss" meta on
## GameState pins one for tests and screenshots).
## Host: the floor's one merchant (#6), a seeded pick ("force_merchant" meta on GameState pins
## one for tests and screenshots).
static func pick_merchant(floor_seed: int) -> String:
	var forced := str(GameState.get_meta("force_merchant", ""))
	if forced != "" and GameData.merchants.get("floor_pick", {}).has(forced):
		return forced
	return DungeonGenerator.pick_merchant(floor_seed)


static func pick_boss(ft: Dictionary, floor_seed: int, avoid: String = "") -> String:
	return FloorPlan.pick_boss(ft, floor_seed, avoid)


@rpc("authority", "call_local", "reliable")
func _boss_music(on: bool) -> void:
	var bdef: Dictionary = GameData.bosses.get(boss_id, {})
	AudioManager.play_music(str(bdef.get("music", floor_def.get("boss_music", "")) if on else floor_def.music))
	if on:
		var b := get_tree().get_first_node_in_group("boss")
		EventBus.boss_engaged.emit(b)


@rpc("authority", "call_local", "reliable")
func _boss_defeated(portal_pos: Vector2) -> void:
	AudioManager.play_music(str(floor_def.music))
	EventBus.boss_defeated.emit(null)
	EventBus.hud_message.emit(Loc.t("The boss is defeated! A portal opens..."), Color(0.75, 0.55, 1.0))
	place_portal(portal_pos)
	if multiplayer.is_server():
		host_offer_mods()
		host_offer_boons()


## Host (#71): the portal's two modifiers for the next floor, sent to every peer.
func host_offer_mods() -> void:
	_set_mod_offer.rpc(FloorMods.offer(run_seed, depth + 1, str(floor_def.get("mod", ""))), {})


func place_portal(portal_pos: Vector2) -> void:
	if portal and is_instance_valid(portal):
		return
	portal = PORTAL_SCRIPT.new()
	portal.name = "Portal"
	portal.position = portal_pos
	entities.add_child(portal)


## Host -> all (reliable, #55): the continued floor's props, doors, torches, grates and cells as
## they were saved, laid over the floor just built from the seed; the portal if the boss is dead.
@rpc("authority", "call_local", "reliable")
func _restore_floor_view(view: Dictionary) -> void:
	FloorState.apply_view(self, view)


## Host -> one client (reliable, #55): the cells its player had discovered on this floor.
@rpc("authority", "call_remote", "reliable")
func _restore_map(cells: PackedByteArray) -> void:
	if cells.size() == dungeon.discovered.size():
		visibility.restore_discovered(cells)
	_map_reported = hash(dungeon.discovered)


## Client: sends its discovered cells to the host every few seconds when they changed, so the
## host can keep them in the saved game.
func _report_map_tick(delta: float) -> void:
	_map_report_left -= delta
	if _map_report_left > 0.0:
		return
	_map_report_left = float(GameData.bal("save.map_report_interval", 5.0))
	var h := hash(dungeon.discovered)
	if h == _map_reported:
		return
	_map_reported = h
	_report_map.rpc_id(1, depth, dungeon.discovered.compress(FloorState.MAP_COMPRESSION))


## Client -> host (reliable, #55): the sender's discovered cells on floor `at_depth`.
@rpc("any_peer", "call_remote", "reliable")
func _report_map(at_depth: int, packed: PackedByteArray) -> void:
	if not multiplayer.is_server() or at_depth != depth:
		return
	var cells := packed.decompress(dungeon.discovered.size(), FloorState.MAP_COMPRESSION)
	if cells.size() == dungeon.discovered.size():
		reported_maps[multiplayer.get_remote_sender_id()] = cells


## Host -> all (reliable): who is ready to descend.
@rpc("authority", "call_local", "reliable")
func _portal_status(ready_ids: Array, alive: int) -> void:
	portal_ready.clear()
	for id in ready_ids:
		portal_ready[int(id)] = true
	if hud and hud.has_method("set_portal_status"):
		hud.set_portal_status(ready_ids.size(), alive)


@rpc("authority", "call_local", "reliable")
func broadcast_message(text: String, color_html: String, args: Array = []) -> void:
	EventBus.hud_message.emit(Loc.f(text, args), Color.from_string(color_html, Color.WHITE))


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
	_rise_marks.erase("Corpse_%d" % corpse_id)
	var c := corpses_root.get_node_or_null("Corpse_%d" % corpse_id)
	if c:
		c.queue_free()


## Host: `remains` (a bone-pile enemy, or a corpse node "Corpse_<id>") will rise in `seconds`; every
## peer shows the mark with its own countdown. Called by the rise-again behaviour modules.
func host_rise_mark(remains: Node, seconds: float, kind: String) -> void:
	if remains == null or not is_instance_valid(remains):
		return
	_rise_marks[str(remains.name)] = {"kind": kind, "seconds": seconds, "at": floor_time}
	_rise_mark.rpc(remains.get_path(), seconds, kind)


## Host: `remains` won't rise (any more): it rose, was crushed, or its raiser stopped.
func host_rise_clear(remains: Node) -> void:
	if remains == null or not is_instance_valid(remains):
		return
	if _rise_marks.erase(str(remains.name)):
		_rise_clear.rpc(remains.get_path())


## The corpse node of corpse `cid` on this peer, or null.
func corpse_node(cid: int) -> Node:
	return corpses_root.get_node_or_null("Corpse_%d" % cid)


## Host -> all (reliable): show the rise mark on `path` for `seconds` (each peer counts down).
@rpc("authority", "call_local", "reliable")
func _rise_mark(path: NodePath, seconds: float, kind: String) -> void:
	var n := get_node_or_null(path)
	if n == null:
		return
	var old := rise_mark_of(n)
	if old:
		old.free()
	entities.add_child(RISE_MARK.new(n, kind, seconds))


## Host -> all (reliable): remove the rise mark of `path`.
@rpc("authority", "call_local", "reliable")
func _rise_clear(path: NodePath) -> void:
	var m := rise_mark_of(get_node_or_null(path))
	if m:
		m.queue_free()


## The rise mark of `remains` on this peer (#49), or null.
func rise_mark_of(remains: Node) -> Node:
	if remains == null:
		return null
	var m := entities.get_node_or_null("RiseMark_" + str(remains.name))
	return m if m and not m.is_queued_for_deletion() and m.remains == remains else null


## Host: corpses within r of pos (optionally only bone piles / one creature type).
## Host: the floor's standing hazards that live in the combat zone system (Archives' void rifts
## pull and burn with shadow; silence runes are one-shot traps).
func _spawn_floor_hazards(lay: Dictionary) -> void:
	var env := combat.env_ctx(0.0)
	for pos in lay.get("rifts", []):
		var c := env.duplicate()
		c.damage_type = "shadow"
		combat.add_zone({"type": "zone", "radius": 56, "duration": 99999.0, "tick": 0.5, "damage": {"base": 3, "coef": 0}, "damage_type": "shadow",
			"color": "#5a20a0", "sprite": "void_rift",
			"tick_effects": [{"type": "pull", "at": "self", "radius": 110, "force": 70}]}, c, pos)
	for pos in lay.get("snares", []):
		combat.add_zone({"type": "trap", "trigger_radius": 16, "duration": 99999.0, "color": "#6a4a1a", "sprite": "root_snare",
			"effects": [{"type": "status", "target": "event_target", "status": "root", "duration": 2.0},
				{"type": "status", "target": "event_target", "status": "bleed", "duration": 4.0, "magnitude": {"base": 2, "coef": 0}}]}, env, pos)
	for pos in lay.get("runes", []):
		combat.add_zone({"type": "trap", "trigger_radius": 16, "duration": 99999.0, "color": "#a0a0ff", "sprite": "silence_rune",
			"effects": [{"type": "status", "target": "event_target", "status": "silence", "duration": 3.0},
				{"type": "aoe", "at": "self", "radius": 20, "damage": {"base": 1, "coef": 0}, "color": "#a0a0ff"}]}, env, pos)


## Host: boiling cauldrons and the like splash everyone around them every few seconds.
func _pulse_prop(pr: Node, delta: float) -> void:
	if not is_instance_valid(pr):
		dungeon.pulse_props.erase(pr)
		return
	var pd: Dictionary = pr.def.pulse
	var left := float(pr.get_meta("pulse_left", randf() * float(pd.get("every", 6.0)))) - delta
	if left > 0.0:
		pr.set_meta("pulse_left", left)
		return
	pr.set_meta("pulse_left", float(pd.get("every", 6.0)))
	var ctx := combat.env_ctx(float(pd.get("damage", 10)))
	var eff := {"type": "aoe", "radius": float(pd.get("radius", 56)), "damage": {"base": 0, "coef": 1.0}, "damage_type": str(pd.get("damage_type", "fire")),
		"color": str(pd.get("color", "#ff9a3a"))}
	if pd.has("status"):
		# Dread totems: a fear wave instead of a scald.
		eff.on_hit = [{"type": "status", "status": str(pd.status), "duration": float(pd.get("status_time", 2.0))}]
	combat.apply_aoe(eff, ctx, pr.global_position)
	combat.fx.sound.rpc("cauldron", pr.global_position)


## Host: gas pockets and the like go off when a hero walks up to them.
func _check_proximity_props() -> void:
	for pr in dungeon.proximity_props.duplicate():
		if not is_instance_valid(pr) or not pr.destructible():
			dungeon.proximity_props.erase(pr)
			continue
		for p in players_root.get_children():
			if p.is_targetable() and p.global_position.distance_to(pr.global_position) <= float(pr.def.proximity):
				dungeon.proximity_props.erase(pr)
				pr.take_damage(pr.hp + 1.0, combat.make_ctx(p, {"id": "proximity", "school": "physical"}))
				break


## Host: a prop broke (floor mechanics react: grave urn miasma...).
func on_prop_broken(prop: Node) -> void:
	for fm in floor_mechanics:
		fm.on_prop_broken(prop)


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
	# #82: the camera and sight stay on the local hero, ghost or not (no spectating).
	if camera.target != local_player:
		camera.target = local_player
		visibility.viewer = local_player


## The single thing the local player would interact with: {node, kind, text, index, count, key}
## or {}. Everything within reach is a candidate; the player chooses by pointing at it:
## - mouse: the candidate closest to the cursor,
## - gamepad: the candidate the character faces (aim direction), nearer ones first on ties.
## Things at the same spot as that one (an item lying in a doorway...) form a stack the player
## switches through with "interact_next" (`pick`, #35): an item they can take comes first, then
## doors and the rest, items they can't take last (their prompt says why).
func find_interactable(p: Player, pick: int = 0) -> Dictionary:
	var pos := p.global_position
	var reach := float(GameData.bal("world.interact_range"))
	var candidates: Array = []  ## [point to aim at, node, kind, text]
	if p.life_state == Player.Life.GHOST:
		# #82: a ghost only opens and closes doors.
		for door in dungeon.doors:
			if p.ghost_can_use(door) and _distance_to_rect(pos, door.world_rect) < reach * 0.6:
				candidates.append([door.world_rect.get_center(), door, "door", door.interact_text()])
		return _pick_interactable(p, candidates, pick)
	for g in items_root.get_children():
		if g.is_landed() and pos.distance_to(g.global_position) < float(GameData.bal("world.pickup_range")):
			candidates.append([g.global_position, g, "item", g.interact_text(p.level)])
	for o in players_root.get_children():
		if o != p and o.life_state == Player.Life.DOWNED and pos.distance_to(o.global_position) < float(GameData.bal("world.revive_range")):
			candidates.append([o.global_position, o, "revive", Loc.f("Hold to revive %s", [o.display_name])])
	for door in dungeon.doors:
		# Doors are wide: in reach when the nearest point of the doorway is.
		if _distance_to_rect(pos, door.world_rect) < reach * 0.6:
			candidates.append([door.world_rect.get_center(), door, "door", door.interact_text()])
	for prop in dungeon.props.values():
		if is_instance_valid(prop) and prop.interactable() and pos.distance_to(prop.global_position) < reach:
			candidates.append([prop.global_position, prop, "chest", prop.interact_text()])
	for t in dungeon.torches.values():
		if is_instance_valid(t) and t.interactable() and pos.distance_to(t.interact_pos()) < reach:
			candidates.append([t.global_position, t, "torch", t.interact_text()])
	if portal and pos.distance_to(portal.global_position) < portal.radius:
		var ready := portal_ready.has(p.peer_id)
		var text := Loc.t("Cancel - stay on this floor") if ready else Loc.t("Enter the portal")
		candidates.append([portal.global_position, portal, "portal", Loc.f("%s (%d/%d ready)", [text, portal_ready.size(), _alive_count()])])
	# #79: only what the hero can reach on its own side of a wall (doors: from either side).
	candidates = candidates.filter(func(c): return c[2] == "door" or dungeon.reach_clear(pos, c[1].interact_pos() if c[1].has_method("interact_pos") else c[0]))
	return _pick_interactable(p, candidates, pick)


## The candidate `p` points at, and the stack of things at that spot (see find_interactable).
func _pick_interactable(p: Player, candidates: Array, pick: int) -> Dictionary:
	var pos := p.global_position
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
	var at: Vector2 = best[0]
	if best[1].has_method("host_set_open"):
		at = _closest_on_rect(p.aim_pos if not InputSettings.using_gamepad else pos, best[1].world_rect)
	var stack_r := float(GameData.bal("world.interact_stack_radius", 30))
	var stack: Array = []
	for c in candidates:
		var pt: Vector2 = _closest_on_rect(at, c[1].world_rect) if c[1].has_method("host_set_open") else c[0]
		if pt.distance_to(at) <= stack_r or c == best:
			var rank := 1
			var text: String = c[3]
			if c[2] == "item":
				var why := take_refusal(p, c[1].item)
				rank = 0 if why.is_empty() else 2
				if not why.is_empty():
					text = "%s - %s" % [text, Loc.t(why)]
			stack.append([rank, pt.distance_to(at), c, text])
	stack.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var i := posmod(pick, stack.size())
	var chosen: Array = stack[i][2]
	var key := ",".join(stack.map(func(s): return str(s[2][1].get_instance_id())))
	# The HUD draws the interact button glyph in front of the text.
	return {"node": chosen[1], "kind": chosen[2], "text": stack[i][3], "index": i, "count": stack.size(), "key": key}


## Why `p` can't take a ground item ("" = they can): a full backpack, or a backpack no bigger than
## the one they carry. Checked on the player's own copy of the inventory (prompts only; the host
## decides on pickup).
func take_refusal(p: Player, item: Dictionary) -> String:
	match str(item.get("kind", "")):
		"gold", "gold_key":
			return ""
		"backpack":
			return "" if int(item.get("capacity", 0)) > p.inv.capacity else "You already have a backpack this big"
	return "" if p.inv.can_add(item) else "Backpack is full"


## True when `pos` lies in (or right at) a doorway.
func in_doorway(pos: Vector2) -> bool:
	var m := float(GameData.bal("world.door_drop_margin", 6))
	for d in dungeon.doors:
		if Rect2(d.world_rect).grow(m).has_point(pos):
			return true
	return false


## The centre of the nearest walkable floor cell to `pos` that is not a doorway (#35).
func floor_beside_door(pos: Vector2) -> Vector2:
	var c := dungeon.cell_of(pos)
	for r in range(1, 6):
		var best := Vector2.INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var cc := c + Vector2i(dx, dy)
				var at := dungeon.cell_center(cc)
				if dungeon.cell_at(cc) == DungeonGenerator.CELL_FLOOR and not in_doorway(at) and at.distance_to(pos) < best.distance_to(pos):
					best = at
		if best != Vector2.INF:
			return best
	return pos


## Host (#63): where a solid piece (an elite altar) may rise near `pos` without blocking the way:
## the nearest dry floor cell with all eight neighbours open (not a corridor), a cell clear of
## every door and away from other props. Falls back to the nearest floor.
func altar_spot(pos: Vector2) -> Vector2:
	var c := dungeon.cell_of(pos)
	var tile := float(dungeon.tile)
	for r in range(0, 8):
		var best := Vector2.INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				var at := dungeon.cell_center(cc)
				if at.distance_to(pos) < best.distance_to(pos) and _altar_fits(cc, at, tile):
					best = at
		if best != Vector2.INF:
			return best
	return nearest_floor(pos)


func _altar_fits(cc: Vector2i, at: Vector2, tile: float) -> bool:
	if dungeon.cell_at(cc) != DungeonGenerator.CELL_FLOOR or dungeon.safe_rect.has_point(cc):
		return false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dungeon.cell_at(cc + Vector2i(dx, dy)) != DungeonGenerator.CELL_FLOOR:
				return false
	for d in dungeon.doors:
		if Rect2(d.world_rect).grow(tile).has_point(at):
			return false
	for pr in dungeon.props.values():
		if is_instance_valid(pr) and pr.global_position.distance_to(at) < tile:
			return false
	return true


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
	# No dry stone near: any walkable cell (shallow water, a catwalk).
	for r2 in range(0, 6):
		for dx2 in range(-r2, r2 + 1):
			for dy2 in range(-r2, r2 + 1):
				var cc2 := c + Vector2i(dx2, dy2)
				if DungeonGenerator.walkable(dungeon.cell_at(cc2)):
					return dungeon.cell_center(cc2)
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



# --- Gold Key (D11): a shared party item ------------------------------------------------------


func gold_key_item() -> Dictionary:
	return {"kind": "gold_key", "base": "gold_key", "name": "Gold Key", "icon": "items.gold_key", "rarity": 5,
		"uid": ItemGenerator.new_uid(loot.rng)}


## Host: the party picked up / used a key.
func add_party_key(delta_keys: int) -> void:
	party_keys = maxi(party_keys + delta_keys, 0)
	_sync_keys.rpc(party_keys)


## Host -> all (reliable): how many Gold Keys the party carries.
@rpc("authority", "call_local", "reliable")
func _sync_keys(n: int) -> void:
	party_keys = n
