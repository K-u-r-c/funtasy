class_name Actor
extends CharacterBody2D
## Base for players and enemies: owns the components (Stats, Health, ResourcePool,
## StatusEffects), the layered sprite, the replicated state and the host-side skill cooldowns.
## Gameplay outcomes (damage, statuses, cooldowns) are only ever decided on the host.

signal died_signal(actor: Actor)

enum Team { PLAYERS, MONSTERS }

var team: int = Team.PLAYERS
var display_name := ""
var radius := 8.0
var level := 1

var stats: Stats
var health: Health
var resource: ResourcePool
var status: StatusEffects
var sprite: CharacterSprite

## Replicated movement state.
var net_pos := Vector2.ZERO
var facing := Vector2.DOWN

var cooldowns: Dictionary = {}  ## host: skill id -> seconds left
var casting: Dictionary = {}  ## host: {skill, aim, left} while a cast time runs
var channel: Dictionary = {}  ## host: {skill, left, tick_left, aim, start} while channelling
var charging: Dictionary = {}  ## host: {skill, t, max, aim} while a charge-up skill is held
var skill_charges: Dictionary = {}  ## host: skill id -> stored charges (skills with "charges")
var lockout_element := ""  ## host: school locked by Counterspell
var last_attacker: Actor = null  ## host: who hit this actor last (kill credit for procs)
var last_attack_ctx: Dictionary = {}
var last_hit_area := false  ## host: the last hit came from an area attack (bone piles break)
var proc_cd: Dictionary = {}  ## host: proc key -> time it is ready again
var static_procs: Array = []  ## host: procs from talents, passives, items, elite modifiers
var _stats_dirty := true
var _action_anim := ""
var _action_left := 0.0
var _last_visual_pos := Vector2.ZERO
var _flash := 0.0
var _shadow: Sprite2D


func _init() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	stats = Stats.new()
	stats.name = "Stats"
	add_child(stats)
	health = Health.new()
	health.name = "Health"
	add_child(health)
	resource = ResourcePool.new()
	resource.name = "Resource"
	add_child(resource)
	status = StatusEffects.new()
	status.name = "Status"
	add_child(status)


func _ready() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = GameData.texture("fx.shadow")
	_shadow.z_index = -1
	_shadow.scale = Vector2.ONE * (radius / 9.0)
	add_child(_shadow)
	sprite = CharacterSprite.new()
	sprite.name = "Sprite"
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	net_pos = position
	_last_visual_pos = position
	health.died.connect(_on_health_died)


func is_alive() -> bool:
	return not health.is_dead()


## Can enemies/allies' skills affect and target this actor right now?
func is_targetable() -> bool:
	return is_alive() and not status.has_flag("untargetable")


## Can allies' heals and buffs reach this actor?
func is_targetable_by_allies() -> bool:
	return is_alive()


func is_invulnerable() -> bool:
	return false


func creature_type() -> String:
	return "humanoid"


## Behaviour hook (frontal shields, shells...): scales damage before mitigation.
func modify_damage_taken(amount: float, _data: Dictionary) -> float:
	return amount


## Full immunity to a damage type (monster data `immune`, statuses `immune_<type>`).
func immune_to(dtype: String) -> bool:
	return status.has_flag("immune_" + dtype)


## Resistance to a non-physical damage type: magic resist + per-type resistance.
func resist_to(dtype: String) -> float:
	return stats.get_stat("magic_resist") + stats.get_stat(dtype + "_resist")


## Every proc this actor has right now: static ones (recomputed with the stats) + statuses'.
func all_procs() -> Array:
	var st := status.procs()
	if st.is_empty():
		return static_procs
	return static_procs + st


func on_stats_dirty() -> void:
	_stats_dirty = true


func feet() -> Vector2:
	return global_position


func move_speed() -> float:
	if status.has_any_flag(["rooted", "stunned", "asleep", "shackled"]):
		return 0.0
	return stats.get_stat("move_speed", 100.0)


func can_act() -> bool:
	return is_alive() and not status.has_any_flag(CombatCore.NO_ACT_FLAGS)


# --- Host-side helpers -----------------------------------------------------------------------


func recompute_stats() -> void:
	pass  # overridden


