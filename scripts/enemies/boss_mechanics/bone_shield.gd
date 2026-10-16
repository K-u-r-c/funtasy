extends BossMechanic
## Morvath P2 - absorbs the bones of fallen skeletons (corpses within `radius`) into a shield of
## `base` x max HP (+ `per_corpse` each). params: base (0.25), per_corpse (0.03), radius (600)

var shield := 0.0


func _ready() -> void:
	var g := game()
	var bones: Array = g.corpses_near(boss.global_position, float(p("radius", 600.0)), {"bones": true})
	for c in bones:
		g.consume_corpse(int(c.id))
	shield = boss.health.max_hp * (float(p("base", 0.25)) + float(p("per_corpse", 0.03)) * bones.size())
	boss.health.absorb = maxf(boss.health.absorb, shield)
	boss.health.absorb_time = 9999.0
	Combat.instance.fx.ring.rpc(boss.global_position, 80.0, "#e8e0c8", "")
	g.broadcast_message.rpc("Morvath draws the bones of the fallen into a shield!", "#e8e0c8")


func test_trigger(_suite: RefCounted) -> void:
	pass


func test_check(_suite: RefCounted) -> String:
	return "" if shield >= boss.health.max_hp * 0.25 - 1.0 else "no shield"
