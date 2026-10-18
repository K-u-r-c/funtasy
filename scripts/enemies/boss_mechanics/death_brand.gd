extends BossMechanic
## Vespera P1 - Black Anointing: a random player is branded; after `delay` s they explode for
## `damage`, multiplied by 1 + the number of allies standing within `radius` (spread out!).
## params: every, delay (5), radius (80), damage (dict)

var victim: Player = null
var _t := -1.0
var _pulse := 0.0


func trigger() -> void:
	var pool := living_players()
	if pool.is_empty() or _t >= 0.0:
		return
	victim = pool[randi() % pool.size()]
	_t = float(p("delay", 5.0))
	Combat.instance.apply_status(ctx(), victim, "death_brand", _t, 0.0)
	game().broadcast_message.rpc("%s bears the Black Anointing - spread out!", "#a020a0", [victim.display_name])


func physics(delta: float) -> void:
	super.physics(delta)
	if _t < 0.0:
		return
	_t -= delta
	if _t > 0.0:
		# The blast radius pulses around the branded hero so the party can spread out.
		_pulse -= delta
		if _pulse <= 0.0 and is_instance_valid(victim):
			_pulse = 0.5
			Combat.instance.fx.ring.rpc(victim.global_position, float(p("radius", 80)), "#a020a0", "")
		return
	_t = -1.0
	if not is_instance_valid(victim) or not victim.is_targetable():
		return
	var r := float(p("radius", 80))
	var near: Array = living_players().filter(func(pl): return pl != victim and pl.global_position.distance_to(victim.global_position) <= r)
	var c := ctx()
	c.damage_mult = float(c.damage_mult) * (1.0 + near.size())
	for pl in [victim] + near:
		Combat.instance.deal_damage(c, pl, Combat.instance.value_of_spec(p("damage", {"base": 10, "coef": 1.2}), c), {"damage_type": "shadow", "area": true})
	Combat.instance.fx.ring.rpc(victim.global_position, r, "#a020a0", "explosion")
	last_hit_count = near.size() + 1


var last_hit_count := 0


func test_check(_suite: RefCounted) -> String:
	return "" if last_hit_count > 0 else "brand not detonated"