func host_tick(delta: float) -> void:
	for k in cooldowns.keys():
		cooldowns[k] -= delta
		if cooldowns[k] <= 0.0:
			cooldowns.erase(k)
			_recharge(k)
	if _stats_dirty:
		_stats_dirty = false
		recompute_stats()
	if not casting.is_empty():
		if not can_act():
			casting = {}
		else:
			casting.left -= delta
			if casting.left <= 0.0:
				var c := casting
				casting = {}
				Combat.instance.finish_cast(self, c.skill, c.aim)


func cooldown_left(skill_id: String) -> float:
	return float(cooldowns.get(skill_id, 0.0))


## Skills with stored charges get one back when their cooldown ends, and recharge the next.
func _recharge(skill_id: String) -> void:
	if not skill_charges.has(skill_id):
		return
	var skill: Dictionary = GameData.skills.get(skill_id, {})
	var max_c := int(skill.get("charges", 1)) + int(stats.skill_mod(skill_id, "charges_add"))
	skill_charges[skill_id] = mini(int(skill_charges[skill_id]) + 1, max_c)
	if int(skill_charges[skill_id]) < max_c:
		cooldowns[skill_id] = stats.cooldown_for(skill) * maxf(0.1, 1.0 + stats.skill_mod(skill_id, "recharge_mult"))


func _on_health_died() -> void:
	if multiplayer.is_server():
		on_death()


func on_death() -> void:
	died_signal.emit(self)


# --- Visuals (every peer) ---------------------------------------------------------------------


## Host -> all (unreliable): one-shot animation such as attack/cast/hit.
@rpc("authority", "call_local", "unreliable")
func play_action(anim_name: String, dir: Vector2) -> void:
	if dir != Vector2.ZERO:
		facing = dir
	_action_anim = anim_name
	if sprite and sprite.anim_length(anim_name) > 0.0:
		_action_left = sprite.anim_length(anim_name)  # the art's own frames / fps
	else:
		var anim_def: Dictionary = GameData.assets.characters.anims.get(anim_name, {"frames": 4, "fps": 10})
		_action_left = float(anim_def.frames) / float(anim_def.fps)
	if anim_name == "hit":
		_flash = 0.12
	if sprite:
		sprite.play(anim_name, facing, true)


func base_anim(moving: bool) -> String:
	return "walk" if moving else "idle"


func update_visuals(delta: float) -> void:
	if sprite == null:
		return
	var moved := (position - _last_visual_pos).length()
	_last_visual_pos = position
	var moving := moved > 20.0 * delta
	_action_left -= delta
	var anim_name := base_anim(moving)
	if _action_left > 0.0 and anim_name in ["idle", "walk"]:
		anim_name = _action_anim
	sprite.play(anim_name, facing)
	_flash = maxf(_flash - delta, 0.0)
	var tint := Color.WHITE
	for s in status.shown:
		var def: Dictionary = GameData.status_effects.get(s[0], {})
		if def.get("debuff", false) and def.has("color"):
			tint = tint.lerp(Color.from_string(def.color, Color.WHITE), 0.35)
	var vis := status.visual()
	tint *= vis.tint
	tint.a = vis.alpha
	if _flash > 0.0:
		tint = Color(2.5, 2.5, 2.5)
	sprite.modulate = tint
	var sc := float(vis.scale) * visual_scale()
	sprite.scale = sprite.scale.lerp(Vector2(sc, sc), minf(1.0, delta * 8.0))
	# "lift": flying actors hover above their shadow (with a slow bob).
	var lift := float(vis.lift)
	var bob := sin(Time.get_ticks_msec() / 300.0) * 2.0 if lift > 0.0 else 0.0
	sprite.position.y = lerpf(sprite.position.y, -lift + bob, minf(1.0, delta * 6.0))


## Base sprite scale (elites and buffed monsters are drawn bigger).
func visual_scale() -> float:
	return 1.0


## Smoothly follows the replicated position on peers that don't simulate this actor.
func follow_net_pos(delta: float) -> void:
	var d := net_pos - position
	if d.length() > 160.0:
		position = net_pos
	else:
		position += d * minf(1.0, delta * 14.0)
