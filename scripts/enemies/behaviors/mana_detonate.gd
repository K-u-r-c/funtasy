extends MonsterBehavior
## Will-o'-the-Blight: drifts erratically; within `reach` px it blinds the hero and detonates their
## remaining Mana / Fury (the pool empties) as physical damage: `pool_damage` of the pool, at most
## `max_hp_share` of the hero's health (#100: it was the whole pool, which one-shot a hero with a
## full pool). params: reach (60), every (8), pool_damage (0.4), max_hp_share (0.3)

var _cd := 1.0
var _wobble := Vector2.ZERO
var _wt := 0.0
var detonated := 0


func move_override(delta: float) -> Vector2:
	var t: Actor = enemy.target
	if t == null or not is_instance_valid(t):
		return Vector2.INF
	_wt -= delta
	if _wt <= 0.0:
		_wt = randf_range(0.3, 0.7)
		_wobble = Vector2.from_angle(randf() * TAU) * 0.8
	return ((t.global_position - enemy.global_position).normalized() + _wobble).normalized()


func on_physics(delta: float) -> void:
	_cd -= delta
	var t: Actor = enemy.target
	if _cd > 0.0 or t == null or not is_instance_valid(t) or not (t is Player):
		return
	if t.global_position.distance_to(enemy.global_position) > float(p("reach", 60.0)):
		return
	_cd = float(p("every", 8.0))
	var ctx := Combat.instance.make_ctx(enemy, {"id": "mana_detonate", "school": "spell", "damage_type": "physical"})
	Combat.instance.apply_status(ctx, t, "blind", 2.5, 0.0)
	var pool: float = t.resource.value
	t.resource.gain(-pool)
	var dmg := detonation(pool, t.health.max_hp, params)
	if dmg > 0.0:
		Combat.instance.deal_damage(ctx, t, dmg, {"damage_type": "physical", "area": true})
	Combat.instance.fx.ring.rpc(t.global_position, 36.0, "#a0ff80", "explosion")
	detonated += 1


## The blast for a pool of `pool` on a hero of `max_hp` health, before armor.
static func detonation(pool: float, max_hp: float, prm: Dictionary) -> float:
	return minf(pool * float(prm.get("pool_damage", 0.4)), max_hp * float(prm.get("max_hp_share", 0.3)))


func test_trigger(suite: RefCounted) -> void:
	enemy.add_threat(suite.p, 50.0)
	suite.p.host_teleport(suite.g.nearest_floor(enemy.global_position + Vector2(20, 0)))
	_cd = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if detonated > 0 else "never detonated"
