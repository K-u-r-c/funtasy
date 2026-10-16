extends MonsterBehavior
## Gutter Stalker: hidden (stealthed) until it strikes; its first hit from stealth is a critical
## backstab (stealth rule in Combat). After `rest` s out of combat contact it slips under again.
## params: status (submerged), rest (6)

var _calm := 0.0


func _ready() -> void:
	enemy.status.apply(str(p("status", "submerged")), -1.0, 0.0, Combat.instance.env_ctx(0.0))


func on_damaged(_attacker: Actor, _amount: float) -> void:
	enemy.status.remove(str(p("status", "submerged")))
	_calm = 0.0


func on_physics(delta: float) -> void:
	if enemy.status.has_flag("stealthed"):
		return
	_calm += delta
	var t: Actor = enemy.target
	if t and is_instance_valid(t) and t.global_position.distance_to(enemy.global_position) < 120.0:
		_calm = 0.0
	if _calm >= float(p("rest", 6.0)):
		_calm = 0.0
		enemy.status.apply(str(p("status", "submerged")), -1.0, 0.0, Combat.instance.env_ctx(0.0))
		Combat.instance.fx.sound.rpc("splash", enemy.global_position)


func test_check(_suite: RefCounted) -> String:
	return "" if enemy.status.has_flag("stealthed") or enemy.status.has(str(p("status", "submerged"))) else "not submerged"
