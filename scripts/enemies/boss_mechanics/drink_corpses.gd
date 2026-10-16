extends BossMechanic
## Cernunnos P2: drives his antlers into the loam and drinks the blood of every corpse in the
## arena, healing `heal` of his maximum health (once when the phase starts, then every `every` s
## if there is blood to drink). params: every (30), heal (0.15), radius (700)

var drank := 0


func _ready() -> void:
	trigger()


func trigger() -> void:
	var g := game()
	var corpses: Array = g.corpses_near(boss.global_position, float(p("radius", 700.0)))
	for c in corpses:
		g.consume_corpse(int(c.id))
	var ctx := ctx()
	Combat.instance.heal(ctx, boss, boss.health.max_hp * float(p("heal", 0.15)))
	Combat.instance.fx.ring.rpc(boss.global_position, 90.0, "#a01010", "")
	g.broadcast_message.rpc("Cernunnos drinks the blood of the fallen!", "#c02020")
	drank += 1


func test_check(_suite: RefCounted) -> String:
	return "" if drank > 0 else "no drinking"
