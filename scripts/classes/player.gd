class_name Player
extends Actor
## A player character. Authority split:
## - the owning peer simulates its own movement (client-side prediction) and streams
##   position/facing/aim through OwnerSync;
## - the host owns everything else (HP, resource, cooldowns, inventory, XP, life state) and
##   validates movement speed. Clients only send intents (skill, dodge, interact, item use).

enum Life { ALIVE, DOWNED, GHOST }

const SLOT_ACTIONS := ["attack", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5"]

var peer_id := 1
var class_id := "warrior"
var class_def: Dictionary = {}
var gender := "male"  ## body art (data/assets.json characters.genders); set at spawn
var skills: Array = []:  ## the loadout: slot 0 = primary attack, 1..5 = skills (replicated)
	set(v):
		skills = v
		if is_inside_tree() and is_local():
			EventBus.local_loadout_changed.emit()

# Replicated by the host (StateSync).
var life_state: int = Life.ALIVE
var torch_sync := 0  ## whole seconds left on the carried torch (host-driven, 0 = none)
var held_by := NodePath():  ## a boss holding this hero (the Amalgam's engulf, #12); replicated
	set(v):
		held_by = v
		# Held inside the boss: no collision (it would shove the boss around), pinned to it.
		collision_layer = 0 if not v.is_empty() else 2
		collision_mask = 0 if not v.is_empty() else (1 | 4 | 8 | 16 | 32 | 64 | 128)
		# Drawn over the boss, green and see-through (the Engulfed look), so the party sees who is held.
		z_index = 1 if not v.is_empty() else 0
var still_time := 0.0  ## host: seconds without moving
var downed_left := 0.0
var revive_progress := 0.0
var xp := 0
var talent_points := 0
var stat_points := 0  ## unspent free stat points (balance progression.stat_points_per_level, D5 / #27)
var allocated: Dictionary = {}  ## stat -> points spent on it
var run_mods: Array = []  ## run-permanent modifiers [{stat, value, source}] (D17)
var gold := 0
var bonus_stat_points := 0  ## from the legendary tome
var bonus_talent_points := 0
var legacy_kit := false  ## a hero saved before the simple start: the old tier-0 starter skills stay free
var talents: Dictionary = {}:
	set(v):
		talents = v
		# Clients only receive the final stats; talent skill modifiers (cooldowns, costs, damage
		# per skill) are rebuilt locally from the replicated ranks for the UI.
		if stats and not class_def.is_empty():
			stats.skill_mods = Stats.skill_mods_for(class_def, v)
var appearance: Dictionary = {}:
	set(v):
		appearance = v
		_apply_appearance()
# Replicated by the owner (OwnerSync).
var aim_pos := Vector2.ZERO

var inv := Inventory.new()  ## host: authoritative; owner: last snapshot from the host
var local_cd: Dictionary = {}  ## owner: slot -> [left, total]
var item_cd_left := 0.0
var item_cd_total := 1.0
var torch_left := 0.0  ## host: exact seconds left on the carried torch
var _torch_node: Node2D
var _torch_light: PointLight2D
var _torch_t := 0.0

# Host-only state
var iframe_left := 0.0
var _move_allowance := 0.0
var _reviver: Player = null
var _revive_target: Player = null
var _dodge_cd_host := 0.0
var _item_cd_host: Dictionary = {}

# Owner-only state
var _dodge_left := 0.0
var _dodge_dir := Vector2.ZERO
var _dodge_cd := 0.0
var _forced_vel := Vector2.ZERO
var _forced_left := 0.0
var dash_sync := false  ## owner -> everyone (OwnerSync): dodging or in a forced dash right now
var _seen_life := 0  ## every peer: the life state the sprite last showed (Life.ALIVE)
var _fall_left := 0.0  ## every peer: the "death" fall plays this long before the downed loop
var _knock := Vector2.ZERO
var _pending: Dictionary = {}
var _quick_hold: Dictionary = {}
var _reviving_peer := 0
var input_blocked := false
var auto_aim := Vector2.INF  ## test harness override for the aim point
var _cc_wander := Vector2.ZERO
var _cc_wander_left := 0.0
var _moved_acc := 0.0  ## host: distance moved since the last on_move proc
var history: Array = []  ## host: [{pos, hp, t}] every 0.25 s for the last 5 s (Temporal Singularity)
var _history_left := 0.0
var _last_host_pos := Vector2.ZERO


func setup(data: Dictionary) -> void:
	peer_id = int(data.peer)
	name = str(peer_id)
	position = data.pos
	net_pos = position
	class_id = data.class_id
	gender = CharacterSprite.valid_gender(str(data.get("gender", "")))
	class_def = GameData.classes[class_id]
	display_name = data.name
	level = int(data.get("level", 1))
	team = Team.PLAYERS
	radius = 8.0
	skills = default_loadout()
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16 | 32 | 64 | 128
	NetSync.make(self, "StateSync", [
		"Health:hp", "Health:max_hp", "Health:absorb", "Resource:value", "Resource:max_value", "Resource:kind",
		"Status:shown", "Stats:final", ".:life_state", ".:downed_left", ".:revive_progress", ".:level",
		".:xp", ".:talent_points", ".:talents", ".:appearance", ".:torch_sync",
		".:stat_points", ".:allocated", ".:run_mods", ".:gold", ".:skills", ".:legacy_kit", ".:held_by",
		".:held_anim",
	], [], 0.1)
	# The owner streams its dash state with its position (#17): the host and other clients don't
	# simulate the owner's dodge / forced dash, so they draw "dash" from this.
	var owner_sync := NetSync.make(self, "OwnerSync", [], [".:net_pos", ".:facing", ".:aim_pos", ".:dash_sync"], 0.05)
	owner_sync.set_multiplayer_authority(peer_id)


func _ready() -> void:
	super._ready()
	add_to_group("players")
	if multiplayer.is_server():
		_host_init()
	_apply_appearance()
	_build_carried_torch()
	if is_local():
		EventBus.local_player_spawned.emit(self)


func is_local() -> bool:
	return is_inside_tree() and peer_id == multiplayer.get_unique_id()


func is_targetable() -> bool:
	return life_state == Life.ALIVE and super.is_targetable()


func is_invulnerable() -> bool:
	return iframe_left > 0.0


func base_anim(moving: bool) -> String:
	match life_state:
		Life.DOWNED:
			return "death" if _fall_left > 0.0 else "downed"
		Life.GHOST:
			return "ghost"
	if _dodge_left > 0.0 or _forced_left > 0.0 or (dash_sync and not is_local()):
		return "dash"
	return "walk" if moving else "idle"


# =========================================================================================
# Host: initialization, stats, persistence
# =========================================================================================


func _host_init() -> void:
	var ch: Dictionary = GameState.characters.get(peer_id, GameState.new_character(display_name, class_id))
	legacy_kit = not ch.has("kit")
	level = int(ch.get("level", 1))
	xp = int(ch.get("xp", 0))
	talents = ch.get("talents", {}).duplicate()
	inv.load_dict({"equipment": ch.get("equipment", {}), "backpack": ch.get("backpack", []),
		"capacity": ch.get("backpack_capacity", 12), "quick": ch.get("quick", {"q": "", "e": ""})})
	# Talent trees v2: ranks of nodes that no longer exist are refunded.
	var t2 := {}
	for k in talents:
		var nd := talent_node(str(k))
		if not nd.is_empty() and not is_free_node(nd):
			t2[k] = mini(int(talents[k]), int(nd.get("max_rank", 1)))
	talents = t2
	allocated = ch.get("allocated", {}).duplicate()
	run_mods = ch.get("run_mods", []).duplicate(true)
	gold = int(ch.get("gold", 0))
	bonus_stat_points = int(ch.get("bonus_stat_points", 0))
	bonus_talent_points = int(ch.get("bonus_talent_points", 0))
	stat_points = maxi(_stat_points_total() - _stat_points_spent(), 0)
	talent_points = _talent_points_total() - _talent_points_spent()
	if talent_points < 0:
		talents = {}
		talent_points = _talent_points_total()
	var lo: Array = ch.get("loadout", [])
	skills = lo if loadout_error(lo).is_empty() else default_loadout()
	resource.setup(class_def.resource, 0.0, true)
	recompute_stats()
	health.hp = health.max_hp
	if resource.kind == "mana":
		resource.value = resource.max_value
	appearance = inv.appearance()
	_send_inventory.call_deferred()


func recompute_stats() -> void:
	stats.compute_player(class_def, level, inv.equipment, talents, status.stat_mods(), stat_extra())
	static_procs = _compile_procs()
	health.set_max(stats.get_stat("max_hp"))
	resource.set_max(stats.get_stat("max_resource"))
	resource.regen_per_second = stats.get_stat("resource_regen")


## Extra stat sources for Stats.compute_player (allocated points, run modifiers, passives).
func stat_extra() -> Dictionary:
	var mods: Array = []
	var smods: Array = []
	for sid in unlocked_skills():
		var sk: Dictionary = GameData.skills.get(sid, {})
		if sk.get("passive", false):
			for m in sk.get("mods", []):
				(smods if m.has("skill") else mods).append(m)
	return {"allocated": allocated, "run_mods": run_mods, "mods": mods, "skill_mods": smods}


# --- Talents v2 (D1): 3 branches x tiers 0-5; skill nodes unlock skills -------------------


func talent_tree() -> Dictionary:
	return GameData.talents.get(class_id, {})


func talent_node(id: String) -> Dictionary:
	for n in talent_tree().get("nodes", []):
		if n.id == id:
			return n
	return {}


## Points spent in a branch (free nodes don't count).
func branch_points(branch: String) -> int:
	var n := 0
	for nd in talent_tree().get("nodes", []):
		if nd.get("branch", "") == branch and not is_free_node(nd):
			n += int(talents.get(nd.id, 0))
	return n


## Starter nodes (the primary attack and the one basic skill) are free; heroes saved before the
## simple start also keep the old tier-0 starters (`legacy_starter`) for free.
func is_free_node(nd: Dictionary) -> bool:
	return nd.get("starter", false) or (legacy_kit and nd.get("legacy_starter", false))


func node_rank(nd: Dictionary) -> int:
	return 1 if is_free_node(nd) else int(talents.get(nd.id, 0))


## Skills this hero may slot / that work as passives: the class's primary attack (always known,
## #9), starters + learned skill nodes.
func unlocked_skills() -> Array:
	var out: Array = [str(class_def.get("primary_attack", ""))]
	for nd in talent_tree().get("nodes", []):
		if nd.get("type", "") == "skill" and node_rank(nd) > 0 and not out.has(str(nd.skill)):
			out.append(str(nd.skill))
	return out


## The primary attack, the class's starting skills (data `skills`), then empty slots.
func default_loadout() -> Array:
	var out: Array = [class_def.primary_attack]
	out.append_array(class_def.skills)
	while out.size() < SLOT_ACTIONS.size():
		out.append("")
	return out.slice(0, SLOT_ACTIONS.size())


## "" when `lo` is a valid loadout: a primary_ok skill first, then distinct unlocked active
## skills or empty slots ("").
func loadout_error(lo: Array) -> String:
	if lo.size() != SLOT_ACTIONS.size():
		return "A loadout has %d slots" % SLOT_ACTIONS.size()
	var unlocked := unlocked_skills()
	var seen := {}
	for i in lo.size():
		var sid := str(lo[i])
		if sid.is_empty() and i > 0:
			continue
		var sk: Dictionary = GameData.skills.get(sid, {})
		if sk.is_empty() or not unlocked.has(sid):
			return "%s is not unlocked" % sk.get("name", sid)
		if sk.get("passive", false):
			return "%s is passive" % sk.name
		if seen.has(sid):
			return "%s is slotted twice" % sk.name
		seen[sid] = true
		if i == 0 and not sk.get("primary_ok", false):
			return "%s can't be the primary attack" % sk.name
	return ""


func in_combat() -> bool:
	return resource.since_combat() < float(GameData.bal("stats.out_of_combat_delay", 5.0))


func _stat_points_total() -> int:
	return (level - 1) * int(GameData.bal("progression.stat_points_per_level", 5)) + bonus_stat_points


func _stat_points_spent() -> int:
	var n := 0
	for k in allocated:
		n += int(allocated[k])
	return n


## Host: a run-permanent modifier (tithe, contract, pact cost, tome) for the rest of the run.
func host_add_run_mod(stat: String, value: float, source: String) -> void:
	var m := run_mods.duplicate(true)
	m.append({"stat": stat, "value": value, "source": source})
	run_mods = m
	on_stats_dirty()
	persist()


func host_add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	GameState.characters[peer_id] = to_character()


## Procs from talents (keystones), unlocked passive skills and equipped items. Each gets a
## stable key for its internal cooldown.
func _compile_procs() -> Array:
	var out: Array = []
	var tree: Dictionary = GameData.talents.get(class_id, {})
	for node in tree.get("nodes", []):
		if int(talents.get(node.id, 0)) <= 0:
			continue
		for i in node.get("procs", []).size():
			out.append(node.procs[i].merged({"_key": "t:%s:%d" % [node.id, i], "source": node.id}, true))
	for sid in unlocked_skills():
		var sk: Dictionary = GameData.skills.get(sid, {})
		if sk.has("procs"):  # passives, and the trigger windows of actives (Overpower, Victory Rush)
			for i in sk.get("procs", []).size():
				out.append(sk.procs[i].merged({"_key": "s:%s:%d" % [sid, i], "source": sid}, true))
	for slot in inv.equipment:
		var item: Dictionary = inv.equipment[slot]
		for i in item.get("procs", []).size():
			out.append(item.procs[i].merged({"_key": "i:%s:%d" % [slot, i], "source": str(item.get("base", ""))}, true))
	return out


func creature_type() -> String:
	return "humanoid"


func to_character() -> Dictionary:
	var d := inv.to_dict()
	var out := {"name": display_name, "class_id": class_id, "gender": gender, "level": level, "xp": xp, "talents": talents.duplicate(), "loadout": skills.duplicate(),
		"equipment": d.equipment, "backpack": d.backpack, "backpack_capacity": d.capacity, "quick": d.quick,
		"allocated": allocated.duplicate(), "run_mods": run_mods.duplicate(true), "gold": gold,
		"bonus_stat_points": bonus_stat_points, "bonus_talent_points": bonus_talent_points}
	if not legacy_kit:
		out.kit = GameState.KIT_VERSION
	return out


## Host: store the authoritative character in the saved game.
func persist() -> void:
	if not multiplayer.is_server():
		return
	GameState.characters[peer_id] = to_character()
	GameState.save_game()


func _talent_points_total() -> int:
	return (level - 1) * int(GameData.bal("progression.talent_points_per_level")) + bonus_talent_points


func _talent_points_spent() -> int:
	var n := 0
	for k in talents:
		n += int(talents[k])
	return n


# =========================================================================================
# Per-frame
# =========================================================================================


func _physics_process(delta: float) -> void:
	if is_local():
		_owner_tick(delta)
	elif multiplayer.is_server():
		_host_follow(delta)
	else:
		follow_net_pos(delta)
	if multiplayer.is_server():
		_host_life_tick(delta)
		host_tick(delta)
		iframe_left = maxf(iframe_left - delta, 0.0)
		_dodge_cd_host = maxf(_dodge_cd_host - delta, 0.0)
		_history_left -= delta
		if _history_left <= 0.0:
			_history_left = 0.25
			history.append({"pos": position, "hp": health.hp, "t": Time.get_ticks_msec() / 1000.0})
			if history.size() > 21:
				history.pop_front()
		# Standing still (Greaves of the Iron Colossus, Wasteland Marksman Hauberk).
		still_time = still_time + delta if position.distance_to(_last_host_pos) < 0.5 else 0.0
		_moved_acc += position.distance_to(_last_host_pos)
		_last_host_pos = position
		if _moved_acc >= float(GameData.bal("combat.on_move_step", 24.0)) and life_state == Life.ALIVE:
			_moved_acc = 0.0
			Combat.instance.fire(self, "on_move", {"target": null})
		for k in _item_cd_host.keys():
			_item_cd_host[k] -= delta
		_host_torch_tick(delta)


func _process(delta: float) -> void:
	# Derived from the replicated life state, so every peer shows the fall (#17).
	if life_state != _seen_life:
		_fall_left = sprite.anim_length("death") if sprite and life_state == Life.DOWNED and _seen_life == Life.ALIVE else 0.0
		_seen_life = life_state
	_fall_left -= delta
	update_visuals(delta)
	_update_carried_torch(delta)
	if sprite:
		sprite.visible = life_state != Life.GHOST or is_local()
		if life_state == Life.GHOST:
			sprite.modulate.a = 0.45
	for k in local_cd.keys():
		local_cd[k][0] -= delta
		if local_cd[k][0] <= 0.0:
			local_cd.erase(k)
	for k in _pending.keys():
		_pending[k] -= delta
		if _pending[k] <= 0.0:
			_pending.erase(k)
	item_cd_left = maxf(item_cd_left - delta, 0.0)


## The boss holding this hero, or null.
func holder() -> Node2D:
	return get_node_or_null(held_by) as Node2D if not held_by.is_empty() else null


## Host: remote players' positions follow what the owner streams, limited to plausible speed.
func _host_follow(delta: float) -> void:
	_move_allowance = maxf(_move_allowance - delta, 0.0)
	var h := holder()
	if h:
		position = h.global_position
		return
	var limit := move_speed() * float(GameData.bal("player.movement_tolerance")) * delta + 2.0
	if _move_allowance > 0.0 or life_state == Life.GHOST:
		limit = 2000.0 * delta + 40.0
	if life_state == Life.DOWNED:
		limit = 0.0
	position = position.move_toward(net_pos, limit)


# =========================================================================================
# Owner: input -> local movement + intents
# =========================================================================================


func _owner_tick(delta: float) -> void:
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	var blocked := input_blocked or get_tree().paused
	var dir := Vector2.ZERO if blocked else InputSettings.move_vector()
	_update_aim(dir)
	if life_state != Life.ALIVE:
		velocity = Vector2.ZERO
		_dodge_left = 0.0
		dash_sync = false
		if life_state == Life.GHOST:
			net_pos = position
		return
	var h := holder()
	if h:
		# Held by a boss: carried along, no input (the host pins the hero too).
		position = h.global_position
		net_pos = position
		velocity = Vector2.ZERO
		_dodge_left = 0.0
		dash_sync = false
		_release_quick_holds()
		return
	var speed := move_speed()
	dir = _cc_move(dir, delta)
	if _forced_left > 0.0:
		_forced_left -= delta
		velocity = _forced_vel
	elif _dodge_left > 0.0:
		_dodge_left -= delta
		velocity = _dodge_dir * float(GameData.bal("player.dodge_distance")) / float(GameData.bal("player.dodge_duration"))
	else:
		velocity = dir * speed
	velocity += _knock
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	net_pos = position
	dash_sync = _dodge_left > 0.0 or _forced_left > 0.0
	if blocked:
		_release_quick_holds()
		return
	# Dodge
	if Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0 and speed > 0.0 and not status.has_flag("no_dash"):
		_dodge_dir = dir if dir != Vector2.ZERO else facing
		_dodge_left = float(GameData.bal("player.dodge_duration"))
		_dodge_cd = float(GameData.bal("player.dodge_cooldown"))
		request_dodge.rpc_id(1, _dodge_dir)
	# Attack + skills (holding repeats as soon as the cooldown allows). Channelled and
	# charge-up skills also report the release.
	for slot in SLOT_ACTIONS.size():
		if Input.is_action_pressed(SLOT_ACTIONS[slot]) and not local_cd.has(slot) and not _pending.has(slot) \
				and slot < skills.size() and not str(skills[slot]).is_empty():
			_pending[slot] = 0.3
			request_skill.rpc_id(1, slot, aim_pos)
		if Input.is_action_just_released(SLOT_ACTIONS[slot]) and slot < skills.size() and _is_hold_skill(str(skills[slot])):
			request_skill_release.rpc_id(1, slot, aim_pos)
	_handle_quick_slots(delta)
	_handle_interact()


func _is_hold_skill(sid: String) -> bool:
	var sk: Dictionary = GameData.skills.get(sid, {})
	return sk.has("channel") or sk.has("charge_time")


## Owner: crowd control that takes the controls away (D25, D33). Fear runs from the nearest
## monster, disorient wanders, inverted controls flip the stick / keys.
func _cc_move(dir: Vector2, delta: float) -> Vector2:
	if status.has_flag("feared"):
		var game := get_tree().get_first_node_in_group("game")
		var away := Vector2.ZERO
		if game:
			var best := INF
			for e in game.enemies_root.get_children():
				var d: float = e.global_position.distance_to(global_position)
				if e.team != team and d < best:
					best = d
					away = global_position - e.global_position
		return away.normalized() if away != Vector2.ZERO else facing
	if status.has_flag("disoriented"):
		_cc_wander_left -= delta
		if _cc_wander_left <= 0.0:
			_cc_wander_left = randf_range(0.4, 0.9)
			_cc_wander = Vector2.from_angle(randf() * TAU)
		return _cc_wander * 0.6
	if status.has_flag("invert_move"):
		return -dir
	return dir


func _update_aim(move_dir: Vector2) -> void:
	if auto_aim != Vector2.INF:
		aim_pos = auto_aim
		facing = (aim_pos - global_position).normalized() if aim_pos != global_position else facing
	elif InputSettings.using_gamepad:
		var stick := InputSettings.stick_aim()
		if stick != Vector2.ZERO:
			facing = stick.normalized()
		elif move_dir != Vector2.ZERO:
			facing = move_dir.normalized()
		aim_pos = global_position + facing * float(GameData.bal("player.gamepad_aim_distance"))
	else:
		aim_pos = get_global_mouse_position()
		var d := aim_pos - global_position
		if d.length() > 4.0:
			facing = d.normalized()


func _handle_quick_slots(delta: float) -> void:
	for slot in ["q", "e"]:
		var action: String = "quick_" + slot
		if Input.is_action_just_pressed(action):
			_quick_hold[slot] = 0.0
		elif Input.is_action_pressed(action) and _quick_hold.has(slot):
			var before: float = _quick_hold[slot]
			_quick_hold[slot] = before + delta
			if before < InputSettings.hold_threshold and _quick_hold[slot] >= InputSettings.hold_threshold:
				var hud := get_tree().get_first_node_in_group("hud")
				if hud:
					hud.open_radial(slot)
		elif Input.is_action_just_released(action) and _quick_hold.has(slot):
			var held: float = _quick_hold[slot]
			_quick_hold.erase(slot)
			var hud2 := get_tree().get_first_node_in_group("hud")
			if held < InputSettings.hold_threshold:
				request_use_quick.rpc_id(1, slot)
			elif hud2:
				var picked: String = hud2.close_radial()
				if not picked.is_empty():
					request_assign_quick.rpc_id(1, slot, picked)


func _release_quick_holds() -> void:
	if _quick_hold.is_empty():
		return
	_quick_hold.clear()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.close_radial()


func _handle_interact() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var target: Dictionary = game.find_interactable(self)
	EventBus.interact_prompt.emit(target.get("text", ""))
	if target.get("kind", "") == "revive":
		var tp: int = target.node.peer_id
		if Input.is_action_pressed("interact"):
			if _reviving_peer != tp:
				_reviving_peer = tp
				request_revive.rpc_id(1, tp, true)
		elif _reviving_peer != 0:
			request_revive.rpc_id(1, _reviving_peer, false)
			_reviving_peer = 0
	else:
		if _reviving_peer != 0:
			request_revive.rpc_id(1, _reviving_peer, false)
			_reviving_peer = 0
		if Input.is_action_just_pressed("interact") and not target.is_empty():
			request_interact.rpc_id(1, target.node.get_path())


# =========================================================================================
# Intents: owner -> host (all reliable). The host checks the sender owns this player.
# =========================================================================================


func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id


@rpc("any_peer", "call_local", "reliable")
func request_skill(slot: int, aim: Vector2) -> void:
	if not _from_owner() or slot < 0 or slot >= skills.size() or str(skills[slot]).is_empty():
		return
	if life_state != Life.ALIVE:
		_skill_result.rpc_id(peer_id, slot, 0.0, false, "")
		return
	aim_pos = aim
	var sid: String = skills[slot]
	var err := Combat.instance.try_use_skill(self, sid, aim, {"primary": slot == 0})
	# Cooldown races and casting are normal while holding a key; don't nag about them.
	var quiet := err in ["Not ready", "Busy"] or slot == 0
	_skill_result.rpc_id(peer_id, slot, cooldown_left(sid), err.is_empty(), "" if quiet else err)


## Owner -> host (reliable): the button of a channelled / charge-up skill was released.
@rpc("any_peer", "call_local", "reliable")
func request_skill_release(slot: int, aim: Vector2) -> void:
	if not _from_owner() or slot < 0 or slot >= skills.size() or str(skills[slot]).is_empty():
		return
	aim_pos = aim
	var sid := str(skills[slot])
	if str(charging.get("skill", "")) == sid:
		Combat.instance.release_charge(self, aim)
	elif str(channel.get("skill", "")) == sid:
		Combat.instance.stop_channel(self)


## Host: a cooldown changed outside a cast (resets, procs); tell the owner's HUD.
func sync_cooldown(sid: String) -> void:
	var slot := skills.find(sid)
	if slot >= 0:
		_skill_result.rpc_id(peer_id, slot, cooldown_left(sid), cooldown_left(sid) > 0.0, "")


## Host: the dodge roll is ready again at once (Predator's Breeches).
func host_reset_dodge() -> void:
	_dodge_cd_host = 0.0
	_owner_reset_dodge.rpc_id(peer_id)


@rpc("authority", "call_local", "reliable")
func _owner_reset_dodge() -> void:
	_dodge_cd = 0.0


@rpc("any_peer", "call_local", "reliable")
func request_dodge(dir: Vector2) -> void:
	if not _from_owner() or life_state != Life.ALIVE or _dodge_cd_host > 0.1 or move_speed() <= 0.0 or status.has_flag("no_dash"):
		return
	_dodge_cd_host = float(GameData.bal("player.dodge_cooldown"))
	iframe_left = maxf(iframe_left, float(GameData.bal("player.dodge_iframes")))
	_move_allowance = float(GameData.bal("player.dodge_duration")) + 0.25
	Combat.instance.fx.sound.rpc("dash", global_position)
	Combat.instance.fire(self, "on_dodge_roll", {"target": null, "dir": dir})


@rpc("any_peer", "call_local", "reliable")
func request_interact(target_path: NodePath) -> void:
	if not _from_owner() or life_state != Life.ALIVE:
		return
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.host_interact(self, get_node_or_null(target_path))


@rpc("any_peer", "call_local", "reliable")
func request_revive(target_peer: int, active: bool) -> void:
	if not _from_owner():
		return
	var game := get_tree().get_first_node_in_group("game")
	var target: Player = game.player_by_peer(target_peer) if game else null
	if target == null:
		return
	if active and life_state == Life.ALIVE and target.life_state == Life.DOWNED:
		target._reviver = self
		_revive_target = target
	elif not active and target._reviver == self:
		target._reviver = null
		target.revive_progress = 0.0
		_revive_target = null


@rpc("any_peer", "call_local", "reliable")
func request_use_quick(slot: String) -> void:
	if not _from_owner() or life_state != Life.ALIVE:
		return
	var base_id: String = inv.quick.get(slot, "")
	if base_id.is_empty():
		_notify.rpc_id(peer_id, "No item assigned to %s", [slot.to_upper()])
		return
	_use_consumable(base_id)


@rpc("any_peer", "call_local", "reliable")
func request_assign_quick(slot: String, base_id: String) -> void:
	if not _from_owner() or not slot in ["q", "e"]:
		return
	if base_id == "__clear__":
		base_id = ""
	if not base_id.is_empty() and not GameData.consumables.has(base_id):
		return
	for k in inv.quick:
		if inv.quick[k] == base_id:
			inv.quick[k] = ""
	inv.quick[slot] = base_id
	_inventory_changed()


@rpc("any_peer", "call_local", "reliable")
func request_equip(index: int) -> void:
	if not _from_owner():
		return
	_report(inv.equip_from_backpack(index, level), "equip")


@rpc("any_peer", "call_local", "reliable")
func request_unequip(slot: String) -> void:
	if not _from_owner():
		return
	_report(inv.unequip(slot), "equip")


@rpc("any_peer", "call_local", "reliable")
func request_drop(from_backpack: bool, key: String) -> void:
	if not _from_owner() or life_state == Life.GHOST:
		return
	var item := inv.take_backpack(int(key)) if from_backpack else inv.take_equipped(key)
	if item.is_empty():
		return
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.loot.drop_item(item, global_position + facing * 18.0)
	_inventory_changed()


@rpc("any_peer", "call_local", "reliable")
func request_learn_talent(node_id: String) -> void:
	if not _from_owner():
		return
	var nd := talent_node(node_id)
	if nd.is_empty() or is_free_node(nd):
		return
	var rank := int(talents.get(node_id, 0))
	if rank >= int(nd.get("max_rank", 1)):
		return
	if talent_points <= 0:
		_notify.rpc_id(peer_id, "No talent points left")
		return
	var need := int(nd.get("tier", 0)) * int(talent_tree().get("tier_points", 2))
	if branch_points(str(nd.branch)) < need:
		_notify.rpc_id(peer_id, "Spend %d points in this branch first", [need])
		return
	for req in nd.get("requires", []):
		if node_rank(talent_node(str(req))) <= 0:
			_notify.rpc_id(peer_id, "Requires another talent first")
			return
	var t := talents.duplicate()
	t[node_id] = rank + 1
	talents = t
	talent_points -= 1
	if nd.get("type", "") == "skill":
		_notify.rpc_id(peer_id, "Learned %s - slot it in the Skill Book", [GameData.skills.get(str(nd.skill), {}).get("name", nd.skill)])
	on_stats_dirty()
	persist()


@rpc("any_peer", "call_local", "reliable")
func request_reset_talents() -> void:
	if not _from_owner():
		return
	talents = {}
	talent_points = _talent_points_total()
	# Skills that are no longer unlocked leave the bar for the default kit.
	if not loadout_error(skills).is_empty():
		skills = default_loadout()
	on_stats_dirty()
	persist()


## Owner -> host (reliable): read the book in a backpack slot (D19). Tomes are consumed and give
## the reader their bonus for the rest of the run; the legendary tome gives a talent point and
## five stat points. The reader opens only on the reader's screen.
@rpc("any_peer", "call_local", "reliable")
func request_read_book(index: int) -> void:
	if not _from_owner() or index < 0 or index >= inv.backpack.size():
		return
	var item: Dictionary = inv.backpack[index]
	if item.get("kind", "") != "book":
		return
	var book: Dictionary = GameData.lore_books.get(str(item.get("book", "")), {})
	if book.is_empty():
		return
	var note := ""
	var eff: Dictionary = book.get("effect", {})
	match str(book.classification):
		"tome":
			for m in eff.get("mods", []):
				host_add_run_mod(str(m.stat), float(m.value), str(book.title))
			note = "tome"
			inv.take_backpack(index)
		"legendary":
			var tp := int(eff.get("talent_points", 0))
			var sp := int(eff.get("stat_points", 0))
			bonus_talent_points += tp
			bonus_stat_points += sp
			talent_points += tp
			stat_points += sp
			note = "legendary"
			inv.take_backpack(index)
	_inventory_changed()
	persist()
	_open_book.rpc_id(peer_id, str(book.id), note)


## `kind` is "tome" / "legendary" when reading used the book up: the note under the text says
## what it gave, in the reader's language (#32).
@rpc("authority", "call_local", "reliable")
func _open_book(book_id: String, kind: String) -> void:
	Codex.mark_read(book_id)
	AudioManager.play_sfx("book_open", 0.0)
	var book: Dictionary = GameData.lore_books.get(book_id, {})
	var note := ""
	match kind:
		"tome":
			note = Loc.f("You learned: %s", [Loc.t(str(book.get("effect_text", ""))).replace(Loc.t(" (Permanent)"), Loc.t(" for this run"))])
		"legendary":
			var eff: Dictionary = book.get("effect", {})
			note = Loc.f("+%d talent point and +%d stat points", [int(eff.get("talent_points", 0)), int(eff.get("stat_points", 0))])
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_book"):
		hud.open_book(book_id, note)


## Owner -> host (reliable): new Skill Book loadout. Out of combat only (D1).
@rpc("any_peer", "call_local", "reliable")
func request_loadout(slots: Array) -> void:
	if not _from_owner():
		return
	if in_combat():
		_notify.rpc_id(peer_id, "Can't change skills in combat")
		return
	var err := loadout_error(slots)
	if not err.is_empty():
		_notify.rpc_id(peer_id, err)
		return
	skills = slots.duplicate()
	cooldowns.clear()
	persist()


## Owner -> host (reliable): spend `count` free stat points on a primary stat (D5, no respec).
@rpc("any_peer", "call_local", "reliable")
func request_spend_stat(stat: String, count: int) -> void:
	if not _from_owner() or not stat in Stats.PRIMARY or count <= 0:
		return
	count = mini(count, stat_points)
	if count <= 0:
		_notify.rpc_id(peer_id, "No stat points left")
		return
	var a := allocated.duplicate()
	a[stat] = int(a.get(stat, 0)) + count
	allocated = a
	stat_points -= count
	on_stats_dirty()
	persist()


# =========================================================================================
# Host -> owner (reliable)
# =========================================================================================


@rpc("authority", "call_local", "reliable")
func _skill_result(slot: int, cd: float, ok: bool, msg: String) -> void:
	if ok:
		_pending.erase(slot)
		local_cd[slot] = [cd, cd]
		EventBus.local_cooldown_started.emit(slot, cd)
	else:
		_pending[slot] = 0.25  # don't spam requests while a held key keeps failing
		if cd > 0.0:
			var total := float(local_cd[slot][1]) if local_cd.has(slot) else cd
			local_cd[slot] = [cd, maxf(total, cd)]
	if not msg.is_empty():
		EventBus.hud_message.emit(Loc.t(msg), Color(1, 0.6, 0.5))


@rpc("authority", "call_local", "reliable")
func _notify(text: String, args: Array = []) -> void:
	EventBus.hud_message.emit(Loc.f(text, args), Color(1, 0.85, 0.5))


@rpc("authority", "call_local", "reliable")
func _receive_inventory(data: Dictionary) -> void:
	if multiplayer.is_server() and is_local():
		EventBus.local_inventory_changed.emit()
		return
	inv.load_dict(data)
	EventBus.local_inventory_changed.emit()


@rpc("authority", "call_local", "reliable")
func _owner_teleport(pos: Vector2) -> void:
	position = pos
	net_pos = pos
	velocity = Vector2.ZERO
	_dodge_left = 0.0
	_forced_left = 0.0


@rpc("authority", "call_local", "reliable")
func _owner_dash(dest: Vector2, duration: float) -> void:
	var d := dest - position
	_forced_left = maxf(duration, 0.05)
	_forced_vel = d / _forced_left


@rpc("authority", "call_local", "reliable")
func _owner_knockback(push: Vector2) -> void:
	_knock += push


@rpc("authority", "call_local", "reliable")
func _item_used(cd: float) -> void:
	item_cd_left = cd
	item_cd_total = cd


# =========================================================================================
# Host-side game logic
# =========================================================================================


func host_teleport(pos: Vector2) -> void:
	position = pos
	net_pos = pos
	_move_allowance = 0.6
	_owner_teleport.rpc_id(peer_id, pos)


func host_dash(dest: Vector2, duration: float) -> void:
	iframe_left = maxf(iframe_left, duration * float(GameData.bal("player.dash_iframe_ratio")))
	_move_allowance = duration + 0.4
	_owner_dash.rpc_id(peer_id, dest, duration)


func host_knockback(push: Vector2) -> void:
	_move_allowance = 0.4
	_owner_knockback.rpc_id(peer_id, push)


func _report(err: String, sfx: String) -> void:
	if err.is_empty():
		_inventory_changed()
		Combat.instance.fx.sound.rpc(sfx, global_position)
	else:
		_notify.rpc_id(peer_id, err, inv.error_args)
		inv.error_args = []


func _inventory_changed() -> void:
	on_stats_dirty()
	appearance = inv.appearance()
	_send_inventory()
	GameState.characters[peer_id] = to_character()


func _send_inventory() -> void:
	if multiplayer.is_server():
		_receive_inventory.rpc_id(peer_id, inv.to_dict())


## Host: tries to put a picked-up item into the backpack. Returns "" or an error.
func host_give_item(item: Dictionary) -> String:
	if item.get("kind") == "backpack":
		if int(item.capacity) <= inv.capacity:
			return "You already have a backpack this big"
		inv.capacity = int(item.capacity)
		_inventory_changed()
		_notify.rpc_id(peer_id, "Backpack upgraded to %d slots", [inv.capacity])
		return ""
	if not inv.can_add(item):
		return "Backpack is full"
	var err := inv.add(item)
	if err.is_empty():
		_inventory_changed()
	return err


func _use_consumable(base_id: String) -> void:
	var def: Dictionary = GameData.consumables.get(base_id, {})
	if def.is_empty() or inv.count_of(base_id) <= 0:
		_notify.rpc_id(peer_id, "No %s left", [def.get("name", "items")])
		return
	if float(_item_cd_host.get("potion", 0.0)) > 0.0:
		_notify.rpc_id(peer_id, "Item not ready")
		return
	inv.consume(base_id)
	var cd := float(def.get("cooldown", 5.0))
	_item_cd_host["potion"] = cd
	_item_used.rpc_id(peer_id, cd)
	var ctx := Combat.instance.make_ctx(self, {"id": "", "school": "spell"})
	for e in def.effects:
		match str(e.type):
			"restore":
				if e.what == "hp":
					Combat.instance.heal(ctx, self, health.max_hp * float(e.fraction))
				else:
					resource.gain(resource.max_value * float(e.fraction))
			"status":
				var mag := health.max_hp * float(e.get("magnitude_fraction", 0.0))
				if e.get("level_scaled", false):
					mag = GameData.level_scale(level)
				status.apply(str(e.status), float(e.duration), mag, ctx)
			"torch":
				host_take_torch()
	# Drinking anything puts out burns that only a potion cures (Molten Blood).
	for st in status.effects.duplicate():
		if st.def.get("cured_by_potion", false):
			status.remove(st.id)
	Combat.instance.fx.sound.rpc(str(def.get("sfx", "potion")), global_position)
	_inventory_changed()


func add_xp(amount: int) -> void:
	var max_level := int(GameData.bal("progression.max_level"))
	if level >= max_level:
		return
	xp += amount
	var leveled := false
	while level < max_level and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		talent_points += int(GameData.bal("progression.talent_points_per_level"))
		stat_points += int(GameData.bal("progression.stat_points_per_level", 5))
		leveled = true
	if leveled:
		recompute_stats()
		health.hp = health.max_hp
		_level_up_fx.rpc(level)
		persist()


static func xp_to_next(lvl: int) -> int:
	return int(float(GameData.bal("progression.xp_base")) * pow(lvl, float(GameData.bal("progression.xp_exponent"))))


@rpc("authority", "call_local", "reliable")
func _level_up_fx(new_level: int) -> void:
	AudioManager.play_sfx_at("level_up", global_position)
	if is_local():
		EventBus.local_level_up.emit(new_level)
		EventBus.hud_message.emit(Loc.f("Level %d! +%d talent points, +%d stat points", [new_level, int(GameData.bal("progression.talent_points_per_level")), int(GameData.bal("progression.stat_points_per_level"))]), Color(1, 0.85, 0.3))


# --- Life state (downed / revive / ghost) ----------------------------------------------------


func on_death() -> void:
	if life_state != Life.ALIVE:
		return
	# Crosier of Eternal Dawn: once per floor a fallen ally rises at once at 50% HP and mana.
	var game := get_tree().get_first_node_in_group("game")
	if game and multiplayer.is_server():
		for pr in game.players_root.get_children():
			if pr != self and pr.is_alive() and pr.stats.has_flag("dawn_crosier") and not pr.has_meta("crosier_used"):
				pr.set_meta("crosier_used", true)
				health.hp = health.max_hp * 0.5
				resource.value = maxf(resource.value, resource.max_value * 0.5)
				Combat.instance.fx.ring.rpc(global_position, 50.0, "#fff6c0", "")
				Combat.instance.fx.number.rpc(global_position, "Eternal Dawn", "heal")
				return
	life_state = Life.DOWNED
	downed_left = float(GameData.bal("player.downed_time"))
	revive_progress = 0.0
	casting = {}
	impact_pending = {}
	status.clear_all()
	Combat.instance.fx.sound.rpc("death", global_position)
	died_signal.emit(self)


func _host_life_tick(delta: float) -> void:
	if _revive_target and (not is_instance_valid(_revive_target) or _revive_target._reviver != self):
		_revive_target = null
	if life_state != Life.DOWNED:
		return
	if _reviver and is_instance_valid(_reviver) and _reviver.life_state == Life.ALIVE \
			and _reviver.global_position.distance_to(global_position) <= float(GameData.bal("world.revive_range")) + 8.0:
		revive_progress += delta / float(GameData.bal("player.revive_channel"))
		if revive_progress >= 1.0:
			revive(float(GameData.bal("player.revive_hp_fraction")))
			Combat.instance.fx.sound.rpc("revive", global_position)
			Combat.instance.fx.number.rpc(global_position, "Revived!", "heal")
		return
	elif _reviver:
		_reviver = null
		revive_progress = 0.0
	downed_left -= delta
	if downed_left <= 0.0:
		life_state = Life.GHOST
		downed_left = 0.0
		collision_mask = 1
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.on_player_ghosted(self)


func revive(hp_fraction: float) -> void:
	life_state = Life.ALIVE
	downed_left = 0.0
	revive_progress = 0.0
	_reviver = null
	collision_mask = 1 | 4 | 8 | 16 | 32 | 64 | 128
	health.hp = maxf(1.0, health.max_hp * hp_fraction)
	iframe_left = float(GameData.bal("player.respawn_invuln"))


# --- Visual ------------------------------------------------------------------------------------


# --- Carried torch ---------------------------------------------------------------------------


## Host: the player took a wall torch; it burns for balance.lighting.carried_torch_duration.
func host_take_torch() -> void:
	torch_left = float(GameData.bal("lighting.carried_torch_duration"))
	torch_sync = ceili(torch_left)
	_notify.rpc_id(peer_id, "You take the torch")


func _host_torch_tick(delta: float) -> void:
	if torch_left <= 0.0:
		return
	torch_left = maxf(torch_left - delta, 0.0)
	var t := ceili(torch_left)
	if t != torch_sync:
		torch_sync = t
		if t == 0:
			_notify.rpc_id(peer_id, "Your torch burned out")


func _build_carried_torch() -> void:
	_torch_node = Node2D.new()
	_torch_node.name = "CarriedTorch"
	add_child(_torch_node)
	var s := Sprite2D.new()
	s.texture = GameData.texture("props.torch")
	s.position = Vector2(10, -24)
	s.scale = Vector2(0.75, 0.75)
	s.light_mask = LightLayers.SELF_LIT
	_torch_node.add_child(s)
	_torch_light = PointLight2D.new()
	LightLayers.setup_light(_torch_light)
	_torch_light.texture = GameData.texture("fx.light")
	_torch_light.color = Color(1.0, 0.62, 0.3)
	_torch_light.shadow_enabled = true
	_torch_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_torch_light.shadow_filter_smooth = 2.0
	# At the feet, like the personal light: never inside an occluder.
	LightLayers.register(_torch_light, float(GameData.bal("lighting.carried_torch_radius")))
	_torch_node.add_child(_torch_light)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = 5
	p.lifetime = 0.7
	p.position = Vector2(10, -32)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.scale_amount_max = 0.8
	p.color = Color(1.6, 0.8, 0.3)
	_torch_node.add_child(p)
	_torch_node.visible = false


## Every peer: show the torch and its light while it burns; it gutters in its last seconds.
func _update_carried_torch(delta: float) -> void:
	if _torch_node == null:
		return
	var burning := torch_sync > 0 and life_state != Life.GHOST
	_torch_node.visible = burning
	if not burning:
		return
	_torch_t += delta
	var energy := float(GameData.bal("lighting.carried_torch_energy"))
	var warn := float(GameData.bal("lighting.carried_torch_warning"))
	var flicker := sin(_torch_t * 9.0) * 0.06 + sin(_torch_t * 23.0) * 0.04
	if torch_sync <= warn:
		var k := float(torch_sync) / warn
		energy *= 0.35 + 0.65 * k
		flicker += sin(_torch_t * 31.0) * 0.2 * (1.0 - k)
	_torch_light.energy = maxf(0.1, energy + flicker)


func _apply_appearance() -> void:
	if sprite == null:
		return
	sprite.set_layer("body", CharacterSprite.body_key(gender))
	var keep := {"body": true}
	for layer in appearance:
		var a: Array = appearance[layer]
		sprite.set_look_layer(layer, a, gender)
		keep[layer] = true
	for layer in ["head", "chest", "legs", "boots", "gloves", "weapon", "offhand"]:
		if not keep.has(layer):
			sprite.set_layer(layer, "")
