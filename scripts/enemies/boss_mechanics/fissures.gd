extends BossMechanic
## Ignis P2: every hammer strike cracks the floor - a permanent magma fissure (burning terrain)
## opens under the boss's target every `every` s. params: every (7), damage (dict)

var opened := 0


func trigger() -> void:
	var t: Actor = boss.target
	if t == null or not is_instance_valid(t):
		return
	var c := ctx()
	boss.play_action.rpc("attack", (t.global_position - boss.global_position).normalized())
	Combat.instance.run_effect({"type": "delayed", "delay": 0.8, "at": "self", "telegraph": {"radius": 26, "color": "#ff3300"},
		"effects": [{"type": "terrain", "kind": "fissure", "shape": "point", "at": "self", "lifetime": 9999, "blocks": "none",
			"zone": {"tick": 0.5, "damage": p("damage", {"base": 3, "coef": 0.5}), "damage_type": "fire", "color": "#ff3300"}}]}, c, t.global_position, t.global_position)
	opened += 1


func test_check(_suite: RefCounted) -> String:
	return "" if opened > 0 else "no fissure"
